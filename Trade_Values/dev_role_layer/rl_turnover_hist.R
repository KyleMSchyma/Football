# Justify the weekly top-50 turnover gate: how many players leave the redraft top 50 from one week to the next
# (live redraft method, default lines), weeks 4-17 of 2021-2025. Writes rl_turnover_hist.csv.
ROLE_AVAIL <- FALSE; SIG_H <- FALSE; LENFIX <- FALSE; QB_DEPTH <- FALSE; NO_WRITE <- TRUE
sink("NUL"); source("dv_10_ros_value.R"); sink()
top50 <- function(y, k) { d <- apply_k(snapshot(y, k)); d <- d %>% left_join(team_n(y, k + 1, 18) %>% rename(tl2 = tg), by = "team") %>% mutate(tg_left = coalesce(tl2, 0L))
  value_board(d) %>% arrange(desc(value)) %>% head(50) %>% pull(player_id) }
R <- bind_rows(lapply(2021:2025, function(y) { tops <- lapply(4:17, function(k) top50(y, k))
  tibble(season = y, week = 5:17, out_of_top50 = sapply(2:14, function(i) length(setdiff(tops[[i - 1]], tops[[i]])))) }))
write.csv(R, "rl_turnover_hist.csv", row.names = FALSE)
cat("week-to-week players leaving the redraft top 50, 2021-2025 weeks 5-17:\n"); print(summary(R$out_of_top50)); print(quantile(R$out_of_top50, c(.9, .95, .99, 1)))
print(R %>% group_by(season) %>% summarise(max = max(out_of_top50), mean = round(mean(out_of_top50), 1)))
