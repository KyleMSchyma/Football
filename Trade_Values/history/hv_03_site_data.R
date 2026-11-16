# =============================================================================
# Site files for the Value History page (prospect-actuary /value-history/), from the point-in-time snapshots.
#   Rscript hv_03_site_data.R SNAP_DIR SCORED_DIR SITE_DIR       (run from the dynasty model folder)
# Writes SITE_DIR/data/history/
#   index.json    snapshot list (season, week, Tuesday date), method notes, track-record summary, top-24 hits and misses
#   values.json   one series per player: [snapshot index, dynasty value (100k), dynasty rank, redraft value (100k), redraft rank]
#                 (redraft blank once a season is over). Players are keyed by nflverse gsis id; the site id from
#                 data/players.json is added when the player has one.
# Values are the reference league the weekly archive uses (12 teams, superflex, 2 RB / 3 WR / 1 TE, no flex, full PPR).
# =============================================================================
suppressMessages({ library(dplyr); library(jsonlite) })
a <- commandArgs(trailingOnly = TRUE); SNAP <- a[1]; SCORED <- a[2]; SITE <- a[3]
OUTD <- file.path(SITE, "data", "history"); dir.create(OUTD, showWarnings = FALSE, recursive = TRUE)
files <- sort(list.files(SNAP, pattern = "^hv_\\d{4}_w\\d{2}\\.rds$", full.names = TRUE))
S <- lapply(files, readRDS)
snaps <- bind_rows(lapply(seq_along(S), function(i) with(S[[i]]$meta, tibble(i = i - 1L, season, week, date, n_dynasty, n_redraft, model_version))))
cat("snapshots:", nrow(snaps), " model versions:", paste(unique(snaps$model_version), collapse = ", "), "\n")

ids <- tryCatch(fromJSON(file.path(SITE, "data", "players.json"))$players %>% select(id, gsis) %>% filter(!is.na(gsis)) %>% distinct(gsis, .keep_all = TRUE),
                error = function(e) tibble(id = character(), gsis = character()))
long <- bind_rows(lapply(seq_along(S), function(i) {
  d <- S[[i]]$dynasty %>% transmute(player_id, name, pos, team, dv = value_100k, dr = rank)
  r <- S[[i]]$redraft %>% transmute(player_id, rv = value_100k, rr = rank)
  d %>% full_join(r, by = "player_id") %>% mutate(i = i - 1L) }))
pl <- long %>% arrange(i) %>% group_by(player_id) %>%
  summarise(name = last(na.omit(name)), pos = last(na.omit(pos)), team = last(na.omit(team)), best = min(dr, na.rm = TRUE),
            s = list(unname(lapply(seq_len(n()), function(k) c(i[k], dv[k], dr[k], rv[k], rr[k])))), .groups = "drop") %>%
  left_join(ids, by = c("player_id" = "gsis")) %>% arrange(best)
write_json(list(note = "Point-in-time trade values: s = [snapshot index, dynasty value (100k), dynasty rank, redraft value (100k), redraft rank]; null = not on that board.",
                players = lapply(seq_len(nrow(pl)), function(k) list(g = pl$player_id[k], id = pl$id[k], n = pl$name[k], p = pl$pos[k], t = pl$team[k], s = pl$s[[k]]))),
           file.path(OUTD, "values.json"), auto_unbox = TRUE, na = "null", null = "null", digits = NA)

# ---------- track record ----------
R <- read.csv(file.path(SCORED, "hv_track_record_by_snapshot.csv")); SM <- read.csv(file.path(SCORED, "hv_track_record_summary.csv"))
P <- readRDS(file.path(SCORED, "hv_track_record_players.rds"))
by_season <- SM %>% filter(pos == "ALL", grepl("^\\d{4}$", seasons)) %>% transmute(kind, season = as.integer(seasons), snapshots, spearman, spearman_naive, top_hit, top_hit_naive, pred_over_actual)
overall <- SM %>% filter(seasons %in% c("all complete", "so far (incomplete)"))
# hits and misses: week-9 snapshot of each scored season, the top 24 by value, with the rank they actually finished
hm <- P %>% filter(week == 9) %>% group_by(format, season) %>% mutate(actual_rank = rank(-actual, ties.method = "min")) %>%
  filter(rank <= 24) %>% ungroup() %>% transmute(format, season, complete, rank, name, pos, actual_rank, player_id) %>% arrange(format, season, rank)
write_json(list(built = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                league = "12 teams, superflex, 2 RB / 3 WR / 1 TE, no flex, full PPR (the weekly archive's reference league)",
                snapshots = snaps %>% select(i, season, week, date, n_dynasty, n_redraft),
                overall = overall, by_season = by_season, hits = hm,
                weekly = R %>% filter(pos == "ALL") %>% select(kind, season, week, spearman, spearman_naive, complete)),
           file.path(OUTD, "index.json"), auto_unbox = TRUE, na = "null", null = "null", digits = NA, dataframe = "rows")
cat("wrote", file.path(OUTD, "values.json"), round(file.size(file.path(OUTD, "values.json")) / 1e6, 2), "MB,", nrow(pl), "players\n")
