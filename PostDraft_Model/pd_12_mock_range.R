# =============================================================================
# 2027 mock pick range (Kyle, 2026-11-18)
#
# Kyle's saved mocks (Football repo Mock_Drafts/, his own mocks only) are combined by
# Mock_Drafts/combine_mocks.py into one row per QB/RB/WR/TE prospect. Rules:
#   * the live grade uses his AVERAGE pick over the mocks that draft him, rounded to a whole pick
#   * BEST case  = his earliest pick;  WORST case = his latest pick, or UNDRAFTED if a mock leaves him out
#   * VALUE = share of mocks that draft him x value at the average pick
#           + share that leave him undrafted x undrafted value
#     Value is linear in the tier probabilities, so this is done on the probabilities:
#     p_*_value = share x p_* (average pick) + (1 - share) x p_* (undrafted base rate).
#   * undrafted base rate: undrafted free agents of the 2010-2023 classes who recorded NFL stats
#     (pd_pool.rds), share with a top-tier / top-two / any-tier finish in years 1-3, by position.
#
# Pipeline (from this folder; MOCK files from Mock_Drafts/range/):
#   MOCK_FILE=<range>/mock_2027_avg.csv                ./run.sh pd_09_mock_2027.R phase9_log.txt
#   MOCK_FILE=<range>/mock_2027_best.csv  OUT_TAG=_best  ./run.sh pd_09_mock_2027.R phase9_best_log.txt
#   MOCK_FILE=<range>/mock_2027_worst.csv OUT_TAG=_worst ./run.sh pd_09_mock_2027.R phase9_worst_log.txt
#   ./run.sh pd_11_mixed_model.R phase11_mixed_log.txt      (mixed model on all three files)
#   RANGE_FILE=<range>/mock_2027_range_players.csv ./run.sh pd_12_mock_range.R phase12_range_log.txt
#   then dv_13 (values) and pd_10 (site page) as usual.
# Adds to pd_post_2027_mock_grades.csv (in place; p_top / p_top2 / p_any stay the average-pick odds):
#   n_mocks, n_drafted, share_drafted, avg_pick_exact, picks_in_mocks
#   p_top_value, p_top2_value, p_any_value   probabilities that price the player (dv_13 uses these)
#   best_pick, best_team_abbr, best_grade, best_p_top, best_p_top2, best_p_any
#   worst_case ("pick" / "undrafted"), worst_pick, worst_team_abbr, worst_grade ("UDFA" when undrafted),
#   worst_p_top, worst_p_top2, worst_p_any   (undrafted base rates when undrafted)
# Plain post-draft model (Kyle 2026-11-18: whatever feeds the mixed model also feeds the post model):
#   p_*_value_draft, best_grade_draft, best_p_*_draft, worst_grade_draft, worst_p_*_draft from the *_draft columns
#   pd_11 keeps (the site's Post-draft view). The pre-draft model never sees draft slot, so the range does not apply to it.
# Also writes pd_mock_range_udfa_rates.csv. Safe to rerun (drops its own columns first).
# =============================================================================
suppressMessages({ library(dplyr) })
PRE_DIR <- if (dir.exists("../PreDraft_Model")) "../PreDraft_Model" else "../Football2_PreDraft"
RANGE_FILE <- Sys.getenv("RANGE_FILE", if (file.exists("../Mock_Drafts/range/mock_2027_range_players.csv"))
  "../Mock_Drafts/range/mock_2027_range_players.csv" else "mock_2027/range/mock_2027_range_players.csv")
TIERS <- list(QB = c(8, 16, 24), RB = c(8, 16, 24), WR = c(12, 24, 36), TE = c(6, 12, 18))
nkey <- function(x) gsub("[^a-z]", "", tolower(gsub("\\b(jr|sr|ii|iii|iv)\\.?$", "", tolower(x))))
check <- function(label, ok, detail = "") { cat(sprintf("[%s] %s %s\n", ifelse(ok, "PASS", "FAIL"), label, detail)); invisible(ok) }
MY_COLS <- c("n_mocks", "n_drafted", "share_drafted", "avg_pick_exact", "picks_in_mocks", "p_top_value", "p_top2_value", "p_any_value",
             "best_pick", "best_team_abbr", "best_grade", "best_p_top", "best_p_top2", "best_p_any",
             "worst_case", "worst_pick", "worst_team_abbr", "worst_grade", "worst_p_top", "worst_p_top2", "worst_p_any",
             "p_top_value_draft", "p_top2_value_draft", "p_any_value_draft", "best_grade_draft", "best_p_top_draft", "best_p_top2_draft",
             "best_p_any_draft", "worst_grade_draft", "worst_p_top_draft", "worst_p_top2_draft", "worst_p_any_draft")

# --- undrafted base rates -------------------------------------------------------------------
pool <- readRDS(file.path(PRE_DIR, "pd_pool.rds"))
ud <- pool %>% filter(class >= 2010, class <= 2023, drafted == 0, !is.na(gsis_id), !is.na(best_finish_3yr))
U <- bind_rows(lapply(names(TIERS), function(P) { x <- ud %>% filter(position == P); t <- TIERS[[P]]
  data.frame(position = P, n_udfa_with_nfl_stats = nrow(x), udfa_top = mean(x$best_finish_3yr <= t[1]),
             udfa_top2 = mean(x$best_finish_3yr <= t[2]), udfa_any = mean(x$best_finish_3yr <= t[3])) }))
write.csv(U %>% mutate(across(where(is.double), ~ round(.x, 4))), "pd_mock_range_udfa_rates.csv", row.names = FALSE)
cat("undrafted base rates (2010-2023 UDFAs with NFL stats, tier finish in years 1-3):\n"); print(U, row.names = FALSE)

# --- the range ------------------------------------------------------------------------------
R <- read.csv(RANGE_FILE, stringsAsFactors = FALSE, na.strings = "") %>% mutate(k = paste(nkey(player), pos))
pk_cols <- grep("^pick_", names(R), value = TRUE)
R$picks_in_mocks <- apply(R[, pk_cols, drop = FALSE], 1, function(v) paste(ifelse(is.na(v), "UD", trimws(v)), collapse = "/"))
rd <- function(f) { d <- read.csv(f, stringsAsFactors = FALSE, na.strings = ""); d$k <- paste(nkey(d$name), d$position); d }
mk <- rd("pd_post_2027_mock_grades.csv"); mk <- mk[, setdiff(names(mk), MY_COLS)]
# files not yet through pd_11 have no *_draft columns: the plain post-draft values are then the values themselves
add_draft <- function(d) { for (cc in c("p_top", "p_top2", "p_any", "post_grade")) if (!paste0(cc, "_draft") %in% names(d)) d[[paste0(cc, "_draft")]] <- d[[cc]]; d }
best <- add_draft(rd("pd_post_2027_mock_grades_best.csv")); mk <- add_draft(mk)
worst <- add_draft(if (file.exists("pd_post_2027_mock_grades_worst.csv")) rd("pd_post_2027_mock_grades_worst.csv") else best[0, ])

mk <- mk %>%
  left_join(R %>% select(k, n_mocks, n_drafted, share_drafted, avg_pick_exact, picks_in_mocks, worst_case), by = "k") %>%
  left_join(U %>% select(position, udfa_top, udfa_top2, udfa_any), by = "position") %>%
  left_join(best %>% select(k, best_pick = pick, best_team_abbr = team_abbr, best_grade = post_grade,
                            best_p_top = p_top, best_p_top2 = p_top2, best_p_any = p_any, best_grade_draft = post_grade_draft,
                            best_p_top_draft = p_top_draft, best_p_top2_draft = p_top2_draft, best_p_any_draft = p_any_draft), by = "k") %>%
  left_join(worst %>% select(k, w_pick = pick, w_team = team_abbr, w_grade = post_grade, w1 = p_top, w2 = p_top2, w3 = p_any,
                             w_grade_d = post_grade_draft, w1d = p_top_draft, w2d = p_top2_draft, w3d = p_any_draft), by = "k") %>%
  mutate(share_drafted = coalesce(share_drafted, 1),
         p_top_value = round(share_drafted * p_top + (1 - share_drafted) * udfa_top, 4),
         p_top2_value = round(share_drafted * p_top2 + (1 - share_drafted) * udfa_top2, 4),
         p_any_value = round(share_drafted * p_any + (1 - share_drafted) * udfa_any, 4),
         p_top_value_draft = round(share_drafted * p_top_draft + (1 - share_drafted) * udfa_top, 4),
         p_top2_value_draft = round(share_drafted * p_top2_draft + (1 - share_drafted) * udfa_top2, 4),
         p_any_value_draft = round(share_drafted * p_any_draft + (1 - share_drafted) * udfa_any, 4),
         und = coalesce(worst_case, "pick") == "undrafted",
         worst_pick = ifelse(und, NA, w_pick), worst_team_abbr = ifelse(und, NA, w_team), worst_grade = ifelse(und, "UDFA", w_grade),
         worst_p_top = ifelse(und, round(udfa_top, 4), w1), worst_p_top2 = ifelse(und, round(udfa_top2, 4), w2),
         worst_p_any = ifelse(und, round(udfa_any, 4), w3),
         worst_grade_draft = ifelse(und, "UDFA", w_grade_d), worst_p_top_draft = ifelse(und, round(udfa_top, 4), w1d),
         worst_p_top2_draft = ifelse(und, round(udfa_top2, 4), w2d), worst_p_any_draft = ifelse(und, round(udfa_any, 4), w3d)) %>%
  select(-k, -udfa_top, -udfa_top2, -udfa_any, -w_pick, -w_team, -w_grade, -w1, -w2, -w3, -w_grade_d, -w1d, -w2d, -w3d, -und)
# Kyle 2026-11-23: a best / worst case keeps any mixed faller boost, but a worst case is capped at the median-pick odds
# and grade, and a best case is floored at them, so every range reads best >= median >= worst (tier by tier on the
# odds; value is increasing in each tier's odds, so the value range is in order too). Same for the plain post-draft range.
GR <- c("A+", "A", "A-", "B+", "B", "B-", "C+", "C", "C-", "D+", "D", "D-", "F", "UDFA")
gr_cap <- function(case, med, worst) { rc <- match(case, GR); rm <- match(med, GR)
  ifelse(is.na(rc) | is.na(rm), case, if (worst) ifelse(rc < rm, med, case) else ifelse(rc > rm, med, case)) }
for (sfx in c("", "_draft")) {
  for (t in c("p_top", "p_top2", "p_any")) {
    med <- mk[[paste0(t, sfx)]]
    mk[[paste0("worst_", t, sfx)]] <- ifelse(is.na(med), mk[[paste0("worst_", t, sfx)]], pmin(mk[[paste0("worst_", t, sfx)]], med))
    mk[[paste0("best_", t, sfx)]] <- ifelse(is.na(med), mk[[paste0("best_", t, sfx)]], pmax(mk[[paste0("best_", t, sfx)]], med))
  }
  g <- mk[[if (sfx == "") "post_grade" else "post_grade_draft"]]
  mk[[paste0("worst_grade", sfx)]] <- gr_cap(mk[[paste0("worst_grade", sfx)]], g, TRUE)
  mk[[paste0("best_grade", sfx)]] <- gr_cap(mk[[paste0("best_grade", sfx)]], g, FALSE)
}
write.csv(mk, "pd_post_2027_mock_grades.csv", row.names = FALSE, na = "")

cat("\n===== 2027 mock range =====\n")
print(as.data.frame(mk %>% arrange(pick) %>% transmute(position, name, picks = picks_in_mocks, avg = pick, grade = post_grade,
  best = paste(best_pick, best_grade), worst = ifelse(worst_case == "undrafted", "UDFA", paste(worst_pick, worst_grade)),
  post_only = paste(best_grade_draft, post_grade_draft, worst_grade_draft, sep = "/"),
  share = share_drafted, p_any, p_any_value, p_any_value_draft)), row.names = FALSE)
check("plain post-draft range present", all(!is.na(mk$best_grade_draft) & !is.na(mk$p_any_value_draft)))
check("non-fallers: post-draft range equals mixed range", with(mk, all(mixed_faller == 1 | is.na(mixed_faller) | abs(p_any_value - p_any_value_draft) < 1e-3)))
check("every mocked player has a range row", all(!is.na(mk$n_drafted)), sprintf("(%d missing)", sum(is.na(mk$n_drafted))))
check("every mocked player has a best case", all(!is.na(mk$best_grade)))
check("worst case for every player drafted in all mocks", all(!is.na(mk$worst_grade)))
check("best >= average >= worst on any-tier odds", all(mk$best_p_any + 1e-6 >= mk$p_any & mk$p_any + 1e-6 >= mk$worst_p_any | is.na(mk$worst_p_any)),
      "(capped at the median, so this should pass)")
print(as.data.frame(mk %>% filter(!(best_p_any + 1e-6 >= p_any & p_any + 1e-6 >= worst_p_any)) %>%
  select(name, position, best_pick, best_team_abbr, best_p_any, pick, team_abbr, p_any, worst_pick, worst_team_abbr, worst_p_any)), row.names = FALSE)
cat("\ndone\n")
