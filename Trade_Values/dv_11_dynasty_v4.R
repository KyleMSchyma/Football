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
  d %>% left_join(nx, by = "player_id") %>% mutate(g_next = coalesce(g_next, 0L), played_next = as.integer(g_next >= 1),
                                                   rate_next = ifelse(g_next >= 1, pmin(g_next / tg_next, 1), NA))
}
SE <- bind_rows(lapply(2009:2025, season_end)) %>% filter(!is.na(age))
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
      nd <- data.frame(cppg = cp, age = x$age + t - 1, exp = x$exp + t - 1, lpick = x$lpick, avail = av)
      S <- S * predict(f$act, nd, type = "response")
      ppg_t <- predict(f$prod, nd); av_t <- predict(f$av, nd, type = "response")
      sd_t <- f$sig * sqrt(t)
      out[i, t + 1] <- S * 17 * av_t * stoploss(ppg_t, x$rep_ppg, sd_t)
      Sm[i, t + 1] <- S; Pm[i, t + 1] <- ppg_t; Gm[i, t + 1] <- S * 17 * av_t
      cp <- ppg_t; av <- av_t
    }
  }
  disc <- v^(0:NFUT)
  list(value = as.vector(out %*% disc), seasons = out, S = Sm, ppg = Pm, G = Gm)
}

# residual sd of the season-level PPG model (per game), used for the uncertainty in future seasons
fix_sig <- function(F) lapply(F, function(f) { r <- residuals(f$prod); w8 <- f$prod$weights
  f$sig <- sqrt(sum(w8 * r^2) / sum(w8)); f })   # weighted residual sd of next-season PPG

# ---------- backtest: week-9 snapshots 2016-2020, 5 seasons of outcomes ----------
seas_pp <- seas %>% transmute(player_id, season, g, ppg = pts / g)
# lg = NULL: the QB24 / RB24 / WR36 / TE12 lines; otherwise a league setting (rep_lines in dv_10)
bt_dyn <- function(lg = NULL) { BT <- list()
for (Y in 2016:2020) {
  F <- fix_sig(fit_future(Y - 2))
  d <- value_board(bt %>% filter(season == Y), lg) %>% filter(n_cur >= 3) %>%
    mutate(age = as.numeric(as.Date(paste0(Y, "-09-01")) - birth_date) / 365.25) %>% filter(!is.na(age))
  pr <- project(d, F, setNames(m1$rmse_credibility, m1$pos))
  act0 <- pmax(d$ppg_ros - d$rep_ppg, 0) * d$n_ros; act0[is.na(act0)] <- 0
  actf <- sapply(1:NFUT, function(t) { a <- seas_pp %>% filter(season == Y + t)
    m <- a[match(d$player_id, a$player_id), ]; x <- pmax(m$ppg - d$rep_ppg, 0) * m$g; x[is.na(x)] <- 0; x })
  actual <- act0 + as.vector(actf %*% v^(1:NFUT))
  naive <- pmax(d$ppg_cur - d$rep_ppg, 0) * (d$tg_left + 17 * sum(v^(1:NFUT)) * d$rate_cur)
  BT[[as.character(Y)]] <- d %>% transmute(season = Y, pos, name, age, exp, young = exp <= 2) %>%
    mutate(pred = pr$value, actual = actual, naive = naive, this_season = pmax(d$value, 0))
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
pr <- project(d26, F, setNames(m1$rmse_credibility, m1$pos))
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
