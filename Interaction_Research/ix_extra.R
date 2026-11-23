# Extra visuals: GAM smooths for the two inputs that showed curvature, 2-D partial dependence for the strongest RF interaction,
# and the trade-value still-playing curve (live vs with added terms).
suppressMessages({ library(dplyr); library(mgcv); library(ranger); library(ggplot2) })
th <- theme_minimal(base_size = 12) + theme(plot.title = element_text(face = "bold"), panel.grid.minor = element_blank(), plot.background = element_rect(fill = "white", colour = NA))
sm <- function(f, v, title) { L <- readRDS(f); X <- L$X[, L$cont]; df <- data.frame(X, y = L$D$y3); names(df) <- make.names(names(df))
  fo <- as.formula(paste("y ~", paste(setdiff(names(df), c("y", v)), collapse = " + "), "+ s(", v, ", k = 5)"))
  g <- gam(fo, family = binomial, data = df, method = "REML"); lin <- glm(as.formula(paste("y ~", paste(setdiff(names(df), "y"), collapse = " + "))), family = binomial, data = df)
  grid <- data.frame(lapply(df, function(z) rep(median(z), 100))); grid[[v]] <- seq(quantile(df[[v]], .02), quantile(df[[v]], .98), length = 100)
  pg <- predict(g, grid, se.fit = TRUE); pl <- predict(lin, grid)
  d <- data.frame(x = grid[[v]], curve = pg$fit, lo = pg$fit - 2 * pg$se.fit, hi = pg$fit + 2 * pg$se.fit, line = pl)
  ggplot(d, aes(x)) + geom_ribbon(aes(ymin = plogis(lo), ymax = plogis(hi)), fill = "#D55E00", alpha = .15) + geom_line(aes(y = plogis(curve), colour = "curve (GAM smooth)"), linewidth = 1) +
    geom_line(aes(y = plogis(line), colour = "straight line (current form)"), linewidth = 1, linetype = 2) + geom_rug(data = df, aes(x = .data[[v]]), inherit.aes = FALSE, alpha = .2) +
    scale_colour_manual(values = c("curve (GAM smooth)" = "#D55E00", "straight line (current form)" = "#0072B2"), name = NULL) +
    labs(x = v, y = "P(any-tier season), other inputs at median", title = title) + th + theme(legend.position = "bottom") }
ggsave("charts/08_curve_postWR_logpick.png", sm("post_WR_design.rds", "log_pick", "Post-draft WR: draft pick (log) - curve vs straight line"), width = 8, height = 5.5, dpi = 130)
ggsave("charts/09_curve_preRB_pcar.png", sm("pre_RB_design.rds", "p_car", "Pre-draft RB: final-season carries - curve vs straight line"), width = 8, height = 5.5, dpi = 130)
pd2 <- function(f, a, b, title) { L <- readRDS(f); X <- as.data.frame(L$X); y <- L$D$y3
  rf <- ranger(x = X, y = factor(y, levels = 0:1), probability = TRUE, num.trees = 500, min.node.size = 20, seed = 2026, num.threads = 4)
  ga <- quantile(X[[a]], seq(.05, .95, length = 15)); gb <- quantile(X[[b]], seq(.05, .95, length = 15)); set.seed(1); S <- X[sample.int(nrow(X), 300), ]
  d <- expand.grid(a = ga, b = gb); d$p <- mapply(function(u, w) { Z <- S; Z[[a]] <- u; Z[[b]] <- w; mean(predict(rf, Z, num.threads = 4)$predictions[, "1"]) }, d$a, d$b)
  ggplot(d, aes(a, b, fill = p)) + geom_tile() + scale_fill_viridis_c(name = "P(any tier)") + labs(x = a, y = b, title = title, subtitle = "Random-forest 2-D partial dependence. Parallel colour bands = no interaction") + th }
ggsave("charts/10_pdp2_preRB_scrim.png", pd2("pre_RB_design.rds", "p_scrim_share", "best_scrim_share", "Pre-draft RB: strongest interaction pair (H = 0.38)"), width = 8, height = 6, dpi = 130)
ggsave("charts/11_pdp2_preTE_dom.png", pd2("pre_TE_design.rds", "best_dominator", "p_rec", "Pre-draft TE: second-strongest pair (H = 0.33)"), width = 8, height = 6, dpi = 130)
cat("extra done\n")
