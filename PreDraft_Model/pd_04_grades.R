# =============================================================================
# Pre-Draft Model -- Phase 4: class grades, position depth and player deep dives
#
# Class strength (per position, per class):
#   E1 / E2 / E3     expected number of top-tier / top-two-tier / any-tier hits
#                    (sum of player probabilities from the chosen model)
#   (sums run over the top K prospects of each class, K = KTOP below)
#   tier points      E1 + E2 + E3 (a top-tier hit counts 3, a middle-tier hit 2, a
#                    bottom-tier hit 1), the headline class-strength number
#   depth            expected any-tier hits from players ranked 4th or lower in the
#                    class, i.e. how much the class has beyond its top 3
#   Classes 2010-2023 use leave-one-class-out predictions (each class scored by a
#   model that never saw it); 2024-2027 use the final model.
# 2027: nobody has declared yet, so each 2026 college player is weighted by P(this
#   is his last college season), a logistic model by position on years out of high
#   school and 2026 volume percentile (fit on 2009-2025 seasons).
# Grades: the percentile of a class's tier points among the 2010-2023 classes,
#   A (top 10%), A-, B, C, C-, D, F (bottom 10%). Overall grade = percentile of the
#   average position z-score.
# Player deep dives (2026 and 2027): probabilities, key stats, top SHAP drivers and
#   the three nearest historical comps (2010-2023 pool players with known outcomes).
# Outputs: pd_class_grades.csv, pd_overall_grades.csv, pd_player_deep_dive.csv,
#   pd_class_validation.csv, plot_class_strength.png
# =============================================================================
source("pd_common.R"); source("pd_model_fns.R")
suppressMessages(library(ggplot2))

# --- P(last college season) for 2027 candidates ---------------------------------------------
dec <- readRDS("pd_declare.rds") %>% mutate(yb = factor(pmin(pmax(yrs_next, 3), 6)), rr = coalesce(recruit_rating, 0), rr_na = as.integer(is.na(recruit_rating)))
# high-volume, highly recruited underclassmen leave earlier: years x volume and recruiting terms
dfit <- glm(final ~ position * yb + yb * vol_pct + position:vol_pct + yb:rr + rr_na, family = binomial, data = dec)
cat("declare model: in-sample AUC", round(aucf(dec$final, fitted(dfit)), 3), "\n")
vol_ref <- dec %>% filter(college_year == 2025)

hist_l <- list(); cur_l <- list(); shap_l <- list(); S_l <- list()
for (POS in POSITIONS) {
  S <- readRDS(sprintf("pd_%s_models.rds", POS)); S_l[[POS]] <- S; ch <- S$chosen
  oof <- read.csv(sprintf("pd_%s_oof.csv", POS)) %>% filter(scheme == "LOCO")
  hist_l[[POS]] <- oof %>% transmute(position = POS, athlete_id = as.character(athlete_id), name, class, p_team, drafted,
    p1 = .data[[paste0("p1_", ch)]], p2 = .data[[paste0("p2_", ch)]], p3 = .data[[paste0("p3_", ch)]], tier, w = 1)
  b <- read.csv(sprintf("pd_%s_board.csv", POS)) %>% mutate(athlete_id = as.character(athlete_id), position = POS)
  vol <- switch(POS, QB = b$p_att, RB = b$p_car + b$p_rec, b$p_rec)
  ref <- vol_ref$vol[vol_ref$position == POS]
  b$vol_pct <- ecdf(ref)(vol); b$rr <- coalesce(b$recruit_rating, 0); b$rr_na <- as.integer(is.na(b$recruit_rating)); b$yb <- factor(pmin(pmax(b$yrs_since_hs, 3), 6), levels = levels(dec$yb))
  b$p_declare <- ifelse(b$class == 2027, predict(dfit, b, type = "response"), 1)
  cur_l[[POS]] <- b
  shap_l[[POS]] <- read.csv(sprintf("pd_%s_shap_prospects.csv", POS)) %>% mutate(athlete_id = as.character(athlete_id))
}
hist <- bind_rows(hist_l); cur <- bind_rows(cur_l)

# Only the top K prospects per class count (K = about the number drafted per class at the position),
# so a class isn't "stronger" just because cfbd logged more fringe players that year (the pool grows
# over time with FCS coverage and the transfer portal). 2027 weights fill K with P(declare).
KTOP <- c(QB = 12, RB = 20, WR = 32, TE = 15)
class_tbl <- function(d) d %>% group_by(position, class) %>% arrange(desc(p3), .by_group = TRUE) %>%
  mutate(w = pmax(0, pmin(w, KTOP[first(position)] - (cumsum(w) - w)))) %>%
  summarize(n_pool = n(), n_eff = sum(w), E1 = sum(w * p1), E2 = sum(w * p2), E3 = sum(w * p3),
            top3_E3 = sum((w * p3)[1:min(3, n())]), depth_E3 = E3 - top3_E3,
            A1 = if ("tier" %in% names(d)) sum(tier == 1, na.rm = TRUE) else NA,
            A2 = if ("tier" %in% names(d)) sum(tier <= 2, na.rm = TRUE) else NA,
            A3 = if ("tier" %in% names(d)) sum(tier <= 3, na.rm = TRUE) else NA, .groups = "drop") %>%
  mutate(tier_points = E1 + E2 + E3, actual_points = A1 + A2 + A3)

H <- class_tbl(hist) %>% mutate(period = "history (LOCO)")

# --- the eligible-pool view (needed for 2027, where nobody has declared yet) -----------------
# For class Y every player 3+ years out of high school with stats in season Y-1 is in the pool,
# whether he declared or went back to school. 2010-2023 pools are scored by a model refit without
# classes Y..Y+2 (a returning player's later row carries his outcome); 2024-2027 by the final model.
elig <- readRDS("pd_eligible_pool.rds")
pool_all <- readRDS("pd_pool.rds")
fit_chosen <- function(S, tr) {
  p <- fit_prep(tr, S$vars); X <- apply_prep(p, tr)
  fits <- lapply(1:3, function(k) {
    y <- as.integer(tr$tier <= k)
    if (S$chosen == "glm") suppressWarnings(glm(y ~ ., family = binomial, data = data.frame(X[, S$simple_vars, drop = FALSE], y = y)))
    else cv.glmnet(X, y, family = "binomial", alpha = 0.5, foldid = as.integer(factor(tr$class)))
  })
  function(d) { Xd <- apply_prep(p, d)
    pr <- sapply(fits, function(f) if (S$chosen == "glm") as.numeric(predict(f, data.frame(Xd[, S$simple_vars, drop = FALSE]), type = "response"))
                 else as.numeric(predict(f, Xd, s = "lambda.min", type = "response")))
    pr <- matrix(pr, ncol = 3); pr[, 2] <- pmax(pr[, 2], pr[, 1]); pr[, 3] <- pmax(pr[, 3], pr[, 2]); pr }
}
el <- list()
for (POS in POSITIONS) {
  S <- S_l[[POS]]; trn <- pool_all %>% filter(position == POS, outcome_known, class %in% TRAIN_CLASSES)
  for (Y in 2010:2027) {
    d <- elig %>% filter(position == POS, class == Y); if (!nrow(d)) next
    pr <- if (Y <= 2023) fit_chosen(S, trn %>% filter(!(class %in% Y:(Y + 2))))(d) else {
      a <- predict_all(S, d); as.matrix(a[, paste0("p", 1:3, "_", S$chosen)]) }
    el[[length(el) + 1]] <- data.frame(position = POS, class = Y, athlete_id = d$athlete_id, name = d$name, p1 = pr[, 1], p2 = pr[, 2], p3 = pr[, 3], w = 1)
  }
}
E <- class_tbl(bind_rows(el)) %>% select(-A1, -A2, -A3, -actual_points) %>%
  left_join(H %>% select(position, class, A1, A2, A3, actual_points), by = c("position", "class")) %>%
  mutate(period = ifelse(class <= 2023, "history (eligible pool)", ifelse(class == 2027, "2027 projected (eligible pool)", "eligible pool")))

pctl <- function(x, hx) sapply(x, function(v) mean(hx <= v))
grade_tbl <- function(G, hist_label) {
  ref <- G %>% filter(period == hist_label) %>% group_by(position) %>% summarize(mu = mean(tier_points), sdv = sd(tier_points), .groups = "drop")
  G %>% left_join(ref, by = "position") %>% group_by(position) %>%
    mutate(pct = pctl(tier_points, tier_points[period == hist_label]), depth_pct = pctl(depth_E3, depth_E3[period == hist_label])) %>% ungroup() %>%
    mutate(grade = grade_of(pct), depth_grade = grade_of(depth_pct), z = (tier_points - mu) / sdv) %>% select(-mu, -sdv) %>% arrange(position, class)
}
# 2010-2026: graded on the players who actually entered each class; 2027: graded on the eligible pool,
# against the eligible-pool versions of 2010-2023 (like for like)
C <- class_tbl(cur %>% filter(class <= 2026) %>% mutate(w = 1) %>% select(position, class, p1, p2, p3, w)) %>%
  mutate(A1 = NA, A2 = NA, A3 = NA, actual_points = NA, period = "drafted already")
G1 <- grade_tbl(bind_rows(H, C), "history (LOCO)")
G2 <- grade_tbl(E, "history (eligible pool)")
write.csv(G2 %>% mutate(across(where(is.double), ~ round(.x, 3))), "pd_eligible_pool_grades.csv", row.names = FALSE)
grades <- bind_rows(G1, G2 %>% filter(class == 2027)) %>% arrange(position, class)
write.csv(grades %>% mutate(across(where(is.double), ~ round(.x, 3))), "pd_class_grades.csv", row.names = FALSE)

ov <- function(G, hist_label) {
  o <- G %>% group_by(class, period) %>% summarize(n_pos = n(), z = mean(z), actual = sum(actual_points), expected = sum(tier_points), .groups = "drop") %>% filter(n_pos == 4)
  o$pct <- pctl(o$z, o$z[o$period == hist_label]); o$grade <- grade_of(o$pct); o }
O1 <- ov(G1, "history (LOCO)"); O2 <- ov(G2, "history (eligible pool)")
overall <- bind_rows(O1, O2 %>% filter(class == 2027)) %>% arrange(class)
write.csv(overall %>% mutate(across(where(is.double), ~ round(.x, 3))), "pd_overall_grades.csv", row.names = FALSE)
cat("\n===== Eligible-pool view: does it track actual class strength too? (2010-2023) =====\n")
print(as.data.frame(G2 %>% filter(class <= 2023) %>% group_by(position) %>% summarize(corr = round(cor(tier_points, actual_points), 3),
  spearman = round(cor(tier_points, actual_points, method = "spearman"), 3), .groups = "drop") %>%
  bind_rows(O2 %>% filter(class <= 2023) %>% summarize(position = "ALL", corr = round(cor(expected, actual), 3), spearman = round(cor(expected, actual, method = "spearman"), 3)))), row.names = FALSE)
cat("eligible-pool grades, 2020-2027:\n")
print(as.data.frame(G2 %>% filter(class >= 2020) %>% transmute(position, class, n_pool, points = round(tier_points, 2), actual = actual_points, grade, depth_grade)), row.names = FALSE)
print(as.data.frame(O2 %>% mutate(across(where(is.double), ~ round(.x, 2)))), row.names = FALSE)

cat("\n===== Does expected class strength track actual class strength? (2010-2023, LOCO) =====\n")
val <- bind_rows(H %>% group_by(position) %>% summarize(classes = n(), corr_points = cor(tier_points, actual_points),
                                                        spearman = cor(tier_points, actual_points, method = "spearman"),
                                                        mean_expected = mean(tier_points), mean_actual = mean(actual_points), .groups = "drop"),
                 overall %>% filter(class <= 2023) %>% summarize(position = "ALL", classes = n(), corr_points = cor(expected, actual),
                                                              spearman = cor(expected, actual, method = "spearman"),
                                                              mean_expected = mean(expected), mean_actual = mean(actual)))
print(as.data.frame(val %>% mutate(across(where(is.double), ~ round(.x, 3)))), row.names = FALSE)
write.csv(val, "pd_class_validation.csv", row.names = FALSE)
set.seed(2026)
for (POS in c(POSITIONS)) { h <- H %>% filter(position == POS)
  perm <- replicate(2000, cor(h$tier_points, sample(h$actual_points)))
  cat(sprintf("%s permutation test, corr %.3f, one-sided p = %.3f\n", POS, cor(h$tier_points, h$actual_points), mean(perm >= cor(h$tier_points, h$actual_points)))) }

cat("\n===== Class grades =====\n")
print(as.data.frame(grades %>% filter(class >= 2020) %>% transmute(position, class, n_eff = round(n_eff), E1 = round(E1, 2), E2 = round(E2, 2), E3 = round(E3, 2),
  depth = round(depth_E3, 2), points = round(tier_points, 2), actual = actual_points, grade, depth_grade)), row.names = FALSE)
cat("\n===== Overall class grades =====\n"); print(as.data.frame(overall %>% mutate(across(where(is.double), ~ round(.x, 2)))), row.names = FALSE)

g <- ggplot(grades, aes(class, tier_points, fill = period)) + geom_col() +
  geom_point(aes(y = actual_points), shape = 21, fill = "white", size = 2) +
  facet_wrap(~ position, scales = "free_y") + scale_fill_manual(values = mycols[c(5, 1, 3)]) + theme_minimal() +
  labs(y = "expected tier points (bars) vs actual (dots)", x = "draft class", fill = NULL,
       title = "Class strength from college data only") + theme(legend.position = "bottom")
ggsave("plot_class_strength.png", g, width = 10, height = 6, dpi = 120)

# --- NFL check for 2026: what did draft position imply? -----------------------------------
nfl_any <- bind_rows(
  read.csv("../Football2_QB/qb_finish_tier_board_2024_2026.csv") %>% transmute(position = "QB", draft_season, pick, p_nfl = p_top24_pick),
  read.csv("../Football2_RB/rb_finish_tier_board_2024_2026.csv") %>% transmute(position = "RB", draft_season, pick, p_nfl = p_top24_pick),
  read.csv("../Football2_TE/te_finish_tier_board_2024_2026.csv") %>% transmute(position = "TE", draft_season, pick, p_nfl = p_top24_pick),
  read.csv("../Football2/wr_tier_board_2024_2026.csv") %>% transmute(position = "WR", draft_season, pick, p_nfl = pick_only_p_wr3plus))
cmp <- cur %>% filter(drafted == 1, class <= 2026) %>% select(position, class, pick, name, p3) %>%
  left_join(nfl_any, by = c("position", "class" = "draft_season", "pick"))
cat("\n===== 2024-2026 drafted players: college-only expected any-tier hits vs draft-slot expected =====\n")
print(as.data.frame(cmp %>% group_by(position, class) %>% summarize(n = n(), college_E3 = round(sum(p3), 2), draft_E3 = round(sum(p_nfl, na.rm = TRUE), 2),
                                                                  corr = round(cor(p3, p_nfl, use = "complete.obs", method = "spearman"), 2), .groups = "drop")), row.names = FALSE)

# --- player deep dives ----------------------------------------------------------------------
pool <- readRDS("pd_pool.rds")
nice <- c(yrs_since_hs = "years out of HS", recruit_rating = "recruiting rating", college_seasons = "college seasons",
          power5 = "Power 5", fbs = "FBS school", transferred = "transferred", early = "early entrant", final_short = "short final year",
          recruit_missing = "no recruiting record", ever_breakout = "broke out", breakout_yrs = "breakout year (yrs from HS)",
          p_att = "pass attempts", p_comp_pct = "completion %", p_ypa = "yards/att", p_aya = "adj. yards/att",
          p_td_rate = "TD rate", p_int_rate = "INT rate", p_pass_share = "share of team attempts", p_rush_yds = "rush yards",
          p_rush_td = "rush TDs", best_aya = "best-season AY/A", career_att = "career attempts", career_rush_yds = "career rush yards",
          starter_seasons = "200+ attempt seasons", p_car = "carries", p_ypc = "yards/carry", p_rec = "receptions",
          p_rec_yds = "receiving yards", p_rec_td = "receiving TDs", p_car_share = "share of team carries",
          p_scrim_share = "share of team scrimmage yards", p_td_share = "share of team TDs", p_rec_share = "share of team catches",
          best_scrim_share = "best scrimmage-yard share", career_rec = "career receptions", featured_seasons = "featured seasons",
          p_ypr = "yards/catch", p_dominator = "dominator", p_ypta = "yards per team pass att", best_dominator = "best dominator",
          career_rec_yds = "career receiving yards")
fmt_driver <- function(v, val, s) sprintf("%s %s (%+.2f)", nice[v] %||% v, ifelse(is.na(val), "n/a", format(round(val, 2), nsmall = 0)), s)
`%||%` <- function(a, b) ifelse(is.na(a), b, a)
NTOP <- c(QB = 8, RB = 12, WR = 15, TE = 10)
dd <- list()
for (POS in POSITIONS) {
  S <- S_l[[POS]]; tr <- pool %>% filter(position == POS, outcome_known, class %in% TRAIN_CLASSES)
  topv <- head(read.csv(sprintf("pd_%s_importance.csv", POS))$variable, 8)
  Xtr <- apply_prep(S$M$prep, tr)[, topv]; mu <- colMeans(Xtr); sdv <- apply(Xtr, 2, sd); sdv[sdv == 0] <- 1
  hp3 <- hist %>% filter(position == POS) %>% pull(p3)
  for (Y in c(2026, 2027)) {
    b <- cur %>% filter(position == POS, class == Y) %>% mutate(rank_score = p3 * p_declare) %>% arrange(desc(p3)) %>% head(NTOP[POS])
    Xb <- apply_prep(S$M$prep, b)[, topv, drop = FALSE]
    for (i in seq_len(nrow(b))) {
      sh <- shap_l[[POS]] %>% filter(athlete_id == b$athlete_id[i], class == Y) %>% arrange(desc(shap))
      pos3 <- head(sh %>% filter(shap > 0), 3); neg3 <- head(sh %>% filter(shap < 0) %>% arrange(shap), 3)
      dist <- sqrt(colSums(((t(Xtr) - Xb[i, ]) / sdv)^2))
      comps <- tr[order(dist)[1:3], ]
      dd[[length(dd) + 1]] <- data.frame(position = POS, class = Y, rank = i, name = b$name[i], team = b$p_team[i],
        level = ifelse(b$fbs[i] == 1, ifelse(b$power5[i] == 1, "Power 5", "FBS"), "FCS or lower"),
        pick = b$pick[i], yrs_out_of_hs = b$yrs_since_hs[i], p_declare = round(b$p_declare[i], 2),
        p_top = round(b$p1[i], 3), p_mid = round(b$p2[i], 3), p_any = round(b$p3[i], 3),
        hist_pctl_any = round(mean(hp3 <= b$p3[i]), 3),
        plus = paste(fmt_driver(pos3$variable, pos3$value, pos3$shap), collapse = "; "),
        minus = paste(fmt_driver(neg3$variable, neg3$value, neg3$shap), collapse = "; "),
        comps = paste(sprintf("%s (%d, %s)", comps$name, comps$class,
                              ifelse(comps$tier <= 3, paste0("best ", POS, comps$best), ifelse(comps$nfl_linked == 1, "no tier season", "no NFL stats"))), collapse = "; "))
    }
  }
}
deep <- bind_rows(dd)
write.csv(deep, "pd_player_deep_dive.csv", row.names = FALSE)
cat("\n===== Player deep dives =====\n")
for (k in seq_len(nrow(deep))) with(deep[k, ], cat(sprintf("%s %d #%d %s (%s%s) yrs %s P(declare) %.2f | P %s: %.3f / %.3f / %.3f, hist pctl %.2f\n   + %s\n   - %s\n   comps: %s\n",
  position, class, rank, name, team, ifelse(is.na(pick), "", paste0(", pick ", pick)), yrs_out_of_hs, p_declare,
  paste(tier_labels(position), collapse = "/"), p_top, p_mid, p_any, hist_pctl_any, plus, minus, comps)))
