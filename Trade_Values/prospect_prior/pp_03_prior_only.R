# How good is each prior ON ITS OWN? Prior PPG vs actual weeks 10-18 PPG, rows that have a prospect-model prior.
suppressMessages({ library(dplyr); library(tidyr) })
OUT <- Sys.getenv("PP_OUT", "prospect_prior/out")
A <- readRDS(file.path(OUT, "pp_results.rds"))$A %>% filter(grepl("_h3$", variant), n_ros >= 3)
ids <- A %>% filter(variant == "mixed_h3", used) %>% distinct(season, player_id)
x <- A %>% semi_join(ids, by = c("season", "player_id")) %>% mutate(grp = cut(exp, c(-1, 0, 2, 4, 99), labels = c("yr 1", "yrs 2-3", "yrs 4-5", "yr 6+")))
r <- x %>% group_by(variant, pos, grp) %>% summarise(n = n(), rmse_prior = sqrt(weighted.mean((ppg_ros - prior)^2, n_ros)),
  cor_prior = cov.wt(cbind(prior, ppg_ros), n_ros, cor = TRUE)$cor[1, 2], .groups = "drop")
r0 <- x %>% group_by(variant, grp) %>% summarise(n = n(), rmse_prior = sqrt(weighted.mean((ppg_ros - prior)^2, n_ros)),
  cor_prior = cov.wt(cbind(prior, ppg_ros), n_ros, cor = TRUE)$cor[1, 2], .groups = "drop") %>% mutate(pos = "ALL")
R <- bind_rows(r, r0)
# share of the credible PPG weight that sits on the prior (dv_10 weights, pick_h3 constants)
K <- readRDS(file.path(OUT, "pp_results.rds"))$K %>% filter(variant == "pick_h3")
wgt <- x %>% filter(variant == "pick_h3") %>% left_join(K, by = "pos") %>% mutate(w_prior = k1 / (n_cur + k1) * k2 / (g_h + k2)) %>%
  group_by(grp) %>% summarise(mean_prior_weight = mean(w_prior))
options(width = 200)
cat("prior-only correlation with weeks 10-18 PPG (players with a prospect prior):\n")
print(R %>% select(variant, pos, grp, cor_prior) %>% pivot_wider(names_from = variant, values_from = cor_prior) %>% arrange(pos, grp) %>% mutate(across(where(is.double), ~ round(.x, 3))), n = 30)
cat("\naverage weight on the prior inside credible PPG at week 9:\n"); print(wgt)
write.csv(R, file.path(OUT, "pp_prior_only.csv"), row.names = FALSE); write.csv(wgt, file.path(OUT, "pp_prior_weight.csv"), row.names = FALSE)
