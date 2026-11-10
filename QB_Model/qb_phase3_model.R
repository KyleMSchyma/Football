# =============================================================================
# QB Model -- Phase 3: draft-pick benchmark, pre/post-draft elastic nets,
#                      value score and 2024-2026 projections
#
# Targets: total_pts_3yr (Gaussian); hit24_3yr, hit16_3yr, hit8_3yr (logistic: any top-24 / 16 / 8 season).
# Models:  pick_only  linear / logistic on log pick (the draft-capital benchmark)
#          pre_enet   elastic net on college, age, combine, recruiting (no pick)
#          post_enet  pre-draft features + log pick + landing spot
#          (The WR work showed random forests were worst at this sample size;
#           with ~160 QBs they are left out.)
# Validation: strict rolling origin -- test class Y in 2016-2023, train only on
#   classes <= Y - 3 (outcomes fully known before Y's draft) -- plus
#   leave-one-class-out. All preprocessing is fit inside each fold.
# Also: bootstrap CIs (post minus pick-only), a value-score back-test
#   (pre-draft minus pick-only prediction), a PPA/usage sensitivity check
#   (classes 2014+), and projections for 2024-2026.
# Outputs: phase3_cv_metrics.csv, phase3_oof_predictions.csv,
#          phase3_value_backtest.csv, qb_projections_2024_2026.csv
# =============================================================================
source("qb_common.R")
set.seed(2026)

tbl   <- load_table()
train <- tbl %>% filter(!is.na(total_pts_3yr))
score <- tbl %>% filter(draft_season >= 2024)
cat("training rows:", nrow(train), " rows to project:", nrow(score), "\n")

targets <- c(total_pts_3yr = "gaussian", hit24_3yr = "binomial", hit16_3yr = "binomial", hit8_3yr = "binomial")

fit_predict <- function(tr, te, target, extra = character(0)) {
  fam <- targets[[target]]; y <- tr[[target]]
  base <- if (fam == "binomial") predict(glm(y ~ log_pick, binomial, data = tr), te, type = "response")
          else predict(lm(y ~ log_pick, data = tr), te)
  out <- data.frame(pick_only = base)
  for (set in c("pre", "post")) {
    num <- c(pre_num, extra, if (set == "post") post_num)
    p <- fit_prep(tr, num); Xtr <- apply_prep(p, tr); Xte <- apply_prep(p, te)
    out[[paste0(set, "_enet")]] <- enet_pred(enet_fit(Xtr, y, fam, tr$draft_season), Xte, y)
  }
  if (fam == "gaussian") out[] <- lapply(out, function(z) pmax(0, z))
  out
}

run_cv <- function(scheme, data = train, tests = NULL, extra = character(0)) {
  res <- list()
  if (is.null(tests)) tests <- if (scheme == "LOCO") sort(unique(data$draft_season)) else 2016:2023
  for (target in names(targets)) for (Y in tests) {
    tr <- if (scheme == "LOCO") filter(data, draft_season != Y) else filter(data, draft_season <= Y - 3)
    te <- filter(data, draft_season == Y)
    if (scheme == "Rolling") stopifnot(max(tr$draft_season) <= Y - 3)
    res[[length(res) + 1]] <- cbind(te[, c("draft_season", "round", "pick", "pfr_player_name")],
                                    scheme = scheme, target = target, actual = te[[target]],
                                    ntrain = nrow(tr), fit_predict(tr, te, target, extra))
  }
  bind_rows(res)
}
oof <- bind_rows(run_cv("Rolling"), run_cv("LOCO"))
write.csv(oof, "phase3_oof_predictions.csv", row.names = FALSE)
cat("rolling training sizes:", paste(unique(oof$ntrain[oof$scheme == "Rolling"]), collapse = ", "), "\n")

metrics <- oof %>% pivot_longer(c(pick_only, pre_enet, post_enet), names_to = "model", values_to = "pred") %>%
  group_by(scheme, target, model) %>%
  summarize(n = n(), Spearman = cor(pred, actual, method = "spearman"),
            RMSE = ifelse(first(target) == "total_pts_3yr", rmse(pred, actual), NA),
            R2 = ifelse(first(target) == "total_pts_3yr", 1 - sum((pred - actual)^2) / sum((actual - mean(actual))^2), NA),
            AUC = ifelse(first(target) != "total_pts_3yr", aucf(actual, pred), NA),
            Brier = ifelse(first(target) != "total_pts_3yr", brier(pred, actual), NA), .groups = "drop") %>%
  mutate(across(where(is.double), ~ round(.x, 4))) %>% arrange(scheme, target, model)
cat("\n===== Cross-validated performance =====\n"); print(as.data.frame(metrics), row.names = FALSE)
write.csv(metrics, "phase3_cv_metrics.csv", row.names = FALSE)

cat("\n===== Bootstrap, rolling origin (2000 draws, players resampled; negative = first model better) =====\n")
for (target in names(targets)) {
  r <- oof %>% filter(scheme == "Rolling", target == !!target)
  f <- if (target == "total_pts_3yr") rmse else brier
  lab <- if (target == "total_pts_3yr") "RMSE " else "Brier"
  cat(sprintf("%-14s %s post - pick: %s\n", target, lab, boot_diff(function(i) f(r$post_enet[i], r$actual[i]) - f(r$pick_only[i], r$actual[i]), nrow(r))))
  cat(sprintf("%-14s %s pre  - pick: %s\n", target, lab, boot_diff(function(i) f(r$pre_enet[i], r$actual[i]) - f(r$pick_only[i], r$actual[i]), nrow(r))))
}

cat("\n===== Calibration, rolling origin, post-draft P(top-24) =====\n")
print(as.data.frame(oof %>% filter(scheme == "Rolling", target == "hit24_3yr") %>%
  mutate(bin = cut(post_enet, c(0, .1, .3, .5, .7, 1), include.lowest = TRUE)) %>%
  group_by(bin) %>% summarize(n = n(), mean_pred = round(mean(post_enet), 3), actual = round(mean(actual), 3), .groups = "drop")),
  row.names = FALSE)

# --- Value score back-test: pre-draft minus pick-only (rolling origin) -----------
v <- oof %>% filter(scheme == "Rolling") %>% select(draft_season, round, pick, pfr_player_name, target, actual, pick_only, pre_enet) %>%
  pivot_wider(names_from = target, values_from = c(actual, pick_only, pre_enet)) %>%
  mutate(value_gap = pre_enet_total_pts_3yr - pick_only_total_pts_3yr,
         beat_slot = actual_total_pts_3yr - pick_only_total_pts_3yr,
         grp = ntile(value_gap, 3))
vt <- v %>% group_by(grp) %>% summarize(n = n(), mean_gap = round(mean(value_gap)), mean_beat_slot = round(mean(beat_slot)),
                                        hit24 = round(mean(actual_hit24_3yr), 3), pick_only_p24 = round(mean(pick_only_hit24_3yr), 3), .groups = "drop")
cat("\n===== Value score back-test (terciles of pre-draft minus pick-only predicted points), rolling 2016-2023 =====\n")
print(as.data.frame(vt), row.names = FALSE)
cat("top minus bottom tercile, actual minus pick-only points:",
    boot_diff(function(i) { s <- v[i, ]; mean(s$beat_slot[s$grp == 3]) - mean(s$beat_slot[s$grp == 1]) }, nrow(v)), "\n")
cat("Spearman(value gap, beat-slot) within round 1:", round(cor(v$value_gap[v$round == 1], v$beat_slot[v$round == 1], method = "spearman"), 3),
    "| rounds 2+:", round(cor(v$value_gap[v$round > 1], v$beat_slot[v$round > 1], method = "spearman"), 3), "\n")
write.csv(v, "phase3_value_backtest.csv", row.names = FALSE)

# --- PPA / usage sensitivity (cfbd PPA exists for 2013+ seasons -> classes 2014+) --
cat("\n===== PPA / usage sensitivity: pre-draft model, LOCO within 2014-2023 classes =====\n")
d14 <- train %>% filter(draft_season >= 2014)
a <- run_cv("LOCO", d14) %>% mutate(feat = "base")
b <- run_cv("LOCO", d14, extra = ppa_num) %>% mutate(feat = "with_ppa")
ab <- bind_rows(a, b)
print(as.data.frame(ab %>% group_by(feat, target) %>%
  summarize(pre_Spearman = round(cor(pre_enet, actual, method = "spearman"), 3),
            pre_AUC = round(ifelse(first(target) == "total_pts_3yr", NA, aucf(actual, pre_enet)), 3),
            post_Spearman = round(cor(post_enet, actual, method = "spearman"), 3), .groups = "drop")), row.names = FALSE)
for (target in c("total_pts_3yr", "hit24_3yr")) {
  aa <- filter(a, target == !!target); bb <- filter(b, target == !!target)
  f <- if (target == "total_pts_3yr") rmse else brier
  cat(sprintf("%-14s pre-draft with PPA minus without: %s\n", target,
              boot_diff(function(i) f(bb$pre_enet[i], bb$actual[i]) - f(aa$pre_enet[i], aa$actual[i]), nrow(aa))))
}

# --- Final fit on 2010-2023 -> 2024-2026 -------------------------------------------
proj <- score %>% select(draft_season, round, pick, pfr_player_name, college, draft_team, yr1_pts, finish_y1, finish_y2)
for (target in names(targets)) {
  f <- fit_predict(train, score, target)
  names(f) <- paste0(names(f), "_", c(total_pts_3yr = "pts3", hit24_3yr = "p24", hit16_3yr = "p16", hit8_3yr = "p8")[target])
  proj <- bind_cols(proj, f)
}
proj <- proj %>% mutate(across(matches("_pts3$"), ~ round(.x, 1)), across(matches("_p(24|16|8)$"), ~ round(.x, 3)),
                        value_gap_pts = round(pre_enet_pts3 - pick_only_pts3, 1),
                        value_gap_p24 = round(pre_enet_p24 - pick_only_p24, 3)) %>%
  arrange(draft_season, desc(post_enet_pts3))
write.csv(proj, "qb_projections_2024_2026.csv", row.names = FALSE)
cat("\n===== Projections (post-draft), by class =====\n")
print(as.data.frame(proj %>% select(draft_season, pick, pfr_player_name, post_enet_pts3, post_enet_p24, post_enet_p16, post_enet_p8,
                                    pick_only_p24, pre_enet_p24, value_gap_p24, finish_y1, finish_y2)), row.names = FALSE)

p <- fit_prep(train, c(pre_num, post_num)); X <- apply_prep(p, train)
for (target in c("total_pts_3yr", "hit24_3yr")) {
  for (set in c("pre", "post")) {
    num <- c(pre_num, if (set == "post") post_num); pp <- fit_prep(train, num); XX <- apply_prep(pp, train)
    fit <- enet_fit(XX, train[[target]], targets[[target]], train$draft_season)
    co <- coef(fit, s = "lambda.min"); nz <- co[which(co[, 1] != 0), 1]
    cat("\nelastic net (", set, ", ", target, ") nonzero coefficients (raw scale):\n", sep = "")
    print(round(nz[order(-abs(nz))], 4))
  }
}

cat("\n===== Checks =====\n")
check("rolling folds never train on test or later classes", all(oof$ntrain[oof$scheme == "Rolling"] > 0))
check("every 2024-2026 QB projected", nrow(proj) == nrow(score) && !any(is.na(proj$post_enet_pts3)))
