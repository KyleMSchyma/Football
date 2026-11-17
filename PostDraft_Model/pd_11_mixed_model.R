# =============================================================================
# Mixed draft model (Kyle, 2026-11-17)
#
# The post-draft grade leans on draft slot. Backtest (2010-2023, leave-one-class-out):
# players with a pre-draft A-range grade (A+, A, A-) whose post-draft grade fell below A-
# hit a tier 40% of the time, but the post-draft model gave them about 25%. The mixed
# draft model keeps the post-draft model and gives exactly those players ("fallers") a
# bump on the odds of each tier ladder step. The bump is fit here, on 2010-2023 outcomes,
# as the coefficient of a faller flag in a logistic model with the post-draft model's own
# probability as an offset:  logit P(hit_k) = a_k + qlogis(p_k) + b_k * faller.
# Fallers get odds x exp(b_k); everyone else is unchanged.
#
# Research + backtest: /research/grade_fallers in the project files (fit LOCO:
# fallers' predicted any-tier 25% -> 41% vs 40% actual; log loss better in 10 of 14 classes).
#
# Run AFTER pd_07_postdraft_grades.R and pd_09_mock_2027.R, from this folder:
#   ./run.sh pd_11_mixed_model.R phase11_mixed_log.txt
# It rewrites, in place:
#   pd_post_player_grades.csv     p_top/p_top2/p_any, post_score/pctile/grade, ranks,
#                                 grade_move are the MIXED values; the draft-only values are
#                                 kept in *_draft columns, plus mixed_faller (0/1).
#   pd_post_2027_mock_grades.csv  same treatment for the mocked 2027 picks
#   pd_post_grade_validation.csv, pd_post_grade_by_round.csv, pd_post_grade_vs_pick.csv,
#   pd_post_grade_scale.csv       recomputed on the mixed grade
#   pd_mixed_model_fit.csv        the fitted bumps (odds multipliers) per tier step
# Safe to rerun: if the *_draft columns exist it starts again from them.
# =============================================================================
PRE_DIR <- if (dir.exists("../PreDraft_Model")) "../PreDraft_Model" else "../Football2_PreDraft"
source(file.path(PRE_DIR, "pd_common.R"))
GRADE_CUTS <- c(0, .10, .25, .35, .45, .55, .65, .75, .85, .90, .95, 1.0001)
GRADES     <- c("F", "D", "C-", "C", "C+", "B-", "B", "B+", "A-", "A", "A+")
A_RANGE    <- c("A+", "A", "A-")
grade_from_pct <- function(p) as.character(cut(p, GRADE_CUTS, labels = GRADES, right = FALSE))
gidx <- function(g) match(g, GRADES)
clip <- function(p) pmin(pmax(p, 1e-4), 1 - 1e-4)

f <- read.csv("pd_post_player_grades.csv", stringsAsFactors = FALSE, na.strings = "")
mk_file <- "pd_post_2027_mock_grades.csv"
mk <- if (file.exists(mk_file)) read.csv(mk_file, stringsAsFactors = FALSE, na.strings = "") else NULL

# --- start from the draft-only values (makes the script safe to rerun) ---------------------
DRAFT_COLS <- c("p_top", "p_top2", "p_any", "post_score", "post_pctile", "post_grade", "grade_move")
to_draft <- function(d) {
  if (is.null(d)) return(d)
  if ("post_grade_draft" %in% names(d)) {
    for (cc in DRAFT_COLS) d[[cc]] <- d[[paste0(cc, "_draft")]]
    d <- d[, setdiff(names(d), c(paste0(DRAFT_COLS, "_draft"), "mixed_faller"))]
  }
  for (cc in DRAFT_COLS) d[[paste0(cc, "_draft")]] <- d[[cc]]
  d$mixed_faller <- as.integer(!is.na(d$pre_grade) & d$pre_grade %in% A_RANGE & !is.na(d$post_grade) & !(d$post_grade %in% A_RANGE))
  d
}
f <- to_draft(f); mk <- to_draft(mk)

# --- fit the faller bump on 2010-2023 outcomes ---------------------------------------------
H <- f %>% filter(class <= 2023, !is.na(nfl_tier), !is.na(p_any)) %>%
  mutate(y1 = as.integer(nfl_tier == 1), y2 = as.integer(nfl_tier <= 2), y3 = as.integer(nfl_tier <= 3))
PC <- c("p_top", "p_top2", "p_any")
fit <- bind_rows(lapply(1:3, function(k) {
  h <- H %>% mutate(y = .data[[paste0("y", k)]], off = qlogis(clip(.data[[PC[k]]])))
  m <- glm(y ~ mixed_faller + offset(off), family = binomial, data = h)
  b <- unname(coef(m)["mixed_faller"]); se <- sqrt(diag(vcov(m)))[["mixed_faller"]]
  data.frame(step = c("top tier", "top two tiers", "any tier")[k], prob_col = PC[k], n = nrow(h), fallers = sum(h$mixed_faller),
             faller_actual = mean(h$y[h$mixed_faller == 1]), faller_model = mean(h[[PC[k]]][h$mixed_faller == 1]),
             coef = b, odds_mult = exp(b), odds_lo = exp(b - 1.96 * se), odds_hi = exp(b + 1.96 * se))
}))
write.csv(fit %>% mutate(across(where(is.double), ~ round(.x, 4))), "pd_mixed_model_fit.csv", row.names = FALSE)
cat("===== Mixed draft model: faller bump (odds multiplier) =====\n"); print(fit, row.names = FALSE)

# --- apply ----------------------------------------------------------------------------------
apply_mix <- function(d) {
  if (is.null(d)) return(d)
  for (k in 1:3) {
    p <- d[[PC[k]]]; z <- qlogis(clip(p)) + fit$coef[k] * d$mixed_faller
    d[[PC[k]]] <- ifelse(is.na(p), NA, ifelse(d$mixed_faller == 1, plogis(z), p))
  }
  d$p_top2 <- pmax(d$p_top2, d$p_top); d$p_any <- pmax(d$p_any, d$p_top2)
  # post_score moves by the change in expected tier points (the mock's score is calibrated,
  # so add the change rather than re-summing)
  delta <- (d$p_top + d$p_top2 + d$p_any) - (d$p_top_draft + d$p_top2_draft + d$p_any_draft)
  d$post_score <- d$post_score_draft + ifelse(is.na(delta), 0, delta)
  d
}
f <- apply_mix(f); mk <- apply_mix(mk)

# grades: percentile against the 2010-2023 MIXED score distribution at the position
REF <- lapply(setNames(POSITIONS, POSITIONS), function(POS) f %>% filter(position == POS, class <= 2023) %>% pull(post_score))
pctf <- function(pos, v) mapply(function(P, x) if (is.na(x)) NA else mean(REF[[P]] < x) + 0.5 * mean(REF[[P]] == x), pos, v)
regrade <- function(d) {
  if (is.null(d)) return(d)
  d$post_pctile <- round(pctf(d$position, d$post_score), 3)
  d$post_grade <- grade_from_pct(d$post_pctile)
  d$grade_move <- gidx(d$post_grade) - gidx(d$pre_grade)
  d$post_score <- round(d$post_score, 3)
  for (cc in PC) d[[cc]] <- round(d[[cc]], 3)
  d
}
f <- regrade(f) %>% group_by(position) %>% mutate(post_rank_all = rank(-post_score, ties.method = "first")) %>%
  group_by(position, class) %>% mutate(post_rank_class = rank(-post_score, ties.method = "first")) %>% ungroup() %>%
  arrange(position, post_rank_all) %>% as.data.frame()
write.csv(f, "pd_post_player_grades.csv", row.names = FALSE, na = "")
if (!is.null(mk)) {
  mk <- regrade(mk) %>% group_by(position) %>% mutate(post_rank_class = rank(-post_score, ties.method = "first")) %>% ungroup() %>% as.data.frame()
  write.csv(mk, mk_file, row.names = FALSE, na = "")
}

cat("\n===== Players whose grade changed =====\n")
ch <- f %>% filter(post_grade != post_grade_draft) %>% arrange(position, class)
cat(nrow(ch), "of", nrow(f), "drafted players changed grade (all are pre-draft A-range fallers)\n")
print(ch %>% filter(class >= 2024) %>% select(position, class, name, pick, pre_grade, post_grade_draft, post_grade), row.names = FALSE)
if (!is.null(mk)) { cat("-- 2027 mock --\n"); print(mk %>% filter(post_grade != post_grade_draft) %>% select(position, pick, name, pre_grade, post_grade_draft, post_grade), row.names = FALSE) }
cat("\nnon-fallers whose grade moved (percentile reference shift only):", sum(f$post_grade != f$post_grade_draft & f$mixed_faller == 0), "\n")

# --- validation tables, now on the mixed grade (same definitions as pd_07) ------------------
H <- f %>% filter(class <= 2023, !is.na(nfl_tier)) %>%
  mutate(y1 = as.integer(nfl_tier == 1), y2 = as.integer(nfl_tier <= 2), y3 = as.integer(nfl_tier <= 3))
bootp <- function(y, B = 2000) { set.seed(2026); if (length(y) < 2) return(c(NA, NA)); unname(quantile(replicate(B, mean(sample(y, replace = TRUE))), c(.025, .975))) }
val <- H %>% group_by(position, grade = post_grade) %>% summarize(n = n(), mean_pick = round(mean(pick)), top_rate = mean(y1), top2_rate = mean(y2),
  any_rate = mean(y3), any_lo = bootp(y3)[1], any_hi = bootp(y3)[2], exp_any = mean(p_any), mean_ppr_3yr = mean(nfl_ppr_pts, na.rm = TRUE), .groups = "drop") %>%
  mutate(across(where(is.double), ~ round(.x, 3)))
write.csv(val, "pd_post_grade_validation.csv", row.names = FALSE)
cat("\n===== Hit rates by mixed grade, 2010-2023 =====\n"); print(as.data.frame(val), row.names = FALSE)

vp2 <- bind_rows(lapply(POSITIONS, function(POS) {
  h <- H %>% filter(position == POS, !is.na(pick)) %>% mutate(lpick = log(pick), lsc = qlogis(clip(p_any)))
  bind_rows(lapply(1:3, function(k) { y <- h[[paste0("y", k)]]
    m0 <- glm(y ~ lpick, family = binomial, data = h); m1 <- glm(y ~ lpick + lsc, family = binomial, data = h)
    data.frame(position = POS, target = tier_labels(POS)[k], n = nrow(h), hits = sum(y),
      AUC_grade = aucf(y, h$post_score), AUC_pick = aucf(y, -h$pick), AUC_pick_plus_grade = aucf(y, fitted(m1)),
      spearman_pts = if (k == 1) cor(h$post_score, h$nfl_ppr_pts, method = "spearman", use = "complete.obs") else NA,
      spearman_pts_pick = if (k == 1) cor(-h$pick, h$nfl_ppr_pts, method = "spearman", use = "complete.obs") else NA,
      LRT_p = anova(m0, m1, test = "LRT")$`Pr(>Chi)`[2], AIC_pick = AIC(m0), AIC_pick_plus_grade = AIC(m1)) })) })) %>%
  mutate(across(where(is.double), ~ signif(.x, 3)))
write.csv(vp2, "pd_post_grade_vs_pick.csv", row.names = FALSE)
cat("\n===== Mixed grade vs draft slot =====\n"); print(as.data.frame(vp2), row.names = FALSE)

gband <- function(g) case_when(g %in% c("A+", "A", "A-") ~ "A range", g %in% c("B+", "B", "B-") ~ "B range", g %in% c("C+", "C", "C-") ~ "C range", TRUE ~ "D/F")
byr2 <- H %>% mutate(round_band = case_when(round == 1 ~ "Round 1", round <= 3 ~ "Rounds 2-3", TRUE ~ "Rounds 4-7"), band = gband(post_grade)) %>%
  group_by(position, round_band, band) %>% summarize(n = n(), any_rate = round(mean(y3), 3), top2_rate = round(mean(y2), 3), .groups = "drop")
write.csv(byr2, "pd_post_grade_by_round.csv", row.names = FALSE)
sc2 <- bind_rows(lapply(POSITIONS, function(POS) { ref <- REF[[POS]]
  data.frame(position = POS, grade = rev(GRADES), pct_from = rev(head(GRADE_CUTS, -1)),
             min_score = round(sapply(rev(head(GRADE_CUTS, -1)), function(q) unname(quantile(ref, q, type = 1))), 3)) }))
write.csv(sc2, "pd_post_grade_scale.csv", row.names = FALSE)
cat("\ndone\n")
