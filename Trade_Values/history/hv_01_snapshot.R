# =============================================================================
# One point-in-time snapshot: the values the weekly refresh would have published on the Tuesday after week W of season S.
#   Rscript hv_01_snapshot.R S W [OUT_DIR] [mode]
# Run from the dynasty model folder (Football2_Dynasty: dv_*.R, rl_*.R, cache_role/, ../Football2/cache/).
# mode "asof" (default): every data file cut to the as-of date (hv_common.R).
# mode "live": no cut and the live "now" role path; only used to prove the copied scripts reproduce the live board.
# Writes OUT_DIR/hv_<S>_w<WW>.rds = list(meta, redraft, dynasty). Nothing in the model folder is written.
# =============================================================================
a <- commandArgs(trailingOnly = TRUE)
HV_S <- as.integer(a[1]); HV_W <- as.integer(a[2]); OUT <- if (length(a) >= 3) a[3] else "history_out"
MODE <- if (length(a) >= 4) a[4] else "asof"
HERE <- normalizePath(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])))
source(file.path(HERE, "hv_common.R"))
HV_LEN <- hv_len(HV_S); HV_NOW <- MODE == "live"; HV_SKIP_BT <- TRUE
HV_GEN <- file.path(tempdir(), "hv_gen"); MODEL_VERSION <- hv_generate(".", HV_GEN)
NO_WRITE <- TRUE
if (MODE == "asof") readRDS <- function(file, ...) hv_cut(base::readRDS(file, ...), HV_S, HV_W)
t0 <- Sys.time()
sink(file.path(tempdir(), "model_log.txt"))                 # the model scripts print a lot; keep it out of the run log
ok <- tryCatch({ source(file.path(HV_GEN, "dv_11_dynasty_v4.R")); TRUE }, finally = sink())
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

st <- function(b) status_tag(if ("cat" %in% names(b)) b$cat else rep(NA, nrow(b)), b$pos,
                             if ("depth_rank" %in% names(b)) b$depth_rank else NA, if ("snap_season" %in% names(b)) b$snap_season else NA)
# redraft (rest of season S), same columns and 100k scaling as dv_ros_2026_board.csv; empty once the season is over
red <- b26 %>% transmute(player_id, name, pos, team, age, status = st(b26), games = n_cur, ppg = round(ppg_cur, 2),
                         credible_ppg = round(cppg, 2), rep_ppg = round(rep_ppg, 2), team_games_left = tg_left,
                         exp_games_left = round(exp_games, 2), value_100k = round(100000 * pmax(value, 0) / max(max(value), 1e-9)),
                         value = round(value, 2))
if (max(b26$value) <= 0) red <- red[0, ]
red <- red %>% arrange(desc(value)) %>% mutate(rank = row_number()) %>% group_by(pos) %>% mutate(rank_pos = row_number()) %>% ungroup()
# dynasty (rest of S + seasons S+1..S+5), same as dv_v4_board.csv
dyn <- d26 %>% transmute(player_id, name, pos, team, age = round(age, 1), exp, draft_pick, games = n_cur, ppg = round(ppg_cur, 2),
                         credible_ppg = round(cppg, 2), ppg_next = round(pr$ppg[, 2], 2), S_y4 = round(pr$S[, 5], 3),
                         value_ros = round(pr$seasons[, 1], 2), value = pr$value) %>%
  left_join(red %>% select(player_id, status), by = "player_id") %>% mutate(status = coalesce(status, st(d26))) %>%
  arrange(desc(value)) %>% mutate(rank = row_number(), value_100k = round(100000 * value / max(value)), value = round(value, 2)) %>%
  group_by(pos) %>% mutate(rank_pos = row_number()) %>% ungroup()
sched <- base::readRDS("cache_role/schedules.rds")
last_game <- max(as.Date(sched$gameday[sched$season == HV_S & sched$week == HV_W & sched$game_type == "REG"]))
tuesday <- last_game + ((2 - as.integer(format(last_game, "%u"))) %% 7)   # the Tuesday after the week's last game
if (tuesday == last_game) tuesday <- tuesday + 7
meta <- list(season = HV_S, week = HV_W, date = format(tuesday), mode = MODE, model_version = MODEL_VERSION,
             credibility_k = K, min_games_replacement = MIN_G_REP, bt_years = range(BT_YEARS), season_games = HV_LEN,
             rep_ppg = b26 %>% distinct(pos, rep_ppg), n_redraft = nrow(red), n_dynasty = nrow(dyn),
             run_seconds = round(as.numeric(difftime(Sys.time(), t0, units = "secs"))))
saveRDS(list(meta = meta, redraft = red, dynasty = dyn), file.path(OUT, sprintf("hv_%d_w%02d.rds", HV_S, HV_W)))
cat(sprintf("%d week %2d (%s): %d redraft, %d dynasty rows, %ss  top: %s\n", HV_S, HV_W, meta$date, nrow(red), nrow(dyn),
            meta$run_seconds, paste(head(dyn$name, 3), collapse = ", ")))
