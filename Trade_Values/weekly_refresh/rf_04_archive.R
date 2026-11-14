# =============================================================================
# Weekly refresh: dated archive of the week's values and a biggest-movers file (FABLE build; runs after the gates pass)
#   ARCHIVE_DIR/YYYY-MM-DD_weekNN_redraft.csv   default-league redraft values (rank, status, credible PPG, games left, value)
#   ARCHIVE_DIR/YYYY-MM-DD_weekNN_dynasty.csv   default-league dynasty values
#   ARCHIVE_DIR/YYYY-MM-DD_weekNN_picks.csv     default-league 2027 rookie pick slots (value on the dynasty scale)
#   ARCHIVE_DIR/YYYY-MM-DD_weekNN_movers.csv    biggest rank / value changes vs the previous archive, both sheets
#   ARCHIVE_DIR/snapshots.json                  every snapshot in the folder, rebuilt from the files each run (the site's Dashboard reads it)
# Each row also carries player_id (site data/players.json; blank when a player has no id yet), snapshot_date, week, format,
# league (the site's league string), model_version (hash of the Football2_Dynasty value scripts) and data_version (nflverse week + file hash).
# One snapshot per day: if the run date already has one, it is KEPT, not overwritten (ARCHIVE_OVERWRITE=1 replaces it on purpose).
# refresh.sh copies the archive folder into the Football repo (Trade_Values/archive/).  env: DYN_DIR, ARCHIVE_DIR, SITE_DIR, ARCHIVE_DATE
# =============================================================================
suppressMessages(library(dplyr)); suppressMessages(library(jsonlite))
DYN <- Sys.getenv("DYN_DIR", "../Football2_Dynasty"); ARCH <- Sys.getenv("ARCHIVE_DIR", "archive"); dir.create(ARCH, showWarnings = FALSE, recursive = TRUE)
SITE <- Sys.getenv("SITE_DIR", "../ProspectActuary")
wk <- max(subset(readRDS(file.path(DYN, "nfl_weekly_2026.rds")), season_type == "REG")$week)
day <- Sys.getenv("ARCHIVE_DATE", format(Sys.Date(), "%Y-%m-%d")); tag <- sprintf("%s_week%02d", day, wk)

# ---------- snapshot list (built from the files on disk, so it never claims a snapshot that isn't there) ----------
write_index <- function() {
  tags <- sub("_dynasty\\.csv$", "", sort(list.files(ARCH, pattern = "^\\d{4}-\\d{2}-\\d{2}_week\\d+_dynasty\\.csv$")))
  one <- function(t) {
    f <- function(k) file.path(ARCH, paste0(t, "_", k, ".csv"))
    d <- read.csv(f("dynasty"), nrows = 1); mv <- file.exists(f("movers"))
    list(date = substr(t, 1, 10), week = as.integer(sub(".*_week", "", t)), tag = t,
         files = I(Filter(function(k) file.exists(f(k)), c("dynasty", "redraft", "picks", "movers"))),
         players_dynasty = length(readLines(f("dynasty"))) - 1L,
         players_redraft = if (file.exists(f("redraft"))) length(readLines(f("redraft"))) - 1L else NA,
         has_player_ids = "player_id" %in% names(d),
         league = if ("league" %in% names(d)) d$league[1] else NA, model_version = if ("model_version" %in% names(d)) d$model_version[1] else NA,
         data_version = if ("data_version" %in% names(d)) d$data_version[1] else NA,
         compared_with = if (mv) read.csv(f("movers"), nrows = 1)$compared_with[1] else NA)
  }
  write_json(list(note = "Weekly value snapshots of the default league, oldest first. Rebuilt from the archive files on every refresh.",
                  built = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), n = length(tags), snapshots = lapply(tags, one)),
             file.path(ARCH, "snapshots.json"), auto_unbox = TRUE, pretty = TRUE, na = "null", null = "null")
  cat("snapshot list:", length(tags), "snapshot(s)\n")
}

have <- list.files(ARCH, pattern = paste0("^", day, "_week\\d+_(dynasty|redraft|picks|movers)\\.csv$"))
if (length(have) && Sys.getenv("ARCHIVE_OVERWRITE") != "1") {
  cat("snapshot for", day, "already exists (", paste(have, collapse = ", "), "): kept, not overwritten. Set ARCHIVE_OVERWRITE=1 to replace it.\n")
  write_index(); quit(save = "no", status = 0)
}
if (length(have)) { cat("ARCHIVE_OVERWRITE=1: replacing", paste(have, collapse = ", "), "\n"); file.remove(file.path(ARCH, have)) }

# ---------- versions, league string, player ids ----------
h10 <- function(f) substr(unname(tools::md5sum(f)), 1, 10)
mfiles <- sort(list.files(DYN, pattern = "^(dv|rl)_.*\\.R$", full.names = TRUE))
tmp <- tempfile(); writeLines(paste(basename(mfiles), h10(mfiles)), tmp); model_version <- h10(tmp)
data_version <- sprintf("nflverse 2026 week %d (%s)", wk, h10(file.path(DYN, "nfl_weekly_2026.rds")))
grab <- function(file, nms) for (e in parse(file)) if (is.call(e) && identical(deparse(e[[1]]), "<-") && is.name(e[[2]]) &&
  as.character(e[[2]]) %in% nms) eval(e, globalenv())
POSITIONS <- c("QB", "RB", "WR", "TE")
grab(file.path(DYN, "dv_10_ros_value.R"), c("rep_lines", "MIN_G_REP", "LG_DEFAULT")); grab(file.path(DYN, "dv_13_league_presets.R"), c("stoploss", "league_values"))
# site format teams_ppr_tep_ptd_sf_rb_wr_te_flex_fdQB_fdRB_fdWR_fdTE; the boards use dv_10's default scoring (full PPR, no TE premium,
# 4-point passing TDs, no first-down bonus)
league <- with(LG_DEFAULT, paste(c(teams, 1, 0, 4, sf, rb, wr, te, flex, 0, 0, 0, 0), collapse = "_"))
pj <- file.path(SITE, "data", "players.json"); ids <- data.frame(name = character(), pos = character(), player_id = character())
if (file.exists(pj)) {
  pl <- fromJSON(pj)$players; tv <- pl$keys$tv; ok <- !is.na(tv)
  ids <- data.frame(name = sub("\\|.*", "", tv[ok]), pos = sub(".*\\|", "", tv[ok]), player_id = pl$id[ok]) %>% distinct(name, pos, .keep_all = TRUE)
} else cat("WARNING: no", pj, "- player_id left blank\n")
stamp <- function(d, fmt) d %>% left_join(ids, by = c("name", "pos")) %>% relocate(player_id) %>%
  mutate(player_id = coalesce(player_id, ""), snapshot_date = day, week = wk, format = fmt, league = league,
         model_version = model_version, data_version = data_version)

# ---------- this week's values ----------
rb <- read.csv(file.path(DYN, "dv_ros_2026_board.csv")); db <- read.csv(file.path(DYN, "dv_v4_board.csv"))
red <- rb %>% transmute(rank, name, pos, team, status = if ("status" %in% names(rb)) status else "", games_2026, ppg_2026, credible_ppg,
                        exp_games_left, value_100k)
dyn <- db %>% left_join(red %>% select(name, pos, status), by = c("name", "pos")) %>%
  transmute(rank, name, pos, team, age, status = coalesce(status, ""), credible_ppg, ppg_2027, S_2030, value_100k)
# 2027 pick slots in the default league: the page's math in R (dv_13 league_values), 100k = the top player
P <- readRDS(file.path(DYN, "dv_league_presets.rds")); L <- league_values(P, LG_DEFAULT); top <- max(L$players$dynasty, na.rm = TRUE)
picks <- L$slots %>% head(36) %>% transmute(pick = sprintf("%d.%02d", (slot - 1) %/% 12 + 1, (slot - 1) %% 12 + 1), value_100k = round(1e5 * val / top),
                                             multiplier = round(P$picks$f, 3))
redS <- stamp(red, "redraft"); dynS <- stamp(dyn, "dynasty")
picksS <- picks %>% mutate(snapshot_date = day, week = wk, format = "dynasty", league = league, model_version = model_version, data_version = data_version)
cat("player ids found:", sum(dynS$player_id != ""), "of", nrow(dynS), "dynasty rows,", sum(redS$player_id != ""), "of", nrow(redS), "redraft rows\n")
write.csv(redS, file.path(ARCH, paste0(tag, "_redraft.csv")), row.names = FALSE)
write.csv(dynS, file.path(ARCH, paste0(tag, "_dynasty.csv")), row.names = FALSE)
write.csv(picksS, file.path(ARCH, paste0(tag, "_picks.csv")), row.names = FALSE)

# ---------- movers vs the previous snapshot (matched on name + position, which older snapshots also have) ----------
prev <- setdiff(sort(list.files(ARCH, pattern = "_dynasty\\.csv$"), decreasing = TRUE), paste0(tag, "_dynasty.csv"))
mv <- function(new, old, sheet) full_join(old %>% select(name, pos, rank_before = rank, value_before = value_100k),
                                          new %>% select(name, pos, team, status, rank_now = rank, value_now = value_100k), by = c("name", "pos")) %>%
  mutate(sheet = sheet, value_change = coalesce(value_now, 0) - coalesce(value_before, 0), rank_change = rank_before - rank_now) %>%
  filter(pmax(coalesce(value_now, 0), coalesce(value_before, 0)) >= 5000) %>% arrange(desc(abs(value_change))) %>% head(25)
if (length(prev)) {
  od <- read.csv(file.path(ARCH, prev[1])); orr <- read.csv(file.path(ARCH, sub("_dynasty", "_redraft", prev[1])))
  M <- bind_rows(mv(dyn, od, "dynasty"), mv(red, orr, "redraft")) %>% mutate(compared_with = sub("_dynasty.csv", "", prev[1])) %>%
    left_join(ids, by = c("name", "pos")) %>% relocate(player_id) %>%
    mutate(player_id = coalesce(player_id, ""), snapshot_date = day, week = wk, league = league, model_version = model_version, data_version = data_version)
  write.csv(M, file.path(ARCH, paste0(tag, "_movers.csv")), row.names = FALSE)
  cat("biggest movers vs", sub("_dynasty.csv", "", prev[1]), ":\n"); print(as.data.frame(M %>% group_by(sheet) %>% slice_head(n = 5) %>% select(sheet, name, pos, rank_before, rank_now, value_change)), row.names = FALSE)
} else cat("first archived week: no movers file\n")
write_index()
cat("archived", tag, "to", normalizePath(ARCH), "\n")
