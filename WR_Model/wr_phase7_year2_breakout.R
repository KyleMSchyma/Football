# =============================================================================
# WR Model -- Phase 7: year-2 breakout model (rookie usage -> years 2-3)
#
# Question: once a WR's ROOKIE regular season is over, how likely is a WR2+/WR3+
# season in NFL years 2-3, and how many PPR points will he score in years 2-3?
#
# Population: drafted WRs, classes 2013-2024, who played >= 1 regular-season game
#   as rookies. (Snap counts in nflreadr start in 2013, not 2012.)
#   Training: classes 2013-2023 (years 2-3 complete through 2025).
#   Scoring: 2025 class (years 2-3 = 2026-27) and 2024 class (year 3 = 2026).
#
# Features -- all known at the END of the rookie regular season:
#   rookie usage (weekly stats): games, targets, receptions, yards, PPR, PPR/game,
#     yards/target, catch rate, target share, air-yards share, WOPR (computed from
#     team totals in the games he played), rookie WR finish, late-season target
#     share (weeks 10+) and trend vs weeks 1-9
#   snaps (load_snap_counts, joined by pfr_player_id): average offense snap %,
#     average over his last 6 games, games with 50%+ snaps
#   team context: team pass attempts in the rookie season
#   draft/college: log pick, age at draft, final dominator, breakout age, career
#     receiving yards, recruiting rating, early declare, college matched
#   NOT used: vacated targets entering year 2 -- departures happen in the
#     offseason, after the prediction point, so using them would leak.
#
# Targets: best WR PPR finish in years 2-3 (unranked/none = 100) as WR2+ (<= 24)
#   and WR3+ (<= 36); total PPR in years 2-3 (0 if he didn't play).
#
# Models:
#   pick_only   logistic / linear on log pick
#   rookie_pts  log pick + rookie PPR total (naive "he already produced" baseline)
#   usage       elastic net (alpha 0.5, inner CV grouped by class) on all
#               features; separate logistic fits for WR2+ and WR3+ forced to
#               P(WR2+) <= P(WR3+); Gaussian elastic net for PPR
#   In-fold preprocessing: median imputation + missing flags fit on training rows.
#
# Validation:
#   rolling origin -- test class Y (2016-2023) is scored right after its rookie
#     season (end of season Y). The only outcomes known then are for classes whose
#     year 3 has finished: class C with C + 2 <= Y. So train on classes <= Y - 2.
#     Rookie-season features of the training classes are from seasons <= Y - 2,
#     also known. Nothing from season Y+1 or later is used.
#   leave-one-class-out over 2013-2023 for comparison.
#
# Outputs: phase7_cv_metrics.csv, phase7_oof_predictions.csv,
#          phase7_hidden_talent_backtest.csv, wr_year2_breakout_board.csv
# =============================================================================

suppressMessages({ library(dplyr); library(tidyr); library(glmnet); library(pROC) })
set.seed(2026)
CAPR <- 100

tbl    <- readRDS("wr_model_table.rds")
weekly <- readRDS(file.path("cache", "nfl_weekly_raw.rds")) %>% filter(season_type == "REG")
snaps  <- readRDS(file.path("cache", "snap_counts_raw.rds")) %>% filter(game_type == "REG")

# --- Season WR ranks (same as Phases 2/5) --------------------------------------
season_tot <- weekly %>% group_by(player_id, season) %>%
  summarize(position = first(position), ppr = sum(fantasy_points_ppr, na.rm = TRUE), .groups = "drop")
wr_rank <- season_tot %>% filter(position == "WR") %>% group_by(season) %>%
  mutate(wr_rank = rank(-ppr, ties.method = "min")) %>% ungroup() %>% select(player_id, season, wr_rank, ppr)

# --- Team weekly totals for shares ---------------------------------------------
team_wk <- weekly %>% group_by(season, week, team) %>%
  summarize(team_tgt = sum(targets, na.rm = TRUE), team_ay = sum(pmax(receiving_air_yards, 0), na.rm = TRUE),
            team_att = sum(attempts, na.rm = TRUE), .groups = "drop")
team_season <- team_wk %>% group_by(season, team) %>% summarize(team_pass_att = sum(team_att), .groups = "drop")

base <- tbl %>% filter(draft_season >= 2013, draft_season <= 2025) %>%
  select(gsis_id, pfr_player_id, pfr_player_name, draft_season, round, pick, draft_team, college,
         log_pick, age_at_draft, final_dominator, breakout_age_filled, career_rec_yds, recruit_rating,
         early_declare, college_matched)

# --- Rookie-season usage --------------------------------------------------------
rk <- weekly %>% inner_join(base %>% filter(!is.na(gsis_id)) %>% select(gsis_id, draft_season), by = c("player_id" = "gsis_id")) %>%
  filter(season == draft_season) %>%
  left_join(team_wk, by = c("season", "week", "team"))
rookie <- rk %>% group_by(player_id) %>%
  summarize(r_games = n_distinct(week), r_targets = sum(targets, na.rm = TRUE),
            r_rec = sum(receptions, na.rm = TRUE), r_yds = sum(receiving_yards, na.rm = TRUE),
            r_ppr = sum(fantasy_points_ppr, na.rm = TRUE),
            r_ts  = sum(targets, na.rm = TRUE) / pmax(sum(team_tgt), 1),
            r_ays = sum(pmax(receiving_air_yards, 0), na.rm = TRUE) / pmax(sum(team_ay), 1),
            r_ts_early = sum(targets[week < 10], na.rm = TRUE) / pmax(sum(team_tgt[week < 10]), 1),
            r_ts_late  = sum(targets[week >= 10], na.rm = TRUE) / pmax(sum(team_tgt[week >= 10]), 1),
            r_games_late = n_distinct(week[week >= 10]),
            r_team = names(which.max(table(team))), .groups = "drop") %>%
  mutate(r_ppg = r_ppr / r_games, r_ypt = ifelse(r_targets > 0, r_yds / r_targets, NA),
         r_catch = ifelse(r_targets > 0, r_rec / r_targets, NA),
         r_wopr = 1.5 * r_ts + 0.7 * r_ays,
         r_ts_late = ifelse(r_games_late > 0, r_ts_late, NA),
         r_ts_trend = r_ts_late - r_ts_early)

sn <- snaps %>% filter(!is.na(pfr_player_id)) %>%
  inner_join(base %>% select(pfr_player_id, draft_season), by = "pfr_player_id") %>%
  filter(season == draft_season, offense_snaps > 0 | offense_pct > 0) %>%
  group_by(pfr_player_id) %>% arrange(week, .by_group = TRUE) %>%
  summarize(r_snap_avg = mean(offense_pct), r_snap_last6 = mean(tail(offense_pct, 6)),
            r_games50 = sum(offense_pct >= 0.5), .groups = "drop")

# --- Outcomes, years 2-3 ----------------------------------------------------------
out <- base %>% select(gsis_id, draft_season) %>% crossing(nfl_year = 2:3) %>%
  mutate(season = draft_season + nfl_year - 1) %>% filter(season <= 2025) %>%
  left_join(wr_rank, by = c("gsis_id" = "player_id", "season")) %>%
  mutate(finish = pmin(coalesce(wr_rank, CAPR), CAPR), ppr = coalesce(ppr, 0)) %>%
  group_by(gsis_id, draft_season) %>%
  summarize(n_obs = n(), y2_finish = finish[nfl_year == 2][1], y3_finish = finish[nfl_year == 3][1],
            best_23 = min(finish), ppr_23 = sum(ppr), .groups = "drop")

d <- base %>%
  inner_join(rookie, by = c("gsis_id" = "player_id")) %>%                 # played as a rookie
  left_join(sn, by = "pfr_player_id") %>%
  left_join(wr_rank %>% select(player_id, season, r_finish = wr_rank),
            by = c("gsis_id" = "player_id", "draft_season" = "season")) %>%
  left_join(team_season, by = c("draft_season" = "season", "r_team" = "team")) %>%
  left_join(out, by = c("gsis_id", "draft_season")) %>%
  mutate(r_finish = pmin(coalesce(r_finish, CAPR), CAPR),
         complete = !is.na(n_obs) & n_obs == 2,
         y_wr2 = as.integer(best_23 <= 24), y_wr3 = as.integer(best_23 <= 36))

train <- d %>% filter(complete, draft_season <= 2023)
cat("rookies who played, by class:\n"); print(table(d$draft_season))
cat("snap data matched:", round(100 * mean(!is.na(d$r_snap_avg)), 1), "% of rookies\n")
cat("training rows (2013-2023):", nrow(train), " WR3+ in yrs 2-3:", sum(train$y_wr3),
    " WR2+:", sum(train$y_wr2), "\n")
print(as.data.frame(train %>% mutate(day = ifelse(round <= 3, "R1-3", "R4-7")) %>% group_by(day) %>%
  summarize(n = n(), WR3plus = sum(y_wr3), WR2plus = sum(y_wr2), mean_ppr_23 = round(mean(ppr_23)), .groups = "drop")),
  row.names = FALSE)

feats <- c("log_pick", "age_at_draft", "final_dominator", "breakout_age_filled", "career_rec_yds",
           "recruit_rating", "early_declare", "college_matched",
           "r_games", "r_targets", "r_rec", "r_yds", "r_ppr", "r_ppg", "r_ypt", "r_catch",
           "r_ts", "r_ays", "r_wopr", "r_ts_late", "r_ts_trend", "r_finish",
           "r_snap_avg", "r_snap_last6", "r_games50", "team_pass_att")

prep_fit <- function(tr) {
  med <- sapply(feats, function(v) median(as.numeric(tr[[v]]), na.rm = TRUE))
  med[is.na(med)] <- 0
  list(med = med, flag = feats[sapply(feats, function(v) any(is.na(tr[[v]])))])
}
prep_apply <- function(p, x) {
  m <- sapply(feats, function(v) { z <- as.numeric(x[[v]]); z[is.na(z)] <- p$med[v]; z })
  if (is.null(dim(m))) m <- matrix(m, nrow = 1, dimnames = list(NULL, feats))
  fl <- sapply(p$flag, function(v) as.integer(is.na(x[[v]])))
  if (length(p$flag)) { if (is.null(dim(fl))) fl <- matrix(fl, nrow = 1); colnames(fl) <- paste0("na_", p$flag); m <- cbind(m, fl) }
  m
}

predict_all <- function(tr, te) {
  o <- data.frame(row.names = seq_len(nrow(te)))
  # pick-only
  o$pick_p3 <- predict(glm(y_wr3 ~ log_pick, binomial, tr), te, type = "response")
  o$pick_p2 <- pmin(predict(glm(y_wr2 ~ log_pick, binomial, tr), te, type = "response"), o$pick_p3)
  o$pick_ppr <- pmax(0, predict(lm(ppr_23 ~ log_pick, tr), te))
  # rookie points baseline
  o$rpts_p3 <- predict(glm(y_wr3 ~ log_pick + r_ppr, binomial, tr), te, type = "response")
  o$rpts_p2 <- pmin(predict(glm(y_wr2 ~ log_pick + r_ppr, binomial, tr), te, type = "response"), o$rpts_p3)
  o$rpts_ppr <- pmax(0, predict(lm(ppr_23 ~ log_pick + r_ppr, tr), te))
  # usage elastic net
  p <- prep_fit(tr); Xtr <- prep_apply(p, tr); Xte <- prep_apply(p, te)
  folds <- as.integer(factor(tr$draft_season))
  if (max(folds) < 4) folds <- sample(rep(1:5, length.out = nrow(tr)))   # too few classes: random 5-fold
  en <- function(y, fam) {
    f <- cv.glmnet(Xtr, y, family = fam, alpha = 0.5, foldid = folds)
    as.numeric(predict(f, Xte, s = "lambda.min", type = "response"))
  }
  o$use_p3 <- en(tr$y_wr3, "binomial")
  o$use_p2 <- pmin(en(tr$y_wr2, "binomial"), o$use_p3)
  o$use_ppr <- pmax(0, en(tr$ppr_23, "gaussian"))
  o
}

# --- Validation -----------------------------------------------------------------
run_cv <- function(scheme) {
  res <- list()
  tests <- if (scheme == "LOCO") 2013:2023 else 2016:2023
  for (Y in tests) {
    tr <- if (scheme == "LOCO") filter(train, draft_season != Y) else filter(train, draft_season <= Y - 2)
    te <- filter(train, draft_season == Y)
    if (scheme == "Rolling") stopifnot(max(tr$draft_season) + 2 <= Y)
    res[[length(res) + 1]] <- cbind(te %>% select(draft_season, round, pick, pfr_player_name, r_ppr, r_finish,
                                                  r_ts, r_snap_avg, best_23, y_wr2, y_wr3, ppr_23),
                                    scheme = scheme, ntrain = nrow(tr), predict_all(tr, te))
  }
  bind_rows(res)
}
oof <- bind_rows(run_cv("LOCO"), run_cv("Rolling"))
write.csv(oof, "phase7_oof_predictions.csv", row.names = FALSE)
cat("\nrolling training sizes:\n")
print(oof %>% filter(scheme == "Rolling") %>% distinct(draft_season, ntrain) %>% as.data.frame(), row.names = FALSE)

aucf <- function(y, p) if (length(unique(y)) < 2 || sd(p) == 0) NA else as.numeric(auc(roc(y, p, quiet = TRUE)))
metric_rows <- function(o) bind_rows(lapply(c("pick", "rpts", "use"), function(m) {
  p3 <- o[[paste0(m, "_p3")]]; p2 <- o[[paste0(m, "_p2")]]; pp <- o[[paste0(m, "_ppr")]]
  data.frame(model = c(pick = "pick_only", rpts = "pick+rookie_pts", use = "usage_enet")[m],
             n = nrow(o), AUC_WR3 = aucf(o$y_wr3, p3), Brier_WR3 = mean((p3 - o$y_wr3)^2),
             AUC_WR2 = aucf(o$y_wr2, p2), Brier_WR2 = mean((p2 - o$y_wr2)^2),
             Spearman_PPR = cor(pp, o$ppr_23, method = "spearman"),
             RMSE_PPR = sqrt(mean((pp - o$ppr_23)^2)))
}))
metrics <- bind_rows(lapply(c("Rolling", "LOCO"), function(s)
  cbind(scheme = s, metric_rows(filter(oof, scheme == s))))) %>%
  mutate(across(where(is.double), ~ round(.x, 4)))
cat("\n===== Year-2 breakout: cross-validated performance =====\n")
print(metrics, row.names = FALSE)
write.csv(metrics, "phase7_cv_metrics.csv", row.names = FALSE)

set.seed(2026)
r <- filter(oof, scheme == "Rolling")
bt <- function(f) {
  pt <- f(seq_len(nrow(r)))
  dd <- replicate(2000, f(sample.int(nrow(r), replace = TRUE)))
  sprintf("%+.4f  95%% CI [%+.4f, %+.4f]  share < 0: %.3f", pt, quantile(dd, .025), quantile(dd, .975), mean(dd < 0))
}
br <- function(p, y) mean((p - y)^2); rm_ <- function(p, y) sqrt(mean((p - y)^2))
cat("\n===== Bootstrap, rolling origin (2000 draws, seed 2026; negative = usage better) =====\n")
cat("Brier WR3+ usage - pick_only:  ", bt(function(i) br(r$use_p3[i], r$y_wr3[i]) - br(r$pick_p3[i], r$y_wr3[i])), "\n")
cat("Brier WR3+ usage - rookie_pts: ", bt(function(i) br(r$use_p3[i], r$y_wr3[i]) - br(r$rpts_p3[i], r$y_wr3[i])), "\n")
cat("Brier WR2+ usage - pick_only:  ", bt(function(i) br(r$use_p2[i], r$y_wr2[i]) - br(r$pick_p2[i], r$y_wr2[i])), "\n")
cat("Brier WR2+ usage - rookie_pts: ", bt(function(i) br(r$use_p2[i], r$y_wr2[i]) - br(r$rpts_p2[i], r$y_wr2[i])), "\n")
cat("RMSE PPR   usage - pick_only:  ", bt(function(i) rm_(r$use_ppr[i], r$ppr_23[i]) - rm_(r$pick_ppr[i], r$ppr_23[i])), "\n")
cat("RMSE PPR   usage - rookie_pts: ", bt(function(i) rm_(r$use_ppr[i], r$ppr_23[i]) - rm_(r$rpts_ppr[i], r$ppr_23[i])), "\n")
cat("Brier WR3+ rookie_pts - pick_only:", bt(function(i) br(r$rpts_p3[i], r$y_wr3[i]) - br(r$pick_p3[i], r$y_wr3[i])), "\n")

# --- Hidden-talent back-test (rolling) --------------------------------------------
topk_hits <- function(sub, col, k) {
  sub %>% group_by(draft_season) %>% arrange(desc(.data[[col]]), pick, .by_group = TRUE) %>%
    slice_head(n = k) %>%
    summarize(hits = sum(y_wr3), names = paste(pfr_player_name[y_wr3 == 1], collapse = ", "), .groups = "drop")
}
ht_rows <- list()
for (sname in c("Day 3 (rounds 4-7)", "outside top-48 as rookie")) {
  sub <- if (sname == "Day 3 (rounds 4-7)") filter(r, round >= 4) else filter(r, r_finish > 48)
  cat("\n=====", sname, "| rolling 2016-2023 |", nrow(sub), "players,", sum(sub$y_wr3), "reached WR3+ in yrs 2-3 =====\n")
  for (k in c(5, 10)) {
    rnd <- sub %>% group_by(draft_season) %>% summarize(e = min(k, n()) * mean(y_wr3), .groups = "drop")
    a <- topk_hits(sub, "use_p3", k); b <- topk_hits(sub, "rpts_p3", k); cpk <- topk_hits(sub, "pick_p3", k)
    row <- data.frame(subset = sname, k = k, usage = sum(a$hits), rookie_pts = sum(b$hits),
                      pick_only = sum(cpk$hits), random_expected = round(sum(rnd$e), 1))
    ht_rows[[length(ht_rows) + 1]] <- row
    print(row, row.names = FALSE)
    cat(" usage top", k, "hits:     ", paste(a$draft_season[a$hits > 0], a$names[a$hits > 0], sep = ": ", collapse = " | "), "\n")
    cat(" rookie-pts top", k, "hits:", paste(b$draft_season[b$hits > 0], b$names[b$hits > 0], sep = ": ", collapse = " | "), "\n")
  }
  cat(" all WR3+ hits in this subset:", paste(sub$pfr_player_name[sub$y_wr3 == 1], " (", sub$draft_season[sub$y_wr3 == 1], ")", sep = "", collapse = ", "), "\n")
}
write.csv(bind_rows(ht_rows), "phase7_hidden_talent_backtest.csv", row.names = FALSE)

known <- c("Puka Nacua", "Amon-Ra St. Brown", "Darnell Mooney", "Hunter Renfrow", "Tyreek Hill",
           "Gabe Davis", "Romeo Doubs")
kr <- r %>% group_by(draft_season) %>%
  mutate(n_class = n(), rank_usage = rank(-use_p3, ties.method = "min"),
         rank_rookie_pts = rank(-rpts_p3, ties.method = "min"), rank_pick = rank(pick)) %>%
  ungroup() %>% filter(pfr_player_name %in% known) %>%
  select(draft_season, pick, pfr_player_name, r_finish, r_ts, r_snap_avg, best_23,
         use_p3, rpts_p3, n_class, rank_usage, rank_rookie_pts, rank_pick) %>%
  mutate(across(c(use_p3, rpts_p3, r_ts, r_snap_avg), ~ round(.x, 3)))
cat("\n===== Known names: rank within their class's rookies (rolling origin, by P(WR3+)) =====\n")
print(as.data.frame(kr), row.names = FALSE)
cat("(Nacua was already WR", kr$r_finish[kr$pfr_player_name == "Puka Nacua"],
    "as a rookie, so he is not a 'hidden' case for this model)\n")

# --- Year-2-only check: 2024 class, trained on classes <= 2022 (rolling rule) ----
c24 <- d %>% filter(draft_season == 2024)
tr22 <- filter(train, draft_season <= 2022)
p24 <- predict_all(tr22, c24)
y2_wr3 <- as.integer(c24$y2_finish <= 36)
cat("\n===== Year-2-only check, 2024 class (n =", nrow(c24), ", trained on <= 2022) =====\n")
cat("actual WR3+ in year 2 (2025):", sum(y2_wr3, na.rm = TRUE), "\n")
for (m in c("pick", "rpts", "use"))
  cat(sprintf("%-5s AUC for year-2 WR3+: %.3f   Brier: %.4f\n", m, aucf(y2_wr3, p24[[paste0(m, "_p3")]]),
              mean((p24[[paste0(m, "_p3")]] - y2_wr3)^2)))

# --- Final fit (2013-2023) and board --------------------------------------------
sc <- d %>% filter(draft_season %in% c(2024, 2025))
pf <- predict_all(train, sc)
board <- bind_cols(sc %>% select(pfr_player_name, draft_season, round, pick, draft_team, college,
                                 r_games, r_targets, r_rec, r_yds, r_ppr, r_ppg, r_finish, r_ts, r_ays, r_wopr,
                                 r_ts_late, r_ts_trend, r_snap_avg, r_snap_last6, r_games50, team_pass_att,
                                 y2_finish_actual = y2_finish),
                   pf) %>%
  mutate(across(c(r_ppr, r_ppg, r_ts, r_ays, r_wopr, r_ts_late, r_ts_trend, r_snap_avg, r_snap_last6,
                  pick_p3, pick_p2, rpts_p3, rpts_p2, use_p3, use_p2), ~ round(.x, 3)),
         across(c(pick_ppr, rpts_ppr, use_ppr), ~ round(.x, 1)),
         y2_finish_actual = ifelse(draft_season == 2024, y2_finish_actual, NA),
         usage_edge_wr3 = round(use_p3 - rpts_p3, 3),
         buy_low = draft_season == 2025 & r_finish > 48 & use_p3 >= 0.15 & usage_edge_wr3 > 0) %>%
  rename(p_wr3_pick_only = pick_p3, p_wr2_pick_only = pick_p2, ppr23_pick_only = pick_ppr,
         p_wr3_rookie_pts = rpts_p3, p_wr2_rookie_pts = rpts_p2, ppr23_rookie_pts = rpts_ppr,
         p_wr3_usage = use_p3, p_wr2_usage = use_p2, ppr23_usage = use_ppr) %>%
  arrange(desc(draft_season), desc(p_wr3_usage))
write.csv(board, "wr_year2_breakout_board.csv", row.names = FALSE)

cat("\n===== 2025 class: top 15 by P(WR3+ in 2026-27), usage model =====\n")
print(as.data.frame(board %>% filter(draft_season == 2025) %>% head(15) %>%
  select(pfr_player_name, pick, r_games, r_targets, r_ts, r_snap_avg, r_snap_last6, r_ppr, r_finish,
         p_wr3_usage, p_wr2_usage, ppr23_usage, p_wr3_rookie_pts)), row.names = FALSE)
cat("\n===== 2025 buy-low: outside top-48 as rookie, P(WR3+) >= 15%, usage model above rookie-pts baseline =====\n")
print(as.data.frame(board %>% filter(buy_low) %>% arrange(desc(usage_edge_wr3)) %>%
  select(pfr_player_name, pick, r_games, r_targets, r_ts, r_ays, r_snap_avg, r_snap_last6, r_ts_trend,
         r_ppr, r_finish, p_wr3_usage, p_wr3_rookie_pts, usage_edge_wr3)), row.names = FALSE)
cat("\n===== 2024 class: year-3 (2026) outlook, top 10 =====\n")
print(as.data.frame(board %>% filter(draft_season == 2024) %>% head(10) %>%
  select(pfr_player_name, pick, r_finish, y2_finish_actual, p_wr3_usage, p_wr2_usage, ppr23_usage)), row.names = FALSE)
cat("\nsaved phase7_cv_metrics.csv, phase7_oof_predictions.csv, phase7_hidden_talent_backtest.csv,",
    "wr_year2_breakout_board.csv\n")
