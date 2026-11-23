# Summaries for the prospect-prior backtest (reads out/pp_results.rds from pp_01).
suppressMessages({ library(dplyr); library(tidyr) })
OUT <- Sys.getenv("PP_OUT", "prospect_prior/out")
R <- readRDS(file.path(OUT, "pp_results.rds")); A <- R$A; B <- R$B
STARTABLE <- c(QB = 24, RB = 24, WR = 36, TE = 12)
grp <- function(e) cut(e, c(-1, 0, 2, 4, 99), labels = c("rookie (yr 1)", "yrs 2-3", "yrs 4-5", "yr 6+"))
base <- "pick_h3"
set.seed(2026)
# paired bootstrap over players: RMSE(variant) - RMSE(base)
boot_diff <- function(d, e_v, e_b, wt, B = 1000) { ids <- unique(d$player_id); idx <- split(seq_len(nrow(d)), d$player_id)
  r <- function(i) sqrt(weighted.mean(e_v[i]^2, wt[i])) - sqrt(weighted.mean(e_b[i]^2, wt[i]))
  bs <- replicate(B, { s <- unlist(idx[sample(names(idx), replace = TRUE)], use.names = FALSE); r(s) })
  c(diff = r(seq_len(nrow(d))), lo = unname(quantile(bs, .025)), hi = unname(quantile(bs, .975))) }

# ---- A: in-season ----
a <- A %>% filter(n_ros >= 3, !is.na(cppg)) %>% mutate(grp = grp(exp), err = ppg_ros - cppg)
ab <- a %>% filter(variant == base) %>% select(season, player_id, err_b = err)
a <- a %>% inner_join(ab, by = c("season", "player_id"))
TA <- bind_rows(
  a %>% group_by(variant, pos) %>% summarise(n = n(), rmse = sqrt(weighted.mean(err^2, n_ros)), rmse_base = sqrt(weighted.mean(err_b^2, n_ros)), .groups = "drop") %>% mutate(grp = "all"),
  a %>% group_by(variant, pos, grp = as.character(grp)) %>% summarise(n = n(), rmse = sqrt(weighted.mean(err^2, n_ros)), rmse_base = sqrt(weighted.mean(err_b^2, n_ros)), .groups = "drop"),
  a %>% group_by(variant, grp = as.character(grp)) %>% summarise(n = n(), rmse = sqrt(weighted.mean(err^2, n_ros)), rmse_base = sqrt(weighted.mean(err_b^2, n_ros)), .groups = "drop") %>% mutate(pos = "ALL"),
  a %>% group_by(variant) %>% summarise(n = n(), rmse = sqrt(weighted.mean(err^2, n_ros)), rmse_base = sqrt(weighted.mean(err_b^2, n_ros)), .groups = "drop") %>% mutate(pos = "ALL", grp = "all")) %>%
  mutate(pct = 100 * (rmse / rmse_base - 1))
# bootstrap CI for the headline cells
ciA <- bind_rows(lapply(unique(a$variant[a$variant != base]), function(v) bind_rows(lapply(c("all", "yrs 2-3", "rookie (yr 1)"), function(gg) {
  x <- a %>% filter(variant == v, gg == "all" | grp == gg); bd <- boot_diff(x, x$err, x$err_b, x$n_ros)
  tibble(variant = v, grp = gg, diff = bd[1], lo = bd[2], hi = bd[3], seasons_better = sum(tapply(x$err^2 * x$n_ros, x$season, sum) < tapply(x$err_b^2 * x$n_ros, x$season, sum))) }))))

# ---- B: season ahead ----
b <- B %>% filter(g_next >= 4, !is.na(pred)) %>% mutate(grp = grp(exp), err = ppg_next - pred)
bb <- b %>% filter(variant == base) %>% select(season, player_id, err_b = err)
b <- b %>% inner_join(bb, by = c("season", "player_id"))
TB <- bind_rows(
  b %>% group_by(variant, pos) %>% summarise(n = n(), rmse = sqrt(weighted.mean(err^2, g_next)), rmse_base = sqrt(weighted.mean(err_b^2, g_next)), .groups = "drop") %>% mutate(grp = "all"),
  b %>% group_by(variant, pos, grp = as.character(grp)) %>% summarise(n = n(), rmse = sqrt(weighted.mean(err^2, g_next)), rmse_base = sqrt(weighted.mean(err_b^2, g_next)), .groups = "drop"),
  b %>% group_by(variant, grp = as.character(grp)) %>% summarise(n = n(), rmse = sqrt(weighted.mean(err^2, g_next)), rmse_base = sqrt(weighted.mean(err_b^2, g_next)), .groups = "drop") %>% mutate(pos = "ALL"),
  b %>% group_by(variant) %>% summarise(n = n(), rmse = sqrt(weighted.mean(err^2, g_next)), rmse_base = sqrt(weighted.mean(err_b^2, g_next)), .groups = "drop") %>% mutate(pos = "ALL", grp = "all")) %>%
  mutate(pct = 100 * (rmse / rmse_base - 1))
ciB <- bind_rows(lapply(unique(b$variant[b$variant != base]), function(v) bind_rows(lapply(c("all", "yrs 2-3", "rookie (yr 1)"), function(gg) {
  x <- b %>% filter(variant == v, gg == "all" | grp == gg); bd <- boot_diff(x, x$err, x$err_b, x$g_next)
  tibble(variant = v, grp = gg, diff = bd[1], lo = bd[2], hi = bd[3], seasons_better = sum(tapply(x$err^2 * x$g_next, x$season, sum) < tapply(x$err_b^2 * x$g_next, x$season, sum))) }))))

# ---- C: rest-of-season value ranking ----
vb <- A %>% group_by(variant, season, pos) %>% mutate(rep = { s <- sort(cppg[n_cur >= 6], decreasing = TRUE); s[min(STARTABLE[pos[1]], length(s))] }) %>% ungroup() %>%
  mutate(value = (cppg - rep) * tg_left * cavail, actual = pts_ros - rep * n_ros, grp = grp(exp)) %>% filter(n_cur >= 3)
TC <- bind_rows(vb %>% group_by(variant, pos) %>% summarise(n = n(), spearman = cor(value, actual, method = "spearman"), .groups = "drop"),
                vb %>% filter(exp %in% 1:2) %>% group_by(variant, pos) %>% summarise(n = n(), spearman = cor(value, actual, method = "spearman"), .groups = "drop") %>% mutate(pos = paste(pos, "yrs 2-3")))

# ---- coverage + constants ----
cov <- A %>% filter(variant == "mixed_h3") %>% group_by(grp = grp(exp)) %>% summarise(rows = n(), with_prospect_prior = mean(used), .groups = "drop")
K <- R$K %>% mutate(across(c(k1, k2), ~ round(.x, 1)))

options(width = 200)
cat("\nCOVERAGE (share of in-season rows with a prospect-model prior):\n"); print(cov)
cat("\nCONSTANTS k1 (2026 games), k2 (history games), fit on all 2016-2025 seasons:\n"); print(K %>% pivot_wider(names_from = pos, values_from = c(k1, k2)))
cat("\nA. IN-SEASON weeks 10-18 PPG RMSE, ALL positions:\n"); print(TA %>% filter(pos == "ALL") %>% select(variant, grp, n, rmse, pct) %>% pivot_wider(names_from = grp, values_from = c(rmse, pct, n)) %>% mutate(across(where(is.double), ~ round(.x, 3))))
cat("\nA. bootstrap (RMSE diff vs pick_h3; negative = better):\n"); print(ciA %>% mutate(across(where(is.double), ~ round(.x, 3))))
cat("\nA. yrs 2-3 by position (% RMSE change):\n"); print(TA %>% filter(grp == "yrs 2-3", pos != "ALL") %>% select(variant, pos, pct) %>% pivot_wider(names_from = pos, values_from = pct) %>% mutate(across(where(is.double), ~ round(.x, 2))))
cat("\nB. NEXT-SEASON PPG RMSE (dv_11 aging model, rolling), ALL positions:\n"); print(TB %>% filter(pos == "ALL") %>% select(variant, grp, n, rmse, pct) %>% pivot_wider(names_from = grp, values_from = c(rmse, pct, n)) %>% mutate(across(where(is.double), ~ round(.x, 3))))
cat("\nB. bootstrap:\n"); print(ciB %>% mutate(across(where(is.double), ~ round(.x, 3))))
cat("\nB. yrs 2-3 by position (% RMSE change):\n"); print(TB %>% filter(grp == "yrs 2-3", pos != "ALL") %>% select(variant, pos, pct) %>% pivot_wider(names_from = pos, values_from = pct) %>% mutate(across(where(is.double), ~ round(.x, 2))))
cat("\nB. rookies (yr 1 -> yr 2) by position (% RMSE change):\n"); print(TB %>% filter(grp == "rookie (yr 1)", pos != "ALL") %>% select(variant, pos, pct) %>% pivot_wider(names_from = pos, values_from = pct) %>% mutate(across(where(is.double), ~ round(.x, 2))))
cat("\nC. rest-of-season value Spearman:\n"); print(TC %>% select(-n) %>% pivot_wider(names_from = pos, values_from = spearman) %>% mutate(across(where(is.double), ~ round(.x, 3))))
write.csv(TA, file.path(OUT, "pp_A_inseason_rmse.csv"), row.names = FALSE); write.csv(ciA, file.path(OUT, "pp_A_bootstrap.csv"), row.names = FALSE)
write.csv(TB, file.path(OUT, "pp_B_nextseason_rmse.csv"), row.names = FALSE); write.csv(ciB, file.path(OUT, "pp_B_bootstrap.csv"), row.names = FALSE)
write.csv(TC, file.path(OUT, "pp_C_value_spearman.csv"), row.names = FALSE); write.csv(R$K, file.path(OUT, "pp_constants.csv"), row.names = FALSE)
write.csv(cov, file.path(OUT, "pp_coverage.csv"), row.names = FALSE)
