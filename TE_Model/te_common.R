# =============================================================================
# TE Model -- shared helpers, sourced by Phases 3-7
#   feature sets, in-fold preprocessing (median impute + missing flags, fit on
#   training rows only), elastic-net wrapper, metrics and bootstrap helpers.
#   (Same helpers as RB_Model/rb_common.R; only the feature sets differ.)
# =============================================================================
suppressMessages({ library(dplyr); library(tidyr); library(glmnet); library(pROC) })
select <- dplyr::select

# Kyle's TE tier cutoffs (best season-total TE finish in NFL years 1-3): tier 1 = TE1-6, tier 2 = TE7-12,
#   tier 3 = TE13-18, tier 4 = rest. Changed from 8/16/24 on 2026-11-12: a 12-team league starts 12 TEs, so
#   TE16/TE24 seasons were below replacement. Column names follow the cutoffs (hit6/hit12/hit18, p_top6/12/18).
TE_CUT <- c(6L, 12L, 18L)

pre_num  <- c("age_at_draft", "p_rec", "p_rec_yds", "p_rec_td", "p_ypr", "p_rec_share", "p_dominator", "p_ypta",
              "best_dominator", "career_rec_yds", "featured_seasons", "breakout_age_filled", "height_in", "weight_lb",
              "forty", "speed_score", "vertical", "broad_jump", "cone", "recruit_rating")
pre_flag <- c("ever_breakout", "transferred", "early_declare", "p_power5", "college_matched",
              "combine_invited", "miss_forty", "final_short")
post_num <- c("log_pick", "vacated_tgt_share", "incumbent_pts")
ppa_num  <- c("p_ppa_pass", "p_usg_pass")

load_table <- function() {
  readRDS("te_model_table.rds") %>%
    mutate(p_power5 = as.integer(coalesce(p_power5, FALSE)), combine_invited = as.integer(combine_invited),
           final_short = coalesce(final_short, 0L), ever_breakout = coalesce(ever_breakout, 0L),
           transferred = coalesce(transferred, 0L))
}
fit_prep <- function(d, num, flags = pre_flag) {
  med  <- sapply(num, function(v) median(as.numeric(d[[v]]), na.rm = TRUE)); med[is.na(med)] <- 0
  flag <- num[sapply(num, function(v) any(is.na(d[[v]])))]
  list(num = num, med = med, flag = flag, flags = flags)
}
apply_prep <- function(p, d) {
  out <- matrix(NA_real_, nrow(d), 0)
  for (v in p$num) {
    x <- as.numeric(d[[v]])
    if (v %in% p$flag) out <- cbind(out, setNames(as.integer(is.na(x)), NULL))
    if (v %in% p$flag) colnames(out)[ncol(out)] <- paste0("na_", v)
    x[is.na(x)] <- p$med[v]; out <- cbind(out, x); colnames(out)[ncol(out)] <- v
  }
  for (v in p$flags) { out <- cbind(out, as.integer(coalesce(as.numeric(d[[v]]), 0))); colnames(out)[ncol(out)] <- v }
  out
}

# elastic net (alpha 0.5), lambda by inner CV with folds = draft classes;
# falls back to random 5-fold when there are < 4 classes, and to the training
# mean if glmnet cannot fit (e.g. too few positives).
enet_fit <- function(X, y, fam, classes, alpha = 0.5) {
  folds <- as.integer(factor(classes))
  if (max(folds) < 4) folds <- sample(rep(1:5, length.out = length(y)))
  tryCatch(suppressWarnings(cv.glmnet(X, y, family = fam, alpha = alpha, foldid = folds)),
           error = function(e) NULL)
}
enet_pred <- function(fit, Xte, y_train) {
  if (is.null(fit)) return(rep(mean(y_train), nrow(Xte)))
  as.numeric(predict(fit, Xte, s = "lambda.min", type = "response"))
}

aucf  <- function(y, p) if (length(unique(y)) < 2 || sd(p) == 0) NA else as.numeric(auc(roc(y, p, quiet = TRUE)))
brier <- function(p, y) mean((p - y)^2)
rmse  <- function(p, y) sqrt(mean((p - y)^2))
boot_diff <- function(f, n, B = 2000, seed = 2026) {
  set.seed(seed)
  pt <- f(seq_len(n)); dd <- replicate(B, f(sample.int(n, replace = TRUE)))
  sprintf("%+.4f  95%% CI [%+.4f, %+.4f]  share < 0: %.3f", pt, quantile(dd, .025, na.rm = TRUE), quantile(dd, .975, na.rm = TRUE), mean(dd < 0, na.rm = TRUE))
}
check <- function(label, ok, detail = "") { cat(sprintf("[%s] %s %s\n", ifelse(ok, "PASS", "FAIL"), label, detail)); invisible(ok) }
