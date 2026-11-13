# Track Record shared helpers: NFL results so far and the scoring of a frozen board.
suppressMessages(library(dplyr))
CACHE <- if (dir.exists("../Football2/cache")) "../Football2/cache" else "../WR_Model/cache"
# season finish = rank of full-PPR season points among players at the position that season; only complete seasons count
nfl_results <- function(TIERS, last_complete = NULL) {
  w <- readRDS(file.path(CACHE, "nfl_weekly_raw.rds")) %>% filter(season_type == "REG")
  w26 <- if (file.exists("../Football2_Dynasty/nfl_weekly_2026.rds")) readRDS("../Football2_Dynasty/nfl_weekly_2026.rds") %>% filter(season_type == "REG") else NULL
  if (!is.null(w26)) w <- bind_rows(w, w26[, intersect(names(w26), names(w))])
  w$position[w$position == "FB"] <- "RB"
  wk <- w %>% group_by(season) %>% summarise(maxwk = max(week), .groups = "drop")
  if (is.null(last_complete)) last_complete <- max(wk$season[wk$maxwk >= 17])
  fin <- w %>% filter(season <= last_complete, position %in% names(TIERS)) %>% group_by(season, player_id, position) %>%
    summarise(pts = sum(fantasy_points_ppr, na.rm = TRUE), .groups = "drop") %>% group_by(season, position) %>% mutate(finish = rank(-pts, ties.method = "min")) %>% ungroup()
  p <- readRDS(file.path(CACHE, "players_raw.rds")) %>% transmute(player_id = gsis_id, class = draft_year, pick = draft_pick) %>%   # class + pick is unique; positions differ for two-way players
    filter(!is.na(pick), class >= 2024)
  p %>% left_join(fin %>% select(season, player_id, finish), by = "player_id") %>% filter(is.na(season) | (season >= class & season <= class + 2)) %>%
    group_by(class, pick) %>% summarise(best_finish_so_far = suppressWarnings(min(finish, na.rm = TRUE)), .groups = "drop") %>%
    mutate(best_finish_so_far = ifelse(is.finite(best_finish_so_far), best_finish_so_far, NA),
           seasons_seen = pmax(0, pmin(last_complete, class + 2) - class + 1), through = last_complete)
}
band <- function(g) ifelse(substr(g, 1, 1) %in% c("A", "B", "C"), substr(g, 1, 1), "D/F")
bootp <- function(y, B = 2000) { set.seed(2026); if (length(y) < 2) return(c(NA, NA)); unname(quantile(replicate(B, mean(sample(y, replace = TRUE))), c(.025, .975))) }
# score a frozen board against results so far: hit rate by grade band, Brier vs pick-only, calibration by probability bin
score_board <- function(f) {
  y <- f %>% filter(seasons_seen >= 1) %>% mutate(y1 = as.integer(tier_so_far == 1), y2 = as.integer(tier_so_far <= 2), y3 = as.integer(tier_so_far <= 3))
  bands <- y %>% mutate(band = band(grade)) %>% group_by(board, band) %>%
    summarise(n = n(), any_tier_so_far = mean(y3), lo = bootp(y3)[1], hi = bootp(y3)[2], top_tier_so_far = mean(y1), expected_any_3yrs = mean(p_any), .groups = "drop")
  brier <- y %>% group_by(board, class) %>% summarise(n = n(), seasons_seen = max(seasons_seen),
    brier_any_model = mean((p_any - y3)^2), brier_any_pick = mean((pk_any - y3)^2), brier_top_model = mean((p_top - y1)^2), brier_top_pick = mean((pk_top - y1)^2), .groups = "drop")
  cal <- y %>% mutate(bin = cut(p_any, c(0, .1, .25, .5, .75, 1), include.lowest = TRUE)) %>% group_by(board, bin) %>%
    summarise(n = n(), mean_predicted_3yrs = mean(p_any), any_tier_so_far = mean(y3), .groups = "drop")
  list(bands = bands, brier = brier, cal = cal)
}
# tier so far from the board's own position (1 = top tier ... 4 = no tier season yet)
add_tier <- function(d, TIERS) d %>% mutate(tier_so_far = mapply(function(ps, b) if (is.na(b)) 4L else as.integer(sum(b > TIERS[[ps]]) + 1L), position, best_finish_so_far))
