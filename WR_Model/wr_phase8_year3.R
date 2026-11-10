# =============================================================================
# WR Model -- Phase 8: year-3 model (end of year 2 -> year 3)
#
# Prediction point: end of the player's NFL year-2 regular season.
# Population: drafted WRs, classes 2013-2024, who played in year 1 or year 2.
#   Training: classes 2013-2023 (year 3 complete through 2025).
#   Scoring: 2024 class for year 3 = 2026; 2023 class for the years 3-4 horizon.
#   No 2026 data is used anywhere (the weekly cache ends with the 2025 season).
#
# Features (copied from Phase 7, computed separately for year 1 and year 2):
#   games, targets, target share, air-yards share, WOPR, PPR, PPR/game, yards per
#   target, snap % (avg and last 6 games), WR finish; year-1 -> year-2 changes in
#   target share, snap % and PPR/game; late-season year-2 target-share trend
#   (weeks 10+ vs 1-9); year-2 team pass attempts; log pick, age at draft, college
#   features. Nothing from the offseason after year 2 (no vacated targets, no
#   free agency), so nothing after the prediction point.
#
# Targets: year-3 WR PPR finish as WR2+ (<= 24) / WR3+ (<= 36) -- nested logistic
#   elastic nets with P(WR2+) <= P(WR3+); year-3 PPR (Gaussian elastic net).
#   Secondary (dynasty horizon): best finish in years 3-4 as WR3+, classes with
#   year 4 complete (<= 2022).
#
# Baselines: pick_only; pick + year-2 PPR; pick + year-1 and year-2 PPR.
#
# Rolling rule: class Y is scored at the end of season Y + 1 (its year 2). Year-3
#   outcomes known then are for classes c with c + 2 <= Y + 1, i.e. c <= Y - 1.
#   Their features (seasons c, c + 1 <= Y) are also known. Train on c <= Y - 1.
#   For the years 3-4 target: c + 3 <= Y + 1, i.e. c <= Y - 2.
#   Test classes 2016-2023. Leave-one-class-out also reported.
#
# Outputs: phase8_cv_metrics.csv, phase8_oof_predictions.csv,
#          phase8_backtest.csv, wr_year3_board.csv
# =============================================================================

suppressMessages({ library(dplyr); library(tidyr); library(glmnet); library(pROC) })
set.seed(2026)
CAPR <- 100; LAST <- 2025

tbl    <- readRDS("wr_model_table.rds")
weekly <- readRDS(file.path("cache", "nfl_weekly_raw.rds")) %>% filter(season_type == "REG", season <= LAST)
snaps  <- readRDS(file.path("cache", "snap_counts_raw.rds")) %>% filter(game_type == "REG", season <= LAST)

season_tot <- weekly %>% group_by(player_id, season) %>%
  summarize(position = first(position), ppr = sum(fantasy_points_ppr, na.rm = TRUE), .groups = "drop")
wr_rank <- season_tot %>% filter(position == "WR") %>% group_by(season) %>%
  mutate(wr_rank = rank(-ppr, ties.method = "min")) %>% ungroup() %>% select(player_id, season, wr_rank, ppr)
team_wk <- weekly %>% group_by(season, week, team) %>%
  summarize(team_tgt = sum(targets, na.rm = TRUE), team_ay = sum(pmax(receiving_air_yards, 0), na.rm = TRUE),
            team_att = sum(attempts, na.rm = TRUE), .groups = "drop")
team_season <- team_wk %>% group_by(season, team) %>% summarize(team_pass_att = sum(team_att), .groups = "drop")

base <- tbl %>% filter(draft_season >= 2013, draft_season <= 2024, !is.na(gsis_id)) %>%
  select(gsis_id, pfr_player_id, pfr_player_name, draft_season, round, pick, draft_team, college,
         log_pick, age_at_draft, final_dominator, breakout_age_filled, career_rec_yds, recruit_rating,
         early_declare, college_matched)

# --- Season usage for NFL year k (copied/adapted from Phase 7) --------------------
usage_year <- function(k) {
  rk <- weekly %>% inner_join(base %>% select(gsis_id, draft_season), by = c("player_id" = "gsis_id")) %>%
    filter(season == draft_season + k - 1) %>% left_join(team_wk, by = c("season", "week", "team"))
  u <- rk %>% group_by(player_id) %>%
    # weekly-level shares first: later lines overwrite `targets` with the season sum
    summarize(ts_early = sum(targets[week < 10], na.rm = TRUE) / pmax(sum(team_tgt[week < 10]), 1),
              ts_late  = sum(targets[week >= 10], na.rm = TRUE) / pmax(sum(team_tgt[week >= 10]), 1),
              games_late = n_distinct(week[week >= 10]),
              ts  = sum(targets, na.rm = TRUE) / pmax(sum(team_tgt), 1),
              ays = sum(pmax(receiving_air_yards, 0), na.rm = TRUE) / pmax(sum(team_ay), 1),
              games = n_distinct(week), targets = sum(targets, na.rm = TRUE),
              rec = sum(receptions, na.rm = TRUE), yds = sum(receiving_yards, na.rm = TRUE),
              ppr = sum(fantasy_points_ppr, na.rm = TRUE),
              team = names(which.max(table(team))), .groups = "drop") %>%
    mutate(ppg = ppr / games, ypt = ifelse(targets > 0, yds / targets, NA),
           wopr = 1.5 * ts + 0.7 * ays,
           ts_trend = ifelse(games_late > 0, ts_late - ts_early, NA))
  sn <- snaps %>% filter(!is.na(pfr_player_id)) %>%
    inner_join(base %>% select(pfr_player_id, draft_season), by = "pfr_player_id") %>%
    filter(season == draft_season + k - 1, offense_snaps > 0 | offense_pct > 0) %>%
    group_by(pfr_player_id) %>% arrange(week, .by_group = TRUE) %>%
    summarize(snap_avg = mean(offense_pct), snap_last6 = mean(tail(offense_pct, 6)), .groups = "drop")
  out <- base %>% select(gsis_id, pfr_player_id, draft_season) %>%
    left_join(u, by = c("gsis_id" = "player_id")) %>%
    left_join(sn, by = "pfr_player_id") %>%
    mutate(season = draft_season + k - 1) %>%
    left_join(wr_rank %>% select(player_id, season, finish = wr_rank), by = c("gsis_id" = "player_id", "season")) %>%
    left_join(team_season %>% rename(team_pass_att = team_pass_att), by = c("season", "team")) %>%
    mutate(played = !is.na(games),
           across(c(games, targets, ppr, ts, ays, wopr), ~ ifelse(played, .x, 0)),
           ppg = ifelse(played, ppg, 0),
           across(c(snap_avg, snap_last6), ~ ifelse(played, .x, 0)),   # no games = no snaps
           finish = pmin(coalesce(finish, CAPR), CAPR),
           season_complete = season <= LAST) %>%
    select(gsis_id, draft_season, played, games, targets, ppr, ppg, ts, ays, wopr, ypt,
           snap_avg, snap_last6, finish, ts_trend, team_pass_att, season_complete)
  names(out)[-(1:2)] <- paste0("y", k, "_", names(out)[-(1:2)])
  out
}
u1 <- usage_year(1); u2 <- usage_year(2)

outcome_year <- function(k) {
  base %>% select(gsis_id, draft_season) %>% mutate(season = draft_season + k - 1) %>%
    left_join(wr_rank, by = c("gsis_id" = "player_id", "season")) %>%
    transmute(gsis_id, draft_season, complete = season <= LAST,
              finish = ifelse(complete, pmin(coalesce(wr_rank, CAPR), CAPR), NA),
              ppr = ifelse(complete, coalesce(ppr, 0), NA)) %>%
    rename_with(~ paste0("o", k, "_", .x), c(complete, finish, ppr))
}
d <- base %>%
  inner_join(u1, by = c("gsis_id", "draft_season")) %>%
  inner_join(u2, by = c("gsis_id", "draft_season")) %>%
  left_join(outcome_year(3), by = c("gsis_id", "draft_season")) %>%
  left_join(outcome_year(4), by = c("gsis_id", "draft_season")) %>%
  filter(y1_played | y2_played, y2_season_complete) %>%
  mutate(d_ts = y2_ts - y1_ts, d_snap = y2_snap_avg - y1_snap_avg, d_ppg = y2_ppg - y1_ppg,
         y_wr2 = as.integer(o3_finish <= 24), y_wr3 = as.integer(o3_finish <= 36),
         best34 = pmin(o3_finish, o4_finish), y34_wr3 = as.integer(best34 <= 36))

train <- d %>% filter(o3_complete, draft_season <= 2023)
cat("players who played in year 1 or 2, by class:\n"); print(table(d$draft_season))
cat("training rows (2013-2023):", nrow(train), " year-3 WR3+:", sum(train$y_wr3), " WR2+:", sum(train$y_wr2), "\n")
cat("years 3-4 horizon rows (2013-2022):", sum(!is.na(train$y34_wr3)), " WR3+:", sum(train$y34_wr3, na.rm = TRUE), "\n")

feats <- c("log_pick", "age_at_draft", "final_dominator", "breakout_age_filled", "career_rec_yds",
           "recruit_rating", "early_declare", "college_matched",
           paste0("y1_", c("games", "targets", "ts", "ays", "wopr", "ppr", "ppg", "ypt", "snap_avg", "snap_last6", "finish")),
           paste0("y2_", c("games", "targets", "ts", "ays", "wopr", "ppr", "ppg", "ypt", "snap_avg", "snap_last6",
                           "finish", "ts_trend", "team_pass_att")),
           "d_ts", "d_snap", "d_ppg")
prep_fit <- function(tr) {
  med <- sapply(feats, function(v) median(as.numeric(tr[[v]]), na.rm = TRUE)); med[is.na(med)] <- 0
  list(med = med, flag = feats[sapply(feats, function(v) any(is.na(tr[[v]])))])
}
prep_apply <- function(p, x) {
  m <- sapply(feats, function(v) { z <- as.numeric(x[[v]]); z[is.na(z)] <- p$med[v]; z })
  if (is.null(dim(m))) m <- matrix(m, nrow = 1, dimnames = list(NULL, feats))
  if (length(p$flag)) {
    fl <- sapply(p$flag, function(v) as.integer(is.na(x[[v]])))
    if (is.null(dim(fl))) fl <- matrix(fl, nrow = 1)
    colnames(fl) <- paste0("na_", p$flag); m <- cbind(m, fl)
  }
  m
}
baselines <- list(pick = "~ log_pick", y2pts = "~ log_pick + y2_ppr", y12pts = "~ log_pick + y1_ppr + y2_ppr")

predict_all <- function(tr, te, horizon34 = FALSE) {
  o <- data.frame(row.names = seq_len(nrow(te)))
  if (horizon34) {
    tr <- filter(tr, !is.na(y34_wr3))
    for (b in names(baselines))
      o[[paste0(b, "_p34")]] <- predict(glm(as.formula(paste("y34_wr3", baselines[[b]])), binomial, tr), te, type = "response")
  } else {
    for (b in names(baselines)) {
      o[[paste0(b, "_p3")]]  <- predict(glm(as.formula(paste("y_wr3", baselines[[b]])), binomial, tr), te, type = "response")
      o[[paste0(b, "_p2")]]  <- pmin(predict(glm(as.formula(paste("y_wr2", baselines[[b]])), binomial, tr), te, type = "response"),
                                     o[[paste0(b, "_p3")]])
      o[[paste0(b, "_ppr")]] <- pmax(0, predict(lm(as.formula(paste("o3_ppr", baselines[[b]])), tr), te))
    }
  }
  p <- prep_fit(tr); Xtr <- prep_apply(p, tr); Xte <- prep_apply(p, te)
  folds <- as.integer(factor(tr$draft_season))
  if (max(folds) < 4) folds <- sample(rep(1:5, length.out = nrow(tr)))
  en <- function(y, fam) {
    f <- cv.glmnet(Xtr, y, family = fam, alpha = 0.5, foldid = folds)
    as.numeric(predict(f, Xte, s = "lambda.min", type = "response"))
  }
  if (horizon34) { o$use_p34 <- en(tr$y34_wr3, "binomial"); return(o) }
  o$use_p3 <- en(tr$y_wr3, "binomial")
  o$use_p2 <- pmin(en(tr$y_wr2, "binomial"), o$use_p3)
  o$use_ppr <- pmax(0, en(tr$o3_ppr, "gaussian"))
  o
}

# --- Validation -----------------------------------------------------------------
keep <- c("draft_season", "round", "pick", "pfr_player_name", "y1_finish", "y2_finish", "y2_ppr",
          "y2_ts", "d_ts", "d_snap", "o3_finish", "o3_ppr", "y_wr2", "y_wr3", "y34_wr3")
run_cv <- function(scheme) {
  res <- list()
  tests <- if (scheme == "LOCO") 2013:2023 else 2016:2023
  for (Y in tests) {
    tr <- if (scheme == "LOCO") filter(train, draft_season != Y) else filter(train, draft_season <= Y - 1)
    te <- filter(train, draft_season == Y)
    if (scheme == "Rolling") stopifnot(max(tr$draft_season) + 2 <= Y + 1)
    o <- cbind(te[, keep], scheme = scheme, ntrain = nrow(tr), predict_all(tr, te))
    # years 3-4 horizon: rolling rule c <= Y - 2
    tr34 <- if (scheme == "LOCO") tr else filter(train, draft_season <= Y - 2)
    if (sum(!is.na(tr34$y34_wr3)) > 30 && any(!is.na(te$y34_wr3)))
      o <- cbind(o, predict_all(tr34, te, horizon34 = TRUE))
    res[[length(res) + 1]] <- o
  }
  bind_rows(res)
}
oof <- bind_rows(run_cv("LOCO"), run_cv("Rolling"))
write.csv(oof, "phase8_oof_predictions.csv", row.names = FALSE)
cat("\nrolling training sizes:\n")
print(as.data.frame(oof %>% filter(scheme == "Rolling") %>% distinct(draft_season, ntrain)), row.names = FALSE)

aucf <- function(y, p) { ok <- !is.na(y) & !is.na(p); if (length(unique(y[ok])) < 2) NA else as.numeric(auc(roc(y[ok], p[ok], quiet = TRUE))) }
mlab <- c(pick = "pick_only", y2pts = "pick+y2_ppr", y12pts = "pick+y1+y2_ppr", use = "usage_enet")
metric_rows <- function(o) bind_rows(lapply(names(mlab), function(m) {
  p3 <- o[[paste0(m, "_p3")]]; p2 <- o[[paste0(m, "_p2")]]; pp <- o[[paste0(m, "_ppr")]]
  data.frame(model = mlab[m], n = nrow(o), AUC_WR3 = aucf(o$y_wr3, p3), Brier_WR3 = mean((p3 - o$y_wr3)^2),
             AUC_WR2 = aucf(o$y_wr2, p2), Brier_WR2 = mean((p2 - o$y_wr2)^2),
             Spearman_PPR = cor(pp, o$o3_ppr, method = "spearman"), RMSE_PPR = sqrt(mean((pp - o$o3_ppr)^2)))
}))
metrics <- bind_rows(lapply(c("Rolling", "LOCO"), function(s) cbind(scheme = s, metric_rows(filter(oof, scheme == s))))) %>%
  mutate(across(where(is.double), ~ round(.x, 4)))
cat("\n===== Year-3 model: cross-validated performance =====\n"); print(metrics, row.names = FALSE)
write.csv(metrics, "phase8_cv_metrics.csv", row.names = FALSE)

h34 <- oof %>% filter(!is.na(use_p34), !is.na(y34_wr3))
cat("\n===== Years 3-4 horizon (best finish WR3+), classes with year 4 complete =====\n")
print(as.data.frame(h34 %>% group_by(scheme) %>% summarize(n = n(), hits = sum(y34_wr3),
  AUC_pick = aucf(y34_wr3, pick_p34), AUC_y2pts = aucf(y34_wr3, y2pts_p34), AUC_y12pts = aucf(y34_wr3, y12pts_p34),
  AUC_usage = aucf(y34_wr3, use_p34),
  Brier_pick = mean((pick_p34 - y34_wr3)^2), Brier_y12pts = mean((y12pts_p34 - y34_wr3)^2),
  Brier_usage = mean((use_p34 - y34_wr3)^2), .groups = "drop") %>% mutate(across(where(is.double), ~ round(.x, 4)))),
  row.names = FALSE)

set.seed(2026)
r <- filter(oof, scheme == "Rolling")
bt <- function(f) {
  pt <- f(seq_len(nrow(r))); dd <- replicate(2000, f(sample.int(nrow(r), replace = TRUE)))
  sprintf("%+.4f  95%% CI [%+.4f, %+.4f]  share < 0: %.3f", pt, quantile(dd, .025), quantile(dd, .975), mean(dd < 0))
}
br <- function(p, y) mean((p - y)^2); rm_ <- function(p, y) sqrt(mean((p - y)^2))
cat("\n===== Bootstrap, rolling origin (2000 draws, seed 2026; negative = usage better) =====\n")
for (b in c("pick", "y2pts", "y12pts")) {
  cat(sprintf("vs %-15s Brier WR3+: %s\n", mlab[b], bt(function(i) br(r$use_p3[i], r$y_wr3[i]) - br(r[[paste0(b, "_p3")]][i], r$y_wr3[i]))))
  cat(sprintf("vs %-15s Brier WR2+: %s\n", mlab[b], bt(function(i) br(r$use_p2[i], r$y_wr2[i]) - br(r[[paste0(b, "_p2")]][i], r$y_wr2[i]))))
  cat(sprintf("vs %-15s RMSE PPR:   %s\n", mlab[b], bt(function(i) rm_(r$use_ppr[i], r$o3_ppr[i]) - rm_(r[[paste0(b, "_ppr")]][i], r$o3_ppr[i]))))
}

# --- Back-test: outside top-36 in year 2 ------------------------------------------
sub <- filter(r, y2_finish > 36)
cat("\n===== Outside top-36 in year 2 | rolling 2016-2023 |", nrow(sub), "players,", sum(sub$y_wr3),
    "reached WR3+ in year 3 =====\n")
topk <- function(col, k) sub %>% group_by(draft_season) %>% arrange(desc(.data[[col]]), pick, .by_group = TRUE) %>%
  slice_head(n = k) %>% summarize(hits = sum(y_wr3), names = paste(pfr_player_name[y_wr3 == 1], collapse = ", "), .groups = "drop")
bt_rows <- list()
for (k in c(5, 10)) {
  rnd <- sub %>% group_by(draft_season) %>% summarize(e = min(k, n()) * mean(y_wr3), .groups = "drop")
  a <- topk("use_p3", k); b <- topk("y2pts_p3", k); c12 <- topk("y12pts_p3", k); pk <- topk("pick_p3", k)
  row <- data.frame(k = k, usage = sum(a$hits), y2_points = sum(b$hits), y1y2_points = sum(c12$hits),
                    pick_only = sum(pk$hits), random_expected = round(sum(rnd$e), 1))
  bt_rows[[length(bt_rows) + 1]] <- row; print(row, row.names = FALSE)
  cat(" usage top", k, "hits:    ", paste(a$draft_season[a$hits > 0], a$names[a$hits > 0], sep = ": ", collapse = " | "), "\n")
  cat(" y2-points top", k, "hits:", paste(b$draft_season[b$hits > 0], b$names[b$hits > 0], sep = ": ", collapse = " | "), "\n")
}
cat(" all hits:", paste0(sub$pfr_player_name[sub$y_wr3 == 1], " (", sub$draft_season[sub$y_wr3 == 1],
                         ", yr2 WR", sub$y2_finish[sub$y_wr3 == 1], " -> yr3 WR", sub$o3_finish[sub$y_wr3 == 1], ")",
                         collapse = ", "), "\n")
write.csv(bind_rows(bt_rows), "phase8_backtest.csv", row.names = FALSE)

# --- Board: 2024 class for 2026 (year 3); 2023 class for years 3-4 ----------------
s24 <- d %>% filter(draft_season == 2024)
f24 <- predict_all(train, s24)
board <- bind_cols(s24 %>% select(pfr_player_name, draft_season, round, pick, draft_team,
                                  y1_games, y1_targets, y1_ts, y1_snap_avg, y1_ppr, y1_finish,
                                  y2_games, y2_targets, y2_ts, y2_ays, y2_snap_avg, y2_snap_last6, y2_ppr, y2_ppg,
                                  y2_finish, y2_ts_trend, d_ts, d_snap, d_ppg), f24) %>%
  mutate(horizon = "year 3 (2026)")
s23 <- d %>% filter(draft_season == 2023)
f23 <- predict_all(filter(train, !is.na(y34_wr3)), s23, horizon34 = TRUE)
board23 <- bind_cols(s23 %>% select(pfr_player_name, draft_season, round, pick, draft_team, y1_finish, y2_finish,
                                    y2_ppr, d_ts, d_snap, year3_finish_actual = o3_finish), f23) %>%
  mutate(horizon = "best of years 3-4 (2025-26); year 3 already known")
board <- board %>%
  mutate(usage_edge_wr3 = use_p3 - y2pts_p3,
         buy_low = use_p3 >= 0.25 & y2_finish > 36 & (d_ts > 0 | d_snap > 0) & usage_edge_wr3 > 0) %>%
  bind_rows(board23) %>%
  mutate(across(where(is.double), ~ round(.x, 3))) %>%
  arrange(desc(draft_season), desc(coalesce(use_p3, use_p34)))
write.csv(board, "wr_year3_board.csv", row.names = FALSE)

cat("\n===== 2024 class: top 15 by P(WR3+ in 2026) =====\n")
print(as.data.frame(board %>% filter(draft_season == 2024) %>% head(15) %>%
  select(pfr_player_name, pick, y1_ts, y1_finish, y2_targets, y2_ts, y2_snap_avg, y2_ppr, y2_finish, d_ts, d_snap,
         use_p3, use_p2, use_ppr, y2pts_p3)), row.names = FALSE)
cat("\n===== 2024 buy-low: P(WR3+) >= 25%, outside top-36 in year 2, rising target share or snaps =====\n")
print(as.data.frame(board %>% filter(draft_season == 2024, buy_low) %>% arrange(desc(usage_edge_wr3)) %>%
  select(pfr_player_name, pick, y2_games, y2_ts, y2_snap_avg, y2_snap_last6, y2_ts_trend, d_ts, d_snap, y2_ppr,
         y2_finish, use_p3, y2pts_p3, usage_edge_wr3)), row.names = FALSE)
cat("\n===== 2023 class: P(WR3+ best of years 3-4), top 10 (year 3 = 2025 already happened) =====\n")
print(as.data.frame(board %>% filter(draft_season == 2023) %>% head(10) %>%
  select(pfr_player_name, pick, y1_finish, y2_finish, use_p34, y12pts_p34, year3_finish_actual)), row.names = FALSE)

cmp_names <- c("Malik Nabers", "Brian Thomas", "Marvin Harrison Jr.", "Ladd McConkey", "Rome Odunze", "Xavier Worthy")
p7 <- read.csv("wr_year2_breakout_board.csv") %>% filter(draft_season == 2024) %>%
  select(pfr_player_name, p7_p_wr3_yrs23 = p_wr3_usage, p7_p_wr2_yrs23 = p_wr2_usage)
cat("\n===== Phase 7 (rookie features, best of yrs 2-3) vs Phase 8 (yr-1+2 features, year 3 only) =====\n")
print(as.data.frame(board %>% filter(draft_season == 2024, pfr_player_name %in% cmp_names) %>%
  select(pfr_player_name, y1_finish, y2_finish, y2_games, p8_p_wr3_yr3 = use_p3, p8_p_wr2_yr3 = use_p2) %>%
  left_join(p7, by = "pfr_player_name")), row.names = FALSE)
cat("\nsaved phase8_cv_metrics.csv, phase8_oof_predictions.csv, phase8_backtest.csv, wr_year3_board.csv\n")
