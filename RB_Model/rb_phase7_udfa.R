# =============================================================================
# RB Model -- Phase 7: undrafted free-agent (UDFA) RBs
#
#   PART 1  UDFA RBs from the nflreadr players table: position RB, no draft
#           pick, rookie season 2010-2025, at least one regular-season carry as an
#           RB. Draft capital: pick = 262 sentinel, undrafted = 1. College stats
#           are not matched for UDFAs (cfbd coverage of these many small-school
#           backs is thin, as Phase 1 showed for FCS RBs); they enter as
#           missing with college_matched = 0, imputed in-fold.
#   PART 2  Outcomes: top-24 / top-8 seasons in years 1-3 and years 2-3,
#           compared with drafted RBs by round.
#   PART 3  Year-2 breakout model (Phase 5 features) trained WITH UDFAs vs
#           drafted only, rolling origin (train classes <= Y - 2, test 2016-2023):
#           does adding them change the drafted-RB results, and does the model
#           catch UDFA breakouts?
#   PART 4  Board: 2025 UDFA RBs who played as rookies.
# Outputs: phase7_udfa_list.csv, phase7_metrics.csv, rb_udfa_board.csv
# =============================================================================
source("rb_common.R"); source("rb_usage.R")
set.seed(2026)
UDFA_PICK <- 262

players <- readRDS(file.path("..", "Football2", "cache", "players_raw.rds"))
drafted <- load_table()
rb_ids <- weekly %>% filter(position == "RB", carries > 0) %>% distinct(player_id)
udfa <- players %>%
  filter(position == "RB", is.na(draft_pick), !is.na(rookie_season), rookie_season >= 2010, rookie_season <= LAST,
         gsis_id %in% rb_ids$player_id, !(gsis_id %in% drafted$gsis_id)) %>%
  transmute(gsis_id, pfr_player_id = pfr_id, pfr_player_name = display_name, college = college_name,
            draft_season = as.integer(rookie_season), round = 8L, pick = UDFA_PICK, draft_team = NA_character_,
            log_pick = log(UDFA_PICK), undrafted = 1L,
            age_at_draft = as.numeric(as.Date(paste0(rookie_season, "-04-25")) - as.Date(birth_date)) / 365.25,
            college_matched = 0L)
cat("UDFA RBs with >= 1 regular-season carry, rookie seasons 2010-2025:", nrow(udfa), "\n")
print(table(udfa$draft_season))

# --- outcomes ------------------------------------------------------------------------
oc <- function(b) {
  b %>% select(gsis_id, draft_season) %>% crossing(nfl_year = 1:3) %>% mutate(season = draft_season + nfl_year - 1) %>%
    filter(season <= LAST) %>% left_join(rb_season_rank, by = c("gsis_id" = "player_id", "season")) %>%
    mutate(fin = pmin(coalesce(rb_rank, CAP), CAP), pts = coalesce(pts, 0)) %>% group_by(gsis_id, draft_season) %>%
    summarize(n_obs = n(), best_13 = min(fin), pts_13 = sum(pts), best_23 = suppressWarnings(min(fin[nfl_year >= 2])), .groups = "drop")
}
uo <- udfa %>% left_join(oc(udfa), by = c("gsis_id", "draft_season")) %>%
  mutate(full = n_obs == 3, top24_13 = as.integer(best_13 <= 24), top8_13 = as.integer(best_13 <= 8))
write.csv(uo %>% select(pfr_player_name, draft_season, college, age_at_draft, best_13, pts_13, best_23), "phase7_udfa_list.csv", row.names = FALSE)
cat("\nUDFA RBs with 3 complete seasons (2010-2023):", sum(uo$full), " any top-24 season yrs 1-3:",
    sum(uo$top24_13[uo$full]), " top-8:", sum(uo$top8_13[uo$full]), "\n")
cat("UDFAs with any top-36 season in years 1-3:\n")
print(as.data.frame(uo %>% filter(full, best_13 <= 36) %>% arrange(best_13) %>% select(pfr_player_name, draft_season, college, best_13, pts_13)), row.names = FALSE)
cat("\nfor comparison, drafted RBs (2010-2023) top-24 rate by round group:\n")
print(as.data.frame(drafted %>% filter(!is.na(hit24_3yr)) %>% mutate(grp = ifelse(round <= 1, "R1", ifelse(round <= 3, "R2-3", "R4-7"))) %>%
  group_by(grp) %>% summarize(n = n(), top24 = round(mean(hit24_3yr), 3), .groups = "drop") %>%
  bind_rows(data.frame(grp = "UDFA", n = sum(uo$full), top24 = round(mean(uo$top24_13[uo$full]), 3)))), row.names = FALSE)

# --- year-2 breakout with UDFAs ---------------------------------------------------------
all_base <- bind_rows(drafted %>% filter(draft_season <= 2025, !is.na(gsis_id)) %>% mutate(undrafted = 0L), udfa)
d <- all_base %>% inner_join(usage_year(all_base, 1), by = c("gsis_id", "draft_season")) %>%
  left_join(outcome_year(all_base, 2), by = c("gsis_id", "draft_season")) %>%
  left_join(outcome_year(all_base, 3), by = c("gsis_id", "draft_season")) %>%
  mutate(complete = coalesce(o3_complete, FALSE), best_23 = pmin(o2_finish, o3_finish), pts_23 = o2_pts + o3_pts,
         y_qb1 = as.integer(best_23 <= 8), y_qb2 = as.integer(best_23 <= 24))
train_all <- d %>% filter(complete, draft_season <= 2023)
cat("\nyear-2 model rows (2010-2023): drafted", sum(train_all$undrafted == 0), " UDFA", sum(train_all$undrafted == 1),
    " UDFA top-24 in yrs 2-3:", sum(train_all$y_qb2[train_all$undrafted == 1]), "\n")
cat("UDFAs reaching top-24 in years 2-3:",
    paste0(train_all$pfr_player_name[train_all$undrafted == 1 & train_all$y_qb2 == 1], " (", train_all$draft_season[train_all$undrafted == 1 & train_all$y_qb2 == 1], ")", collapse = ", "), "\n")

feats <- c(draft_feats, "undrafted", usage_feats(1))
fitp <- function(tr, te) {
  o <- data.frame(row.names = seq_len(nrow(te)))
  o$rpts_p2 <- predict(glm(y_qb2 ~ log_pick + y1_pts, binomial, tr), te, type = "response")
  p <- prep_fit_u(tr, feats); Xtr <- prep_apply_u(p, tr); Xte <- prep_apply_u(p, te)
  o$use_p2 <- enet_pred(enet_fit(Xtr, tr$y_qb2, "binomial", tr$draft_season), Xte, tr$y_qb2)
  o
}
res <- list()
for (with_udfa in c(FALSE, TRUE)) for (Y in 2016:2023) {
  tr <- train_all %>% filter(draft_season <= Y - 2, with_udfa | undrafted == 0)
  te <- train_all %>% filter(draft_season == Y)
  res[[length(res) + 1]] <- cbind(te %>% select(draft_season, pick, pfr_player_name, undrafted, y1_finish, best_23, y_qb2),
                                  trained_with_udfa = with_udfa, fitp(tr, te))
}
res <- bind_rows(res)
met <- res %>% group_by(trained_with_udfa, eval_on = ifelse(undrafted == 1, "UDFA", "drafted")) %>%
  summarize(n = n(), RB24 = sum(y_qb2), AUC_usage = aucf(y_qb2, use_p2), Brier_usage = brier(use_p2, y_qb2),
            AUC_rookie_pts = aucf(y_qb2, rpts_p2), Brier_rookie_pts = brier(rpts_p2, y_qb2), .groups = "drop") %>%
  mutate(across(where(is.double), ~ round(.x, 4)))
cat("\n===== Year-2 model with vs without UDFAs in training, rolling 2016-2023 =====\n"); print(as.data.frame(met), row.names = FALSE)
write.csv(met, "phase7_metrics.csv", row.names = FALSE)
cat("\nUDFAs in the test years ranked by usage model P(top-24) (trained with UDFAs):\n")
print(as.data.frame(res %>% filter(trained_with_udfa, undrafted == 1) %>% arrange(desc(use_p2)) %>% head(10) %>%
  mutate(across(c(use_p2, rpts_p2), ~ round(.x, 3))) %>% select(draft_season, pfr_player_name, y1_finish, best_23, use_p2, rpts_p2)), row.names = FALSE)

# --- board: 2024-2025 UDFAs -----------------------------------------------------------
sc <- d %>% filter(undrafted == 1, draft_season %in% 2024:2025)
board <- if (nrow(sc)) bind_cols(sc %>% select(pfr_player_name, draft_season, college, y1_games, y1_tch_pg, y1_pts, y1_finish, y1_ypc, y1_snap_avg, o2_finish),
                                 fitp(train_all, sc)) %>% mutate(across(where(is.double), ~ round(.x, 3))) %>% arrange(desc(use_p2)) else data.frame()
write.csv(board, "rb_udfa_board.csv", row.names = FALSE)
cat("\n===== 2024-2025 UDFA RBs who played as rookies =====\n"); print(as.data.frame(board), row.names = FALSE)
