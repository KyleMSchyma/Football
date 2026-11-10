# =============================================================================
# Summary lists from existing boards (no new modeling)
#   Year 1 prospects (2026 class), Year 2 buys/sells (2025 class),
#   Year 3 buys/sells (2024 class). Writes wr_summary_lists.csv.
# =============================================================================
suppressMessages(library(dplyr))
options(width = 200)

# ---------------- Year 1 prospects: 2026 class ----------------
proj <- read.csv("wr_projections_2024_2026.csv") %>% filter(draft_season == 2026)
tier <- read.csv("wr_tier_board_2024_2026.csv") %>% filter(draft_season == 2026) %>%
  select(pick, p_wr1 = post_enet_p_wr1, p_wr2plus = post_enet_p_wr2plus, p_wr3plus = post_enet_p_wr3plus)
val  <- read.csv("wr_value_board_2024_2026.csv") %>% filter(draft_season == 2026) %>%
  select(pick, pick_ppr, pre_ppr, value_gap_ppr, rank_gap, flag)
y1 <- proj %>% select(pfr_player_name, round, pick, draft_team, post_ppr_3yr, post_hit_prob) %>%
  left_join(tier, by = "pick") %>% left_join(val, by = "pick") %>% arrange(desc(post_hit_prob))
cat("===== YEAR 1 PROSPECTS (2026 class): top 12 by post-draft P(top-24 season in yrs 1-3) =====\n")
print(head(y1, 12), row.names = FALSE)
cat("\n----- Day-3 stashes: top 6 by pre-draft value gap -----\n")
print(y1 %>% filter(round >= 4) %>% arrange(desc(value_gap_ppr)) %>% head(6) %>%
        select(pfr_player_name, pick, draft_team, pick_ppr, pre_ppr, value_gap_ppr, rank_gap, p_wr3plus, flag),
      row.names = FALSE)

# ---------------- Year 2: 2025 class ----------------
wk <- readRDS(file.path("cache", "nfl_weekly_raw.rds")) %>% filter(season_type == "REG", season == 2025)
tbl <- readRDS("wr_model_table.rds") %>% filter(draft_season == 2025) %>% select(pfr_player_name, pick, gsis_id)
td <- wk %>% group_by(player_id) %>%
  summarize(rec_td = sum(receiving_tds, na.rm = TRUE), ppr = sum(fantasy_points_ppr, na.rm = TRUE), .groups = "drop") %>%
  mutate(td_share_of_ppr = round(6 * rec_td / pmax(ppr, 1), 3))
y2 <- read.csv("wr_year2_breakout_board.csv") %>% filter(draft_season == 2025) %>%
  left_join(tbl %>% select(pick, gsis_id), by = "pick") %>%
  left_join(td %>% select(player_id, rec_td, td_share_of_ppr), by = c("gsis_id" = "player_id"))
cols2 <- c("pfr_player_name", "pick", "r_games", "r_targets", "r_ts", "r_ays", "r_snap_avg", "r_snap_last6",
           "r_ts_trend", "r_ppr", "r_finish", "rec_td", "td_share_of_ppr", "p_wr3_usage", "p_wr2_usage",
           "p_wr3_rookie_pts", "usage_edge_wr3", "ppr23_usage")
cat("\n===== YEAR 2 (2025 class) candidates =====\n")
cat("BUYS: usage edge >= +0.03, or P(WR3+) >= 0.40 with rookie finish worse than WR36\n")
buys2 <- y2 %>% filter(usage_edge_wr3 >= 0.03 | (p_wr3_usage >= 0.40 & r_finish > 36)) %>%
  filter(p_wr3_usage >= 0.10) %>% arrange(desc(p_wr3_usage))
print(buys2[, cols2], row.names = FALSE)
cat("\nSELLS: rookie finish <= WR60 and (usage edge <= -0.03, or last-6 snaps < 50%, or falling target share, or TD-heavy)\n")
sells2 <- y2 %>% filter(r_finish <= 60,
                        usage_edge_wr3 <= -0.03 | r_snap_last6 < 0.5 | r_ts_trend < -0.02 | td_share_of_ppr >= 0.30) %>%
  arrange(usage_edge_wr3)
print(sells2[, cols2], row.names = FALSE)

# ---------------- Year 3: 2024 class ----------------
y3 <- read.csv("wr_year3_board.csv") %>% filter(draft_season == 2024)
cols3 <- c("pfr_player_name", "pick", "y1_finish", "y2_finish", "y2_games", "y2_targets", "y2_ts", "y2_snap_avg",
           "y2_snap_last6", "y2_ts_trend", "d_ts", "d_snap", "y2_ppr", "use_p3", "use_p2", "y2pts_p3",
           "y12pts_p3", "use_ppr")
y3 <- y3 %>% mutate(edge_vs_y2pts = round(use_p3 - y2pts_p3, 3))
cat("\n===== YEAR 3 (2024 class) candidates =====\n")
cat("BUYS: usage edge vs year-2 points >= +0.05 with P(WR3+) >= 0.20, or rising usage (d_ts > 0 and d_snap > 0) with P >= 0.25\n")
buys3 <- y3 %>% filter((edge_vs_y2pts >= 0.05 & use_p3 >= 0.20) | (d_ts > 0 & d_snap > 0 & use_p3 >= 0.25)) %>%
  arrange(desc(use_p3))
print(buys3[, c(cols3, "edge_vs_y2pts")], row.names = FALSE)
cat("\nSELLS: year-2 finish <= WR48 and (usage edge <= -0.05, or both target share and snaps fell, or late trend < -0.03)\n")
sells3 <- y3 %>% filter(y2_finish <= 48,
                        edge_vs_y2pts <= -0.05 | (d_ts < 0 & d_snap < 0) | y2_ts_trend < -0.03) %>%
  arrange(edge_vs_y2pts)
print(sells3[, c(cols3, "edge_vs_y2pts")], row.names = FALSE)

out <- bind_rows(
  head(y1, 12) %>% transmute(list = "Year 1 prospect", player = pfr_player_name, pick, key_prob = post_hit_prob,
                             note = sprintf("P(WR1/2+/3+) %.2f/%.2f/%.2f; value gap %+.0f", p_wr1, p_wr2plus, p_wr3plus, value_gap_ppr)),
  y1 %>% filter(round >= 4) %>% arrange(desc(value_gap_ppr)) %>% head(6) %>%
    transmute(list = "Year 1 Day-3 stash", player = pfr_player_name, pick, key_prob = p_wr3plus,
              note = sprintf("pre-draft %0.f vs pick-only %0.f PPR (gap %+.0f)", pre_ppr, pick_ppr, value_gap_ppr)),
  buys2 %>% transmute(list = "Year 2 buy", player = pfr_player_name, pick, key_prob = p_wr3_usage,
                      note = sprintf("rookie WR%d; P(WR3+) %.2f vs pts %.2f; snaps %.2f (last6 %.2f); TS %.3f",
                                     r_finish, p_wr3_usage, p_wr3_rookie_pts, r_snap_avg, r_snap_last6, r_ts)),
  sells2 %>% transmute(list = "Year 2 sell", player = pfr_player_name, pick, key_prob = p_wr3_usage,
                       note = sprintf("rookie WR%d; P(WR3+) %.2f vs pts %.2f; last6 snaps %.2f; TS trend %+.3f; TD share of PPR %.2f",
                                      r_finish, p_wr3_usage, p_wr3_rookie_pts, r_snap_last6, r_ts_trend, td_share_of_ppr)),
  buys3 %>% transmute(list = "Year 3 buy", player = pfr_player_name, pick, key_prob = use_p3,
                      note = sprintf("y2 WR%d; P(WR3+) %.2f vs y2-pts %.2f; d_TS %+.3f, d_snap %+.3f; last6 snaps %.2f",
                                     y2_finish, use_p3, y2pts_p3, d_ts, d_snap, y2_snap_last6)),
  sells3 %>% transmute(list = "Year 3 sell", player = pfr_player_name, pick, key_prob = use_p3,
                       note = sprintf("y2 WR%d; P(WR3+) %.2f vs y2-pts %.2f; d_TS %+.3f, d_snap %+.3f; late trend %+.3f",
                                      y2_finish, use_p3, y2pts_p3, d_ts, d_snap, y2_ts_trend)))
write.csv(out, "wr_summary_lists.csv", row.names = FALSE)
cat("\nsaved wr_summary_lists.csv (", nrow(out), "rows )\n")
