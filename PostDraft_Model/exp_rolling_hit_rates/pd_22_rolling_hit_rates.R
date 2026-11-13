# =============================================================================
# FABLE build part 7 (finding 6): hit rate by grade band from STRICT ROLLING-ORIGIN predictions
# (test class Y = 2016-2023, models trained only on classes <= Y - 3), next to the leave-one-class-out (LOCO) numbers
# now published. Reads existing outputs only (nothing is refit, nothing live is changed).
#   pre-draft : Football2_PreDraft/pd_<POS>_oof.csv, scheme "Rolling", the chosen model per position (pd_<POS>_models.rds),
#               drafted players; graded with the published cut scores (pd_grade_scale.csv)
#   post-draft: the position models' rolling rows (QB/RB/TE phase4_oof_predictions.csv post ladder, WR phase6 post_enet);
#               graded with the published post-draft cut scores (pd_post_grade_scale.csv)
# Writes pd22_pre_grade_validation_rolling.csv, pd22_post_grade_validation_rolling.csv (same columns as the published
# *_grade_validation.csv) and pd22_band_comparison.csv (A / B / C / D-F, any tier and top tier, LOCO 2010-2023 as
# published, LOCO 2016-2023, rolling 2016-2023, with bootstrap intervals).
# =============================================================================
suppressMessages(library(dplyr))
PRE <- "../Football2_PreDraft"; POST <- "../Football2_PostDraft"
POS_DIR <- c(QB = "../Football2_QB", RB = "../Football2_RB", WR = "../Football2", TE = "../Football2_TE")
GR <- c("A+", "A", "A-", "B+", "B", "B-", "C+", "C", "C-", "D", "F")
band <- function(g) ifelse(substr(g, 1, 1) %in% c("A", "B", "C"), substr(g, 1, 1), "D/F")
grade_of <- function(sc, pos, scale) mapply(function(p, v) { g <- scale %>% filter(position == p, min_score <= v) %>% arrange(desc(min_score)); if (nrow(g)) g$grade[1] else "F" }, pos, sc)
bootp <- function(y, B = 2000) { set.seed(2026); if (length(y) < 2) return(c(NA, NA)); unname(quantile(replicate(B, mean(sample(y, replace = TRUE))), c(.025, .975))) }
val_tab <- function(H) H %>% group_by(position, grade) %>% summarise(n = n(), mean_pick = round(mean(pick, na.rm = TRUE)), top_rate = mean(y1), top2_rate = mean(y2),
  any_rate = mean(y3), any_lo = bootp(y3)[1], any_hi = bootp(y3)[2], exp_any = mean(q3), mean_ppr_3yr = NA_real_, .groups = "drop") %>%
  mutate(grade = factor(grade, GR)) %>% arrange(position, grade) %>% mutate(across(where(is.double), ~ round(.x, 3)))
band_tab <- function(H, version) H %>% mutate(band = band(as.character(grade))) %>% group_by(position, band) %>%
  summarise(n = n(), any_rate = mean(y3), any_lo = bootp(y3)[1], any_hi = bootp(y3)[2], top_rate = mean(y1), top_lo = bootp(y1)[1], top_hi = bootp(y1)[2], .groups = "drop") %>%
  mutate(version = version)

# ---------------- pre-draft ----------------
psc <- read.csv(file.path(PRE, "pd_grade_scale.csv"), stringsAsFactors = FALSE)
pre_roll <- bind_rows(lapply(names(POS_DIR), function(P) { ch <- readRDS(file.path(PRE, sprintf("pd_%s_models.rds", P)))$chosen
  read.csv(file.path(PRE, sprintf("pd_%s_oof.csv", P))) %>% filter(scheme == "Rolling", drafted == 1) %>%
    transmute(position = P, class, pick, tier, y1, y2, y3, q1 = .data[[paste0("p1_", ch)]], q2 = pmax(.data[[paste0("p2_", ch)]], q1), q3 = pmax(.data[[paste0("p3_", ch)]], q2), model = ch) %>%
    mutate(score = q1 + q2 + q3) }))
pre_roll$grade <- grade_of(pre_roll$score, pre_roll$position, psc)
pg <- read.csv(file.path(PRE, "pd_player_grades.csv"), stringsAsFactors = FALSE, na.strings = "") %>% filter(status == "drafted", class <= 2023, !is.na(nfl_tier)) %>%
  transmute(position, class, pick, grade, y1 = as.integer(nfl_tier == 1), y2 = as.integer(nfl_tier <= 2), y3 = as.integer(nfl_tier <= 3), q3 = p_any)
cat("pre-draft rolling rows:", nrow(pre_roll), " chosen models:", paste(unique(paste(pre_roll$position, pre_roll$model)), collapse = ", "), "\n")

# ---------------- post-draft ----------------
qsc <- read.csv(file.path(POST, "pd_post_grade_scale.csv"), stringsAsFactors = FALSE)
cols <- list(QB = c("p_top8_post", "p_top16_post", "p_top24_post"), RB = c("p_top8_post", "p_top16_post", "p_top24_post"), TE = c("p_top6_post", "p_top12_post", "p_top18_post"))
post_roll <- bind_rows(lapply(names(POS_DIR), function(P) {
  if (P == "WR") o <- read.csv(file.path(POS_DIR[[P]], "phase6_oof_predictions.csv")) %>% filter(scheme == "Rolling", model == "post_enet") %>%
      transmute(class = draft_season, pick, tier, q1 = p_wr1, q2 = p_wr2plus, q3 = p_wr3plus)
  else o <- read.csv(file.path(POS_DIR[[P]], "phase4_oof_predictions.csv")) %>% filter(scheme == "Rolling") %>%
      transmute(class = draft_season, pick, tier, q1 = .data[[cols[[P]][1]]], q2 = .data[[cols[[P]][2]]], q3 = .data[[cols[[P]][3]]])
  o %>% mutate(position = P, q2 = pmax(q2, q1), q3 = pmax(q3, q2), score = q1 + q2 + q3, y1 = as.integer(tier == 1), y2 = as.integer(tier <= 2), y3 = as.integer(tier <= 3)) }))
post_roll$grade <- grade_of(post_roll$score, post_roll$position, qsc)
qg <- read.csv(file.path(POST, "pd_post_player_grades.csv"), stringsAsFactors = FALSE, na.strings = "") %>% filter(class <= 2023, !is.na(nfl_tier)) %>%
  transmute(position, class, pick, grade = post_grade, y1 = as.integer(nfl_tier == 1), y2 = as.integer(nfl_tier <= 2), y3 = as.integer(nfl_tier <= 3), q3 = p_any)
cat("post-draft rolling rows:", nrow(post_roll), "\n")

write.csv(val_tab(pre_roll), "pd22_pre_grade_validation_rolling.csv", row.names = FALSE)
write.csv(val_tab(post_roll), "pd22_post_grade_validation_rolling.csv", row.names = FALSE)
B <- bind_rows(band_tab(pg, "pre LOCO 2010-2023 (published)") , band_tab(pg %>% filter(class >= 2016), "pre LOCO 2016-2023"), band_tab(pre_roll, "pre rolling 2016-2023"),
               band_tab(qg, "post LOCO 2010-2023 (published)"), band_tab(qg %>% filter(class >= 2016), "post LOCO 2016-2023"), band_tab(post_roll, "post rolling 2016-2023")) %>%
  mutate(across(where(is.double), ~ round(.x, 3))) %>% select(version, position, band, everything())
write.csv(B, "pd22_band_comparison.csv", row.names = FALSE)
# all positions together, A band
AB <- bind_rows(lapply(list(list(pg, "pre LOCO 2010-2023 (published)"), list(pg %>% filter(class >= 2016), "pre LOCO 2016-2023"), list(pre_roll, "pre rolling 2016-2023"),
                            list(qg, "post LOCO 2010-2023 (published)"), list(qg %>% filter(class >= 2016), "post LOCO 2016-2023"), list(post_roll, "post rolling 2016-2023")),
  function(z) z[[1]] %>% mutate(band = band(as.character(grade))) %>% group_by(band) %>% summarise(n = n(), any_rate = mean(y3), any_lo = bootp(y3)[1], any_hi = bootp(y3)[2],
    top_rate = mean(y1), .groups = "drop") %>% mutate(version = z[[2]]))) %>% mutate(across(where(is.double), ~ round(.x, 3))) %>% select(version, everything())
write.csv(AB, "pd22_band_comparison_all_positions.csv", row.names = FALSE)
options(width = 200); cat("\nALL POSITIONS, hit rate by grade band:\n"); print(as.data.frame(AB), row.names = FALSE)
cat("\nBY POSITION, A band:\n"); print(as.data.frame(B %>% filter(band == "A")), row.names = FALSE)
