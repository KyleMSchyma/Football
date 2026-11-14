# =============================================================================
# Role layer, step 1 (A1): one tidy player-week table for QB / RB / WR / TE, 2012-2026, regular season
#
#   cache_role/depth_week.rds  season, week, team, player_id, dc_pos, depth_rank
#        2012-2024: nflverse weekly depth charts (depth_team, offense formation)
#        2025-2026: ESPN snapshots (pos_rank, "3WR 1TE" group); for each week the last snapshot taken before
#                   that week's first kickoff. Week 99 of 2026 = the latest snapshot ("now").
#   cache_role/role_week.rds   one row per player on a team's weekly roster (any status) or with a stat line:
#        played (stat line or offense snaps > 0), pass attempts, QB start (15+ attempts), roster status,
#        injury report status, depth rank, offense snap share, and the A1 class:
#          played | missed_injured | missed_healthy | missed_other (suspended / exempt) | off_roster
#        missed_injured = did not play and (reserve list, or Out / Doubtful / Questionable on the report,
#                         or an injury listed on the report)
#        missed_healthy = did not play, on the active / inactive roster, not injured: depth chart or benching
#        off_roster     = practice squad, cut, retired, free agent lists
# Usage: ./run.sh rl_01_role_build.R rl_01_log.txt   (after rl_00_pull_role_data.R)
# =============================================================================
suppressMessages({ library(dplyr); library(tidyr) })
SHARED <- "../Football2/cache"
POS <- c("QB", "RB", "WR", "TE")
rdc <- function(f) { x <- readRDS(f); x$season <- as.integer(x$season); if ("week" %in% names(x)) x$week <- as.integer(x$week); x }
sch <- rdc("cache_role/schedules.rds") %>% filter(game_type == "REG")
tw <- bind_rows(sch %>% transmute(season, week, team = home_team, gameday, gametime, result),
                sch %>% transmute(season, week, team = away_team, gameday, gametime, result)) %>%
  mutate(team = recode(team, OAK = "LV", SD = "LAC", STL = "LA"))
played_tw <- tw %>% filter(!is.na(result)) %>% distinct(season, week, team)       # team-weeks with a finished game

# ---------- depth charts ----------
dc <- rdc("cache_role/depth_charts.rds")
old <- dc %>% filter(season <= 2024, formation == "Offense", game_type == "REG" | is.na(game_type)) %>%
  mutate(dc_pos = case_when(depth_position == "QB" ~ "QB", depth_position %in% c("RB", "HB", "H-B", "TE/HB") ~ "RB",
                            depth_position %in% c("WR", "LWR", "RWR", "SWR", "FL", "SE") ~ "WR", depth_position == "TE" ~ "TE"),
         depth_rank = suppressWarnings(as.integer(depth_team))) %>%
  filter(!is.na(dc_pos), !is.na(depth_rank), !is.na(gsis_id)) %>%
  group_by(season, week = as.integer(week), team = club_code, player_id = gsis_id, dc_pos) %>% summarise(depth_rank = min(depth_rank), .groups = "drop")
new <- dc %>% filter(season >= 2025, pos_abb %in% POS, grepl("WR", pos_grp)) %>%
  transmute(season, dt = as.POSIXct(sub("Z$", "", sub("T", " ", dt)), tz = "UTC"), team, player_id = gsis_id, dc_pos = pos_abb,
            depth_rank = as.integer(pos_rank)) %>% filter(!is.na(player_id))
kick <- tw %>% filter(season >= 2025) %>% group_by(season, week) %>%
  summarise(k = min(as.POSIXct(paste(gameday, coalesce(gametime, "13:00")), tz = "America/New_York")), .groups = "drop")
snaps <- new %>% distinct(season, dt)
pick_snap <- bind_rows(lapply(seq_len(nrow(kick)), function(i) {
  s <- snaps %>% filter(dt < kick$k[i], dt > kick$k[i] - 86400 * 21)      # last snapshot before the week's first kickoff (within 3 weeks)
  if (!nrow(s)) return(NULL); tibble(season = kick$season[i], week = kick$week[i], dt = max(s$dt)) }))
pick_snap <- bind_rows(pick_snap, tibble(season = 2026L, week = 99L, dt = max(snaps$dt[snaps$season == 2026])))
new_w <- new %>% inner_join(pick_snap, by = c("season", "dt"), relationship = "many-to-many") %>%
  group_by(season, week, team, player_id, dc_pos) %>% summarise(depth_rank = min(depth_rank), .groups = "drop")
depth <- bind_rows(old, new_w) %>% group_by(season, week, player_id) %>% slice_min(depth_rank, n = 1, with_ties = FALSE) %>% ungroup()
saveRDS(depth, "cache_role/depth_week.rds")
cat("depth chart: player-weeks by season (QB/RB/WR/TE):\n"); print(depth %>% count(season, dc_pos) %>% pivot_wider(names_from = dc_pos, values_from = n), n = 20)
cat("latest 2026 snapshot:", format(max(snaps$dt[snaps$season == 2026])), " weeks matched to a snapshot (2025-26):",
    nrow(pick_snap), "\n")

# ---------- snap counts (pfr id -> gsis id) ----------
ros <- rdc("cache_role/rosters_weekly.rds") %>% filter(game_type == "REG" | is.na(game_type))
pl <- readRDS(file.path(SHARED, "players_raw.rds"))
idmap <- bind_rows(ros %>% filter(!is.na(pfr_id), !is.na(gsis_id)) %>% distinct(pfr_id, gsis_id),
                   if ("pfr_id" %in% names(pl)) pl %>% filter(!is.na(pfr_id), !is.na(gsis_id)) %>% distinct(pfr_id, gsis_id)) %>%
  distinct(pfr_id, .keep_all = TRUE)
snp <- rdc("cache_role/snap_counts.rds") %>% filter(game_type == "REG", position %in% c(POS, "FB")) %>%
  left_join(idmap, by = c("pfr_player_id" = "pfr_id")) %>%
  transmute(season, week = as.integer(week), player_id = gsis_id, off_snaps = offense_snaps, off_pct = offense_pct)
cat("\nsnap-count rows mapped to a gsis id:", round(mean(!is.na(snp$player_id)), 3), "\n")
snp <- snp %>% filter(!is.na(player_id)) %>% group_by(season, week, player_id) %>% summarise(off_snaps = sum(off_snaps), off_pct = max(off_pct), .groups = "drop")

# ---------- stat lines ----------
w <- readRDS(file.path(SHARED, "nfl_weekly_raw.rds"))
w26 <- readRDS("nfl_weekly_2026.rds")
w <- bind_rows(w, w26[, intersect(names(w26), names(w))]) %>% filter(season_type == "REG", season >= 2012)
w$position[w$position == "FB"] <- "RB"
st <- w %>% filter(position %in% POS) %>% transmute(season, week, player_id, st_team = team, st_pos = position, att = coalesce(attempts, 0), stat = 1L)

# ---------- injuries ----------
inj <- rdc("cache_role/injuries.rds") %>% filter(game_type == "REG" | is.na(game_type)) %>%
  transmute(season, week = as.integer(week), player_id = gsis_id, report_status, inj_listed = !is.na(report_primary_injury) | !is.na(report_status)) %>%
  filter(!is.na(player_id)) %>%
  mutate(sev = match(report_status, c("Out", "Doubtful", "Questionable", "Probable", "Note"))) %>%
  group_by(season, week, player_id) %>% arrange(sev, .by_group = TRUE) %>% slice(1) %>% ungroup() %>% select(-sev)

# ---------- roster status ----------
rs <- ros %>% filter(position %in% c(POS, "FB"), !is.na(gsis_id)) %>%
  transmute(season, week = as.integer(week), player_id = gsis_id, r_team = team, r_pos = ifelse(position == "FB", "RB", position),
            status, abbr = status_description_abbr) %>%
  mutate(pri = match(status, c("ACT", "INA", "RES", "PUP", "SUS", "EXE", "NWT", "E14", "E01", "DEV", "CUT", "RET", "UFA", "RFA", "TRC", "TRD", "TRT", "RSN", "RSR")),
         pri = coalesce(pri, 99L)) %>%
  group_by(season, week, player_id) %>% slice_min(pri, n = 1, with_ties = FALSE) %>% ungroup() %>% select(-pri)

# ---------- player-week table ----------
rw <- full_join(rs, st, by = c("season", "week", "player_id")) %>%
  mutate(team = coalesce(st_team, r_team), pos = coalesce(st_pos, r_pos)) %>%
  semi_join(played_tw, by = c("season", "week", "team")) %>%                       # weeks the player's team played
  left_join(snp, by = c("season", "week", "player_id")) %>%
  left_join(inj, by = c("season", "week", "player_id")) %>%
  left_join(depth %>% select(season, week, player_id, depth_rank), by = c("season", "week", "player_id")) %>%
  mutate(stat = coalesce(stat, 0L), att = coalesce(att, 0), off_snaps = coalesce(off_snaps, 0),
         played = as.integer(stat == 1 | off_snaps > 0), qb_start = as.integer(pos == "QB" & att >= 15),
         reserve = as.integer(status %in% c("RES", "PUP") | grepl("^R", coalesce(abbr, "")) & status != "RET"),
         inj_flag = as.integer(reserve == 1 | report_status %in% c("Out", "Doubtful", "Questionable") | coalesce(inj_listed, FALSE)),
         class = case_when(played == 1 ~ "played",
                           inj_flag == 1 & !status %in% c("CUT", "DEV", "RET", "UFA", "RFA") ~ "missed_injured",
                           status %in% c("ACT", "INA") ~ "missed_healthy",
                           status %in% c("SUS", "EXE", "NWT", "E14", "E01", "RSN", "RSR") ~ "missed_other",
                           TRUE ~ "off_roster"))
saveRDS(rw, "cache_role/role_week.rds")
saveRDS(rs, "cache_role/roster_status_week.rds")      # every roster week, including weeks not played yet (status "now")
saveRDS(inj, "cache_role/injury_week.rds")
saveRDS(tw, "cache_role/team_weeks.rds")              # full schedule (played or not)

cat("\nA1: player-weeks 2016-2026 by class and position (regular season, weeks the team played):\n")
a1 <- rw %>% filter(season >= 2016) %>% count(pos, class) %>% pivot_wider(names_from = class, values_from = n, values_fill = 0)
print(a1)
write.csv(a1, "rl_a1_class_counts_by_pos.csv", row.names = FALSE)
cat("\nA1 by season (all four positions):\n")
a1s <- rw %>% count(season, class) %>% pivot_wider(names_from = class, values_from = n, values_fill = 0)
print(a1s, n = 20); write.csv(a1s, "rl_a1_class_counts_by_season.csv", row.names = FALSE)
cat("\ncoverage by season: share of player-weeks with a depth rank, with a snap count, on the injury report, roster status INA\n")
cov <- rw %>% group_by(season) %>% summarise(depth = mean(!is.na(depth_rank)), depth_if_played = mean(!is.na(depth_rank[played == 1])),
  snaps_if_played = mean(off_snaps[played == 1] > 0), on_report = mean(!is.na(report_status)), ina = mean(status == "INA", na.rm = TRUE), .groups = "drop")
print(cov %>% mutate(across(-season, ~ round(.x, 3))), n = 20); write.csv(cov, "rl_coverage_by_season.csv", row.names = FALSE)
cat("\nmissed-healthy share of all misses by position and depth rank (2016-2025):\n")
print(rw %>% filter(season %in% 2016:2025, class %in% c("missed_injured", "missed_healthy")) %>%
        mutate(dr = ifelse(is.na(depth_rank), "none", pmin(depth_rank, 3))) %>% group_by(pos, dr) %>%
        summarise(n = n(), healthy_share = round(mean(class == "missed_healthy"), 3), .groups = "drop") %>%
        pivot_wider(names_from = dr, values_from = c(n, healthy_share)))
cat("\n2026 latest week, examples:\n")
nm <- pl %>% transmute(player_id = gsis_id, name = display_name)
print(rw %>% filter(season == 2026) %>% group_by(player_id) %>% filter(week == max(week)) %>% ungroup() %>% left_join(nm, by = "player_id") %>%
  filter(name %in% c("Justin Fields", "Tua Tagovailoa", "Marcus Mariota", "Jameis Winston", "Davante Adams", "Mike Evans", "DeVonta Smith", "Jalen Hurts",
                     "Carson Wentz", "Anthony Richardson", "Deshaun Watson")) %>%
  select(name, team, week, status, abbr, report_status, depth_rank, played, class) %>% as.data.frame())
