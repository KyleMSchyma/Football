# =============================================================================
# TE Model -- Phase 1: data build (single script)
#
# Same design as the WR, QB and RB Phase 1 scripts, adapted to tight ends.
# Builds a TE-only base table for draft classes 2010-2026 with each player's full
# college career attached, then runs pass/fail validation checks.
#
#   PART 1  Load raw data. Pulls already cached by the WR work (college stats
#           2004-2025, NFL weekly 2006-2025, players, combine, cfbd PPA/usage) are
#           read from ../Football2/cache and never re-pulled. New pulls (TE draft
#           picks, TE recruiting) are cached in ./cache.
#   PART 2  Match each drafted TE to his college career and build per-season
#           receiving production and team-share columns.
#   PART 3  Validate (95% match rate, no leakage, ranges) and write review files.
#
# Outputs (this folder):
#   te_base.rds             one row per drafted TE
#   te_college_seasons.rds  one row per TE per college season
#   unmatched_tes.csv, suspicious_matches.csv
#
# Requires: nflreadr, cfbfastR, dplyr, stringr. CFBD_API_KEY must be set (it is
# read from ~/.Renviron; it is never written to any file here).
# Hand fixes: manual_matches.csv with pfr_player_id,athlete_id overrides the match.
# =============================================================================

suppressMessages({ library(nflreadr); library(cfbfastR); library(dplyr); library(stringr) })

draft_seasons <- 2010:2026
WR_CACHE <- file.path("..", "Football2", "cache")
dir.create("cache", showWarnings = FALSE)

cache_or_pull <- function(file, pull_fn, dir = "cache") {
  path <- file.path(dir, file)
  if (file.exists(path)) { cat("cached:", path, "\n"); return(readRDS(path)) }
  cat("pulling:", path, "...\n")
  out <- pull_fn(); saveRDS(out, path); out
}
shared <- function(file) {
  path <- file.path(WR_CACHE, file)
  if (!file.exists(path)) stop("missing shared cache file: ", path)
  cat("shared cache:", path, "\n"); readRDS(path)
}

# =============================================================================
# PART 1: Raw data
# =============================================================================
te_draft <- cache_or_pull("te_draft_picks.rds", function() {
  load_draft_picks(seasons = draft_seasons) %>% filter(position == "TE") %>%
    select(season, round, pick, team, gsis_id, pfr_player_id, cfb_player_id,
           pfr_player_name, position, college, age) %>% as.data.frame()
})
cat("drafted TEs:", nrow(te_draft), "\n"); print(table(te_draft$season))

combine_raw <- shared("combine_raw.rds")
players_raw <- shared("players_raw.rds")
cfb_all     <- shared("cfbd_stats_2004_2025.rds")
ppa_raw     <- shared("cfbd_ppa_raw.rds")
usage_raw   <- shared("cfbd_usage_raw.rds")

recruit_raw <- cache_or_pull("recruiting_te_raw.rds", function() {
  out <- list()
  for (y in 2003:2024) {
    res <- tryCatch(cfbd_recruiting_player(year = y, recruit_type = "HighSchool", position = "TE"),
                    error = function(e) NULL)
    if (!is.null(res) && nrow(res) > 0) out[[as.character(y)]] <- as.data.frame(res)
    Sys.sleep(0.5)
  }
  bind_rows(out)
})
cat("TE recruiting rows:", nrow(recruit_raw), "\n")

# =============================================================================
# PART 2: Match each drafted TE to his college career (WR matcher, TE-adapted)
# =============================================================================
norm_name <- function(x) {
  x %>% str_to_lower() %>% str_replace_all("[.']", "") %>%
    str_replace_all("\\s+(jr|sr|ii|iii|iv|v)\\.?$", "") %>%
    str_replace_all("[^a-z ]", "") %>% str_squish()
}
school_alias <- c(
  "central florida" = "ucf", "southern california" = "usc", "louisiana state" = "lsu",
  "mississippi" = "ole miss", "southern methodist" = "smu", "texas christian" = "tcu",
  "brigham young" = "byu", "nevadalas vegas" = "unlv", "alabamabirmingham" = "uab",
  "texasel paso" = "utep", "texassan antonio" = "utsa", "miami fl" = "miami",
  "miami oh" = "miami oh", "north carolina state" = "nc state",
  "louisianamonroe" = "ul monroe", "louisianalafayette" = "louisiana",
  "middle tennessee state" = "middle tennessee", "florida international" = "fiu",
  "massachusetts" = "umass", "connecticut" = "uconn", "middle tenn state" = "middle tennessee",
  "lamonroe" = "ul monroe", "alabirmingham" = "uab", "se missouri state" = "southeast missouri state",
  "lalafayette" = "louisiana", "east central ok" = "east central", "boston col" = "boston college",
  "app state" = "appalachian state", "fla atlantic" = "florida atlantic", "ga tech" = "georgia tech"
)
norm_school <- function(x) {
  s <- x %>% str_to_lower() %>% str_replace_all("\\bst\\.?$", "state") %>%
    str_replace_all("\\bst\\.?\\s", "state ") %>% str_replace_all("[^a-z ]", "") %>% str_squish()
  ifelse(s %in% names(school_alias), unname(school_alias[s]), s)
}

# Team totals per college season (share denominators)
team_totals <- cfb_all %>% group_by(college_year, team) %>%
  summarize(team_rec      = sum(receiving_rec, na.rm = TRUE),
            team_rec_yds  = sum(receiving_yds, na.rm = TRUE),
            team_rec_td   = sum(receiving_td, na.rm = TRUE),
            team_pass_att = sum(passing_att, na.rm = TRUE), .groups = "drop")

cfb_all <- cfb_all %>% mutate(name_key = norm_name(player), school_key = norm_school(team))
dp <- te_draft %>% mutate(name_key = norm_name(pfr_player_name), school_key = norm_school(college))
offensive_pos <- c("TE", "?", "WR", "FB", "OL", "OT", "QB", "ATH", "RB", "DE", "DL")

pick_best <- function(cand_df, method, require_school = FALSE) {
  cand_df %>%
    mutate(sk  = ifelse(is.na(school_key) | school_key == "", "@@none@@", school_key),
           skc = ifelse(is.na(school_key_cfb) | school_key_cfb == "", "@@none@@", school_key_cfb),
           school_match = sk == skc | str_detect(skc, fixed(sk)) | str_detect(sk, fixed(skc)),
           is_te = cfb_position %in% c("TE")) %>%
    filter(school_match | cfb_position %in% offensive_pos) %>%
    filter(!require_school | school_match) %>%
    group_by(pfr_player_name, season, pick) %>%
    mutate(n_candidates = n_distinct(athlete_id)) %>%
    arrange(desc(school_match), year_offset, desc(is_te), desc(coalesce(receiving_rec, 0)), .by_group = TRUE) %>%
    slice(1) %>% ungroup() %>%
    transmute(season, pick, pfr_player_name, athlete_id, match_year_offset = year_offset,
              match_school_ok = school_match, match_cfb_position = cfb_position,
              match_n_candidates = n_candidates, match_method = method)
}
cfb_keys <- cfb_all %>% select(name_key, college_year, athlete_id, team, conference,
                               cfb_position = position, school_key_cfb = school_key, receiving_rec) %>%
  mutate(last_key = word(name_key, -1))
# a TE may have missed his final college season (injury) or had no stats in it: look back up to 3 years
dp_years <- bind_rows(dp %>% mutate(college_year = season - 1L, year_offset = 1L),
                      dp %>% mutate(college_year = season - 2L, year_offset = 2L),
                      dp %>% mutate(college_year = season - 3L, year_offset = 3L))

cands <- dp_years %>% inner_join(cfb_keys %>% select(-last_key), by = c("name_key", "college_year"),
                                 relationship = "many-to-many") %>% pick_best("auto_name")
unmatched_keys <- anti_join(dp, cands, by = c("season", "pick", "pfr_player_name"))
cands2 <- dp_years %>% semi_join(unmatched_keys, by = c("season", "pick", "pfr_player_name")) %>%
  mutate(last_key = word(name_key, -1)) %>%
  inner_join(cfb_keys %>% select(-name_key), by = c("last_key", "college_year"), relationship = "many-to-many") %>%
  filter(cfb_position %in% offensive_pos) %>%
  pick_best("auto_lastname_school", require_school = TRUE) %>% filter(match_n_candidates == 1)
cands <- bind_rows(cands, cands2)
dp <- dp %>% left_join(cands, by = c("season", "pick", "pfr_player_name"))
cat("pass 1 (name) matches:", nrow(cands) - nrow(cands2), " pass 2 (last name + school):", nrow(cands2), "\n")

if (file.exists("manual_matches.csv")) {
  mm <- read.csv("manual_matches.csv", stringsAsFactors = FALSE)
  cat("applying", nrow(mm), "manual matches\n")
  idx <- match(dp$pfr_player_id, mm$pfr_player_id); hit <- !is.na(idx)
  dp$athlete_id[hit] <- mm$athlete_id[idx[hit]]; dp$match_method[hit] <- "manual"
}
cat("matched:", sum(!is.na(dp$athlete_id)), "of", nrow(dp), "drafted TEs\n")

# --- Full college career by athlete_id, seasons before the draft only ----------
career <- dp %>% filter(!is.na(athlete_id)) %>%
  select(gsis_id, pfr_player_id, pfr_player_name, draft_season = season, pick, athlete_id) %>%
  inner_join(cfb_all %>% select(athlete_id, college_year, team, conference, cfb_position = position,
                                rec = receiving_rec, rec_yds = receiving_yds, rec_td = receiving_td,
                                car = rushing_car, rush_yds = rushing_yds),
             by = "athlete_id", relationship = "many-to-many") %>%
  filter(college_year < draft_season) %>%
  left_join(team_totals, by = c("college_year", "team")) %>%
  mutate(across(c(rec, rec_yds, rec_td, car, rush_yds), ~ coalesce(.x, 0)),
         ypr            = ifelse(rec >= 8, rec_yds / rec, NA_real_),
         rec_share      = ifelse(team_rec >= 60, pmin(1, rec / team_rec), NA_real_),
         rec_yds_share  = ifelse(team_rec_yds >= 600, pmin(1, pmax(0, rec_yds) / team_rec_yds), NA_real_),
         rec_td_share   = ifelse(team_rec_td >= 5, pmin(1, rec_td / team_rec_td), NA_real_),
         # receiving dominator: mean of yards share and TD share (as in the WR model)
         dominator      = ifelse(is.na(rec_yds_share), NA_real_, (rec_yds_share + coalesce(rec_td_share, rec_yds_share)) / 2),
         yds_per_team_att = ifelse(team_pass_att >= 150, rec_yds / team_pass_att, NA_real_),
         power5 = conference %in% c("SEC", "Big Ten", "Big 12", "ACC", "Pac-12") | team == "Notre Dame")

# cfbd PPA and usage (cached by the WR work; rows exist from the 2013 season)
ppa <- ppa_raw %>% transmute(athlete_id = as.character(athlete_id), college_year = season,
                             ppa_all = avg_PPA_all, ppa_pass = avg_PPA_pass, ppa_plays = countable_plays) %>%
  distinct(athlete_id, college_year, .keep_all = TRUE)
usg_cols <- intersect(c("usg_overall", "usg_pass"), names(usage_raw))
usg <- usage_raw %>% transmute(athlete_id = as.character(athlete_id), college_year = season,
                               across(all_of(usg_cols))) %>%
  distinct(athlete_id, college_year, .keep_all = TRUE)
career <- career %>% mutate(athlete_id = as.character(athlete_id)) %>%
  left_join(ppa, by = c("athlete_id", "college_year")) %>%
  left_join(usg, by = c("athlete_id", "college_year"))

# Birth dates -> age at draft and age on Sept 1 of each college season
bd <- players_raw %>% transmute(gsis_id, pfr_id, birth_date = as.Date(birth_date)) %>% filter(!is.na(birth_date))
dp <- dp %>%
  left_join(bd %>% filter(!is.na(gsis_id)) %>% select(gsis_id, birth_date) %>% distinct(gsis_id, .keep_all = TRUE),
            by = "gsis_id", na_matches = "never") %>%
  left_join(bd %>% filter(!is.na(pfr_id)) %>% select(pfr_id, birth_date_pfr = birth_date) %>%
              distinct(pfr_id, .keep_all = TRUE), by = c("pfr_player_id" = "pfr_id"), na_matches = "never") %>%
  mutate(birth_date = coalesce(birth_date, birth_date_pfr),
         age_at_draft = as.numeric(as.Date(paste0(season, "-04-25")) - birth_date) / 365.25) %>%
  select(-birth_date_pfr)
career <- career %>%
  left_join(dp %>% select(pfr_player_name, season, pick, birth_date),
            by = c("pfr_player_name", "draft_season" = "season", "pick")) %>%
  mutate(age_sept1 = as.numeric(as.Date(paste0(college_year, "-09-01")) - birth_date) / 365.25) %>%
  arrange(draft_season, pick, college_year)

# Combine (pfr id first, then name + year)
ht_to_inches <- function(ht) sapply(strsplit(as.character(ht), "-"), function(p)
  if (length(p) == 2) as.numeric(p[1]) * 12 + as.numeric(p[2]) else NA_real_)
cb <- combine_raw %>% transmute(pfr_id, cb_name_key = norm_name(player_name), cb_season = season,
                                height_in = ht_to_inches(ht), weight_lb = wt, forty, bench, vertical,
                                broad_jump, cone, shuttle)
by_id <- dp %>% select(pfr_player_id) %>% filter(!is.na(pfr_player_id)) %>%
  inner_join(cb %>% filter(!is.na(pfr_id)) %>% distinct(pfr_id, .keep_all = TRUE), by = c("pfr_player_id" = "pfr_id")) %>%
  select(-cb_name_key, -cb_season)
dp <- dp %>% left_join(by_id, by = "pfr_player_id")
need <- is.na(dp$height_in) & is.na(dp$forty) & is.na(dp$weight_lb)
if (any(need)) {
  by_name <- dp[need, c("name_key", "season")] %>%
    left_join(cb %>% distinct(cb_name_key, cb_season, .keep_all = TRUE), by = c("name_key" = "cb_name_key", "season" = "cb_season"))
  for (v in c("height_in", "weight_lb", "forty", "bench", "vertical", "broad_jump", "cone", "shuttle")) dp[[v]][need] <- by_name[[v]]
}
dp$combine_invited <- !(is.na(dp$height_in) & is.na(dp$weight_lb) & is.na(dp$forty))

# Recruiting (by cfbd athlete_id)
if (nrow(recruit_raw) > 0 && "athlete_id" %in% names(recruit_raw)) {
  rec <- recruit_raw %>% filter(!is.na(athlete_id)) %>% mutate(athlete_id = as.character(athlete_id)) %>%
    group_by(athlete_id) %>% slice_max(rating, n = 1, with_ties = FALSE) %>% ungroup() %>%
    transmute(athlete_id, recruit_stars = stars, recruit_rating = rating, recruit_rank = ranking)
  dp <- dp %>% mutate(athlete_id = as.character(athlete_id)) %>% left_join(rec, by = "athlete_id")
} else cat("recruiting data unavailable -- skipped\n")
dp$athlete_id <- as.character(dp$athlete_id)

last_nfl_season <- 2025
dp <- dp %>% mutate(nfl_years_complete = pmax(0, pmin(3, last_nfl_season - season + 1)),
                    full_3yr_outcome = nfl_years_complete == 3)

saveRDS(as.data.frame(career), "te_college_seasons.rds")
saveRDS(as.data.frame(dp), "te_base.rds")
cat("saved te_base.rds (", nrow(dp), "rows ) and te_college_seasons.rds (", nrow(career), "rows )\n")

# =============================================================================
# PART 3: Validate
# =============================================================================
te <- as.data.frame(dp); cs <- as.data.frame(career)
check <- function(label, ok, detail = "") { cat(sprintf("[%s] %s %s\n", ifelse(ok, "PASS", "FAIL"), label, detail)); invisible(ok) }

cat("\n===== Match rate =====\n")
match_rate <- mean(!is.na(te$athlete_id))
check("college match rate >= 95%", match_rate >= 0.95, sprintf("(%.1f%%)", 100 * match_rate))
print(as.data.frame(te %>% group_by(season) %>% summarize(n = n(), matched = sum(!is.na(athlete_id)), .groups = "drop")), row.names = FALSE)
cat("match rate by round:\n")
print(as.data.frame(te %>% group_by(round) %>% summarize(n = n(), pct = round(100 * mean(!is.na(athlete_id)), 1))), row.names = FALSE)
cat("match method:\n"); print(table(te$match_method, useNA = "ifany"))

cat("\n===== Uniqueness and leakage =====\n")
check("one row per drafted TE", !any(duplicated(te[, c("season", "pick")])))
check("no college season on/after draft year", all(cs$college_year < cs$draft_season))
check("one athlete_id per drafted TE", !any(duplicated(te$athlete_id[!is.na(te$athlete_id)])))
fs <- cs %>% group_by(draft_season, pick) %>% slice_max(college_year, n = 1) %>% ungroup()
check("matched final season has a catch for 90%+",
      mean(fs$rec >= 1) >= 0.9, sprintf("(%.1f%%)", 100 * mean(fs$rec >= 1)))

cat("\n===== Ranges =====\n")
check("rec share within [0, 1]", all(is.na(cs$rec_share) | (cs$rec_share >= 0 & cs$rec_share <= 1)))
check("dominator within [0, 1]", all(is.na(cs$dominator) | (cs$dominator >= 0 & cs$dominator <= 1)))
check("age at draft within 20-29", all(is.na(te$age_at_draft) | (te$age_at_draft > 20 & te$age_at_draft < 29)))
cat("birth date coverage:", round(100 * mean(!is.na(te$birth_date)), 1), "%\n")
cat("combine invite rate:", round(100 * mean(te$combine_invited), 1), "%\n")
cat("drill missingness among invitees:\n")
print(round(100 * colMeans(is.na(te[te$combine_invited, c("height_in", "weight_lb", "forty", "vertical", "broad_jump", "cone", "shuttle")])), 1))
if ("recruit_stars" %in% names(te)) cat("recruiting coverage:", round(100 * mean(!is.na(te$recruit_stars)), 1), "%\n")
cat("final-season PPA coverage (classes 2014+):",
    round(100 * mean(!is.na(fs$ppa_pass[fs$draft_season >= 2014])), 1), "%\n")

cat("\n===== Final college season summary =====\n")
print(summary(fs[, c("rec", "rec_yds", "rec_td", "ypr", "rec_share", "dominator", "age_sept1")]))

unmatched <- te %>% filter(is.na(athlete_id)) %>% select(season, round, pick, pfr_player_name, college, pfr_player_id)
write.csv(unmatched, "unmatched_tes.csv", row.names = FALSE)
cat("\nunmatched_tes.csv:", nrow(unmatched), "rows\n"); if (nrow(unmatched)) print(unmatched, row.names = FALSE)
suspicious <- te %>% filter(!is.na(athlete_id), coalesce(match_method, "") != "manual",
                            !match_school_ok | !(coalesce(match_cfb_position, "") %in% c("TE")) | match_n_candidates > 1) %>%
  select(season, round, pick, pfr_player_name, college, athlete_id, match_school_ok, match_cfb_position,
         match_n_candidates, match_method)
write.csv(suspicious, "suspicious_matches.csv", row.names = FALSE)
cat("suspicious_matches.csv:", nrow(suspicious), "rows\n"); if (nrow(suspicious)) print(suspicious, row.names = FALSE)
lowrec <- fs %>% filter(rec < 10) %>% select(draft_season, pick, pfr_player_name, college_year, team, rec, rec_yds)
if (nrow(lowrec)) { cat("\nfinal seasons under 10 catches (blocking TE / injury / bad match?):\n"); print(as.data.frame(lowrec), row.names = FALSE) }
check("Phase 1 ready for Phase 2", match_rate >= 0.95)
