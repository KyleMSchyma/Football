# Kyle 2026-11-21: top-24 rookies of every class (2010-2022) under three post-draft (NOT mixed) value methods, default scoring:
#   current = dv_13 tier method on the post-draft model's draft-only odds (p_*_draft, out-of-class)
#   ppg1    = PPG model, rookie-year PPG;  ppg3 = PPG model, seasons 1-3 PPG   (pp_06, out-of-class)
# Same reference league, discount, stop-loss and season lengths for all three. Realized = discounted points over replacement,
# seasons 1-5 (to 2025). Replacement lines: the draft season's week-9 line (2016+); 2010-2015 classes use the 2016 lines.
# Grade = percentile of the value among all drafted rookies 2010-2022 (all positions), on the site's grade scale.
suppressMessages({ library(dplyr); library(tidyr); library(splines); library(jsonlite); library(ggplot2) })
E <- readRDS("/tmp/claude-0/tvrun/Football2_Dynasty/exp/rookie_env.rds"); v <- E$v; NK <- E$NK; LF <- E$LAST_FULL
POS4 <- c("QB", "RB", "WR", "TE")
agef <- function(ps, a) approx(E$agegrid[[ps]]$a, E$agegrid[[ps]]$f, xout = pmin(pmax(a, 19), 30))$y
ryl <- function(Y, ps) { Y2 <- pmax(Y, min(E$rep_y$season)); E$rep_y$rep_ppg[match(paste(Y2, ps), paste(E$rep_y$season, E$rep_y$pos))] }
P1 <- readRDS("ppg_oof.rds")
G <- E$gpo %>% filter(!is.na(pick)) %>% distinct(position, class, pick, .keep_all = TRUE) %>%
  transmute(pos = position, class, pick, name, college, q1 = p_top_draft, q2 = p_top2_draft, q3 = p_any_draft, post_grade = post_grade_draft, nfl_outcome)
HK <- E$hk %>% select(pos, class, pick, k, g, pts, g17)
ages <- E$hk %>% distinct(pos, class, pick, age0)
pl <- P1 %>% rename(act_ppg1 = ppg1, act_ppg3 = ppg3, proj_ppg1 = ppgA, proj_ppg3 = ppgB) %>% inner_join(G, by = c("pos", "class", "pick")) %>% left_join(ages, by = c("pos", "class", "pick")) %>%
  mutate(age = coalesce(age0, age))
H2 <- HK %>% inner_join(P1 %>% select(pos, class, pick, age, ppgA, ppgB), by = c("pos", "class", "pick"))
res <- bind_rows(lapply(2010:2022, function(Y) { te <- pl %>% filter(class == Y); K <- min(NK, LF - Y + 1)
  te$realized <- sapply(seq_len(nrow(te)), function(i) { h <- HK %>% filter(pos == te$pos[i], class == Y, pick == te$pick[i], k <= K)
    sum(v^h$k * pmax(ifelse(h$g > 0, h$pts / h$g, 0) - ryl(Y, te$pos[i]), 0) * h$g) })
  cy <- E$tier_cal(E$hk %>% filter(class != Y))
  te$current <- sapply(seq_len(nrow(te)), function(i) { ps <- te$pos[i]; cc <- cy %>% filter(pos == ps, k <= K); a0 <- E$a_ref$a[E$a_ref$pos == ps]
    d <- c(0, cumsum(sapply(2:NK, function(k) agef(ps, te$age[i] + k - 2) - agef(ps, a0 + k - 2))))[cc$k]
    q1 <- te$q1[i]; q2 <- max(te$q2[i], q1); q3 <- max(te$q3[i], q2); P <- c(q1, q2 - q1, q3 - q2, 1 - q3)
    sum(P[cc$tier] * v^cc$k * cc$G * ifelse(Y + cc$k - 1 >= 2021, 17, 16) / 17 * E$stoploss(cc$mu + d, ryl(Y, ps), cc$sd)) })
  for (m in c("ppgA", "ppgB")) { out <- rep(0, nrow(te))
    for (ps in POS4) { ii <- which(te$pos == ps); if (!length(ii)) next
      for (k in 1:K) { tr <- H2 %>% filter(pos == ps, class != Y, k == !!k) %>% mutate(x = .data[[m]]); pk_ <- tr %>% filter(g > 0) %>% mutate(ppg = pts / g)
        fm <- lm(ppg ~ x + age, data = pk_, weights = g); sdk <- sqrt(sum(pk_$g * resid(fm)^2) / sum(pk_$g))
        gm <- glm(I(g17 / 17) ~ ns(x, 3), family = quasibinomial, data = tr); nd <- data.frame(x = te[[sub("ppgA", "proj_ppg1", sub("ppgB", "proj_ppg3", m))]][ii], age = te$age[ii])
        out[ii] <- out[ii] + v^k * ifelse(Y + k - 1 >= 2021, 17, 16) / 17 * 17 * predict(gm, nd, type = "response") * E$stoploss(predict(fm, nd), ryl(Y, ps), sdk) } }
    te[[c(ppgA = "ppg1", ppgB = "ppg3")[[m]]]] <- out }
  te %>% mutate(K = K) }))
CUTS <- c(0, .10, .25, .35, .45, .55, .65, .75, .85, .90, .95, 1.0001); GR <- c("F", "D", "C-", "C", "C+", "B-", "B", "B+", "A-", "A", "A+")
gr <- function(x) as.character(cut(rank(x, ties.method = "average") / length(x), CUTS, labels = GR, right = FALSE))
M <- c(current = "Current (tier odds)", ppg1 = "Rookie-year PPG", ppg3 = "3-year PPG")
for (m in c(names(M), "realized")) res[[paste0("g_", m)]] <- gr(res[[m]])
res <- res %>% group_by(class) %>% mutate(across(c(current, ppg1, ppg3, realized), ~ rank(-.x, ties.method = "first"), .names = "r_{.col}")) %>% ungroup()
saveRDS(res, "top24_all_players.rds")
write.csv(res %>% transmute(class, pos, name, college, pick, post_grade, current = round(current, 1), r_current, g_current, ppg1 = round(ppg1, 1), r_ppg1, g_ppg1,
  ppg3 = round(ppg3, 1), r_ppg3, g_ppg3, proj_ppg1 = round(proj_ppg1, 1), proj_ppg3 = round(proj_ppg3, 1), realized = round(realized, 1), r_realized, g_realized, seasons = K, nfl_outcome) %>%
  arrange(class, r_current), "top24_boards.csv", row.names = FALSE)
# ---- summary per class: realized value of each method's top 24, hits (actual top 24 of the class), overlap ----
S <- bind_rows(lapply(names(M), function(m) res %>% group_by(class) %>% summarise(method = m,
  top24_realized = sum(realized[get(paste0("r_", m)) <= 24]), best24 = sum(realized[r_realized <= 24]),
  hits = sum(get(paste0("r_", m)) <= 24 & r_realized <= 24),
  rho_top24 = cor(get(m)[get(paste0("r_", m)) <= 24], realized[get(paste0("r_", m)) <= 24], method = "spearman"),
  rho_all = cor(get(m), realized, method = "spearman"), .groups = "drop")))
ov <- res %>% group_by(class) %>% summarise(cur_ppg1 = sum(r_current <= 24 & r_ppg1 <= 24), cur_ppg3 = sum(r_current <= 24 & r_ppg3 <= 24), ppg1_ppg3 = sum(r_ppg1 <= 24 & r_ppg3 <= 24))
T <- S %>% group_by(method) %>% summarise(pct_of_best = sum(top24_realized) / sum(best24), top24_realized = mean(top24_realized), hits = mean(hits),
  rho_top24 = mean(rho_top24), rho_all = mean(rho_all), .groups = "drop")
wins <- S %>% select(class, method, top24_realized) %>% pivot_wider(names_from = method, values_from = top24_realized) %>%
  summarise(ppg1_beats_current = sum(ppg1 > current), ppg3_beats_current = sum(ppg3 > current), classes = n())
write.csv(S, "top24_summary_by_class.csv", row.names = FALSE); write.csv(T, "top24_summary.csv", row.names = FALSE); write.csv(ov, "top24_overlap.csv", row.names = FALSE)
options(width = 200); print(as.data.frame(T), digits = 3); print(wins); print(as.data.frame(ov)); print(colMeans(ov[, -1]))
# ---- charts ----
th <- theme_minimal(base_size = 12) + theme(plot.title = element_text(face = "bold"), panel.grid.minor = element_blank(), plot.background = element_rect(fill = "white", colour = NA))
q <- S %>% mutate(method = M[method])
g <- ggplot(q, aes(class, top24_realized, colour = method)) + geom_line(linewidth = .9) + geom_point(size = 2) +
  geom_line(data = S %>% filter(method == "current"), aes(class, best24), colour = "grey60", linetype = 3, inherit.aes = FALSE) +
  scale_colour_manual(values = c("#111111", "#0072B2", "#E69F00"), name = NULL) + scale_x_continuous(breaks = 2010:2022) +
  labs(x = "Draft class", y = "Realized value of the top 24 (discounted pts over replacement)", title = "Top 24 rookies by each post-draft method: what they actually produced",
       subtitle = "Draft-only post-draft model (not mixed), out-of-class. Dotted grey = best possible 24 in hindsight. 2021-22 classes have 4-5 seasons, earlier 5") + th + theme(legend.position = "bottom")
ggsave("charts/11_top24_realized_by_class.png", g, width = 12, height = 6, dpi = 130)
q <- S %>% mutate(method = M[method])
g <- ggplot(q, aes(class, hits, fill = method)) + geom_col(position = "dodge", width = .8) + scale_fill_manual(values = c("#111111", "#0072B2", "#E69F00"), name = NULL) +
  scale_x_continuous(breaks = 2010:2022) + labs(x = "Draft class", y = "Players also in the class's actual top 24", title = "How many of each method's top 24 really finished top 24 in their class?",
  subtitle = "Actual top 24 by realized dynasty value over the first 5 seasons") + th + theme(legend.position = "bottom")
ggsave("charts/12_top24_hits_by_class.png", g, width = 12, height = 5.5, dpi = 130)
