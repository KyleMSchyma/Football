# =============================================================================
# WR Model -- Phase 10: college usage & efficiency features (cfbd usage + PPA)
#
# Adds College Football Data player usage (share of team plays / pass plays the
# player was involved in, by down) and PPA (predicted points added per play) to
# the PRE-DRAFT model, and tests whether they help.
#
#   Data: cfbd_player_usage and cfbd_metrics_ppa_players_season, seasons
#         2013-2025, cached in cache/cfbd_usage_raw.rds and cache/cfbd_ppa_raw.rds.
#         Joined by cfbd athlete_id to each WR's final and best college seasons.
#         Classes whose final college season is before 2013 (drafts <= 2013) have
#         no values: imputed in-fold with missing flags.
#   Models: pre-draft elastic nets (Phase 3 features) WITHOUT vs WITH the new
#         features, for 3-yr PPR, top-24 hit, and the tier ladder (nested logistic
#         elastic nets for WR1 / WR2+ / WR3+, forced monotone; ranked probability
#         score). glmnet nested logits are used here instead of ordinalNet to keep
#         the with/without comparison fast and identical in form.
#   Validation: strict rolling origin (test 2016-2023, train <= Y - 3) and
#         leave-one-class-out restricted to test classes 2015-2023 (where the
#         features exist). Bootstrap CIs for with minus without.
#   Hidden talent: Day-3 back-test (top 5/10 per class by P(WR3+)) and ranks of
#         Hill, Renfrow, Mooney, Nacua, St. Brown, Gabe Davis, Doubs.
#
# Outputs: phase10_cv_metrics.csv, phase10_oof_predictions.csv,
#          wr_pre_draft_usage_board_2024_2026.csv
# =============================================================================

suppressMessages({ library(dplyr); library(tidyr); library(glmnet); library(pROC) })
set.seed(2026)

tbl <- readRDS("wr_model_table.rds") %>%
  mutate(final_power5 = as.integer(final_power5), combine_invited = as.integer(combine_invited),
         athlete_id = as.character(athlete_id)) %>%
  left_join(read.csv("phase5_finish_targets.csv") %>%
              transmute(draft_season, pick, best_fin = pmin(finish_y1, finish_y2, finish_y3)),
            by = c("draft_season", "pick")) %>%
  mutate(y1 = as.integer(best_fin <= 12), y2 = as.integer(best_fin <= 24), y3 = as.integer(best_fin <= 36))
cs  <- readRDS("wr_college_seasons.rds") %>% mutate(athlete_id = as.character(athlete_id))
usg <- readRDS("cache/cfbd_usage_raw.rds") %>% mutate(athlete_id = as.character(athlete_id))
ppa <- readRDS("cache/cfbd_ppa_raw.rds") %>% mutate(athlete_id = as.character(athlete_id))

# --- Usage / PPA features per player ----------------------------------------------
seas <- cs %>% distinct(draft_season, pick, athlete_id, college_year) %>%
  left_join(usg %>% select(athlete_id, season, usg_overall, usg_pass, usg_3rd_down, usg_passing_downs) %>%
              distinct(athlete_id, season, .keep_all = TRUE),
            by = c("athlete_id", "college_year" = "season")) %>%
  left_join(ppa %>% select(athlete_id, season, avg_PPA_all, avg_PPA_pass, total_PPA_pass, countable_plays) %>%
              distinct(athlete_id, season, .keep_all = TRUE),
            by = c("athlete_id", "college_year" = "season"))
uf <- seas %>% group_by(draft_season, pick) %>% arrange(college_year, .by_group = TRUE) %>%
  summarize(f_usg_overall = last(usg_overall), f_usg_pass = last(usg_pass),
            f_usg_3rd = last(usg_3rd_down), f_usg_pd = last(usg_passing_downs),
            f_ppa_pass = last(avg_PPA_pass), f_ppa_all = last(avg_PPA_all),
            f_tot_ppa_pass = last(total_PPA_pass), f_plays = last(countable_plays),
            best_usg_pass = suppressWarnings(max(usg_pass, na.rm = TRUE)),
            best_tot_ppa_pass = suppressWarnings(max(total_PPA_pass, na.rm = TRUE)),
            .groups = "drop") %>%
  mutate(across(c(best_usg_pass, best_tot_ppa_pass), ~ ifelse(is.infinite(.x), NA, .x)),
         # avg PPA on very few plays is noise. cfbd's countable_plays is empty, so
         # estimate pass plays as total PPA / average PPA and require 20+.
         f_pass_plays_est = ifelse(!is.na(f_ppa_pass) & abs(f_ppa_pass) > 1e-6, f_tot_ppa_pass / f_ppa_pass, NA),
         across(c(f_ppa_pass, f_ppa_all), ~ ifelse(!is.na(f_pass_plays_est) & f_pass_plays_est >= 20, .x, NA)))
tbl <- tbl %>% left_join(uf, by = c("draft_season", "pick"))
new_feats <- c("f_usg_overall", "f_usg_pass", "f_usg_3rd", "f_usg_pd", "f_ppa_pass", "f_ppa_all",
               "f_tot_ppa_pass", "best_usg_pass", "best_tot_ppa_pass")
cat("coverage of final-season usage (f_usg_pass) and PPA (f_ppa_pass) by class (%):\n")
print(as.data.frame(tbl %>% group_by(draft_season) %>%
  summarize(n = n(), usage = round(100 * mean(!is.na(f_usg_pass))), ppa = round(100 * mean(!is.na(f_ppa_pass))), .groups = "drop")),
  row.names = FALSE)

train <- tbl %>% filter(!is.na(total_ppr_3yr))
score <- tbl %>% filter(is.na(total_ppr_3yr), draft_season >= 2024)
cat("\nSpearman of new features with total_ppr_3yr (training classes, non-missing):\n")
print(round(sapply(new_feats, function(v) suppressWarnings(cor(train[[v]], train$total_ppr_3yr, method = "spearman", use = "pairwise.complete.obs"))), 3))

# --- Preprocessing (Phase 3, copied) + optional new features ----------------------
drills   <- c("forty", "vertical", "broad_jump", "speed_score")
pre_num  <- c("age_at_draft", "final_dominator", "best_dominator", "final_yptpa", "breakout_age_filled",
              "career_rec_yds", "college_seasons", "height_in", "weight_lb", "recruit_rating")
pre_flag <- c("broke_out", "transferred", "early_declare", "final_power5", "college_matched",
              "combine_invited", "miss_forty", "miss_vertical", "miss_broad_jump")
fit_prep <- function(d, num) {
  med <- sapply(c(num, drills), function(v) median(d[[v]], na.rm = TRUE)); med[is.na(med)] <- 0
  flag <- num[sapply(num, function(v) any(is.na(d[[v]])))]
  dm <- as.matrix(d[, drills]); for (v in drills) dm[is.na(dm[, v]), v] <- med[v]
  list(num = num, med = med, flag = flag, pca = prcomp(dm, center = TRUE, scale. = TRUE))
}
apply_prep <- function(p, d) {
  out <- data.frame(row.names = seq_len(nrow(d)))
  for (v in p$num) { x <- d[[v]]; if (v %in% p$flag) out[[paste0("na_", v)]] <- as.integer(is.na(x)); x[is.na(x)] <- p$med[v]; out[[v]] <- x }
  dm <- as.matrix(d[, drills]); for (v in drills) dm[is.na(dm[, v]), v] <- p$med[v]
  pcs <- predict(p$pca, dm)[, 1:2, drop = FALSE]; out$athletic_pc1 <- pcs[, 1]; out$athletic_pc2 <- pcs[, 2]
  for (v in pre_flag) out[[v]] <- as.integer(coalesce(as.numeric(d[[v]]), 0))
  as.matrix(out)
}
fit_set <- function(tr, te, with_new) {
  num <- if (with_new) c(pre_num, new_feats) else pre_num
  p <- fit_prep(tr, num); Xtr <- apply_prep(p, tr); Xte <- apply_prep(p, te)
  folds <- as.integer(factor(tr$draft_season)); if (max(folds) < 4) folds <- sample(rep(1:5, length.out = nrow(tr)))
  en <- function(y, fam) { f <- cv.glmnet(Xtr, y, family = fam, alpha = 0.5, foldid = folds)
    as.numeric(predict(f, Xte, s = "lambda.min", type = "response")) }
  P1 <- en(tr$y1, "binomial"); P2 <- pmax(en(tr$y2, "binomial"), P1); P3 <- pmax(en(tr$y3, "binomial"), P2)
  data.frame(ppr = pmax(0, en(tr$total_ppr_3yr, "gaussian")), hit = en(tr$hit_3yr, "binomial"),
             p1 = P1, p2 = P2, p3 = P3)
}
run <- function(scheme) {
  res <- list()
  tests <- if (scheme == "Rolling") 2016:2023 else 2015:2023
  for (Y in tests) {
    tr <- if (scheme == "Rolling") filter(train, draft_season <= Y - 3) else filter(train, draft_season != Y)
    te <- filter(train, draft_season == Y)
    a <- fit_set(tr, te, FALSE); b <- fit_set(tr, te, TRUE)
    names(a) <- paste0("without_", names(a)); names(b) <- paste0("with_", names(b))
    res[[length(res) + 1]] <- cbind(te %>% select(draft_season, round, pick, pfr_player_name, total_ppr_3yr, hit_3yr,
                                                  y1, y2, y3, best_fin, f_usg_pass, f_ppa_pass),
                                    scheme = scheme, a, b)
  }
  bind_rows(res)
}
oof <- bind_rows(run("Rolling"), run("LOCO 2015-23"))
write.csv(oof, "phase10_oof_predictions.csv", row.names = FALSE)

aucf <- function(y, p) if (length(unique(y)) < 2) NA else as.numeric(auc(roc(y, p, quiet = TRUE)))
rps <- function(o, s) ((o[[paste0(s, "_p1")]] - o$y1)^2 + (o[[paste0(s, "_p2")]] - o$y2)^2 + (o[[paste0(s, "_p3")]] - o$y3)^2) / 3
met <- bind_rows(lapply(unique(oof$scheme), function(sc) bind_rows(lapply(c("without", "with"), function(s) {
  o <- filter(oof, scheme == sc)
  data.frame(scheme = sc, features = paste(s, "usage/PPA"), n = nrow(o),
             Spearman_PPR = cor(o[[paste0(s, "_ppr")]], o$total_ppr_3yr, method = "spearman"),
             RMSE_PPR = sqrt(mean((o[[paste0(s, "_ppr")]] - o$total_ppr_3yr)^2)),
             AUC_hit = aucf(o$hit_3yr, o[[paste0(s, "_hit")]]), Brier_hit = mean((o[[paste0(s, "_hit")]] - o$hit_3yr)^2),
             RPS_ladder = mean(rps(o, s)), AUC_WR3 = aucf(o$y3, o[[paste0(s, "_p3")]]))
})))) %>% mutate(across(where(is.double), ~ round(.x, 4)))
cat("\n===== Pre-draft model WITHOUT vs WITH college usage/PPA features =====\n")
print(met, row.names = FALSE)
write.csv(met, "phase10_cv_metrics.csv", row.names = FALSE)

set.seed(2026)
r <- filter(oof, scheme == "Rolling")
bt <- function(f) { pt <- f(seq_len(nrow(r))); dd <- replicate(2000, f(sample.int(nrow(r), replace = TRUE)))
  sprintf("%+.4f  95%% CI [%+.4f, %+.4f]  share < 0: %.3f", pt, quantile(dd, .025), quantile(dd, .975), mean(dd < 0)) }
cat("\n===== Bootstrap, rolling origin (2000 draws, seed 2026; WITH minus WITHOUT, negative = new features help) =====\n")
cat("RMSE PPR:  ", bt(function(i) sqrt(mean((r$with_ppr[i] - r$total_ppr_3yr[i])^2)) - sqrt(mean((r$without_ppr[i] - r$total_ppr_3yr[i])^2))), "\n")
cat("Brier hit: ", bt(function(i) mean((r$with_hit[i] - r$hit_3yr[i])^2) - mean((r$without_hit[i] - r$hit_3yr[i])^2)), "\n")
cat("RPS ladder:", bt(function(i) mean(rps(r[i, ], "with")) - mean(rps(r[i, ], "without"))), "\n")
cat("Spearman PPR (positive = help):",
    bt(function(i) -(cor(r$with_ppr[i], r$total_ppr_3yr[i], method = "spearman") - cor(r$without_ppr[i], r$total_ppr_3yr[i], method = "spearman"))),
    "  <- sign flipped: negative here means WITH has the higher Spearman\n")

# --- Day-3 hidden talent: before vs after -----------------------------------------
d3 <- filter(r, round >= 4)
cat("\n===== Day-3 back-test, rolling (", nrow(d3), "players,", sum(d3$y3), "reached WR3+ in yrs 1-3 ) =====\n")
for (k in c(5, 10)) {
  h <- function(col) sum((d3 %>% group_by(draft_season) %>% arrange(desc(.data[[col]]), pick, .by_group = TRUE) %>%
                            slice_head(n = k) %>% ungroup())$y3)
  d3$earliest <- -d3$pick
  cat(sprintf("top %d per class: without %d | with %d | earliest picks %d\n", k, h("without_p3"), h("with_p3"), h("earliest")))
}
known <- c("Tyreek Hill", "Hunter Renfrow", "Darnell Mooney", "Puka Nacua", "Amon-Ra St. Brown", "Gabe Davis", "Romeo Doubs")
kr <- d3 %>% group_by(draft_season) %>%
  mutate(n_day3 = n(), rank_without = rank(-without_p3, ties.method = "min"), rank_with = rank(-with_p3, ties.method = "min"),
         rank_pick = rank(pick)) %>% ungroup() %>% filter(pfr_player_name %in% known) %>%
  select(draft_season, pick, pfr_player_name, best_fin, f_usg_pass, f_ppa_pass, without_p3, with_p3,
         rank_without, rank_with, rank_pick, n_day3) %>%
  mutate(across(c(f_usg_pass, f_ppa_pass, without_p3, with_p3), ~ round(.x, 3)))
cat("\nknown Day-3 hits: rank among their class's Day-3 WRs by pre-draft P(WR3+), before vs after\n")
print(as.data.frame(kr), row.names = FALSE)

# --- Final fit: coefficients and a 2024-2026 board --------------------------------
p <- fit_prep(train, c(pre_num, new_feats)); X <- apply_prep(p, train)
f <- cv.glmnet(X, train$total_ppr_3yr, alpha = 0.5, foldid = as.integer(factor(train$draft_season)))
co <- coef(f, s = "lambda.min"); co <- co[which(co[, 1] != 0), 1]
cat("\nfinal pre-draft PPR elastic net with usage/PPA: nonzero coefficients\n"); print(round(co[order(-abs(co))], 3))
fs <- fit_set(train, score, TRUE); f0 <- fit_set(train, score, FALSE)
board <- score %>% select(pfr_player_name, draft_season, round, pick, draft_team, college,
                          f_usg_overall, f_usg_pass, f_ppa_pass, f_tot_ppa_pass, best_usg_pass) %>%
  mutate(pre_ppr_without = round(f0$ppr, 1), pre_ppr_with = round(fs$ppr, 1),
         p_wr3_without = round(f0$p3, 3), p_wr3_with = round(fs$p3, 3),
         p_wr2_with = round(fs$p2, 3), p_wr1_with = round(fs$p1, 3),
         change_ppr = round(pre_ppr_with - pre_ppr_without, 1)) %>%
  mutate(across(c(f_usg_overall, f_usg_pass, f_ppa_pass, f_tot_ppa_pass, best_usg_pass), ~ round(.x, 3))) %>%
  arrange(draft_season, desc(pre_ppr_with))
write.csv(board, "wr_pre_draft_usage_board_2024_2026.csv", row.names = FALSE)
cat("\n2026 class, pre-draft projection with usage/PPA, top 10:\n")
print(as.data.frame(board %>% filter(draft_season == 2026) %>% head(10) %>%
  select(pfr_player_name, pick, f_usg_pass, f_ppa_pass, pre_ppr_without, pre_ppr_with, change_ppr, p_wr3_with)), row.names = FALSE)
cat("2026 Day-3, biggest gains from the new features:\n")
print(as.data.frame(board %>% filter(draft_season == 2026, round >= 4) %>% arrange(desc(change_ppr)) %>% head(6) %>%
  select(pfr_player_name, pick, f_usg_pass, f_ppa_pass, pre_ppr_without, pre_ppr_with, change_ppr)), row.names = FALSE)
cat("\nsaved phase10_cv_metrics.csv, phase10_oof_predictions.csv, wr_pre_draft_usage_board_2024_2026.csv\n")
