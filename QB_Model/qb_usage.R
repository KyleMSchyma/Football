# =============================================================================
# QB Model -- NFL usage helpers, sourced by Phases 5-7
#   qb_season_rank: every QB's season fantasy points and QB rank (regular season)
#   usage_year(base, k): one row per player in `base` with his NFL year-k usage:
#     games, starts (15+ attempts), attempts, att per game, YPA, ANY/A, passing
#     EPA per dropback, CPOE, sack rate, TD and INT rates, rushing attempts /
#     yards / TDs per game, fantasy points, points per game and per start, QB
#     finish (capped at 50), late-season (weeks 10+) starts and points per game,
#     team pass attempts. Players who did not play get 0 for volume and NA for
#     efficiency (imputed in-fold with a missing flag).
# =============================================================================
LAST <- 2025; CAP <- 50
team_map <- c(GNB = "GB", KAN = "KC", NOR = "NO", NWE = "NE", SFO = "SF", TAM = "TB",
              LAR = "LA", RAM = "LA", STL = "LA", LVR = "LV", OAK = "LV", SDG = "LAC", SD = "LAC")
fix_team <- function(x) ifelse(x %in% names(team_map), unname(team_map[x]), x)

weekly <- readRDS(file.path("..", "Football2", "cache", "nfl_weekly_raw.rds")) %>%
  filter(season_type == "REG", season <= LAST) %>% mutate(team = fix_team(team))

season_tot <- weekly %>% group_by(player_id, season) %>%
  summarize(position = first(position), pts = sum(fantasy_points_ppr, na.rm = TRUE), .groups = "drop")
qb_season_rank <- season_tot %>% filter(position == "QB") %>% group_by(season) %>%
  mutate(qb_rank = rank(-pts, ties.method = "min")) %>% ungroup() %>% select(player_id, season, qb_rank, pts)
team_season <- weekly %>% group_by(season, team) %>% summarize(team_pass_att = sum(attempts, na.rm = TRUE), .groups = "drop")

usage_year <- function(base, k) {
  w <- weekly %>% inner_join(base %>% select(gsis_id, draft_season), by = c("player_id" = "gsis_id")) %>%
    filter(season == draft_season + k - 1) %>%
    mutate(across(c(attempts, completions, passing_yards, passing_tds, passing_interceptions, sacks_suffered,
                    sack_yards_lost, carries, rushing_yards, rushing_tds, fantasy_points_ppr), ~ coalesce(.x, 0)),
           start = attempts >= 15)
  u <- w %>% group_by(player_id) %>%
    summarize(games = n_distinct(week), starts = sum(start), att = sum(attempts),
              yds = sum(passing_yards), td = sum(passing_tds), int = sum(passing_interceptions),
              sacks = sum(sacks_suffered), sack_yds = sum(sack_yards_lost),
              epa = sum(passing_epa, na.rm = TRUE),
              cpoe = ifelse(sum(attempts[!is.na(passing_cpoe)]) > 0,
                            weighted.mean(passing_cpoe[!is.na(passing_cpoe)], attempts[!is.na(passing_cpoe)]), NA),
              rush_att = sum(carries), rush_yds = sum(rushing_yards), rush_td = sum(rushing_tds),
              pts = sum(fantasy_points_ppr), pts_starts = sum(fantasy_points_ppr[start]),
              starts_late = sum(start & week >= 10), pts_late_starts = sum(fantasy_points_ppr[start & week >= 10]),
              team = names(which.max(table(team))), .groups = "drop") %>%
    mutate(db = att + sacks,
           att_pg = att / games, ppg = pts / games,
           pts_per_start = ifelse(starts > 0, pts_starts / starts, NA),
           ppg_late_starts = ifelse(starts_late > 0, pts_late_starts / starts_late, NA),
           ypa = ifelse(att >= 20, yds / att, NA),
           anya = ifelse(db >= 20, (yds + 20 * td - 45 * int - sack_yds) / db, NA),
           epa_db = ifelse(db >= 20, epa / db, NA),
           cpoe = ifelse(att >= 20, cpoe, NA),
           sack_rate = ifelse(db >= 20, sacks / db, NA),
           td_rate = ifelse(att >= 20, td / att, NA), int_rate = ifelse(att >= 20, int / att, NA),
           rush_ypg = rush_yds / games, rush_td_pg = rush_td / games,
           rush_share_pts = ifelse(pts > 0, (0.1 * rush_yds + 6 * rush_td) / pts, NA))
  out <- base %>% select(gsis_id, draft_season) %>%
    left_join(u, by = c("gsis_id" = "player_id")) %>%
    mutate(season = draft_season + k - 1) %>%
    left_join(qb_season_rank %>% select(player_id, season, finish = qb_rank), by = c("gsis_id" = "player_id", "season")) %>%
    left_join(team_season, by = c("season", "team")) %>%
    mutate(played = !is.na(games),
           across(c(games, starts, att, att_pg, pts, ppg, rush_att, rush_yds, rush_td, rush_ypg, rush_td_pg, starts_late),
                  ~ ifelse(played, .x, 0)),
           finish = pmin(coalesce(finish, CAP), CAP), season_complete = season <= LAST) %>%
    select(gsis_id, draft_season, played, games, starts, att, att_pg, pts, ppg, pts_per_start, finish,
           ypa, anya, epa_db, cpoe, sack_rate, td_rate, int_rate, rush_att, rush_yds, rush_ypg, rush_td_pg,
           rush_share_pts, starts_late, ppg_late_starts, team_pass_att, season_complete)
  names(out)[-(1:2)] <- paste0("y", k, "_", names(out)[-(1:2)])
  out
}

outcome_year <- function(base, k) {
  base %>% select(gsis_id, draft_season) %>% mutate(season = draft_season + k - 1) %>%
    left_join(qb_season_rank, by = c("gsis_id" = "player_id", "season")) %>%
    transmute(gsis_id, draft_season, complete = season <= LAST,
              finish = ifelse(complete, pmin(coalesce(qb_rank, CAP), CAP), NA),
              pts = ifelse(complete, coalesce(pts, 0), NA)) %>%
    rename_with(~ paste0("o", k, "_", .x), c(complete, finish, pts))
}

usage_feats <- function(k) paste0("y", k, "_", c("games", "starts", "att_pg", "pts", "ppg", "pts_per_start", "finish",
  "ypa", "anya", "epa_db", "cpoe", "sack_rate", "td_rate", "int_rate", "rush_ypg", "rush_td_pg", "rush_share_pts",
  "starts_late", "ppg_late_starts"))
draft_feats <- c("log_pick", "age_at_draft", "p_aya", "p_comp_pct", "p_rush_yds", "career_rush_yds",
                 "starter_age_filled", "recruit_rating", "college_matched")

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
