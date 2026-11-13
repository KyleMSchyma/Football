# =============================================================================
# B1 / B3 calibration tables: ./run.sh rl_calib.R logs/calib.txt <tag1> <tag2> ...
# Dynasty backtest (week-9 snapshots 2016-2020, players with 3+ games, default league): predicted vs actual five-season
# discounted points over replacement by decile of predicted value, position, age band, years in league and season ahead;
# and (B3) predicted vs actual "still playing t seasons later" and projected vs actual PPG by age band and position.
# Writes rl_calib_<table>.csv (all tags stacked).
# =============================================================================
suppressMessages(library(dplyr)); options(width = 220)
tags <- commandArgs(trailingOnly = TRUE); v <- 1 / 1.15
band_age <- function(a) cut(a, c(0, 23, 26, 29, 32, 35, 99), right = FALSE, labels = c("<23", "23-25", "26-28", "29-31", "32-34", "35+"))
band_exp <- function(e) cut(e, c(-1, 0, 1, 2, 5, 99), labels = c("rookie", "year 2", "year 3", "years 4-6", "years 7+"))
tab <- function(d, g) d %>% group_by(group = as.character({{ g }})) %>%
  summarise(n = n(), pred = sum(pred), actual = sum(actual), .groups = "drop") %>%
  mutate(ratio = pred / actual, excess = pred - actual, share_of_excess = excess / sum(excess))
OUT <- list(); OUT3 <- list()
for (t in tags) {
  BT <- readRDS(paste0("exp/dv11_", t, ".rds"))$BT %>% mutate(dec = ntile(pred, 10))
  T <- bind_rows(tab(BT, dec) %>% mutate(table = "decile of predicted value") %>% arrange(as.integer(group)),
                 tab(BT, pos) %>% mutate(table = "position"), tab(BT, band_age(age)) %>% mutate(table = "age band"),
                 tab(BT, band_exp(exp)) %>% mutate(table = "years in league"),
                 tab(BT, paste(pos, band_age(age))) %>% mutate(table = "position x age band"))
  # by season ahead (t = 0 rest of the snapshot season, 1..5): discounted predicted vs actual
  sa <- bind_rows(tibble(group = "t0 rest of season", pred = sum(BT$pred0), actual = sum(BT$act0)),
                  tibble(group = paste0("t", 1:5), pred = colSums(BT$VS) * v^(1:5), actual = colSums(BT$AV) * v^(1:5))) %>%
    mutate(n = nrow(BT), ratio = pred / actual, excess = pred - actual, share_of_excess = excess / sum(excess), table = "season ahead")
  OUT[[t]] <- bind_rows(T, sa) %>% mutate(tag = t, .before = 1)
  # B3: still playing and PPG by age band x position, horizons 1, 3, 5
  OUT3[[t]] <- bind_rows(lapply(c(1, 3, 5), function(h) BT %>% mutate(band = band_age(age), S = S[, h], alive = as.integer(AG[, h] >= 1),
                                                                   P = P[, h], AP = AP[, h], g = AG[, h]) %>%
    group_by(pos, band) %>% summarise(n = n(), pred_still_playing = mean(S), actual_still_playing = mean(alive),
                                      n_ppg = sum(g >= 4), proj_ppg = mean(P[g >= 4]), actual_ppg = mean(AP[g >= 4]), .groups = "drop") %>% mutate(h = h))) %>%
    mutate(tag = t, .before = 1)
}
C <- bind_rows(OUT) %>% mutate(across(c(pred, actual, excess), round), across(c(ratio, share_of_excess), ~ round(.x, 3)))
for (tb in unique(C$table)) { cat("\n==", tb, "==\n"); print(as.data.frame(C %>% filter(table == tb) %>% select(tag, group, n, pred, actual, ratio, share_of_excess)), row.names = FALSE) }
write.csv(C, "rl_calib_tables.csv", row.names = FALSE)
C3 <- bind_rows(OUT3) %>% mutate(across(c(pred_still_playing, actual_still_playing, proj_ppg, actual_ppg), ~ round(.x, 3)))
cat("\n== B3: still playing h seasons later and PPG (players with 4+ games that season), by position and age band ==\n")
print(as.data.frame(C3 %>% filter(band %in% c("29-31", "32-34", "35+"))), row.names = FALSE)
write.csv(C3, "rl_calib_age.csv", row.names = FALSE)
