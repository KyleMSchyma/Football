# =============================================================================
# Pre-Draft Model -- Phase 6: player grades for every drafted QB/RB/WR/TE,
# 2010-2026, plus projected 2027 prospects
#
# Score = expected tier points from the college-only model (no combine, no draft
# capital): 3 x P(top tier) + 2 x P(middle tier) + 1 x P(bottom tier) = p1 + p2 + p3.
#   2010-2023  leave-one-class-out predictions (each class scored by a model that never
#              saw it), so historical grades are honest out-of-sample grades
#   2024-2026  the final model (trained on 2010-2023), so also out-of-sample
#   2027       the final model on the in-progress 2026 college season, twice:
#              "pro-rated" (counting stats scaled to 12 games, the Phase 1 default) and
#              "as-is" (stats through ~week 10, pool built with PD_NO_SCALE=1)
# Grade = percentile of the score among drafted players at the same position in
#   2010-2023 (the reference population), mapped to A+ ... F. The same cut points apply
#   to every class, so a B+ in 2012 means the same thing as a B+ in 2027.
# Sanity checks (ATPA/PA style):
#   - NFL outcome next to every historical player (best finish in years 1-3, tier)
#   - hit rates by grade with bootstrap CIs (calibration / lift by grade)
#   - Spearman of score vs 3-year fantasy points; AUC vs a draft-slot-only benchmark
#   - nested logistic: does the grade add to draft slot? (likelihood-ratio test, AIC)
#   - hit rate by grade within draft-round bands (is the grade just re-learning draft slot?)
#   - biggest misses both ways
# Outputs: pd_player_grades.csv, pd_grade_scale.csv, pd_grade_validation.csv,
#          pd_grade_vs_pick.csv, pd_grade_by_round.csv, plot_grade_hit_rates.png
# Run after pd_01 (both default and PD_NO_SCALE=1), pd_02 (all positions).
# =============================================================================
source("pd_common.R"); source("pd_model_fns.R")
suppressMessages(library(ggplot2))
NTOP_2027 <- c(QB = 12, RB = 20, WR = 32, TE = 15)   # 2027 prospects inserted per position (same K as the class grades)
# Kyle's community watchlist: these 2027 players are always inserted (flagged), whatever their score.
# The list's order is NOT used; they are ranked by the model like everyone else. cfbd_name = name in cfbd if different.
WATCH <- read.csv("pd_2027_watchlist.csv", stringsAsFactors = FALSE) %>%
  mutate(nk = norm_name(ifelse(is.na(cfbd_name) | cfbd_name == "", name, cfbd_name)), sk = norm_school(team))
watch_found <- character(0)

# --- grade scale: percentile among drafted players at the position, 2010-2023 ------------
GRADE_CUTS <- c(0, .10, .25, .35, .45, .55, .65, .75, .85, .90, .95, 1.0001)
GRADES     <- c("F", "D", "C-", "C", "C+", "B-", "B", "B+", "A-", "A", "A+")
grade_from_pct <- function(p) as.character(cut(p, GRADE_CUTS, labels = GRADES, right = FALSE))
grade_band <- function(g) case_when(g %in% c("A+", "A", "A-") ~ "A range", g %in% c("B+", "B", "B-") ~ "B range",
                                    g %in% c("C+", "C", "C-") ~ "C range", TRUE ~ "D/F")

# --- NFL outcomes so far for 2024-2025 classes (weekly data runs through 2025) -----------
weekly <- readRDS(file.path(SHARED, "nfl_weekly_raw.rds"))
LAST_NFL <- max(weekly$season)
ranks <- weekly %>% filter(season_type == "REG", position %in% POSITIONS) %>%
  group_by(player_id, season) %>% summarize(position = first(position), pts = sum(fantasy_points_ppr, na.rm = TRUE), .groups = "drop") %>%
  group_by(season, position) %>% mutate(rk = rank(-pts, ties.method = "min")) %>% ungroup()

pool  <- readRDS("pd_pool.rds")
pasis <- readRDS("pd_pool_asis.rds")

# P(declares) for 2027 candidates, same model as pd_04 (reported as a flag only)
dec <- readRDS("pd_declare.rds") %>% mutate(yb = factor(pmin(pmax(yrs_next, 3), 6)), rr = coalesce(recruit_rating, 0), rr_na = as.integer(is.na(recruit_rating)))
dfit <- glm(final ~ position * yb + yb * vol_pct + position:vol_pct + yb:rr + rr_na, family = binomial, data = dec)
vol_ref <- dec %>% filter(college_year == 2025)
p_declare <- function(b, POS) {
  vol <- switch(POS, QB = b$p_att, RB = b$p_car + b$p_rec, b$p_rec)
  b$position <- POS; b$vol_pct <- ecdf(vol_ref$vol[vol_ref$position == POS])(vol); b$rr <- coalesce(b$recruit_rating, 0)
  b$rr_na <- as.integer(is.na(b$recruit_rating)); b$yb <- factor(pmin(pmax(b$yrs_since_hs, 3), 6), levels = levels(dec$yb))
  as.numeric(predict(dfit, b, type = "response"))
}

out <- list()
for (POS in POSITIONS) {
  S <- readRDS(sprintf("pd_%s_models.rds", POS)); ch <- S$chosen
  pp <- pool %>% filter(position == POS)
  info <- pp %>% select(athlete_id, class, p_team, level, gsis_id, yrs_since_hs, recruit_stars, best_finish_3yr, total_pts_3yr)

  # 2010-2023 drafted: LOCO out-of-fold
  hist <- read.csv(sprintf("pd_%s_oof.csv", POS)) %>% filter(scheme == "LOCO", drafted == 1) %>%
    mutate(athlete_id = as.character(athlete_id)) %>%
    transmute(athlete_id, name, class, round, pick, tier,
              p1 = .data[[paste0("p1_", ch)]], p2 = .data[[paste0("p2_", ch)]], p3 = .data[[paste0("p3_", ch)]],
              score_source = "out-of-class (LOCO)") %>%
    left_join(info, by = c("athlete_id", "class"))

  # 2024-2026 drafted: final model
  rec <- pp %>% filter(class %in% 2024:2026, drafted == 1)
  rec <- cbind(rec %>% select(athlete_id, name, class, round, pick, tier, p_team, level, gsis_id, yrs_since_hs, recruit_stars,
                              best_finish_3yr, total_pts_3yr),
               predict_all(S, rec)[, paste0("p", 1:3, "_", ch)] %>% setNames(c("p1", "p2", "p3"))) %>%
    mutate(score_source = "final model (trained 2010-2023)")

  # 2027 projected: final model, pro-rated and as-is
  sc27 <- function(d) cbind(d %>% select(athlete_id, name, p_team, level, yrs_since_hs, recruit_stars, recruit_rating, p_att, p_car, p_rec),
                            predict_all(S, d)[, paste0("p", 1:3, "_", ch)] %>% setNames(c("p1", "p2", "p3"))) %>%
    mutate(score = p1 + p2 + p3)
  pr <- sc27(pp %>% filter(class == 2027))
  pr$p_declare <- p_declare(pr, POS)
  as <- sc27(pasis %>% filter(position == POS, class == 2027)) %>% select(athlete_id, p1_asis = p1, p2_asis = p2, p3_asis = p3, score_asis = score)
  wl_ids <- pr %>% filter(paste(norm_name(name), norm_school(p_team)) %in% paste(WATCH$nk, WATCH$sk)) %>% pull(athlete_id)
  keep <- union(union(pr %>% arrange(desc(score)) %>% head(NTOP_2027[POS]) %>% pull(athlete_id),
                      as %>% arrange(desc(score_asis)) %>% head(NTOP_2027[POS]) %>% pull(athlete_id)), wl_ids)
  watch_found <- c(watch_found, paste(norm_name(pr$name), norm_school(pr$p_team))[pr$athlete_id %in% wl_ids])
  proj <- pr %>% filter(athlete_id %in% keep) %>% left_join(as, by = "athlete_id") %>%
    mutate(community_list = as.integer(athlete_id %in% wl_ids)) %>%
    mutate(class = 2027L, round = NA, pick = NA, tier = NA, gsis_id = NA, best_finish_3yr = NA, total_pts_3yr = NA,
           score_source = "final model, 2026 season in progress") %>%
    select(-recruit_rating, -p_att, -p_car, -p_rec)

  d <- bind_rows(hist %>% mutate(status = "drafted"), rec %>% mutate(status = "drafted"), proj %>% mutate(status = "projected 2027")) %>%
    mutate(position = POS, score = p1 + p2 + p3)

  # grade scale from 2010-2023 drafted scores
  ref <- d %>% filter(status == "drafted", class <= 2023) %>% pull(score)
  pct <- function(x) sapply(x, function(v) mean(ref < v) + 0.5 * mean(ref == v))
  d <- d %>% mutate(pctile = pct(score), grade = grade_from_pct(pctile),
                    pctile_asis = ifelse(is.na(score_asis), NA, pct(score_asis)), grade_asis = ifelse(is.na(score_asis), NA, grade_from_pct(pctile_asis)))
  out[[POS]] <- d
  cat(POS, ": drafted 2010-2023", sum(d$status == "drafted" & d$class <= 2023), " 2024-26", sum(d$status == "drafted" & d$class >= 2024),
      " 2027 projected", sum(d$status != "drafted"), "\n")
}
G <- bind_rows(out)

# --- NFL outcome labels -----------------------------------------------------------------------
so_far <- G %>% filter(class %in% 2024:LAST_NFL, !is.na(gsis_id)) %>% select(position, gsis_id, class) %>%
  crossing(k = 0:2) %>% mutate(season = class + k) %>% filter(season <= LAST_NFL) %>%
  left_join(ranks %>% rename(nfl_pos = position), by = c("gsis_id" = "player_id", "season")) %>%
  mutate(rk = ifelse(!is.na(nfl_pos) & nfl_pos != position, NA, rk)) %>%
  group_by(gsis_id) %>% summarize(seasons = n(), best_sofar = suppressWarnings(min(rk, na.rm = TRUE)), pts_sofar = sum(pts, na.rm = TRUE), .groups = "drop") %>%
  mutate(best_sofar = ifelse(is.finite(best_sofar), best_sofar, NA))
G <- G %>% left_join(so_far, by = "gsis_id") %>%
  mutate(tier_cut = sapply(position, function(p) TIERS[[p]][3]),
         best_obs = ifelse(class <= 2023, best_finish_3yr, best_sofar),
         tier_obs = case_when(is.na(best_obs) ~ NA_integer_,
                              best_obs <= sapply(position, function(p) TIERS[[p]][1]) ~ 1L,
                              best_obs <= sapply(position, function(p) TIERS[[p]][2]) ~ 2L,
                              best_obs <= tier_cut ~ 3L, TRUE ~ 4L),
         tier = ifelse(class <= 2023, tier, tier_obs),
         nfl_outcome = case_when(
           status != "drafted" ~ "not yet drafted",
           class > LAST_NFL ~ "rookie season in progress",
           is.na(best_obs) | best_obs >= 999 ~ ifelse(class <= 2023, "no ranked season (yrs 1-3)", "no ranked season yet"),
           TRUE ~ paste0("best ", position, round(best_obs),
                         ifelse(tier == 4, " (no tier season)", paste0(" (", position, sapply(seq_along(tier), function(i) TIERS[[position[i]]][pmin(tier[i], 3)]), " hit)")),
                         ifelse(class <= 2023, "", paste0(", ", seasons, " season", ifelse(seasons > 1, "s", ""), " so far")))),
         nfl_pts = ifelse(class <= 2023, total_pts_3yr, pts_sofar),
         outcome_complete = class <= 2023)

G <- G %>% group_by(position) %>% mutate(pos_rank_all = rank(-score, ties.method = "first")) %>%
  group_by(position, class) %>% mutate(pos_rank_class = rank(-score, ties.method = "first")) %>% ungroup() %>%
  arrange(position, pos_rank_all)

final <- G %>% transmute(position, pos_rank_all, class, pos_rank_class, status, name, college = p_team, level,
                         yrs_out_of_hs = yrs_since_hs, recruit_stars, round, pick,
                         score = round(score, 3), pctile = round(pctile, 3), grade,
                         p_top = round(p1, 3), p_top2 = round(p2, 3), p_any = round(p3, 3),
                         score_asis = round(score_asis, 3), grade_asis, p_declare = round(p_declare, 2),
                         nfl_outcome, nfl_best_finish = ifelse(is.finite(best_obs) & best_obs < 999, best_obs, NA),
                         nfl_tier = tier, nfl_ppr_pts = round(nfl_pts, 1), outcome_complete, score_source,
                         data_flag = ifelse(level == "FCS" & class <= 2022, "thin college data (FCS before 2022: only games vs FBS logged)", ""),
                         community_list = ifelse(coalesce(community_list, 0L) == 1L, "yes", ""))
write.csv(final, "pd_player_grades.csv", row.names = FALSE, na = "")
miss_w <- WATCH %>% filter(!(paste(nk, sk) %in% watch_found))
cat("\ncommunity watchlist:", nrow(WATCH), "listed,", nrow(WATCH) - nrow(miss_w), "matched in the 2027 pool\n")
if (nrow(miss_w)) { cat("NOT matched:\n"); print(miss_w %>% select(name, listed_pos, team)) }
cat("\n===== Community watchlist players, model order =====\n")
print(as.data.frame(final %>% filter(community_list == "yes") %>% arrange(position, pos_rank_all) %>%
  select(position, pos_rank_all, name, college, score, grade, grade_asis)), row.names = FALSE)

# --- grade scale table --------------------------------------------------------------------
scale_tab <- bind_rows(lapply(POSITIONS, function(POS) {
  ref <- G %>% filter(position == POS, status == "drafted", class <= 2023) %>% pull(score)
  data.frame(position = POS, grade = rev(GRADES), pct_from = rev(head(GRADE_CUTS, -1)),
             min_score = round(sapply(rev(head(GRADE_CUTS, -1)), function(q) unname(quantile(ref, q, type = 1))), 3))
}))
write.csv(scale_tab, "pd_grade_scale.csv", row.names = FALSE)

# --- validation (drafted 2010-2023, complete outcomes) -----------------------------------
H <- G %>% filter(status == "drafted", class <= 2023) %>%
  mutate(y1 = as.integer(tier == 1), y2 = as.integer(tier <= 2), y3 = as.integer(tier <= 3), grade = factor(grade, levels = rev(GRADES)))
bootp <- function(y, B = 2000) { set.seed(2026); if (length(y) < 2) return(c(NA, NA)); q <- quantile(replicate(B, mean(sample(y, replace = TRUE))), c(.025, .975)); unname(q) }
val <- H %>% group_by(position, grade) %>% summarize(n = n(), mean_pick = round(mean(pick, na.rm = TRUE)),
  top_rate = mean(y1), top2_rate = mean(y2), any_rate = mean(y3), any_lo = bootp(y3)[1], any_hi = bootp(y3)[2],
  exp_any = mean(p3), mean_ppr_3yr = mean(total_pts_3yr, na.rm = TRUE), .groups = "drop") %>%
  mutate(across(where(is.double), ~ round(.x, 3)))
write.csv(val, "pd_grade_validation.csv", row.names = FALSE)
cat("\n===== Hit rates by grade, drafted 2010-2023 (any = any-tier season in years 1-3) =====\n"); print(as.data.frame(val), row.names = FALSE)

vp <- bind_rows(lapply(POSITIONS, function(POS) {
  h <- H %>% filter(position == POS, !is.na(pick)) %>% mutate(lpick = log(pick), lsc = qlogis(pmin(pmax(p3, 1e-4), 1 - 1e-4)))
  r <- list()
  for (k in 1:3) {
    y <- h[[paste0("y", k)]]
    m0 <- glm(y ~ lpick, family = binomial, data = h); m1 <- glm(y ~ lpick + lsc, family = binomial, data = h)
    lrt <- anova(m0, m1, test = "LRT")
    r[[k]] <- data.frame(position = POS, target = tier_labels(POS)[k], n = nrow(h), hits = sum(y),
      AUC_grade = aucf(y, h$score), AUC_pick = aucf(y, -h$pick), AUC_pick_plus_grade = aucf(y, fitted(m1)),
      spearman_pts = if (k == 1) cor(h$score, h$total_pts_3yr, method = "spearman", use = "complete.obs") else NA,
      spearman_pts_pick = if (k == 1) cor(-h$pick, h$total_pts_3yr, method = "spearman", use = "complete.obs") else NA,
      grade_coef = unname(coef(m1)["lsc"]), LRT_p = lrt$`Pr(>Chi)`[2], AIC_pick = AIC(m0), AIC_pick_plus_grade = AIC(m1))
  }
  bind_rows(r)
})) %>% mutate(across(where(is.double), ~ signif(.x, 3)))
write.csv(vp, "pd_grade_vs_pick.csv", row.names = FALSE)
cat("\n===== College-only grade vs draft slot (drafted 2010-2023) =====\n"); print(as.data.frame(vp), row.names = FALSE)

byr <- H %>% mutate(round_band = case_when(round == 1 ~ "Round 1", round <= 3 ~ "Rounds 2-3", TRUE ~ "Rounds 4-7"),
                    band = factor(grade_band(as.character(grade)), levels = c("A range", "B range", "C range", "D/F"))) %>%
  group_by(position, round_band, band) %>% summarize(n = n(), any_rate = round(mean(y3), 3), top2_rate = round(mean(y2), 3), .groups = "drop")
write.csv(byr, "pd_grade_by_round.csv", row.names = FALSE)
cat("\n===== Any-tier hit rate by grade band within draft-round band =====\n")
print(as.data.frame(byr %>% select(-top2_rate) %>% pivot_wider(names_from = band, values_from = c(n, any_rate))), row.names = FALSE)

cat("\n===== Biggest misses: A-range grades with no tier season; D/F grades that hit (2010-2023) =====\n")
for (POS in POSITIONS) {
  cat("--", POS, "-- high grade, no hit:\n")
  print(as.data.frame(final %>% filter(position == POS, class <= 2023, grade %in% c("A+", "A"), nfl_tier == 4) %>%
    select(class, name, college, pick, grade, nfl_outcome) %>% head(6)), row.names = FALSE)
  cat("-- low grade, top-tier hit:\n")
  print(as.data.frame(final %>% filter(position == POS, class <= 2023, grade %in% c("F", "D"), nfl_tier == 1) %>%
    select(class, name, college, pick, grade, nfl_outcome, data_flag)), row.names = FALSE)
}
cat("\nthin-data (FCS before 2022) players among drafted 2010-2023, by grade band:\n")
print(as.data.frame(final %>% filter(status == "drafted", class <= 2023) %>% mutate(b = grade_band(grade)) %>%
  group_by(position, b) %>% summarize(n = n(), thin = sum(data_flag != ""), .groups = "drop") %>%
  pivot_wider(names_from = b, values_from = c(n, thin))), row.names = FALSE)

cat("\n===== Top 15 all-time by position (drafted + projected 2027) =====\n")
for (POS in POSITIONS) { cat("--", POS, "--\n"); print(as.data.frame(final %>% filter(position == POS) %>% head(15) %>%
  select(pos_rank_all, class, status, name, college, pick, score, grade, grade_asis, nfl_outcome)), row.names = FALSE) }
cat("\n===== 2027 projected =====\n")
for (POS in POSITIONS) { cat("--", POS, "--\n"); print(as.data.frame(final %>% filter(position == POS, status != "drafted") %>%
  select(pos_rank_all, name, college, yrs_out_of_hs, score, grade, score_asis, grade_asis, p_declare)), row.names = FALSE) }

cat("\n===== Grade distribution by class (drafted) =====\n")
print(as.data.frame(final %>% filter(status == "drafted") %>% mutate(b = grade_band(grade)) %>% count(class, b) %>%
  pivot_wider(names_from = b, values_from = n, values_fill = 0)), row.names = FALSE)

# --- plot: hit rate by grade ------------------------------------------------------------
pv <- val %>% mutate(grade = factor(grade, levels = rev(GRADES)))
g <- ggplot(pv, aes(grade, any_rate)) + geom_col(fill = mycols[5], alpha = .85) +
  geom_errorbar(aes(ymin = any_lo, ymax = any_hi), width = .25, colour = "grey30") +
  geom_point(aes(y = exp_any), colour = mycols[6], size = 2) + facet_wrap(~position, nrow = 1) +
  labs(x = "college-only grade", y = "share with an any-tier season (yrs 1-3)",
       title = "Drafted 2010-2023: actual hit rate by pre-draft grade (bars, 95% bootstrap CI) vs model expectation (dots)") +
  theme_minimal(base_size = 11)
ggsave("plot_grade_hit_rates.png", g, width = 13, height = 4.2, dpi = 120)
cat("\ndone\n")
