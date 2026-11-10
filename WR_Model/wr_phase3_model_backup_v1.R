# =============================================================================
# WR Model -- Phase 3: model training, validation and 2024-2026 projections
#
# Predicts, for each drafted WR:
#   total_ppr_3yr  total PPR points in NFL years 1-3        (regression)
#   hit_3yr        1 if any top-24 WR PPR season, years 1-3 (classification)
#
# Two feature sets:
#   pre-draft   college production, breakout age, age, combine, recruiting
#   post-draft  pre-draft + draft capital (log pick) + landing spot (vacated targets)
#
# Validation: leave-one-draft-class-out cross-validation on the 2010-2023 classes
# (14 folds). Every preprocessing step -- median imputation, missing flags, and the
# PCA of combine drills -- is fit on the training classes only inside each fold, so
# the held-out class never leaks into training (ATPA 3.7a).
#
# Models compared in each fold:
#   baseline      regression: mean (pre-draft) or linear on log pick (post-draft)
#                 classification: base rate (pre-draft) or logistic on log pick
#   elastic net   glmnet, alpha = 0.5, lambda chosen by inner class-grouped CV
#   random forest ranger, 500 trees
#
# Inputs:  wr_model_table.rds (Phase 2)
# Outputs: phase3_cv_metrics.csv, phase3_oof_predictions.csv,
#          phase3_importance.csv, wr_projections_2024_2026.csv,
#          plot_p3_*.png
# Requires: dplyr, tidyr, ggplot2, glmnet, ranger, pROC
# Decisions used (Kyle's open questions, defaulted):
#   main target total_ppr_3yr + hit_3yr classifier; both pre- and post-draft sets;
#   final_yds_share dropped (redundant with dominator / yptpa); unmatched WRs kept
#   with imputation + college_matched flag; breakout rule and top-24 hit unchanged.
# =============================================================================

suppressMessages({
  library(dplyr); library(tidyr); library(ggplot2)
  library(glmnet); library(ranger); library(pROC)
})
set.seed(2026)
mycols <- c("#E69F00", "#56B4E9", "#009E73", "#F0E442", "#0072B2", "#D55E00", "#CC79A7")

tbl <- readRDS("wr_model_table.rds") %>%
  mutate(final_power5 = as.integer(final_power5),
         combine_invited = as.integer(combine_invited))

train <- tbl %>% filter(!is.na(total_ppr_3yr))
score <- tbl %>% filter(is.na(total_ppr_3yr), draft_season >= 2024)
cat("training rows:", nrow(train), "(classes", paste(range(train$draft_season), collapse = "-"), ")\n")
cat("rows to project:", nrow(score), "\n"); print(table(score$draft_season))

# --- Feature sets -------------------------------------------------------------
drills   <- c("forty", "vertical", "broad_jump", "speed_score")   # -> PCA in-fold
pre_num  <- c("age_at_draft", "final_dominator", "best_dominator", "final_yptpa",
              "breakout_age_filled", "career_rec_yds", "college_seasons",
              "height_in", "weight_lb", "recruit_rating")
pre_flag <- c("broke_out", "transferred", "early_declare", "final_power5",
              "college_matched", "combine_invited", "miss_forty", "miss_vertical",
              "miss_broad_jump")
post_num <- c("log_pick", "vacated_target_share", "team_targets_prev")

# --- In-fold preprocessing ----------------------------------------------------
# fit_prep() learns medians, which columns need a missing flag, and the drill PCA
# from the TRAINING rows only; apply_prep() applies them to any rows.
fit_prep <- function(d, num) {
  med  <- sapply(c(num, drills), function(v) median(d[[v]], na.rm = TRUE))
  flag <- num[sapply(num, function(v) any(is.na(d[[v]])))]
  dm <- as.matrix(d[, drills])
  for (v in drills) dm[is.na(dm[, v]), v] <- med[v]
  pca <- prcomp(dm, center = TRUE, scale. = TRUE)
  list(num = num, med = med, flag = flag, pca = pca)
}
apply_prep <- function(p, d) {
  out <- data.frame(row.names = seq_len(nrow(d)))
  for (v in p$num) {
    x <- d[[v]]
    if (v %in% p$flag) out[[paste0("na_", v)]] <- as.integer(is.na(x))
    x[is.na(x)] <- p$med[v]
    out[[v]] <- x
  }
  dm <- as.matrix(d[, drills])
  for (v in drills) dm[is.na(dm[, v]), v] <- p$med[v]
  pcs <- predict(p$pca, dm)[, 1:2, drop = FALSE]
  out$athletic_pc1 <- pcs[, 1]
  out$athletic_pc2 <- pcs[, 2]
  for (v in pre_flag) out[[v]] <- as.integer(coalesce(as.numeric(d[[v]]), 0))
  out
}

# --- Fit one model family on train rows, predict new rows ---------------------
fit_predict <- function(tr, te, set, target) {
  num <- if (set == "pre") pre_num else c(pre_num, post_num)
  p   <- fit_prep(tr, num)
  Xtr <- apply_prep(p, tr); Xte <- apply_prep(p, te)
  y   <- tr[[target]]
  fam <- if (target == "hit_3yr") "binomial" else "gaussian"

  # baseline
  base <- if (set == "pre") rep(mean(y), nrow(te)) else {
    if (fam == "binomial")
      predict(glm(y ~ log_pick, family = binomial, data = cbind(Xtr, y = y)), Xte, type = "response")
    else predict(lm(y ~ log_pick, data = cbind(Xtr, y = y)), Xte)
  }

  # elastic net, lambda picked by inner CV grouped by draft class
  foldid <- as.integer(factor(tr$draft_season))
  en <- cv.glmnet(as.matrix(Xtr), y, family = fam, alpha = 0.5, foldid = foldid)
  enet <- as.numeric(predict(en, as.matrix(Xte), s = "lambda.min", type = "response"))

  # random forest
  if (fam == "binomial") {
    rf <- ranger(x = Xtr, y = factor(y), num.trees = 500, probability = TRUE,
                 min.node.size = 10, seed = 2026)
    rfp <- predict(rf, Xte)$predictions[, "1"]
  } else {
    rf <- ranger(x = Xtr, y = y, num.trees = 500, min.node.size = 10, seed = 2026)
    rfp <- predict(rf, Xte)$predictions
  }
  if (fam == "gaussian") { base <- pmax(0, base); enet <- pmax(0, enet); rfp <- pmax(0, rfp) }
  list(pred = data.frame(baseline = base, elastic_net = enet, random_forest = rfp),
       enet_fit = en, rf_fit = rf, Xtr = Xtr)
}

# =============================================================================
# Leave-one-class-out cross-validation
# =============================================================================
classes <- sort(unique(train$draft_season))
oof <- list()
leak_ok <- TRUE
for (set in c("pre", "post")) for (target in c("total_ppr_3yr", "hit_3yr")) {
  for (cl in classes) {
    tr <- train %>% filter(draft_season != cl)
    te <- train %>% filter(draft_season == cl)
    if (any(tr$draft_season == cl)) leak_ok <- FALSE
    r <- fit_predict(tr, te, set, target)
    oof[[length(oof) + 1]] <- cbind(
      te[, c("draft_season", "pick", "round", "pfr_player_name")],
      set = set, target = target, actual = te[[target]], r$pred)
  }
  cat("CV done:", set, target, "\n")
}
oof <- bind_rows(oof)

# --- Metrics ------------------------------------------------------------------
long <- oof %>% pivot_longer(c(baseline, elastic_net, random_forest),
                             names_to = "model", values_to = "pred")
reg_m <- long %>% filter(target == "total_ppr_3yr") %>%
  group_by(set, model) %>%
  summarize(RMSE = sqrt(mean((pred - actual)^2)), MAE = mean(abs(pred - actual)),
            R2 = 1 - sum((pred - actual)^2) / sum((actual - mean(actual))^2),
            Spearman = cor(pred, actual, method = "spearman"), .groups = "drop")
cls_m <- long %>% filter(target == "hit_3yr") %>%
  group_by(set, model) %>%
  summarize(AUC = if (sd(pred) > 0) as.numeric(auc(roc(actual, pred, quiet = TRUE))) else 0.5,
            Brier = mean((pred - actual)^2),
            LogLoss = -mean(actual * log(pmin(pmax(pred, 1e-6), 1 - 1e-6)) +
                            (1 - actual) * log(1 - pmin(pmax(pred, 1e-6), 1 - 1e-6))),
            .groups = "drop")
metrics <- full_join(reg_m, cls_m, by = c("set", "model")) %>%
  mutate(across(where(is.numeric), ~ round(.x, 3))) %>% arrange(set, model)
cat("\n===== Cross-validated performance (leave-one-class-out, 2010-2023) =====\n")
print(as.data.frame(metrics))
write.csv(metrics, "phase3_cv_metrics.csv", row.names = FALSE)
write.csv(oof, "phase3_oof_predictions.csv", row.names = FALSE)

# Pick the best model per set/target by Spearman (regression) and Brier (classification)
best_reg <- reg_m %>% filter(model != "baseline") %>% group_by(set) %>% slice_max(Spearman, n = 1) %>% ungroup()
best_cls <- cls_m %>% filter(model != "baseline") %>% group_by(set) %>% slice_min(Brier, n = 1) %>% ungroup()
cat("\nbest regression model:     ", paste(best_reg$set, best_reg$model, collapse = "; "), "\n")
cat("best classification model: ", paste(best_cls$set, best_cls$model, collapse = "; "), "\n")

# Calibration of hit probabilities (post-draft, best model)
bc <- best_cls$model[best_cls$set == "post"]
cal <- long %>% filter(target == "hit_3yr", set == "post", model == bc) %>%
  mutate(bin = cut(pred, c(0, .05, .15, .3, .5, 1), include.lowest = TRUE)) %>%
  group_by(bin) %>% summarize(n = n(), mean_pred = round(mean(pred), 3),
                              actual_rate = round(mean(actual), 3), .groups = "drop")
cat("\ncalibration, post-draft", bc, "hit probabilities:\n"); print(as.data.frame(cal))

# =============================================================================
# Final models on all 2010-2023 classes -> project 2024-2026
# =============================================================================
proj <- score %>% select(draft_season, round, pick, pfr_player_name, college, draft_team)
imp_all <- list()
for (set in c("pre", "post")) {
  rr <- fit_predict(train, score, set, "total_ppr_3yr")
  rc <- fit_predict(train, score, set, "hit_3yr")
  br <- best_reg$model[best_reg$set == set]; bcl <- best_cls$model[best_cls$set == set]
  proj[[paste0(set, "_ppr_3yr")]] <- round(rr$pred[[br]], 1)
  proj[[paste0(set, "_hit_prob")]] <- round(rc$pred[[bcl]], 3)
  # permutation importance from a forest refit with importance on
  rfi <- ranger(x = rr$Xtr, y = train$total_ppr_3yr, num.trees = 500, min.node.size = 10,
                importance = "permutation", seed = 2026)
  imp_all[[set]] <- data.frame(set = set, feature = names(rfi$variable.importance),
                               importance = round(rfi$variable.importance, 1))
  co <- coef(rr$enet_fit, s = "lambda.min")
  cat("\nelastic net (", set, ", total_ppr_3yr) nonzero coefficients:\n", sep = "")
  nz <- co[which(co[, 1] != 0), 1]
  print(round(nz[order(-abs(nz))], 3))
}
imp <- bind_rows(imp_all) %>% group_by(set) %>% arrange(desc(importance), .by_group = TRUE) %>% ungroup()
write.csv(imp, "phase3_importance.csv", row.names = FALSE)
cat("\nrandom forest permutation importance (top 10 per set):\n")
print(as.data.frame(imp %>% group_by(set) %>% slice_head(n = 10)))

# Players with < 3 complete NFL seasons already have partial results; show them
# alongside the projection (actual so far, not used in training).
proj <- proj %>%
  left_join(score %>% select(draft_season, pick, yr1_ppr), by = c("draft_season", "pick")) %>%
  mutate(draft_value = round(post_ppr_3yr - pre_ppr_3yr, 1)) %>%
  arrange(draft_season, desc(post_ppr_3yr))
write.csv(proj, "wr_projections_2024_2026.csv", row.names = FALSE)
cat("\n===== Projections (post-draft model), top 10 per class =====\n")
print(as.data.frame(proj %>% group_by(draft_season) %>% slice_head(n = 10) %>%
  select(draft_season, pick, pfr_player_name, post_ppr_3yr, post_hit_prob, pre_ppr_3yr, yr1_ppr)))

# --- Plots --------------------------------------------------------------------
brp <- best_reg$model[best_reg$set == "post"]
g1 <- ggplot(oof %>% filter(target == "total_ppr_3yr", set == "post"),
             aes(x = .data[[brp]], y = actual)) +
  geom_abline(linetype = 2, color = "grey40") +
  geom_point(alpha = 0.5, color = mycols[5]) +
  labs(title = paste("Out-of-fold predicted vs actual 3-year PPR (post-draft,", brp, ")"),
       x = "Predicted (held-out class)", y = "Actual total PPR, years 1-3")
ggsave("plot_p3_pred_vs_actual.png", g1, width = 7, height = 5, dpi = 150)

g2 <- ggplot(imp %>% group_by(set) %>% slice_head(n = 12),
             aes(x = importance, y = reorder(feature, importance), fill = set)) +
  geom_col(position = "dodge") + scale_fill_manual(values = mycols[c(1, 5)]) +
  labs(title = "Random forest permutation importance (total_ppr_3yr)", x = "Importance", y = NULL)
ggsave("plot_p3_importance.png", g2, width = 7, height = 6, dpi = 150)

g3 <- ggplot(cal, aes(x = mean_pred, y = actual_rate, size = n)) +
  geom_abline(linetype = 2, color = "grey40") + geom_point(color = mycols[6]) +
  coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
  labs(title = paste("Hit-probability calibration (post-draft,", bc, ")"),
       x = "Mean predicted probability", y = "Actual hit rate")
ggsave("plot_p3_calibration.png", g3, width = 6, height = 6, dpi = 150)

# --- Checks -------------------------------------------------------------------
check <- function(label, ok, detail = "") {
  cat(sprintf("[%s] %s %s\n", ifelse(ok, "PASS", "FAIL"), label, detail)); invisible(ok)
}
cat("\n===== Checks =====\n")
check("held-out class never in its training fold", leak_ok)
check("every 2024-2026 WR projected", nrow(proj) == nrow(score) && !any(is.na(proj$post_ppr_3yr)))
pb <- reg_m %>% filter(set == "post")
check("post-draft model beats pick-only baseline (Spearman)",
      max(pb$Spearman[pb$model != "baseline"]) > pb$Spearman[pb$model == "baseline"],
      sprintf("(best %.3f vs baseline %.3f)", max(pb$Spearman[pb$model != "baseline"]),
              pb$Spearman[pb$model == "baseline"]))
pc <- cls_m %>% filter(set == "post")
check("post-draft hit model beats pick-only baseline (Brier)",
      min(pc$Brier[pc$model != "baseline"]) < pc$Brier[pc$model == "baseline"],
      sprintf("(best %.4f vs baseline %.4f)", min(pc$Brier[pc$model != "baseline"]),
              pc$Brier[pc$model == "baseline"]))
pp <- reg_m %>% filter(set == "pre")
check("pre-draft model has real signal (Spearman > 0.3)",
      max(pp$Spearman[pp$model != "baseline"]) > 0.3,
      sprintf("(%.3f)", max(pp$Spearman[pp$model != "baseline"])))
