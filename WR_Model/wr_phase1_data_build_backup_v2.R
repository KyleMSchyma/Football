# =============================================================================
# WR Model -- Phase 1: data build (single script)
#
# Builds a WR-only base table for draft classes 2010-2026 with each player's full
# college career attached, then runs pass/fail validation checks.
#
#   PART 1  Pull and cache raw data (draft picks, combine, birth dates, NFL weekly
#           stats, college stats 2004-2025, recruiting)
#   PART 2  Match each drafted WR to his college career and build market-share
#           columns (yards/TD share, dominator, yards per team pass attempt)
#   PART 3  Validate (95% match rate, no leakage, shares in range) and write
#           review files
#
# Outputs (in this folder):
#   wr_base.rds             one row per drafted WR
#   wr_college_seasons.rds  one row per WR per college season
#   unmatched_wrs.csv       WRs to look up by hand
#   suspicious_matches.csv  matches worth a second look
#
# Requires: nflreadr, cfbfastR, dplyr, stringr
# cfbfastR needs your College Football Data API key in CFBD_API_KEY.
# Run with the working directory set to this WR_Model folder. Every pull is
# cached under cache/ and skipped on re-run; delete a cache file to refresh it.
#
# Hand fixes: copy manual_matches_template.csv to manual_matches.csv, add rows of
# pfr_player_id,athlete_id, and re-run. Manual rows override the automatic match.
# =============================================================================

library(nflreadr)
library(cfbfastR)
library(dplyr)
library(stringr)

# =============================================================================
# PART 1: Pull and cache raw data
# =============================================================================
draft_seasons <- 2010:2026          # cfbd has almost no player data before 2008
nfl_seasons   <- 2006:2025          # last COMPLETE NFL season as of Nov 2026
cfb_years     <- 2004:2025          # cfbd player season stats start around 2004;
# the validation script reports rows per year so
# any gap in early coverage is visible
dir.create("cache", showWarnings = FALSE)

cache_or_pull <- function(file, pull_fn) {
  path <- file.path("cache", file)
  if (file.exists(path)) {
    cat("cached:", path, "\n")
    return(readRDS(path))
  }
  cat("pulling:", path, "...\n")
  out <- pull_fn()
  saveRDS(out, path)
  out
}














# --- 1. Draft picks: all WRs, 2006-2026 -------------------------------------
# NOTE: the yardage columns on this table (games, rec_yards, ...) are NFL CAREER
# totals, not college stats -- the leak found in the Rookie_Model work. They are
# dropped here so they can never reach a feature set by accident.
wr_draft <- cache_or_pull("wr_draft_picks.rds", function() {
  load_draft_picks(seasons = draft_seasons) %>%
    filter(position == "WR") %>%
    select(season, round, pick, team, gsis_id, pfr_player_id, cfb_player_id,
           pfr_player_name, position, college, age) %>%
    as.data.frame()
})
cat("drafted WRs:", nrow(wr_draft), "\n")
print(table(wr_draft$season))

# --- 2. Combine results -----------------------------------------------------
combine_raw <- cache_or_pull("combine_raw.rds", function() {
  as.data.frame(load_combine(seasons = draft_seasons))
})

# --- 3. Player master table (birth dates) -----------------------------------
# draft_picks$age is an integer; breakout age and age-at-draft need the real date.
players_raw <- cache_or_pull("players_raw.rds", function() {
  as.data.frame(load_players())
})

# --- 4. NFL weekly stats (outcomes for Phase 2) -----------------------------
# ALL players, not just rookies: the top-24 "hit" flag ranks a rookie against
# every WR in that season.
weekly_raw <- cache_or_pull("nfl_weekly_raw.rds", function() {
  as.data.frame(load_player_stats(seasons = nfl_seasons, summary_level = "week"))
})

# --- 5. College player season stats, 2004-2025 ------------------------------
# Reuse the 2015-2025 pull already cached by the Rookie_Model work and only pull
# the missing years from the API.
cfb_file <- file.path("cache", "cfbd_stats_2004_2025.rds")
if (file.exists(cfb_file)) {
  cfb_all <- readRDS(cfb_file)
  cat("cached:", cfb_file, "\n")
} else {
  existing <- NULL
  prior_cache <- "../Rookie_Model/cfbd_stats_all_years.rds"
  if (file.exists(prior_cache)) {
    existing <- readRDS(prior_cache)
    cat("reusing Rookie_Model cache for years:",
        paste(range(existing$college_year), collapse = "-"), "\n")
  }
  have_years <- if (is.null(existing)) integer(0) else unique(existing$college_year)
  need_years <- setdiff(cfb_years, have_years)
  new_list <- list()
  for (y in need_years) {
    cat("pulling college stats", y, "...\n")
    res <- tryCatch(
      cfbd_stats_season_player(year = y, season_type = "regular"),
      error = function(e) { cat("  failed:", conditionMessage(e), "\n"); NULL }
    )
    if (!is.null(res) && nrow(res) > 0) new_list[[as.character(y)]] <- res %>% mutate(college_year = y)
    Sys.sleep(1) # be polite to the free API tier
  }
  cfb_all <- bind_rows(existing, bind_rows(new_list)) %>% as.data.frame()
  saveRDS(cfb_all, cfb_file)
}
cat("college player-season rows:", nrow(cfb_all), "\n")
print(table(cfb_all$college_year))

# --- 6. Recruiting rankings (optional pre-college talent prior) -------------
# Joined later by cfbd athlete_id. A failure here does not stop Phase 1.
recruit_raw <- cache_or_pull("recruiting_wr_raw.rds", function() {
  out <- list()
  for (y in 2000:2024) {
    res <- tryCatch(
      cfbd_recruiting_player(year = y, recruit_type = "HighSchool", position = "WR"),
      error = function(e) NULL
    )
    if (!is.null(res) && nrow(res) > 0) out[[as.character(y)]] <- as.data.frame(res)
    Sys.sleep(1)
  }
  bind_rows(out)
})
cat("recruiting rows:", nrow(recruit_raw), "\n")

# =============================================================================
# PART 2: Match each drafted WR to his college career
#
#   1. Normalized name + college season (draft year - 1, fallback draft year - 2).
#   2. Several same-name rows: rank by school agreement > draft year - 1 >
#      listed as WR > most receiving yards. A same-name player at another school
#      who played defense or QB is rejected as a different person.
#   3. Nickname pass for the rest: same last name + same school + same season,
#      offensive position, and only one such player.
#   4. Take the WHOLE college career by cfbd athlete_id (carries across transfers),
#      keeping only seasons before the draft year.
#   5. manual_matches.csv, if present, overrides the automatic match.
# =============================================================================
if (is.null(recruit_raw)) recruit_raw <- data.frame()
norm_name <- function(x) {
  x %>% str_to_lower() %>%
    str_replace_all("[.']", "") %>%
    str_replace_all("\\s+(jr|sr|ii|iii|iv|v)\\.?$", "") %>%
    str_replace_all("[^a-z ]", "") %>%
    str_squish()
}

# PFR college names ("Ohio St.", "Miami (FL)") vs cfbd team names ("Ohio State",
# "Miami"). Only used to break ties and flag suspicious matches, never to drop rows.
school_alias <- c(
  "central florida" = "ucf", "southern california" = "usc", "louisiana state" = "lsu",
  "mississippi" = "ole miss", "southern methodist" = "smu", "texas christian" = "tcu",
  "brigham young" = "byu", "nevadalas vegas" = "unlv", "alabamabirmingham" = "uab",
  "texasel paso" = "utep", "texassan antonio" = "utsa", "miami fl" = "miami",
  "miami oh" = "miami oh", "pittsburgh" = "pittsburgh", "north carolina state" = "nc state",
  "louisianamonroe" = "ul monroe", "louisianalafayette" = "louisiana",
  "middle tennessee state" = "middle tennessee", "florida international" = "fiu",
  "massachusetts" = "umass", "connecticut" = "uconn", "hawaii" = "hawaii",
  "middle tenn state" = "middle tennessee", "lamonroe" = "ul monroe", "alabirmingham" = "uab", "se missouri state" = "southeast missouri state",
  "lalafayette" = "louisiana", "east central ok" = "east central"
)
norm_school <- function(x) {
  s <- x %>% str_to_lower() %>%
    str_replace_all("\\bst\\.?$", "state") %>%
    str_replace_all("\\bst\\.?\\s", "state ") %>%
    str_replace_all("[^a-z ]", "") %>% str_squish()
  ifelse(s %in% names(school_alias), unname(school_alias[s]), s)
}

# --- Team totals per college season (market-share denominators) ------------
# Summed over every player cfbd lists for that team-season. This tracks official
# team totals closely for FBS; for small-school (FCS/DII) teams cfbd coverage can be
# thinner, so shares there are flagged in the validation step.
team_totals <- cfb_all %>%
  group_by(college_year, team) %>%
  summarize(team_rec_yds = sum(receiving_yds, na.rm = TRUE),
            team_rec_td  = sum(receiving_td,  na.rm = TRUE),
            team_rec     = sum(receiving_rec, na.rm = TRUE),
            team_pass_att = sum(passing_att,  na.rm = TRUE),
            .groups = "drop")

cfb_all <- cfb_all %>%
  mutate(name_key = norm_name(player), school_key = norm_school(team))

# --- Candidate matching for the final college season -----------------------
dp <- wr_draft %>%
  mutate(name_key = norm_name(pfr_player_name), school_key = norm_school(college))

offensive_pos <- c("WR", "TE", "RB", "?")   # "?" = position not listed in cfbd

pick_best <- function(cand_df, method, require_school = FALSE) {
  cand_df %>%
    mutate(sk  = ifelse(is.na(school_key) | school_key == "", "@@none@@", school_key),
           skc = ifelse(is.na(school_key_cfb) | school_key_cfb == "", "@@none@@", school_key_cfb),
           school_match = sk == skc | str_detect(skc, fixed(sk)) | str_detect(sk, fixed(skc)),
           is_wr = cfb_position %in% "WR") %>%
    # A same-name player at a different school who also played defense or QB is
    # almost always a different person (e.g. an FCS WR whose season cfbd lacks,
    # matched to a same-name DB elsewhere). Reject those rather than keep them.
    filter(school_match | cfb_position %in% offensive_pos) %>%
    filter(!require_school | school_match) %>%
    group_by(pfr_player_name, season, pick) %>%
    mutate(n_candidates = n_distinct(athlete_id)) %>%
    arrange(desc(school_match), year_offset, desc(is_wr), desc(coalesce(receiving_yds, 0)),
            .by_group = TRUE) %>%
    slice(1) %>%
    ungroup() %>%
    transmute(season, pick, pfr_player_name, athlete_id, match_year_offset = year_offset,
              match_school_ok = school_match, match_cfb_position = cfb_position,
              match_n_candidates = n_candidates, match_method = method)
}

cfb_keys <- cfb_all %>% select(name_key, college_year, athlete_id, team, conference,
                               cfb_position = position, school_key_cfb = school_key,
                               receiving_yds) %>%
  mutate(last_key = word(name_key, -1))

dp_years <- bind_rows(
  dp %>% mutate(college_year = season - 1L, year_offset = 1L),
  dp %>% mutate(college_year = season - 2L, year_offset = 2L)
)

# Pass 1: exact normalized name + season
cands <- dp_years %>%
  inner_join(cfb_keys %>% select(-last_key), by = c("name_key", "college_year"),
             relationship = "many-to-many") %>%
  pick_best("auto_name")

# Pass 2 (nicknames, e.g. "Gabe" vs "Gabriel", "Tutu" vs "Chatarius"): same last
# name + same school + same season, offensive position, and only ONE such player.
unmatched_keys <- anti_join(dp, cands, by = c("season", "pick", "pfr_player_name"))
cands2 <- dp_years %>%
  semi_join(unmatched_keys, by = c("season", "pick", "pfr_player_name")) %>%
  mutate(last_key = word(name_key, -1)) %>%
  inner_join(cfb_keys %>% select(-name_key), by = c("last_key", "college_year"),
             relationship = "many-to-many") %>%
  filter(cfb_position %in% offensive_pos) %>%
  pick_best("auto_lastname_school", require_school = TRUE) %>%
  filter(match_n_candidates == 1)

cands <- bind_rows(cands, cands2)

dp <- dp %>% left_join(cands, by = c("season", "pick", "pfr_player_name"))
cat("pass 1 (name) matches:", nrow(cands) - nrow(cands2),
    " pass 2 (last name + school) matches:", nrow(cands2), "\n")

# Manual overrides
if (file.exists("manual_matches.csv")) {
  mm <- read.csv("manual_matches.csv", stringsAsFactors = FALSE)
  cat("applying", nrow(mm), "manual matches\n")
  idx <- match(dp$pfr_player_id, mm$pfr_player_id)
  hit <- !is.na(idx)
  dp$athlete_id[hit]   <- mm$athlete_id[idx[hit]]
  dp$match_method[hit] <- "manual"
}

cat("matched:", sum(!is.na(dp$athlete_id)), "of", nrow(dp), "drafted WRs\n")

# --- Full college career by athlete_id -------------------------------------
# Only seasons BEFORE the draft year, so nothing post-draft can leak in.
career <- dp %>%
  filter(!is.na(athlete_id)) %>%
  select(gsis_id, pfr_player_id, pfr_player_name, draft_season = season, pick, athlete_id) %>%
  inner_join(cfb_all %>% select(athlete_id, college_year, team, conference, cfb_position = position,
                                rec = receiving_rec, rec_yds = receiving_yds, rec_td = receiving_td,
                                rush_car = rushing_car, rush_yds = rushing_yds, rush_td = rushing_td,
                                kr_yds = kick_returns_yds, pr_yds = punt_returns_yds),
             by = "athlete_id", relationship = "many-to-many") %>%
  filter(college_year < draft_season) %>%
  left_join(team_totals, by = c("college_year", "team")) %>%
  mutate(across(c(rec, rec_yds, rec_td, rush_car, rush_yds, rush_td), ~ coalesce(.x, 0)),
         # pmax(0, ...): a few players have small negative season receiving yards
         yds_share  = ifelse(team_rec_yds > 0, pmax(0, rec_yds) / team_rec_yds, NA_real_),
         td_share   = ifelse(team_rec_td  > 0, rec_td  / team_rec_td,  NA_real_),
         rec_share  = ifelse(team_rec     > 0, rec     / team_rec,     NA_real_),
         # dominator: average of yards and TD share; if the team had no receiving
         # TDs, fall back to yards share alone rather than dropping the season
         dominator  = ifelse(is.na(td_share), yds_share, (yds_share + td_share) / 2),
         yptpa      = ifelse(team_pass_att >= 100, pmax(0, rec_yds) / team_pass_att, NA_real_),
         power5     = conference %in% c("SEC", "Big Ten", "Big 12", "ACC", "Pac-12") |
           team == "Notre Dame")

# Birth dates -> age on Sept 1 of each college season (breakout age in Phase 2)
bd <- players_raw %>%
  transmute(gsis_id, pfr_id, birth_date = as.Date(birth_date)) %>%
  filter(!is.na(birth_date))
dp <- dp %>%
  left_join(bd %>% filter(!is.na(gsis_id)) %>% select(gsis_id, birth_date) %>%
              distinct(gsis_id, .keep_all = TRUE), by = "gsis_id", na_matches = "never") %>%
  left_join(bd %>% filter(!is.na(pfr_id)) %>% select(pfr_id, birth_date_pfr = birth_date) %>%
              distinct(pfr_id, .keep_all = TRUE),
            by = c("pfr_player_id" = "pfr_id"), na_matches = "never") %>%
  mutate(birth_date = coalesce(birth_date, birth_date_pfr),
         age_at_draft = as.numeric(as.Date(paste0(season, "-04-25")) - birth_date) / 365.25) %>%
  select(-birth_date_pfr)

career <- career %>%
  left_join(dp %>% select(pfr_player_name, season, pick, birth_date),
            by = c("pfr_player_name", "draft_season" = "season", "pick")) %>%
  mutate(age_sept1 = as.numeric(as.Date(paste0(college_year, "-09-01")) - birth_date) / 365.25) %>%
  arrange(draft_season, pick, college_year)

# Career coverage: cfbd data starts in 2004, so the earliest classes lose their
# freshman/sophomore seasons. Flag classes whose 5-year college window is covered.
min_cfb_year <- 2008   # first year cfbd player coverage is usable
dp$career_window_covered <- (dp$season - 5) >= min_cfb_year

# --- Combine (pfr id first, then name + year fallback) ----------------------
ht_to_inches <- function(ht) {
  sapply(strsplit(as.character(ht), "-"), function(p)
    if (length(p) == 2) as.numeric(p[1]) * 12 + as.numeric(p[2]) else NA_real_)
}
cb <- combine_raw %>%
  transmute(pfr_id, cb_name_key = norm_name(player_name), cb_season = season,
            height_in = ht_to_inches(ht), weight_lb = wt,
            forty, bench, vertical, broad_jump, cone, shuttle)

by_id <- dp %>% select(pfr_player_id) %>% filter(!is.na(pfr_player_id)) %>%
  inner_join(cb %>% filter(!is.na(pfr_id)) %>% distinct(pfr_id, .keep_all = TRUE),
             by = c("pfr_player_id" = "pfr_id")) %>%
  select(-cb_name_key, -cb_season)
dp <- dp %>% left_join(by_id, by = "pfr_player_id")
need <- is.na(dp$height_in) & is.na(dp$forty) & is.na(dp$weight_lb)
if (any(need)) {
  by_name <- dp[need, c("name_key", "season")] %>%
    left_join(cb %>% distinct(cb_name_key, cb_season, .keep_all = TRUE),
              by = c("name_key" = "cb_name_key", "season" = "cb_season"))
  for (v in c("height_in", "weight_lb", "forty", "bench", "vertical", "broad_jump", "cone", "shuttle"))
    dp[[v]][need] <- by_name[[v]]
}
dp$combine_invited <- !(is.na(dp$height_in) & is.na(dp$weight_lb) & is.na(dp$forty))

# --- Recruiting (optional) -------------------------------------------------
if (nrow(recruit_raw) > 0 && "athlete_id" %in% names(recruit_raw)) {
  rec <- recruit_raw %>%
    filter(!is.na(athlete_id)) %>%
    mutate(athlete_id = as.character(athlete_id)) %>%
    group_by(athlete_id) %>% slice_max(rating, n = 1, with_ties = FALSE) %>% ungroup() %>%
    select(athlete_id, recruit_stars = stars, recruit_rating = rating, recruit_rank = ranking)
  dp <- dp %>% mutate(athlete_id = as.character(athlete_id)) %>% left_join(rec, by = "athlete_id")
  career$athlete_id <- as.character(career$athlete_id)
} else {
  cat("recruiting data unavailable or has no athlete_id -- skipped\n")
}

# --- Censoring flags for Phase 2 targets -----------------------------------
last_nfl_season <- 2025
dp <- dp %>%
  mutate(nfl_years_complete = pmax(0, pmin(3, last_nfl_season - season + 1)),
         full_3yr_outcome   = nfl_years_complete == 3)

saveRDS(as.data.frame(career), "wr_college_seasons.rds")
saveRDS(as.data.frame(dp), "wr_base.rds")
cat("saved wr_base.rds (", nrow(dp), "rows ) and wr_college_seasons.rds (", nrow(career), "rows )\n")

# =============================================================================
# PART 3: Validate the data build (ATPA 2.5 style checks)
#
# Phase 1 passes when at least 95% of drafted WRs match to college stats, there
# are no duplicate players, no college season falls on/after the draft year, and
# market shares fall in [0, 1].
# =============================================================================
wr <- as.data.frame(dp)
cs <- as.data.frame(career)
check <- function(label, ok, detail = "") {
  cat(sprintf("[%s] %s %s\n", ifelse(ok, "PASS", "FAIL"), label, detail))
  invisible(ok)
}

cat("\n===== Coverage =====\n")
cat("college player-season rows by year (watch for thin early years):\n")
print(table(cfb_all$college_year))
cat("\ndrafted WRs by class:\n")
print(table(wr$season))

cat("\n===== Match rate =====\n")
match_rate <- mean(!is.na(wr$athlete_id))
check("college match rate >= 95%", match_rate >= 0.95, sprintf("(%.1f%%)", 100 * match_rate))
print(wr %>% group_by(season) %>%
        summarize(n = n(), matched = sum(!is.na(athlete_id)),
                  pct = round(100 * matched / n, 1), .groups = "drop"), n = 30)
cat("match rate by round:\n")
print(wr %>% group_by(round) %>% summarize(pct = round(100 * mean(!is.na(athlete_id)), 1)))

cat("\n===== Uniqueness and leakage =====\n")
check("one row per drafted WR", !any(duplicated(wr[, c("season", "pick")])))
check("no college season on/after draft year", all(cs$college_year < cs$draft_season))
check("one athlete_id per drafted WR",
      !any(duplicated(wr$athlete_id[!is.na(wr$athlete_id)])),
      "(a FAIL means two picks were matched to the same college player)")
dup_ids <- wr %>% filter(!is.na(athlete_id)) %>% group_by(athlete_id) %>% filter(n() > 1)
if (nrow(dup_ids) > 0) print(dup_ids %>% select(pfr_player_name, season, college, athlete_id))

cat("\n===== Ranges =====\n")
check("yards share within [0, 1]", all(is.na(cs$yds_share) | (cs$yds_share >= 0 & cs$yds_share <= 1)))
check("TD share within [0, 1]",    all(is.na(cs$td_share)  | (cs$td_share  >= 0 & cs$td_share  <= 1)))
check("age at draft within 20-27",
      all(is.na(wr$age_at_draft) | (wr$age_at_draft > 20 & wr$age_at_draft < 27)))
cat("birth date coverage:", round(100 * mean(!is.na(wr$birth_date)), 1), "%\n")
cat("combine invite rate:", round(100 * mean(wr$combine_invited), 1), "%\n")
cat("drill missingness among invitees (often a strategic skip, so keep a flag):\n")
print(round(100 * colMeans(is.na(wr[wr$combine_invited,
                                    c("height_in", "weight_lb", "forty", "vertical", "broad_jump", "cone", "shuttle", "bench")])), 1))
if ("recruit_stars" %in% names(wr))
  cat("recruiting coverage:", round(100 * mean(!is.na(wr$recruit_stars)), 1), "%\n")

cat("\n===== Final college season summary =====\n")
final_season <- cs %>% group_by(draft_season, pick) %>% slice_max(college_year, n = 1) %>% ungroup()
print(summary(final_season[, c("rec", "rec_yds", "yds_share", "dominator", "yptpa", "age_sept1")]))
thin_team <- final_season %>% filter(!power5, team_rec_yds < 1500)
cat("final seasons with low team receiving totals (possible thin cfbd coverage):",
    nrow(thin_team), "\n")

cat("\n===== Review files =====\n")
unmatched <- wr %>% filter(is.na(athlete_id)) %>%
  select(season, round, pick, pfr_player_name, college, pfr_player_id)
write.csv(unmatched, "unmatched_wrs.csv", row.names = FALSE)
cat("unmatched_wrs.csv:", nrow(unmatched), "rows\n")

suspicious <- wr %>%
  filter(!is.na(athlete_id),
         !match_school_ok | coalesce(match_cfb_position, "") != "WR" | match_n_candidates > 1) %>%
  select(season, round, pick, pfr_player_name, college, athlete_id,
         match_school_ok, match_cfb_position, match_n_candidates, match_method)
write.csv(suspicious, "suspicious_matches.csv", row.names = FALSE)
cat("suspicious_matches.csv:", nrow(suspicious),
    "rows (school disagrees, not listed as WR, or several same-name candidates)\n")
check("Phase 1 ready for Phase 2", match_rate >= 0.95)

