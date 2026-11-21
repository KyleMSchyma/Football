# Kyle 2026-11-21: rookie values from a PPG MODEL. Per-game projection -> points over replacement per game, x expected games.
#   Stage 1 (out-of-class, LOCO 2010-2022): elastic net on the post-draft inputs (same prep as the post-draft grade), target PPG,
#           weighted by games played: (A) rookie-year PPG, (B) PPG over seasons 1-3.
#   Stage 2 (fit on the other classes): for each season k = 1..5, PPG_k = a_k + b_k * projected PPG + c_k * age (games-weighted lm,
#           residual sd = stop-loss spread) and games_k / 17 = quasi-binomial spline of projected PPG.
#   Value  = sum_k v^k x len x G_k x stoploss(PPG_k - replacement line, sd_k)  -- the same pieces dv_13 uses for each tier.
REPO <- "/home/user/Football"; IX <- "/mnt/project-files/research/interactions_squared"
suppressMessages({ library(dplyr); library(tidyr); library(glmnet); library(splines); library(ggplot2) })
E <- readRDS("/tmp/claude-0/tvrun/Football2_Dynasty/exp/rookie_env.rds"); v <- E$v; NK <- E$NK; LF <- E$LAST_FULL
POS4 <- c("QB", "RB", "WR", "TE")
ryl <- function(Y, ps) { Y2 <- pmax(Y, min(E$rep_y$season)); E$rep_y$rep_ppg[match(paste(Y2, ps), paste(E$rep_y$season, E$rep_y$pos))] }
src <- readLines(file.path(REPO, "PostDraft_Model/pd_20_pick_penalty_experiment.R"))
i <- grep("^load_pos <- function", src); j <- grep("^# ---------- elastic-net variants", src) - 1
select <- dplyr::select; eval(parse(text = src[i:j]))
POS_DIR <- c(QB = file.path(REPO, "QB_Model"), RB = file.path(REPO, "RB_Model"), WR = file.path(REPO, "WR_Model"), TE = file.path(REPO, "TE_Model"))
HK <- E$hk %>% select(pos, class, pick, k, g, pts, g17)
enet <- function(X, y, w, cls, Xte, unpen = "log_pick") { keep <- apply(X, 2, sd) > 0; X <- X[, keep, drop = FALSE]; Xte <- Xte[, keep, drop = FALSE]
  f <- cv.glmnet(X, y, weights = w, alpha = 0.5, foldid = as.integer(factor(cls)), penalty.factor = as.numeric(!colnames(X) %in% unpen))
  as.numeric(predict(f, Xte, s = "lambda.min")) }
# ---------- stage 1: out-of-class PPG projections ----------
P1 <- bind_rows(lapply(POS4, function(POS) { L <- load_pos(POS)
  D <- readRDS(file.path(IX, sprintf("post_%s_design.rds", POS)))$D %>% filter(class <= 2022)
  s <- HK %>% filter(pos == POS) %>% group_by(class, pick) %>%
    summarise(g1 = sum(g[k == 1]), p1 = sum(pts[k == 1]), g3 = sum(g[k <= 3]), p3 = sum(pts[k <= 3]), .groups = "drop")
  D <- D %>% left_join(s, by = c("class", "pick")) %>% mutate(across(c(g1, p1, g3, p3), ~ coalesce(.x, 0)),
    ppg1 = ifelse(g1 > 0, p1 / g1, 0), ppg3 = ifelse(g3 > 0, p3 / g3, 0))
  bind_rows(lapply(sort(unique(D$class)), function(Y) { tr <- D[D$class != Y, ]; te <- D[D$class == Y, ]; P <- L$prep(tr, te)
    a <- tr$g1 > 0; b <- tr$g3 > 0
    data.frame(pos = POS, class = Y, pick = te$pick, age = te$age_at_draft,
               ppgA = enet(P$Xtr[a, ], tr$ppg1[a], pmin(tr$g1[a], 17), tr$class[a], P$Xte),
               ppgB = enet(P$Xtr[b, ], tr$ppg3[b], pmin(tr$g3[b], 51), tr$class[b], P$Xte),
               ppg1 = te$ppg1, g1 = te$g1, ppg3 = te$ppg3, g3 = te$g3) })) }))
P1 <- P1 %>% group_by(pos) %>% mutate(age = coalesce(age, median(age, na.rm = TRUE))) %>% ungroup()
saveRDS(P1, "ppg_oof.rds")
acc <- P1 %>% group_by(pos) %>% summarise(n = n(),
  rookieA_rho = cor(ppgA[g1 > 0], ppg1[g1 > 0], method = "spearman"), rookieA_rmse = sqrt(weighted.mean((ppgA - ppg1)[g1 > 0]^2, g1[g1 > 0])),
  yr13B_rho = cor(ppgB[g3 > 0], ppg3[g3 > 0], method = "spearman"), yr13B_rmse = sqrt(weighted.mean((ppgB - ppg3)[g3 > 0]^2, g3[g3 > 0])), .groups = "drop")
print(as.data.frame(acc), digits = 3); write.csv(acc, "ppg_model_accuracy.csv", row.names = FALSE)
# ---------- stage 2 + values ----------
B <- readRDS("value_backtest_players.rds")
H2 <- HK %>% inner_join(P1 %>% select(pos, class, pick, age, ppgA, ppgB), by = c("pos", "class", "pick"))
vals <- bind_rows(lapply(2016:2022, function(Y) { te <- P1 %>% filter(class == Y); K <- min(NK, LF - Y + 1)
  for (m in c("ppgA", "ppgB")) { out <- rep(0, nrow(te))
    for (ps in POS4) { ii <- which(te$pos == ps); if (!length(ii)) next; rep_ <- ryl(Y, ps)
      for (k in 1:K) { tr <- H2 %>% filter(pos == ps, class != Y, k == !!k) %>% mutate(x = .data[[m]])
        pl <- tr %>% filter(g > 0) %>% mutate(ppg = pts / g)
        fm <- lm(ppg ~ x + age, data = pl, weights = g); sdk <- sqrt(sum(pl$g * resid(fm)^2) / sum(pl$g))
        gm <- glm(I(g17 / 17) ~ ns(x, 3), family = quasibinomial, data = tr)
        nd <- data.frame(x = te[[m]][ii], age = te$age[ii])
        mu <- predict(fm, nd); G <- 17 * predict(gm, nd, type = "response"); len <- ifelse(Y + k - 1 >= 2021, 17, 16) / 17
        out[ii] <- out[ii] + v^k * len * G * E$stoploss(mu, rep_, sdk) } }
    te[[paste0("v_", m)]] <- out }
  te %>% select(pos, class, pick, v_ppgA, v_ppgB) }))
out <- B %>% inner_join(vals, by = c("pos", "class", "pick"))
cat("players", nrow(out), "of", nrow(B), "\n")
M <- c(tier_live = "Live tier method (dv_13)", tier_research = "Tier method, research hit model", v_ppgA = "PPG model: rookie-year PPG", v_ppgB = "PPG model: seasons 1-3 PPG",
       v_lp1 = "Points model, rookie year (earlier test)", v_lp3 = "Points model, 3-year (earlier test)")
sp <- function(a, b) suppressWarnings(cor(a, b, method = "spearman"))
by_pos <- out %>% group_by(pos) %>% group_modify(function(d, k) bind_rows(lapply(names(M), function(s) data.frame(method = s,
  rho = sp(d[[s]], d$realized), ratio = sum(d$realized) / sum(d[[s]]))))) %>% ungroup()
cls <- out %>% group_by(class) %>% group_modify(function(d, k) bind_rows(lapply(names(M), function(s) { o <- order(-d[[s]])[1:12]
  data.frame(method = s, rho_all = sp(d[[s]], d$realized), top12_realized = sum(d$realized[o]), top12_pred = sum(d[[s]][o]), best12 = sum(sort(d$realized, decreasing = TRUE)[1:12])) }))) %>% ungroup()
lv <- cls %>% filter(method == "tier_live") %>% select(class, live_top12 = top12_realized, live_rho = rho_all)
cross <- cls %>% left_join(lv, by = "class") %>% group_by(method) %>% summarise(top12_ratio = sum(top12_realized) / sum(top12_pred), classes_rho_beat_live = sum(rho_all > live_rho), classes_top12_beat_live = sum(top12_realized > live_top12),
  rho_all = mean(rho_all), top12_realized = mean(top12_realized), .groups = "drop")
set.seed(2026)
bt <- bind_rows(lapply(setdiff(names(M), "tier_live"), function(s) { f <- function(d) mean(sapply(split(d, d$class), function(z) sp(z[[s]], z$realized) - sp(z$tier_live, z$realized)))
  b <- replicate(1000, { cl <- sample(2016:2022, replace = TRUE); d <- bind_rows(lapply(seq_along(cl), function(j) { z <- out[out$class == cl[j], ]; z[sample.int(nrow(z), replace = TRUE), ] %>% mutate(class = j) })); f(d) })
  data.frame(method = s, d_rho = f(out), lo = quantile(b, .025), hi = quantile(b, .975)) }))
cross <- cross %>% left_join(bt, by = "method") %>% mutate(label = M[method]) %>% arrange(desc(rho_all))
write.csv(cross, "ppg_value_cross.csv", row.names = FALSE); write.csv(by_pos, "ppg_value_by_pos.csv", row.names = FALSE); write.csv(cls, "ppg_value_by_class.csv", row.names = FALSE)
saveRDS(out, "ppg_value_players.rds")
options(width = 220); print(as.data.frame(cross %>% mutate(across(where(is.double), ~ round(.x, 3)))), row.names = FALSE)
print(as.data.frame(by_pos %>% mutate(across(where(is.double), ~ round(.x, 3))) %>% pivot_wider(names_from = pos, values_from = c(rho, ratio))), row.names = FALSE)
# ---------- charts ----------
th <- theme_minimal(base_size = 12) + theme(plot.title = element_text(face = "bold"), panel.grid.minor = element_blank(), plot.background = element_rect(fill = "white", colour = NA))
lv_ <- rev(M[cross$method]); hi_ <- c("tier_live", "v_ppgA", "v_ppgB")
g <- ggplot(cross %>% mutate(label = factor(label, levels = lv_)), aes(rho_all, label, colour = method %in% hi_)) + geom_point(size = 3) +
  geom_errorbarh(aes(xmin = rho_all + lo - d_rho, xmax = rho_all + hi - d_rho), height = 0) + geom_vline(xintercept = cross$rho_all[cross$method == "tier_live"], linetype = 2) +
  scale_colour_manual(values = c("#99AABB", "#0072B2"), guide = "none") +
  labs(x = "Spearman: predicted vs realized rookie value (all drafted players, all positions, within class; mean 2016-2022)", y = NULL,
       title = "PPG-model rookie values vs the live tier method", subtitle = "Dashed = live tier method. Bars = 95% bootstrap interval of the gap to it") + th
ggsave("charts/07_ppg_value_rank.png", g, width = 12, height = 4.5, dpi = 130)
g <- ggplot(by_pos %>% mutate(label = factor(M[method], levels = lv_)), aes(rho, label, colour = method == "tier_live")) + geom_point(size = 2.6) + facet_wrap(~pos, ncol = 4) +
  scale_colour_manual(values = c("#56B4E9", "#111111"), guide = "none") + labs(x = "Spearman: predicted vs realized value, 2016-2022", y = NULL, title = "PPG-model values by position", subtitle = "Black = live tier method") + th
ggsave("charts/08_ppg_value_by_pos.png", g, width = 14, height = 4.5, dpi = 130)
q <- cls %>% filter(method %in% c("tier_live", "v_ppgA", "v_ppgB")) %>% mutate(label = M[method])
g <- ggplot(q, aes(class, top12_realized, colour = label)) + geom_line(linewidth = .9) + geom_point(size = 2) +
  geom_line(data = cls %>% filter(method == "tier_live"), aes(class, best12), colour = "grey60", linetype = 3, inherit.aes = FALSE) +
  scale_colour_manual(values = c("#111111", "#E69F00", "#0072B2"), name = NULL) +
  labs(x = "Draft class", y = "Realized value of the 12 players taken", title = "12-pick rookie draft: PPG model vs live tier method", subtitle = "Dotted grey = best possible 12 in hindsight") + th + theme(legend.position = "bottom")
ggsave("charts/09_ppg_top12_by_class.png", g, width = 11, height = 6, dpi = 130)
q <- out %>% select(realized, tier_live, v_ppgA, v_ppgB) %>% pivot_longer(-realized) %>% group_by(name) %>% mutate(bin = ntile(value, 10)) %>%
  group_by(name, bin) %>% summarise(pred = mean(value), act = mean(realized), .groups = "drop") %>% mutate(name = M[name])
g <- ggplot(q, aes(pred, act, colour = name)) + geom_abline(linetype = 2) + geom_line() + geom_point(size = 2.2) + scale_colour_manual(values = c("#111111", "#E69F00", "#0072B2"), name = NULL) +
  labs(x = "Predicted value (decile mean)", y = "Realized value (decile mean)", title = "Calibration: PPG model vs live tier method", subtitle = "2016-2022 drafted players; dashed line = right on average") + th + theme(legend.position = "bottom")
ggsave("charts/10_ppg_value_calibration.png", g, width = 8, height = 6.5, dpi = 130)
