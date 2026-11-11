# =============================================================================
# Post-Draft Model -- Phase 8: what drives the post-draft model, by position
#
# The post-draft model is the "post" tier ladder from each position model
#   QB/RB/TE: *_phase4_finish_tiers.R      WR: wr_phase6_tier_ladder.R
# an ordinal elastic net (ordinalNet, cumulative logit, alpha 0.5, parallel terms,
# lambda by class-grouped CV) on college features + combine + age + log(pick) +
# landing spot. Tiers: QB/RB/TE 8/16/24, WR 12/24/36 (tier 1 = top).
# Those scripts don't save the fitted model, so this script refits the final post
# ladder on every 2010-2023 training row with the exact same features and in-fold
# preprocessing (median impute + missing flags, standardize on train; WR adds the
# athletic PCA of forty / vertical / broad jump / speed score), then:
#   1. permutation importance: drop in AUC of P(any tier) when an input is shuffled
#      together with its missing flag, mean of 3 shuffles, seed 2026
#   2. effect sizes: ordinal coefficients on the standardized inputs as odds per SD
#      (sign check: a later pick, i.e. higher log_pick, must lower the hit odds)
#   3. PDP + ICE for the top 3 inputs: P(any tier) from the 5th to 95th percentile,
#      plus 40 sampled ICE curves
#   4. SHAP as exact linear contributions beta * (x - mean), mean |value| ranking
# Outputs per position: pd_post_<pos>_importance.csv, pd_post_<pos>_pdp_ice.csv,
#   pd_post_<pos>_coefs.csv, plot_post_<pos>_importance.png, plot_post_<pos>_pdp_ice.png,
#   plot_post_<pos>_shap.png; pd_post_predictors_summary.csv
# Runs from the repo (PostDraft_Model, QB_Model, ...) or Kyle's PC (Football2_PostDraft,
# Football2_QB, ...): ./run.sh pd_08_post_predictors.R phase8_log.txt
# =============================================================================
suppressMessages({ library(dplyr); library(tidyr); library(ggplot2); library(pROC); library(ordinalNet) })
select <- dplyr::select
mycols <- c("#E69F00", "#56B4E9", "#009E73", "#F0E442", "#0072B2", "#D55E00", "#CC79A7")
OUT <- getwd()
POS_DIR <- if (dir.exists("../WR_Model")) c(QB = "../QB_Model", RB = "../RB_Model", WR = "../WR_Model", TE = "../TE_Model") else
  c(QB = "../Football2_QB", RB = "../Football2_RB", WR = "../Football2", TE = "../Football2_TE")
TIERS <- list(QB = c(8, 16, 24), RB = c(8, 16, 24), WR = c(12, 24, 36), TE = c(8, 16, 24))
aucf <- function(y, p) as.numeric(auc(roc(y, p, quiet = TRUE, direction = "<")))

# --- load each position's training table and its exact post-draft preprocessing ---------
load_pos <- function(POS) {
  old <- setwd(POS_DIR[[POS]]); on.exit(setwd(old))
  e <- new.env()
  if (POS == "WR") {
    tbl <- readRDS("wr_model_table.rds") %>%
      mutate(final_power5 = as.integer(final_power5), combine_invited = as.integer(combine_invited)) %>%
      left_join(read.csv("phase5_finish_targets.csv") %>% select(draft_season, pick, finish_y1, finish_y2, finish_y3, finish_sum_3yr),
                by = c("draft_season", "pick")) %>%
      mutate(best_finish = pmin(finish_y1, finish_y2, finish_y3, na.rm = TRUE),
             tier = case_when(best_finish <= 12 ~ 1L, best_finish <= 24 ~ 2L, best_finish <= 36 ~ 3L, TRUE ~ 4L))
    train <- tbl %>% filter(!is.na(finish_sum_3yr))
    # wr_phase6_tier_ladder.R, verbatim
    drills   <- c("forty", "vertical", "broad_jump", "speed_score")
    pre_num  <- c("age_at_draft", "final_dominator", "best_dominator", "final_yptpa", "breakout_age_filled", "career_rec_yds",
                  "college_seasons", "height_in", "weight_lb", "recruit_rating")
    pre_flag <- c("broke_out", "transferred", "early_declare", "final_power5", "college_matched", "combine_invited",
                  "miss_forty", "miss_vertical", "miss_broad_jump")
    post_num <- c("log_pick", "vacated_target_share", "team_targets_prev")
    num <- c(pre_num, post_num)
    fit_prep <- function(d) {
      med  <- sapply(c(num, drills), function(v) median(d[[v]], na.rm = TRUE))
      flag <- num[sapply(num, function(v) any(is.na(d[[v]])))]
      dm <- as.matrix(d[, drills]); for (v in drills) dm[is.na(dm[, v]), v] <- med[v]
      list(num = num, med = med, flag = flag, pca = prcomp(dm, center = TRUE, scale. = TRUE))
    }
    apply_prep <- function(p, d) {
      out <- data.frame(row.names = seq_len(nrow(d)))
      for (v in p$num) { x <- d[[v]]
        if (v %in% p$flag) out[[paste0("na_", v)]] <- as.integer(is.na(x))
        x[is.na(x)] <- p$med[v]; out[[v]] <- x }
      dm <- as.matrix(d[, drills]); for (v in drills) dm[is.na(dm[, v]), v] <- p$med[v]
      pcs <- predict(p$pca, dm)[, 1:2, drop = FALSE]
      out$athletic_pc1 <- pcs[, 1]; out$athletic_pc2 <- pcs[, 2]
      for (v in pre_flag) out[[v]] <- as.integer(coalesce(as.numeric(d[[v]]), 0))
      as.matrix(out)
    }
    pp <- fit_prep(train); X <- apply_prep(pp, train)
    sc <- apply(X, 2, sd); sc[sc == 0] <- 1; nlam <- 25; pca <- pp$pca
  } else {
    sys.source(paste0(tolower(POS), "_common.R"), envir = e)
    tbl <- e$load_table()
    train <- tbl %>% filter(!is.na(finish_sum_3yr))
    num <- c(e$pre_num, e$post_num)
    pp <- e$fit_prep(train, num); X <- e$apply_prep(pp, train)
    X <- X[, apply(X, 2, sd) > 0, drop = FALSE]; sc <- apply(X, 2, sd); nlam <- 20; pca <- NULL
  }
  list(train = train, X = X, ce = colMeans(X), sc = sc, nlam = nlam, pca = pca)
}

# --- refit the final post ladder (same call as the position scripts) ---------------------
fit_ladder <- function(L) {
  Xs <- scale(L$X, L$ce, L$sc)
  y <- factor(L$train$tier, levels = 1:4, ordered = TRUE)
  fit <- ordinalNet(Xs, y, family = "cumulative", link = "logit", alpha = 0.5, parallelTerms = TRUE,
                    nonparallelTerms = FALSE, nLambda = L$nlam, standardize = FALSE)
  folds <- split(seq_len(nrow(Xs)), L$train$draft_season)
  tune <- tryCatch(ordinalNetTune(Xs, y, lambdaVals = fit$lambdaVals, folds = folds, printProgress = FALSE, warn = FALSE,
                                  family = "cumulative", link = "logit", alpha = 0.5, parallelTerms = TRUE,
                                  nonparallelTerms = FALSE, standardize = FALSE), error = function(e) NULL)
  ll <- if (is.null(tune)) NULL else rowMeans(tune$loglik)
  best <- if (is.null(ll) || all(!is.finite(ll))) length(fit$lambdaVals) %/% 2 else which.max(ll)
  list(fit = fit, best = best)
}
p_any <- function(F, L, X) {   # P(any tier) = P(tier <= 3) on a raw (prepared, unstandardized) matrix
  pr <- matrix(predict(F$fit, scale(X, L$ce, L$sc), whichLambda = F$best, type = "response"), ncol = 4)
  pr[, 1] + pr[, 2] + pr[, 3]
}

LABELS <- c(log_pick = "Draft pick (log)", age_at_draft = "Age at draft", recruit_rating = "Recruiting rating",
  vacated_att_share = "Vacated pass-attempt share", vacated_touch_share = "Vacated touch share",
  vacated_tgt_share = "Vacated target share", vacated_target_share = "Vacated target share",
  incumbent_pts = "Incumbent's fantasy points", team_targets_prev = "Team targets the year before",
  height_in = "Height", weight_lb = "Weight", forty = "40-yard dash", speed_score = "Speed score",
  vertical = "Vertical jump", broad_jump = "Broad jump", cone = "3-cone", athletic_pc1 = "Athletic PC1", athletic_pc2 = "Athletic PC2",
  p_aya = "AY/A, primary season", best_aya = "Best-season AY/A", p_comp_pct = "Completion %", p_td_rate = "TD rate",
  p_int_rate = "INT rate", p_pass_share = "Share of team pass attempts", p_rush_yds = "Rushing yards, primary season",
  p_rush_td = "Rushing TDs, primary season", career_att = "Career pass attempts", career_rush_yds = "Career rushing yards",
  starter_age_filled = "Age when he became a starter", starter_seasons = "Seasons as starter", p_ypc = "Yards per carry",
  p_rec = "Receptions, primary season", p_rec_share = "Share of team catches", p_car_share = "Share of team carries",
  p_scrim_share = "Share of team scrimmage yards", p_td_share = "Share of team TDs", best_scrim_share = "Best-season scrimmage share",
  career_rec = "Career receptions", career_ypc = "Career yards per carry", featured_seasons = "Featured seasons",
  breakout_age_filled = "Breakout age", p_rec_yds = "Receiving yards, primary season", p_rec_td = "Receiving TDs, primary season",
  p_ypr = "Yards per catch", p_dominator = "Dominator rating", p_ypta = "Rec. yards per team pass attempt",
  best_dominator = "Best-season dominator", career_rec_yds = "Career receiving yards", final_dominator = "Dominator, final season",
  final_yptpa = "Rec. yards per team pass attempt, final", college_seasons = "College seasons",
  ever_starter = "Ever a starter", ever_breakout = "Ever broke out", broke_out = "Broke out", transferred = "Transferred",
  early_declare = "Early declare", p_power5 = "Power 5 school", final_power5 = "Power 5 school", college_matched = "College stats matched",
  combine_invited = "Combine invite", miss_forty = "No 40 time", miss_vertical = "No vertical", miss_broad_jump = "No broad jump",
  final_short = "Short final season", recruit_dual = "Dual-threat recruit", recruit_apb = "All-purpose back recruit")
lab <- function(v) ifelse(v %in% names(LABELS), LABELS[v], v)

summ <- list()
for (POS in c("WR", "QB", "RB", "TE")) {
  cat("\n=====", POS, "=====\n")
  L <- load_pos(POS); tr <- L$train
  y3 <- as.integer(tr$tier <= 3)
  cat("training rows:", nrow(tr), " classes", min(tr$draft_season), "-", max(tr$draft_season),
      " hits top / top two / any:", sum(tr$tier == 1), "/", sum(tr$tier <= 2), "/", sum(y3), "\n")
  F <- fit_ladder(L)
  cat("lambda index", F$best, "of", length(F$fit$lambdaVals), " lambda =", signif(F$fit$lambdaVals[F$best], 3), "\n")

  # --- 2. coefficients: odds per SD, sign check ------------------------------------------
  cf <- coef(F$fit, whichLambda = F$best)
  b <- cf[!grepl("Intercept", names(cf))]; names(b) <- colnames(L$X)
  stopifnot(length(b) == ncol(L$X))
  # ordinalNet cumulative logit: P(tier <= j) = plogis(int_j + x'b); tier 1 = best, so b > 0 raises hit odds
  ok <- b[["log_pick"]] < 0
  cat(sprintf("[%s] sign check: log_pick coefficient %.3f (a later pick lowers the odds of a tier season)\n", ifelse(ok, "PASS", "FAIL"), b[["log_pick"]]))
  stopifnot(ok)
  coefs <- data.frame(column = names(b), beta = unname(b), odds_per_sd = exp(unname(b)), sd = L$sc[names(b)]) %>%
    mutate(variable = sub("^na_", "", column))
  write.csv(coefs %>% mutate(across(where(is.double), ~ signif(.x, 4))), file.path(OUT, sprintf("pd_post_%s_coefs.csv", POS)), row.names = FALSE)

  # --- 1. permutation importance (input + its missing flag shuffled together) ----------
  base <- p_any(F, L, L$X); base_auc <- aucf(y3, base)
  vars <- unique(sub("^na_", "", colnames(L$X)))
  set.seed(2026)
  imp <- bind_rows(lapply(vars, function(v) {
    cols <- intersect(c(v, paste0("na_", v)), colnames(L$X))
    drops <- replicate(3, { Xp <- L$X; i <- sample(nrow(Xp)); Xp[, cols] <- Xp[i, cols, drop = FALSE]; base_auc - aucf(y3, p_any(F, L, Xp)) })
    data.frame(variable = v, auc_drop = mean(drops))
  })) %>% left_join(coefs %>% filter(column == variable) %>% select(variable, beta, odds_per_sd), by = "variable") %>%
    left_join(coefs %>% filter(column != variable) %>% select(variable, flag_beta = beta, flag_odds = odds_per_sd), by = "variable") %>%
    mutate(label = lab(variable)) %>% arrange(desc(auc_drop)) %>% mutate(across(where(is.double), ~ round(.x, 4)))
  cat("in-sample AUC P(any tier):", round(base_auc, 3), "\n"); print(as.data.frame(imp), row.names = FALSE)
  write.csv(imp, file.path(OUT, sprintf("pd_post_%s_importance.csv", POS)), row.names = FALSE)
  g <- ggplot(head(imp, 12), aes(reorder(label, auc_drop), auc_drop)) + geom_col(fill = mycols[5]) + coord_flip() +
    labs(x = NULL, y = "AUC drop when shuffled", title = sprintf("%s post-draft model: permutation importance", POS)) + theme_minimal()
  ggsave(file.path(OUT, sprintf("plot_post_%s_importance.png", POS)), g, width = 7, height = 4.5, dpi = 120)

  # --- 3. PDP + ICE for the top 3 inputs ------------------------------------------------
  top3 <- head(imp$variable, 3)
  set.seed(2026); ice_ids <- sample(nrow(L$X), 40)
  pd <- bind_rows(lapply(top3, function(v) {
    x <- L$X[, v]; if (paste0("na_", v) %in% colnames(L$X)) x <- x[L$X[, paste0("na_", v)] == 0]
    grid <- if (all(x %in% c(0, 1))) c(0, 1) else unique(quantile(x, seq(.05, .95, length.out = 15)))   # yes/no inputs: 0 vs 1
    bind_rows(lapply(grid, function(gv) {
      Xg <- L$X; Xg[, v] <- gv; if (paste0("na_", v) %in% colnames(Xg)) Xg[, paste0("na_", v)] <- 0
      p <- p_any(F, L, Xg)
      data.frame(variable = v, label = lab(v), x = gv, id = c(0, ice_ids), p = c(mean(p), p[ice_ids]))
    }))
  }))
  pd_shown <- pd %>% mutate(x_shown = ifelse(variable == "log_pick", exp(x), x))
  # extra PDP readings for the write-up: pick 10 / 32 / 64 / 100 / 150 / 200
  for (pk in c(10, 32, 64, 100, 150, 200)) { Xg <- L$X; Xg[, "log_pick"] <- log(pk)
    cat(sprintf("PDP pick %3d: P(any tier) %.3f\n", pk, mean(p_any(F, L, Xg)))) }
  write.csv(pd_shown %>% mutate(across(where(is.double), ~ signif(.x, 4))), file.path(OUT, sprintf("pd_post_%s_pdp_ice.csv", POS)), row.names = FALSE)
  cat("PDP endpoints (5th -> 95th pct):\n")
  print(as.data.frame(pd_shown %>% filter(id == 0) %>% group_by(variable) %>%
    summarize(x_lo = first(x_shown), p_lo = first(p), x_hi = last(x_shown), p_hi = last(p), .groups = "drop") %>%
    mutate(across(where(is.double), ~ signif(.x, 3)))), row.names = FALSE)
  g <- ggplot(pd_shown %>% filter(id != 0), aes(x_shown, p, group = id)) + geom_line(alpha = .25, color = "grey50") +
    geom_line(data = pd_shown %>% filter(id == 0), color = mycols[6], linewidth = 1.3) +
    facet_wrap(~ label, scales = "free_x") + theme_minimal() +
    labs(x = "input value (draft pick shown as the pick number, on the model's log scale)", y = sprintf("P(%s%d season in yrs 1-3)", POS, TIERS[[POS]][3]),
         title = sprintf("%s post-draft: PDP (orange) and ICE (grey) for the top 3 inputs", POS))
  ggsave(file.path(OUT, sprintf("plot_post_%s_pdp_ice.png", POS)), g, width = 9, height = 3.8, dpi = 120)

  # --- 4. SHAP: exact linear contributions on the log-odds scale --------------------------
  Xs <- scale(L$X, L$ce, L$sc)                       # standardized; mean 0 on the training rows
  sh <- sweep(sweep(Xs, 2, colMeans(Xs)), 2, b, "*")  # beta * (x - mean)
  base_v <- sub("^na_", "", colnames(sh))
  sh <- sapply(unique(base_v), function(u) rowSums(sh[, base_v == u, drop = FALSE]))
  ms <- sort(colMeans(abs(sh)), decreasing = TRUE)
  cat("SHAP mean |value| (log-odds):\n"); print(round(head(ms, 12), 3))
  top10 <- names(head(ms[ms > 0], 10))
  long <- as.data.frame(sh[, top10, drop = FALSE]) %>% mutate(row = row_number()) %>%
    pivot_longer(-row, names_to = "variable", values_to = "shap") %>%
    group_by(variable) %>% mutate(val = percent_rank(L$X[row, first(variable)])) %>% ungroup() %>%
    mutate(label = factor(lab(variable), levels = rev(lab(top10))))
  g <- ggplot(long, aes(shap, label, color = val)) + geom_jitter(height = .2, size = .7, alpha = .6) +
    scale_color_gradient(low = mycols[2], high = mycols[6], name = "input\npercentile") + theme_minimal() +
    labs(x = "SHAP value (log-odds of a tier season)", y = NULL, title = sprintf("%s post-draft: SHAP summary (exact linear contributions)", POS))
  ggsave(file.path(OUT, sprintf("plot_post_%s_shap.png", POS)), g, width = 8, height = 5, dpi = 120)

  pick_share <- unname(ms["log_pick"] / sum(ms))
  summ[[POS]] <- data.frame(position = POS, n = nrow(tr), hits_top = sum(tr$tier == 1), hits_top2 = sum(tr$tier <= 2), hits_any = sum(y3),
    inputs = ncol(L$X), nonzero = sum(b != 0), auc_any = round(base_auc, 3), lambda = signif(F$fit$lambdaVals[F$best], 3),
    log_pick_beta = round(b[["log_pick"]], 3), log_pick_odds_per_sd = round(exp(b[["log_pick"]]), 3),
    log_pick_auc_drop = imp$auc_drop[imp$variable == "log_pick"], next_auc_drop = imp$auc_drop[imp$variable != "log_pick"][1],
    log_pick_shap_share = round(pick_share, 3), shap_rank_matches_importance_top3 = setequal(head(names(ms), 3), top3))
}
S <- bind_rows(summ); print(S, row.names = FALSE)
write.csv(S, file.path(OUT, "pd_post_predictors_summary.csv"), row.names = FALSE)
cat("\ndone\n")
