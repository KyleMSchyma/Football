# =============================================================================
# QB Model -- Phase 4: finish score (single-step and two-step) and tier ladder
#
# Finish score = QB rank in years 1-3 summed, each season capped at 50 (did not
#   play or worse than QB50 = 50). QB3 + QB8 + QB12 = 23; three lost years = 150.
#   Lower is better.
#   single-step  Gaussian elastic net on the score (pick-only: linear on log pick)
#   two-step     step 1: P(any top-32 season in years 1-3, i.e. a starter-level
#                year); step 2: expected score given one (Gaussian elastic net on
#                those players only). Combined = P * E[score | starter year] +
#                (1 - P) * mean score of training players without one.
# Tier ladder: best finish in years 1-3 as 1 = QB1 (top 12), 2 = QB2 (13-24),
#   3 = below. Cumulative logit, so P(QB1) <= P(QB2+) always:
#   pick-only MASS::polr on log pick; pre/post penalized ordinal elastic net
#   (ordinalNet, alpha 0.5, lambda by inner class-grouped CV).
# Validation: rolling origin (test 2016-2023, train <= Y - 3) and leave-one-class-
#   out. Hidden-talent back-test for QBs drafted after round 1.
# Outputs: phase4_cv_metrics.csv, phase4_oof_predictions.csv,
#          qb_finish_tier_board_2024_2026.csv
# =============================================================================
source("qb_common.R")
suppressMessages({ library(MASS); library(ordinalNet) }); select <- dplyr::select
set.seed(2026)
CAP <- 50; STARTER <- 32

tbl <- load_table() %>% mutate(starter_yr = as.integer(best_finish_3yr <= STARTER))
train <- tbl %>% filter(!is.na(finish_sum_3yr))
score <- tbl %>% filter(draft_season >= 2024)
cat("training rows:", nrow(train), " any top-32 season:", sum(train$starter_yr),
    " QB1:", sum(train$tier == 1), " QB2:", sum(train$tier == 2), "\n")
cat("finish score distribution: at 150 =", sum(train$finish_sum_3yr == 150), "; quantiles:\n")
print(quantile(train$finish_sum_3yr, c(.05, .1, .25, .5, .75)))
cat("Spearman(finish score, 3-yr points):", round(cor(train$finish_sum_3yr, train$total_pts_3yr, method = "spearman"), 3), "\n")
cat("best 10 finish scores 2010-2023:\n")
print(as.data.frame(train %>% arrange(finish_sum_3yr) %>% head(10) %>%
  select(pfr_player_name, draft_season, pick, finish_y1, finish_y2, finish_y3, finish_sum_3yr)), row.names = FALSE)

# --- finish score models ---------------------------------------------------------
finish_models <- function(tr, te) {
  o <- data.frame(row.names = seq_len(nrow(te)))
  o$single_pick <- predict(lm(finish_sum_3yr ~ log_pick, tr), te)
  o$p_start_pick <- predict(glm(starter_yr ~ log_pick, binomial, tr), te, type = "response")
  s1 <- filter(tr, starter_yr == 1); s0 <- mean(tr$finish_sum_3yr[tr$starter_yr == 0])
  o$cond_pick <- predict(lm(finish_sum_3yr ~ log_pick, s1), te)
  for (set in c("pre", "post")) {
    num <- c(pre_num, if (set == "post") post_num)
    p <- fit_prep(tr, num); Xtr <- apply_prep(p, tr); Xte <- apply_prep(p, te)
    o[[paste0("single_", set)]] <- enet_pred(enet_fit(Xtr, tr$finish_sum_3yr, "gaussian", tr$draft_season), Xte, tr$finish_sum_3yr)
    o[[paste0("p_start_", set)]] <- enet_pred(enet_fit(Xtr, tr$starter_yr, "binomial", tr$draft_season), Xte, tr$starter_yr)
    p1 <- fit_prep(s1, num); X1 <- apply_prep(p1, s1)
    o[[paste0("cond_", set)]] <- enet_pred(enet_fit(X1, s1$finish_sum_3yr, "gaussian", s1$draft_season), apply_prep(p1, te), s1$finish_sum_3yr)
  }
  for (m in c("pick", "pre", "post")) {
    o[[paste0("single_", m)]] <- pmin(150, pmax(3, o[[paste0("single_", m)]]))
    o[[paste0("cond_", m)]] <- pmin(150, pmax(3, o[[paste0("cond_", m)]]))
    o[[paste0("two_", m)]] <- o[[paste0("p_start_", m)]] * o[[paste0("cond_", m)]] + (1 - o[[paste0("p_start_", m)]]) * s0
  }
  o
}

# --- tier ladder ------------------------------------------------------------------
ladder <- function(tr, te, model) {
  if (model == "pick") {
    fit <- polr(factor(tier, levels = 1:3, ordered = TRUE) ~ log_pick, data = tr, Hess = TRUE)
    pr <- predict(fit, te, type = "probs")
  } else {
    num <- c(pre_num, if (model == "post") post_num)
    pp <- fit_prep(tr, num); Xtr <- apply_prep(pp, tr); Xte <- apply_prep(pp, te)
    keep <- apply(Xtr, 2, sd) > 0; Xtr <- Xtr[, keep, drop = FALSE]; Xte <- Xte[, keep, drop = FALSE]
    ce <- colMeans(Xtr); sc <- apply(Xtr, 2, sd)
    Xtr <- scale(Xtr, ce, sc); Xte <- scale(Xte, ce, sc)
    y <- factor(tr$tier, levels = 1:3, ordered = TRUE)
    fit <- ordinalNet(Xtr, y, family = "cumulative", link = "logit", alpha = 0.5, parallelTerms = TRUE,
                      nonparallelTerms = FALSE, nLambda = 20, standardize = FALSE)
    folds <- split(seq_len(nrow(tr)), tr$draft_season)
    tune <- tryCatch(ordinalNetTune(Xtr, y, lambdaVals = fit$lambdaVals, folds = folds, printProgress = FALSE,
                                    warn = FALSE, family = "cumulative", link = "logit", alpha = 0.5,
                                    parallelTerms = TRUE, nonparallelTerms = FALSE, standardize = FALSE),
                     error = function(e) NULL)
    ll <- if (is.null(tune)) NULL else rowMeans(tune$loglik)
    best <- if (is.null(ll) || all(!is.finite(ll))) length(fit$lambdaVals) %/% 2 else which.max(ll)
    pr <- predict(fit, Xte, whichLambda = best, type = "response")
  }
  pr <- matrix(pr, ncol = 3)
  data.frame(p_qb1 = pr[, 1], p_qb2plus = pr[, 1] + pr[, 2])
}

run_cv <- function(scheme) {
  res <- list()
  tests <- if (scheme == "LOCO") sort(unique(train$draft_season)) else 2016:2023
  for (Y in tests) {
    tr <- if (scheme == "LOCO") filter(train, draft_season != Y) else filter(train, draft_season <= Y - 3)
    te <- filter(train, draft_season == Y)
    lad <- lapply(c("pick", "pre", "post"), function(m) setNames(ladder(tr, te, m), paste0(c("p_qb1_", "p_qb2plus_"), m)))
    res[[length(res) + 1]] <- cbind(te %>% select(draft_season, round, pick, pfr_player_name, finish_sum_3yr,
                                                  starter_yr, best_finish_3yr, tier),
                                    scheme = scheme, finish_models(tr, te), do.call(cbind, lad))
  }
  bind_rows(res)
}
oof <- bind_rows(run_cv("Rolling"), run_cv("LOCO")) %>% mutate(y1 = as.integer(tier == 1), y2 = as.integer(tier <= 2))
stopifnot(all(oof$p_qb1_post <= oof$p_qb2plus_post + 1e-9))
write.csv(oof, "phase4_oof_predictions.csv", row.names = FALSE)

met <- list()
for (s in c("Rolling", "LOCO")) for (m in c("pick", "pre", "post")) {
  d <- filter(oof, scheme == s)
  sg <- d[[paste0("single_", m)]]; tw <- d[[paste0("two_", m)]]; ps <- d[[paste0("p_start_", m)]]
  q1 <- d[[paste0("p_qb1_", m)]]; q2 <- d[[paste0("p_qb2plus_", m)]]
  st <- d$starter_yr == 1
  met[[length(met) + 1]] <- data.frame(scheme = s, model = m, n = nrow(d),
    single_Spearman = cor(sg, d$finish_sum_3yr, method = "spearman"), single_RMSE = rmse(sg, d$finish_sum_3yr),
    single_MAE = mean(abs(sg - d$finish_sum_3yr)),
    two_Spearman = cor(tw, d$finish_sum_3yr, method = "spearman"), two_RMSE = rmse(tw, d$finish_sum_3yr),
    step1_AUC = aucf(d$starter_yr, ps), step1_Brier = brier(ps, d$starter_yr),
    step2_RMSE = rmse(d[[paste0("cond_", m)]][st], d$finish_sum_3yr[st]),
    ladder_RPS = mean(((q1 - d$y1)^2 + (q2 - d$y2)^2) / 2),
    AUC_QB1 = aucf(d$y1, q1), AUC_QB2plus = aucf(d$y2, q2), Brier_QB1 = brier(q1, d$y1), Brier_QB2plus = brier(q2, d$y2))
}
metrics <- bind_rows(met) %>% mutate(across(where(is.double), ~ round(.x, 4)))
cat("\n===== Finish score and tier ladder: cross-validated performance (Spearman of predicted vs actual score; higher = better) =====\n")
print(metrics, row.names = FALSE)
write.csv(metrics, "phase4_cv_metrics.csv", row.names = FALSE)

r <- filter(oof, scheme == "Rolling"); n <- nrow(r)
rps <- function(m, i) mean(((r[[paste0("p_qb1_", m)]][i] - r$y1[i])^2 + (r[[paste0("p_qb2plus_", m)]][i] - r$y2[i])^2) / 2)
cat("\n===== Bootstrap, rolling origin (negative = first better) =====\n")
cat("single RMSE  post - pick:     ", boot_diff(function(i) rmse(r$single_post[i], r$finish_sum_3yr[i]) - rmse(r$single_pick[i], r$finish_sum_3yr[i]), n), "\n")
cat("two-step RMSE post - single post:", boot_diff(function(i) rmse(r$two_post[i], r$finish_sum_3yr[i]) - rmse(r$single_post[i], r$finish_sum_3yr[i]), n), "\n")
cat("two-step RMSE post - pick:    ", boot_diff(function(i) rmse(r$two_post[i], r$finish_sum_3yr[i]) - rmse(r$single_pick[i], r$finish_sum_3yr[i]), n), "\n")
cat("ladder RPS   post - pick:     ", boot_diff(function(i) rps("post", i) - rps("pick", i), n), "\n")
cat("ladder RPS   pre  - pick:     ", boot_diff(function(i) rps("pre", i) - rps("pick", i), n), "\n")

cat("\n===== Step-1 calibration (rolling, post-draft P(top-32 season)) =====\n")
print(as.data.frame(r %>% mutate(q = ntile(p_start_post, 4)) %>% group_by(q) %>%
  summarize(n = n(), mean_p = round(mean(p_start_post), 3), actual = round(mean(starter_yr), 3), .groups = "drop")), row.names = FALSE)

# --- hidden talent after round 1 (rolling) ------------------------------------------
h <- r %>% filter(round >= 2) %>% mutate(hidden = p_qb2plus_post - p_qb2plus_pick, hidden_pre = p_qb2plus_pre - p_qb2plus_pick)
cat("\n===== Hidden-talent back-test, QBs drafted in rounds 2-7, rolling 2016-2023 (", nrow(h), "QBs,", sum(h$y2), "QB2+ ) =====\n")
topk <- function(col, k) h %>% group_by(draft_season) %>% arrange(desc(.data[[col]]), pick, .by_group = TRUE) %>%
  slice_head(n = k) %>% ungroup()
h$earliest <- -h$pick
for (k in c(2, 3)) {
  row <- sapply(c("hidden", "hidden_pre", "p_qb2plus_post", "earliest"), function(cc) sum(topk(cc, k)$y2))
  cat(sprintf("top %d per class -> QB2+ hits: post hidden %d | pre hidden %d | post P %d | earliest pick %d | random %.1f\n",
              k, row[1], row[2], row[3], row[4], sum(tapply(h$y2, h$draft_season, function(z) min(k, length(z)) * mean(z)))))
}
cat("all round 2-7 QB2+ in test years, with rank in class by post hidden score / pre hidden score / pick:\n")
print(as.data.frame(h %>% group_by(draft_season) %>%
  mutate(n_cls = n(), rk_hidden = rank(-hidden), rk_pre = rank(-hidden_pre), rk_pick = rank(pick)) %>% ungroup() %>%
  filter(y2 == 1) %>% select(draft_season, pick, pfr_player_name, best_finish_3yr, n_cls, rk_hidden, rk_pre, rk_pick)), row.names = FALSE)

# --- 2024-2026 board ------------------------------------------------------------------
fm <- finish_models(train, score)
lad <- do.call(cbind, lapply(c("pick", "pre", "post"), function(m) setNames(ladder(train, score, m), paste0(c("p_qb1_", "p_qb2plus_"), m))))
board <- bind_cols(score %>% select(pfr_player_name, draft_season, round, pick, draft_team, college, finish_y1, finish_y2),
                   fm %>% select(single_pick, single_post, p_start_post, cond_post, two_pick, two_pre, two_post), lad) %>%
  mutate(across(c(single_pick, single_post, cond_post, two_pick, two_pre, two_post), ~ round(.x, 1)),
         across(c(p_start_post, starts_with("p_qb")), ~ round(.x, 3)),
         hidden_qb2_post = round(p_qb2plus_post - p_qb2plus_pick, 3),
         hidden_qb2_pre = round(p_qb2plus_pre - p_qb2plus_pick, 3)) %>%
  arrange(draft_season, two_post)
write.csv(board, "qb_finish_tier_board_2024_2026.csv", row.names = FALSE)
cat("\n===== 2024-2026 board (two-step post-draft expected finish score; tier ladder) =====\n")
print(as.data.frame(board %>% select(draft_season, pick, pfr_player_name, single_post, p_start_post, cond_post, two_post,
                                     p_qb1_post, p_qb2plus_post, hidden_qb2_post, hidden_qb2_pre, finish_y1, finish_y2)), row.names = FALSE)
