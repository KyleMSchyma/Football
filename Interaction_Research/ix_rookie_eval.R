suppressMessages({ library(dplyr); library(tidyr); library(ggplot2) }); source("ix_engine.R")
NMS <- c("post_QB", "post_RB", "post_WR", "post_TE", "pre_QB", "pre_RB", "pre_WR", "pre_TE")
A <- bind_rows(lapply(NMS, function(nm) { r <- readRDS(sprintf("%s_rookie.rds", nm))
  # the 3-year models' scores for the same players (does a 3-year model also rank the rookie year?)
  b3 <- readRDS(sprintf("%s_results.rds", nm))$pred %>% filter(model == nm, variant == "base") %>% transmute(scheme, class, row, hit3yr = p1 + p2 + p3)
  l3 <- readRDS(sprintf("%s_logpts.rds", nm)) %>% filter(variant == "base") %>% transmute(scheme, class, row, logpts3yr = lpts_hat)
  r %>% left_join(b3, by = c("scheme", "class", "row")) %>% left_join(l3, by = c("scheme", "class", "row")) }))
SC <- c(hit_score = "Rookie-year hit model", pts_lin = "Rookie-year points model", logpts = "Rookie-year log-points model",
        logpts_int = "Rookie-year log-points + interactions", hit3yr = "3-year hit model (current type)", logpts3yr = "3-year log-points model")
met <- function(d) bind_rows(lapply(names(SC), function(s) { x <- d[[s]]
  data.frame(score = s, rho_pts = cor(x, d$r_pts, method = "spearman"), AUC_any = aucf(d$r3, x), AUC_top2 = aucf(d$r2, x),
             top10_pts_share = { k <- ceiling(.1 * length(x)); sum(pmax(d$r_pts, 0)[order(-x)][1:k]) / sum(pmax(d$r_pts, 0)) }) }))
M <- A %>% group_by(model, scheme) %>% group_modify(~ met(.x)) %>% ungroup()
bt <- A %>% group_by(model, scheme) %>% group_modify(function(d, k) { set.seed(2026)
  f <- function(i, s) cor(d[[s]][i], d$r_pts[i], method = "spearman") - cor(d$hit_score[i], d$r_pts[i], method = "spearman")
  bind_rows(lapply(setdiff(names(SC), "hit_score"), function(s) { b <- replicate(1000, f(sample.int(nrow(d), replace = TRUE), s))
    data.frame(score = s, d_rho = f(seq_len(nrow(d)), s), lo = quantile(b, .025), hi = quantile(b, .975)) })) }) %>% ungroup()
M <- M %>% left_join(bt, by = c("model", "scheme", "score")); write.csv(M, "rookie_year_points_vs_hits.csv", row.names = FALSE)
options(width = 220); print(as.data.frame(M %>% mutate(across(where(is.double), ~ round(.x, 3)))), row.names = FALSE)
lab <- function(m) { m <- sub("^post_", "Post-draft ", m); sub("^pre_", "Pre-draft ", m) }
th <- theme_minimal(base_size = 12) + theme(plot.title = element_text(face = "bold"), panel.grid.minor = element_blank(), plot.background = element_rect(fill = "white", colour = NA))
P <- M %>% filter(score != "hit_score") %>% mutate(model = lab(model), score = factor(SC[score], levels = rev(SC[-1])))
g <- ggplot(P, aes(d_rho, score, colour = scheme)) + geom_vline(xintercept = 0) + geom_errorbarh(aes(xmin = lo, xmax = hi), height = 0, position = position_dodge(.6)) +
  geom_point(size = 2.2, position = position_dodge(.6)) + facet_wrap(~model, ncol = 4) + scale_colour_manual(values = c(LOCO = "#0072B2", Rolling = "#D55E00")) +
  labs(x = "Spearman with actual ROOKIE-YEAR points, minus the rookie-year hit model (right of 0 = ranks rookie year better)", y = NULL, colour = "Holdout",
       title = "Rookie year only: points models vs the hit model", subtitle = "Same holdout players; bars = 95% bootstrap interval") + th
ggsave("charts/14_rookie_year_points_vs_hits.png", g, width = 14, height = 6.5, dpi = 130)
Q <- M %>% mutate(model = lab(model), score = factor(SC[score], levels = SC))
g <- ggplot(Q, aes(rho_pts, model, colour = score, shape = scheme)) + geom_point(size = 2.6, position = position_dodge(.6)) +
  scale_colour_manual(values = c("#111111", "#56B4E9", "#E69F00", "#D55E00", "grey55", "#009E73"), name = NULL) +
  labs(x = "Spearman with actual rookie-year points (higher = better)", y = NULL, shape = "Holdout", title = "How well each model ranks the rookie year") + th + theme(legend.position = "bottom", legend.box = "vertical")
ggsave("charts/15_rookie_year_rho_all.png", g, width = 12, height = 6.5, dpi = 130)
