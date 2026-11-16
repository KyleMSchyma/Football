# Plain CSV copies of the snapshots, one file per season (both formats), for the Football repo.
#   Rscript hv_04_export_csv.R SNAP_DIR OUT_DIR
suppressMessages(library(dplyr)); options(scipen = 99)
a <- commandArgs(trailingOnly = TRUE); dir.create(a[2], showWarnings = FALSE, recursive = TRUE)
files <- sort(list.files(a[1], pattern = "^hv_\\d{4}_w\\d{2}\\.rds$", full.names = TRUE))
all <- bind_rows(lapply(files, function(f) { s <- readRDS(f); m <- s$meta
  bind_rows(s$redraft %>% mutate(format = "redraft"), s$dynasty %>% mutate(format = "dynasty")) %>%
    mutate(season = m$season, week = m$week, date = m$date, model_version = m$model_version) }))
cols <- c("season", "week", "date", "format", "rank", "rank_pos", "player_id", "name", "pos", "team", "age", "status", "games", "ppg",
          "credible_ppg", "rep_ppg", "team_games_left", "exp_games_left", "ppg_next", "S_y4", "value_ros", "value", "value_100k", "model_version")
for (s in sort(unique(all$season))) write.csv(all %>% filter(season == s) %>% select(any_of(cols)) %>% arrange(week, format, rank),
                                             file.path(a[2], sprintf("values_%d.csv", s)), row.names = FALSE, na = "")
cat("wrote", length(unique(all$season)), "season files,", nrow(all), "rows\n")
