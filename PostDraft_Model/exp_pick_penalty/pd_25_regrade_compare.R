# =============================================================================
# FABLE build part 6: before / after tables for the post-draft regrade with log_pick unpenalized (dev copy only)
#   usage: Rscript pd_25_regrade_compare.R ../Football2_PostDraft_dev_unpen
# before = the live Football2_PostDraft outputs; after = the dev copy's pd_07 / pd_09 outputs. Writes pd25_*.csv.
# =============================================================================
suppressMessages(library(dplyr))
DEV <- commandArgs(trailingOnly = TRUE)[1]; LIVE <- "../Football2_PostDraft"
GR <- c("F", "D", "C-", "C", "C+", "B-", "B", "B+", "A-", "A", "A+")
a <- read.csv(file.path(LIVE, "pd_post_player_grades.csv"), stringsAsFactors = FALSE); b <- read.csv(file.path(DEV, "pd_post_player_grades.csv"), stringsAsFactors = FALSE)
j <- inner_join(a %>% select(position, class, pick, name, grade_before = post_grade, score_before = post_score, p_any_before = p_any, nfl_outcome),
                b %>% select(position, class, pick, grade_after = post_grade, score_after = post_score, p_any_after = p_any), by = c("position", "class", "pick")) %>%
  mutate(steps = match(grade_after, GR) - match(grade_before, GR), letter_before = substr(grade_before, 1, 1), letter_after = substr(grade_after, 1, 1))
cat("matched rows:", nrow(j), "of", nrow(a), "/", nrow(b), "\n")
ch <- j %>% group_by(position) %>% summarise(n = n(), grade_changed = sum(grade_before != grade_after), letter_changed = sum(letter_before != letter_after),
  up = sum(steps > 0), down = sum(steps < 0), moved_2plus = sum(abs(steps) >= 2), .groups = "drop")
ch <- bind_rows(ch, ch %>% summarise(position = "all", across(-position, sum)))
write.csv(ch, "pd25_grade_changes.csv", row.names = FALSE); print(as.data.frame(ch), row.names = FALSE)
mv <- j %>% arrange(desc(abs(steps)), desc(abs(score_after - score_before))) %>% head(25) %>%
  transmute(position, class, name, pick, grade_before, grade_after, steps, p_any_before = round(p_any_before, 3), p_any_after = round(p_any_after, 3), nfl_outcome)
write.csv(mv, "pd25_biggest_movers.csv", row.names = FALSE); cat("\n25 biggest movers:\n"); print(as.data.frame(mv), row.names = FALSE)
ma <- read.csv(file.path(LIVE, "pd_post_2027_mock_grades.csv"), stringsAsFactors = FALSE); mb <- read.csv(file.path(DEV, "pd_post_2027_mock_grades.csv"), stringsAsFactors = FALSE)
nm <- intersect(c("board_name", "name"), names(ma))[1]
mk <- inner_join(ma %>% select(name = all_of(nm), position, round, pick, grade_before = post_grade, p_any_before = p_any),
                 mb %>% select(name = all_of(nm), position, grade_after = post_grade, p_any_after = p_any), by = c("name", "position")) %>%
  mutate(p_any_before = round(p_any_before, 3), p_any_after = round(p_any_after, 3)) %>% arrange(round, pick)
write.csv(mk, "pd25_mock_2027_before_after.csv", row.names = FALSE); cat("\n2027 mock grades before / after:\n"); print(as.data.frame(mk), row.names = FALSE)
for (f in c("pd_post_grade_validation.csv", "pd_post_grade_vs_pick.csv", "pd_post_vs_pre_metrics.csv")) {
  x <- read.csv(file.path(LIVE, f)); y <- read.csv(file.path(DEV, f)); write.csv(y, paste0("pd25_after_", f), row.names = FALSE) }
vp <- inner_join(read.csv(file.path(LIVE, "pd_post_grade_vs_pick.csv")) %>% select(position, target, AUC_grade_before = AUC_grade, AUC_pick, spearman_before = spearman_pts, LRT_p_before = LRT_p),
                 read.csv(file.path(DEV, "pd_post_grade_vs_pick.csv")) %>% select(position, target, AUC_grade_after = AUC_grade, spearman_after = spearman_pts, LRT_p_after = LRT_p), by = c("position", "target"))
write.csv(vp, "pd25_grade_vs_pick_before_after.csv", row.names = FALSE); cat("\nAUC vs draft pick, before / after:\n"); print(as.data.frame(vp), row.names = FALSE)
band <- function(g) ifelse(substr(g, 1, 1) %in% c("A", "B", "C"), substr(g, 1, 1), "D/F")
hb <- bind_rows(read.csv(file.path(LIVE, "pd_post_grade_validation.csv")) %>% mutate(version = "before"), read.csv(file.path(DEV, "pd_post_grade_validation.csv")) %>% mutate(version = "after")) %>%
  mutate(band = band(grade)) %>% group_by(version, position, band) %>% summarise(n = sum(n), any_rate = round(sum(any_rate * n) / sum(n), 3), top_rate = round(sum(top_rate * n) / sum(n), 3), .groups = "drop")
write.csv(hb, "pd25_hit_rate_by_band_before_after.csv", row.names = FALSE); cat("\nhit rate by grade band (LOCO 2010-2023):\n"); print(as.data.frame(tidyr::pivot_wider(hb, names_from = version, values_from = c(n, any_rate, top_rate))), row.names = FALSE)
