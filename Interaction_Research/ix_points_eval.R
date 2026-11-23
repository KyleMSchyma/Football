suppressMessages({ library(dplyr); library(tidyr); library(ggplot2) }); source("ix_engine.R")
NMS <- c("post_QB", "post_RB", "post_WR", "post_TE", "pre_QB", "pre_RB", "pre_WR", "pre_TE")
rows <- list()
for (nm in NMS) { R <- readRDS(sprintf("%s_results.rds", nm))$pred %>% filter(model == nm)
  lp <- readRDS(sprintf("%s_logpts.rds", nm)) %>% pivot_wider(names_from = variant, values_from = lpts_hat, names_prefix = "lp_")
  b <- R %>% filter(variant == "base") %>% transmute(model, scheme, class, row, y1, y2, y3, pts, hit_score = p1 + p2 + p3, pts_lin = ptsh)
  i <- R %>% filter(variant == "int_all") %>% transmute(scheme, class, row, pts_lin_int = ptsh)
  rows[[nm]] <- b %>% left_join(i, by = c("scheme", "class", "row")) %>% left_join(lp %>% select(-model), by = c("scheme", "class", "row")) %>%
    rename(logpts = lp_base, logpts_int = lp_int_all) }
A <- bind_rows(rows) %>% filter(!is.na(pts))
SC <- c(hit_score = "Hit model (live type): P(top)+P(top2)+P(any)", pts_lin = "Points model", pts_lin_int = "Points model + interactions",
        logpts = "Log-points model", logpts_int = "Log-points model + interactions")
top10 <- function(s, y) { k <- ceiling(.1 * length(s)); sum(y[order(-s)][1:k]) / max(1, sum(y)) }
met <- function(d) bind_rows(lapply(names(SC), function(s) { x <- d[[s]]
  data.frame(score = s, rho_pts = cor(x, d$pts, method = "spearman"), rho_tier = cor(x, d$y1 + d$y2 + d$y3, method = "spearman"),
             AUC_any = aucf(d$y3, x), AUC_top = aucf(d$y1, x), top10_pts_share = top10(x, d$pts), top10_toptier_share = top10(x, d$y1)) }))
M <- A %>% group_by(model, scheme) %>% group_modify(~ met(.x)) %>% ungroup()
# paired bootstrap: points-model Spearman minus hit-model Spearman (players resampled)
bt <- A %>% group_by(model, scheme) %>% group_modify(function(d, k) { set.seed(2026)
  f <- function(i, s) cor(d[[s]][i], d$pts[i], method = "spearman") - cor(d$hit_score[i], d$pts[i], method = "spearman")
  bind_rows(lapply(setdiff(names(SC), "hit_score"), function(s) { b <- replicate(1000, f(sample.int(nrow(d), replace = TRUE), s))
    data.frame(score = s, d_rho_pts = f(seq_len(nrow(d)), s), lo = quantile(b, .025), hi = quantile(b, .975)) })) }) %>% ungroup()
M <- M %>% left_join(bt, by = c("model", "scheme", "score"))
write.csv(M, "points_vs_hits.csv", row.names = FALSE)
options(width = 220); print(as.data.frame(M %>% mutate(across(where(is.double), ~ round(.x, 3)))), row.names = FALSE)
lab <- function(m) { m <- sub("^post_", "Post-draft ", m); sub("^pre_", "Pre-draft ", m) }
P <- M %>% filter(score != "hit_score") %>% mutate(model = lab(model), score = factor(SC[score], levels = SC[-1]))
th <- theme_minimal(base_size = 12) + theme(plot.title = element_text(face = "bold"), panel.grid.minor = element_blank(), plot.background = element_rect(fill = "white", colour = NA))
g <- ggplot(P, aes(d_rho_pts, score, colour = scheme)) + geom_vline(xintercept = 0) + geom_errorbarh(aes(xmin = lo, xmax = hi), height = 0, position = position_dodge(.6)) +
  geom_point(size = 2.2, position = position_dodge(.6)) + facet_wrap(~model, ncol = 4) + scale_colour_manual(values = c(LOCO = "#0072B2", Rolling = "#D55E00")) +
  labs(x = "Spearman with actual 3-year points: points model minus hit model (right of 0 = points model ranks better)", y = NULL, colour = "Holdout",
       title = "Do 3-year points models rank rookies better than the tier-hit models?", subtitle = "Same holdout players; bars = 95% bootstrap interval") + th
ggsave("charts/12_points_vs_hits_rho.png", g, width = 14, height = 6.5, dpi = 130)
Q <- M %>% mutate(model = lab(model), score = factor(SC[score], levels = SC)) %>% select(model, scheme, score, AUC_any, AUC_top, rho_pts) %>%
  pivot_longer(c(AUC_any, AUC_top, rho_pts), names_to = "metric") %>% mutate(metric = recode(metric, AUC_any = "AUC: any-tier season", AUC_top = "AUC: top-tier season", rho_pts = "Spearman: 3-year points"))
g <- ggplot(Q, aes(value, model, colour = score, shape = scheme)) + geom_point(size = 2.4, position = position_dodge(.6)) + facet_wrap(~metric, scales = "free_x") +
  scale_colour_manual(values = c("#111111", "#56B4E9", "#0072B2", "#E69F00", "#D55E00"), name = NULL) + labs(x = NULL, y = NULL, shape = "Holdout",
  title = "Hit model vs points models on three yardsticks", subtitle = "Higher = better on every panel") + th + theme(legend.position = "bottom", legend.box = "vertical")
ggsave("charts/13_points_vs_hits_metrics.png", g, width = 14, height = 7, dpi = 130)
