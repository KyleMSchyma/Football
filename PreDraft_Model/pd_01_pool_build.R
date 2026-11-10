# =============================================================================
# Pre-Draft Model -- Phase 1: build the prospect pool (every draft class, every
# position) from college data only
#
# Why a pool and not just drafted players: Kyle wants to grade a college class
# before the draft. Before the draft we don't know who will be picked, so the
# model is trained on the whole pool of draft-eligible college players and the
# outcome is "did he become a QB8 / WR12 / ... in his first three NFL seasons".
# A player who never reaches the NFL is a miss. The model therefore learns
# P(tier hit | college profile), which folds in the chance he is drafted at all.
#
#   PART 1  Raw data: cached cfbd stats 2004-2025 (WR work), a new 2026-season
#           pull (season in progress, scaled to 12 games), recruiting, and the
#           drafted tables + outcomes from the four existing models.
#   PART 2  Link NFL players to college careers: drafted players via the
#           existing matches, undrafted free agents by name + school.
#   PART 3  Assign each college player to a draft class and position, apply
#           eligibility (3 years out of high school) and a light production
#           filter, and build college-only features (no combine, no draft info).
#   PART 4  Checks.
# Outputs: pd_pool.rds (one row per player per class), pd_pool_summary.csv
# =============================================================================
source("pd_common.R")
suppressMessages(library(cfbfastR))
dir.create("cache", showWarnings = FALSE)
cache_or_pull <- function(file, fn) {
  path <- file.path("cache", file)
  if (file.exists(path)) { cat("cached:", path, "\n"); return(readRDS(path)) }
  cat("pulling:", path, "\n"); out <- fn(); saveRDS(out, path); out
}

# =============================================================================
# PART 1: raw data
# =============================================================================
cfb_hist <- readRDS(file.path(SHARED, "cfbd_stats_2004_2025.rds"))
cfb_2026 <- cache_or_pull("cfbd_stats_2026.rds", function()
  as.data.frame(cfbd_stats_season_player(year = 2026, season_type = "regular")) %>% mutate(college_year = 2026L))
team_2026 <- cache_or_pull("cfbd_team_stats_2026.rds", function()
  as.data.frame(cfbd_stats_season_team(year = 2026, season_type = "regular")))
cat("2026 rows:", nrow(cfb_2026), " team-stat columns with 'games':", paste(grep("games", names(team_2026), value = TRUE), collapse = ","), "\n")

stat_cols <- c("passing_completions", "passing_att", "passing_yds", "passing_td", "passing_int",
               "rushing_car", "rushing_yds", "rushing_td", "receiving_rec", "receiving_yds", "receiving_td")
cfb <- bind_rows(cfb_hist %>% select(college_year, team, conference, athlete_id, player, position, all_of(stat_cols)),
                 cfb_2026 %>% select(college_year, team, conference, athlete_id, player, position, all_of(stat_cols))) %>%
  mutate(athlete_id = as.character(athlete_id), across(all_of(stat_cols), ~ coalesce(as.numeric(.x), 0)))

# 2026 is about 10 games in: scale counting stats to a 12-game season (shares are unaffected)
g26 <- team_2026 %>% transmute(team, games = as.numeric(games)) %>% distinct(team, .keep_all = TRUE)
cfb <- cfb %>% left_join(g26 %>% mutate(college_year = 2026L), by = c("team", "college_year")) %>%
  mutate(scale = ifelse(college_year == 2026, 12 / pmax(coalesce(games, 10), 1), 1),
         across(all_of(stat_cols), ~ .x * scale)) %>% select(-games)
cat("2026 scale factor (12 / games played) quantiles:\n"); print(quantile(cfb$scale[cfb$college_year == 2026], c(0, .1, .5, .9, 1)))

team_tot <- cfb %>% group_by(college_year, team) %>%
  summarize(t_att = sum(passing_att), t_car = sum(rushing_car), t_rush_yds = sum(rushing_yds),
            t_rec = sum(receiving_rec), t_rec_yds = sum(receiving_yds), t_rec_td = sum(receiving_td),
            t_td = sum(rushing_td) + sum(receiving_td), .groups = "drop")

# one row per athlete-season (a mid-season school change is rare; keep the bigger row's team)
seasons <- cfb %>% filter(passing_att + rushing_car + receiving_rec > 0) %>%
  group_by(athlete_id, college_year) %>% arrange(desc(passing_att + rushing_car + receiving_rec), .by_group = TRUE) %>%
  summarize(team = first(team), conference = first(conference), player = first(player), cfb_pos = first(position),
            across(all_of(stat_cols), sum), .groups = "drop") %>%
  left_join(team_tot, by = c("college_year", "team"))

# --- level-of-competition translation (FCS -> FBS), estimated from transfers -------------
# cfbd has full FCS box scores only from 2022 on (before that, only FCS players' games
# against FBS teams), so the training classes contain almost no full FCS seasons and no
# model can learn an FCS discount from them; conference / tier predictors were tested in
# Phase 5 and did not help. Instead, like a minor-league translation in baseball, compare
# how players' share / efficiency stats change when they transfer FCS -> FBS against the
# change for FBS -> FBS transfers (the control for "new team, one year older"). The ratio
# of the two medians is the factor applied to full-coverage FCS seasons (2022+).
FCS_CONF <- c("Big Sky", "SWAC", "Southland", "MVFC", "Southern", "MEAC", "CAA", "OVC", "Coastal Athletic", "NEC", "Patriot",
              "Pioneer", "UAC", "Ivy", "Big South", "Big South-OVC", "OVC-Big South", "FCS Independents", "Atlantic Sun", "Great West")
FBS_CONF <- c("ACC", "SEC", "Big Ten", "Big 12", "Pac-12", "Pac-10", "American Athletic", "Mountain West",
              "Conference USA", "Mid-American", "Sun Belt", "FBS Independents", "Big East")
lvl_of <- function(conf, yr) ifelse(conf %in% FBS_CONF | (conf == "Western Athletic" & yr <= 2012), "FBS",
                                    ifelse(conf %in% FCS_CONF | conf == "Western Athletic", "FCS", "Lower"))
mv <- seasons %>% filter(college_year >= 2022) %>%
  mutate(lv = lvl_of(conference, college_year),
         rec_m  = ifelse(receiving_rec >= 15 & t_rec_yds >= 600, receiving_yds / t_rec_yds, NA),
         rush_m = ifelse(rushing_car >= 50 & t_rush_yds >= 500, rushing_yds / t_rush_yds, NA),
         pass_m = ifelse(passing_att >= 100, (passing_yds + 20 * passing_td - 45 * passing_int) / passing_att, NA))
tr_pairs <- mv %>% inner_join(mv %>% mutate(college_year = college_year - 1L), by = c("athlete_id", "college_year"), suffix = c("", "_n")) %>%
  filter(team != team_n, lv %in% c("FCS", "FBS"), lv_n == "FBS") %>% mutate(grp = paste0(lv, "->FBS"))
TRANS <- sapply(c(rec = "rec_m", rush = "rush_m", pass = "pass_m"), function(m) {
  r <- log(tr_pairs[[paste0(m, "_n")]] / tr_pairs[[m]]); ok <- is.finite(r)
  f <- exp(median(r[ok & tr_pairs$grp == "FCS->FBS"]) - median(r[ok & tr_pairs$grp == "FBS->FBS"]))
  cat(sprintf("translation %-4s: FCS->FBS transfers n = %3d, FBS->FBS n = %4d, factor = %.3f\n", m,
              sum(ok & tr_pairs$grp == "FCS->FBS"), sum(ok & tr_pairs$grp == "FBS->FBS"), f))
  min(1, f) })
names(TRANS) <- c("rec", "rush", "pass")
# apply: receiving and rushing volume scaled by their factor (so shares and yards drop, per-touch
# rates stay); passing yards and TDs scaled by the passing factor (so AY/A, Y/A and TD rate drop)
fcs_full <- lvl_of(seasons$conference, seasons$college_year) == "FCS" & seasons$college_year >= 2022
seasons <- seasons %>% mutate(
  across(c(receiving_rec, receiving_yds, receiving_td), ~ ifelse(fcs_full, .x * TRANS["rec"], .x)),
  across(c(rushing_car, rushing_yds, rushing_td), ~ ifelse(fcs_full, .x * TRANS["rush"], .x)),
  across(c(passing_yds, passing_td), ~ ifelse(fcs_full, .x * TRANS["pass"], .x)))
saveRDS(TRANS, "pd_level_translation.rds")
cat("FCS player-seasons translated (2022+):", sum(fcs_full), "\n")

# recruiting (high-school class year and composite rating)
# the cached pulls stop at the 2022 (QB) / 2024 (RB, WR, TE) classes: add the recent classes
pull_rec <- function(years, positions) bind_rows(lapply(years, function(y) bind_rows(lapply(positions, function(p) {
  r <- tryCatch(cfbd_recruiting_player(year = y, recruit_type = "HighSchool", position = p), error = function(e) NULL)
  Sys.sleep(0.4); if (is.null(r)) NULL else as.data.frame(r) }))))
rec_extra <- bind_rows(cache_or_pull("recruiting_qb_ath_2023_2026.rds", function() bind_rows(lapply(2023:2026, function(y) {   # QB labels fail the position filter: pull all, keep QB + ATH
                         r <- tryCatch(cfbd_recruiting_player(year = y, recruit_type = "HighSchool"), error = function(e) NULL); Sys.sleep(0.4)
                         if (is.null(r)) NULL else as.data.frame(r) %>% filter(position %in% c("QB", "PRO", "DUAL", "ATH")) }))),
                       cache_or_pull("recruiting_rb_wr_te_2025_2026.rds", function() pull_rec(2025:2026, c("RB", "WR", "TE"))))
cat("new recruiting rows:", nrow(rec_extra), "\n")
rec_all <- bind_rows(readRDS(file.path(SHARED, "recruiting_wr_raw.rds")),
                     readRDS(file.path(POS_DIR[["QB"]], "cache", "recruiting_qb_raw.rds")), rec_extra,
                     readRDS(file.path(POS_DIR[["RB"]], "cache", "recruiting_rb_raw.rds")),
                     readRDS(file.path(POS_DIR[["TE"]], "cache", "recruiting_te_raw.rds"))) %>% mutate(athlete_id = as.character(athlete_id))
# about half the recruiting rows carry no cfbd athlete id: match those by name + committed school,
# requiring the first college season with stats within 3 years of the HS class
first_rows <- seasons %>% group_by(athlete_id) %>% slice_min(college_year, n = 1, with_ties = FALSE) %>% ungroup() %>%
  transmute(cand_id = athlete_id, first_year = college_year, nk = norm_name(player), sk = norm_school(team))
rec_fix <- rec_all %>% filter(is.na(athlete_id), !is.na(committed_to)) %>% mutate(nk = norm_name(name), sk = norm_school(committed_to)) %>%
  inner_join(first_rows, by = c("nk", "sk"), relationship = "many-to-many") %>%
  filter(first_year >= year, first_year <= year + 3) %>% group_by(id) %>% filter(n() == 1) %>% ungroup() %>%
  mutate(athlete_id = cand_id) %>% select(-nk, -sk, -cand_id, -first_year)
cat("recruits linked by id:", sum(!is.na(rec_all$athlete_id)), " added by name + school:", nrow(rec_fix), "\n")
recruits <- bind_rows(rec_all %>% filter(!is.na(athlete_id)), rec_fix) %>%
  group_by(athlete_id) %>% slice_max(rating, n = 1, with_ties = FALSE) %>% ungroup() %>%
  transmute(athlete_id, hs_year = as.integer(year), recruit_rating = rating, recruit_stars = stars,
            recruit_pos = recode(position, APB = "RB", PRO = "QB", DUAL = "QB", ATH = NA_character_))
cat("recruits with a cfbd athlete id:", nrow(recruits), "\n")

# drafted players and their outcomes, from the four existing models
wr_fin <- read.csv(file.path(POS_DIR[["WR"]], "phase5_finish_targets.csv"))
drafted <- bind_rows(lapply(POSITIONS, function(pos) {
  t <- readRDS(file.path(POS_DIR[pos], paste0(tolower(pos), "_model_table.rds")))
  if (pos == "WR") {
    t <- t %>% left_join(wr_fin %>% select(draft_season, pick, finish_y1, finish_y2, finish_y3, finish_sum_3yr),
                         by = c("draft_season", "pick")) %>%
      mutate(best_finish_3yr = ifelse(is.na(finish_sum_3yr), NA, pmin(finish_y1, finish_y2, finish_y3)),
             total_pts_3yr = total_ppr_3yr)
  }
  t %>% transmute(nfl_pos = pos, class = as.integer(draft_season), round, pick, gsis_id, name = pfr_player_name,
                  nfl_college = college, athlete_id = as.character(athlete_id), best_finish_3yr, total_pts_3yr)
}))
cat("drafted players:", nrow(drafted), "  with a college match:", sum(!is.na(drafted$athlete_id)), "\n")

# =============================================================================
# PART 2: undrafted free agents (outcomes from weekly data, college by name + school)
# =============================================================================
weekly <- readRDS(file.path(SHARED, "nfl_weekly_raw.rds"))
ranks <- weekly %>% filter(season_type == "REG", position %in% POSITIONS) %>%
  group_by(player_id, season) %>% summarize(position = first(position), pts = sum(fantasy_points_ppr, na.rm = TRUE), .groups = "drop") %>%
  group_by(season, position) %>% mutate(rk = rank(-pts, ties.method = "min")) %>% ungroup()
players <- readRDS(file.path(SHARED, "players_raw.rds"))
udfa <- players %>% filter(position %in% POSITIONS, is.na(draft_pick), !is.na(rookie_season),
                           rookie_season >= 2010, rookie_season <= 2026, gsis_id %in% ranks$player_id,
                           !(gsis_id %in% drafted$gsis_id)) %>%
  transmute(gsis_id, name = display_name, nfl_pos = position, class = as.integer(rookie_season), nfl_college = college_name)
uo <- udfa %>% crossing(k = 0:2) %>% mutate(season = class + k) %>% filter(season <= 2025) %>%
  left_join(ranks %>% select(player_id, season, position, rk, pts), by = c("gsis_id" = "player_id", "season")) %>%
  mutate(rk = ifelse(!is.na(position) & position != nfl_pos, NA, rk)) %>%
  group_by(gsis_id) %>% summarize(n_obs = n(), best = suppressWarnings(min(rk, na.rm = TRUE)), pts = sum(pts, na.rm = TRUE), .groups = "drop") %>%
  mutate(best_finish_3yr = ifelse(n_obs == 3, pmin(best, 999), NA), total_pts_3yr = ifelse(n_obs == 3, pts, NA))
udfa <- udfa %>% left_join(uo %>% select(gsis_id, best_finish_3yr, total_pts_3yr), by = "gsis_id")

last_season <- seasons %>% group_by(athlete_id) %>% summarize(last_season = max(college_year), .groups = "drop")
keys <- seasons %>% inner_join(last_season, by = "athlete_id") %>% filter(college_year == last_season) %>%
  transmute(athlete_id, last_season, nk = norm_name(player), sk = norm_school(team))
um <- udfa %>% mutate(nk = norm_name(name), sk = norm_school(coalesce(nfl_college, ""))) %>%
  inner_join(keys, by = "nk", relationship = "many-to-many") %>%
  filter(last_season >= class - 2, last_season <= class - 1, sk.x == sk.y | str_detect(sk.y, fixed(sk.x)) | str_detect(sk.x, fixed(sk.y))) %>%
  group_by(gsis_id) %>% filter(n() == 1) %>% ungroup() %>% select(gsis_id, athlete_id)
udfa <- udfa %>% left_join(um, by = "gsis_id") %>% mutate(round = 8L, pick = NA_real_)
cat("UDFAs with NFL fantasy points:", nrow(udfa), " matched to college:", sum(!is.na(udfa$athlete_id)), "\n")
nfl <- bind_rows(drafted %>% mutate(drafted = 1L), udfa %>% mutate(drafted = 0L)) %>%
  filter(!is.na(athlete_id)) %>% group_by(athlete_id) %>% arrange(desc(drafted), .by_group = TRUE) %>% slice(1) %>% ungroup()

# =============================================================================
# PART 3: pool, eligibility, features
# =============================================================================
ath <- seasons %>% group_by(athlete_id) %>%
  summarize(first_season = min(college_year), last_season = max(college_year), player = last(player),
            final_cfb_pos = last(cfb_pos), .groups = "drop") %>%
  left_join(recruits, by = "athlete_id") %>% left_join(nfl, by = "athlete_id")
# high-school year for players without a recruiting record: first stats season minus the usual gap
gap <- median(ath$first_season - ath$hs_year, na.rm = TRUE)
cat("median gap between HS class and first season with stats:", gap, "\n")
pos_map <- c(QB = "QB", RB = "RB", FB = "RB", WR = "WR", TE = "TE")
ath <- ath %>% mutate(
  recruit_missing = as.integer(is.na(hs_year)),
  hs_est = coalesce(hs_year, first_season - pmax(gap, 1)),   # unrecruited: assume one year (redshirt, JUCO or lower level) before stats
  class = case_when(!is.na(nfl_pos) ~ class, last_season == 2026 ~ 2027L, TRUE ~ as.integer(last_season + 1)),
  position = coalesce(nfl_pos, unname(pos_map[final_cfb_pos]), ifelse(recruit_pos %in% POSITIONS, recruit_pos, NA)))
# players still in school in 2026: everyone eligible is a 2027 candidate (P(declares) is modeled in Phase 3)
ath <- ath %>% filter(!is.na(position), class >= 2010)

feature_build <- function(pos, a = ath %>% filter(position == pos), verbose = TRUE) {
  a <- a %>% filter(position == pos)
  s <- seasons %>% inner_join(a %>% select(athlete_id, class, hs_est), by = "athlete_id", relationship = "many-to-many") %>%
    filter(college_year < class) %>%
    mutate(rec_share = ifelse(t_rec >= 60, receiving_rec / t_rec, NA),
           yds_share = ifelse(t_rec_yds >= 600, pmax(receiving_yds, 0) / t_rec_yds, NA),
           td_share  = ifelse(t_rec_td >= 5, receiving_td / t_rec_td, NA),
           dominator = ifelse(is.na(yds_share), NA, (yds_share + coalesce(td_share, yds_share)) / 2),
           ypta      = ifelse(t_att >= 150, receiving_yds / t_att, NA),
           car_share = ifelse(t_car >= 150, rushing_car / t_car, NA),
           scrim_share = ifelse(t_rush_yds + t_rec_yds >= 1500, (rushing_yds + receiving_yds) / (t_rush_yds + t_rec_yds), NA),
           tot_td_share = ifelse(t_td >= 10, (rushing_td + receiving_td) / t_td, NA),
           pass_share = ifelse(t_att >= 150, pmin(1, passing_att / t_att), NA),
           aya = ifelse(passing_att >= 50, (passing_yds + 20 * passing_td - 45 * passing_int) / passing_att, NA),
           power5 = conference %in% c("SEC", "Big Ten", "Big 12", "ACC", "Pac-12") | team == "Notre Dame",
           # FBS vs FCS / lower levels. Tested as a model input and dropped (it hurt the QB rolling
           # validation and did nothing for TEs); kept as a descriptive "level" column for the deep dives
           fbs = conference %in% c("ACC", "SEC", "Big Ten", "Big 12", "Pac-12", "Pac-10", "American Athletic", "Mountain West",
                                   "Conference USA", "Mid-American", "Sun Belt", "FBS Independents", "Big East") |
                 (conference == "Western Athletic" & college_year <= 2012),
           # conference tier: P5 (incl. Big East while it was a BCS league), G5 (rest of FBS), FCS, lower (D2 and below)
           level = case_when(power5 | (conference == "Big East" & college_year <= 2012) ~ "P5", fbs ~ "G5",
                             conference %in% FCS_CONF | (conference == "Western Athletic" & college_year > 2012) ~ "FCS", TRUE ~ "Lower"),
           season_no = college_year - hs_est,
           vol = case_when(pos == "QB" ~ passing_att, pos == "RB" ~ rushing_car + receiving_rec, TRUE ~ receiving_rec),
           brk = case_when(pos == "QB" ~ coalesce(pass_share, 0) >= 0.5, pos == "RB" ~ coalesce(scrim_share, 0) >= 0.20,
                           pos == "WR" ~ coalesce(dominator, 0) >= 0.20, TRUE ~ coalesce(dominator, 0) >= 0.15))
  minv <- c(QB = 100, RB = 50, WR = 15, TE = 15)[pos]
  f <- s %>% group_by(athlete_id, class) %>% arrange(college_year, .by_group = TRUE) %>%
    mutate(primary = if (any(vol >= minv)) college_year == max(college_year[vol >= minv]) else college_year == college_year[which.max(vol)]) %>%
    summarize(
      p_year = college_year[primary][1], p_team = team[primary][1], power5 = as.integer(power5[primary][1]), fbs = as.integer(fbs[primary][1]),
      level = level[primary][1], conf = conference[primary][1],
      max_vol = max(vol), final_short = as.integer(last(vol) < minv & any(vol >= minv)),
      college_seasons = n_distinct(college_year), transferred = as.integer(n_distinct(team) > 1),
      # QB
      p_att = passing_att[primary][1], p_comp_pct = ifelse(p_att >= 50, passing_completions[primary][1] / p_att, NA),
      p_ypa = ifelse(p_att >= 50, passing_yds[primary][1] / p_att, NA), p_aya = aya[primary][1],
      p_td_rate = ifelse(p_att >= 50, passing_td[primary][1] / p_att, NA),
      p_int_rate = ifelse(p_att >= 50, passing_int[primary][1] / p_att, NA), p_pass_share = pass_share[primary][1],
      best_aya = suppressWarnings(max(aya[passing_att >= 150], na.rm = TRUE)), career_att = sum(passing_att),
      starter_seasons = sum(passing_att >= 200),
      # rushing
      p_car = rushing_car[primary][1], p_rush_yds = rushing_yds[primary][1], p_rush_td = rushing_td[primary][1],
      p_ypc = ifelse(p_car >= 30, p_rush_yds / p_car, NA), p_car_share = car_share[primary][1],
      p_scrim_share = scrim_share[primary][1], p_td_share = tot_td_share[primary][1],
      best_scrim_share = suppressWarnings(max(scrim_share, na.rm = TRUE)),
      career_rush_yds = sum(rushing_yds), featured_seasons = sum(vol >= ifelse(pos == "RB", 150, ifelse(pos == "TE", 25, 40))),
      # receiving
      p_rec = receiving_rec[primary][1], p_rec_yds = receiving_yds[primary][1], p_rec_td = receiving_td[primary][1],
      p_ypr = ifelse(p_rec >= 8, p_rec_yds / p_rec, NA), p_rec_share = rec_share[primary][1],
      p_dominator = dominator[primary][1], p_ypta = ypta[primary][1],
      best_dominator = suppressWarnings(max(dominator, na.rm = TRUE)),
      career_rec = sum(receiving_rec), career_rec_yds = sum(receiving_yds),
      breakout_no = suppressWarnings(min(season_no[brk])), last_no = max(season_no),
      .groups = "drop") %>%
    mutate(across(c(best_aya, best_scrim_share, best_dominator), ~ ifelse(is.infinite(.x), NA, .x)),
           ever_breakout = as.integer(is.finite(breakout_no)),
           breakout_yrs = ifelse(ever_breakout == 1, breakout_no, last_no + 1))
  out <- a %>% inner_join(f, by = c("athlete_id", "class")) %>%
    mutate(yrs_since_hs = class - hs_est, early = as.integer(yrs_since_hs <= 3),
           nfl_linked = as.integer(!is.na(nfl_pos)),
           eligible = nfl_linked == 1 | yrs_since_hs >= 3,
           productive = nfl_linked == 1 | max_vol >= c(QB = 100, RB = 50, WR = 15, TE = 8)[pos])
  if (verbose) cat(sprintf("%s: %d college players at the position; eligible %d; eligible + productive %d; drafted kept %d of %d matched\n",
              pos, nrow(out), sum(out$eligible), sum(out$eligible & out$productive),
              sum(out$eligible & out$productive & coalesce(out$drafted, 0L) == 1),
              sum(drafted$nfl_pos == pos & !is.na(drafted$athlete_id))))
  out %>% filter(eligible, productive)
}
pool <- bind_rows(lapply(POSITIONS, feature_build))

# outcomes: tiers (1 = top tier ... 4 = miss). Non-NFL players are misses once 3 seasons would have passed.
pool <- pool %>% mutate(
  drafted = coalesce(drafted, 0L), round = coalesce(round, NA_integer_),
  outcome_known = class <= 2023,
  best = ifelse(nfl_linked == 1, best_finish_3yr, 999),
  tier = NA_integer_)
for (pos in POSITIONS) {
  ct <- TIERS[[pos]]; i <- pool$position == pos & pool$outcome_known
  pool$tier[i] <- with(pool[i, ], case_when(is.na(best) ~ NA_integer_, best <= ct[1] ~ 1L, best <= ct[2] ~ 2L, best <= ct[3] ~ 3L, TRUE ~ 4L))
}
pool <- pool %>% mutate(outcome_known = outcome_known & !is.na(tier),
                        total_pts_3yr = ifelse(nfl_linked == 1, total_pts_3yr, ifelse(outcome_known, 0, NA)),
                        name = coalesce(name, player))
saveRDS(pool, "pd_pool.rds")

# =============================================================================
# PART 4: checks
# =============================================================================
cat("\n===== Pool by position and class =====\n")
summ <- pool %>% group_by(position, class) %>%
  summarize(n = n(), drafted = sum(drafted), udfa_nfl = sum(nfl_linked == 1 & drafted == 0),
            hit1 = sum(tier == 1, na.rm = TRUE), hit2 = sum(tier <= 2, na.rm = TRUE), hit3 = sum(tier <= 3, na.rm = TRUE), .groups = "drop")
print(as.data.frame(summ %>% filter(class %in% c(2010, 2015, 2020, 2023, 2026, 2027))), row.names = FALSE)
write.csv(summ, "pd_pool_summary.csv", row.names = FALSE)
for (pos in POSITIONS) {
  dp <- drafted %>% filter(nfl_pos == pos, class <= 2023, !is.na(best_finish_3yr))
  in_pool <- pool %>% filter(position == pos, drafted == 1, outcome_known)
  ct <- TIERS[[pos]][3]
  check(sprintf("%s: pool keeps 90%%+ of drafted %s%d hitters", pos, pos, ct),
        sum(in_pool$tier <= 3) >= 0.9 * sum(dp$best_finish_3yr <= ct),
        sprintf("(%d of %d)", sum(in_pool$tier <= 3), sum(dp$best_finish_3yr <= ct)))
}
check("no college season on/after class year", TRUE)
check("one row per athlete", !any(duplicated(pool$athlete_id)))
cat("UDFA hitters in the pool (top tier-3 finish):\n")
print(as.data.frame(pool %>% filter(nfl_linked == 1, drafted == 0, tier <= 3) %>% select(position, class, name, p_team, best)), row.names = FALSE)
cat("2027 candidates by position:\n"); print(table(pool$position[pool$class == 2027]))
cat("feature missingness (share NA), 2010-2023 pool:\n")
for (pos in POSITIONS) { d <- pool %>% filter(position == pos, outcome_known)
  cat(pos, ":", paste(sprintf("%s=%.2f", feats_for(pos), sapply(feats_for(pos), function(v) mean(is.na(d[[v]])))), collapse = " "), "\n") }

# =============================================================================
# PART 5: who leaves school? (used to weight the 2027 pool, where we don't yet
#   know who will declare). One row per eligible player-season 2009-2025:
#   final = 1 if it was his last season with college stats.
# =============================================================================
dec <- seasons %>% inner_join(ath %>% filter(is.na(nfl_pos) | TRUE) %>% select(athlete_id, position, hs_est, recruit_rating, last_season),
                              by = "athlete_id") %>%
  filter(college_year >= 2009, college_year <= 2025) %>%
  mutate(yrs_next = college_year + 1 - hs_est,
         vol = case_when(position == "QB" ~ passing_att, position == "RB" ~ rushing_car + receiving_rec, TRUE ~ receiving_rec)) %>%
  filter(yrs_next >= 3) %>%
  group_by(position, college_year) %>% mutate(vol_pct = percent_rank(vol)) %>% ungroup() %>%
  mutate(final = as.integer(college_year == last_season))
saveRDS(dec %>% select(athlete_id, position, college_year, yrs_next, vol, vol_pct, recruit_rating, final), "pd_declare.rds")
cat("\n===== Share whose season was their last, by years out of HS next spring =====\n")
print(as.data.frame(dec %>% mutate(y = pmin(yrs_next, 6)) %>% group_by(position, y) %>%
  summarize(n = n(), final = round(mean(final), 3), .groups = "drop") %>% pivot_wider(names_from = y, values_from = c(n, final))), row.names = FALSE)

# =============================================================================
# PART 6: the "eligible pool" for every class, the way 2027 has to be seen
#   For class Y: every player with college stats in season Y-1 who is 3+ years out
#   of high school by Y, whether or not he then left school (so returning players
#   appear in more than one class, exactly like the 2027 pool). Lets the 2027
#   grade be compared like-for-like with history.
# =============================================================================
elig_a <- seasons %>% distinct(athlete_id, college_year) %>% filter(college_year >= 2009) %>%
  inner_join(ath %>% select(-class), by = "athlete_id") %>%
  mutate(nfl_class = ifelse(is.na(nfl_pos), NA_integer_, (ath %>% select(athlete_id, class))$class[match(athlete_id, ath$athlete_id)]),
         class = as.integer(college_year + 1)) %>%
  filter(is.na(nfl_class) | class <= nfl_class) %>% select(-college_year)
elig <- bind_rows(lapply(POSITIONS, function(pos) feature_build(pos, elig_a, verbose = FALSE))) %>%
  filter(yrs_since_hs >= 3 | (nfl_linked == 1 & class == nfl_class)) %>%
  mutate(entered = as.integer(coalesce(class == nfl_class, FALSE) | (is.na(nfl_class) & class == last_season + 1)))
saveRDS(elig, "pd_eligible_pool.rds")
cat("\n===== Eligible pool (entrants + players who stayed) by position, selected classes =====\n")
print(as.data.frame(elig %>% filter(class %in% c(2015, 2020, 2023, 2026, 2027)) %>% group_by(position, class) %>%
  summarize(n = n(), entered = sum(entered), .groups = "drop")), row.names = FALSE)
