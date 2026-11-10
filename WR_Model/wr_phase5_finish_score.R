# =============================================================================
# WR Model -- Phase 5: 3-year finish score model
#
# Target: finish_sum_3yr = sum of the player's season-end WR PPR rank in NFL years
#   1-3 (e.g. WR2 + WR12 + WR15 = 29). LOWER IS BETTER.
#   A season outside the top CAP (or with no games) counts as CAP, so a player who
#   never plays scores 3 * CAP. Best possible = 3.
#
# Same features, in-fold preprocessing and models as Phase 3 (baseline on log pick,
# elastic net, random forest; pre- and post-draft). Evaluated two ways:
#   leave-one-class-out (2010-2023) and rolling origin (test 2016-2023, train on
#   classes <= Y - 3). Projects 2024-2026 with models fit on all 2010-2023.
#
# Outputs: phase5_finish_targets.csv, phase5_cv_metrics.csv (+ _cap60 versions),
#          wr_finish_projections_2024_2026.csv
# Does not modify earlier phase files.
# =============================================================================

suppressMessages({ library(dplyr); library(tidyr); library(glmnet); library(ranger) })
set.seed(2026)
# rank assigned to a season outside the top CAP or not played. Default 100;
# sensitivity run: Rscript wr_phase5_finish_score.R 60  (writes *_cap60 files)
CAP <- if (length(commandArgs(TRUE)) > 0) as.integer(commandArgs(TRUE)[1]) else 100
SUFFIX <- if (CAP == 100) "" else paste0("_cap", CAP)
last_nfl_season <- 2025

tbl    <- readRDS("wr_model_table.rds") %>%
  mutate(final_power5 = as.integer(final_power5), combine_invited = as.integer(combine_invited))
weekly <- readRDS(file.path("cache", "nfl_weekly_raw.rds"))

# --- Season WR ranks (same ranking as Phase 2's hit flag) ---------------------
season_tot <- weekly %>% filter(season_type == "REG") %>%
  group_by(player_id, season) %>%
  summarize(position = first(position), ppr = sum(fantasy_points_ppr, na.rm = TRUE), .groups = "drop")
wr_rank <- season_tot %>% filter(position == "WR") %>% group_by(season) %>%
  mutate(wr_rank = rank(-ppr, ties.method = "min")) %>% ungroup() %>% select(player_id, season, wr_rank)

yrs <- tbl %>% select(gsis_id, draft_season, pick) %>%
  crossing(nfl_year = 1:3) %>%
  mutate(season = draft_season + nfl_year - 1) %>%
  filter(season <= last_nfl_season) %>%
  left_join(wr_rank, by = c("gsis_id" = "player_id", "season")) %>%
  mutate(finish = pmin(coalesce(wr_rank, CAP), CAP))
fin <- yrs %>% group_by(draft_season, pick) %>%
  summarize(n_obs = n(),
            finish_y1 = finish[nfl_year == 1][1], finish_y2 = finish[nfl_year == 2][1],
            finish_y3 = finish[nfl_year == 3][1],
            finish_sum_obs = sum(finish), .groups = "drop") %>%
  mutate(finish_sum_3yr = ifelse(n_obs == 3, finish_sum_obs, NA))
tbl <- tbl %>% left_join(fin, by = c("draft_season", "pick"))
write.csv(tbl %>% filter(!is.na(finish_y1)) %>%
            select(draft_season, round, pick, pfr_player_name, finish_y1, finish_y2, finish_y3, finish_sum_3yr),
          paste0("phase5_finish_targets", SUFFIX, ".csv"), row.names = FALSE)

train <- tbl %>% filter(!is.na(finish_sum_3yr))
score <- tbl %>% filter(is.na(finish_sum_3yr), draft_season >= 2024)
cat("training rows:", nrow(train), " to project:", nrow(score), "\n")
cat("\nfinish_sum_3yr distribution (lower = better, cap", CAP, "per season, max", 3 * CAP, "):\n")
print(summary(train$finish_sum_3yr))
cat("share at the max (never a top-", CAP, " season): ", round(mean(train$finish_sum_3yr == 3 * CAP), 3), "\n", sep = "")
cat("by round (mean / median):\n")
print(as.data.frame(train %>% group_by(round) %>%
  summarize(n = n(), mean = round(mean(finish_sum_3yr), 1), median = median(finish_sum_3yr), .groups = "drop")))
cat("\nbest 15 finish sums, 2010-2023:\n")
print(as.data.frame(train %>% arrange(finish_sum_3yr) %>% head(15) %>%
  select(draft_season, pick, pfr_player_name, finish_y1, finish_y2, finish_y3, finish_sum_3yr)), row.names = FALSE)
cat("\nSpearman(finish_sum_3yr, total_ppr_3yr) =",
    round(cor(train$finish_sum_3yr, train$total_ppr_3yr, method = "spearman"), 3), "\n")

# --- Features / preprocessing (as Phase 3) --------------------------------------
drills   <- c("forty", "vertical", "broad_jump", "speed_score")
pre_num  <- c("age_at_draft", "final_dominator", "best_dominator", "final_yptpa",
              "breakout_age_filled", "career_rec_yds", "college_seasons",
              "height_in", "weight_lb", "recruit_rating")
pre_flag <- c("broke_out", "transferred", "early_declare", "final_power5",
              "college_matched", "combine_invited", "miss_forty", "miss_vertical", "miss_broad_jump")
post_num <- c("log_pick", "vacated_target_share", "team_targets_prev")
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
clamp <- function(x) pmin(pmax(x, 3), 3 * CAP)
fit_predict <- function(tr, te, set) {
  y <- tr$finish_sum_3yr
  p <- fit_prep(tr, if (set == "pre") pre_num else c(pre_num, post_num))
  Xtr <- apply_prep(p, tr); Xte <- apply_prep(p, te)
  base <- if (set == "pre") rep(mean(y), nrow(te)) else predict(lm(y ~ log_pick, data = cbind(Xtr, y = y)), Xte)
  en <- cv.glmnet(as.matrix(Xtr), y, alpha = 0.5, foldid = as.integer(factor(tr$draft_season)))
  rf <- ranger(x = Xtr, y = y, num.trees = 500, min.node.size = 10, seed = 2026)
  list(pred = data.frame(baseline = clamp(base),
                         elastic_net = clamp(as.numeric(predict(en, as.matrix(Xte), s = "lambda.min"))),
                         random_forest = clamp(predict(rf, Xte)$predictions)),
       en = en)
}

# --- Evaluation -----------------------------------------------------------------
run_cv <- function(scheme) {
  out <- list()
  tests <- if (scheme == "LOCO") sort(unique(train$draft_season)) else 2016:2023
  for (set in c("pre", "post")) for (Y in tests) {
    tr <- if (scheme == "LOCO") filter(train, draft_season != Y) else filter(train, draft_season <= Y - 3)
    te <- filter(train, draft_season == Y)
    out[[length(out) + 1]] <- cbind(te[, c("draft_season", "pick", "pfr_player_name")],
                                    set = set, actual = te$finish_sum_3yr, fit_predict(tr, te, set)$pred)
  }
  bind_rows(out) %>% mutate(scheme = scheme)
}
oof <- bind_rows(run_cv("LOCO"), run_cv("Rolling"))
lng <- oof %>%
  pivot_longer(c(baseline, elastic_net, random_forest), names_to = "model", values_to = "pred")
# within-class Spearman: correlation inside each draft class, averaged over classes
# (higher = better ordering of players within a class; NA for a constant prediction)
wc <- lng %>% group_by(scheme, set, model, draft_season) %>%
  summarize(rho = if (sd(pred) > 0) cor(pred, actual, method = "spearman") else NA_real_, .groups = "drop") %>%
  group_by(scheme, set, model) %>% summarize(within_class_Spearman = mean(rho, na.rm = TRUE), .groups = "drop")
metrics <- lng %>% group_by(scheme, set, model) %>%
  summarize(n = n(), pooled_Spearman = cor(pred, actual, method = "spearman"),
            R2 = 1 - sum((pred - actual)^2) / sum((actual - mean(actual))^2),
            RMSE = sqrt(mean((pred - actual)^2)), MAE = mean(abs(pred - actual)), .groups = "drop") %>%
  left_join(wc, by = c("scheme", "set", "model")) %>%
  mutate(across(c(pooled_Spearman, within_class_Spearman, R2, RMSE, MAE), ~ round(.x, 3))) %>%
  arrange(scheme, set, model)
cat("\n===== Cross-validated performance, finish_sum_3yr (cap", CAP, ") =====\n")
cat("(predicted vs actual finish sums: positive Spearman = better agreement)\n")
print(as.data.frame(metrics), row.names = FALSE)
write.csv(metrics, paste0("phase5_cv_metrics", SUFFIX, ".csv"), row.names = FALSE)

# Bootstrap: post elastic net minus pick-only RMSE, rolling origin
set.seed(2026)
r <- oof %>% filter(scheme == "Rolling", set == "post")
d <- replicate(2000, { i <- sample.int(nrow(r), replace = TRUE)
  sqrt(mean((r$elastic_net[i] - r$actual[i])^2)) - sqrt(mean((r$baseline[i] - r$actual[i])^2)) })
cat(sprintf("\nrolling origin, post-draft elastic net minus pick-only RMSE: %+.2f  95%% CI [%+.2f, %+.2f]  (negative = elastic net better; share of draws < 0: %.3f)\n",
            sqrt(mean((r$elastic_net - r$actual)^2)) - sqrt(mean((r$baseline - r$actual)^2)),
            quantile(d, .025), quantile(d, .975), mean(d < 0)))
if (CAP != 100) quit(save = "no")   # sensitivity run: metrics only, no board

# --- Projections 2024-2026 ------------------------------------------------------
proj <- score %>% select(draft_season, round, pick, pfr_player_name, college, draft_team,
                         finish_y1, finish_y2)
for (set in c("pre", "post")) {
  f <- fit_predict(train, score, set)
  proj[[paste0(set, "_pick_only")]] <- if (set == "post") round(f$pred$baseline, 1) else NULL
  proj[[paste0(set, "_finish_sum")]] <- round(f$pred$elastic_net, 1)
  co <- coef(f$en, s = "lambda.min"); nz <- co[which(co[, 1] != 0), 1]
  cat("\nelastic net (", set, ") nonzero coefficients (negative = better finish):\n", sep = "")
  print(round(nz[order(-abs(nz))], 3))
}
proj <- proj %>% rename(pick_only_finish_sum = post_pick_only) %>%
  mutate(value_gap = round(pick_only_finish_sum - pre_finish_sum, 1)) %>%   # positive = college likes him more
  arrange(draft_season, post_finish_sum)
write.csv(proj, "wr_finish_board_2024_2026.csv", row.names = FALSE)
cat("\n===== Projected finish_sum_3yr (post-draft elastic net), top 10 per class =====\n")
print(as.data.frame(proj %>% group_by(draft_season) %>% slice_head(n = 10) %>%
  select(draft_season, pick, pfr_player_name, post_finish_sum, pick_only_finish_sum, pre_finish_sum,
         finish_y1, finish_y2)), row.names = FALSE)
