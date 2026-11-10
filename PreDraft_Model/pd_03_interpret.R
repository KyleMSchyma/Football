# =============================================================================
# Pre-Draft Model -- Phase 3: interpretation (ATPA 4.3 workflow)
#   1. Permutation variable importance for the chosen model (AUC drop when a
#      college input is shuffled; its missing flag is shuffled with it)
#   2. PDP + ICE curves for the three most important inputs (any-tier probability)
#   3. SHAP values: exact TreeSHAP from the xgboost component (log-odds scale), or
#      exact linear contributions when the chosen model is the elastic net. These
#      drive the per-player deep dives.
# Outputs per position: pd_<pos>_importance.csv, pd_<pos>_shap_prospects.csv,
#   plots plot_<pos>_importance.png, plot_<pos>_pdp_ice.png, plot_<pos>_shap.png
# =============================================================================
source("pd_common.R"); source("pd_model_fns.R")
suppressMessages(library(ggplot2))

base_var <- function(cols) sub("^na_", "", cols)
for (POS in POSITIONS) {
  S <- readRDS(sprintf("pd_%s_models.rds", POS))
  pool  <- readRDS("pd_pool.rds") %>% filter(position == POS)
  train <- pool %>% filter(outcome_known, class %in% TRAIN_CLASSES) %>% mutate(y3 = as.integer(tier <= 3))
  score <- pool %>% filter(class >= 2024)
  cat("\n=====", POS, ": chosen model", S$chosen, "=====\n")

  # --- 1. permutation importance ------------------------------------------------------
  base_p <- pred_chosen(S, train, 3); base_auc <- aucf(train$y3, base_p)
  set.seed(2026)
  imp <- bind_rows(lapply(S$vars, function(v) {
    drops <- replicate(3, { d <- train; d[[v]] <- sample(d[[v]]); base_auc - aucf(d$y3, pred_chosen(S, d, 3)) })
    data.frame(variable = v, auc_drop = mean(drops))
  })) %>% arrange(desc(auc_drop)) %>% mutate(auc_drop = round(auc_drop, 4))
  cat("in-sample AUC (any tier):", round(base_auc, 3), "\npermutation importance:\n"); print(imp, row.names = FALSE)
  write.csv(imp, sprintf("pd_%s_importance.csv", POS), row.names = FALSE)
  g <- ggplot(head(imp, 12), aes(reorder(variable, auc_drop), auc_drop)) + geom_col(fill = mycols[5]) + coord_flip() +
    labs(x = NULL, y = "AUC drop when shuffled", title = sprintf("%s pre-draft model (%s): permutation importance", POS, S$chosen)) + theme_minimal()
  ggsave(sprintf("plot_%s_importance.png", POS), g, width = 7, height = 4.5, dpi = 120)

  # --- 2. PDP + ICE ---------------------------------------------------------------------
  top3 <- head(imp$variable[!imp$variable %in% c("recruit_missing")], 3)
  set.seed(2026); ice_ids <- sample(nrow(train), 40)
  pd <- bind_rows(lapply(top3, function(v) {
    grid <- unique(quantile(train[[v]], seq(.05, .95, length.out = 15), na.rm = TRUE))
    bind_rows(lapply(grid, function(gv) {
      d <- train; d[[v]] <- gv; p <- pred_chosen(S, d, 3)
      data.frame(variable = v, x = gv, id = c(0, ice_ids), p = c(mean(p), p[ice_ids]))
    }))
  }))
  write.csv(pd, sprintf("pd_%s_pdp_ice.csv", POS), row.names = FALSE)
  g <- ggplot(pd %>% filter(id != 0), aes(x, p, group = id)) + geom_line(alpha = .25, color = "grey50") +
    geom_line(data = pd %>% filter(id == 0), color = mycols[6], linewidth = 1.3) +
    facet_wrap(~ variable, scales = "free_x") + theme_minimal() +
    labs(x = NULL, y = sprintf("P(%s season in yrs 1-3)", tier_labels(POS)[3]),
         title = sprintf("%s: PDP (orange) and ICE (grey) for the top 3 inputs", POS))
  ggsave(sprintf("plot_%s_pdp_ice.png", POS), g, width = 9, height = 3.8, dpi = 120)

  # --- 3. SHAP --------------------------------------------------------------------------
  Xtr <- apply_prep(S$M$prep, train); Xsc <- apply_prep(S$M$prep, score)
  shap_fn <- if (S$chosen %in% c("enet", "glm")) {
    b <- setNames(rep(0, ncol(Xtr)), colnames(Xtr))
    if (S$chosen == "enet") { cf <- as.matrix(coef(S$M$fits$y3$enet, s = "lambda.min"))[-1, 1]; b[names(cf)] <- cf
    } else { cf <- coef(S$M$fits$y3$glm)[-1]; cf[is.na(cf)] <- 0; b[names(cf)] <- cf }
    mu <- colMeans(Xtr)
    function(X) sweep(sweep(X, 2, mu), 2, b, "*")
  } else function(X) { s <- predict(S$M$fits$y3$xgb, X, predcontrib = TRUE); s[, !colnames(s) %in% c("BIAS", "(Intercept)"), drop = FALSE] }
  method <- switch(S$chosen, enet = "elastic-net linear contributions", glm = "logistic-regression linear contributions", "xgboost TreeSHAP")
  agg <- function(sh) { sh <- as.matrix(sh); v <- base_var(colnames(sh))
    sapply(unique(v), function(u) rowSums(sh[, v == u, drop = FALSE])) }
  sh_tr <- agg(shap_fn(Xtr)); sh_sc <- agg(shap_fn(Xsc))
  ms <- sort(colMeans(abs(sh_tr)), decreasing = TRUE)
  cat("SHAP (", method, ") mean |value| on training pool:\n"); print(round(head(ms, 12), 3))
  long <- as.data.frame(sh_tr[, names(head(ms, 10))]) %>% mutate(row = row_number()) %>%
    pivot_longer(-row, names_to = "variable", values_to = "shap") %>%
    group_by(variable) %>% mutate(val = percent_rank(train[[first(variable)]][row])) %>% ungroup()
  g <- ggplot(long, aes(shap, factor(variable, levels = rev(names(head(ms, 10)))), color = val)) +
    geom_jitter(height = .2, size = .7, alpha = .6) + scale_color_gradient(low = mycols[2], high = mycols[6], name = "input\npercentile") +
    theme_minimal() + labs(x = "SHAP value (log-odds of any-tier season)", y = NULL,
                           title = sprintf("%s: SHAP summary (%s)", POS, method))
  ggsave(sprintf("plot_%s_shap.png", POS), g, width = 8, height = 5, dpi = 120)
  out <- as.data.frame(sh_sc) %>% mutate(athlete_id = score$athlete_id, class = score$class) %>%
    pivot_longer(-c(athlete_id, class), names_to = "variable", values_to = "shap") %>%
    mutate(value = mapply(function(a, v) score[[v]][match(a, score$athlete_id)], athlete_id, variable), method = method)
  write.csv(out, sprintf("pd_%s_shap_prospects.csv", POS), row.names = FALSE)
}
