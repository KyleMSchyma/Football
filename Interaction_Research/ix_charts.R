suppressMessages({ library(dplyr); library(tidyr); library(ggplot2) })
dir.create("charts", showWarnings = FALSE)
th <- theme_minimal(base_size = 12) + theme(plot.title = element_text(face = "bold"), panel.grid.minor = element_blank(), plot.background = element_rect(fill = "white", colour = NA))
lab_model <- function(m) { m <- sub("^post_", "Post-draft ", m); m <- sub("^pre_", "Pre-draft ", m); sub("_glm5$", " (5-input GLM)", m) }
vlab <- c(sq_key = "squared: 2 key inputs", sq_all = "squared: every input", int_key = "key input times others", int_all = "all pairwise products", full = "all squared + all products")
# 1. holdout results: % change in log loss vs current model, with 95% bootstrap CI
S <- bind_rows(lapply(Sys.glob("p*_summary.csv"), read.csv)) %>% filter(variant != "base") %>%
  mutate(model = lab_model(model), variant = factor(vlab[variant], levels = vlab),
         base_ll = LL_mean - dLL, lo = 100 * dLL_lo / base_ll, hi = 100 * dLL_hi / base_ll)
write.csv(S, "all_rookie_summaries.csv", row.names = FALSE)
g <- ggplot(S, aes(dLL_pct, variant, colour = scheme)) + geom_vline(xintercept = 0, colour = "grey40") +
  geom_errorbarh(aes(xmin = lo, xmax = hi), height = 0, position = position_dodge(.6), alpha = .7) + geom_point(position = position_dodge(.6), size = 2) +
  facet_wrap(~model, ncol = 3) + coord_cartesian(xlim = c(-15, 25)) + scale_colour_manual(values = c(LOCO = "#0072B2", Rolling = "#D55E00")) +
  labs(x = "% change in holdout log loss vs current model (left of 0 = better)", y = NULL, colour = "Holdout",
       title = "Adding squared or interaction terms to the rookie models", subtitle = "Mean of the 3 tier-hit targets; bars = 95% bootstrap interval (players resampled)") + th
ggsave("charts/01_rookie_holdout_logloss.png", g, width = 13, height = 9, dpi = 130)
g <- ggplot(S, aes(AUC_mean - (AUC_mean - 0), variant, colour = scheme)) + geom_point(size = 2, position = position_dodge(.6)) +
  facet_wrap(~model, ncol = 3) + labs(x = "holdout AUC (mean of 3 tier targets)", y = NULL, colour = "Holdout", title = "Holdout AUC by variant") + th
B <- bind_rows(lapply(Sys.glob("p*_summary.csv"), read.csv)) %>% mutate(model = lab_model(model), variant = factor(c(base = "current model", vlab)[variant], levels = c("current model", vlab)))
g <- ggplot(B, aes(AUC_mean, variant, colour = scheme)) + geom_point(size = 2.3, position = position_dodge(.5)) + facet_wrap(~model, ncol = 3) +
  scale_colour_manual(values = c(LOCO = "#0072B2", Rolling = "#D55E00")) + labs(x = "holdout AUC (mean of the 3 tier targets; higher = better)", y = NULL, colour = "Holdout", title = "Holdout AUC: current model vs added terms") + th
ggsave("charts/02_rookie_holdout_auc.png", g, width = 13, height = 9, dpi = 130)
# 3. trade values
T <- read.csv("tv_summary.csv") %>% filter(!variant %in% c("live", "base")) %>% mutate(part = recode(part, "act (still playing)" = "Still playing", "prior (draft-capital PPG)" = "Draft prior", "prod (next-season PPG)" = "Next-season PPG")) %>%
  mutate(variant = recode(variant, cppg_sq = "credible PPG squared", cppg_x_age = "credible PPG x age", cppg_x_exp = "credible PPG x years in league", cppg_ns = "spline on credible PPG",
                          lpick_x_exp = "draft pick x years in league", int = "draft pick x years in league", all = "all of these"))
g <- ggplot(T, aes(pct_vs_live, variant, fill = pct_vs_live < 0)) + geom_col() + geom_vline(xintercept = 0) +
  geom_text(aes(label = paste0(seasons_better, "/", seasons)), hjust = ifelse(T$pct_vs_live < 0, 1.1, -0.1), size = 3) +
  facet_grid(part ~ pos, scales = "free_y", space = "free_y") + scale_fill_manual(values = c(`TRUE` = "#009E73", `FALSE` = "#D55E00"), guide = "none") +
  scale_x_continuous(expand = expansion(mult = .35)) +
  labs(x = "% change in holdout error vs live model (left = better); label = seasons better", y = NULL,
       title = "Trade value regressions: adding squared / interaction terms", subtitle = "Rolling by season: train on earlier seasons, test the next (2014-2025)") + th
ggsave("charts/03_trade_value_holdout.png", g, width = 13, height = 7.5, dpi = 130)
# 4-7 diagnostics
if (file.exists("diag_hstat.csv")) {
  H <- read.csv("diag_hstat.csv") %>% mutate(design = lab_model(design), pair = paste(var1, "x", var2)) %>% group_by(design) %>% slice_max(H, n = 8) %>% ungroup()
  g <- ggplot(H, aes(H, reorder(paste(design, pair), H))) + geom_col(fill = "#0072B2") + facet_wrap(~design, scales = "free_y", ncol = 2) +
    scale_y_discrete(labels = function(x) sub("^(Pre|Post)-draft [A-Z]{2} ", "", x)) + geom_vline(xintercept = .2, linetype = 2, colour = "grey50") +
    labs(x = "Friedman H (share of the pair's joint effect that is interaction; 0 = none)", y = NULL, title = "Interaction strength in a random forest, top 6 inputs", subtitle = "Target: any-tier hit in NFL years 1-3. Dashed line = 0.2") + th
  ggsave("charts/04_hstat.png", g, width = 13, height = 11, dpi = 130)
  V <- read.csv("diag_vif.csv") %>% mutate(design = lab_model(design)) %>% group_by(design) %>% slice_max(VIF, n = 10) %>% ungroup()
  g <- ggplot(V, aes(VIF, reorder(paste(design, var), VIF), fill = VIF > 10)) + geom_col() + facet_wrap(~design, scales = "free_y", ncol = 2) +
    scale_y_discrete(labels = function(x) sub("^(Pre|Post)-draft [A-Z]{2} ", "", x)) + geom_vline(xintercept = c(5, 10), linetype = 2, colour = "grey50") + scale_x_log10() +
    scale_fill_manual(values = c(`TRUE` = "#D55E00", `FALSE` = "#56B4E9"), guide = "none") + labs(x = "VIF (log scale; dashed = 5 and 10)", y = NULL, title = "Collinearity: 10 highest VIFs per model") + th
  ggsave("charts/05_vif.png", g, width = 13, height = 12, dpi = 130)
  G <- read.csv("diag_curvature_gam.csv") %>% mutate(design = lab_model(design))
  g <- ggplot(G, aes(-dAIC_vs_linear, reorder(paste(design, var), -dAIC_vs_linear), fill = p_smooth < .01 & dAIC_vs_linear < -4)) + geom_col() +
    facet_wrap(~design, scales = "free_y", ncol = 2) + scale_y_discrete(labels = function(x) sub("^(Pre|Post)-draft [A-Z]{2} ", "", x)) +
    scale_fill_manual(values = c(`TRUE` = "#D55E00", `FALSE` = "grey70"), labels = c("no clear curve", "curve (p<.01, AIC drop > 4)"), name = NULL) +
    labs(x = "AIC improvement from letting this input curve (GAM smooth vs straight line, in-sample)", y = NULL, title = "Curvature check per input (any-tier hit)") + th + theme(legend.position = "bottom")
  ggsave("charts/06_curvature.png", g, width = 13, height = 16, dpi = 130)
}
# correlation heatmaps
for (f in Sys.glob("*_design.rds")) { L <- readRDS(f); Xc <- L$X[, L$cont, drop = FALSE]; Xc <- Xc[, apply(Xc, 2, sd) > 0]
  C <- cor(Xc); d <- as.data.frame(as.table(C)); nm <- lab_model(sub("_design.rds", "", f))
  g <- ggplot(d, aes(Var1, Var2, fill = Freq)) + geom_tile() + geom_text(aes(label = ifelse(abs(Freq) >= .7 & Var1 != Var2, sprintf("%.2f", Freq), "")), size = 2.6) +
    scale_fill_gradient2(low = "#0072B2", high = "#D55E00", limits = c(-1, 1), name = "r") + labs(x = NULL, y = NULL, title = paste0(nm, ": correlations between inputs"), subtitle = "Numbers shown where |r| >= 0.7") +
    th + theme(axis.text.x = element_text(angle = 50, hjust = 1))
  ggsave(sprintf("charts/07_corr_%s.png", sub("_design.rds", "", f)), g, width = 9, height = 8, dpi = 120) }
cat("charts done\n")
