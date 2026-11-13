# =============================================================================
# Role layer hook for dv_10 (sourced after bt <- apply_k(bt) when ROLE_AVAIL, QB_START or ROLE_SNAP is on)
# Builds extra training snapshots 2012-2015, joins the role status, adds QB start features, then replaces
# cppg / cavail in the backtest rows season by season with models fit only on earlier snapshot seasons.
# Defines rl_now(s26) for the live board (fit on every snapshot season through 2025).
# =============================================================================
source("rl_common.R")
cat("\n== role layer: ROLE_AVAIL =", ROLE_AVAIL, " QB_START =", QB_START, " ROLE_SNAP =", ROLE_SNAP, "==\n")

# ---------- QB starts: season table, potential prior in starts, snapshot features and targets ----------
wq <- w %>% filter(position == "QB", att >= 15)
seasS <- wq %>% group_by(player_id, season) %>% summarise(g_s = n_distinct(week), pts_s = sum(pts), .groups = "drop") %>%
  left_join(seas %>% select(player_id, season, tg_season), by = c("player_id", "season"))
potS_fit <- function(yr) {
  tr <- seasS %>% filter(season < yr, season >= yr - 10) %>% inner_join(p, by = "player_id") %>%
    mutate(exp = pmin(pmax(season - coalesce(rookie_season, season), 0), 4), lpick = log(coalesce(draft_pick, 262)), ppg = pts_s / g_s)
  lm(ppg ~ ns(lpick, knots = log(c(32, 100)), Boundary.knots = log(c(1, 262))) + factor(exp), data = tr, weights = g_s)
}
POTS <- list()
qb_starts <- function(d) bind_rows(lapply(sort(unique(d$season)), function(yr) {
  x <- d %>% filter(season == yr); cut <- if (yr == CUR) CUT26 else CUT
  cs <- wq %>% filter(season == yr, week <= cut) %>% group_by(player_id) %>% summarise(n_s = n_distinct(week), pts_s_cur = sum(pts), .groups = "drop")
  hs <- seasS %>% filter(season >= yr - 3, season <= yr - 1) %>% group_by(player_id) %>% summarise(g_s_h = sum(g_s), pts_s_h = sum(pts_s), .groups = "drop")
  fs <- wq %>% filter(season == yr, week > cut) %>% group_by(player_id) %>% summarise(n_s_ros = n_distinct(week), pts_s_ros = sum(pts), .groups = "drop")
  key <- as.character(yr); if (is.null(POTS[[key]])) POTS[[key]] <<- potS_fit(yr)
  x <- x %>% select(-any_of(c("n_s", "pts_s_cur", "g_s_h", "pts_s_h", "n_s_ros", "pts_s_ros"))) %>%
    left_join(cs, by = "player_id") %>% left_join(hs, by = "player_id") %>% left_join(fs, by = "player_id") %>%
    mutate(across(c(n_s, g_s_h, n_s_ros), ~ coalesce(.x, 0L)), across(c(pts_s_cur, pts_s_h, pts_s_ros), ~ coalesce(.x, 0)),
           age_s = as.numeric(as.Date(paste0(yr, "-09-01")) - birth_date) / 365.25)
  x$age_s[is.na(x$age_s)] <- 26
  x$prior_s <- pmax(predict(POTS[[key]], newdata = data.frame(lpick = x$lpick, exp = factor(pmin(x$exp, 4), levels = 0:4))), 0)
  x }))
cred_s <- function(d, k1, k2) {
  ppg_c <- ifelse(d$n_s > 0, d$pts_s_cur / pmax(d$n_s, 1), 0); ppg_h <- ifelse(d$g_s_h > 0, d$pts_s_h / pmax(d$g_s_h, 1), 0)
  hist <- d$g_s_h / (d$g_s_h + k2) * ppg_h + k2 / (d$g_s_h + k2) * d$prior_s
  d$n_s / (d$n_s + k1) * ppg_c + k1 / (d$n_s + k1) * hist
}

# ---------- all snapshot rows 2012-2025 with role status ----------
bt_x <- bind_rows(lapply(RL_FIRST:(min(BT_YEARS) - 1), function(y) snapshot(y) %>% left_join(targets(y), by = "player_id"))) %>%
  mutate(n_ros = coalesce(n_ros, 0L), pts_ros = coalesce(pts_ros, 0), rate_ros = pmin(n_ros / tg_left, 1),
         ppg_ros = ifelse(n_ros > 0, pts_ros / n_ros, NA)) %>% filter(!is.na(prior_ppg), tg_left > 0)
bt_x <- apply_k(bt_x)
RL_ALL <- qb_starts(role_join(bind_rows(bt_x, bt)))
cat("role status at the week-9 snapshot, 2016-2025 backtest rows:\n")
print(table(RL_ALL$pos[RL_ALL$season >= 2016], coalesce(RL_ALL$cat[RL_ALL$season >= 2016], "no roster row")))
# QB credibility constants for PPG in starts (same fit as k1, k2 in dv_10: 2016-2025 rows, 3+ later starts)
q1 <- RL_ALL %>% filter(pos == "QB", season %in% BT_YEARS, n_s_ros >= 3) %>% mutate(ppg_s_ros = pts_s_ros / n_s_ros)
oq <- optim(c(log(4), log(8)), function(q) { pr <- cred_s(q1, exp(q[1]), exp(q[2])); sum(q1$n_s_ros * (q1$ppg_s_ros - pr)^2) })
KS <- exp(oq$par); cat("QB credibility constants, PPG in starts: k1 =", round(KS[1], 2), " k2 =", round(KS[2], 2), "\n")
RL_ALL$cppg_s <- ifelse(RL_ALL$pos == "QB", cred_s(RL_ALL, KS[1], KS[2]), NA)
QB_SD0 <- with(q1 %>% mutate(pr = cred_s(q1, KS[1], KS[2])), sqrt(weighted.mean((ppg_s_ros - pr)^2, n_s_ros)))

# ---------- apply the switches to one season's rows with fits from earlier seasons ----------
rl_apply <- function(x, tr) {
  x$cppg_rep <- x$cppg   # replacement lines and the backtest targets stay on the live definition
  if (ROLE_SNAP) { S <- sp_fit(tr); i <- x$pos %in% SP_POS; x$cppg[i] <- x$cppg[i] + sp_pred(x[i, ], S) }
  if (ROLE_AVAIL) { f <- ra_fit(tr, snap = ROLE_SNAP); x$cavail <- ra_pred(x, f) }
  if (QB_START && QB_FUT_ONLY) x$ppg_r <- qadj_fit(tr)$ppg_r   # A3F: starter layer for future seasons only
  if (QB_START && !QB_FUT_ONLY) { i <- which(x$pos == "QB"); g <- qs_fit(tr); qa <- qadj_fit(tr)
    games_sh <- x$cavail[i]                                       # share of games he plays (A2 if on, else the live availability)
    x$cppg[i] <- x$cppg_s[i] + qa$adj[pmin(coalesce(x$depth3[i], 3L), 3L)]
    x$cavail[i] <- qs_pred(x[i, ], g)
    x$relief_g <- 0; x$relief_g[i] <- x$tg_left[i] * pmax(games_sh - x$cavail[i], 0)   # appearances that are not starts
    x$ppg_r <- qa$ppg_r }
  x
}
# QB: average (PPG in starts later - credible PPG in starts) by depth rank, and PPG in relief appearances (< 15 attempts),
# both from the training snapshot seasons only
qadj_fit <- function(tr) {
  x <- role_fill(tr) %>% filter(pos == "QB", n_s_ros >= 3) %>% mutate(res = pts_s_ros / n_s_ros - cppg_s)
  adj <- sapply(1:3, function(k) { z <- x %>% filter(depth3 == k); if (sum(z$n_s_ros) < 30) 0 else weighted.mean(z$res, z$n_s_ros) })
  rl <- w %>% filter(position == "QB", att < 15, season %in% unique(tr$season))
  list(adj = adj, ppg_r = sum(rl$pts) / nrow(rl))
}
RL_FITS <- list()
bt <- bind_rows(lapply(BT_YEARS, function(Y) rl_apply(RL_ALL %>% filter(season == Y), RL_ALL %>% filter(season < Y))))
cat("backtest rows after the role layer:", nrow(bt), "\n")
rl_now <- function(s) {
  s <- qb_starts(role_join(s %>% mutate(season = CUR), now = TRUE))
  s$cppg_s <- ifelse(s$pos == "QB", cred_s(s, KS[1], KS[2]), NA)
  rl_apply(s, RL_ALL)
}
