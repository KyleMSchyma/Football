# =============================================================================
# TE Model -- summary lists from existing boards (no new modeling)
#   Year 1 prospects (2026 class), Year 2 buys/sells (2025 class),
#   Year 3 buys/sells (2024 class). Writes te_summary_lists.csv.
#   Same layout as WR_Model/wr_summary_lists.R; TE tiers are top 8 / 16 / 24.
# =============================================================================
suppressMessages(library(dplyr))
options(width = 220)

# ---------------- Year 1 prospects: 2026 class ----------------
proj <- read.csv("te_projections_2024_2026.csv") %>% filter(draft_season == 2026)
tier <- read.csv("te_finish_tier_board_2024_2026.csv") %>% filter(draft_season == 2026) %>%
  select(pick, p_top8 = p_top8_post, p_top16 = p_top16_post, p_top24 = p_top24_post, two_post, hidden_top24_pre)
y1 <- proj %>% select(pfr_player_name, round, pick, draft_team, post_enet_pts3, post_enet_p24, pick_only_pts3,
                      pre_enet_pts3, pick_only_p24, pre_enet_p24, value_gap_pts, value_gap_p24) %>%
  left_join(tier, by = "pick") %>% arrange(desc(post_enet_p24))
cat("===== YEAR 1 PROSPECTS (2026 class): ranked by post-draft P(top-24 TE season in yrs 1-3) =====\n")
print(y1 %>% select(pfr_player_name, round, pick, draft_team, post_enet_pts3, post_enet_p24, p_top8, p_top16, p_top24,
                    two_post, value_gap_pts), row.names = FALSE)
cat("\n----- Day-3 stashes: rounds 4-7 by pre-draft value gap (college model P(top 24) minus pick-only) -----\n")
stash <- y1 %>% filter(round >= 4) %>% arrange(desc(value_gap_p24)) %>% head(5)
print(stash %>% select(pfr_player_name, pick, draft_team, pick_only_p24, pre_enet_p24, value_gap_p24, pick_only_pts3, pre_enet_pts3),
      row.names = FALSE)

# ---------------- Year 2: 2025 class ----------------
y2 <- read.csv("te_year2_breakout_board.csv") %>% filter(draft_season == 2025)
cols2 <- c("pfr_player_name", "pick", "y1_games", "y1_tgt_pg", "y1_tgt_share", "y1_wopr", "y1_snap_avg", "y1_snap_last6",
           "y1_ppg", "y1_finish", "y1_td_share_pts", "p_top24_usage", "p_top16_usage", "p_top8_usage", "p_top24_rookie_pts",
           "usage_edge_top24", "pts23_usage")
cat("\n===== YEAR 2 (2025 class) candidates =====\n")
cat("BUYS: usage edge >= +0.05 with P(top 24) >= 0.15, or P(top 24) >= 0.40 with a rookie finish worse than TE24\n")
buys2 <- y2 %>% filter((usage_edge_top24 >= 0.05 & p_top24_usage >= 0.15) | (p_top24_usage >= 0.40 & y1_finish > 24)) %>% filter(usage_edge_top24 > -0.05) %>%
  arrange(desc(p_top24_usage))
print(buys2[, cols2], row.names = FALSE)
cat("\nSELLS: rookie finish <= TE36 and (usage edge <= -0.05, or last-6 snap share 5+ points below his season average, or TD-heavy: TDs >= 35% of points)\n")
sells2 <- y2 %>% filter(y1_finish <= 36, usage_edge_top24 < 0,
                        usage_edge_top24 <= -0.05 | coalesce(y1_snap_last6 - y1_snap_avg, 0) <= -0.05 | coalesce(y1_td_share_pts, 0) >= 0.35) %>%
  arrange(usage_edge_top24)
print(sells2[, cols2], row.names = FALSE)

# ---------------- Year 3: 2024 class ----------------
y3 <- read.csv("te_year3_board.csv") %>% filter(draft_season == 2024)
cols3 <- c("pfr_player_name", "pick", "y1_finish", "y2_finish", "y2_games", "y2_tgt_pg", "y2_tgt_share", "y2_wopr",
           "y2_snap_avg", "y2_snap_last6", "d_tgt", "d_snap", "y2_ppg", "y2_td_share_pts", "p_top24_usage", "p_top16_usage",
           "p_top8_usage", "p_top24_y2pts", "usage_edge_top24", "pts_y3_usage")
cat("\n===== YEAR 3 (2024 class) candidates =====\n")
cat("BUYS: usage edge vs year-2 points >= +0.05 with P(top 24) >= 0.15, or rising usage (more targets and snaps) with P >= 0.20\n")
buys3 <- y3 %>% filter((usage_edge_top24 >= 0.05 & p_top24_usage >= 0.15) | (d_tgt > 0 & coalesce(d_snap, 0) > 0 & p_top24_usage >= 0.20)) %>% filter(usage_edge_top24 > -0.05) %>%
  arrange(desc(p_top24_usage))
print(buys3[, cols3], row.names = FALSE)
cat("\nSELLS: year-2 finish <= TE40 and (usage edge <= -0.05, or targets and snaps both fell, or last-6 snaps 5+ points below average, or TD-heavy)\n")
sells3 <- y3 %>% filter(y2_finish <= 40, usage_edge_top24 < 0,
                        usage_edge_top24 <= -0.05 | (d_tgt < 0 & coalesce(d_snap, 0) < 0) |
                          coalesce(y2_snap_last6 - y2_snap_avg, 0) <= -0.05 | coalesce(y2_td_share_pts, 0) >= 0.35) %>%
  arrange(usage_edge_top24)
print(sells3[, cols3], row.names = FALSE)

out <- bind_rows(
  y1 %>% filter(post_enet_p24 >= 0.10 | round <= 3) %>%
    transmute(list = "Year 1 prospect", player = pfr_player_name, pick, key_prob = post_enet_p24,
              note = sprintf("P(TE8/16/24) %.2f/%.2f/%.2f; 3-yr PPR %.0f; value gap %+.0f pts", p_top8, p_top16, p_top24,
                             post_enet_pts3, value_gap_pts)),
  stash %>% transmute(list = "Year 1 Day-3 stash", player = pfr_player_name, pick, key_prob = pre_enet_p24,
                      note = sprintf("college model P(top 24) %.2f vs pick-only %.2f (gap %+.2f)", pre_enet_p24, pick_only_p24, value_gap_p24)),
  buys2 %>% transmute(list = "Year 2 buy", player = pfr_player_name, pick, key_prob = p_top24_usage,
                      note = sprintf("rookie TE%d; P(top 24) %.2f vs rookie pts %.2f; %.1f targets/g; snaps %.2f (last6 %.2f)",
                                     y1_finish, p_top24_usage, p_top24_rookie_pts, y1_tgt_pg, y1_snap_avg, y1_snap_last6)),
  sells2 %>% transmute(list = "Year 2 sell", player = pfr_player_name, pick, key_prob = p_top24_usage,
                       note = sprintf("rookie TE%d; P(top 24) %.2f vs rookie pts %.2f; snaps %.2f -> last6 %.2f; TD share of pts %.2f",
                                      y1_finish, p_top24_usage, p_top24_rookie_pts, y1_snap_avg, y1_snap_last6, y1_td_share_pts)),
  buys3 %>% transmute(list = "Year 3 buy", player = pfr_player_name, pick, key_prob = p_top24_usage,
                      note = sprintf("y2 TE%d; P(top 24) %.2f vs y2-pts %.2f; targets/g %+.1f, snaps %+.2f",
                                     y2_finish, p_top24_usage, p_top24_y2pts, d_tgt, d_snap)),
  sells3 %>% transmute(list = "Year 3 sell", player = pfr_player_name, pick, key_prob = p_top24_usage,
                       note = sprintf("y2 TE%d; P(top 24) %.2f vs y2-pts %.2f; targets/g %+.1f, snaps %+.2f; last6 %.2f",
                                      y2_finish, p_top24_usage, p_top24_y2pts, d_tgt, d_snap, y2_snap_last6)))
write.csv(out, "te_summary_lists.csv", row.names = FALSE)
cat("\nsaved te_summary_lists.csv (", nrow(out), "rows )\n")
