# =============================================================================
# 2026 rest-of-season value (Kyle's spec, 2026-11-11)
#
#   Value = (credible PPG - replacement PPG) x expected games left in 2026
#   credible PPG    = Z x 2026 PPG + (1 - Z) x historical PPG        Z = n / (n + k1)   (Buhlmann form)
#     historical PPG = games-weighted PPG over the last 3 seasons, itself credibility-weighted
#                      toward a rookie prior (position x draft round) with weight g / (g + k2)
#   expected games  = team games left x credible availability
#     availability   = blend of 2026 games-played rate, the player's last-3-season rate and the position
#                      average, with the same credibility form (k3, k4)
#   replacement PPG = credible PPG of the QB24 / RB24 / WR36 / TE12 (players with 6+ games in 2026)
#
# k1..k4 are fit per position on past seasons (2016-2025): weeks 1-9 are "now", weeks 10-18 are what
# we try to predict. The classic Buhlmann k (EPV / VHM from week-to-week scatter) is shown for comparison.
# Scoring: nflverse full PPR, regular season.
# =============================================================================
source("dv_common.R")
# ---- FABLE build defaults (Football2_Dynasty_dev, 2026-11-13). Set any of these to FALSE before sourcing for the old model.
#   ROLE_AVAIL  expected games from current status (reserve / Out / Doubtful / Questionable / starter / backup), rl_common.R
#   SIG_H       stop-loss sd from h-year-ahead residuals (dv_11)          LENFIX  real season length in the dynasty backtest
#   QB_DEPTH, QB_SS  depth rank (and share of games started: QB_SS TRUE, or "avg" = mean of both models) in the QB still-playing and PPG models (dv_11)
for (v_ in c("ROLE_AVAIL", "SIG_H", "LENFIX", "QB_DEPTH")) if (!exists(v_)) assign(v_, TRUE)
if (!exists("QB_SS")) QB_SS <- "avg"   # average of the depth-only and depth + start-share QB models (closest backup-QB calibration)
cat("== 2026 rest-of-season value ==\n")
CUT <- 9                          # backtests: weeks 1-9 = "now", weeks 10-18 = what we predict
CUT26 <- max(readRDS("nfl_weekly_2026.rds") %>% filter(season_type == "REG") %>% pull(week))   # 2026: latest completed week (weekly refresh)
BT_YEARS <- 2016:2025
MIN_G_REP <- 6

w <- readRDS(file.path(SHARED, "nfl_weekly_raw.rds"))
w26 <- readRDS("nfl_weekly_2026.rds")
w <- bind_rows(w, w26[, intersect(names(w26), names(w))]) %>% filter(season_type == "REG")
w$position[w$position == "FB"] <- "RB"
# league scoring (Kyle 2026-11-11): reception points (0.5 / 1 PPR), TE premium (+0 / 0.5 / 1 per TE catch), passing TD (4 / 5 / 6).
# Each knob touches only one position group, and every fit below is per position, so the fits are run once per distinct
# position scoring (dv_13): SC$ppr = points per RB/WR catch, SC$te = points per TE catch (PPR + premium), SC$ptd = QB passing TD.
# Kyle 2026-11-12: first-down bonus per position (0 / 0.25 / 0.5 / 0.75 / 1 per rushing or receiving first down, never passing),
# SC$fd = c(QB = , RB = , WR = , TE = ).
if (!exists("SC")) SC <- list(ppr = 1, te = 1, ptd = 4)          # default: full PPR, no TE premium, 4-point passing TDs
if (is.null(SC$fd)) SC$fd <- c(QB = 0, RB = 0, WR = 0, TE = 0)   # default: no first-down bonus
WRITE <- !exists("NO_WRITE") || !isTRUE(NO_WRITE)               # the league-preset loop (dv_13) writes only the default run's files
w <- w %>% filter(position %in% POSITIONS) %>% mutate(fantasy_points_ppr = coalesce(fantasy_points_ppr, 0) +
  coalesce(receptions, 0) * ifelse(position == "TE", SC$te - 1, ifelse(position %in% c("RB", "WR"), SC$ppr - 1, 0)) +
  coalesce(passing_tds, 0) * ifelse(position == "QB", SC$ptd - 4, 0) +
  (coalesce(rushing_first_downs, 0) + coalesce(receiving_first_downs, 0)) * unname(SC$fd[position]))
w <- w %>% select(player_id, name = player_display_name, position, season, week, team, pts = fantasy_points_ppr, att = attempts)   # att: QB starts (role layer)
w$pts[is.na(w$pts)] <- 0
tw <- w %>% distinct(season, team, week)                                   # team schedule actually played
team_n <- function(yr, wk_lo, wk_hi) tw %>% filter(season == yr, week >= wk_lo, week <= wk_hi) %>% count(team, name = "tg")
seas <- w %>% group_by(player_id, season) %>% summarise(g = n_distinct(week), pts = sum(pts), team = last(team), .groups = "drop") %>%
  left_join(tw %>% count(season, team, name = "tg_season"), by = c("season", "team"))
p <- readRDS(file.path(SHARED, "players_raw.rds")) %>% transmute(player_id = gsis_id, draft = draft_bucket(draft_round),
                                                                  draft_pick, rookie_season, birth_date = as.Date(birth_date))
seasP <- seas %>% inner_join(w %>% count(player_id, season, position) %>% group_by(player_id, season) %>%
                               slice_max(n, n = 1, with_ties = FALSE) %>% select(player_id, season, pos = position), by = c("player_id", "season"))

# ---------- one snapshot: everything known at week CUT of season yr ----------
snapshot <- function(yr, cut = if (yr == CUR) CUT26 else CUT) {
  cur <- w %>% filter(season == yr, week <= cut) %>% group_by(player_id) %>%
    summarise(name = last(name), pos = names(which.max(table(position))), team = last(team),
              n_cur = n_distinct(week), pts_cur = sum(pts), last_wk = max(week), .groups = "drop") %>%
    left_join(team_n(yr, 1, cut) %>% rename(tg_cur = tg), by = "team") %>%
    left_join(team_n(yr, cut + 1, 18) %>% rename(tg_left = tg), by = "team") %>%
    mutate(ppg_cur = pts_cur / n_cur, rate_cur = pmin(n_cur / tg_cur, 1))
  if (yr == CUR) cur$tg_left <- 17 - cur$tg_cur                              # 2026: schedule not played yet
  his <- seas %>% filter(season >= yr - 3, season <= yr - 1) %>% group_by(player_id) %>%
    summarise(g_h = sum(g), pts_h = sum(pts), tg_h = sum(tg_season, na.rm = TRUE), .groups = "drop") %>%
    mutate(ppg_h = pts_h / g_h, avail_h = pmin(g_h / tg_h, 1))
  d <- cur %>% left_join(his, by = "player_id") %>% left_join(p, by = "player_id") %>%
    mutate(g_h = coalesce(g_h, 0), tg_h = coalesce(tg_h, 0), draft = coalesce(draft, factor("UDFA", levels(draft))),
           missed_last2 = as.integer(last_wk <= cut - 2), season = yr)
  # "potential" prior: expected PPG from draft slot and years in the league (fit on the 10 seasons before yr)
  d <- d %>% mutate(exp = pmax(0, yr - coalesce(rookie_season, yr)), lpick = log(coalesce(draft_pick, 262)))
  d$prior_ppg <- potential_ppg(yr, d)
  pa <- seasP %>% filter(season >= yr - 3, season <= yr - 1) %>% group_by(pos) %>%
    summarise(pos_avail = sum(g) / sum(tg_season, na.rm = TRUE))
  d <- d %>% left_join(pa, by = "pos")
  if (isTRUE(WIDE_POP)) d <- wide_rows(d, yr, cut)
  d
}
# WIDE_POP (dev): also score players on a roster at the snapshot week (active, inactive or reserve list; not practice
# squad) with no game yet this season, if they have a draft pick or games in the previous season (n_cur = 0).
if (!exists("WIDE_POP")) WIDE_POP <- FALSE
if (WIDE_POP) { RS_W <- readRDS("cache_role/roster_status_week.rds"); PN_W <- readRDS(file.path(SHARED, "players_raw.rds")) %>% transmute(player_id = gsis_id, nm = display_name) }
wide_rows <- function(d, yr, cut) {
  r <- RS_W %>% filter(season == yr, week <= cut) %>% group_by(player_id) %>% slice_max(week, n = 1, with_ties = FALSE) %>% ungroup()
  tl <- RS_W %>% filter(season == yr, week <= cut) %>% group_by(r_team) %>% summarise(tlw = max(week), .groups = "drop")
  prev <- seas %>% filter(season == yr - 1, g >= 1) %>% pull(player_id)
  r <- r %>% left_join(tl, by = "r_team") %>% filter(week == tlw, status %in% c("ACT", "INA", "RES", "PUP", "SUS", "EXE", "NWT"), r_pos %in% POSITIONS,
                                                    !player_id %in% d$player_id) %>%
    left_join(p, by = "player_id") %>% filter(!is.na(draft_pick) | player_id %in% prev)
  if (!nrow(r)) return(d)
  x <- r %>% transmute(player_id, name = PN_W$nm[match(player_id, PN_W$player_id)], pos = r_pos, team = r_team, n_cur = 0L, pts_cur = 0, last_wk = 0L) %>%
    left_join(team_n(yr, 1, cut) %>% rename(tg_cur = tg), by = "team") %>% left_join(team_n(yr, cut + 1, 18) %>% rename(tg_left = tg), by = "team") %>%
    mutate(ppg_cur = 0, rate_cur = 0)
  if (yr == CUR) x$tg_left <- 17 - x$tg_cur
  his <- seas %>% filter(season >= yr - 3, season <= yr - 1) %>% group_by(player_id) %>%
    summarise(g_h = sum(g), pts_h = sum(pts), tg_h = sum(tg_season, na.rm = TRUE), .groups = "drop") %>% mutate(ppg_h = pts_h / g_h, avail_h = pmin(g_h / tg_h, 1))
  x <- x %>% left_join(his, by = "player_id") %>% left_join(p, by = "player_id") %>%
    mutate(g_h = coalesce(g_h, 0), tg_h = coalesce(tg_h, 0), draft = coalesce(draft, factor("UDFA", levels(draft))), missed_last2 = 1L, season = yr,
           exp = pmax(0, yr - coalesce(rookie_season, yr)), lpick = log(coalesce(draft_pick, 262)))
  x$prior_ppg <- potential_ppg(yr, x)
  pa <- seasP %>% filter(season >= yr - 3, season <= yr - 1) %>% group_by(pos) %>% summarise(pos_avail = sum(g) / sum(tg_season, na.rm = TRUE))
  bind_rows(d, x %>% left_join(pa, by = "pos") %>% filter(!is.na(tg_cur)))
}
# draft-capital prior: PPG ~ ns(log pick) + years in league, per position, weighted by games
potential_fit <- function(yr) {
  tr <- seasP %>% filter(season < yr, season >= yr - 10, g >= 1) %>% inner_join(p, by = "player_id") %>%
    mutate(exp = pmin(pmax(season - coalesce(rookie_season, season), 0), 4), lpick = log(coalesce(draft_pick, 262)), ppg = pts / g)
  lapply(setNames(POSITIONS, POSITIONS), function(ps)
    lm(ppg ~ ns(lpick, knots = log(c(32, 100)), Boundary.knots = log(c(1, 262))) + factor(exp), data = tr %>% filter(pos == ps), weights = g))
}
POT_CACHE <- list()
potential_ppg <- function(yr, d) {
  key <- as.character(yr); if (is.null(POT_CACHE[[key]])) POT_CACHE[[key]] <<- potential_fit(yr)
  f <- POT_CACHE[[key]]; out <- rep(NA_real_, nrow(d))
  for (ps in POSITIONS) { i <- which(d$pos == ps)
    if (length(i)) out[i] <- predict(f[[ps]], newdata = data.frame(lpick = d$lpick[i], exp = factor(pmin(d$exp[i], 4), levels = 0:4))) }
  pmax(out, 0)
}
targets <- function(yr) w %>% filter(season == yr, week > CUT) %>% group_by(player_id) %>%
  summarise(n_ros = n_distinct(week), pts_ros = sum(pts), .groups = "drop")

cred_ppg <- function(d, k1, k2) {
  hist <- ifelse(d$g_h > 0, d$g_h / (d$g_h + k2) * coalesce(d$ppg_h, 0) + k2 / (d$g_h + k2) * d$prior_ppg, d$prior_ppg)
  d$n_cur / (d$n_cur + k1) * d$ppg_cur + k1 / (d$n_cur + k1) * hist
}
cred_avail <- function(d, k3, k4) {
  hist <- d$tg_h / (d$tg_h + k4) * coalesce(d$avail_h, 0) + k4 / (d$tg_h + k4) * d$pos_avail
  d$tg_cur / (d$tg_cur + k3) * d$rate_cur + k3 / (d$tg_cur + k3) * hist
}

# ---------- backtest data ----------
bt <- bind_rows(lapply(BT_YEARS, function(y) snapshot(y) %>% left_join(targets(y), by = "player_id"))) %>%
  mutate(n_ros = coalesce(n_ros, 0L), pts_ros = coalesce(pts_ros, 0), rate_ros = pmin(n_ros / tg_left, 1),
         ppg_ros = ifelse(n_ros > 0, pts_ros / n_ros, NA)) %>% filter(!is.na(prior_ppg), tg_left > 0)
cat("backtest player-seasons:", nrow(bt), "\n")

# ---------- fit k1..k4 per position ----------
fitk <- list()
for (ps in POSITIONS) {
  d1 <- bt %>% filter(pos == ps, n_ros >= 3)
  o1 <- optim(c(log(4), log(8)), function(q) { pr <- cred_ppg(d1, exp(q[1]), exp(q[2])); sum(d1$n_ros * (d1$ppg_ros - pr)^2) })
  d2 <- bt %>% filter(pos == ps, n_cur >= 2)
  o2 <- optim(c(log(8), log(16)), function(q) { pr <- cred_avail(d2, exp(q[1]), exp(q[2])); sum(d2$tg_left * (d2$rate_ros - pr)^2) })
  fitk[[ps]] <- c(k1 = exp(o1$par[1]), k2 = exp(o1$par[2]), k3 = exp(o2$par[1]), k4 = exp(o2$par[2]))
}
K <- do.call(rbind, fitk); cat("\nfitted credibility constants (games):\n"); print(round(K, 2))

# classic Buhlmann-Straub k from in-season weekly scatter, 2021-2025, player-seasons with 4+ games
bk <- w %>% filter(season %in% 2021:2025) %>% group_by(position, player_id, season) %>% filter(n() >= 4) %>%
  summarise(n = n(), m = mean(pts), v = var(pts), .groups = "drop") %>% group_by(position) %>%
  summarise(EPV = sum((n - 1) * v) / sum(n - 1), xbar = sum(n * m) / sum(n), r = n(), N = sum(n),
            VHM = (sum(n * (m - xbar)^2) - (r - 1) * EPV) / (N - sum(n^2) / N)) %>%
  mutate(k_buhlmann = EPV / VHM)
cat("\nclassic Buhlmann k (EPV / VHM, weekly points):\n"); print(bk %>% select(position, EPV, VHM, k_buhlmann) %>% mutate(across(where(is.numeric), ~ round(.x, 2))))

apply_k <- function(d) bind_rows(lapply(POSITIONS, function(ps) { x <- d %>% filter(pos == ps); k <- K[ps, ]
  x %>% mutate(cppg = cred_ppg(x, k["k1"], k["k2"]), cavail = cred_avail(x, k["k3"], k["k4"]),
               Z = n_cur / (n_cur + k["k1"])) }))
bt <- apply_k(bt)
ROLE_ON <- any(sapply(c("ROLE_AVAIL", "QB_START", "ROLE_SNAP"), function(v) exists(v) && isTRUE(get(v))))
if (ROLE_ON) source("rl_dv10.R")   # role layer (Football2_Dynasty_dev): replaces cppg / cavail season by season

# ---------- backtest metrics: PPG and availability ----------
hist_only <- function(d) ifelse(d$g_h > 0, d$ppg_h, d$prior_ppg)
m1 <- bt %>% filter(n_ros >= 3) %>% group_by(pos) %>%
  summarise(n = n(), rmse_current_only = sqrt(weighted.mean((ppg_ros - ppg_cur)^2, n_ros)),
            rmse_history_only = sqrt(weighted.mean((ppg_ros - hist_only(pick(everything())))^2, n_ros)),
            rmse_credibility = sqrt(weighted.mean((ppg_ros - cppg)^2, n_ros)), .groups = "drop")
cat("\nPredicting weeks 10-18 PPG from weeks 1-9 (2016-2025, players with 3+ later games), RMSE:\n"); print(m1 %>% mutate(across(where(is.numeric), ~ round(.x, 3))))
m2 <- bt %>% filter(n_cur >= 2) %>% group_by(pos) %>%
  summarise(n = n(), rmse_current_rate = sqrt(weighted.mean((rate_ros - rate_cur)^2, tg_left)),
            rmse_credibility = sqrt(weighted.mean((rate_ros - cavail)^2, tg_left)),
            mean_pred = mean(cavail), mean_actual = mean(rate_ros), .groups = "drop")
cat("\nPredicting the share of weeks 10-18 games played, RMSE:\n"); print(m2 %>% mutate(across(where(is.numeric), ~ round(.x, 3))))

# ---------- replacement and value ----------
# league replacement lines: fill every team's dedicated slots, then FLEX (RB/WR/TE), then SUPERFLEX (any position),
# greedily by credible PPG; the last player started at each position is its replacement line. The page runs the same in JS.
LG_DEFAULT <- list(teams = 12, qb = 1, rb = 2, wr = 3, te = 1, flex = 0, sf = 1)   # gives QB24 / RB24 / WR36 / TE12
rep_lines <- function(d, lg = LG_DEFAULT) {
  if ("cppg_rep" %in% names(d)) d$cppg <- d$cppg_rep   # role layer: replacement lines stay on the live definition (credible PPG, all games)
  pool <- d %>% filter(n_cur >= MIN_G_REP, !is.na(cppg)) %>% arrange(desc(cppg))
  by <- split(pool$cppg, factor(pool$pos, POSITIONS))
  n <- pmin(c(QB = lg$qb, RB = lg$rb, WR = lg$wr, TE = lg$te) * lg$teams, lengths(by)[POSITIONS])
  take_mixed <- function(ps, k) for (s in seq_len(k)) {
    nxt <- sapply(ps, function(q) if (n[q] < length(by[[q]])) by[[q]][n[q] + 1] else -Inf)
    if (all(!is.finite(nxt))) break; q <- ps[which.max(nxt)]; n[q] <<- n[q] + 1 }
  take_mixed(c("RB", "WR", "TE"), lg$flex * lg$teams); take_mixed(POSITIONS, lg$sf * lg$teams)
  tibble(pos = POSITIONS, rep_ppg = sapply(POSITIONS, function(q) by[[q]][max(n[q], 1)]), n_started = as.integer(n[POSITIONS]))
}
# status tag for the pages: reserve list -> IR, Out, Doubtful, Questionable (Q), depth rank 2+ -> Backup, else ""
# Backup: QBs at depth 2+ or not listed; RB / WR / TE only when listed at depth 3+ (ESPN slot charts make depth 2 and "not listed" noisy for them)
status_tag <- function(cat, pos = rep("QB", length(cat)), depth = rep(NA_integer_, length(cat)), snap = rep(NA_real_, length(cat))) { s <- unname(c(reserve = "IR", out = "Out", doubtful = "Doubtful", questionable = "Q", backup2 = "Backup", backup3 = "Backup")[cat])
  s[cat %in% c("backup2", "backup3") & pos != "QB" & !(coalesce(as.integer(depth), 0L) >= 3 & coalesce(snap, 0) < 0.5)] <- NA; coalesce(s, "") }   # and under half the offensive snaps
# role layer (QB_START): QB appearances that are not starts, expected count x (relief PPG - replacement); 0 otherwise
relief_v <- function(d) if ("relief_g" %in% names(d)) coalesce(d$relief_g, 0) * (coalesce(d$ppg_r, 0) - d$rep_ppg) else 0
value_board <- function(d, lg = NULL) {
  if (!is.null(lg)) return(d %>% left_join(rep_lines(d, lg) %>% select(pos, rep_ppg), by = "pos") %>%
    mutate(por_pg = cppg - rep_ppg, exp_games = tg_left * cavail, value = por_pg * exp_games + relief_v(pick(everything()))))
  if (!"cppg_rep" %in% names(d)) d$cppg_rep <- d$cppg   # role layer: replacement lines stay on the live definition
  rep <- d %>% filter(n_cur >= MIN_G_REP) %>% group_by(pos) %>% arrange(desc(cppg_rep), .by_group = TRUE) %>%
    summarise(rep_ppg = cppg_rep[STARTABLE[pos[1]]], rep_raw = sort(ppg_cur, decreasing = TRUE)[STARTABLE[pos[1]]], .groups = "drop")
  d %>% left_join(rep, by = "pos") %>% mutate(por_pg = cppg - rep_ppg, exp_games = tg_left * cavail, value = por_pg * exp_games + relief_v(pick(everything())))
}
# whole-value backtest: predicted vs actual rest-of-season points over replacement
bv <- bind_rows(lapply(BT_YEARS, function(y) value_board(bt %>% filter(season == y)))) %>%
  mutate(actual = pts_ros - rep_ppg * n_ros, naive = (ppg_cur - rep_ppg) * tg_left)
if (!exists("BT_MIN")) BT_MIN <- 3   # backtest sample: players with BT_MIN+ games by week 9 (live: 3)
st <- bv %>% filter(n_cur >= BT_MIN)
m3 <- st %>% group_by(pos) %>% summarise(n = n(), spearman_model = cor(value, actual, method = "spearman"),
  spearman_naive = cor(naive, actual, method = "spearman"), rmse_model = sqrt(mean((value - actual)^2)),
  rmse_naive = sqrt(mean((naive - actual)^2)), .groups = "drop")
if (exists("EXP_TAG")) { dir.create("exp", showWarnings = FALSE)
  saveRDS(list(bv = bv %>% select(season, player_id, name, pos, n_cur, value, actual, naive, cppg, ppg_ros, n_ros, cavail, rate_ros, tg_left, any_of(c("cat", "depth_rank")))), paste0("exp/dv10_", EXP_TAG, ".rds")) }
cat("\nWhole value, predicted vs actual weeks 10-18 points over replacement (players with 3+ games by week 9):\n")
print(m3 %>% mutate(across(where(is.numeric), ~ round(.x, 3))))

# ---------- 2026 board ----------
s26 <- apply_k(snapshot(CUR))
if (ROLE_ON) s26 <- rl_now(s26)
b26 <- value_board(s26) %>% mutate(age = round(as.numeric(as.Date("2026-09-01") - birth_date) / 365.25, 1)) %>%
  arrange(desc(value)) %>% mutate(rank = row_number()) %>% group_by(pos) %>% mutate(rank_pos = row_number()) %>% ungroup()
reps <- b26 %>% distinct(pos, rep_ppg, rep_raw); cat("\n2026 replacement PPG (credible / raw):\n"); print(reps %>% mutate(across(where(is.numeric), ~ round(.x, 2))))
out <- b26 %>% transmute(rank, rank_pos = paste0(pos, rank_pos), name, pos, team, age, games_2026 = n_cur, ppg_2026 = round(ppg_cur, 2),
  hist_games = g_h, hist_ppg = round(ppg_h, 2), Z_2026 = round(Z, 2), credible_ppg = round(cppg, 2), replacement_ppg = round(rep_ppg, 2),
  por_per_game = round(por_pg, 2), team_games_left = tg_left, avail_rate = round(cavail, 3), exp_games_left = round(exp_games, 2),
  ros_value = round(value, 1), value_100k = round(100000 * pmax(value, 0) / max(max(value), 1e-9)), missed_last2 = missed_last2, player_id,
  status = status_tag(if ("cat" %in% names(b26)) b26$cat else rep(NA, nrow(b26)), b26$pos, if ("depth_rank" %in% names(b26)) b26$depth_rank else NA, if ("snap_season" %in% names(b26)) b26$snap_season else NA))
if (WRITE) if (max(b26$value) > 0) write.csv(out, "dv_ros_2026_board.csv", row.names = FALSE) else
  cat("\nregular season over (no games left): dv_ros_2026_board.csv kept from the last week with games left\n")
if (WRITE) write.csv(K %>% as.data.frame() %>% tibble::rownames_to_column("pos"), "dv_ros_credibility_k.csv", row.names = FALSE)
if (WRITE) write.csv(bind_rows(m1 %>% mutate(test = "ppg"), m2 %>% mutate(test = "availability")), "dv_ros_backtest_parts.csv", row.names = FALSE)
if (WRITE) write.csv(m3, "dv_ros_backtest_value.csv", row.names = FALSE)
options(width = 220)
cat("\nTOP 40, 2026 rest-of-season value:\n")
print(out %>% select(rank, rank_pos, name, team, games_2026, ppg_2026, hist_ppg, Z_2026, credible_ppg, por_per_game, exp_games_left, ros_value, missed_last2) %>% head(40), n = 40)
cat("\nposition mix, top 24 / 50 / 100:\n"); for (k in c(24, 50, 100)) print(table(out$pos[out$rank <= k]))

# objects reused by the multi-season dynasty value (dv_11)
if (WRITE) saveRDS(list(K = K, b26 = b26, ppg_rmse = setNames(m1$rmse_credibility, m1$pos)), "dv_ros_objects.rds")
