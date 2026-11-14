# =============================================================================
# Role layer for dv_11 (QB_START): QB dynasty value
#   season t value = 17 x E[share of team games started] x E[(PPG in starts - replacement)+]
#                    - 17 x E[share of games played without starting] x (replacement - relief PPG) x P(season above the line)
#   floored at 0 per season, like the backtest target (relief appearances lower the season PPG).
# Training rows are week-9 snapshots (same design as dv_10 / the dv_11 backtest), seasons 2007 onward: features at the
# snapshot (share of team games started so far, depth rank for week 10 (2012+, "unknown" before), credible PPG in starts,
# age, draft pick, years in league); outcomes in season y + h, h = 1..5. One pooled model over h (with h interactions)
# for each of: share started, share relief, PPG in starts (direct, no feeding forward). sd of PPG in starts per h
# from the residuals. Fit only on outcome seasons <= last_y + 1 (same information as fit_future(last_y)).
# Uses snapshot(), qb_starts(), cred_s, KS, seasS (rl_dv10.R) and role_snapshot (rl_common.R).
# =============================================================================
tg_of <- function(y) ifelse(y >= 2021, 17L, 16L)
QSNAP <- local({
  s <- bind_rows(lapply(2007:2025, function(y) snapshot(y) %>% filter(pos == "QB") %>% mutate(season = y)))
  s <- qb_starts(s); s$cppg_s <- cred_s(s, KS[1], KS[2])
  r <- bind_rows(lapply(RL_FIRST:2025, function(y) role_snapshot(y, CUT) %>% mutate(season = y) %>% select(season, player_id, depth3)))
  s %>% left_join(r, by = c("season", "player_id")) %>%
    mutate(age = age_s, ss = pmin(n_s / pmax(tg_cur, 1), 1),
           depthf = factor(ifelse(season < RL_FIRST, "unk", as.character(pmin(coalesce(depth3, 3L), 3L))), levels = c("1", "2", "3", "unk")))
})
QSH <- bind_rows(lapply(1:NFUT, function(h) QSNAP %>% mutate(h = h, yo = season + h) %>%
  left_join(seasS %>% transmute(player_id, yo = season, g_s_o = g_s, pts_s_o = pts_s), by = c("player_id", "yo")) %>%
  left_join(seas %>% transmute(player_id, yo = season, g_o = g), by = c("player_id", "yo")) %>%
  mutate(g_s_o = coalesce(g_s_o, 0L), g_o = coalesce(g_o, 0L), share_o = pmin(g_s_o / tg_of(yo), 1), relief_o = pmin(pmax(g_o - g_s_o, 0) / tg_of(yo), 1),
         ppg_s_o = ifelse(g_s_o > 0, pts_s_o / g_s_o, NA))))
fit_qb <- function(last_y) {
  d <- QSH %>% filter(yo <= last_y + 1)
  fx <- ~ ns(h, 2) + ss + depthf + cppg_s + age + I(pmax(age - 33, 0)) + lpick + factor(pmin(exp, 3)) + h:ss + h:age + h:cppg_s
  sh <- suppressWarnings(glm(update(fx, share_o ~ .), family = quasibinomial, data = d))
  rl <- suppressWarnings(glm(update(fx, relief_o ~ .), family = quasibinomial, data = d))
  d4 <- d %>% filter(g_s_o >= 4)
  pr <- lm(ppg_s_o ~ ns(h, 2) + cppg_s + depthf + age + I(pmax(age - 33, 0)) + factor(pmin(exp, 3)) + lpick + h:cppg_s + h:age, data = d4, weights = g_s_o)
  r <- residuals(pr); sig_h <- sapply(1:NFUT, function(k) { i <- d4$h == k; sqrt(sum(d4$g_s_o[i] * r[i]^2) / sum(d4$g_s_o[i])) })
  list(sh = sh, rl = rl, pr = pr, sig = sig_h[1], sig_h = sig_h, n = nrow(d))
}
# x: snapshot QB rows (cppg = depth-adjusted PPG in starts for this season, cppg_s raw, n_s, tg_cur, depth3, age, exp, lpick,
#    rep_ppg, relief_g, ppg_r); returns per-season values t = 1..NFUT and the rest of this season (v0)
project_qb <- function(x, Q, sd0) {
  out <- matrix(0, nrow(x), NFUT); Gm <- out; Pm <- out
  v0 <- pmax(x$tg_left * x$cavail * stoploss(x$cppg, x$rep_ppg, sd0) - x$relief_g * (x$rep_ppg - x$ppg_r) * pnorm((x$cppg - x$rep_ppg) / sd0), 0)
  nd <- data.frame(ss = pmin(x$n_s / pmax(x$tg_cur, 1), 1), cppg_s = x$cppg_s, age = x$age, lpick = x$lpick, exp = x$exp,
                   depthf = factor(as.character(pmin(coalesce(x$depth3, 3L), 3L)), levels = c("1", "2", "3", "unk")))
  for (t in 1:NFUT) { nd$h <- t
    sh <- predict(Q$sh, newdata = nd, type = "response"); rl <- predict(Q$rl, newdata = nd, type = "response"); pp <- predict(Q$pr, newdata = nd)
    sd_t <- Q$sig_h[t]   # direct h-ahead residual sd (the QB layer has no feeding forward)
    out[, t] <- pmax(GLEN_[t] * sh * stoploss(pp, x$rep_ppg, sd_t) - GLEN_[t] * rl * (x$rep_ppg - x$ppg_r) * pnorm((pp - x$rep_ppg) / sd_t), 0)
    Gm[, t] <- GLEN_[t] * (sh + rl); Pm[, t] <- pp
  }
  list(val = out, G = Gm, ppg = Pm, v0 = v0)
}
