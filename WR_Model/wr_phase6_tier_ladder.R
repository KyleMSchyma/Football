# =============================================================================
# WR Model -- Phase 6: tier ladder (WR1 / WR2 / WR3 finish models)
#
# Outcome: best season-end WR PPR finish in NFL years 1-3, as ordered tiers
#   1 = WR1 (top 12), 2 = WR2 (13-24), 3 = WR3 (25-36), 4 = below / never played
# Cumulative ladder: P(WR1) <= P(WR2+) <= P(WR3+), guaranteed by the model form.
#
# Models
#   pick-only   proportional-odds cumulative logit on log pick (MASS::polr)
#   pre / post  penalized cumulative logit (ordinalNet, elastic net alpha = 0.5,
#               parallel terms), lambda chosen by inner CV with folds = draft
#               classes (out-of-fold log-likelihood). Same features and in-fold
#               preprocessing as Phases 3-5.
# Validation: strict rolling origin (test 2016-2023, train <= Y - 3) and
#   leave-one-class-out. AUC + Brier per threshold, ranked probability score (RPS),
#   WR3+ calibration by quintile, bootstrap CI for post minus pick-only RPS.
# Hidden-talent score: post-draft P(WR2+) - pick-only P(WR2+) (and WR3+ version).
#   Back-tested on Day-3 picks (rounds 4-7), rolling origin.
#
# Inputs: wr_model_table.rds, phase5_finish_targets.csv,
#         wr_finish_hurdle_board_2024_2026.csv
# Outputs: phase6_cv_metrics.csv, phase6_oof_predictions.csv,
#          phase6_hidden_talent_backtest.csv, wr_tier_board_2024_2026.csv
# =============================================================================

suppressMessages({ library(dplyr); library(tidyr); library(pROC); library(MASS); library(ordinalNet) })
select <- dplyr::select
set.seed(2026)

tbl <- readRDS("wr_model_table.rds") %>%
  mutate(final_power5 = as.integer(final_power5), combine_invited = as.integer(combine_invited)) %>%
  left_join(read.csv("phase5_finish_targets.csv") %>%
              select(draft_season, pick, finish_y1, finish_y2, finish_y3, finish_sum_3yr),
            by = c("draft_season", "pick")) %>%
  mutate(best_finish = pmin(finish_y1, finish_y2, finish_y3, na.rm = TRUE),
         tier = case_when(best_finish <= 12 ~ 1L, best_finish <= 24 ~ 2L,
                          best_finish <= 36 ~ 3L, TRUE ~ 4L))
train <- tbl %>% filter(!is.na(finish_sum_3yr)) %>%
  mutate(y1 = as.integer(tier <= 1), y2 = as.integer(tier <= 2), y3 = as.integer(tier <= 3))
score <- tbl %>% filter(is.na(finish_sum_3yr), draft_season >= 2024)

cat("training rows:", nrow(train), " WR1:", sum(train$y1), " WR2+:", sum(train$y2), " WR3+:", sum(train$y3), "\n")
print(as.data.frame(train %>% mutate(day = ifelse(round == 1, "R1", ifelse(round <= 3, "R2-3", "R4-7"))) %>%
  group_by(day) %>% summarize(n = n(), WR1 = sum(y1), WR2plus = sum(y2), WR3plus = sum(y3), .groups = "drop")),
  row.names = FALSE)

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

# --- Ladder model ---------------------------------------------------------------
fit_log <- character(0)
ladder <- function(tr, te, model) {
  if (model == "pick_only") {
    fit <- polr(factor(tier, levels = 1:4, ordered = TRUE) ~ log_pick, data = tr, Hess = TRUE)
    pr <- predict(fit, te, type = "probs")
  } else {
    num <- if (model == "pre_enet") pre_num else c(pre_num, post_num)
    pp <- fit_prep(tr, num)
    Xtr <- as.matrix(apply_prep(pp, tr)); Xte <- as.matrix(apply_prep(pp, te))
    sc <- apply(Xtr, 2, sd); sc[sc == 0] <- 1; ce <- colMeans(Xtr)       # standardize on train
    Xtr <- scale(Xtr, ce, sc); Xte <- scale(Xte, ce, sc)
    y <- factor(tr$tier, levels = 1:4, ordered = TRUE)
    folds <- split(seq_len(nrow(tr)), tr$draft_season)                  # inner CV by class
    fit_full <- ordinalNet(Xtr, y, family = "cumulative", link = "logit", alpha = 0.5,
                           parallelTerms = TRUE, nonparallelTerms = FALSE, nLambda = 25,
                           standardize = FALSE)
    tune <- ordinalNetTune(Xtr, y, lambdaVals = fit_full$lambdaVals, folds = folds,
                           printProgress = FALSE, warn = FALSE, family = "cumulative",
                           link = "logit", alpha = 0.5, parallelTerms = TRUE,
                           nonparallelTerms = FALSE, standardize = FALSE)
    best <- which.max(rowMeans(tune$loglik))
    fit_log <<- c(fit_log, sprintf("%s n=%d lambda#%d", model, nrow(tr), best))
    pr <- predict(fit_full, Xte, whichLambda = best, type = "response")
  }
  pr <- matrix(pr, ncol = 4)
  data.frame(p_wr1 = pr[, 1], p_wr2plus = pr[, 1] + pr[, 2], p_wr3plus = pr[, 1] + pr[, 2] + pr[, 3])
}

# --- Evaluation -----------------------------------------------------------------
run_cv <- function(scheme) {
  out <- list()
  tests <- if (scheme == "LOCO") sort(unique(train$draft_season)) else 2016:2023
  for (model in c("pick_only", "pre_enet", "post_enet")) for (Y in tests) {
    tr <- if (scheme == "LOCO") filter(train, draft_season != Y) else filter(train, draft_season <= Y - 3)
    te <- filter(train, draft_season == Y)
    out[[length(out) + 1]] <- cbind(te[, c("draft_season", "round", "pick", "pfr_player_name",
                                           "best_finish", "tier", "y1", "y2", "y3")],
                                    scheme = scheme, model = model, ladder(tr, te, model))
  }
  bind_rows(out)
}
oof <- bind_rows(run_cv("LOCO"), run_cv("Rolling"))
stopifnot(all(oof$p_wr1 <= oof$p_wr2plus + 1e-9), all(oof$p_wr2plus <= oof$p_wr3plus + 1e-9))
cat("ladder order P(WR1) <= P(WR2+) <= P(WR3+) holds for every prediction\n")
write.csv(oof, "phase6_oof_predictions.csv", row.names = FALSE)

oof$rps <- ((oof$p_wr1 - oof$y1)^2 + (oof$p_wr2plus - oof$y2)^2 + (oof$p_wr3plus - oof$y3)^2) / 3
aucf <- function(y, p) if (length(unique(y)) < 2 || sd(p) == 0) NA else as.numeric(auc(roc(y, p, quiet = TRUE)))
summ <- function(d) d %>% summarize(n = n(), RPS = mean(rps),
            AUC_WR1 = aucf(y1, p_wr1), AUC_WR2plus = aucf(y2, p_wr2plus), AUC_WR3plus = aucf(y3, p_wr3plus),
            Brier_WR1 = mean((p_wr1 - y1)^2), Brier_WR2plus = mean((p_wr2plus - y2)^2),
            Brier_WR3plus = mean((p_wr3plus - y3)^2), .groups = "drop") %>%
  mutate(across(where(is.double), ~ round(.x, 4)))
metrics <- oof %>% group_by(scheme, model) %>% summ() %>% arrange(scheme, model)
cat("\n===== Tier ladder: cross-validated performance (RPS & Brier lower = better) =====\n")
print(as.data.frame(metrics), row.names = FALSE)
write.csv(metrics, "phase6_cv_metrics.csv", row.names = FALSE)
cat("\nDay 3 (rounds 4-7) only:\n")
print(as.data.frame(oof %>% filter(round >= 4) %>% group_by(scheme, model) %>% summ()), row.names = FALSE)

set.seed(2026)
w <- oof %>% filter(scheme == "Rolling") %>% select(draft_season, pick, model, rps) %>%
  pivot_wider(names_from = model, values_from = rps)
bt <- function(a, b) {
  d <- replicate(2000, { i <- sample.int(nrow(w), replace = TRUE); mean(a[i] - b[i]) })
  sprintf("%+.4f  95%% CI [%+.4f, %+.4f]  share < 0: %.3f", mean(a - b), quantile(d, .025), quantile(d, .975), mean(d < 0))
}
cat("\n===== Bootstrap, rolling origin, RPS (2000 draws, seed 2026; negative = first better) =====\n")
cat("post minus pick-only:", bt(w$post_enet, w$pick_only), "\n")
cat("pre  minus pick-only:", bt(w$pre_enet, w$pick_only), "\n")

cat("\n===== WR3+ calibration by quintile, rolling origin =====\n")
print(as.data.frame(oof %>% filter(scheme == "Rolling") %>% group_by(model) %>%
  mutate(q = ntile(p_wr3plus, 5)) %>% group_by(model, q) %>%
  summarize(n = n(), mean_p = round(mean(p_wr3plus), 3), actual = round(mean(y3), 3), .groups = "drop")),
  row.names = FALSE)

# =============================================================================
# Hidden-talent back-test (Day 3, rolling origin)
# =============================================================================
hw <- oof %>% filter(scheme == "Rolling", round >= 4) %>%
  select(draft_season, round, pick, pfr_player_name, best_finish, y2, y3, model, p_wr2plus, p_wr3plus) %>%
  pivot_wider(names_from = model, values_from = c(p_wr2plus, p_wr3plus)) %>%
  mutate(score_wr2 = p_wr2plus_post_enet - p_wr2plus_pick_only,
         score_wr3 = p_wr3plus_post_enet - p_wr3plus_pick_only,
         score_pre_wr3 = p_wr3plus_pre_enet - p_wr3plus_pick_only)
write.csv(hw, "phase6_hidden_talent_backtest.csv", row.names = FALSE)

topk <- function(col, k, outcome) {
  hw %>% group_by(draft_season) %>%
    arrange(desc(.data[[col]]), pick, .by_group = TRUE) %>% slice_head(n = k) %>%
    summarize(hits = sum(.data[[outcome]]),
              names = paste(pfr_player_name[.data[[outcome]] == 1], collapse = ", "), .groups = "drop")
}
cat("\n===== Day-3 top-k hit counts, rolling 2016-2023 (", nrow(hw), "Day-3 WRs;",
    sum(hw$y3), "WR3+,", sum(hw$y2), "WR2+ ) =====\n")
hw <- hw %>% mutate(earliest = -pick)          # pick-only ranking = earliest Day-3 picks
res <- list()
for (k in c(5, 10)) for (oc in c("y3", "y2")) {
  rand <- hw %>% group_by(draft_season) %>% summarize(e = min(k, n()) * mean(.data[[oc]]), .groups = "drop")
  row <- data.frame(k = k, outcome = ifelse(oc == "y3", "WR3+", "WR2+"),
    hidden_score_post = sum(topk(ifelse(oc == "y3", "score_wr3", "score_wr2"), k, oc)$hits),
    hidden_score_pre  = sum(topk("score_pre_wr3", k, oc)$hits),
    post_model_prob   = sum(topk(ifelse(oc == "y3", "p_wr3plus_post_enet", "p_wr2plus_post_enet"), k, oc)$hits),
    earliest_picks    = sum(topk("earliest", k, oc)$hits),
    random_expected   = round(sum(rand$e), 1))
  res[[length(res) + 1]] <- row
}
print(bind_rows(res), row.names = FALSE)
cat("(columns: hits among each class's top-k Day-3 WRs ranked by: post-draft hidden score,\n",
    " pre-draft hidden score (WR3+ gap), post-draft P itself, earliest pick, random)\n")

cat("\nper-year hit lists, top 10 by post-draft hidden score (WR3+ version):\n")
print(as.data.frame(topk("score_wr3", 10, "y3")), row.names = FALSE)
cat("\nper-year hit lists, top 10 by earliest Day-3 pick:\n")
print(as.data.frame(topk("earliest", 10, "y3")), row.names = FALSE)
cat("\nper-year hit lists, top 10 by pre-draft hidden score:\n")
print(as.data.frame(topk("score_pre_wr3", 10, "y3")), row.names = FALSE)

known <- c("Tyreek Hill", "Puka Nacua", "Amon-Ra St. Brown", "Hunter Renfrow", "Mike Williams",
           "Stefon Diggs", "Antonio Brown", "Darnell Mooney")
ranks <- hw %>% group_by(draft_season) %>%
  mutate(n_day3 = n(),
         rank_post_wr2 = rank(-score_wr2, ties.method = "min"),
         rank_post_wr3 = rank(-score_wr3, ties.method = "min"),
         rank_pre_wr3  = rank(-score_pre_wr3, ties.method = "min"),
         rank_by_pick  = rank(pick)) %>% ungroup() %>%
  filter(pfr_player_name %in% known, round >= 4) %>%
  select(draft_season, pick, pfr_player_name, best_finish, n_day3, rank_by_pick,
         rank_post_wr2, rank_post_wr3, rank_pre_wr3)
cat("\nknown Day-3 WR2+ hits in the test years (2016-2023): rank among that class's Day-3 WRs\n")
print(as.data.frame(ranks), row.names = FALSE)
cat("(not in test years: ", paste(setdiff(known, ranks$pfr_player_name), collapse = ", "), ")\n")

# =============================================================================
# 2024-2026 board
# =============================================================================
board <- score %>% select(pfr_player_name, draft_season, round, pick, draft_team, college, finish_y1, finish_y2)
for (model in c("pick_only", "pre_enet", "post_enet")) {
  f <- ladder(train, score, model)
  names(f) <- paste0(model, "_", names(f)); board <- bind_cols(board, round(f, 3))
}
hb <- read.csv("wr_finish_hurdle_board_2024_2026.csv") %>%
  select(draft_season, pick, p_top100 = post_enet_p_relevant, expected_finish_score = post_enet_two_step)
board <- board %>% left_join(hb, by = c("draft_season", "pick")) %>%
  mutate(best_finish_so_far = pmin(finish_y1, finish_y2, na.rm = TRUE),
         hidden_wr2_post = round(post_enet_p_wr2plus - pick_only_p_wr2plus, 3),
         hidden_wr3_post = round(post_enet_p_wr3plus - pick_only_p_wr3plus, 3),
         hidden_wr3_pre  = round(pre_enet_p_wr3plus - pick_only_p_wr3plus, 3)) %>%
  arrange(draft_season, desc(post_enet_p_wr3plus))
write.csv(board, "wr_tier_board_2024_2026.csv", row.names = FALSE)

cat("\n===== 2024-2026: top 10 per class by post-draft P(WR3+) =====\n")
print(as.data.frame(board %>% group_by(draft_season) %>% slice_head(n = 10) %>% ungroup() %>%
  select(draft_season, pick, pfr_player_name, post_enet_p_wr1, post_enet_p_wr2plus, post_enet_p_wr3plus,
         best_finish_so_far)), row.names = FALSE)
cat("\n===== Day-3 hidden-talent list: top 8 per class by post-draft hidden score (WR3+) =====\n")
print(as.data.frame(board %>% filter(round >= 4) %>% group_by(draft_season) %>%
  arrange(desc(hidden_wr3_post), .by_group = TRUE) %>% slice_head(n = 8) %>% ungroup() %>%
  select(draft_season, pick, pfr_player_name, pick_only_p_wr3plus, post_enet_p_wr3plus, hidden_wr3_post,
         hidden_wr2_post, hidden_wr3_pre, best_finish_so_far)), row.names = FALSE)
cat("\nfinal-fit lambda choices:", paste(tail(fit_log, 2), collapse = "; "), "\n")
cat("saved phase6_cv_metrics.csv, phase6_oof_predictions.csv, phase6_hidden_talent_backtest.csv,",
    "wr_tier_board_2024_2026.csv\n")
