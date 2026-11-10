# =============================================================================
# RB Model -- shared helpers, sourced by Phases 3-7
#   feature sets, in-fold preprocessing (median impute + missing flags, fit on
#   training rows only), elastic-net wrapper, metrics and bootstrap helpers.
#   (Same helpers as QB_Model/qb_common.R; only the feature sets differ.)
# =============================================================================
suppressMessages({ library(dplyr); library(tidyr); library(glmnet); library(pROC) })
select <- dplyr::select

pre_num  <- c("age_at_draft", "p_rush_yds", "p_ypc", "p_rush_td", "p_rec", "p_rec_share", "p_car_share",
              "p_scrim_share", "p_td_share", "best_scrim_share", "career_rush_yds", "career_rec", "career_ypc",
              "featured_seasons", "breakout_age_filled", "height_in", "weight_lb", "forty", "speed_score",
              "broad_jump", "vertical", "recruit_rating")
pre_flag <- c("ever_breakout", "transferred", "early_declare", "p_power5", "college_matched",
              "combine_invited", "miss_forty", "final_short", "recruit_apb")
post_num <- c("log_pick", "vacated_touch_share", "incumbent_pts")
ppa_num  <- c("p_ppa_rush", "p_ppa_pass", "p_usg_overall")

load_table <- function() {
  readRDS("rb_model_table.rds") %>%
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
  tryCatch(cv.glmnet(X, y, family = fam, alpha = alpha, foldid = folds),
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
  sprintf("%+.4f  95%% CI [%+.4f, %+.4f]  share < 0: %.3f", pt, quantile(dd, .025), quantile(dd, .975), mean(dd < 0))
}
check <- function(label, ok, detail = "") { cat(sprintf("[%s] %s %s\n", ifelse(ok, "PASS", "FAIL"), label, detail)); invisible(ok) }
