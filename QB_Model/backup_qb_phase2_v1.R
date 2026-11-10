# =============================================================================
# QB Model -- Phase 2: targets and features (single script)
#
# One row per drafted QB (classes 2010-2026).
#
#   PART 1  Targets (regular season, nflverse fantasy_points_ppr -- for QBs this
#           is standard 4-pt passing TD scoring plus the rare reception)
#             total_pts_3yr   fantasy points in NFL years 1-3 (0 if he never played)
#             hit24_3yr       1 if any top-24 QB season in years 1-3 (QB2 or better)
#             hit12_3yr       1 if any top-12 QB season in years 1-3 (QB1)
#             finish_y1..y3   season QB rank, capped at 50 (didn't play / worse = 50)
#             finish_sum_3yr  sum of the three (3 best, 150 worst)
#             tier            1 = QB1 (best finish <= 12), 2 = QB2 (13-24), 3 = below
#             starts_3yr      games with 15+ pass attempts (a start proxy)
#           3-year targets are NA for classes without 3 complete seasons (2024+).
#   PART 2  College features from the "primary" season: the last college season
#           with 150+ attempts (so an injury-shortened final year doesn't count as
#           the profile; flagged final_short). Efficiency (comp %, YPA, AY/A,
#           TD and INT rates), share of team pass attempts, rushing yards and TDs
#           and share of team rushing, cfbd PPA per pass / rush play and usage
#           (2013+ seasons only), career totals, starter seasons, age at first
#           starter season ("starter age", the QB analogue of breakout age).
#           cfbd only logs FCS QBs' games against FBS teams, so a QB with no
#           college season of 120+ attempts is treated as missing college data
#           (college_thin = 1) rather than as a bad season.
#   PART 3  Athletic, age, draft capital, recruiting
#   PART 4  Landing spot (post-draft only): vacated pass-attempt share and the
#           incumbent QB's prior-season fantasy points
#   PART 5  Checks, feature dictionary and EDA plots
#
# Inputs: qb_base.rds, qb_college_seasons.rds, ../Football2/cache/nfl_weekly_raw.rds
# Outputs: qb_model_table.rds, qb_feature_dictionary.csv, plot_p2_*.png
# =============================================================================

suppressMessages({ library(dplyr); library(tidyr); library(ggplot2) })
mycols <- c("#E69F00", "#56B4E9", "#009E73", "#F0E442", "#0072B2", "#D55E00", "#CC79A7")

qb     <- readRDS("qb_base.rds")
cs     <- readRDS("qb_college_seasons.rds")
weekly <- readRDS(file.path("..", "Football2", "cache", "nfl_weekly_raw.rds"))

last_nfl_season <- 2025; CAP <- 50; min_games_ppg <- 8
team_map <- c(GNB = "GB", KAN = "KC", NOR = "NO", NWE = "NE", SFO = "SF", TAM = "TB",
              LAR = "LA", RAM = "LA", STL = "LA", LVR = "LV", OAK = "LV", SDG = "LAC", SD = "LAC")
fix_team <- function(x) ifelse(x %in% names(team_map), unname(team_map[x]), x)

# =============================================================================
# PART 1: Targets
# =============================================================================
reg <- weekly %>% filter(season_type == "REG", season <= last_nfl_season) %>% mutate(team = fix_team(team))
season_tot <- reg %>% group_by(player_id, season) %>%
  summarize(position = first(position), pts = sum(fantasy_points_ppr, na.rm = TRUE),
            games = n_distinct(week), starts = sum(coalesce(attempts, 0) >= 15),
            .groups = "drop")
qb_rank <- season_tot %>% filter(position == "QB") %>% group_by(season) %>%
  mutate(qb_rank = rank(-pts, ties.method = "min")) %>% ungroup() %>% select(player_id, season, qb_rank)
season_tot <- season_tot %>% left_join(qb_rank, by = c("player_id", "season"))

yrs <- qb %>% select(gsis_id, draft_season = season, pick) %>% crossing(nfl_year = 1:3) %>%
  mutate(season = draft_season + nfl_year - 1) %>% filter(season <= last_nfl_season) %>%
  left_join(season_tot, by = c("gsis_id" = "player_id", "season")) %>%
  mutate(pts = coalesce(pts, 0), games = coalesce(games, 0L), starts = coalesce(starts, 0L),
         finish = pmin(coalesce(qb_rank, CAP), CAP))

targets <- yrs %>% group_by(draft_season, pick) %>%
  summarize(n_years_obs = n(), total_pts_3yr = sum(pts), games_3yr = sum(games), starts_3yr = sum(starts),
            hit24_3yr = as.integer(any(finish <= 24)), hit12_3yr = as.integer(any(finish <= 12)),
            best_finish_3yr = min(finish), finish_sum_3yr = sum(finish),
            finish_y1 = finish[nfl_year == 1][1], finish_y2 = finish[nfl_year == 2][1],
            finish_y3 = finish[nfl_year == 3][1],
            yr1_pts = sum(pts[nfl_year == 1]), yr1_games = sum(games[nfl_year == 1]),
            yr1_starts = sum(starts[nfl_year == 1]), .groups = "drop") %>%
  mutate(ppg_3yr = ifelse(games_3yr >= min_games_ppg, total_pts_3yr / games_3yr, NA_real_),
         across(c(total_pts_3yr, games_3yr, starts_3yr, hit24_3yr, hit12_3yr, best_finish_3yr,
                  finish_sum_3yr, ppg_3yr), ~ ifelse(n_years_obs == 3, .x, NA)),
         tier = case_when(is.na(best_finish_3yr) ~ NA_integer_, best_finish_3yr <= 12 ~ 1L,
                          best_finish_3yr <= 24 ~ 2L, TRUE ~ 3L))

# =============================================================================
# PART 2: College features
# =============================================================================
col_feat <- cs %>% group_by(draft_season, pick) %>% arrange(college_year, .by_group = TRUE) %>%
  mutate(primary = if (any(att >= 150)) college_year == max(college_year[att >= 150])
                   else college_year == college_year[which.max(att)]) %>%
  summarize(
    p_year = college_year[primary][1], p_team_pass_att = team_pass_att[primary][1],
    p_att = att[primary][1], p_comp_pct = comp_pct[primary][1], p_ypa = ypa[primary][1],
    p_aya = aya[primary][1], p_td_rate = td_rate[primary][1], p_int_rate = int_rate[primary][1],
    p_pass_share = pass_share[primary][1], p_rush_car = rush_car[primary][1],
    p_rush_yds = rush_yds[primary][1], p_rush_td = rush_td[primary][1],
    p_rush_share = rush_yds_share[primary][1], p_power5 = power5[primary][1],
    p_ppa_pass = ppa_pass[primary][1], p_ppa_rush = ppa_rush[primary][1], p_ppa_all = ppa_all[primary][1],
    p_usg_overall = usg_overall[primary][1], p_usg_rush = usg_rush[primary][1],
    final_att = last(att), final_short = as.integer(last(att) < 150 & any(att >= 150)),
    best_aya = suppressWarnings(max(aya[att >= 150], na.rm = TRUE)),
    career_att = sum(att), career_pass_yds = sum(pass_yds), career_pass_td = sum(pass_td),
    career_int = sum(pass_int), career_rush_yds = sum(rush_yds), career_rush_td = sum(rush_td),
    college_seasons = n_distinct(college_year), college_teams = n_distinct(team),
    starter_seasons = sum(att >= 200),
    starter_age = suppressWarnings(min(age_sept1[att >= 200], na.rm = TRUE)),
    final_age = last(age_sept1), .groups = "drop") %>%
  mutate(best_aya = ifelse(is.infinite(best_aya), NA, best_aya),
         starter_age = ifelse(is.infinite(starter_age), NA, starter_age),
         ever_starter = as.integer(starter_seasons > 0),
         starter_age_filled = ifelse(ever_starter == 1, starter_age, final_age + 1),
         transferred = as.integer(college_teams > 1),
         career_aya = ifelse(career_att > 0, (career_pass_yds + 20 * career_pass_td - 45 * career_int) / career_att, NA),
         # no season with 120+ attempts = FCS partial coverage (FBS starters all clear
         # this, including Justin Fields' 8-game 2020 season)
         college_thin = as.integer(is.na(p_att) | p_att < 120))

# Thin (FCS) coverage: efficiency, volume and share numbers are not trustworthy
thin_cols <- c("p_att", "p_comp_pct", "p_ypa", "p_aya", "p_td_rate", "p_int_rate", "p_pass_share",
               "p_rush_car", "p_rush_yds", "p_rush_td", "p_rush_share", "best_aya", "career_att",
               "career_pass_yds", "career_pass_td", "career_rush_yds", "career_rush_td", "career_aya",
               "starter_seasons", "starter_age_filled", "p_ppa_pass", "p_ppa_rush", "p_ppa_all",
               "p_usg_overall", "p_usg_rush")
for (v in thin_cols) col_feat[[v]][col_feat$college_thin == 1] <- NA

# =============================================================================
# PART 3: Athletic, age, draft capital, recruiting
# =============================================================================
tbl <- qb %>% rename(draft_season = season, draft_team = team) %>%
  left_join(targets, by = c("draft_season", "pick")) %>%
  left_join(col_feat, by = c("draft_season", "pick")) %>%
  mutate(draft_team = fix_team(draft_team), log_pick = log(pick), round_f = factor(round),
         day3 = as.integer(round >= 4), round1 = as.integer(round == 1),
         bmi = ifelse(!is.na(height_in) & !is.na(weight_lb), 703 * weight_lb / height_in^2, NA_real_),
         college_matched = as.integer(!is.na(athlete_id) & coalesce(college_thin, 1L) == 0),
         college_thin = coalesce(college_thin, 1L),
         early_declare = as.integer(coalesce(college_seasons, 5) <= 3 | (!is.na(age_at_draft) & age_at_draft < 22)),
         recruit_dual = coalesce(recruit_dual, 0L))
for (d in c("forty", "vertical", "broad_jump")) tbl[[paste0("miss_", d)]] <- as.integer(is.na(tbl[[d]]))

# =============================================================================
# PART 4: Landing spot (post-draft only)
#   vacated_att_share: share of the drafting team's prior-season pass attempts
#     thrown by players who did not play for that team in the rookie season
#   incumbent_pts: prior-season fantasy points of the team's leading QB who is
#     still on the team in the rookie season (0 if none)
#   Rookie-season rosters are known by Week 1, but in-season moves creep in, so
#   these live only in the post-draft set (same caveat as the WR model).
# =============================================================================
team_att <- reg %>% group_by(team, season, player_id) %>%
  summarize(att = sum(attempts, na.rm = TRUE), pts = sum(fantasy_points_ppr, na.rm = TRUE),
            pos = first(position), .groups = "drop")
on_team <- team_att %>% distinct(team, season, player_id)
land <- team_att %>% mutate(next_season = season + 1) %>%
  left_join(on_team %>% mutate(stayed = TRUE), by = c("team", "next_season" = "season", "player_id")) %>%
  group_by(team, next_season) %>%
  summarize(team_att_prev = sum(att), vacated_att_share = sum(att[is.na(stayed)]) / pmax(sum(att), 1),
            incumbent_pts = suppressWarnings(max(c(0, pts[pos == "QB" & !is.na(stayed)]))), .groups = "drop")
tbl <- tbl %>% left_join(land, by = c("draft_team" = "team", "draft_season" = "next_season"))

# =============================================================================
# PART 5: Checks, dictionary, EDA
# =============================================================================
check <- function(label, ok, detail = "") { cat(sprintf("[%s] %s %s\n", ifelse(ok, "PASS", "FAIL"), label, detail)); invisible(ok) }
train_ok <- tbl %>% filter(!is.na(total_pts_3yr))

cat("\n===== Targets =====\n")
check("one row per drafted QB", nrow(tbl) == nrow(qb) && !any(duplicated(tbl[, c("draft_season", "pick")])))
check("3-year targets only for classes <= 2023", all(is.na(tbl$total_pts_3yr[tbl$draft_season > last_nfl_season - 2])))
check("hit12 implies hit24", all(train_ok$hit24_3yr >= train_ok$hit12_3yr))
check("finish sum within [3, 150]", all(train_ok$finish_sum_3yr >= 3 & train_ok$finish_sum_3yr <= 3 * CAP))
cat("rows with a full 3-year target:", nrow(train_ok), "\n")
print(as.data.frame(train_ok %>% group_by(draft_season) %>%
  summarize(n = n(), hit24 = sum(hit24_3yr), hit12 = sum(hit12_3yr), mean_pts = round(mean(total_pts_3yr)),
            zero_pts = sum(total_pts_3yr == 0), .groups = "drop")), row.names = FALSE)
cat("total top-24 hits:", sum(train_ok$hit24_3yr), " top-12 hits:", sum(train_ok$hit12_3yr), "of", nrow(train_ok), "\n")
print(as.data.frame(train_ok %>% mutate(grp = ifelse(round == 1, "R1", ifelse(round <= 3, "R2-3", "R4-7"))) %>%
  group_by(grp) %>% summarize(n = n(), hit24 = round(mean(hit24_3yr), 2), hit12 = round(mean(hit12_3yr), 2),
                              median_finish_sum = median(finish_sum_3yr), .groups = "drop")), row.names = FALSE)
cat("\ntop-12 hits (name, class, pick, best finish, 3-yr pts):\n")
print(as.data.frame(train_ok %>% filter(hit12_3yr == 1) %>% arrange(draft_season, pick) %>%
  transmute(pfr_player_name, draft_season, pick, best_finish_3yr, total_pts_3yr = round(total_pts_3yr))), row.names = FALSE)
cat("\nDay 2-3 (round 2+) top-24 hits:\n")
print(as.data.frame(train_ok %>% filter(hit24_3yr == 1, round >= 2) %>% arrange(draft_season, pick) %>%
  transmute(pfr_player_name, draft_season, round, pick, best_finish_3yr)), row.names = FALSE)

cat("\n===== Feature coverage (% non-missing) =====\n")
feat_cols <- c("p_aya", "p_comp_pct", "p_pass_share", "p_rush_yds", "p_rush_share", "p_ppa_pass",
               "starter_age_filled", "age_at_draft", "forty", "height_in", "recruit_rating",
               "vacated_att_share", "incumbent_pts")
print(round(100 * colMeans(!is.na(tbl[, feat_cols])), 1))
cat("college_thin (FCS / missing) QBs:", sum(tbl$college_thin), "\n")
print(tbl %>% filter(college_thin == 1) %>% select(draft_season, pick, pfr_player_name, college) %>% as.data.frame(), row.names = FALSE)

cat("\n===== Spearman correlation with total_pts_3yr (training classes) =====\n")
num_feats <- c("log_pick", "age_at_draft", "p_aya", "p_ypa", "p_comp_pct", "p_td_rate", "p_int_rate",
               "p_pass_share", "p_rush_yds", "p_rush_td", "p_rush_share", "p_ppa_pass", "p_ppa_rush",
               "best_aya", "career_att", "career_rush_yds", "starter_seasons", "starter_age_filled",
               "height_in", "weight_lb", "forty", "recruit_rating", "vacated_att_share", "incumbent_pts")
cors <- sapply(num_feats, function(v) suppressWarnings(cor(train_ok[[v]], train_ok$total_pts_3yr,
                                                            method = "spearman", use = "pairwise.complete.obs")))
print(round(sort(cors), 3))
cat("\nhighly correlated pairs (|rho| > 0.8):\n")
cm <- suppressWarnings(cor(train_ok[, num_feats], method = "spearman", use = "pairwise.complete.obs"))
hi <- which(abs(cm) > 0.8 & upper.tri(cm), arr.ind = TRUE)
if (nrow(hi) > 0) print(data.frame(a = rownames(cm)[hi[, 1]], b = colnames(cm)[hi[, 2]], rho = round(cm[hi], 2))) else cat("none\n")
cat("\nwithin round 1 only (n =", sum(train_ok$round == 1), "), Spearman with total_pts_3yr:\n")
r1 <- train_ok %>% filter(round == 1)
print(round(sort(sapply(setdiff(num_feats, "vacated_att_share"), function(v)
  suppressWarnings(cor(r1[[v]], r1$total_pts_3yr, method = "spearman", use = "pairwise.complete.obs")))), 3))

p1 <- ggplot(train_ok, aes(pick, total_pts_3yr)) + geom_point(alpha = 0.6, color = mycols[5]) +
  geom_smooth(se = TRUE, color = mycols[6]) + scale_x_log10() +
  labs(title = "QB 3-year fantasy points vs draft pick (log scale)", x = "Draft pick", y = "Fantasy points, years 1-3")
ggsave("plot_p2_pts_vs_pick.png", p1, width = 7, height = 5, dpi = 150)
p2 <- ggplot(train_ok %>% filter(!is.na(p_rush_yds)), aes(p_rush_yds, total_pts_3yr, color = round == 1)) +
  geom_point(alpha = 0.7) + geom_smooth(se = FALSE, method = "loess", formula = y ~ x) +
  scale_color_manual(values = mycols[c(1, 5)], labels = c("Rounds 2-7", "Round 1"), name = NULL) +
  labs(title = "3-year fantasy points vs primary-season college rushing yards", x = "College rushing yards", y = "Fantasy points, years 1-3")
ggsave("plot_p2_pts_vs_rushing.png", p2, width = 7, height = 5, dpi = 150)
p3 <- ggplot(train_ok %>% filter(!is.na(p_aya)), aes(p_aya, total_pts_3yr, color = round == 1)) +
  geom_point(alpha = 0.7) + geom_smooth(se = FALSE, method = "loess", formula = y ~ x) +
  scale_color_manual(values = mycols[c(1, 5)], labels = c("Rounds 2-7", "Round 1"), name = NULL) +
  labs(title = "3-year fantasy points vs college AY/A", x = "Primary-season adjusted yards per attempt", y = "Fantasy points, years 1-3")
ggsave("plot_p2_pts_vs_aya.png", p3, width = 7, height = 5, dpi = 150)

dict <- tribble(
  ~feature, ~set, ~definition,
  "total_pts_3yr", "target", "Regular-season fantasy points (nflverse PPR column; 4-pt pass TD) in NFL years 1-3",
  "hit24_3yr / hit12_3yr", "target", "1 if any top-24 / top-12 QB season in years 1-3",
  "finish_y1..y3, finish_sum_3yr", "target", "Season QB rank capped at 50; sum over years 1-3 (3 best, 150 worst)",
  "tier", "target", "1 = QB1 (best finish <= 12), 2 = QB2 (13-24), 3 = below",
  "starts_3yr / yr1_starts", "outcome", "Games with 15+ pass attempts (start proxy)",
  "p_*", "pre-draft", "Primary college season = last season with 150+ attempts (else most attempts)",
  "p_aya", "pre-draft", "Adjusted yards per attempt: (yds + 20 TD - 45 INT) / att",
  "p_comp_pct, p_ypa, p_td_rate, p_int_rate", "pre-draft", "Passing efficiency, primary season",
  "p_pass_share", "pre-draft", "His attempts / team attempts (was he the starter all year)",
  "p_rush_yds, p_rush_td, p_rush_share", "pre-draft", "Rushing production and share of team rushing yards",
  "p_ppa_pass, p_ppa_rush, p_usg_overall", "pre-draft", "cfbd predicted points added per play and usage; 2013+ seasons only",
  "best_aya, career_aya, career_att, career_rush_yds", "pre-draft", "Career passing / rushing",
  "starter_seasons, starter_age_filled, ever_starter", "pre-draft", "Seasons with 200+ att; age (Sept 1) at first such season, never = final age + 1",
  "final_short", "pre-draft", "1 if the final college season had < 150 att but an earlier one had more",
  "college_thin", "pre-draft", "1 if cfbd coverage is thin (FCS) or missing; college stats set to NA and imputed in-fold",
  "age_at_draft, height_in, weight_lb, forty, vertical, broad_jump", "pre-draft", "Age and combine",
  "recruit_rating, recruit_dual", "pre-draft", "High-school recruiting (PRO / DUAL) rating; ~45% covered",
  "log_pick, round1", "post-draft", "Draft capital",
  "vacated_att_share", "post-draft", "Share of drafting team's prior-season pass attempts by players gone in the rookie season",
  "incumbent_pts", "post-draft", "Prior-season fantasy points of the team's best returning QB"
)
write.csv(dict, "qb_feature_dictionary.csv", row.names = FALSE)
saveRDS(as.data.frame(tbl), "qb_model_table.rds")
cat("\nsaved qb_model_table.rds (", nrow(tbl), "rows,", ncol(tbl), "cols ), dictionary and 3 plots\n")
check("Phase 2 ready for Phase 3", nrow(train_ok) >= 150 && sum(train_ok$hit24_3yr) >= 30,
      sprintf("(%d training rows, %d top-24 hits, %d top-12 hits)", nrow(train_ok), sum(train_ok$hit24_3yr), sum(train_ok$hit12_3yr)))
