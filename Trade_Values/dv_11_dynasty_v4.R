# =============================================================================
# Dynasty value v4: potential + production + aging + injury + staying in the league
#
#   Value = sum_{t=0..4} v^t x S(t) x G(t) x E[(PPG_t - replacement)+]        v = 1/1.15
#     t = 0     rest of 2026 (team games left x credible availability), from dv_10
#     t = 1..5  2027-2031, 17 games x projected availability (was 2027-2030 until 2026-11-13)
#   PPG_t      projected by an aging model: next-season PPG ~ this season's credible PPG + age curve
#              + years in league + draft slot for young players (fit by position)
#   S(t)       chance he is still playing in the NFL in season t (logistic, by position)
#   G(t)       expected games (availability model with an age curve)
#   E[(X - r)+] the expected amount above replacement when PPG is uncertain (normal, sd grows with t).
#              This is the insurance "stop-loss" formula, so a player projected just below replacement
#              still has some upside value.
# Credible PPG already blends 2026 PPG, the last 3 seasons and a draft-capital "potential" prior (dv_10).
# Backtest: snapshots at week 9 of 2016-2020, models fit only on earlier seasons, 5-season outcomes.
# =============================================================================
source("dv_10_ros_value.R")
cat("\n\n== Dynasty value v4 ==\n")
v <- 1 / (1 + I_MAIN); NFUT <- 5   # Kyle 2026-11-13: value everyone (players and 2027 picks) through 2031
age_ns <- function(a) ns(a, knots = c(25, 28, 31), Boundary.knots = c(21, 38))
# ---- Football2_Dynasty_dev switches (all off = the live model) ----
#   H_DIRECT  B2(i)   direct horizon models: PPG, still playing and availability in season y+h fit on year-y features
#   SIG_H     B2(ii)  stop-loss sd from h-year-ahead residuals instead of sig x sqrt(t)
#   SURV4     B2(iii) "still playing" = 4+ games instead of any game
#   AGE_MODE  B3      "none" | "mono" (still-playing probability non-increasing in age after 30) | "pool37" (ages 37+ pooled)
#   QB_START  A3/A5   QBs: share of games started x value as a starter (rl_dv11_qb.R)
for (v_ in c("H_DIRECT", "SIG_H", "SURV4", "QB_START", "QB_FUT_ONLY")) if (!exists(v_)) assign(v_, FALSE)
if (!exists("AGE_MODE")) AGE_MODE <- "none"
if (AGE_MODE == "pool37") age_ns <- function(a) cbind(ns(pmin(a, 37), knots = c(25, 28, 31), Boundary.knots = c(21, 37)), a37 = as.numeric(a >= 37))
MIN_ALIVE <- if (SURV4) 4 else 1
# LENFIX (dev): in the backtest, value future season Y + t at its real length (16 games before 2021, 17 after) instead of 17.
# The live board is unaffected (every season from 2027 on has 17 games). GLEN_ = games per future season used by project().
if (!exists("LENFIX")) LENFIX <- FALSE
tg_of <- function(y) ifelse(y >= 2021, 17L, 16L)
GLEN_ <- rep(17, NFUT)

# ---------- season-end table: credible PPG at the end of season y, and what happened in y+1 ----------
season_end <- function(y) {
  cur <- seasP %>% filter(season == y, g >= 1)
  his <- seas %>% filter(season >= y - 3, season <= y - 1) %>% group_by(player_id) %>%
    summarise(g_h = sum(g), pts_h = sum(pts), tg_h = sum(tg_season, na.rm = TRUE), .groups = "drop") %>%
    mutate(ppg_h = pts_h / g_h, avail_h = pmin(g_h / tg_h, 1))
  d <- cur %>% left_join(his, by = "player_id") %>% left_join(p, by = "player_id") %>%
    mutate(g_h = coalesce(g_h, 0), tg_h = coalesce(tg_h, 0), exp = pmax(0, y - coalesce(rookie_season, y)),
           lpick = log(coalesce(draft_pick, 262)), age = as.numeric(as.Date(paste0(y, "-09-01")) - birth_date) / 365.25,
           ppg = pts / g, avail = pmin(g / tg_season, 1))
  d$prior_ppg <- potential_ppg(y, d)
  k <- K[d$pos, , drop = FALSE]
  hist <- ifelse(d$g_h > 0, d$g_h / (d$g_h + k[, "k2"]) * coalesce(d$ppg_h, 0) + k[, "k2"] / (d$g_h + k[, "k2"]) * d$prior_ppg, d$prior_ppg)
  d$cppg <- d$g / (d$g + k[, "k1"]) * d$ppg + k[, "k1"] / (d$g + k[, "k1"]) * hist
  nx <- seas %>% filter(season == y + 1) %>% transmute(player_id, g_next = g, ppg_next = pts / g, tg_next = tg_season)
  d %>% left_join(nx, by = "player_id") %>% mutate(g_next = coalesce(g_next, 0L), played_next = as.integer(g_next >= MIN_ALIVE),
                                                   rate_next = ifelse(g_next >= MIN_ALIVE, pmin(g_next / tg_next, 1), NA))
}
SE <- bind_rows(lapply(2009:2025, season_end)) %>% filter(!is.na(age))
source("rl_dv11_ext.R")                     # direct-horizon fits, h-ahead sd, monotone age (dev)
if (QB_START) source("rl_dv11_qb.R")        # QB starter layer (dev)
# QB_DEPTH (dev): depth rank at the end of season y (2012+, "unk" before) in the QB still-playing and PPG models.
# Projection: the snapshot depth rank for the first future season, "unk" (no depth information) after that.
if (!exists("QB_DEPTH")) QB_DEPTH <- FALSE
if (!exists("QB_SS")) QB_SS <- FALSE   # QB_SS: also the share of team games started this season
# average of two fitted models (QB_SS = "avg"): predictions averaged on the response scale
avg_model <- function(m1, m2) structure(list(m1 = m1, m2 = m2, weights = m1$weights), class = "avgmod")
predict.avgmod <- function(object, newdata, type = "response", ...) (predict(object$m1, newdata, type = type) + predict(object$m2, newdata, type = type)) / 2
residuals.avgmod <- function(object, ...) residuals(object$m1) + (fitted(object$m1) - (fitted(object$m1) + fitted(object$m2)) / 2)
dep_f <- function(known, d) factor(ifelse(known, as.character(pmin(coalesce(as.integer(d), 3L), 3L)), "unk"), levels = c("1", "2", "3", "unk"))
if (QB_DEPTH) {
  de_ <- RL_DEPTH %>% filter(week < 99, week <= 18) %>% group_by(season, team) %>% filter(week == max(week)) %>% ungroup() %>%
    group_by(season, player_id) %>% summarise(depth_end = min(depth_rank), .groups = "drop")
  SE <- SE %>% left_join(de_, by = c("season", "player_id")) %>% mutate(depthf = dep_f(season >= RL_FIRST, depth_end)) %>%
    left_join(seasS %>% select(player_id, season, g_s), by = c("player_id", "season")) %>% mutate(ss = pmin(coalesce(g_s, 0L) / tg_season, 1))
  SEH_ <- lapply(SEH_, function(z) z %>% left_join(SE %>% select(player_id, season, depthf, ss), by = c("player_id", "season")))
}
cat("season-end rows:", nrow(SE), "\n")

fit_future <- function(last_y) {
  d <- SE %>% filter(season <= last_y)
  lapply(setNames(POSITIONS, POSITIONS), function(ps) { x <- d %>% filter(pos == ps)
    prod <- lm(ppg_next ~ cppg + age_ns(age) + factor(pmin(exp, 3)) + lpick:I(exp <= 2), data = x %>% filter(g_next >= 4), weights = g_next)
    act  <- glm(played_next ~ cppg + age_ns(age) + factor(pmin(exp, 3)) + lpick, data = x, family = binomial)
    av   <- glm(rate_next ~ avail + age_ns(age) + cppg, data = x %>% filter(played_next == 1), family = quasibinomial, weights = tg_next)
    sig  <- NA   # set by fix_sig()
    list(prod = prod, act = act, av = av, sig = sig)
  })
}
fit_future0 <- fit_future
fit_future <- function(last_y) {
  F <- fit_future0(last_y)
  if (QB_DEPTH) { x <- SE %>% filter(season <= last_y, pos == "QB")
    fp <- function(ssf) lm(if (ssf) ppg_next ~ cppg + age_ns(age) + factor(pmin(exp, 3)) + lpick:I(exp <= 2) + depthf + ss else
                             ppg_next ~ cppg + age_ns(age) + factor(pmin(exp, 3)) + lpick:I(exp <= 2) + depthf, data = x %>% filter(g_next >= 4), weights = g_next)
    fa <- function(ssf) glm(if (ssf) played_next ~ cppg + age_ns(age) + factor(pmin(exp, 3)) + lpick + depthf + ss else
                              played_next ~ cppg + age_ns(age) + factor(pmin(exp, 3)) + lpick + depthf, data = x, family = binomial)
    if (identical(QB_SS, "avg")) { F$QB$prod <- avg_model(fp(FALSE), fp(TRUE)); F$QB$act <- avg_model(fa(FALSE), fa(TRUE)) }
    else { F$QB$prod <- fp(isTRUE(QB_SS)); F$QB$act <- fa(isTRUE(QB_SS)) } }
  if (H_DIRECT) { D <- fit_direct(last_y); for (ps in POSITIONS) F[[ps]]$dir <- D[[ps]] }
  if (SIG_H) for (ps in POSITIONS) F[[ps]]$sig_h <- sig_h_fit(F[[ps]], ps, last_y)
  if (QB_START) F$QB$Q <- fit_qb(last_y)
  F
}
stoploss <- function(mu, r, s) { z <- (mu - r) / s; s * dnorm(z) + (mu - r) * pnorm(z) }

# d needs: pos, cppg, cavail, age (at the snapshot season), exp, lpick, rep_ppg, tg_left; sd0 = rest-of-season PPG error
project <- function(d, F, sd0) {
  out <- matrix(0, nrow(d), NFUT + 1); Sm <- matrix(1, nrow(d), NFUT + 1); Pm <- matrix(NA, nrow(d), NFUT + 1)
  Gm <- matrix(0, nrow(d), NFUT + 1)   # expected games, survival included (S x 17 x availability)
  for (ps in POSITIONS) { i <- which(d$pos == ps); if (!length(i)) next
    f <- F[[ps]]; x <- d[i, ]
    Pm[i, 1] <- x$cppg; Gm[i, 1] <- x$tg_left * x$cavail
    out[i, 1] <- x$tg_left * x$cavail * stoploss(x$cppg, x$rep_ppg, sd0[ps])   # sd0 = backtest error of credible PPG for the rest of the season
    cp <- x$cppg; av <- x$cavail; S <- rep(1, length(i))
    for (t in 1:NFUT) {
      if (H_DIRECT) { D <- f$dir[[t]]
        nd <- data.frame(cppg = x$cppg, age = x$age, exp = x$exp, lpick = x$lpick, avail = x$cavail)
        S <- pmin(S, act_p(D$act, nd)); ppg_t <- predict(D$prod, nd); av_t <- predict(D$av, nd, type = "response")
        sd_t <- if (SIG_H) D$sig else f$sig * sqrt(t)
      } else {
      nd <- data.frame(cppg = cp, age = x$age + t - 1, exp = x$exp + t - 1, lpick = x$lpick, avail = av)
      if (QB_DEPTH) { nd$depthf <- dep_f(rep(t == 1, nrow(x)), x$depth3); nd$ss <- pmin(coalesce(x$n_s, 0L) / pmax(x$tg_cur, 1), 1) }   # share started this season, carried forward
      S <- S * act_p(f$act, nd)
      ppg_t <- predict(f$prod, nd); av_t <- predict(f$av, nd, type = "response")
      sd_t <- if (SIG_H) f$sig_h[t] else f$sig * sqrt(t)
      }
      out[i, t + 1] <- S * GLEN_[t] * av_t * stoploss(ppg_t, x$rep_ppg, sd_t)
      Sm[i, t + 1] <- S; Pm[i, t + 1] <- ppg_t; Gm[i, t + 1] <- S * GLEN_[t] * av_t
      cp <- ppg_t; av <- av_t
    }
    if (QB_START && ps == "QB") { q <- project_qb(x, F$QB$Q, sd0[ps])
      if (!QB_FUT_ONLY) out[i, 1] <- q$v0; out[i, 2:(NFUT + 1)] <- q$val; Gm[i, 2:(NFUT + 1)] <- q$G; Pm[i, 2:(NFUT + 1)] <- q$ppg }
  }
  disc <- v^(0:NFUT)
  list(value = as.vector(out %*% disc), seasons = out, S = Sm, ppg = Pm, G = Gm)
}

# residual sd of the season-level PPG model (per game), used for the uncertainty in future seasons
fix_sig <- function(F) lapply(F, function(f) { r <- residuals(f$prod); w8 <- f$prod$weights
  f$sig <- sqrt(sum(w8 * r^2) / sum(w8)); f })   # weighted residual sd of next-season PPG

# ---------- backtest: week-9 snapshots 2016-2020, 5 seasons of outcomes ----------
seas_pp <- seas %>% transmute(player_id, season, g, ppg = pts / g)
SD0 <- setNames(m1$rmse_credibility, m1$pos); if (QB_START && !QB_FUT_ONLY) SD0["QB"] <- QB_SD0   # rest-of-season PPG error (PPG in starts for QBs)
# lg = NULL: the QB24 / RB24 / WR36 / TE12 lines; otherwise a league setting (rep_lines in dv_10)
bt_dyn <- function(lg = NULL) { BT <- list()
for (Y in 2016:2020) {
  F <- fix_sig(fit_future(Y - 2))
  d <- value_board(bt %>% filter(season == Y), lg) %>% filter(n_cur >= BT_MIN) %>%
    mutate(age = as.numeric(as.Date(paste0(Y, "-09-01")) - birth_date) / 365.25) %>% filter(!is.na(age))
  GLEN_ <<- if (LENFIX) tg_of(Y + 1:NFUT) else rep(17, NFUT)
  pr <- project(d, F, SD0); GLEN_ <<- rep(17, NFUT)
  act0 <- pmax(d$ppg_ros - d$rep_ppg, 0) * d$n_ros; act0[is.na(act0)] <- 0
  actf <- sapply(1:NFUT, function(t) { a <- seas_pp %>% filter(season == Y + t)
    m <- a[match(d$player_id, a$player_id), ]; x <- pmax(m$ppg - d$rep_ppg, 0) * m$g; x[is.na(x)] <- 0; x })
  actual <- act0 + as.vector(actf %*% v^(1:NFUT))
  naive <- pmax(d$ppg_cur - d$rep_ppg, 0) * (d$tg_left + 17 * sum(v^(1:NFUT)) * d$rate_cur)
  agm <- sapply(1:NFUT, function(t) { a <- seas_pp %>% filter(season == Y + t); x <- a$g[match(d$player_id, a$player_id)]; x[is.na(x)] <- 0; x })
  apm <- sapply(1:NFUT, function(t) { a <- seas_pp %>% filter(season == Y + t); a$ppg[match(d$player_id, a$player_id)] })
  BT[[as.character(Y)]] <- d %>% transmute(season = Y, player_id, pos, name, age, exp, young = exp <= 2, lpick, rep_ppg, cppg, cavail, tg_left, n_cur) %>%
    mutate(pred = pr$value, actual = actual, naive = naive, this_season = pmax(d$value, 0), pred0 = pr$seasons[, 1], act0 = act0,
           S = pr$S[, -1], P = pr$ppg[, -1], G = pr$G[, -1], VS = pr$seasons[, -1], AG = agm, AP = apm, AV = actf)
}
bind_rows(BT) }
BT <- bt_dyn()
sm <- function(x) x %>% summarise(n = n(), spearman_v4 = cor(pred, actual, method = "spearman"),
  spearman_naive = cor(naive, actual, method = "spearman"), spearman_this_season_only = cor(this_season, actual, method = "spearman"),
  pred_total = sum(pred), actual_total = sum(actual), .groups = "drop")
res <- bind_rows(BT %>% group_by(group = pos) %>% sm(), BT %>% filter(young) %>% group_by(group = paste(pos, "years 0-2")) %>% sm(),
                 BT %>% mutate(group = "all") %>% group_by(group) %>% sm()) %>% mutate(across(where(is.numeric), ~ round(.x, 3)))
cat("\nBACKTEST (week-9 snapshots 2016-2020): predicted vs actual 5-season discounted points over replacement\n"); print(as.data.frame(res))
if (WRITE) write.csv(res, "dv_v4_backtest.csv", row.names = FALSE)

# ---------- 2026 board ----------
F <- fix_sig(fit_future(2024))
cat("\nper-game sd of next-season PPG:", paste(POSITIONS, round(sapply(F, `[[`, "sig"), 2), collapse = "  "), "\n")
d26 <- b26 %>% filter(!is.na(age)) %>% mutate(exp = pmax(0, CUR - coalesce(rookie_season, CUR)))
d26 <- d26 %>% left_join(p %>% select(player_id, draft_pick), by = "player_id", suffix = c("", ".p")) %>%
  mutate(lpick = log(coalesce(draft_pick, 262)))
pr <- project(d26, F, SD0)
b4 <- d26 %>% transmute(name, pos, team, age, exp, draft_pick, games_2026 = n_cur, ppg_2026 = round(ppg_cur, 1),
  potential_ppg = round(prior_ppg, 1), credible_ppg = round(cppg, 1), rep_ppg = round(rep_ppg, 1)) %>%
  mutate(ppg_2027 = round(pr$ppg[, 2], 1), ppg_2028 = round(pr$ppg[, 3], 1), ppg_2030 = round(pr$ppg[, 5], 1),
         S_2030 = round(pr$S[, 5], 2), value_2026_ros = round(pr$seasons[, 1], 1), value_2027 = round(pr$seasons[, 2], 1),
         value_raw = pr$value) %>%
  arrange(desc(value_raw)) %>% mutate(rank = row_number(), value_100k = round(100000 * value_raw / max(value_raw))) %>%
  group_by(pos) %>% mutate(rank_pos = paste0(pos, row_number())) %>% ungroup()
if (WRITE) write.csv(b4 %>% select(rank, rank_pos, everything(), -value_raw), "dv_v4_board.csv", row.names = FALSE)
options(width = 220)
cat("\nTOP 40, dynasty value v4 (100k scale):\n")
print(b4 %>% select(rank, rank_pos, name, team, age, exp, draft_pick, ppg_2026, credible_ppg, ppg_2027, ppg_2030, S_2030, value_100k) %>% head(40), n = 40)
cat("\nposition mix, top 24 / 50 / 100:\n"); for (k in c(24, 50, 100)) print(table(b4$pos[b4$rank <= k]))
cat("\nyoungest in the top 60:\n"); print(b4 %>% filter(rank <= 60) %>% arrange(age) %>% select(rank, name, pos, age, exp, draft_pick, ppg_2026, potential_ppg, value_100k) %>% head(10))

# dev: export for the role / calibration comparisons
if (exists("EXP_TAG")) { dir.create("exp", showWarnings = FALSE)
  saveRDS(list(BT = BT, b4 = b4, d26 = d26 %>% select(player_id, name, pos, team, age, exp, any_of(c("cat", "depth_rank", "report_status", "cavail", "cppg", "n_s", "rank", "value", "n_cur", "ppg_cur"))),
               pr26 = pr, sig = sapply(F[POSITIONS], `[[`, "sig")), paste0("exp/dv11_", EXP_TAG, ".rds")) }

