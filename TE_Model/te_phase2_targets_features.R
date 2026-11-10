# =============================================================================
# TE Model -- Phase 2: targets and features (single script)
#
# One row per drafted TE (classes 2010-2026).
#
#   PART 1  Targets (regular season, nflverse fantasy_points_ppr = full PPR)
#             total_pts_3yr   PPR points in NFL years 1-3 (0 if he never played)
#             hit24_3yr       1 if any top-24 TE season in years 1-3
#             hit16_3yr       1 if any top-16 TE season in years 1-3
#             hit8_3yr        1 if any top-8 TE season in years 1-3
#             finish_y1..y3   season TE rank, capped at 60 (didn't play / worse = 60)
#             finish_sum_3yr  sum of the three (3 best, 180 worst)
#             tier            best finish yrs 1-3: 1 = top 8, 2 = 9-16, 3 = 17-24, 4 = rest
#           3-year targets are NA for classes without 3 complete seasons (2024+).
#   PART 2  College features from the "primary" season: the last college season
#           with 15+ receptions, so an injury-shortened final year doesn't count as
#           the profile (flagged final_short). Receiving volume and efficiency,
#           share of team receptions / receiving yards / receiving TDs, the
#           receiving "dominator" (mean of yards and TD shares), yards per team
#           pass attempt, cfbd PPA per target and usage (2013+ seasons only),
#           career totals and breakout age (age on Sept 1 of the first season with
#           a 15%+ dominator; the TE threshold is lower than the WR 20%).
#           cfbd only logs FCS players' games against FBS teams, so a TE whose
#           primary-season team totals are partial (< 60 team receptions) or who
#           has no season with 3+ catches is treated as missing college data
#           (college_thin = 1), not a bad season.
#   PART 3  Athletic (incl. speed score), age, draft capital, recruiting
#   PART 4  Landing spot (post-draft only): vacated TE-target share and the
#           incumbent TE's prior-season PPR points
#   PART 5  Checks, feature dictionary and EDA plots
#
# Inputs: te_base.rds, te_college_seasons.rds, ../Football2/cache/nfl_weekly_raw.rds
# Outputs: te_model_table.rds, te_feature_dictionary.csv, plot_p2_*.png
# =============================================================================

suppressMessages({ library(dplyr); library(tidyr); library(ggplot2) })
mycols <- c("#E69F00", "#56B4E9", "#009E73", "#F0E442", "#0072B2", "#D55E00", "#CC79A7")

te     <- readRDS("te_base.rds")
cs     <- readRDS("te_college_seasons.rds")
weekly <- readRDS(file.path("..", "Football2", "cache", "nfl_weekly_raw.rds"))

last_nfl_season <- 2025; CAP <- 60; min_games_ppg <- 8; BREAKOUT <- 0.15; PRIMARY_REC <- 15
team_map <- c(GNB = "GB", KAN = "KC", NOR = "NO", NWE = "NE", SFO = "SF", TAM = "TB",
              LAR = "LA", RAM = "LA", STL = "LA", LVR = "LV", OAK = "LV", SDG = "LAC", SD = "LAC")
fix_team <- function(x) ifelse(x %in% names(team_map), unname(team_map[x]), x)

# =============================================================================
# PART 1: Targets
# =============================================================================
reg <- weekly %>% filter(season_type == "REG", season <= last_nfl_season) %>% mutate(team = fix_team(team))
season_tot <- reg %>% group_by(player_id, season) %>%
  summarize(position = first(position), pts = sum(fantasy_points_ppr, na.rm = TRUE),
            games = n_distinct(week), .groups = "drop")
te_rank <- season_tot %>% filter(position == "TE") %>% group_by(season) %>%
  mutate(te_rank = rank(-pts, ties.method = "min")) %>% ungroup() %>% select(player_id, season, te_rank)
season_tot <- season_tot %>% left_join(te_rank, by = c("player_id", "season"))

yrs <- te %>% select(gsis_id, draft_season = season, pick) %>% crossing(nfl_year = 1:3) %>%
  mutate(season = draft_season + nfl_year - 1) %>% filter(season <= last_nfl_season) %>%
  left_join(season_tot, by = c("gsis_id" = "player_id", "season")) %>%
  mutate(pts = coalesce(pts, 0), games = coalesce(games, 0L),
         finish = pmin(coalesce(te_rank, CAP), CAP))

targets <- yrs %>% group_by(draft_season, pick) %>%
  summarize(n_years_obs = n(), total_pts_3yr = sum(pts), games_3yr = sum(games),
            hit24_3yr = as.integer(any(finish <= 24)), hit16_3yr = as.integer(any(finish <= 16)),
            hit8_3yr = as.integer(any(finish <= 8)), hit32_3yr = as.integer(any(finish <= 32)),
            best_finish_3yr = min(finish), finish_sum_3yr = sum(finish),
            finish_y1 = finish[nfl_year == 1][1], finish_y2 = finish[nfl_year == 2][1],
            finish_y3 = finish[nfl_year == 3][1],
            yr1_pts = sum(pts[nfl_year == 1]), yr1_games = sum(games[nfl_year == 1]), .groups = "drop") %>%
  mutate(ppg_3yr = ifelse(games_3yr >= min_games_ppg, total_pts_3yr / games_3yr, NA_real_),
         across(c(total_pts_3yr, games_3yr, hit24_3yr, hit16_3yr, hit8_3yr, hit32_3yr, best_finish_3yr,
                  finish_sum_3yr, ppg_3yr), ~ ifelse(n_years_obs == 3, .x, NA)),
         # Kyle's TE tiers: top 8 / 9-16 / 17-24 / rest
         tier = case_when(is.na(best_finish_3yr) ~ NA_integer_, best_finish_3yr <= 8 ~ 1L,
                          best_finish_3yr <= 16 ~ 2L, best_finish_3yr <= 24 ~ 3L, TRUE ~ 4L))

# =============================================================================
# PART 2: College features
# =============================================================================
col_feat <- cs %>% group_by(draft_season, pick) %>% arrange(college_year, .by_group = TRUE) %>%
  mutate(primary = if (any(rec >= PRIMARY_REC)) college_year == max(college_year[rec >= PRIMARY_REC])
                   else college_year == college_year[which.max(rec)]) %>%
  summarize(
    p_year = college_year[primary][1], p_team_rec = team_rec[primary][1],
    p_rec = rec[primary][1], p_rec_yds = rec_yds[primary][1], p_rec_td = rec_td[primary][1],
    p_ypr = ypr[primary][1], p_rec_share = rec_share[primary][1], p_rec_yds_share = rec_yds_share[primary][1],
    p_rec_td_share = rec_td_share[primary][1], p_dominator = dominator[primary][1],
    p_ypta = yds_per_team_att[primary][1], p_power5 = power5[primary][1],
    p_ppa_pass = ppa_pass[primary][1], p_ppa_all = ppa_all[primary][1],
    p_usg_pass = if ("usg_pass" %in% names(cs)) usg_pass[primary][1] else NA_real_,
    p_usg_overall = if ("usg_overall" %in% names(cs)) usg_overall[primary][1] else NA_real_,
    final_rec = last(rec), final_short = as.integer(last(rec) < PRIMARY_REC & any(rec >= PRIMARY_REC)),
    max_rec = max(rec), best_dominator = suppressWarnings(max(dominator, na.rm = TRUE)),
    best_rec_share = suppressWarnings(max(rec_share, na.rm = TRUE)),
    career_rec = sum(rec), career_rec_yds = sum(rec_yds), career_rec_td = sum(rec_td),
    college_seasons = n_distinct(college_year), college_teams = n_distinct(team),
    featured_seasons = sum(rec >= 25),
    breakout_age = suppressWarnings(min(age_sept1[coalesce(dominator, 0) >= BREAKOUT], na.rm = TRUE)),
    final_age = last(age_sept1), .groups = "drop") %>%
  mutate(across(c(best_dominator, best_rec_share, breakout_age), ~ ifelse(is.infinite(.x), NA, .x)),
         ever_breakout = as.integer(!is.na(breakout_age)),
         breakout_age_filled = ifelse(ever_breakout == 1, breakout_age, final_age + 1),
         transferred = as.integer(college_teams > 1),
         career_ypr = ifelse(career_rec >= 20, career_rec_yds / career_rec, NA),
         # thin = FCS partial coverage (team totals from a game or two) or a cfbd gap
         college_thin = as.integer(is.na(p_rec) | max_rec < 3 | coalesce(p_team_rec, 0) < 60))

thin_cols <- c("p_rec", "p_rec_yds", "p_rec_td", "p_ypr", "p_rec_share", "p_rec_yds_share", "p_rec_td_share",
               "p_dominator", "p_ypta", "p_ppa_pass", "p_ppa_all", "p_usg_pass", "p_usg_overall",
               "best_dominator", "best_rec_share", "career_rec", "career_rec_yds", "career_rec_td", "career_ypr",
               "featured_seasons", "breakout_age_filled")
for (v in thin_cols) col_feat[[v]][col_feat$college_thin == 1] <- NA
col_feat$ever_breakout[col_feat$college_thin == 1] <- NA

# =============================================================================
# PART 3: Athletic, age, draft capital, recruiting
# =============================================================================
tbl <- te %>% rename(draft_season = season, draft_team = team) %>%
  left_join(targets, by = c("draft_season", "pick")) %>%
  left_join(col_feat, by = c("draft_season", "pick")) %>%
  mutate(draft_team = fix_team(draft_team), log_pick = log(pick), round_f = factor(round),
         day3 = as.integer(round >= 4), round1 = as.integer(round == 1),
         bmi = ifelse(!is.na(height_in) & !is.na(weight_lb), 703 * weight_lb / height_in^2, NA_real_),
         # Bill Barnwell's speed score: weight * 200 / forty^4
         speed_score = ifelse(!is.na(forty) & !is.na(weight_lb), weight_lb * 200 / forty^4, NA_real_),
         college_matched = as.integer(!is.na(athlete_id) & coalesce(college_thin, 1L) == 0),
         college_thin = coalesce(college_thin, 1L),
         ever_breakout = coalesce(ever_breakout, 0L),
         early_declare = as.integer(coalesce(college_seasons, 5) <= 3 | (!is.na(age_at_draft) & age_at_draft < 22)))
for (d in c("forty", "vertical", "broad_jump")) tbl[[paste0("miss_", d)]] <- as.integer(is.na(tbl[[d]]))

# =============================================================================
# PART 4: Landing spot (post-draft only)
#   vacated_tgt_share: share of the drafting team's prior-season TE targets that
#     went to TEs who did not play for that team in the rookie season
#   incumbent_pts: prior-season PPR points of the team's best TE who is still on
#     the team in the rookie season (0 if none)
#   Rookie-season rosters are known by Week 1, but in-season moves creep in, so
#   these live only in the post-draft set (same caveat as the WR, QB and RB models).
# =============================================================================
team_te <- reg %>% filter(position == "TE") %>% group_by(team, season, player_id) %>%
  summarize(tgt = sum(coalesce(targets, 0)), pts = sum(fantasy_points_ppr, na.rm = TRUE), .groups = "drop")
on_team <- reg %>% distinct(team, season, player_id)
land <- team_te %>% mutate(next_season = season + 1) %>%
  left_join(on_team %>% mutate(stayed = TRUE), by = c("team", "next_season" = "season", "player_id")) %>%
  group_by(team, next_season) %>%
  summarize(team_te_tgt_prev = sum(tgt), vacated_tgt_share = sum(tgt[is.na(stayed)]) / pmax(sum(tgt), 1),
            incumbent_pts = suppressWarnings(max(c(0, pts[!is.na(stayed)]))), .groups = "drop")
tbl <- tbl %>% left_join(land, by = c("draft_team" = "team", "draft_season" = "next_season"))

# =============================================================================
# PART 5: Checks, dictionary, EDA
# =============================================================================
check <- function(label, ok, detail = "") { cat(sprintf("[%s] %s %s\n", ifelse(ok, "PASS", "FAIL"), label, detail)); invisible(ok) }
train_ok <- tbl %>% filter(!is.na(total_pts_3yr))

cat("\n===== Targets =====\n")
check("one row per drafted TE", nrow(tbl) == nrow(te) && !any(duplicated(tbl[, c("draft_season", "pick")])))
check("3-year targets only for classes <= 2023", all(is.na(tbl$total_pts_3yr[tbl$draft_season > last_nfl_season - 2])))
check("hit8 implies hit16 implies hit24", all(train_ok$hit24_3yr >= train_ok$hit16_3yr & train_ok$hit16_3yr >= train_ok$hit8_3yr))
check("finish sum within [3, 180]", all(train_ok$finish_sum_3yr >= 3 & train_ok$finish_sum_3yr <= 3 * CAP))
cat("rows with a full 3-year target:", nrow(train_ok), "\n")
print(as.data.frame(train_ok %>% group_by(draft_season) %>%
  summarize(n = n(), hit24 = sum(hit24_3yr), hit16 = sum(hit16_3yr), hit8 = sum(hit8_3yr), mean_pts = round(mean(total_pts_3yr)),
            zero_pts = sum(total_pts_3yr == 0), .groups = "drop")), row.names = FALSE)
cat("total top-24 hits:", sum(train_ok$hit24_3yr), " top-16:", sum(train_ok$hit16_3yr), " top-8:", sum(train_ok$hit8_3yr),
    " top-32:", sum(train_ok$hit32_3yr), "of", nrow(train_ok), "\n")
cat("tiers (1 = top 8, 2 = 9-16, 3 = 17-24, 4 = rest):\n"); print(table(train_ok$tier))
print(as.data.frame(train_ok %>% mutate(grp = ifelse(round == 1, "R1", ifelse(round <= 3, "R2-3", "R4-7"))) %>%
  group_by(grp) %>% summarize(n = n(), hit24 = round(mean(hit24_3yr), 2), hit16 = round(mean(hit16_3yr), 2),
                              hit8 = round(mean(hit8_3yr), 2), median_finish_sum = median(finish_sum_3yr), .groups = "drop")), row.names = FALSE)
cat("\ntop-8 hits (name, class, pick, best finish, 3-yr pts):\n")
print(as.data.frame(train_ok %>% filter(hit8_3yr == 1) %>% arrange(draft_season, pick) %>%
  transmute(pfr_player_name, draft_season, pick, best_finish_3yr, total_pts_3yr = round(total_pts_3yr))), row.names = FALSE)
cat("\nDay 3 (round 4+) top-24 hits:\n")
print(as.data.frame(train_ok %>% filter(hit24_3yr == 1, round >= 4) %>% arrange(draft_season, pick) %>%
  transmute(pfr_player_name, draft_season, round, pick, best_finish_3yr)), row.names = FALSE)
cat("\nfinish by NFL year among training TEs (share top-24): y1", round(mean(train_ok$finish_y1 <= 24), 3),
    " y2", round(mean(train_ok$finish_y2 <= 24), 3), " y3", round(mean(train_ok$finish_y3 <= 24), 3), "\n")

cat("\n===== Feature coverage (% non-missing) =====\n")
feat_cols <- c("p_rec", "p_rec_yds", "p_ypr", "p_rec_share", "p_dominator", "p_ypta", "p_ppa_pass",
               "breakout_age_filled", "age_at_draft", "height_in", "forty", "weight_lb", "speed_score", "vertical",
               "broad_jump", "recruit_rating", "vacated_tgt_share", "incumbent_pts")
print(round(100 * colMeans(!is.na(tbl[, feat_cols])), 1))
cat("college_thin (FCS / cfbd gap / unmatched) TEs:", sum(tbl$college_thin), "\n")
print(tbl %>% filter(college_thin == 1) %>% select(draft_season, pick, pfr_player_name, college, max_rec, p_team_rec) %>% as.data.frame(), row.names = FALSE)
cat("breakout (15%+ dominator) rate among matched:", round(mean(tbl$ever_breakout[tbl$college_matched == 1]), 3), "\n")

cat("\n===== Spearman correlation with total_pts_3yr (training classes) =====\n")
num_feats <- c("log_pick", "age_at_draft", "p_rec", "p_rec_yds", "p_rec_td", "p_ypr", "p_rec_share", "p_rec_yds_share",
               "p_dominator", "p_ypta", "p_ppa_pass", "best_dominator", "career_rec", "career_rec_yds", "career_ypr",
               "featured_seasons", "breakout_age_filled", "height_in", "weight_lb", "forty", "speed_score", "vertical",
               "broad_jump", "cone", "shuttle", "recruit_rating", "vacated_tgt_share", "incumbent_pts")
cors <- sapply(num_feats, function(v) suppressWarnings(cor(train_ok[[v]], train_ok$total_pts_3yr,
                                                            method = "spearman", use = "pairwise.complete.obs")))
print(round(sort(cors), 3))
cat("\nhighly correlated pairs (|rho| > 0.8):\n")
cm <- suppressWarnings(cor(train_ok[, num_feats], method = "spearman", use = "pairwise.complete.obs"))
hi <- which(abs(cm) > 0.8 & upper.tri(cm), arr.ind = TRUE)
if (nrow(hi) > 0) print(data.frame(a = rownames(cm)[hi[, 1]], b = colnames(cm)[hi[, 2]], rho = round(cm[hi], 2))) else cat("none\n")
cat("\nwithin rounds 1-3 only (n =", sum(train_ok$round <= 3), "), Spearman with total_pts_3yr:\n")
r13 <- train_ok %>% filter(round <= 3)
print(round(sort(sapply(num_feats, function(v)
  suppressWarnings(cor(r13[[v]], r13$total_pts_3yr, method = "spearman", use = "pairwise.complete.obs")))), 3))

p1 <- ggplot(train_ok, aes(pick, total_pts_3yr)) + geom_point(alpha = 0.6, color = mycols[5]) +
  geom_smooth(se = TRUE, color = mycols[6]) + scale_x_log10() +
  labs(title = "TE 3-year PPR points vs draft pick (log scale)", x = "Draft pick", y = "PPR points, years 1-3")
ggsave("plot_p2_pts_vs_pick.png", p1, width = 7, height = 5, dpi = 150)
p2 <- ggplot(train_ok %>% filter(!is.na(p_dominator)), aes(p_dominator, total_pts_3yr, color = round <= 3)) +
  geom_point(alpha = 0.7) + geom_smooth(se = FALSE, method = "loess", formula = y ~ x) +
  scale_color_manual(values = mycols[c(1, 5)], labels = c("Rounds 4-7", "Rounds 1-3"), name = NULL) +
  labs(title = "3-year PPR points vs college receiving dominator", x = "Primary-season dominator (mean of team rec yds and rec TD shares)", y = "PPR points, years 1-3")
ggsave("plot_p2_pts_vs_dominator.png", p2, width = 7, height = 5, dpi = 150)
p3 <- ggplot(train_ok %>% filter(!is.na(speed_score)), aes(speed_score, total_pts_3yr, color = round <= 3)) +
  geom_point(alpha = 0.7) + geom_smooth(se = FALSE, method = "loess", formula = y ~ x) +
  scale_color_manual(values = mycols[c(1, 5)], labels = c("Rounds 4-7", "Rounds 1-3"), name = NULL) +
  labs(title = "3-year PPR points vs speed score", x = "Speed score (weight x 200 / forty^4)", y = "PPR points, years 1-3")
ggsave("plot_p2_pts_vs_speed_score.png", p3, width = 7, height = 5, dpi = 150)

dict <- tribble(
  ~feature, ~set, ~definition,
  "total_pts_3yr", "target", "Regular-season PPR points (nflverse fantasy_points_ppr) in NFL years 1-3",
  "hit24_3yr / hit16_3yr / hit8_3yr", "target", "1 if any top-24 / top-16 / top-8 TE PPR season in years 1-3",
  "finish_y1..y3, finish_sum_3yr", "target", "Season TE rank capped at 60; sum over years 1-3 (3 best, 180 worst)",
  "tier", "target", "Best finish yrs 1-3: 1 = top 8, 2 = 9-16, 3 = 17-24, 4 = rest",
  "p_*", "pre-draft", "Primary college season = last season with 15+ receptions (else most receptions)",
  "p_rec, p_rec_yds, p_rec_td, p_ypr", "pre-draft", "Receiving volume and efficiency, primary season",
  "p_rec_share, p_rec_yds_share, p_rec_td_share", "pre-draft", "Share of team receptions / receiving yards / receiving TDs",
  "p_dominator, best_dominator", "pre-draft", "Mean of team receiving-yard and receiving-TD shares; primary season / best season",
  "p_ypta", "pre-draft", "Receiving yards per team pass attempt, primary season",
  "p_ppa_pass, p_usg_pass", "pre-draft", "cfbd predicted points added per target and passing usage; 2013+ seasons only",
  "career_*", "pre-draft", "Career receiving production",
  "breakout_age_filled, ever_breakout", "pre-draft", "Age (Sept 1) at first season with a 15%+ dominator; never = final age + 1",
  "featured_seasons", "pre-draft", "College seasons with 25+ receptions",
  "final_short", "pre-draft", "1 if the final college season had < 15 receptions but an earlier one had more",
  "college_thin", "pre-draft", "1 if cfbd coverage is thin (FCS), has a gap, or no match; college stats set to NA and imputed in-fold",
  "age_at_draft, height_in, weight_lb, forty, vertical, broad_jump, cone, shuttle", "pre-draft", "Age and combine",
  "speed_score", "pre-draft", "weight x 200 / forty^4",
  "recruit_rating", "pre-draft", "High-school TE recruiting rating",
  "log_pick, round1", "post-draft", "Draft capital",
  "vacated_tgt_share", "post-draft", "Share of drafting team's prior-season TE targets by TEs gone in the rookie season",
  "incumbent_pts", "post-draft", "Prior-season PPR points of the team's best returning TE"
)
write.csv(dict, "te_feature_dictionary.csv", row.names = FALSE)
saveRDS(as.data.frame(tbl), "te_model_table.rds")
cat("\nsaved te_model_table.rds (", nrow(tbl), "rows,", ncol(tbl), "cols ), dictionary and 3 plots\n")
check("Phase 2 ready for Phase 3", nrow(train_ok) >= 180 && sum(train_ok$hit24_3yr) >= 30,
      sprintf("(%d training rows, %d top-24, %d top-16, %d top-8)", nrow(train_ok), sum(train_ok$hit24_3yr),
              sum(train_ok$hit16_3yr), sum(train_ok$hit8_3yr)))
