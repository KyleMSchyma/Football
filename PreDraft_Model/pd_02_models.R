# =============================================================================
# Pre-Draft Model -- Phase 2: model comparison per position
#   usage: Rscript pd_02_models.R QB   (one position per run, so they run in parallel)
#
# Targets (each a 0/1 per pool player, classes 2010-2023):
#   y1 = top tier (QB8 / RB8 / WR12 / TE6 season in NFL years 1-3)
#   y2 = top two tiers (QB16 / RB16 / WR24 / TE12), y3 = any tier (QB24 / RB24 / WR36 / TE18)
# Candidate models (ATPA 4.5-style comparison, all on the same leakage-safe matrix):
#   null      training base rate
#   glm       logistic regression on 5 hand-picked inputs (production share, volume,
#             years since HS, recruiting, Power 5) -- the "simple, explainable" benchmark
#   enet      elastic-net logistic (alpha 0.5, lambda by inner CV with folds = classes)
#   rf        random forest (ranger, 500 trees, probability forest)
#   xgb       gradient boosting (xgboost, depth 3, eta 0.03, rounds by inner 5-fold CV)
#   ens       simple average of enet, rf and xgb (stacking without a meta-learner,
#             which 8 test classes can't support)
#   Probabilities are made nested afterward: P(top tier) <= P(top two) <= P(any tier).
# Validation: strict rolling origin (test class Y, train on classes <= Y - 3, Y = 2016-2023)
#   and leave-one-class-out (2010-2023). Player level: AUC, Brier, Brier skill vs null,
#   log loss, share of hits captured by the top 5% of scores (gain chart point).
#   Class level: expected hits per class (sum of probabilities) vs actual hits.
# Final: all models refit on 2010-2023; the one with the best rolling Brier skill
#   (averaged over the three thresholds) is the "chosen" model.
# Outputs: pd_<pos>_oof.csv, pd_<pos>_metrics.csv, pd_<pos>_class_backtest.csv,
#          pd_<pos>_models.rds, pd_<pos>_board.csv (classes 2024-2027)
# =============================================================================
args <- commandArgs(trailingOnly = TRUE); POS <- if (length(args)) args[1] else "TE"
source("pd_common.R")
suppressMessages({ library(glmnet); library(ranger); library(xgboost); library(pROC) })
cat("position:", POS, "\n")

pool  <- readRDS("pd_pool.rds") %>% filter(position == POS)
train <- pool %>% filter(outcome_known, class %in% TRAIN_CLASSES) %>%
  mutate(y1 = as.integer(tier == 1), y2 = as.integer(tier <= 2), y3 = as.integer(tier <= 3))
score <- pool %>% filter(class >= 2024)
vars  <- feats_for(POS)
simple_vars <- switch(POS,
  QB = c("p_aya", "p_att", "yrs_since_hs", "recruit_rating", "power5"),
  RB = c("p_scrim_share", "p_rush_yds", "yrs_since_hs", "recruit_rating", "power5"),
  c("p_dominator", "p_rec_yds", "yrs_since_hs", "recruit_rating", "power5"))
YS <- c("y1", "y2", "y3"); MODELS <- c("null", "glm", "enet", "rf", "xgb", "ens")
cat("training pool:", nrow(train), " hits:", paste(sapply(YS, function(y) sum(train[[y]])), collapse = " / "),
    " (", paste(tier_labels(POS), collapse = " / "), ")\n")

XGB_PAR <- list(objective = "binary:logistic", eval_metric = "logloss", eta = 0.03, max_depth = 3,
                min_child_weight = 3, subsample = 0.8, colsample_bytree = 0.8, nthread = 1, seed = 2026)

fit_one <- function(Xtr, y, classes) {
  m <- list()
  m$rate <- mean(y)
  m$glm <- suppressWarnings(glm(y ~ ., family = binomial, data = data.frame(Xtr[, simple_vars, drop = FALSE], y = y)))
  folds <- as.integer(factor(classes))
  m$enet <- tryCatch(suppressWarnings(cv.glmnet(Xtr, y, family = "binomial", alpha = 0.5, foldid = folds)), error = function(e) NULL)
  m$rf <- ranger(x = as.data.frame(Xtr), y = factor(y, levels = 0:1), probability = TRUE, num.trees = 500,
                 min.node.size = 20, seed = 2026, num.threads = 1)
  dtr <- xgb.DMatrix(Xtr, label = y)
  set.seed(2026)
  cv <- xgb.cv(params = XGB_PAR, data = dtr, nrounds = 800, nfold = 5, early_stopping_rounds = 40, verbose = 0)
  nr <- max(25, cv$early_stop$best_iteration %||% which.min(cv$evaluation_log$test_logloss_mean))
  m$xgb <- xgb.train(params = XGB_PAR, data = dtr, nrounds = nr, verbose = 0); m$nrounds <- nr
  m
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
pred_one <- function(m, X) {
  o <- data.frame(null = rep(m$rate, nrow(X)))
  o$glm  <- as.numeric(predict(m$glm, data.frame(X[, simple_vars, drop = FALSE]), type = "response"))
  o$enet <- if (is.null(m$enet)) m$rate else as.numeric(predict(m$enet, X, s = "lambda.min", type = "response"))
  o$rf   <- predict(m$rf, as.data.frame(X), num.threads = 1)$predictions[, "1"]
  o$xgb  <- predict(m$xgb, X)
  o$ens  <- (o$enet + o$rf + o$xgb) / 3
  o
}
fit_all <- function(tr) {
  p <- fit_prep(tr, vars); Xtr <- apply_prep(p, tr)
  list(prep = p, fits = lapply(setNames(YS, YS), function(y) fit_one(Xtr, tr[[y]], tr$class)))
}
predict_all <- function(M, d) {
  X <- apply_prep(M$prep, d)
  pr <- lapply(YS, function(y) pred_one(M$fits[[y]], X))
  out <- list()
  for (m in MODELS) {   # nested: P(top tier) <= P(top two) <= P(any tier)
    p1 <- pr[[1]][[m]]; p2 <- pmax(pr[[2]][[m]], p1); p3 <- pmax(pr[[3]][[m]], p2)
    out[[paste0("p1_", m)]] <- p1; out[[paste0("p2_", m)]] <- p2; out[[paste0("p3_", m)]] <- p3
  }
  as.data.frame(out)
}

# --- cross-validation ---------------------------------------------------------------
run_cv <- function(scheme) {
  tests <- if (scheme == "LOCO") TRAIN_CLASSES else ROLL_TESTS
  bind_rows(lapply(tests, function(Y) {
    tr <- if (scheme == "LOCO") filter(train, class != Y) else filter(train, class <= Y - 3)
    te <- filter(train, class == Y)
    cat(scheme, Y, "train", nrow(tr), "test", nrow(te), "\n")
    cbind(te %>% select(athlete_id, name, class, p_team, drafted, round, pick, best, tier, y1, y2, y3),
          scheme = scheme, predict_all(fit_all(tr), te))
  }))
}
t0 <- Sys.time()
oof <- bind_rows(run_cv("Rolling"), run_cv("LOCO"))
cat("CV time:", round(difftime(Sys.time(), t0, units = "mins"), 1), "min\n")
write.csv(oof, sprintf("pd_%s_oof.csv", POS), row.names = FALSE)

gain5 <- function(y, p) { k <- ceiling(0.05 * length(p)); sum(y[order(-p)][1:k]) / max(1, sum(y)) }
met <- list()
for (s in c("Rolling", "LOCO")) for (m in MODELS) for (k in 1:3) {
  d <- filter(oof, scheme == s); y <- d[[YS[k]]]; p <- d[[paste0("p", k, "_", m)]]; pn <- d[[paste0("p", k, "_null")]]
  met[[length(met) + 1]] <- data.frame(scheme = s, model = m, target = tier_labels(POS)[k], n = nrow(d), hits = sum(y),
    AUC = aucf(y, p), Brier = brier(p, y), BSS = 1 - brier(p, y) / brier(pn, y), LogLoss = logloss(p, y), Gain_top5pct = gain5(y, p))
}
metrics <- bind_rows(met) %>% mutate(across(where(is.double), ~ round(.x, 4)))
write.csv(metrics, sprintf("pd_%s_metrics.csv", POS), row.names = FALSE)
cat("\n===== Player-level performance (BSS = Brier skill vs base rate; higher = better) =====\n")
print(metrics, row.names = FALSE)

roll <- metrics %>% filter(scheme == "Rolling", model != "null") %>% group_by(model) %>%
  summarize(mean_BSS = mean(BSS), mean_AUC = mean(AUC, na.rm = TRUE), .groups = "drop") %>% arrange(desc(mean_BSS))
cat("\nRolling-origin ranking (mean over the three tiers):\n"); print(as.data.frame(roll), row.names = FALSE)
CHOSEN <- roll$model[1]; cat("chosen model:", CHOSEN, "\n")

r <- filter(oof, scheme == "Rolling"); n <- nrow(r)
bs <- function(k, m, i) brier(r[[paste0("p", k, "_", m)]][i], r[[YS[k]]][i])
cat("\n===== Bootstrap (rolling, players resampled; negative = first model better) =====\n")
for (k in 1:3) for (cmp in list(c(CHOSEN, "null"), c(CHOSEN, "glm"), c(CHOSEN, "enet"))) {
  if (cmp[1] == cmp[2]) next
  ci <- boot_ci(function(i) bs(k, cmp[1], i) - bs(k, cmp[2], i), n)
  cat(sprintf("%-6s Brier %s - %s: %+.5f  95%% CI [%+.5f, %+.5f]\n", tier_labels(POS)[k], cmp[1], cmp[2], ci[1], ci[2], ci[3]))
}

# --- class level: does the summed probability track how many hits a class produced? --
cls <- oof %>% group_by(scheme, class) %>%
  summarize(n_pool = n(), across(c(y1, y2, y3), sum), across(matches("^p[123]_"), sum), .groups = "drop")
write.csv(cls, sprintf("pd_%s_class_backtest.csv", POS), row.names = FALSE)
cat("\n===== Class level: expected vs actual hits per class =====\n")
cm <- list()
for (s in c("Rolling", "LOCO")) for (m in setdiff(MODELS, "glm")) for (k in 1:3) {
  d <- filter(cls, scheme == s); a <- d[[YS[k]]]; e <- d[[paste0("p", k, "_", m)]]
  cm[[length(cm) + 1]] <- data.frame(scheme = s, model = m, target = tier_labels(POS)[k], classes = nrow(d),
    actual_mean = mean(a), expected_mean = mean(e), corr = ifelse(sd(e) > 0, cor(e, a), NA),
    spearman = ifelse(sd(e) > 0, cor(e, a, method = "spearman"), NA), RMSE = sqrt(mean((e - a)^2)))
}
class_metrics <- bind_rows(cm) %>% mutate(across(where(is.double), ~ round(.x, 3)))
print(class_metrics, row.names = FALSE)
write.csv(class_metrics, sprintf("pd_%s_class_metrics.csv", POS), row.names = FALSE)
cat("\nper-class detail, LOCO, chosen model:\n")
print(as.data.frame(cls %>% filter(scheme == "LOCO") %>%
  transmute(class, n_pool, act1 = y1, exp1 = round(.data[[paste0("p1_", CHOSEN)]], 2), act2 = y2,
            exp2 = round(.data[[paste0("p2_", CHOSEN)]], 2), act3 = y3, exp3 = round(.data[[paste0("p3_", CHOSEN)]], 2))), row.names = FALSE)

# --- final fit and board ----------------------------------------------------------------
M <- fit_all(train)
saveRDS(list(M = M, chosen = CHOSEN, vars = vars, simple_vars = simple_vars, position = POS), sprintf("pd_%s_models.rds", POS))
board <- cbind(score %>% select(athlete_id, name, class, p_team, power5, fbs, drafted, round, pick, yrs_since_hs, recruit_rating,
                                recruit_stars, all_of(setdiff(vars, c("yrs_since_hs", "recruit_rating", "power5")))),
               predict_all(M, score))
board$p1 <- board[[paste0("p1_", CHOSEN)]]; board$p2 <- board[[paste0("p2_", CHOSEN)]]; board$p3 <- board[[paste0("p3_", CHOSEN)]]
write.csv(board, sprintf("pd_%s_board.csv", POS), row.names = FALSE)
cat("\n===== Top 12 per class, chosen model (", CHOSEN, ") =====\n")
for (Y in 2024:2027) {
  cat("class", Y, "\n")
  print(as.data.frame(board %>% filter(class == Y) %>% arrange(desc(p3)) %>% head(12) %>%
    transmute(name, p_team, pick, yrs = yrs_since_hs, p1 = round(p1, 3), p2 = round(p2, 3), p3 = round(p3, 3))), row.names = FALSE)
}
