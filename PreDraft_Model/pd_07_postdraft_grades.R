# =============================================================================
# Pre-Draft Model -- Phase 7: post-draft grades for every drafted QB/RB/WR/TE,
# 2010-2026, side by side with the pre-draft grades from Phase 6
#
# Post-draft model = the "post" tier ladder of each position model (QB/RB/TE phase 4,
# WR phase 6): college profile + age + draft pick + landing spot (vacated share,
# incumbent production). Ordinal elastic net, tiers QB/RB/TE 8/16/24, WR 12/24/36.
#   2010-2023  leave-one-class-out predictions (out-of-class, like Phase 6)
#   2024-2026  the final post model (trained on 2010-2023), from each position's board
# Score = expected tier points = P(top) + P(top two) + P(any tier).
# Grade = percentile among drafted players at the position in 2010-2023 (same A+..F
#   cut points as Phase 6, but against the post-draft score distribution).
# Comparison: pre-draft vs post-draft percentile, grade steps moved, and per class the
#   average move and how well each version ranked the class's actual results.
# Outputs: pd_post_player_grades.csv, pd_post_grade_validation.csv,
#          pd_post_vs_pre_metrics.csv, pd_post_class_summary.csv, plot_post_vs_pre.png
# Needs: pd_player_grades.csv (Phase 6) and the four position models' outputs.
# =============================================================================
source("pd_common.R")
suppressMessages(library(ggplot2))
GRADE_CUTS <- c(0, .10, .25, .35, .45, .55, .65, .75, .85, .90, .95, 1.0001)
GRADES     <- c("F", "D", "C-", "C", "C+", "B-", "B", "B+", "A-", "A", "A+")
grade_from_pct <- function(p) as.character(cut(p, GRADE_CUTS, labels = GRADES, right = FALSE))
gidx <- function(g) match(g, GRADES)   # 1 = F ... 11 = A+

pre <- read.csv("pd_player_grades.csv", stringsAsFactors = FALSE, na.strings = "") %>% filter(status == "drafted")

src <- list(
  QB = list(oof = file.path(POS_DIR[["QB"]], "phase4_oof_predictions.csv"), board = file.path(POS_DIR[["QB"]], "qb_finish_tier_board_2024_2026.csv"),
            cols = c("p_top8_post", "p_top16_post", "p_top24_post")),
  RB = list(oof = file.path(POS_DIR[["RB"]], "phase4_oof_predictions.csv"), board = file.path(POS_DIR[["RB"]], "rb_finish_tier_board_2024_2026.csv"),
            cols = c("p_top8_post", "p_top16_post", "p_top24_post")),
  TE = list(oof = file.path(POS_DIR[["TE"]], "phase4_oof_predictions.csv"), board = file.path(POS_DIR[["TE"]], "te_finish_tier_board_2024_2026.csv"),
            cols = c("p_top8_post", "p_top16_post", "p_top24_post")),
  WR = list(oof = file.path(POS_DIR[["WR"]], "phase6_oof_predictions.csv"), board = file.path(POS_DIR[["WR"]], "wr_tier_board_2024_2026.csv"),
            cols = c("post_enet_p_wr1", "post_enet_p_wr2plus", "post_enet_p_wr3plus")))

out <- list()
for (POS in POSITIONS) {
  s <- src[[POS]]
  o <- read.csv(s$oof, stringsAsFactors = FALSE)
  if (POS == "WR") {
    o <- o %>% filter(scheme == "LOCO", model == "post_enet") %>%
      transmute(class = draft_season, round, pick, name = pfr_player_name, q1 = p_wr1, q2 = p_wr2plus, q3 = p_wr3plus, post_tier = tier)
  } else {
    o <- o %>% filter(scheme == "LOCO") %>%
      transmute(class = draft_season, round, pick, name = pfr_player_name, q1 = p_top8_post, q2 = p_top16_post, q3 = p_top24_post, post_tier = tier)
  }
  b <- read.csv(s$board, stringsAsFactors = FALSE) %>%
    transmute(class = draft_season, round, pick, name = pfr_player_name, q1 = .data[[s$cols[1]]], q2 = .data[[s$cols[2]]], q3 = .data[[s$cols[3]]], post_tier = NA_integer_)
  d <- bind_rows(o %>% mutate(score_source = "out-of-class (LOCO)"), b %>% mutate(score_source = "final model (trained 2010-2023)")) %>%
    mutate(position = POS, q2 = pmax(q2, q1), q3 = pmax(q3, q2), post_score = q1 + q2 + q3)
  ref <- d %>% filter(class <= 2023) %>% pull(post_score)
  d$post_pctile <- sapply(d$post_score, function(v) mean(ref < v) + 0.5 * mean(ref == v))
  d$post_grade <- grade_from_pct(d$post_pctile)
  out[[POS]] <- d
}
P <- bind_rows(out)

# join to the pre-draft grade (same draft class + pick; name as a fallback for missing picks)
pre_j <- pre %>% select(position, class, pick, pre_name = name, college, level, round_pre = round, pre_score = score, pre_pctile = pctile, pre_grade = grade,
                        nfl_outcome, nfl_best_finish, nfl_tier, nfl_ppr_pts, outcome_complete, data_flag)
J <- P %>% left_join(pre_j, by = c("position", "class", "pick"))
cat("post-draft rows:", nrow(P), " matched to a pre-draft grade:", sum(!is.na(J$pre_grade)), "\n")
print(J %>% group_by(position) %>% summarize(n = n(), matched = sum(!is.na(pre_grade)), .groups = "drop") %>% as.data.frame())

# outcome for rows without a pre-draft match: the post model's own tier (2010-2023)
J <- J %>% mutate(nfl_tier = coalesce(nfl_tier, post_tier),
                  nfl_outcome = coalesce(nfl_outcome, ifelse(class <= 2023 & !is.na(post_tier),
                                         ifelse(post_tier == 4, "no tier season (yrs 1-3)", paste0(position, sapply(seq_along(post_tier), function(i) TIERS[[position[i]]][pmin(post_tier[i], 3)]), " hit")),
                                         ifelse(class == 2026, "rookie season in progress", "")))) %>%
  mutate(grade_move = gidx(post_grade) - gidx(pre_grade), pctile_move = post_pctile - pre_pctile) %>%
  group_by(position) %>% mutate(post_rank_all = rank(-post_score, ties.method = "first"),
                                pre_rank_all = ifelse(is.na(pre_score), NA, rank(-coalesce(pre_score, -1), ties.method = "first"))) %>%
  group_by(position, class) %>% mutate(post_rank_class = rank(-post_score, ties.method = "first"),
                                       pre_rank_class = ifelse(is.na(pre_score), NA, rank(-coalesce(pre_score, -1), ties.method = "first"))) %>%
  ungroup() %>% arrange(position, post_rank_all)

final <- J %>% transmute(position, post_rank_all, class, post_rank_class, pre_rank_class, name, college, round, pick,
                         post_grade, post_score = round(post_score, 3), post_pctile = round(post_pctile, 3),
                         pre_grade, pre_score = round(pre_score, 3), pre_pctile = round(pre_pctile, 3),
                         grade_move, p_top = round(q1, 3), p_top2 = round(q2, 3), p_any = round(q3, 3),
                         nfl_outcome, nfl_best_finish, nfl_tier, nfl_ppr_pts, outcome_complete = class <= 2023, score_source, data_flag)
write.csv(final, "pd_post_player_grades.csv", row.names = FALSE, na = "")

# --- validation: hit rate by post-draft grade, and pre vs post vs pick (2010-2023) ------
H <- J %>% filter(class <= 2023, !is.na(nfl_tier)) %>% mutate(y1 = as.integer(nfl_tier == 1), y2 = as.integer(nfl_tier <= 2), y3 = as.integer(nfl_tier <= 3))
bootp <- function(y, B = 2000) { set.seed(2026); if (length(y) < 2) return(c(NA, NA)); unname(quantile(replicate(B, mean(sample(y, replace = TRUE))), c(.025, .975))) }
val <- H %>% group_by(position, grade = post_grade) %>% summarize(n = n(), mean_pick = round(mean(pick)), top_rate = mean(y1), top2_rate = mean(y2),
  any_rate = mean(y3), any_lo = bootp(y3)[1], any_hi = bootp(y3)[2], exp_any = mean(q3), mean_ppr_3yr = mean(nfl_ppr_pts, na.rm = TRUE), .groups = "drop") %>%
  mutate(across(where(is.double), ~ round(.x, 3)))
write.csv(val, "pd_post_grade_validation.csv", row.names = FALSE)
cat("\n===== Hit rates by post-draft grade, 2010-2023 =====\n"); print(as.data.frame(val), row.names = FALSE)

both <- H %>% filter(!is.na(pre_score))
vm <- bind_rows(lapply(POSITIONS, function(POS) { h <- both %>% filter(position == POS)
  bind_rows(lapply(1:3, function(k) { y <- h[[paste0("y", k)]]
    data.frame(position = POS, target = tier_labels(POS)[k], n = nrow(h), hits = sum(y),
               AUC_pre = aucf(y, h$pre_score), AUC_pick = aucf(y, -h$pick), AUC_post = aucf(y, h$post_score),
               spearman_pts_pre = cor(h$pre_score, h$nfl_ppr_pts, method = "spearman", use = "complete.obs"),
               spearman_pts_post = cor(h$post_score, h$nfl_ppr_pts, method = "spearman", use = "complete.obs"),
               spearman_pre_post = cor(h$pre_score, h$post_score, method = "spearman")) })) })) %>%
  mutate(across(where(is.double), ~ round(.x, 3)))
write.csv(vm, "pd_post_vs_pre_metrics.csv", row.names = FALSE)
cat("\n===== Pre-draft vs post-draft vs pick only (players with both grades, 2010-2023) =====\n"); print(as.data.frame(vm), row.names = FALSE)

band <- function(g) ifelse(substr(g, 1, 1) %in% c("A", "B", "C"), substr(g, 1, 1), "DF")
cat("\n===== Any-tier hit rate by grade band, pre vs post =====\n")
print(as.data.frame(both %>% mutate(pre_b = band(pre_grade), post_b = band(post_grade)) %>%
  { bind_rows(group_by(., position, band = pre_b) %>% summarize(n = n(), any = round(mean(y3), 3), .groups = "drop") %>% mutate(version = "pre"),
              group_by(., position, band = post_b) %>% summarize(n = n(), any = round(mean(y3), 3), .groups = "drop") %>% mutate(version = "post")) } %>%
  tidyr::pivot_wider(names_from = c(version, band), values_from = c(n, any))), row.names = FALSE)

# --- class level: how draft capital moved each class, and which version ranked it better --
cs <- J %>% filter(!is.na(pre_score)) %>% group_by(position, class) %>%
  summarize(n = n(), mean_pre_pctile = mean(pre_pctile), mean_post_pctile = mean(post_pctile),
            mean_grade_move = mean(grade_move), up = sum(grade_move >= 2), down = sum(grade_move <= -2),
            exp_pre = sum(pre_score), exp_post = sum(post_score),
            actual_pts = ifelse(all(class <= 2023), sum(4 - pmin(nfl_tier, 4)), NA),   # tier points: top 3, middle 2, bottom 1
            rho_pre = ifelse(all(class <= 2023) & n() > 3, cor(pre_score, 4 - pmin(nfl_tier, 4), method = "spearman"), NA),
            rho_post = ifelse(all(class <= 2023) & n() > 3, cor(post_score, 4 - pmin(nfl_tier, 4), method = "spearman"), NA),
            biggest_riser = name[which.max(grade_move)], biggest_faller = name[which.min(grade_move)], .groups = "drop") %>%
  mutate(across(where(is.double), ~ round(.x, 3)))
write.csv(cs, "pd_post_class_summary.csv", row.names = FALSE)
cat("\n===== Class summary (players with both grades) =====\n"); print(as.data.frame(cs %>% select(-biggest_riser, -biggest_faller)), row.names = FALSE)
cat("\nclass-level correlation of expected vs actual tier points, 2010-2023:\n")
print(as.data.frame(cs %>% filter(class <= 2023) %>% group_by(position) %>%
  summarize(corr_pre = round(cor(exp_pre, actual_pts), 3), corr_post = round(cor(exp_post, actual_pts), 3),
            mean_rho_pre = round(mean(rho_pre, na.rm = TRUE), 3), mean_rho_post = round(mean(rho_post, na.rm = TRUE), 3), .groups = "drop")), row.names = FALSE)

cat("\n===== Biggest movers, 2010-2023 (grade steps, + = draft capital raised him) =====\n")
for (POS in POSITIONS) {
  cat("--", POS, "risers --\n"); print(as.data.frame(final %>% filter(position == POS, class <= 2023, !is.na(grade_move)) %>% arrange(desc(grade_move), desc(post_score)) %>%
    head(8) %>% select(class, name, pick, pre_grade, post_grade, nfl_outcome)), row.names = FALSE)
  cat("--", POS, "fallers --\n"); print(as.data.frame(final %>% filter(position == POS, class <= 2023, !is.na(grade_move)) %>% arrange(grade_move, pre_score * -1) %>%
    head(8) %>% select(class, name, pick, pre_grade, post_grade, nfl_outcome)), row.names = FALSE)
}
cat("\n===== Top 12 all-time post-draft by position =====\n")
for (POS in POSITIONS) { cat("--", POS, "--\n"); print(as.data.frame(final %>% filter(position == POS) %>% head(12) %>%
  select(post_rank_all, class, name, pick, post_grade, pre_grade, nfl_outcome)), row.names = FALSE) }

g <- ggplot(final %>% filter(!is.na(pre_pctile)), aes(pre_pctile, post_pctile, colour = factor(pmin(coalesce(nfl_tier, 5), 5)))) +
  geom_abline(linetype = 2, colour = "grey60") + geom_point(alpha = .6, size = 1.4) + facet_wrap(~position, nrow = 1) +
  scale_colour_manual(values = c("1" = mycols[3], "2" = mycols[5], "3" = mycols[2], "4" = "grey70", "5" = mycols[1]),
                      labels = c("top tier", "middle tier", "bottom tier", "no tier season", "outcome pending"), name = NULL) +
  labs(x = "pre-draft percentile (college only)", y = "post-draft percentile (with draft slot + landing spot)",
       title = "How draft capital moved each drafted player, 2010-2026") + theme_minimal(base_size = 11) + theme(legend.position = "bottom")
ggsave("plot_post_vs_pre.png", g, width = 13, height = 4.8, dpi = 120)
cat("\ndone\n")
