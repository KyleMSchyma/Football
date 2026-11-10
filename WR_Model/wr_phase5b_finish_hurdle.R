# =============================================================================
# WR Model -- Phase 5b: two-step (hurdle) model for the 3-year finish score
#
# About half of drafted WRs never post a top-100 season (finish score = 300), so the
# finish score is a spike at 300 plus a spread of real careers. Two steps:
#   Step 1  P(relevant) = P(at least one top-100 WR season in years 1-3)   [logistic]
#   Step 2  E[finish score | relevant]                                     [Gaussian]
#   Combined expected score = p * E[score | relevant] + (1 - p) * 300
#
# Models per step: pick-only (log pick), pre-draft elastic net, post-draft elastic net
# (same features and in-fold preprocessing as Phases 3/5). Compared with the
# one-step models from Phase 5 under rolling origin (test 2016-2023, train on
# classes <= Y - 3) and leave-one-class-out.
#
# Inputs: wr_model_table.rds, phase5_finish_targets.csv
# Outputs: phase5b_cv_metrics.csv, phase5b_oof_predictions.csv,
#          wr_finish_hurdle_board_2024_2026.csv
# =============================================================================

suppressMessages({ library(dplyr); library(tidyr); library(glmnet); library(pROC) })
set.seed(2026)
CAP <- 100; MAXS <- 3 * CAP

tbl <- readRDS("wr_model_table.rds") %>%
  mutate(final_power5 = as.integer(final_power5), combine_invited = as.integer(combine_invited)) %>%
  left_join(read.csv("phase5_finish_targets.csv") %>%
              select(draft_season, pick, finish_y1, finish_y2, finish_sum_3yr),
            by = c("draft_season", "pick")) %>%
  mutate(relevant = as.integer(finish_sum_3yr < MAXS))
train <- tbl %>% filter(!is.na(finish_sum_3yr))
score <- tbl %>% filter(is.na(finish_sum_3yr), draft_season >= 2024)
cat("training rows:", nrow(train), " relevant (any top-100 season):", sum(train$relevant),
    sprintf("(%.1f%%)", 100 * mean(train$relevant)), "\n")
cat("relevant rate by round:\n")
print(as.data.frame(train %>% group_by(round) %>% summarize(n = n(), pct_relevant = round(mean(relevant), 2),
  mean_score_if_relevant = round(mean(finish_sum_3yr[relevant == 1]), 1), .groups = "drop")))

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
enet <- function(Xtr, y, Xte, fam, folds) {
  # inner CV grouped by class; fall back to fewer folds if a class has too few rows
  en <- cv.glmnet(as.matrix(Xtr), y, family = fam, alpha = 0.5, foldid = folds)
  as.numeric(predict(en, as.matrix(Xte), s = "lambda.min", type = "response"))
}
clamp <- function(x) pmin(pmax(x, 3), MAXS)

# Returns, for the te rows: p_relevant, score_if_relevant, combined, and one-step
# Step-2 target: raw score, or log(300 - score) back-transformed as 300 - exp(pred).
# Chosen per fit by inner class-grouped CV RMSE on the ORIGINAL score scale.
to_score <- function(z, form) if (form == "log") MAXS - exp(z) else z
step2_pick_only <- function(rel_tr, te) {
  cv_err <- sapply(c("raw", "log"), function(form) {
    e <- unlist(lapply(unique(rel_tr$draft_season), function(cl) {
      a <- filter(rel_tr, draft_season != cl); b <- filter(rel_tr, draft_season == cl)
      yv <- if (form == "log") log(MAXS - a$finish_sum_3yr) else a$finish_sum_3yr
      to_score(predict(lm(yv ~ log_pick, data = cbind(a, yv = yv)), b), form) - b$finish_sum_3yr
    }))
    sqrt(mean(e^2))
  })
  form <- names(which.min(cv_err))
  yv <- if (form == "log") log(MAXS - rel_tr$finish_sum_3yr) else rel_tr$finish_sum_3yr
  list(s = to_score(predict(lm(yv ~ log_pick, data = cbind(rel_tr, yv = yv)), te), form), form = form)
}
step2_enet <- function(Xr, yr, Xte, folds) {
  fits <- lapply(c(raw = "raw", log = "log"), function(form) {
    yv <- if (form == "log") log(MAXS - yr) else yr
    cv.glmnet(as.matrix(Xr), yv, alpha = 0.5, foldid = folds, keep = TRUE)
  })
  cv_err <- sapply(names(fits), function(form) {
    f <- fits[[form]]
    pre <- f$fit.preval[, which(f$lambda == f$lambda.min)]   # inner out-of-fold predictions
    sqrt(mean((to_score(pre, form) - yr)^2))
  })
  form <- names(which.min(cv_err))
  list(s = to_score(as.numeric(predict(fits[[form]], as.matrix(Xte), s = "lambda.min")), form), form = form)
}

two_step <- function(tr, te, model) {
  rel <- tr$relevant == 1
  if (model == "pick_only") {
    m1 <- glm(relevant ~ log_pick, family = binomial, data = tr)
    m0 <- lm(finish_sum_3yr ~ log_pick, data = tr)
    p  <- predict(m1, te, type = "response")
    s2 <- step2_pick_only(tr[rel, ], te)
    one <- clamp(predict(m0, te))
  } else {
    num <- if (model == "pre_enet") pre_num else c(pre_num, post_num)
    pp <- fit_prep(tr, num); Xtr <- apply_prep(pp, tr); Xte <- apply_prep(pp, te)
    folds <- as.integer(factor(tr$draft_season))
    p <- enet(Xtr, tr$relevant, Xte, "binomial", folds)
    # step 2 refits preprocessing on the relevant rows only
    pp2 <- fit_prep(tr[rel, ], num)
    s2 <- step2_enet(apply_prep(pp2, tr[rel, ]), tr$finish_sum_3yr[rel], apply_prep(pp2, te),
                     as.integer(factor(tr$draft_season[rel])))
    one <- clamp(enet(Xtr, tr$finish_sum_3yr, Xte, "gaussian", folds))
  }
  s <- pmin(pmax(s2$s, 3), MAXS - 1)
  data.frame(p_relevant = p, score_if_relevant = s, step2_form = s2$form,
             two_step = p * s + (1 - p) * MAXS, one_step = one)
}

# --- Evaluation -----------------------------------------------------------------
run_cv <- function(scheme) {
  out <- list()
  tests <- if (scheme == "LOCO") sort(unique(train$draft_season)) else 2016:2023
  for (model in c("pick_only", "pre_enet", "post_enet")) for (Y in tests) {
    tr <- if (scheme == "LOCO") filter(train, draft_season != Y) else filter(train, draft_season <= Y - 3)
    te <- filter(train, draft_season == Y)
    out[[length(out) + 1]] <- cbind(te[, c("draft_season", "pick", "pfr_player_name", "relevant", "finish_sum_3yr")],
                                    scheme = scheme, model = model, two_step(tr, te, model))
  }
  bind_rows(out)
}
oof <- bind_rows(run_cv("LOCO"), run_cv("Rolling"))
write.csv(oof, "phase5b_oof_predictions.csv", row.names = FALSE)
cat("\nstep-2 target chosen by inner CV (count of fold fits, one per test class):\n")
print(as.data.frame(oof %>% distinct(scheme, model, draft_season, step2_form) %>%
  count(scheme, model, step2_form)), row.names = FALSE)

wc_rho <- function(pred, actual, cls) {
  r <- sapply(split(seq_along(pred), cls), function(i)
    if (sd(pred[i]) > 0) cor(pred[i], actual[i], method = "spearman") else NA)
  mean(r, na.rm = TRUE)
}
metrics <- oof %>% pivot_longer(c(two_step, one_step), names_to = "approach", values_to = "pred") %>%
  group_by(scheme, model, approach) %>%
  summarize(n = n(),
            within_class_Spearman = wc_rho(-pred, -finish_sum_3yr, draft_season),
            RMSE = sqrt(mean((pred - finish_sum_3yr)^2)),
            MAE = mean(abs(pred - finish_sum_3yr)),
            step1_AUC = as.numeric(auc(roc(relevant, p_relevant, quiet = TRUE))),
            step1_Brier = mean((p_relevant - relevant)^2),
            step2_RMSE_relevant = sqrt(mean((score_if_relevant[relevant == 1] - finish_sum_3yr[relevant == 1])^2)),
            .groups = "drop") %>%
  mutate(across(where(is.double), ~ round(.x, 3)),
         across(c(step1_AUC, step1_Brier, step2_RMSE_relevant), ~ ifelse(approach == "one_step", NA, .x))) %>%
  arrange(scheme, model, approach)
cat("\n===== Two-step vs one-step, finish score (lower = better; Spearman higher = better) =====\n")
print(as.data.frame(metrics), row.names = FALSE)
write.csv(metrics, "phase5b_cv_metrics.csv", row.names = FALSE)

# Bootstrap (rolling origin): post two-step minus pick-only two-step, and post
# two-step minus post one-step, on RMSE and MAE
set.seed(2026)
r <- oof %>% filter(scheme == "Rolling")
wide <- r %>% select(draft_season, pick, model, finish_sum_3yr, two_step, one_step) %>%
  pivot_wider(names_from = model, values_from = c(two_step, one_step))
y <- wide$finish_sum_3yr
boot <- function(a, b, f) {
  pt <- f(a, y) - f(b, y)
  d <- replicate(2000, { i <- sample.int(length(y), replace = TRUE); f(a[i], y[i]) - f(b[i], y[i]) })
  sprintf("%+.2f  95%% CI [%+.2f, %+.2f]  share < 0: %.3f", pt, quantile(d, .025), quantile(d, .975), mean(d < 0))
}
rmse <- function(p, y) sqrt(mean((p - y)^2)); mae <- function(p, y) mean(abs(p - y))
cat("\n===== Bootstrap, rolling origin (2000 draws, seed 2026; negative = first model better) =====\n")
cat("post two-step minus pick-only two-step, RMSE:", boot(wide$two_step_post_enet, wide$two_step_pick_only, rmse), "\n")
cat("post two-step minus pick-only two-step, MAE: ", boot(wide$two_step_post_enet, wide$two_step_pick_only, mae), "\n")
cat("post two-step minus pick-only ONE-step, RMSE:", boot(wide$two_step_post_enet, wide$one_step_pick_only, rmse), "\n")
cat("post two-step minus post one-step, RMSE:     ", boot(wide$two_step_post_enet, wide$one_step_post_enet, rmse), "\n")
cat("post two-step minus post one-step, MAE:      ", boot(wide$two_step_post_enet, wide$one_step_post_enet, mae), "\n")
cat("pick-only two-step minus pick-only one-step, MAE:", boot(wide$two_step_pick_only, wide$one_step_pick_only, mae), "\n")
cat("pre two-step minus pick-only two-step, MAE:  ", boot(wide$two_step_pre_enet, wide$two_step_pick_only, mae), "\n")

# Step-1 calibration (rolling, post)
cal <- r %>% filter(model == "post_enet") %>%
  mutate(bin = cut(p_relevant, c(0, .2, .4, .6, .8, 1), include.lowest = TRUE)) %>%
  group_by(bin) %>% summarize(n = n(), mean_p = round(mean(p_relevant), 3),
                              actual = round(mean(relevant), 3), .groups = "drop")
cat("\nstep-1 calibration, post-draft, rolling origin:\n"); print(as.data.frame(cal), row.names = FALSE)

# --- 2024-2026 board ------------------------------------------------------------
board <- score %>% select(pfr_player_name, draft_season, round, pick, draft_team, college,
                          finish_y1, finish_y2)
for (model in c("pick_only", "pre_enet", "post_enet")) {
  f <- two_step(train, score, model)
  board[[paste0(model, "_p_relevant")]] <- round(f$p_relevant, 3)
  board[[paste0(model, "_score_if_relevant")]] <- round(f$score_if_relevant, 1)
  board[[paste0(model, "_two_step")]] <- round(f$two_step, 1)
  board[[paste0(model, "_one_step")]] <- round(f$one_step, 1)
  cat("final fit,", model, "step-2 target:", f$step2_form[1], "\n")
}
board <- board %>% group_by(draft_season) %>%
  mutate(rank_hurdle = rank(post_enet_two_step, ties.method = "first"),
         rank_single = rank(post_enet_one_step, ties.method = "first"),
         rank_diff = rank_single - rank_hurdle) %>% ungroup() %>%   # positive = hurdle ranks him higher
  arrange(draft_season, post_enet_two_step)
cat("\nplayers whose within-class rank differs by 10+ places (post-draft hurdle vs single-step):\n")
big <- board %>% filter(abs(rank_diff) >= 10) %>%
  select(draft_season, pick, pfr_player_name, post_enet_p_relevant, post_enet_score_if_relevant,
         post_enet_two_step, post_enet_one_step, rank_hurdle, rank_single, rank_diff)
if (nrow(big)) print(as.data.frame(big), row.names = FALSE) else cat("none\n")
write.csv(board, "wr_finish_hurdle_board_2024_2026.csv", row.names = FALSE)
cat("\n===== 2024-2026, post-draft two-step: top 10 per class =====\n")
print(as.data.frame(board %>% group_by(draft_season) %>% slice_head(n = 10) %>% ungroup() %>%
  select(draft_season, pick, pfr_player_name, post_enet_p_relevant, post_enet_score_if_relevant,
         post_enet_two_step, pick_only_two_step, pre_enet_two_step, finish_y1, finish_y2)), row.names = FALSE)
cat("\nsaved phase5b_cv_metrics.csv, phase5b_oof_predictions.csv, wr_finish_hurdle_board_2024_2026.csv\n")
