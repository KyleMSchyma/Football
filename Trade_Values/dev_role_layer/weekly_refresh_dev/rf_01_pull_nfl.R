# Weekly refresh step 1: pull 2026 NFL weekly player stats and the injury report from nflverse (nflreadr)
# writes ../Football2_Dynasty/nfl_weekly_2026.rds and ../Football2_Dynasty/nfl_injuries_2026.rds
suppressMessages(library(dplyr))
dyn <- Sys.getenv("DYN_DIR", "../Football2_Dynasty")   # FABLE: dev runs point this at Football2_Dynasty_dev
old_wk <- if (file.exists(file.path(dyn, "nfl_weekly_2026.rds"))) max(readRDS(file.path(dyn, "nfl_weekly_2026.rds"))$week) else 0
w <- as.data.frame(nflreadr::load_player_stats(2026, summary_level = "week"))
stopifnot(nrow(w) > 1000, max(w$week) >= old_wk)
saveRDS(w, file.path(dyn, "nfl_weekly_2026.rds"))
reg <- w %>% filter(season_type == "REG")
cat("NFL 2026 weekly rows:", nrow(w), " regular-season weeks:", paste(range(reg$week), collapse = "-"),
    " (was through week", old_wk, ")\n")
print(reg %>% count(week) %>% tail(3))
inj <- tryCatch(as.data.frame(nflreadr::load_injuries(2026)), error = function(e) { cat("injury report not available:", conditionMessage(e), "\n"); NULL })
if (!is.null(inj) && nrow(inj)) {
  saveRDS(inj, file.path(dyn, "nfl_injuries_2026.rds"))
  cat("injury report rows:", nrow(inj), " latest week:", max(inj$week), "\n")
}
ros <- tryCatch(as.data.frame(nflreadr::load_rosters_weekly(2026)), error = function(e) { cat("weekly rosters not available:", conditionMessage(e), "\n"); NULL })
if (!is.null(ros) && nrow(ros)) {
  saveRDS(ros, file.path(dyn, "nfl_rosters_weekly_2026.rds"))
  cat("weekly roster rows:", nrow(ros), " latest week:", max(ros$week), "\n")
}
