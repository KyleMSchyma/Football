# =============================================================================
# TE Model -- NFL usage helpers, sourced by Phases 5-7
#   te_season_rank: every TE's season PPR points and TE rank (regular season)
#   usage_year(base, k): one row per player in `base` with his NFL year-k usage:
#     games, targets / receptions per game, share of team targets (and nflverse
#     target share and air-yards share), WOPR, yards per target, receiving EPA
#     per target, catch rate, aDOT, TDs per game, PPR points and per game, TE
#     finish (capped at 60), TD share of his points, late-season (weeks 10+)
#     targets and points per game, offensive snap share (season and last 6
#     games; snap counts exist from 2013). Players who did not play get 0 for
#     volume and NA for efficiency (imputed in-fold with a missing flag).
# =============================================================================
LAST <- 2025; CAP <- 60
team_map <- c(GNB = "GB", KAN = "KC", NOR = "NO", NWE = "NE", SFO = "SF", TAM = "TB",
              LAR = "LA", RAM = "LA", STL = "LA", LVR = "LV", OAK = "LV", SDG = "LAC", SD = "LAC")
fix_team <- function(x) ifelse(x %in% names(team_map), unname(team_map[x]), x)

weekly <- readRDS(file.path("..", "Football2", "cache", "nfl_weekly_raw.rds")) %>%
  filter(season_type == "REG", season <= LAST) %>% mutate(team = fix_team(team))
snaps <- readRDS(file.path("..", "Football2", "cache", "snap_counts_raw.rds")) %>%
  filter(game_type == "REG", season <= LAST) %>%
  select(pfr_player_id, season, week, offense_pct)

season_tot <- weekly %>% group_by(player_id, season) %>%
  summarize(position = first(position), pts = sum(fantasy_points_ppr, na.rm = TRUE), .groups = "drop")
te_season_rank <- season_tot %>% filter(position == "TE") %>% group_by(season) %>%
  mutate(te_rank = rank(-pts, ties.method = "min")) %>% ungroup() %>% select(player_id, season, te_rank, pts)
team_week <- weekly %>% group_by(season, week, team) %>%
  summarize(tm_tgt = sum(targets, na.rm = TRUE), tm_air = sum(pmax(0, coalesce(receiving_air_yards, 0))), .groups = "drop")

usage_year <- function(base, k) {
  w <- weekly %>% inner_join(base %>% select(gsis_id, pfr_player_id, draft_season), by = c("player_id" = "gsis_id")) %>%
    filter(season == draft_season + k - 1) %>%
    mutate(across(c(targets, receptions, receiving_yards, receiving_tds, receiving_air_yards, fantasy_points_ppr,
                    rushing_tds), ~ coalesce(.x, 0))) %>%
    left_join(team_week, by = c("season", "week", "team")) %>%
    left_join(snaps, by = c("pfr_player_id", "season", "week"))
  u <- w %>% group_by(player_id) %>% arrange(week, .by_group = TRUE) %>%
    summarize(games = n_distinct(week), tgt = sum(targets), rec = sum(receptions), rec_yds = sum(receiving_yards),
              rec_td = sum(receiving_tds), tot_td = sum(receiving_tds + rushing_tds), air = sum(receiving_air_yards),
              rec_epa = sum(receiving_epa, na.rm = TRUE),
              tm_tgt = sum(tm_tgt), tm_air = sum(tm_air), pts = sum(fantasy_points_ppr),
              games_late = sum(week >= 10), tgt_late = sum(targets[week >= 10]),
              pts_late = sum(fantasy_points_ppr[week >= 10]),
              snap_avg = if (all(is.na(offense_pct))) NA_real_ else mean(offense_pct, na.rm = TRUE),
              snap_last6 = if (all(is.na(offense_pct))) NA_real_ else mean(tail(offense_pct[!is.na(offense_pct)], 6)),
              team = names(which.max(table(team))), .groups = "drop") %>%
    mutate(tgt_pg = tgt / games, rec_pg = rec / games, ppg = pts / games,
           tgt_share = ifelse(tm_tgt > 0, tgt / tm_tgt, NA), air_share = ifelse(tm_air > 0, pmax(0, air) / tm_air, NA),
           wopr = ifelse(is.na(tgt_share), NA, 1.5 * tgt_share + 0.7 * coalesce(air_share, 0)),
           ypt = ifelse(tgt >= 10, rec_yds / tgt, NA), epa_tgt = ifelse(tgt >= 10, rec_epa / tgt, NA),
           catch_rate = ifelse(tgt >= 10, rec / tgt, NA), adot = ifelse(tgt >= 10, air / tgt, NA),
           td_pg = tot_td / games,
           td_share_pts = ifelse(pts > 0, 6 * tot_td / pts, NA),
           tgt_pg_late = ifelse(games_late > 0, tgt_late / games_late, NA),
           ppg_late = ifelse(games_late > 0, pts_late / games_late, NA))
  out <- base %>% select(gsis_id, draft_season) %>%
    left_join(u, by = c("gsis_id" = "player_id")) %>%
    mutate(season = draft_season + k - 1) %>%
    left_join(te_season_rank %>% select(player_id, season, finish = te_rank), by = c("gsis_id" = "player_id", "season")) %>%
    mutate(played = !is.na(games),
           across(c(games, tgt, rec, tgt_pg, rec_pg, pts, ppg, td_pg, tgt_share, air_share, wopr, games_late),
                  ~ ifelse(played, .x, 0)),
           finish = pmin(coalesce(finish, CAP), CAP), season_complete = season <= LAST) %>%
    select(gsis_id, draft_season, played, games, tgt, rec, tgt_pg, rec_pg, tgt_share, air_share, wopr,
           pts, ppg, finish, ypt, epa_tgt, catch_rate, adot, td_pg, td_share_pts, tgt_pg_late, ppg_late,
           snap_avg, snap_last6, season_complete)
  names(out)[-(1:2)] <- paste0("y", k, "_", names(out)[-(1:2)])
  out
}

outcome_year <- function(base, k) {
  base %>% select(gsis_id, draft_season) %>% mutate(season = draft_season + k - 1) %>%
    left_join(te_season_rank, by = c("gsis_id" = "player_id", "season")) %>%
    transmute(gsis_id, draft_season, complete = season <= LAST,
              finish = ifelse(complete, pmin(coalesce(te_rank, CAP), CAP), NA),
              pts = ifelse(complete, coalesce(pts, 0), NA)) %>%
    rename_with(~ paste0("o", k, "_", .x), c(complete, finish, pts))
}

usage_feats <- function(k) paste0("y", k, "_", c("games", "tgt_pg", "rec_pg", "tgt_share", "air_share", "wopr",
  "pts", "ppg", "finish", "ypt", "epa_tgt", "catch_rate", "adot", "td_pg", "td_share_pts", "tgt_pg_late",
  "ppg_late", "snap_avg", "snap_last6"))
draft_feats <- c("log_pick", "age_at_draft", "p_dominator", "p_rec_yds", "p_ypr", "speed_score",
                 "weight_lb", "breakout_age_filled", "college_matched")

prep_fit_u <- function(tr, feats) {
  med <- sapply(feats, function(v) median(as.numeric(tr[[v]]), na.rm = TRUE)); med[is.na(med)] <- 0
  list(feats = feats, med = med, flag = feats[sapply(feats, function(v) any(is.na(tr[[v]])))])
}
prep_apply_u <- function(p, x) {
  m <- sapply(p$feats, function(v) { z <- as.numeric(x[[v]]); z[is.na(z)] <- p$med[v]; z })
  if (is.null(dim(m))) m <- matrix(m, nrow = 1, dimnames = list(NULL, p$feats))
  if (length(p$flag)) {
    fl <- sapply(p$flag, function(v) as.integer(is.na(x[[v]])))
    if (is.null(dim(fl))) fl <- matrix(fl, nrow = 1)
    colnames(fl) <- paste0("na_", p$flag); m <- cbind(m, fl)
  }
  m
}
