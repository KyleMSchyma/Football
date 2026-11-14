# =============================================================================
# Dynasty Model, step 1: player-season table, startable flags, landmark data
#
# Output
#   dv_seasons.rds    one row per player-season 2006-2026 (QB/RB/WR/TE, drafted + undrafted)
#   dv_landmarks.rds  one row per player at each season he played ("landmark"), with
#                     features known that season and what happened over the next H seasons
#   dv_person_period.rds  hazard GLM rows (one per landmark x future season at risk)
# =============================================================================
source("dv_common.R")
cat("== Dynasty step 1: data build ==\n")

w  <- readRDS(file.path(SHARED, "nfl_weekly_raw.rds"))
w26 <- if (file.exists("nfl_weekly_2026.rds")) readRDS("nfl_weekly_2026.rds") else {
  x <- nflreadr::load_player_stats(CUR, summary_level = "week"); saveRDS(x, "nfl_weekly_2026.rds"); x }
w <- bind_rows(w, w26[, intersect(names(w26), names(w))]) %>% filter(season_type == "REG")
w$position[w$position == "FB"] <- "RB"
w <- w %>% filter(position %in% POSITIONS)
cat("weekly rows:", nrow(w), " seasons", paste(range(w$season), collapse = "-"),
    " 2026 weeks:", max(w$week[w$season == CUR]), "\n")

# team games so far (bye weeks differ) -> used to pro-rate the season in progress
team_g <- w %>% distinct(season, team, week) %>% count(season, team, name = "team_games")

# ---- season totals ----
s <- w %>% group_by(player_id, season) %>%
  summarise(name = last(player_display_name), pos = names(which.max(table(position))), team = last(team),
            pts = sum(fantasy_points_ppr, na.rm = TRUE), games = n_distinct(week),
            pass_att = sum(attempts, na.rm = TRUE), carries = sum(carries, na.rm = TRUE),
            targets = sum(targets, na.rm = TRUE), .groups = "drop") %>%
  left_join(team_g, by = c("season", "team")) %>%
  mutate(sched = ifelse(season <= 2020, 16, 17),
         sched_so_far = ifelse(season == CUR, team_games, sched),
         pts17 = pts * 17 / sched_so_far,                 # full 17-game pace (pro-rates 2026 and 16-game years)
         games_frac = pmin(games / sched_so_far, 1),
         ppg = pts / games,
         opp_pg = (ifelse(pos == "QB", pass_att, 0) + carries + targets) / games)

# rank and replacement line within season x position (on 17-game pace)
s <- s %>% group_by(season, pos) %>% arrange(desc(pts17), .by_group = TRUE) %>%
  mutate(rank = row_number(), line = STARTABLE[pos[1]],
         rep_pts = pts17[pmin(line[1], n())],
         par = pts17 - rep_pts, startable = as.integer(rank <= line)) %>% ungroup()
cat("replacement lines (17-game points), recent seasons:\n")
print(s %>% filter(season >= 2022) %>% distinct(season, pos, rep_pts) %>%
        pivot_wider(names_from = pos, values_from = rep_pts) %>% arrange(season) %>% mutate(across(-season, round)))

# ---- player info: age, draft, rookie season ----
p <- readRDS(file.path(SHARED, "players_raw.rds")) %>%
  transmute(player_id = gsis_id, birth_date = as.Date(birth_date), draft_round, draft_pick,
            rookie_season, roster_status = status, latest_team, last_season)
first_seen <- s %>% group_by(player_id) %>% summarise(first_season = min(season), main_pos = names(which.max(table(pos))))
info <- first_seen %>% left_join(p, by = "player_id") %>%
  mutate(rookie_season = ifelse(is.na(rookie_season) | rookie_season > first_season, first_season, rookie_season),
         draft = draft_bucket(draft_round))
cat("players:", nrow(info), " undrafted:", sum(info$draft == "UDFA"), " missing birth date:", sum(is.na(info$birth_date)), "\n")

# ---- full player x season grid: a season with no games counts as below the line ----
grid <- info %>% select(player_id, rookie_season) %>%
  mutate(season = purrr::map(rookie_season, ~ max(.x, 2006):CUR)) %>% unnest(season) %>% select(-rookie_season)
sg <- grid %>% left_join(s, by = c("player_id", "season")) %>%
  mutate(played = !is.na(pts), startable = coalesce(startable, 0L), par = coalesce(par, NA_real_)) %>%
  arrange(player_id, season)
# fill missing par for non-played seasons with the season's most negative value (it is never used as PAR+)
sg <- sg %>% mutate(par_pos = ifelse(played, pmax(par, 0), 0))

# ---- landmarks: every season a player appeared in ----
age_at <- function(bd, season) as.numeric(as.Date(paste0(season, "-09-01")) - bd) / 365.25
lm <- sg %>% group_by(player_id) %>%
  mutate(par_prev = lag(ifelse(played, par, NA)), startable_prev = lag(startable),
         n_startable = cumsum(startable),
         # best season in the last three (this one included): keeps a proven player's track record in view
         par_best3 = pmax(ifelse(played, par, -300), lag(ifelse(played, par, -300), default = -300),
                          lag(ifelse(played, par, -300), 2, default = -300)),
         # per-game pace above replacement: separates "hurt but good" from "healthy but bad"
         par_rate = ifelse(played, ppg * 17 - rep_pts, NA)) %>% ungroup() %>%
  filter(played) %>%
  left_join(info %>% select(player_id, birth_date, draft, draft_round, draft_pick, rookie_season, roster_status, latest_team, last_season),
            by = "player_id") %>%
  mutate(exp = season - rookie_season, age = age_at(birth_date, season))
# impute missing ages from position x experience medians (flagged)
lm <- lm %>% group_by(pos, exp) %>% mutate(age_missing = is.na(age), age = ifelse(is.na(age), median(age, na.rm = TRUE), age)) %>%
  ungroup() %>% mutate(age = ifelse(is.na(age), 22 + exp, age),
                       par_prev = ifelse(is.na(par_prev), min(par, na.rm = TRUE), par_prev),   # did not play previous season
                       startable_prev = coalesce(startable_prev, 0L), pos = factor(pos, POSITIONS))
lm$par_prev <- pmax(lm$par_prev, -300); lm$par <- pmax(lm$par, -300)   # cap the far left tail (deep backups)
lm$par_best3 <- pmax(lm$par_best3, -300); lm$par_rate <- pmin(pmax(lm$par_rate, -300), 400)

# ---- outcome over the next H seasons: death = 2 straight seasons below the line ----
B <- sg %>% select(player_id, season, startable, par_pos)
# Rookie free pass: the rookie season never counts toward the two-straight rule
# (8% of players "dead" after rookie + year 2 later became startable, so year 2-3 breakouts stay alive).
fut <- lm %>% select(player_id, season, startable, rookie_season) %>% rename(lm_season = season, st0 = startable) %>%
  crossing(t = 1:18) %>% mutate(season = lm_season + t) %>% filter(season <= LAST_FULL) %>%
  left_join(B, by = c("player_id", "season")) %>%
  mutate(startable = coalesce(startable, 0L), par_pos = coalesce(par_pos, 0)) %>%   # past the grid = retired = below
  arrange(player_id, lm_season, t) %>% group_by(player_id, lm_season) %>%
  mutate(below = 1L - startable,
         below_prev = lag(below, default = ifelse(lm_season[1] == rookie_season[1], 0L, 1L - st0[1])),
         dead_now = as.integer(below == 1 & below_prev == 1), died = cumsum(cumsum(dead_now)) ) %>%
  ungroup()
# died counts how many seasons since death; keep seasons up to and including the death season
pp <- fut %>% filter(died <= 1) %>% mutate(event = dead_now) %>% rename(fut_season = season, fut_startable = startable)
surv <- pp %>% group_by(player_id, lm_season) %>%
  summarise(time = max(t), status = max(event), .groups = "drop")
lm <- lm %>% left_join(surv, by = c("player_id", "season" = "lm_season"))
cat("landmarks:", nrow(lm), " with follow-up:", sum(!is.na(lm$time)), " deaths:", sum(lm$status, na.rm = TRUE), "\n")

pp <- pp %>% left_join(lm %>% select(player_id, season, all_of(setdiff(FEATS, "pos")), pos),
                       by = c("player_id", "lm_season" = "season")) %>%
  mutate(age_t = age + t, y = par_pos, alive = 1L - event)
cat("person-period rows:", nrow(pp), " hazard events:", sum(pp$event), "\n")

saveRDS(sg, "dv_seasons.rds"); saveRDS(lm, "dv_landmarks.rds"); saveRDS(pp, "dv_person_period.rds")
write.csv(s %>% filter(season >= 2024) %>% select(season, name, pos, team, games, pts, pts17, rank, startable, par) %>%
            arrange(season, pos, rank), "dv_recent_finishes.csv", row.names = FALSE)

# quick sanity checks
cat("\nstartable seasons by position (2006-2025):\n"); print(table(s$pos[s$season <= LAST_FULL], s$startable[s$season <= LAST_FULL]))
cat("\nexample career: Austin Ekeler (UDFA)\n")
print(lm %>% filter(name == "Austin Ekeler") %>% select(season, pos, exp, age, draft, rank, startable, par, time, status) %>% mutate(across(where(is.numeric), ~ round(.x, 1))))
