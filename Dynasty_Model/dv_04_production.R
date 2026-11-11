# =============================================================================
# Dynasty Model, step 4: production model, E[PAR+ in season t | still alive]
#
# PAR+ = max(0, 17-game PPR points - replacement line). It is zero in about half of alive seasons and
# right-skewed above zero, the same shape as insurance pure premium (many zero-loss policies, a long tail).
# So the main model is a Tweedie GLM with log link (compound Poisson-gamma), compared with a random forest
# and a naive "last season repeats" baseline. Train landmarks 2007-2017, test 2018-2024.
# =============================================================================
source("dv_common.R"); suppressMessages({ library(ranger); library(statmod); library(ggplot2) })
cat("== Dynasty step 4: production model ==\n")
pp <- readRDS("dv_person_period.rds") %>% filter(event == 0)     # alive seasons only
cat("alive player-seasons:", nrow(pp), " share with PAR+ = 0:", round(mean(pp$y == 0), 3), "\n")
tr <- pp %>% filter(lm_season %in% TRAIN_LM); te <- pp %>% filter(lm_season %in% TEST_LM)
RF_X <- c(FEATS, "t", "age_t")

gini <- function(y, p) {   # normalized Gini (lift): 1 = perfect ranking, 0 = random
  g <- function(y, p) { o <- order(p, decreasing = TRUE); cy <- cumsum(y[o]) / sum(y); sum(cy - seq_along(y) / length(y)) }
  g(y, p) / g(y, y) }
score <- function(y, p) c(RMSE = sqrt(mean((y - p)^2)), MAE = mean(abs(y - p)), Spearman = cor(y, p, method = "spearman"),
                          Gini = gini(y, p), mean_pred_minus_actual = mean(p) - mean(y))

fits <- list(); preds <- list()
for (pw in c(1.3, 1.5, 1.7)) {
  f <- glm(pr_formula, data = tr, family = tweedie(var.power = pw, link.power = 0), control = glm.control(maxit = 100))
  fits[[paste0("Tweedie p=", pw)]] <- f; preds[[paste0("Tweedie p=", pw)]] <- predict(f, newdata = te, type = "response")
}
rf <- ranger(y ~ ., data = tr[, c("y", RF_X)], num.trees = 500, min.node.size = 20, mtry = 5, seed = 2026)
preds[["Random forest"]] <- predict(rf, data = te)$predictions
preds[["Blend: Tweedie 1.5 + RF"]] <- (preds[["Tweedie p=1.5"]] + preds[["Random forest"]]) / 2
preds[["Naive: last season repeats"]] <- pmax(te$par, 0)
saveRDS(list(glm = fits[["Tweedie p=1.5"]], rf = rf), "dv_production_models_train.rds")   # for the step 5 backtest
met <- as.data.frame(t(sapply(preds, function(p) score(te$y, p)))) %>% mutate(across(everything(), ~ round(.x, 3)))
cat("\nTEST (alive seasons from landmarks 2018-2024):\n"); print(met)
write.csv(met %>% tibble::rownames_to_column("model"), "dv_production_metrics.csv", row.names = FALSE)

# by horizon: is the model still useful 3-5 seasons out?
byt <- bind_rows(lapply(c("Tweedie p=1.5", "Random forest", "Blend: Tweedie 1.5 + RF", "Naive: last season repeats"), function(n)
  te %>% mutate(p = preds[[n]]) %>% mutate(tb = pmin(t, 5)) %>% group_by(tb) %>%
    summarise(rows = n(), actual = mean(y), pred = mean(p), spearman = cor(y, p, method = "spearman"), .groups = "drop") %>% mutate(model = n)))
cat("\nby seasons ahead (5 = 5+):\n"); print(byt %>% mutate(across(where(is.numeric), ~ round(.x, 2))), n = 30)

# ---- final production model: Tweedie p = 1.5 refit on every landmark (explainable, insurance-standard) ----
final <- glm(pr_formula, data = pp, family = tweedie(var.power = 1.5, link.power = 0), control = glm.control(maxit = 100))
rf_all <- ranger(y ~ ., data = pp[, c("y", RF_X)], num.trees = 500, min.node.size = 20, mtry = 5, importance = "permutation", seed = 2026)
saveRDS(list(glm = final, rf = rf_all), "dv_production_models.rds")
co <- summary(final)$coefficients
out <- data.frame(term = rownames(co), coef = co[, 1], se = co[, 2], p = co[, 4]) %>%
  mutate(multiplier = exp(coef)) %>% mutate(across(where(is.numeric), ~ signif(.x, 3)))
write.csv(out, "dv_production_glm_coefficients.csv", row.names = FALSE)
cat("\nfinal Tweedie GLM (log link: exp(coef) multiplies expected PAR+):\n"); print(out, row.names = FALSE)
imp <- sort(rf_all$variable.importance, decreasing = TRUE)
write.csv(data.frame(feature = names(imp), importance = imp), "dv_production_rf_importance.csv", row.names = FALSE)
cat("\nproduction RF permutation importance:\n"); print(round(imp, 1))

# aging curve picture: average predicted PAR+ by age for a typical startable player (PDP-style)
base <- pp %>% filter(startable == 1, t == 1)
ag <- bind_rows(lapply(POSITIONS, function(ps) bind_rows(lapply(seq(22, 35, 1), function(a) {
  d <- base %>% filter(pos == ps); d$age <- a - 1; d$age_t <- a; d$exp <- pmax(0, pmin(d$exp, a - 22))
  data.frame(pos = ps, age = a, par_plus = mean(predict(final, newdata = d, type = "response"))) }))))
g <- ggplot(ag, aes(age, par_plus, color = pos)) + geom_line(linewidth = 1.1) + scale_color_manual(values = mycols) +
  labs(title = "Aging curves from the production GLM", subtitle = "Expected points above replacement next season for a currently startable player, by age",
       x = "Age next season", y = "Expected PAR+ (PPR, 17 games)", color = NULL) + theme_minimal(base_size = 12)
ggsave("plot_production_aging_curves.png", g, width = 8, height = 5, dpi = 120)
write.csv(ag, "dv_production_aging_curves.csv", row.names = FALSE)
