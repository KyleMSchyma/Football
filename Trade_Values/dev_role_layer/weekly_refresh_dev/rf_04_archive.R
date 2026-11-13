# =============================================================================
# Weekly refresh: dated archive of the week's values and a biggest-movers file (FABLE build; runs after the gates pass)
#   ARCHIVE_DIR/YYYY-MM-DD_weekNN_redraft.csv   default-league redraft values (rank, status, credible PPG, games left, value)
#   ARCHIVE_DIR/YYYY-MM-DD_weekNN_dynasty.csv   default-league dynasty values
#   ARCHIVE_DIR/YYYY-MM-DD_weekNN_picks.csv     default-league 2027 rookie pick slots (value on the dynasty scale)
#   ARCHIVE_DIR/YYYY-MM-DD_weekNN_movers.csv    biggest rank / value changes vs the previous archive, both sheets
# refresh.sh copies the archive folder into the Football repo (Trade_Values/archive/).  env: DYN_DIR, ARCHIVE_DIR
# =============================================================================
suppressMessages(library(dplyr))
DYN <- Sys.getenv("DYN_DIR", "../Football2_Dynasty"); ARCH <- Sys.getenv("ARCHIVE_DIR", "archive"); dir.create(ARCH, showWarnings = FALSE, recursive = TRUE)
wk <- max(subset(readRDS(file.path(DYN, "nfl_weekly_2026.rds")), season_type == "REG")$week)
tag <- sprintf("%s_week%02d", Sys.getenv("ARCHIVE_DATE", format(Sys.Date(), "%Y-%m-%d")), wk)
rb <- read.csv(file.path(DYN, "dv_ros_2026_board.csv")); db <- read.csv(file.path(DYN, "dv_v4_board.csv"))
red <- rb %>% transmute(rank, name, pos, team, status = if ("status" %in% names(rb)) status else "", games_2026, ppg_2026, credible_ppg,
                        exp_games_left, value_100k)
dyn <- db %>% left_join(red %>% select(name, pos, status), by = c("name", "pos")) %>%
  transmute(rank, name, pos, team, age, status = coalesce(status, ""), credible_ppg, ppg_2027, S_2030, value_100k)
# 2027 pick slots in the default league: the page's math in R (dv_13 league_values), 100k = the top player
grab <- function(file, nms) for (e in parse(file)) if (is.call(e) && identical(deparse(e[[1]]), "<-") && is.name(e[[2]]) &&
  as.character(e[[2]]) %in% nms) eval(e, globalenv())
POSITIONS <- c("QB", "RB", "WR", "TE")
grab(file.path(DYN, "dv_10_ros_value.R"), c("rep_lines", "MIN_G_REP", "LG_DEFAULT")); grab(file.path(DYN, "dv_13_league_presets.R"), c("stoploss", "league_values"))
P <- readRDS(file.path(DYN, "dv_league_presets.rds")); L <- league_values(P, LG_DEFAULT); top <- max(L$players$dynasty, na.rm = TRUE)
picks <- L$slots %>% head(36) %>% transmute(pick = sprintf("%d.%02d", (slot - 1) %/% 12 + 1, (slot - 1) %% 12 + 1), value_100k = round(1e5 * val / top),
                                             multiplier = round(P$picks$f, 3))
write.csv(red, file.path(ARCH, paste0(tag, "_redraft.csv")), row.names = FALSE)
write.csv(dyn, file.path(ARCH, paste0(tag, "_dynasty.csv")), row.names = FALSE)
write.csv(picks, file.path(ARCH, paste0(tag, "_picks.csv")), row.names = FALSE)
# movers vs the previous archive
prev <- setdiff(sort(list.files(ARCH, pattern = "_dynasty\\.csv$"), decreasing = TRUE), paste0(tag, "_dynasty.csv"))
mv <- function(new, old, sheet) full_join(old %>% select(name, pos, rank_before = rank, value_before = value_100k),
                                          new %>% select(name, pos, team, status, rank_now = rank, value_now = value_100k), by = c("name", "pos")) %>%
  mutate(sheet = sheet, value_change = coalesce(value_now, 0) - coalesce(value_before, 0), rank_change = rank_before - rank_now) %>%
  filter(pmax(coalesce(value_now, 0), coalesce(value_before, 0)) >= 5000) %>% arrange(desc(abs(value_change))) %>% head(25)
if (length(prev)) {
  od <- read.csv(file.path(ARCH, prev[1])); orr <- read.csv(file.path(ARCH, sub("_dynasty", "_redraft", prev[1])))
  M <- bind_rows(mv(dyn, od, "dynasty"), mv(red, orr, "redraft")) %>% mutate(compared_with = sub("_dynasty.csv", "", prev[1]))
  write.csv(M, file.path(ARCH, paste0(tag, "_movers.csv")), row.names = FALSE)
  cat("biggest movers vs", sub("_dynasty.csv", "", prev[1]), ":\n"); print(as.data.frame(M %>% group_by(sheet) %>% slice_head(n = 5) %>% select(sheet, name, pos, rank_before, rank_now, value_change)), row.names = FALSE)
} else cat("first archived week: no movers file\n")
cat("archived", tag, "to", normalizePath(ARCH), "\n")
