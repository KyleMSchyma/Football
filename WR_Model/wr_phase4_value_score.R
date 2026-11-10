# =============================================================================
# WR Model -- Phase 4: value score (college model vs draft slot)
#
# value_gap_ppr  = pre-draft elastic net predicted 3-yr PPR - pick-only predicted 3-yr PPR
# value_gap_hit  = same gap for hit probability
# rank_gap       = within-class percentile of pre-draft prediction
#                  - within-class percentile of draft slot (earlier pick = higher)
#
# PART 1  Back-test on the rolling-origin out-of-sample predictions (2016-2023)
#         from Phase 3 (phase3_rolling_oof_predictions.csv): does a positive value
#         score predict beating draft slot (actual - pick-only prediction)?
# PART 2  Fit on all 2010-2023 and score 2024-2026 -> wr_value_board_2024_2026.csv
#
# Does not modify any Phase 3 file. Model code is copied from wr_phase3_model.R.
# Requires: dplyr, tidyr, glmnet, pROC
# =============================================================================

suppressMessages({ library(dplyr); library(tidyr); library(glmnet) })
set.seed(2026)

tbl <- readRDS("wr_model_table.rds") %>%
  mutate(final_power5 = as.integer(final_power5), combine_invited = as.integer(combine_invited))
train <- tbl %>% filter(!is.na(total_ppr_3yr))
score <- tbl %>% filter(is.na(total_ppr_3yr), draft_season >= 2024)

# --- Same features / in-fold preprocessing as Phase 3 --------------------------
drills   <- c("forty", "vertical", "broad_jump", "speed_score")
pre_num  <- c("age_at_draft", "final_dominator", "best_dominator", "final_yptpa",
              "breakout_age_filled", "career_rec_yds", "college_seasons",
              "height_in", "weight_lb", "recruit_rating")
pre_flag <- c("broke_out", "transferred", "early_declare", "final_power5",
              "college_matched", "combine_invited", "miss_forty", "miss_vertical",
              "miss_broad_jump")
fit_prep <- function(d, num) {
  med  <- sapply(c(num, drills), function(v) median(d[[v]], na.rm = TRUE))
  flag <- num[sapply(num, function(v) any(is.na(d[[v]])))]
  dm <- as.matrix(d[, drills]); for (v in drills) dm[is.na(dm[, v]), v] <- med[v]
  list(num = num, med = med, flag = flag, pca = prcomp(dm, center = TRUE, scale. = TRUE))
}
apply_prep <- function(p, d) {
  out <- data.frame(row.names = seq_len(nrow(d)))
  for (v in p$num) {
    x <- d[[v]]
    if (v %in% p$flag) out[[paste0("na_", v)]] <- as.integer(is.na(x))
    x[is.na(x)] <- p$med[v]; out[[v]] <- x
  }
  dm <- as.matrix(d[, drills]); for (v in drills) dm[is.na(dm[, v]), v] <- p$med[v]
  pcs <- predict(p$pca, dm)[, 1:2, drop = FALSE]
  out$athletic_pc1 <- pcs[, 1]; out$athletic_pc2 <- pcs[, 2]
  for (v in pre_flag) out[[v]] <- as.integer(coalesce(as.numeric(d[[v]]), 0))
  out
}
pick_only <- function(tr, te, target) {
  if (target == "hit_3yr")
    predict(glm(hit_3yr ~ log_pick, family = binomial, data = tr), te, type = "response")
  else pmax(0, predict(lm(total_ppr_3yr ~ log_pick, data = tr), te))
}
pre_enet <- function(tr, te, target) {
  p <- fit_prep(tr, pre_num)
  fam <- if (target == "hit_3yr") "binomial" else "gaussian"
  en <- cv.glmnet(as.matrix(apply_prep(p, tr)), tr[[target]], family = fam, alpha = 0.5,
                  foldid = as.integer(factor(tr$draft_season)))
  pr <- as.numeric(predict(en, as.matrix(apply_prep(p, te)), s = "lambda.min", type = "response"))
  if (fam == "gaussian") pmax(0, pr) else pr
}
pct_rank <- function(x) (rank(x, ties.method = "average") - 0.5) / length(x)

add_scores <- function(d) {
  d %>% group_by(draft_season) %>%
    mutate(pre_pct  = round(pct_rank(pre_ppr), 3),
           pick_pct = round(pct_rank(-pick), 3),
           rank_gap = pre_pct - pick_pct) %>% ungroup() %>%
    mutate(value_gap_ppr = pre_ppr - pick_ppr, value_gap_hit = pre_hit - pick_hit)
}

# =============================================================================
# PART 1: Back-test on rolling-origin out-of-sample predictions
# =============================================================================
roll <- read.csv("phase3_rolling_oof_predictions.csv")
key <- c("draft_season", "pick", "round", "pfr_player_name")
bt <- roll %>% filter(set == "pre", target == "total_ppr_3yr") %>%
  transmute(across(all_of(key)), actual_ppr = actual, pre_ppr = elastic_net) %>%
  inner_join(roll %>% filter(set == "post", target == "total_ppr_3yr") %>%
               transmute(across(all_of(key)), pick_ppr = baseline), by = key) %>%
  inner_join(roll %>% filter(set == "pre", target == "hit_3yr") %>%
               transmute(across(all_of(key)), actual_hit = actual, pre_hit = elastic_net), by = key) %>%
  inner_join(roll %>% filter(set == "post", target == "hit_3yr") %>%
               transmute(across(all_of(key)), pick_hit = baseline), by = key) %>%
  add_scores() %>%
  mutate(beat_ppr = actual_ppr - pick_ppr, beat_hit = actual_hit - pick_hit)
cat("back-test players (2016-2023, rolling origin):", nrow(bt), "\n")

group_table <- function(d, score_col, k) {
  d %>% mutate(grp = ntile(.data[[score_col]], k)) %>% group_by(grp) %>%
    summarize(n = n(),
              score_range = sprintf("%.2f to %.2f", min(.data[[score_col]]), max(.data[[score_col]])),
              mean_pick = round(mean(pick)),
              actual_ppr = round(mean(actual_ppr), 1), pick_only_ppr = round(mean(pick_ppr), 1),
              ppr_vs_slot = round(mean(beat_ppr), 1),
              actual_hit = round(mean(actual_hit), 3), pick_only_hit = round(mean(pick_hit), 3),
              hit_vs_slot = round(mean(beat_hit), 3), .groups = "drop")
}
boot_top_bottom <- function(d, score_col, k, B = 2000) {
  g <- ntile(d[[score_col]], k)
  top <- d$beat_ppr[g == k]; bot <- d$beat_ppr[g == 1]
  th <- d$beat_hit[g == k];  bh <- d$beat_hit[g == 1]
  bs <- replicate(B, mean(sample(top, replace = TRUE)) - mean(sample(bot, replace = TRUE)))
  bh_s <- replicate(B, mean(sample(th, replace = TRUE)) - mean(sample(bh, replace = TRUE)))
  sprintf(paste0("top minus bottom (actual - pick-only): PPR %+.1f  95%% CI [%+.1f, %+.1f]  P(>0)=%.3f | ",
                 "hit rate %+.3f  95%% CI [%+.3f, %+.3f]"),
          mean(top) - mean(bot), quantile(bs, .025), quantile(bs, .975), mean(bs > 0),
          mean(th) - mean(bh), quantile(bh_s, .025), quantile(bh_s, .975))
}
run_bt <- function(d, label, k) {
  for (sc in c("value_gap_ppr", "rank_gap")) {
    cat(sprintf("\n--- %s | score = %s | %d groups (1 = most negative, %d = most positive) ---\n",
                label, sc, k, k))
    print(as.data.frame(group_table(d, sc, k)), row.names = FALSE)
    set.seed(2026); cat(boot_top_bottom(d, sc, k), "\n")
    cat(sprintf("Spearman(score, actual - pick-only PPR) = %.3f\n",
                cor(d[[sc]], d$beat_ppr, method = "spearman")))
  }
}
cat("\n===== Back-test: does a positive value score predict beating draft slot? =====\n")
cat("cor(value_gap_ppr, pick) =", round(cor(bt$value_gap_ppr, bt$pick, method = "spearman"), 3),
    " cor(rank_gap, pick) =", round(cor(bt$rank_gap, bt$pick, method = "spearman"), 3), "\n")
run_bt(bt, "ALL rounds", 5)
run_bt(bt %>% filter(round <= 3), "Day 1-2 (rounds 1-3)", 3)
run_bt(bt %>% filter(round >= 4), "Day 3 (rounds 4-7)", 3)
write.csv(bt, "phase4_backtest_players.csv", row.names = FALSE)

# =============================================================================
# PART 2: Score 2024-2026 with models fit on all 2010-2023
# =============================================================================
board <- score %>%
  transmute(pfr_player_name, draft_season, round, pick, draft_team, college,
            pick_ppr = round(pick_only(train, score, "total_ppr_3yr"), 1),
            pre_ppr  = round(pre_enet(train, score, "total_ppr_3yr"), 1),
            pick_hit = round(pick_only(train, score, "hit_3yr"), 3),
            pre_hit  = round(pre_enet(train, score, "hit_3yr"), 3),
            college_matched, final_rec_yds, career_rec_yds) %>%
  add_scores() %>%
  mutate(value_gap_ppr = round(value_gap_ppr, 1), value_gap_hit = round(value_gap_hit, 3),
         rank_gap = round(rank_gap, 3))

# Actual NFL PPR so far (2024: 2 seasons, 2025: 1 season)
weekly <- readRDS(file.path("cache", "nfl_weekly_raw.rds"))
so_far <- weekly %>% filter(season_type == "REG", season >= 2024, season <= 2025) %>%
  group_by(player_id) %>% summarize(nfl_ppr_so_far = round(sum(fantasy_points_ppr, na.rm = TRUE), 1),
                                    nfl_games_so_far = n_distinct(paste(season, week)), .groups = "drop")
board <- board %>%
  left_join(score %>% select(draft_season, pick, gsis_id), by = c("draft_season", "pick")) %>%
  left_join(so_far, by = c("gsis_id" = "player_id")) %>%
  mutate(nfl_ppr_so_far   = ifelse(draft_season <= 2025, coalesce(nfl_ppr_so_far, 0), NA),
         nfl_games_so_far = ifelse(draft_season <= 2025, coalesce(nfl_games_so_far, 0L), NA))

# Flags where college data is known to mislead
cs <- readRDS("wr_college_seasons.rds")
best_season <- cs %>% group_by(draft_season, pick) %>%
  summarize(best_season_rec_yds = max(rec_yds), .groups = "drop")
two_way <- c("Travis Hunter")   # also played defense full-time in college
board <- board %>%
  left_join(best_season, by = c("draft_season", "pick")) %>%
  mutate(flag = paste0(
    ifelse(college_matched == 0, "no college data; ", ""),
    ifelse(pfr_player_name %in% two_way, "two-way player (college receiving understates him); ", ""),
    ifelse(!is.na(best_season_rec_yds) & best_season_rec_yds >= 400 &
             final_rec_yds < 0.5 * best_season_rec_yds,
           sprintf("short final season (%d yds vs best %d); ", as.integer(final_rec_yds),
                   as.integer(best_season_rec_yds)), "")),
    flag = sub("; $", "", flag)) %>%
  select(pfr_player_name, draft_season, round, pick, draft_team, college,
         pick_ppr, pre_ppr, value_gap_ppr, pick_hit, pre_hit, value_gap_hit,
         pre_pct, pick_pct, rank_gap, nfl_ppr_so_far, nfl_games_so_far, flag) %>%
  arrange(draft_season, desc(value_gap_ppr))
write.csv(board, "wr_value_board_2024_2026.csv", row.names = FALSE)

cat("\n===== Value board 2024-2026: top 5 / bottom 5 by value_gap_ppr per class =====\n")
for (y in 2024:2026) {
  b <- board %>% filter(draft_season == y)
  cat("\n", y, "-- most POSITIVE (college data likes him more than draft slot)\n")
  print(as.data.frame(head(b, 5) %>% select(pfr_player_name, pick, pick_ppr, pre_ppr, value_gap_ppr,
                                            rank_gap, nfl_ppr_so_far, flag)), row.names = FALSE)
  cat(y, "-- most NEGATIVE\n")
  print(as.data.frame(tail(b, 5) %>% arrange(value_gap_ppr) %>%
          select(pfr_player_name, pick, pick_ppr, pre_ppr, value_gap_ppr, rank_gap, nfl_ppr_so_far, flag)),
        row.names = FALSE)
  cat(y, "-- most positive by rank_gap (removes the pull toward the mean)\n")
  print(as.data.frame(b %>% arrange(desc(rank_gap)) %>% head(5) %>%
          select(pfr_player_name, pick, pre_pct, pick_pct, rank_gap, flag)), row.names = FALSE)
}
cat("\nflagged players on the board:\n")
print(as.data.frame(board %>% filter(flag != "") %>% select(pfr_player_name, draft_season, pick, value_gap_ppr, flag)),
      row.names = FALSE)
cat("\nsaved wr_value_board_2024_2026.csv (", nrow(board), "rows ) and phase4_backtest_players.csv\n")
