# =============================================================================
# WR Model -- Phase 9: undrafted free-agent (UDFA) WRs
#
# Adds UDFA WRs (rookie seasons 2010-2025, never drafted, >= 1 regular-season NFL
# game) to the draft-time models and the year-2 breakout model.
#
#   PART 1  UDFA list from the cached nflreadr players table (position WR,
#           no draft pick, rookie_season 2010-2025, appeared in weekly stats).
#   PART 2  College match with the Phase 1 matcher (copied), full college career,
#           Phase 2 college / combine / recruiting features (copied).
#           Draft capital: pick = 262 sentinel, round = 8, undrafted = 1.
#   PART 3  Outcomes years 1-3 (PPR, top-24 hit, best finish -> WR3+/WR2+).
#   PART 4  Draft-time models, rolling origin (test 2016-2023, train <= Y - 3):
#           pre-draft and post-draft elastic nets trained WITH vs WITHOUT UDFAs,
#           evaluated on drafted players (comparable) and on everyone.
#           Hidden-talent back-test on the Day-3 + UDFA pool.
#   PART 5  Year-2 breakout model (Phase 7 features, copied) with UDFAs who
#           played as rookies; rolling origin (train <= Y - 2). Does it catch
#           UDFA breakouts? Board for 2025 UDFAs (year 2) and 2024 UDFAs.
#
# Inputs: cache/ (players_raw, cfbd_stats_2004_2025, combine_raw, recruiting_wr_raw,
#         nfl_weekly_raw, snap_counts_raw), wr_model_table.rds
# Outputs: wr_udfa_table.rds, phase9_udfa_list.csv, phase9_metrics.csv,
#          phase9_year2_metrics.csv, wr_udfa_board.csv
# =============================================================================

suppressMessages({ library(dplyr); library(tidyr); library(stringr); library(glmnet); library(pROC) })
set.seed(2026)
UDFA_PICK <- 262; LAST <- 2025; CAPR <- 100

players <- readRDS("cache/players_raw.rds")
cfb_all <- readRDS("cache/cfbd_stats_2004_2025.rds")
combine_raw <- readRDS("cache/combine_raw.rds")
recruit_raw <- readRDS("cache/recruiting_wr_raw.rds")
weekly  <- readRDS("cache/nfl_weekly_raw.rds") %>% filter(season_type == "REG", season <= LAST)
snaps   <- readRDS("cache/snap_counts_raw.rds") %>% filter(game_type == "REG", season <= LAST)
drafted <- readRDS("wr_model_table.rds")

# =============================================================================
# PART 1: UDFA list
# =============================================================================
wr_games <- weekly %>% filter(position == "WR") %>% distinct(player_id)
udfa <- players %>%
  filter(position == "WR", is.na(draft_pick), !is.na(rookie_season),
         rookie_season >= 2010, rookie_season <= LAST, gsis_id %in% wr_games$player_id,
         !(gsis_id %in% drafted$gsis_id)) %>%
  transmute(season = as.integer(rookie_season), round = 8L, pick = UDFA_PICK + row_number() / 1e4,
            team = NA_character_, gsis_id, pfr_player_id = pfr_id, cfb_player_id = NA_character_,
            pfr_player_name = display_name, position = "WR", college = college_name,
            birth_date = as.Date(birth_date))
# `pick` gets a tiny unique offset so (season, pick) stays a unique key; log_pick uses 262.
cat("UDFA WRs with >= 1 NFL regular-season game as WR, rookie seasons 2010-2025:", nrow(udfa), "\n")
print(table(udfa$season))

# =============================================================================
# PART 2: College match (Phase 1 matcher, copied)
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
  "miami oh" = "miami oh", "pittsburgh" = "pittsburgh", "north carolina state" = "nc state",
  "louisianamonroe" = "ul monroe", "louisianalafayette" = "louisiana",
  "middle tennessee state" = "middle tennessee", "florida international" = "fiu",
  "massachusetts" = "umass", "connecticut" = "uconn", "hawaii" = "hawaii",
  "middle tenn state" = "middle tennessee", "lamonroe" = "ul monroe", "alabirmingham" = "uab",
  "se missouri state" = "southeast missouri state", "lalafayette" = "louisiana", "east central ok" = "east central"
)
norm_school <- function(x) {
  s <- x %>% str_to_lower() %>% str_replace_all("\\bst\\.?$", "state") %>%
    str_replace_all("\\bst\\.?\\s", "state ") %>% str_replace_all("[^a-z ]", "") %>% str_squish()
  ifelse(s %in% names(school_alias), unname(school_alias[s]), s)
}
team_totals <- cfb_all %>% group_by(college_year, team) %>%
  summarize(team_rec_yds = sum(receiving_yds, na.rm = TRUE), team_rec_td = sum(receiving_td, na.rm = TRUE),
            team_rec = sum(receiving_rec, na.rm = TRUE), team_pass_att = sum(passing_att, na.rm = TRUE), .groups = "drop")
cfb_all <- cfb_all %>% mutate(name_key = norm_name(player), school_key = norm_school(team))
dp <- udfa %>% mutate(name_key = norm_name(pfr_player_name), school_key = norm_school(college))
offensive_pos <- c("WR", "TE", "RB", "?")
pick_best <- function(cand_df, method, require_school = FALSE) {
  cand_df %>%
    mutate(sk  = ifelse(is.na(school_key) | school_key == "", "@@none@@", school_key),
           skc = ifelse(is.na(school_key_cfb) | school_key_cfb == "", "@@none@@", school_key_cfb),
           school_match = sk == skc | str_detect(skc, fixed(sk)) | str_detect(sk, fixed(skc)),
           is_wr = cfb_position %in% "WR") %>%
    filter(school_match | cfb_position %in% offensive_pos) %>%
    filter(!require_school | school_match) %>%
    group_by(pfr_player_name, season, pick) %>%
    mutate(n_candidates = n_distinct(athlete_id)) %>%
    arrange(desc(school_match), year_offset, desc(is_wr), desc(coalesce(receiving_yds, 0)), .by_group = TRUE) %>%
    slice(1) %>% ungroup() %>%
    transmute(season, pick, pfr_player_name, athlete_id, match_year_offset = year_offset,
              match_school_ok = school_match, match_cfb_position = cfb_position,
              match_n_candidates = n_candidates, match_method = method)
}
cfb_keys <- cfb_all %>% select(name_key, college_year, athlete_id, team, conference,
                               cfb_position = position, school_key_cfb = school_key, receiving_yds) %>%
  mutate(last_key = word(name_key, -1))
dp_years <- bind_rows(dp %>% mutate(college_year = season - 1L, year_offset = 1L),
                      dp %>% mutate(college_year = season - 2L, year_offset = 2L))
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
# a college player already matched to a drafted WR can't also be a UDFA
dup <- !is.na(dp$athlete_id) & as.character(dp$athlete_id) %in% as.character(drafted$athlete_id)
dp$athlete_id[dup] <- NA
dp$athlete_id[duplicated(dp$athlete_id) & !is.na(dp$athlete_id)] <- NA
cat("college match: pass 1", nrow(cands) - nrow(cands2), " pass 2", nrow(cands2),
    " matched", sum(!is.na(dp$athlete_id)), "of", nrow(dp),
    sprintf("(%.1f%%)", 100 * mean(!is.na(dp$athlete_id))), "\n")
print(dp %>% group_by(season) %>% summarize(n = n(), matched = sum(!is.na(athlete_id)), .groups = "drop") %>%
        as.data.frame(), row.names = FALSE)

career <- dp %>% filter(!is.na(athlete_id)) %>%
  select(gsis_id, pfr_player_id, pfr_player_name, draft_season = season, pick, athlete_id) %>%
  inner_join(cfb_all %>% select(athlete_id, college_year, team, conference, cfb_position = position,
                                rec = receiving_rec, rec_yds = receiving_yds, rec_td = receiving_td,
                                rush_car = rushing_car, rush_yds = rushing_yds, rush_td = rushing_td),
             by = "athlete_id", relationship = "many-to-many") %>%
  filter(college_year < draft_season) %>%
  left_join(team_totals, by = c("college_year", "team")) %>%
  mutate(across(c(rec, rec_yds, rec_td, rush_car, rush_yds, rush_td), ~ coalesce(.x, 0)),
         yds_share = ifelse(team_rec_yds > 0, pmax(0, rec_yds) / team_rec_yds, NA_real_),
         td_share  = ifelse(team_rec_td  > 0, rec_td / team_rec_td, NA_real_),
         dominator = ifelse(is.na(td_share), yds_share, (yds_share + td_share) / 2),
         yptpa     = ifelse(team_pass_att >= 100, pmax(0, rec_yds) / team_pass_att, NA_real_),
         power5    = conference %in% c("SEC", "Big Ten", "Big 12", "ACC", "Pac-12") | team == "Notre Dame") %>%
  left_join(dp %>% select(season, pick, birth_date), by = c("draft_season" = "season", "pick")) %>%
  mutate(age_sept1 = as.numeric(as.Date(paste0(college_year, "-09-01")) - birth_date) / 365.25)

# Phase 2 college features (copied)
col_feat <- career %>% group_by(draft_season, pick) %>% arrange(college_year, .by_group = TRUE) %>%
  summarize(final_rec = last(rec), final_rec_yds = last(rec_yds), final_rec_td = last(rec_td),
            final_yds_share = last(yds_share), final_td_share = last(td_share),
            final_dominator = last(dominator), final_yptpa = last(yptpa), final_power5 = last(power5),
            final_conference = last(conference),
            best_dominator = suppressWarnings(max(dominator, na.rm = TRUE)),
            best_yds_share = suppressWarnings(max(yds_share, na.rm = TRUE)),
            career_rec = sum(rec), career_rec_yds = sum(rec_yds), career_rush_yds = sum(rush_yds),
            college_seasons = n_distinct(college_year), college_teams = n_distinct(team),
            broke_out = as.integer(any(dominator >= 0.20, na.rm = TRUE)),
            breakout_age = suppressWarnings(min(age_sept1[dominator >= 0.20], na.rm = TRUE)),
            final_age = last(age_sept1), .groups = "drop") %>%
  mutate(across(c(best_dominator, best_yds_share, breakout_age), ~ ifelse(is.infinite(.x), NA, .x)),
         breakout_age_filled = ifelse(broke_out == 1, breakout_age, final_age + 1),
         transferred = as.integer(college_teams > 1))

# Combine (pfr id, then name + year) -- copied
ht_to_inches <- function(ht) sapply(strsplit(as.character(ht), "-"), function(p)
  if (length(p) == 2) as.numeric(p[1]) * 12 + as.numeric(p[2]) else NA_real_)
cb <- combine_raw %>% transmute(pfr_id, cb_name_key = norm_name(player_name), cb_season = season,
                                height_in = ht_to_inches(ht), weight_lb = wt, forty, bench, vertical,
                                broad_jump, cone, shuttle)
by_id <- dp %>% select(pfr_player_id) %>% filter(!is.na(pfr_player_id)) %>%
  inner_join(cb %>% filter(!is.na(pfr_id)) %>% distinct(pfr_id, .keep_all = TRUE), by = c("pfr_player_id" = "pfr_id")) %>%
  select(-cb_name_key, -cb_season) %>% distinct(pfr_player_id, .keep_all = TRUE)
dp <- dp %>% left_join(by_id, by = "pfr_player_id")
need <- is.na(dp$height_in) & is.na(dp$forty) & is.na(dp$weight_lb)
if (any(need)) {
  by_name <- dp[need, c("name_key", "season")] %>%
    left_join(cb %>% distinct(cb_name_key, cb_season, .keep_all = TRUE), by = c("name_key" = "cb_name_key", "season" = "cb_season"))
  for (v in c("height_in", "weight_lb", "forty", "bench", "vertical", "broad_jump", "cone", "shuttle")) dp[[v]][need] <- by_name[[v]]
}
dp$combine_invited <- !(is.na(dp$height_in) & is.na(dp$weight_lb) & is.na(dp$forty))
rec <- recruit_raw %>% filter(!is.na(athlete_id)) %>% mutate(athlete_id = as.character(athlete_id)) %>%
  group_by(athlete_id) %>% slice_max(rating, n = 1, with_ties = FALSE) %>% ungroup() %>%
  select(athlete_id, recruit_stars = stars, recruit_rating = rating, recruit_rank = ranking)
dp <- dp %>% mutate(athlete_id = as.character(athlete_id)) %>% left_join(rec, by = "athlete_id")

# =============================================================================
# PART 3: Outcomes, years 1-3
# =============================================================================
season_tot <- weekly %>% group_by(player_id, season) %>%
  summarize(position = first(position), ppr = sum(fantasy_points_ppr, na.rm = TRUE),
            games = n_distinct(week), .groups = "drop")
wr_rank <- season_tot %>% filter(position == "WR") %>% group_by(season) %>%
  mutate(wr_rank = rank(-ppr, ties.method = "min")) %>% ungroup() %>% select(player_id, season, wr_rank)
season_tot <- season_tot %>% left_join(wr_rank, by = c("player_id", "season"))
outcomes <- function(d) {
  d %>% select(gsis_id, draft_season, pick) %>% crossing(nfl_year = 1:3) %>%
    mutate(season = draft_season + nfl_year - 1) %>% filter(season <= LAST) %>%
    left_join(season_tot, by = c("gsis_id" = "player_id", "season")) %>%
    mutate(ppr = coalesce(ppr, 0), games = coalesce(games, 0L), fin = pmin(coalesce(wr_rank, CAPR), CAPR)) %>%
    group_by(draft_season, pick) %>%
    summarize(n_years_obs = n(), total_ppr_3yr = sum(ppr), hit_3yr = as.integer(any(fin <= 24)),
              best_finish_3yr = min(fin), yr1_games = sum(games[nfl_year == 1]), .groups = "drop") %>%
    mutate(across(c(total_ppr_3yr, hit_3yr, best_finish_3yr), ~ ifelse(n_years_obs == 3, .x, NA)))
}
u <- dp %>% rename(draft_season = season, draft_team = team) %>%
  left_join(col_feat, by = c("draft_season", "pick")) %>%
  left_join(outcomes(dp %>% rename(draft_season = season)), by = c("draft_season", "pick")) %>%
  mutate(age_at_draft = as.numeric(as.Date(paste0(draft_season, "-04-25")) - birth_date) / 365.25,
         log_pick = log(UDFA_PICK), day3 = 1L, undrafted = 1L,
         speed_score = ifelse(!is.na(forty) & !is.na(weight_lb), weight_lb * 200 / forty^4, NA_real_),
         college_matched = as.integer(!is.na(athlete_id)),
         early_declare = as.integer(college_seasons <= 3 | (!is.na(age_at_draft) & age_at_draft < 21.5)),
         vacated_target_share = NA_real_, team_targets_prev = NA_real_)
for (dd in c("forty", "vertical", "broad_jump", "cone", "shuttle", "bench")) u[[paste0("miss_", dd)]] <- as.integer(is.na(u[[dd]]))
saveRDS(as.data.frame(u), "wr_udfa_table.rds")

cat("\nUDFAs with a full 3-year window (rookie season <= 2023):", sum(!is.na(u$total_ppr_3yr)), "\n")
cat("WR3+ (top-36) season in years 1-3:", sum(u$best_finish_3yr <= 36, na.rm = TRUE),
    "| WR2+ (top-24):", sum(u$best_finish_3yr <= 24, na.rm = TRUE), "\n")
hits <- u %>% filter(best_finish_3yr <= 36) %>% arrange(best_finish_3yr) %>%
  select(draft_season, pfr_player_name, college, college_matched, best_finish_3yr, total_ppr_3yr)
print(as.data.frame(hits), row.names = FALSE)
write.csv(u %>% select(draft_season, pfr_player_name, college, gsis_id, pfr_player_id, athlete_id, match_method,
                       college_matched, best_finish_3yr, total_ppr_3yr, yr1_games),
          "phase9_udfa_list.csv", row.names = FALSE)

# =============================================================================
# PART 4: Draft-time models with vs without UDFAs (rolling origin)
# =============================================================================
best_fin_drafted <- read.csv("phase5_finish_targets.csv") %>%
  transmute(draft_season, pick, best_finish_3yr = pmin(finish_y1, finish_y2, finish_y3))
dr <- drafted %>% left_join(best_fin_drafted, by = c("draft_season", "pick")) %>% mutate(undrafted = 0L)
common <- c("draft_season", "round", "pick", "pfr_player_name", "undrafted", "total_ppr_3yr", "hit_3yr", "best_finish_3yr",
            "log_pick", "vacated_target_share", "team_targets_prev",
            "age_at_draft", "final_dominator", "best_dominator", "final_yptpa", "breakout_age_filled",
            "career_rec_yds", "college_seasons", "height_in", "weight_lb", "recruit_rating",
            "broke_out", "transferred", "early_declare", "final_power5", "college_matched", "combine_invited",
            "miss_forty", "miss_vertical", "miss_broad_jump", "forty", "vertical", "broad_jump", "speed_score")
allp <- bind_rows(dr %>% select(all_of(common)) %>% mutate(across(c(final_power5, combine_invited), as.integer)),
                  u %>% select(all_of(common)) %>% mutate(across(c(final_power5, combine_invited), as.integer))) %>%
  mutate(wr3 = as.integer(best_finish_3yr <= 36))
trn <- allp %>% filter(!is.na(total_ppr_3yr), draft_season <= 2023)

drills   <- c("forty", "vertical", "broad_jump", "speed_score")
pre_num  <- c("age_at_draft", "final_dominator", "best_dominator", "final_yptpa", "breakout_age_filled",
              "career_rec_yds", "college_seasons", "height_in", "weight_lb", "recruit_rating")
pre_flag <- c("broke_out", "transferred", "early_declare", "final_power5", "college_matched",
              "combine_invited", "miss_forty", "miss_vertical", "miss_broad_jump", "undrafted")
post_num <- c("log_pick", "vacated_target_share", "team_targets_prev")
fit_prep <- function(d, num) {
  med <- sapply(c(num, drills), function(v) median(d[[v]], na.rm = TRUE))
  flag <- num[sapply(num, function(v) any(is.na(d[[v]])))]
  dm <- as.matrix(d[, drills]); for (v in drills) dm[is.na(dm[, v]), v] <- med[v]
  list(num = num, med = med, flag = flag, pca = prcomp(dm, center = TRUE, scale. = TRUE))
}
apply_prep <- function(p, d) {
  out <- data.frame(row.names = seq_len(nrow(d)))
  for (v in p$num) { x <- d[[v]]; if (v %in% p$flag) out[[paste0("na_", v)]] <- as.integer(is.na(x)); x[is.na(x)] <- p$med[v]; out[[v]] <- x }
  dm <- as.matrix(d[, drills]); for (v in drills) dm[is.na(dm[, v]), v] <- p$med[v]
  pcs <- predict(p$pca, dm)[, 1:2, drop = FALSE]; out$athletic_pc1 <- pcs[, 1]; out$athletic_pc2 <- pcs[, 2]
  for (v in pre_flag) out[[v]] <- as.integer(coalesce(as.numeric(d[[v]]), 0))
  as.matrix(out)
}
fit_models <- function(tr, te) {
  o <- data.frame(row.names = seq_len(nrow(te)))
  o$pick_ppr <- pmax(0, predict(lm(total_ppr_3yr ~ log_pick + undrafted, tr), te))
  o$pick_wr3 <- predict(glm(wr3 ~ log_pick + undrafted, binomial, tr), te, type = "response")
  o$pick_hit <- predict(glm(hit_3yr ~ log_pick + undrafted, binomial, tr), te, type = "response")
  folds <- as.integer(factor(tr$draft_season))
  for (set in c("pre", "post")) {
    p <- fit_prep(tr, if (set == "pre") pre_num else c(pre_num, post_num))
    Xtr <- apply_prep(p, tr); Xte <- apply_prep(p, te)
    for (tg in c("ppr", "wr3", "hit")) {
      y <- switch(tg, ppr = tr$total_ppr_3yr, wr3 = tr$wr3, hit = tr$hit_3yr)
      fam <- if (tg == "ppr") "gaussian" else "binomial"
      f <- cv.glmnet(Xtr, y, family = fam, alpha = 0.5, foldid = folds)
      pr <- as.numeric(predict(f, Xte, s = "lambda.min", type = "response"))
      o[[paste0(set, "_", tg)]] <- if (tg == "ppr") pmax(0, pr) else pr
    }
  }
  o
}
roll <- list()
for (Y in 2016:2023) for (with_udfa in c(FALSE, TRUE)) {
  tr <- trn %>% filter(draft_season <= Y - 3, with_udfa | undrafted == 0)
  te <- trn %>% filter(draft_season == Y)                 # always score drafted + UDFA test players
  roll[[length(roll) + 1]] <- cbind(te %>% select(draft_season, round, pick, pfr_player_name, undrafted,
                                                  total_ppr_3yr, hit_3yr, wr3, best_finish_3yr),
                                    train_with_udfa = with_udfa, fit_models(tr, te))
}
roll <- bind_rows(roll)
aucf <- function(y, p) if (length(unique(y)) < 2) NA else as.numeric(auc(roc(y, p, quiet = TRUE)))
mrow <- function(o) bind_rows(lapply(c("pick", "pre", "post"), function(m) data.frame(
  model = m, n = nrow(o),
  Spearman_PPR = cor(o[[paste0(m, "_ppr")]], o$total_ppr_3yr, method = "spearman"),
  RMSE_PPR = sqrt(mean((o[[paste0(m, "_ppr")]] - o$total_ppr_3yr)^2)),
  AUC_hit = aucf(o$hit_3yr, o[[paste0(m, "_hit")]]), Brier_hit = mean((o[[paste0(m, "_hit")]] - o$hit_3yr)^2),
  AUC_WR3 = aucf(o$wr3, o[[paste0(m, "_wr3")]]), Brier_WR3 = mean((o[[paste0(m, "_wr3")]] - o$wr3)^2))))
met <- bind_rows(
  cbind(train = "drafted only", eval = "drafted test players", mrow(filter(roll, !train_with_udfa, undrafted == 0))),
  cbind(train = "drafted + UDFA", eval = "drafted test players", mrow(filter(roll, train_with_udfa, undrafted == 0))),
  cbind(train = "drafted only", eval = "all incl. UDFA", mrow(filter(roll, !train_with_udfa))),
  cbind(train = "drafted + UDFA", eval = "all incl. UDFA", mrow(filter(roll, train_with_udfa)))) %>%
  mutate(across(where(is.double), ~ round(.x, 4)))
cat("\n===== Draft-time models, rolling origin 2016-2023: with vs without UDFAs in training =====\n")
print(met, row.names = FALSE)
write.csv(met, "phase9_metrics.csv", row.names = FALSE)
cat("UDFA test players:", sum(roll$undrafted == 1 & roll$train_with_udfa), " of whom WR3+:",
    sum(roll$wr3[roll$undrafted == 1 & roll$train_with_udfa]), "\n")

# Hidden-talent back-test: Day-3 + UDFA pool, models trained WITH UDFAs
pool <- roll %>% filter(train_with_udfa, round >= 4)
cat("\n===== Hidden-talent back-test: Day-3 + UDFA pool (", nrow(pool), "players,", sum(pool$wr3),
    "reached WR3+ in yrs 1-3 ) =====\n")
topk <- function(col, k) pool %>% group_by(draft_season) %>% arrange(desc(.data[[col]]), pick, .by_group = TRUE) %>%
  slice_head(n = k) %>% summarize(hits = sum(wr3), names = paste(pfr_player_name[wr3 == 1], collapse = ", "), .groups = "drop")
for (k in c(5, 10)) {
  rnd <- pool %>% group_by(draft_season) %>% summarize(e = min(k, n()) * mean(wr3), .groups = "drop")
  pool$earliest <- -pool$pick
  r1 <- topk("pre_wr3", k); r2 <- topk("post_wr3", k); r3 <- topk("earliest", k)
  cat(sprintf("top %d per class -> pre-draft model: %d | post-draft model: %d | earliest picks: %d | random: %.1f\n",
              k, sum(r1$hits), sum(r2$hits), sum(r3$hits), sum(rnd$e)))
  cat("  pre-draft hits:", paste(r1$draft_season[r1$hits > 0], r1$names[r1$hits > 0], sep = ": ", collapse = " | "), "\n")
}
cat("all WR3+ in the pool:", paste0(pool$pfr_player_name[pool$wr3 == 1], " (", pool$draft_season[pool$wr3 == 1],
                                    ifelse(pool$undrafted[pool$wr3 == 1] == 1, ", UDFA", ""), ")", collapse = ", "), "\n")
uh <- pool %>% group_by(draft_season) %>% mutate(n_pool = n(), rank_pre = rank(-pre_wr3, ties.method = "min")) %>%
  ungroup() %>% filter(undrafted == 1, wr3 == 1) %>% select(draft_season, pfr_player_name, best_finish_3yr, pre_wr3, rank_pre, n_pool)
cat("UDFA WR3+ hits in test years -- pre-draft model rank within Day-3+UDFA pool:\n"); print(as.data.frame(uh), row.names = FALSE)

# =============================================================================
# PART 5: Year-2 breakout model with UDFAs (Phase 7 features, copied)
# =============================================================================
team_wk <- weekly %>% group_by(season, week, team) %>%
  summarize(team_tgt = sum(targets, na.rm = TRUE), team_ay = sum(pmax(receiving_air_yards, 0), na.rm = TRUE),
            team_att = sum(attempts, na.rm = TRUE), .groups = "drop")
team_season <- team_wk %>% group_by(season, team) %>% summarize(team_pass_att = sum(team_att), .groups = "drop")
wr_rank2 <- wr_rank %>% left_join(season_tot %>% select(player_id, season, ppr), by = c("player_id", "season"))
b2 <- bind_rows(
  drafted %>% filter(draft_season >= 2013) %>% mutate(undrafted = 0L) %>%
    select(gsis_id, pfr_player_id, pfr_player_name, draft_season, round, pick, log_pick, undrafted, age_at_draft,
           final_dominator, breakout_age_filled, career_rec_yds, recruit_rating, early_declare, college_matched),
  u %>% filter(draft_season >= 2013) %>%
    select(gsis_id, pfr_player_id, pfr_player_name, draft_season, round, pick, log_pick, undrafted, age_at_draft,
           final_dominator, breakout_age_filled, career_rec_yds, recruit_rating, early_declare, college_matched)) %>%
  filter(!is.na(gsis_id), draft_season <= LAST)
rk <- weekly %>% inner_join(b2 %>% select(gsis_id, draft_season), by = c("player_id" = "gsis_id")) %>%
  filter(season == draft_season) %>% left_join(team_wk, by = c("season", "week", "team"))
rookie <- rk %>% group_by(player_id) %>%
  summarize(r_ts_early = sum(targets[week < 10], na.rm = TRUE) / pmax(sum(team_tgt[week < 10]), 1),
            r_ts_late  = sum(targets[week >= 10], na.rm = TRUE) / pmax(sum(team_tgt[week >= 10]), 1),
            r_games_late = n_distinct(week[week >= 10]),
            r_ts  = sum(targets, na.rm = TRUE) / pmax(sum(team_tgt), 1),
            r_ays = sum(pmax(receiving_air_yards, 0), na.rm = TRUE) / pmax(sum(team_ay), 1),
            r_games = n_distinct(week), r_targets = sum(targets, na.rm = TRUE),
            r_rec = sum(receptions, na.rm = TRUE), r_yds = sum(receiving_yards, na.rm = TRUE),
            r_ppr = sum(fantasy_points_ppr, na.rm = TRUE),
            r_team = names(which.max(table(team))), .groups = "drop") %>%
  mutate(r_ppg = r_ppr / r_games, r_ypt = ifelse(r_targets > 0, r_yds / r_targets, NA),
         r_catch = ifelse(r_targets > 0, r_rec / r_targets, NA), r_wopr = 1.5 * r_ts + 0.7 * r_ays,
         r_ts_late = ifelse(r_games_late > 0, r_ts_late, NA), r_ts_trend = r_ts_late - r_ts_early)
sn <- snaps %>% filter(!is.na(pfr_player_id)) %>%
  inner_join(b2 %>% filter(!is.na(pfr_player_id)) %>% select(pfr_player_id, draft_season), by = "pfr_player_id") %>%
  filter(season == draft_season, offense_snaps > 0 | offense_pct > 0) %>%
  group_by(pfr_player_id) %>% arrange(week, .by_group = TRUE) %>%
  summarize(r_snap_avg = mean(offense_pct), r_snap_last6 = mean(tail(offense_pct, 6)),
            r_games50 = sum(offense_pct >= 0.5), .groups = "drop")
out23 <- b2 %>% select(gsis_id, draft_season) %>% crossing(nfl_year = 2:3) %>%
  mutate(season = draft_season + nfl_year - 1) %>% filter(season <= LAST) %>%
  left_join(wr_rank2, by = c("gsis_id" = "player_id", "season")) %>%
  mutate(finish = pmin(coalesce(wr_rank, CAPR), CAPR), ppr = coalesce(ppr, 0)) %>%
  group_by(gsis_id, draft_season) %>%
  summarize(n_obs = n(), y2_finish = finish[nfl_year == 2][1], best_23 = min(finish), ppr_23 = sum(ppr), .groups = "drop")
d2 <- b2 %>% inner_join(rookie, by = c("gsis_id" = "player_id")) %>% left_join(sn, by = "pfr_player_id") %>%
  left_join(wr_rank %>% select(player_id, season, r_finish = wr_rank), by = c("gsis_id" = "player_id", "draft_season" = "season")) %>%
  left_join(team_season, by = c("draft_season" = "season", "r_team" = "team")) %>%
  left_join(out23, by = c("gsis_id", "draft_season")) %>%
  mutate(r_finish = pmin(coalesce(r_finish, CAPR), CAPR), complete = !is.na(n_obs) & n_obs == 2,
         y_wr2 = as.integer(best_23 <= 24), y_wr3 = as.integer(best_23 <= 36))
tr2 <- d2 %>% filter(complete, draft_season <= 2023)
cat("\n===== Year-2 breakout with UDFAs =====\n")
cat("rookies who played (2013-2023):", nrow(tr2), " of which UDFA:", sum(tr2$undrafted),
    " UDFA WR3+ in yrs 2-3:", sum(tr2$y_wr3[tr2$undrafted == 1]), "\n")
cat("UDFA year-2/3 breakouts:", paste0(tr2$pfr_player_name[tr2$undrafted == 1 & tr2$y_wr3 == 1], " (", tr2$draft_season[tr2$undrafted == 1 & tr2$y_wr3 == 1],
                                        ", rookie WR", tr2$r_finish[tr2$undrafted == 1 & tr2$y_wr3 == 1], " -> best WR", tr2$best_23[tr2$undrafted == 1 & tr2$y_wr3 == 1], ")",
                                        collapse = ", "), "\n")
feats2 <- c("log_pick", "undrafted", "age_at_draft", "final_dominator", "breakout_age_filled", "career_rec_yds",
            "recruit_rating", "early_declare", "college_matched", "r_games", "r_targets", "r_rec", "r_yds", "r_ppr",
            "r_ppg", "r_ypt", "r_catch", "r_ts", "r_ays", "r_wopr", "r_ts_late", "r_ts_trend", "r_finish",
            "r_snap_avg", "r_snap_last6", "r_games50", "team_pass_att")
prep2 <- function(tr) { med <- sapply(feats2, function(v) median(as.numeric(tr[[v]]), na.rm = TRUE)); med[is.na(med)] <- 0
  list(med = med, flag = feats2[sapply(feats2, function(v) any(is.na(tr[[v]])))]) }
app2 <- function(p, x) {
  m <- sapply(feats2, function(v) { z <- as.numeric(x[[v]]); z[is.na(z)] <- p$med[v]; z })
  if (is.null(dim(m))) m <- matrix(m, nrow = 1, dimnames = list(NULL, feats2))
  if (length(p$flag)) { fl <- sapply(p$flag, function(v) as.integer(is.na(x[[v]]))); if (is.null(dim(fl))) fl <- matrix(fl, nrow = 1)
    colnames(fl) <- paste0("na_", p$flag); m <- cbind(m, fl) }
  m
}
pred2 <- function(tr, te) {
  o <- data.frame(row.names = seq_len(nrow(te)))
  o$pick_p3 <- predict(glm(y_wr3 ~ log_pick + undrafted, binomial, tr), te, type = "response")
  o$rpts_p3 <- predict(glm(y_wr3 ~ log_pick + undrafted + r_ppr, binomial, tr), te, type = "response")
  p <- prep2(tr); Xtr <- app2(p, tr); Xte <- app2(p, te)
  folds <- as.integer(factor(tr$draft_season)); if (max(folds) < 4) folds <- sample(rep(1:5, length.out = nrow(tr)))
  f3 <- cv.glmnet(Xtr, tr$y_wr3, family = "binomial", alpha = 0.5, foldid = folds)
  f2 <- cv.glmnet(Xtr, tr$y_wr2, family = "binomial", alpha = 0.5, foldid = folds)
  o$use_p3 <- as.numeric(predict(f3, Xte, s = "lambda.min", type = "response"))
  o$use_p2 <- pmin(as.numeric(predict(f2, Xte, s = "lambda.min", type = "response")), o$use_p3)
  o
}
r2 <- list()
for (Y in 2016:2023) for (wu in c(FALSE, TRUE)) {
  tr <- tr2 %>% filter(draft_season <= Y - 2, wu | undrafted == 0)
  te <- tr2 %>% filter(draft_season == Y)
  r2[[length(r2) + 1]] <- cbind(te %>% select(draft_season, pick, pfr_player_name, undrafted, round, r_finish, r_ppr, best_23, y_wr3),
                                train_with_udfa = wu, pred2(tr, te))
}
r2 <- bind_rows(r2)
m2 <- r2 %>% mutate(eval = ifelse(undrafted == 1, "UDFA test", "drafted test")) %>%
  bind_rows(r2 %>% mutate(eval = "all test")) %>%
  group_by(train_with_udfa, eval) %>%
  summarize(n = n(), hits = sum(y_wr3),
            AUC_pick = aucf(y_wr3, pick_p3), AUC_rookie_pts = aucf(y_wr3, rpts_p3), AUC_usage = aucf(y_wr3, use_p3),
            Brier_pick = mean((pick_p3 - y_wr3)^2), Brier_rookie_pts = mean((rpts_p3 - y_wr3)^2),
            Brier_usage = mean((use_p3 - y_wr3)^2), .groups = "drop") %>%
  mutate(across(where(is.double), ~ round(.x, 4)))
cat("\nyear-2 model, rolling origin 2016-2023 (WR3+ in years 2-3):\n"); print(as.data.frame(m2), row.names = FALSE)
write.csv(m2, "phase9_year2_metrics.csv", row.names = FALSE)
cat("\nUDFA breakouts in test years -- rank within their class (all rookies who played), trained with UDFAs:\n")
print(as.data.frame(r2 %>% filter(train_with_udfa) %>% group_by(draft_season) %>%
  mutate(n_class = n(), rank_usage = rank(-use_p3, ties.method = "min"), rank_rookie_pts = rank(-rpts_p3, ties.method = "min")) %>%
  ungroup() %>% filter(undrafted == 1, y_wr3 == 1) %>%
  select(draft_season, pfr_player_name, r_finish, best_23, use_p3, rank_usage, rank_rookie_pts, n_class) %>%
  mutate(use_p3 = round(use_p3, 3))), row.names = FALSE)
pool2 <- r2 %>% filter(train_with_udfa, round >= 4)
for (k in c(5, 10)) {
  t1 <- pool2 %>% group_by(draft_season) %>% arrange(desc(use_p3), .by_group = TRUE) %>% slice_head(n = k) %>% summarize(h = sum(y_wr3), .groups = "drop")
  t2 <- pool2 %>% group_by(draft_season) %>% arrange(desc(rpts_p3), .by_group = TRUE) %>% slice_head(n = k) %>% summarize(h = sum(y_wr3), .groups = "drop")
  rnd <- pool2 %>% group_by(draft_season) %>% summarize(e = min(k, n()) * mean(y_wr3), .groups = "drop")
  cat(sprintf("Day-3 + UDFA rookies, top %d per class reaching WR3+ in yrs 2-3: usage %d | rookie pts %d | random %.1f (pool %d, hits %d)\n",
              k, sum(t1$h), sum(t2$h), sum(rnd$e), nrow(pool2), sum(pool2$y_wr3)))
}

# --- UDFA board: 2025 UDFAs (year 2 outlook) and 2024 UDFAs ---------------------
sc <- d2 %>% filter(undrafted == 1, draft_season %in% c(2024, 2025))
if (nrow(sc) > 0) {
  pf <- pred2(tr2, sc)
  board <- bind_cols(sc %>% select(pfr_player_name, draft_season, r_games, r_targets, r_ts, r_ays, r_snap_avg, r_snap_last6,
                                   r_ppr, r_finish, college_matched), pf) %>%
    left_join(u %>% select(pfr_player_name, draft_season, college), by = c("pfr_player_name", "draft_season")) %>%
    mutate(across(where(is.double), ~ round(.x, 3)), usage_edge = round(use_p3 - rpts_p3, 3)) %>%
    arrange(desc(draft_season), desc(use_p3))
  write.csv(board, "wr_udfa_board.csv", row.names = FALSE)
  cat("\n===== UDFA board: top 10 by P(WR3+ in years 2-3) =====\n")
  print(as.data.frame(board %>% group_by(draft_season) %>% slice_head(n = 10) %>% ungroup() %>%
    select(draft_season, pfr_player_name, college, r_games, r_targets, r_ts, r_snap_avg, r_ppr, r_finish, use_p3, rpts_p3, usage_edge)),
    row.names = FALSE)
}
cat("\nsaved wr_udfa_table.rds, phase9_udfa_list.csv, phase9_metrics.csv, phase9_year2_metrics.csv, wr_udfa_board.csv\n")
