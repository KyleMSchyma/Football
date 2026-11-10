# =============================================================================
# WR Model -- Phase 2: targets and features (single script)
#
# Reads the Phase 1 outputs and builds one modeling table, one row per drafted
# WR (classes 2010-2026):
#
#   PART 1  Targets from NFL weekly stats (regular season, PPR)
#             total_ppr_3yr  total PPR points in NFL years 1-3 (0 if he never played)
#             hit_3yr        1 if any top-24 WR PPR season in years 1-3
#             ppg_3yr        PPR points per game over years 1-3 (NA under 8 games)
#             yr1_ppr / yr1_ppg / yr1_top24   rookie-season versions
#           3-year targets are NA for classes without 3 complete NFL seasons
#           (2024+); year-1 targets are NA for the 2026 class.
#   PART 2  College features: final season, career bests, breakout age
#   PART 3  Athletic, age, draft capital and recruiting features
#   PART 4  Landing spot (post-draft feature set only)
#   PART 5  Checks, feature dictionary and EDA plots
#
# PCA of combine drills, standardization and imputation are deliberately NOT done
# here: they must be fit inside each training fold in Phase 3 (ATPA 3.7a), or the
# test classes leak into the training data.
#
# Inputs (from Phase 1, same folder): wr_base.rds, wr_college_seasons.rds,
#   cache/nfl_weekly_raw.rds
# Outputs: wr_model_table.rds, wr_feature_dictionary.csv, plot_p2_*.png
# Requires: dplyr, tidyr, ggplot2
# =============================================================================

library(dplyr)
library(tidyr)
library(ggplot2)

mycols <- c("#E69F00", "#56B4E9", "#009E73", "#F0E442", "#0072B2", "#D55E00", "#CC79A7")

wr      <- readRDS("wr_base.rds")
cs      <- readRDS("wr_college_seasons.rds")
weekly  <- readRDS(file.path("cache", "nfl_weekly_raw.rds"))

last_nfl_season <- 2025
hit_rank        <- 24    # top-24 WR PPR season = a fantasy WR2 or better
min_games_ppg   <- 8

# Franchise codes: weekly stats and draft picks use different abbreviations, and
# some franchises moved. Map everything to today's code.
team_map <- c(GNB = "GB", KAN = "KC", NOR = "NO", NWE = "NE", SFO = "SF", TAM = "TB",
              LAR = "LA", RAM = "LA", STL = "LA", LVR = "LV", OAK = "LV",
              SDG = "LAC", SD = "LAC")
fix_team <- function(x) ifelse(x %in% names(team_map), unname(team_map[x]), x)

# =============================================================================
# PART 1: Targets
# =============================================================================
reg <- weekly %>%
  filter(season_type == "REG") %>%
  mutate(team = fix_team(team))

# Season totals for every player (needed to rank rookies against ALL WRs)
season_tot <- reg %>%
  group_by(player_id, season) %>%
  summarize(position = first(position),
            ppr      = sum(fantasy_points_ppr, na.rm = TRUE),
            games    = n_distinct(week),
            targets  = sum(targets, na.rm = TRUE),
            .groups  = "drop")

wr_rank <- season_tot %>%
  filter(position == "WR") %>%
  group_by(season) %>%
  mutate(wr_rank = rank(-ppr, ties.method = "min")) %>%
  ungroup() %>%
  select(player_id, season, wr_rank)

season_tot <- season_tot %>% left_join(wr_rank, by = c("player_id", "season"))

# Each drafted WR x NFL years 1-3 (a missing season = 0 points, a real bust)
yrs <- wr %>%
  select(gsis_id, draft_season = season, pick) %>%
  crossing(nfl_year = 1:3) %>%
  mutate(season = draft_season + nfl_year - 1) %>%
  filter(season <= last_nfl_season) %>%
  left_join(season_tot, by = c("gsis_id" = "player_id", "season")) %>%
  mutate(ppr = coalesce(ppr, 0), games = coalesce(games, 0L),
         targets = coalesce(targets, 0),
         top24 = !is.na(wr_rank) & wr_rank <= hit_rank)

targets <- yrs %>%
  group_by(draft_season, pick) %>%
  summarize(
    n_years_obs   = n(),
    total_ppr_3yr = sum(ppr),
    games_3yr     = sum(games),
    targets_3yr   = sum(targets),
    hit_3yr       = as.integer(any(top24)),
    best_ppr_season = max(ppr),
    yr1_ppr   = sum(ppr[nfl_year == 1]),
    yr1_games = sum(games[nfl_year == 1]),
    yr1_top24 = as.integer(any(top24[nfl_year == 1])),
    .groups = "drop") %>%
  mutate(
    ppg_3yr = ifelse(games_3yr >= min_games_ppg, total_ppr_3yr / games_3yr, NA_real_),
    yr1_ppg = ifelse(yr1_games >= min_games_ppg, yr1_ppr / yr1_games, NA_real_),
    # 3-year targets only where all 3 seasons are complete (right-censoring)
    across(c(total_ppr_3yr, games_3yr, targets_3yr, hit_3yr, best_ppr_season, ppg_3yr),
           ~ ifelse(n_years_obs == 3, .x, NA))
  )

# =============================================================================
# PART 2: College features
# =============================================================================
breakout_cut <- 0.20   # dominator rating that counts as a college "breakout"

col_feat <- cs %>%
  group_by(draft_season, pick) %>%
  arrange(college_year, .by_group = TRUE) %>%
  summarize(
    # final college season
    final_rec        = last(rec),
    final_rec_yds    = last(rec_yds),
    final_rec_td     = last(rec_td),
    final_yds_share  = last(yds_share),
    final_td_share   = last(td_share),
    final_dominator  = last(dominator),
    final_yptpa      = last(yptpa),
    final_power5     = last(power5),
    final_conference = last(conference),
    # career
    best_dominator   = suppressWarnings(max(dominator, na.rm = TRUE)),
    best_yds_share   = suppressWarnings(max(yds_share, na.rm = TRUE)),
    career_rec       = sum(rec),
    career_rec_yds   = sum(rec_yds),
    career_rush_yds  = sum(rush_yds),
    college_seasons  = n_distinct(college_year),
    college_teams    = n_distinct(team),
    # breakout age: age (Sept 1) in the first season with dominator >= 20%
    broke_out        = as.integer(any(dominator >= breakout_cut, na.rm = TRUE)),
    breakout_age     = suppressWarnings(min(age_sept1[dominator >= breakout_cut], na.rm = TRUE)),
    final_age        = last(age_sept1),
    .groups = "drop") %>%
  mutate(across(c(best_dominator, best_yds_share, breakout_age), ~ ifelse(is.infinite(.x), NA, .x)),
         # Never broke out: a common convention is final college age + 1, so the
         # model reads "never" as "later than anyone who did". broke_out keeps the
         # distinction explicit.
         breakout_age_filled = ifelse(broke_out == 1, breakout_age, final_age + 1),
         transferred = as.integer(college_teams > 1))

# =============================================================================
# PART 3: Athletic, age, draft capital, recruiting
# =============================================================================
drills <- c("forty", "vertical", "broad_jump", "cone", "shuttle", "bench")

tbl <- wr %>%
  rename(draft_season = season, draft_team = team) %>%
  left_join(targets,  by = c("draft_season", "pick")) %>%
  left_join(col_feat, by = c("draft_season", "pick")) %>%
  mutate(
    draft_team   = fix_team(draft_team),
    log_pick     = log(pick),
    round_f      = factor(round),
    day3         = as.integer(round >= 4),
    # speed score: weight-adjusted 40 time (Bill Barnwell's formula)
    speed_score  = ifelse(!is.na(forty) & !is.na(weight_lb), weight_lb * 200 / forty^4, NA_real_),
    bmi          = ifelse(!is.na(height_in) & !is.na(weight_lb), 703 * weight_lb / height_in^2, NA_real_),
    college_matched = as.integer(!is.na(athlete_id)),
    early_declare = as.integer(college_seasons <= 3 | (!is.na(age_at_draft) & age_at_draft < 21.5))
  )

# Drill-missing flags (a skipped drill is often a choice, so it carries signal)
for (d in drills) tbl[[paste0("miss_", d)]] <- as.integer(is.na(tbl[[d]]))

# =============================================================================
# PART 4: Landing spot (post-draft only)
# Vacated target share: share of the drafting team's prior-season targets that
# went to players who did not play for that team in the rookie season. Season-S
# rosters are known by Week 1, but in-season injuries/cuts creep in slightly, so
# this lives ONLY in the post-draft feature set.
# =============================================================================
team_tgt_prev <- reg %>%
  group_by(team, season, player_id) %>%
  summarize(tgt = sum(targets, na.rm = TRUE), .groups = "drop")
on_team <- team_tgt_prev %>% distinct(team, season, player_id)

vacated <- team_tgt_prev %>%
  mutate(next_season = season + 1) %>%
  left_join(on_team %>% mutate(stayed = TRUE),
            by = c("team", "next_season" = "season", "player_id")) %>%
  group_by(team, next_season) %>%
  summarize(team_targets_prev = sum(tgt),
            vacated_targets   = sum(tgt[is.na(stayed)]),
            .groups = "drop") %>%
  mutate(vacated_target_share = vacated_targets / team_targets_prev)

tbl <- tbl %>%
  left_join(vacated %>% select(team, next_season, team_targets_prev, vacated_target_share),
            by = c("draft_team" = "team", "draft_season" = "next_season"))

# =============================================================================
# PART 5: Checks, dictionary, EDA
# =============================================================================
check <- function(label, ok, detail = "") {
  cat(sprintf("[%s] %s %s\n", ifelse(ok, "PASS", "FAIL"), label, detail)); invisible(ok)
}
train_ok <- tbl %>% filter(!is.na(total_ppr_3yr))

cat("\n===== Targets =====\n")
check("one row per drafted WR", nrow(tbl) == nrow(wr) && !any(duplicated(tbl[, c("draft_season", "pick")])))
check("3-year targets only for classes <= 2023",
      all(is.na(tbl$total_ppr_3yr[tbl$draft_season > last_nfl_season - 2])))
check("NFL outcome found for most players",
      mean(tbl$yr1_games[tbl$draft_season <= last_nfl_season] > 0, na.rm = TRUE) > 0.6,
      sprintf("(%.1f%% played as rookies)",
              100 * mean(tbl$yr1_games[tbl$draft_season <= last_nfl_season] > 0, na.rm = TRUE)))
cat("rows with a full 3-year target:", nrow(train_ok), "\n")
print(train_ok %>% group_by(draft_season) %>%
        summarize(n = n(), hits = sum(hit_3yr), hit_rate = round(mean(hit_3yr), 2),
                  mean_ppr_3yr = round(mean(total_ppr_3yr)), zero_pts = sum(total_ppr_3yr == 0),
                  .groups = "drop"), n = 30)
cat("total hits:", sum(train_ok$hit_3yr), "of", nrow(train_ok), "\n")
cat("hit rate by round:\n")
print(train_ok %>% group_by(round) %>% summarize(n = n(), hit_rate = round(mean(hit_3yr), 2)))

cat("\n===== Feature coverage (% non-missing) =====\n")
feat_cols <- c("final_dominator", "best_dominator", "final_yptpa", "breakout_age_filled",
               "age_at_draft", "speed_score", "forty", "vertical", "broad_jump", "cone",
               "recruit_rating", "vacated_target_share")
feat_cols <- intersect(feat_cols, names(tbl))
print(round(100 * colMeans(!is.na(tbl[, feat_cols])), 1))

cat("\n===== Spearman correlation with total_ppr_3yr (training classes) =====\n")
num_feats <- c("log_pick", "age_at_draft", "final_dominator", "best_dominator", "final_yds_share",
               "final_yptpa", "breakout_age_filled", "career_rec_yds", "speed_score", "height_in",
               "weight_lb", "forty", "vertical", "broad_jump", "recruit_rating", "vacated_target_share")
num_feats <- intersect(num_feats, names(tbl))
cors <- sapply(num_feats, function(v)
  suppressWarnings(cor(train_ok[[v]], train_ok$total_ppr_3yr, method = "spearman", use = "pairwise.complete.obs")))
print(round(sort(cors), 3))

cat("\nhighly correlated feature pairs (|rho| > 0.8), candidates to drop or combine:\n")
cm <- suppressWarnings(cor(train_ok[, num_feats], method = "spearman", use = "pairwise.complete.obs"))
hi <- which(abs(cm) > 0.8 & upper.tri(cm), arr.ind = TRUE)
if (nrow(hi) > 0) print(data.frame(a = rownames(cm)[hi[, 1]], b = colnames(cm)[hi[, 2]],
                                   rho = round(cm[hi], 2))) else cat("none\n")

# --- EDA plots ---
p1 <- ggplot(train_ok, aes(x = pick, y = total_ppr_3yr)) +
  geom_point(alpha = 0.5, color = mycols[5]) + geom_smooth(se = TRUE, color = mycols[6]) +
  scale_x_log10() + labs(title = "3-year PPR points vs draft pick (log scale)",
                         x = "Draft pick", y = "Total PPR points, years 1-3")
ggsave("plot_p2_ppr_vs_pick.png", p1, width = 7, height = 5, dpi = 150)

p2 <- ggplot(train_ok %>% filter(!is.na(final_dominator)),
             aes(x = final_dominator, y = total_ppr_3yr, color = day3 == 1)) +
  geom_point(alpha = 0.6) + geom_smooth(se = FALSE) +
  scale_color_manual(values = mycols[c(5, 1)], labels = c("Rounds 1-3", "Rounds 4-7"), name = NULL) +
  labs(title = "3-year PPR points vs final-season dominator rating",
       x = "Final college season dominator", y = "Total PPR points, years 1-3")
ggsave("plot_p2_ppr_vs_dominator.png", p2, width = 7, height = 5, dpi = 150)

p3 <- ggplot(train_ok %>% filter(!is.na(breakout_age_filled)),
             aes(x = breakout_age_filled, fill = factor(hit_3yr))) +
  geom_histogram(binwidth = 0.5, position = "identity", alpha = 0.6) +
  scale_fill_manual(values = mycols[c(2, 6)], labels = c("No hit", "Top-24 season"), name = NULL) +
  labs(title = "Breakout age by 3-year outcome", x = "Breakout age (never = final age + 1)", y = "WRs")
ggsave("plot_p2_breakout_age.png", p3, width = 7, height = 5, dpi = 150)

# --- Feature dictionary ---
dict <- tribble(
  ~feature, ~set, ~definition,
  "total_ppr_3yr", "target", "Regular-season PPR points in NFL years 1-3; 0 if he never played",
  "hit_3yr", "target", "1 if any top-24 WR PPR season in years 1-3",
  "ppg_3yr", "target", "PPR points per game, years 1-3 (NA under 8 games)",
  "yr1_ppr / yr1_ppg / yr1_top24", "target", "Rookie-season versions",
  "final_dominator", "pre-draft", "Final college season: average of receiving yards share and TD share",
  "best_dominator", "pre-draft", "Best single-season dominator in college",
  "final_yds_share", "pre-draft", "Final season share of team receiving yards",
  "final_yptpa", "pre-draft", "Final season receiving yards per team pass attempt",
  "breakout_age / breakout_age_filled", "pre-draft", "Age on Sept 1 of first season with dominator >= 0.20; filled = final age + 1 if never",
  "broke_out", "pre-draft", "1 if any college season reached dominator >= 0.20",
  "career_rec_yds, career_rec", "pre-draft", "College career receiving totals",
  "college_seasons, transferred", "pre-draft", "Seasons with stats; 1 if played for 2+ schools",
  "early_declare", "pre-draft", "Proxy: 3 or fewer college seasons, or under 21.5 at the draft",
  "final_power5", "pre-draft", "Final season in SEC, Big Ten, Big 12, ACC, Pac-12 or Notre Dame",
  "age_at_draft", "pre-draft", "Decimal age on April 25 of the draft year",
  "height_in, weight_lb, bmi", "pre-draft", "Combine size",
  "forty, vertical, broad_jump, cone, shuttle, bench", "pre-draft", "Combine drills (PCA these inside folds in Phase 3)",
  "speed_score", "pre-draft", "weight x 200 / forty^4",
  "miss_*", "pre-draft", "1 if the drill was skipped",
  "recruit_rating, recruit_stars", "pre-draft", "247/cfbd high-school recruiting (about half covered)",
  "college_matched", "pre-draft", "0 if cfbd has no college record for him (impute + keep this flag)",
  "log_pick, round_f, day3", "post-draft", "Draft capital",
  "vacated_target_share", "post-draft", "Share of drafting team's prior-season targets that left",
  "team_targets_prev", "post-draft", "Drafting team's prior-season total targets",
  "career_window_covered", "flag", "FALSE for 2010-2012 classes: early college seasons may be missing, so breakout age is less reliable"
)
write.csv(dict, "wr_feature_dictionary.csv", row.names = FALSE)

saveRDS(as.data.frame(tbl), "wr_model_table.rds")
cat("\nsaved wr_model_table.rds (", nrow(tbl), "rows,", ncol(tbl), "columns ),",
    "wr_feature_dictionary.csv and 3 plots\n")
check("Phase 2 ready for Phase 3", nrow(train_ok) >= 300 && sum(train_ok$hit_3yr) >= 40,
      sprintf("(%d training rows, %d hits)", nrow(train_ok), sum(train_ok$hit_3yr)))
