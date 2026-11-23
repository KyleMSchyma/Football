# Rookie VALUE backtest: live tier method (P(tier) x tier-calibrated seasons, dv_13) vs points projections.
# Drafted players 2016-2022, everything out-of-class. Realized value = dv_13's "players' definition":
#   sum over seasons k <= min(5, 2025 - class + 1) of v^k x games x max(PPG - replacement line of the draft season, 0).
# Mapped methods: for each position and season k, a quasi-Poisson GLM of that season's points over replacement on
# ns(projection, 3) + age, fit on the other 2010-2022 classes; value = sum_k v^k x fitted. Same mapping for every projection,
# so differences come from the projection, not the mapping.
suppressMessages({ library(dplyr); library(tidyr); library(splines); library(ggplot2) })
E <- readRDS("/tmp/claude-0/tvrun/Football2_Dynasty/exp/rookie_env.rds"); v <- E$v; NK <- E$NK; LF <- E$LAST_FULL
POS <- c("QB", "RB", "WR", "TE")
agef <- function(ps, a) approx(E$agegrid[[ps]]$a, E$agegrid[[ps]]$f, xout = pmin(pmax(a, 19), 30))$y
ryl <- function(Y, ps) { Y2 <- pmax(Y, min(E$rep_y$season)); E$rep_y$rep_ppg[match(paste(Y2, ps), paste(E$rep_y$season, E$rep_y$pos))] }
# --- projections (out-of-class, LOCO) ---
A <- readRDS("oof_projections.rds") %>% filter(scheme == "LOCO")
MX <- readRDS("mixed_points_oof.rds") %>% select(pos, class, pick, lp3_mixed = m_faller)
post <- A %>% filter(board == "post") %>% select(pos, class, pick, gsis_id, age_at_draft, hit3, lp3, hit1, lp1, p1, p2, p3) %>% left_join(MX, by = c("pos", "class", "pick"))
pre <- A %>% filter(board == "pre", !is.na(gsis_id)) %>% distinct(pos, class, gsis_id, .keep_all = TRUE) %>% select(pos, class, gsis_id, pre_hit3 = hit3, pre_lp3 = lp3, pre_lp1 = lp1)
G <- E$gpo %>% filter(!is.na(pick)) %>% distinct(position, class, pick, .keep_all = TRUE) %>% transmute(pos = position, class, pick, name, q1 = p_top, q2 = p_top2, q3 = p_any)
# --- realized seasons per player (hk: drafted 2010-2022, seasons 1-5 to 2025) ---
H <- E$hk %>% mutate(ry = ryl(class, pos), len = ifelse(season >= 2021, 17, 16) / 17,
                     por = pmax(ifelse(g > 0, pts / g, 0) - ry, 0) * g)
pl <- H %>% distinct(pos, class, pick, player_id, age0, tier) %>%
  inner_join(post, by = c("pos", "class", "pick")) %>% left_join(pre, by = c("pos", "class", "gsis_id")) %>% left_join(G, by = c("pos", "class", "pick")) %>%
  mutate(age = coalesce(age0, age_at_draft, E$a_ref$a[match(pos, E$a_ref$pos)]))
cat("players with projections and NFL seasons:", nrow(pl), " missing pre-draft:", sum(is.na(pl$pre_lp3)), " missing live probs:", sum(is.na(pl$q1)), "\n")
pl <- pl %>% group_by(pos) %>% mutate(across(c(pre_hit3, pre_lp3, pre_lp1), ~ coalesce(.x, min(.x, na.rm = TRUE)))) %>% ungroup()
HK <- H %>% select(pos, class, pick, k, por) %>% inner_join(pl, by = c("pos", "class", "pick"))
PROJ <- c(hit3 = "Hit model, 3-year (mapped)", lp3 = "Points model, 3-year", lp3_mixed = "Points model, 3-year, mixed", lp1 = "Points model, rookie year",
          hit1 = "Hit model, rookie year (mapped)", pre_lp3 = "Pre-draft points model, 3-year")
# --- live tier method (dv_13 FABLE pick_factor val), out-of-class tier calibration ---
tier_val <- function(x, Y, P1, P12, P123) { cy <- E$tier_cal(E$hk %>% filter(class != Y)); K <- min(NK, LF - Y + 1)
  sapply(seq_len(nrow(x)), function(i) { ps <- x$pos[i]; cc <- cy %>% filter(pos == ps, k <= K); a0 <- E$a_ref$a[E$a_ref$pos == ps]
    d <- c(0, cumsum(sapply(2:NK, function(k) agef(ps, x$age[i] + k - 2) - agef(ps, a0 + k - 2))))[cc$k]
    P <- c(P1[i], P12[i] - P1[i], P123[i] - P12[i], 1 - P123[i]); len <- ifelse(Y + cc$k - 1 >= 2021, 17, 16) / 17
    sum(P[cc$tier] * v^cc$k * cc$G * len * E$stoploss(cc$mu + d, ryl(Y, ps), cc$sd)) }) }
out <- bind_rows(lapply(2016:2022, function(Y) { te <- pl %>% filter(class == Y); K <- min(NK, LF - Y + 1)
  te$realized <- sapply(seq_len(nrow(te)), function(i) { h <- HK %>% filter(pos == te$pos[i], class == Y, pick == te$pick[i], k <= K); sum(v^h$k * h$por) })
  te$tier_live <- tier_val(te, Y, te$q1, pmax(te$q2, te$q1), pmax(te$q3, te$q2, te$q1))
  te$tier_research <- tier_val(te, Y, te$p1, pmax(te$p2, te$p1), pmax(te$p3, te$p2, te$p1))
  for (s in names(PROJ)) { vs <- paste0("v_", s); te[[vs]] <- 0
    for (ps in POS) { i <- te$pos == ps; if (!any(i)) next
      for (k in 1:K) { tr <- HK %>% filter(pos == ps, class != Y, k == !!k)
        m <- glm(as.formula(sprintf("por ~ ns(%s, 3) + age", s)), family = quasipoisson, data = tr)
        te[[vs]][i] <- te[[vs]][i] + v^k * predict(m, te[i, ], type = "response") } } }
  te %>% mutate(K = K) }))
M <- c(tier_live = "Live tier method (dv_13)", tier_research = "Tier method, research hit model", setNames(PROJ, paste0("v_", names(PROJ))))
saveRDS(out, "value_backtest_players.rds")
# --- metrics ---
sp <- function(a, b) suppressWarnings(cor(a, b, method = "spearman"))
by_pos <- out %>% group_by(pos) %>% group_modify(function(d, k) bind_rows(lapply(names(M), function(s) data.frame(method = s, n = nrow(d),
  rho = sp(d[[s]], d$realized), ratio = sum(d$realized) / sum(d[[s]]), mae = mean(abs(d[[s]] - d$realized)))))) %>% ungroup()
# cross-position: within each class, Spearman over all drafted players and the realized total of each method's top 12 (a rookie draft)
cls <- out %>% group_by(class) %>% group_modify(function(d, k) bind_rows(lapply(names(M), function(s) { o <- order(-d[[s]])[1:12]
  data.frame(method = s, rho_all = sp(d[[s]], d$realized), top12_realized = sum(d$realized[o]), top12_pred = sum(d[[s]][o]),
             best12 = sum(sort(d$realized, decreasing = TRUE)[1:12])) }))) %>% ungroup()
cross <- cls %>% group_by(method) %>% summarise(top12_ratio = sum(top12_realized) / sum(top12_pred), rho_all = mean(rho_all), top12_realized = mean(top12_realized),
  best12 = mean(best12), classes_beat_live = NA_integer_, .groups = "drop")
lv <- cls %>% filter(method == "tier_live") %>% select(class, live_top12 = top12_realized, live_rho = rho_all)
cross$classes_beat_live <- sapply(cross$method, function(s) { z <- cls %>% filter(method == s) %>% left_join(lv, by = "class"); sum(z$rho_all > z$live_rho) })
cross$top12_classes_beat_live <- sapply(cross$method, function(s) { z <- cls %>% filter(method == s) %>% left_join(lv, by = "class"); sum(z$top12_realized > z$live_top12) })
# pooled bootstrap (classes then players) of Spearman difference vs live, all positions pooled within class
set.seed(2026)
bt <- bind_rows(lapply(setdiff(names(M), "tier_live"), function(s) { f <- function(d) mean(sapply(split(d, d$class), function(z) sp(z[[s]], z$realized) - sp(z$tier_live, z$realized)))
  b <- replicate(1000, { cl <- sample(2016:2022, replace = TRUE); d <- bind_rows(lapply(seq_along(cl), function(j) { z <- out[out$class == cl[j], ]; z[sample.int(nrow(z), replace = TRUE), ] %>% mutate(class = j) })); f(d) })
  data.frame(method = s, d_rho = f(out), lo = quantile(b, .025), hi = quantile(b, .975)) }))
cross <- cross %>% left_join(bt, by = "method") %>% mutate(label = M[method]) %>% arrange(desc(rho_all))
write.csv(by_pos, "value_backtest_by_pos.csv", row.names = FALSE); write.csv(cls, "value_backtest_by_class.csv", row.names = FALSE); write.csv(cross, "value_backtest_cross.csv", row.names = FALSE)
options(width = 220); print(as.data.frame(cross %>% mutate(across(where(is.double), ~ round(.x, 3)))), row.names = FALSE)
print(as.data.frame(by_pos %>% mutate(across(where(is.double), ~ round(.x, 3))) %>% select(pos, method, rho, ratio) %>% pivot_wider(names_from = pos, values_from = c(rho, ratio))), row.names = FALSE)

# --- charts ---
th <- theme_minimal(base_size = 12) + theme(plot.title = element_text(face = "bold"), panel.grid.minor = element_blank(), plot.background = element_rect(fill = "white", colour = NA))
lv_ <- rev(M[cross$method])
g <- ggplot(cross %>% mutate(label = factor(label, levels = lv_)), aes(rho_all, label)) + geom_point(size = 3, colour = "#0072B2") +
  geom_errorbarh(aes(xmin = rho_all + lo - d_rho, xmax = rho_all + hi - d_rho), height = 0, colour = "#0072B2") +
  geom_vline(xintercept = cross$rho_all[cross$method == "tier_live"], linetype = 2) +
  labs(x = "Spearman: predicted vs realized rookie value (all drafted players, all positions, within class; mean 2016-2022)", y = NULL,
       title = "Which projection ranks rookies by the value they actually produced?", subtitle = "Dashed line = live tier method. Bars = 95% bootstrap interval of the gap to it (classes, then players)") + th
ggsave("charts/03_value_rank_by_method.png", g, width = 12, height = 5, dpi = 130)
q <- by_pos %>% mutate(label = factor(M[method], levels = lv_))
g <- ggplot(q, aes(rho, label, colour = method == "tier_live")) + geom_point(size = 2.6) + facet_wrap(~pos, ncol = 4) + scale_colour_manual(values = c("#56B4E9", "#111111"), guide = "none") +
  labs(x = "Spearman: predicted vs realized value, 2016-2022 drafted players", y = NULL, title = "Value ranking by position", subtitle = "Black = live tier method") + th
ggsave("charts/04_value_rank_by_pos.png", g, width = 14, height = 5, dpi = 130)
q <- cls %>% filter(method %in% c("tier_live", "v_lp1", "v_lp3", "v_lp3_mixed", "v_hit3")) %>% mutate(label = M[method])
g <- ggplot(q, aes(class, top12_realized, colour = label)) + geom_line(linewidth = .9) + geom_point(size = 2) +
  geom_line(data = cls %>% filter(method == "tier_live"), aes(class, best12), colour = "grey60", linetype = 3, inherit.aes = FALSE) +
  scale_colour_manual(values = c("#111111", "#E69F00", "#0072B2", "#56B4E9", "#D55E00"), name = NULL) +
  labs(x = "Draft class", y = "Realized value of the 12 players taken (points over replacement, discounted)", title = "A 12-pick rookie draft by each method: what the picks actually produced",
       subtitle = "Top 12 players of the class by each method's value, all positions. Dotted grey = best possible 12 in hindsight") + th + theme(legend.position = "bottom")
ggsave("charts/05_top12_draft_by_class.png", g, width = 11, height = 6, dpi = 130)
q <- out %>% select(class, realized, all_of(c("tier_live", "v_lp1", "v_lp3"))) %>% pivot_longer(-c(class, realized)) %>% group_by(name) %>%
  mutate(bin = ntile(value, 10)) %>% group_by(name, bin) %>% summarise(pred = mean(value), act = mean(realized), .groups = "drop") %>% mutate(name = M[name])
g <- ggplot(q, aes(pred, act, colour = name)) + geom_abline(linetype = 2) + geom_line() + geom_point(size = 2.2) +
  scale_colour_manual(values = c("#111111", "#E69F00", "#0072B2"), name = NULL) +
  labs(x = "Predicted value (decile mean)", y = "Realized value (decile mean)", title = "Calibration: predicted vs realized rookie value", subtitle = "Deciles of each method's prediction, 2016-2022 drafted players.\nOn the dashed line = right on average") + th + theme(legend.position = "bottom")
ggsave("charts/06_value_calibration.png", g, width = 8, height = 6.5, dpi = 130)
