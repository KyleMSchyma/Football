# =============================================================================
# Projected 3-year PPG for the post-draft board (Kyle 2026-11-23: show "Proj. PPG" next to the grade).
# Display only: grades and the Value column do not use it (rookie values stay on the tier odds; research in
# Interaction_Research/points_projection/: PPG-model values ranked realized value .516 vs .540 for the tier method).
#
# Target: PPR points per game over NFL seasons 1-3 (total_pts_3yr / games_3yr), players with 1+ game, weighted by games.
# Model:  elastic net (alpha 0.5, folds = draft classes) on the same inputs and in-fold prep as the post-draft grade
#         (load_pos in pd_20_pick_penalty_experiment.R), log_pick unpenalized.
# Past classes (2010-2023): out-of-class (each class predicted by a model fit without it). 2024-2026 drafted and the
# 2027 mock rows (pd_post_2027_mock_inputs.csv): final model fit on 2010-2023.
# Mixed: pre-draft A-range fallers (mixed_faller, pd_11) get + b PPG, b = games-weighted mean out-of-class residual of
#        fallers minus non-fallers, per position (the PPG version of pd_11's faller bump).
# Writes pd_post_proj_ppg.csv and pd_post_2027_mock_proj_ppg.csv (read by pd_10_site_page.R). Safe to rerun; run after
# pd_11 (fallers) and pd_09 (mock inputs).
# =============================================================================
suppressMessages({ library(dplyr); library(tidyr); library(glmnet) })
REPO <- dir.exists("../WR_Model")
POS_DIR <- if (REPO) c(QB = "../QB_Model", RB = "../RB_Model", WR = "../WR_Model", TE = "../TE_Model") else
  c(QB = "../Football2_QB", RB = "../Football2_RB", WR = "../Football2", TE = "../Football2_TE")
src <- readLines("pd_20_pick_penalty_experiment.R")
i <- grep("^load_pos <- function", src); j <- grep("^# ---------- elastic-net variants", src) - 1
s <- paste(src[i:j], collapse = "\n")
s <- sub("train <- tbl %>%", "full <- tbl; train <- tbl %>%", s, fixed = TRUE)
s <- sub("train <- e$load_table() %>%", "full <- e$load_table(); train <- full %>%", s, fixed = TRUE)
s <- sub("list(train = train, prep = prep)", "list(train = train, prep = prep, full = full)", s, fixed = TRUE)
select <- dplyr::select; eval(parse(text = s))
enet <- function(X, y, w, cls, Xte) { keep <- apply(X, 2, sd) > 0; X <- X[, keep, drop = FALSE]; Xte <- Xte[, keep, drop = FALSE]
  set.seed(2026); f <- cv.glmnet(X, y, weights = w, alpha = 0.5, foldid = as.integer(factor(cls)), penalty.factor = as.numeric(colnames(X) != "log_pick"))
  as.numeric(predict(f, Xte, s = "lambda.min")) }
MI <- if (file.exists("pd_post_2027_mock_inputs.csv")) read.csv("pd_post_2027_mock_inputs.csv", stringsAsFactors = FALSE) %>%
  pivot_wider(id_cols = c(position, pick, name), names_from = input, values_from = value) else NULL
OUT <- list(); MK <- list()
for (POS in c("QB", "RB", "WR", "TE")) { L <- load_pos(POS)
  tr0 <- L$train %>% filter(draft_season <= 2023, !is.na(games_3yr), games_3yr > 0) %>% mutate(ppg = pts / games_3yr)
  full <- L$full
  oof <- bind_rows(lapply(sort(unique(tr0$draft_season)), function(Y) { tr <- tr0 %>% filter(draft_season != Y); te <- full %>% filter(draft_season == Y)
    P <- L$prep(tr, te); data.frame(draft_season = Y, pick = te$pick, proj = enet(P$Xtr, tr$ppg, pmin(tr$games_3yr, 51), tr$draft_season, P$Xte)) }))
  new <- full %>% filter(draft_season >= 2024); P <- L$prep(tr0, new)
  Xm <- NULL
  if (!is.null(MI)) { m <- MI %>% filter(position == POS); Xm <- matrix(0, nrow(m), ncol(P$Xtr), dimnames = list(NULL, colnames(P$Xtr)))
    for (cc in intersect(colnames(P$Xtr), names(m))) Xm[, cc] <- as.numeric(m[[cc]])
    miss <- setdiff(colnames(P$Xtr), names(m)); if (length(miss)) cat(POS, "mock inputs missing (set to 0):", paste(miss, collapse = ", "), "\n") }
  pr <- enet(P$Xtr, tr0$ppg, pmin(tr0$games_3yr, 51), tr0$draft_season, rbind(P$Xte, if (is.null(Xm)) P$Xte[0, , drop = FALSE] else Xm))
  OUT[[POS]] <- bind_rows(oof %>% mutate(source = "out-of-class"),
                          data.frame(draft_season = new$draft_season, pick = new$pick, proj = pr[seq_len(nrow(new))], source = "final model (2010-2023)")) %>%
    mutate(position = POS) %>% left_join(tr0 %>% select(draft_season, pick, ppg, games_3yr), by = c("draft_season", "pick"))
  if (!is.null(Xm)) MK[[POS]] <- data.frame(position = POS, pick = m$pick, board_name = m$name, proj = pr[nrow(new) + seq_len(nrow(m))])
  o <- OUT[[POS]] %>% filter(!is.na(ppg))
  cat(sprintf("%s: %d training players; out-of-class 3-yr PPG Spearman %.3f, games-weighted RMSE %.2f\n", POS, nrow(o),
              cor(o$proj, o$ppg, method = "spearman"), sqrt(weighted.mean((o$proj - o$ppg)^2, o$games_3yr))))
}
A <- bind_rows(OUT) %>% rename(class = draft_season)
g <- read.csv("pd_post_player_grades.csv", stringsAsFactors = FALSE, na.strings = "")
if (!"mixed_faller" %in% names(g)) g$mixed_faller <- 0L
A <- A %>% left_join(g %>% filter(!is.na(pick)) %>% distinct(position, class, pick, .keep_all = TRUE) %>% select(position, class, pick, name, mixed_faller),
                     by = c("position", "class", "pick")) %>% mutate(mixed_faller = coalesce(mixed_faller, 0L))
bump <- A %>% filter(source == "out-of-class", !is.na(ppg)) %>% group_by(position) %>%
  summarise(fallers = sum(mixed_faller), bump = if (sum(mixed_faller) > 0) unname(coef(lm(I(ppg - proj) ~ mixed_faller, weights = games_3yr))[2]) else 0, .groups = "drop")
cat("\nfaller bump (PPG added for pre-draft A-range fallers, mixed view):\n"); print(as.data.frame(bump), digits = 3)
A <- A %>% left_join(bump %>% select(position, bump), by = "position") %>%
  mutate(proj_ppg3_post = round(pmax(proj, 0), 1), proj_ppg3_mixed = round(pmax(proj + ifelse(mixed_faller == 1, bump, 0), 0), 1))
write.csv(A %>% select(position, class, pick, name, proj_ppg3_post, proj_ppg3_mixed, mixed_faller, source, actual_ppg3 = ppg, games_3yr) %>%
            mutate(actual_ppg3 = round(actual_ppg3, 1)) %>% arrange(position, class, pick), "pd_post_proj_ppg.csv", row.names = FALSE, na = "")
if (length(MK)) {
  mk <- read.csv("pd_post_2027_mock_grades.csv", stringsAsFactors = FALSE, na.strings = "")
  if (!"mixed_faller" %in% names(mk)) mk$mixed_faller <- 0L
  M <- bind_rows(MK) %>% left_join(mk %>% select(position, pick, board_name, name, mixed_faller), by = c("position", "pick", "board_name")) %>%
    left_join(bump %>% select(position, bump), by = "position") %>% mutate(mixed_faller = coalesce(mixed_faller, 0L),
      proj_ppg3_post = round(pmax(proj, 0), 1), proj_ppg3_mixed = round(pmax(proj + ifelse(mixed_faller == 1, bump, 0), 0), 1))
  write.csv(M %>% select(position, pick, name, board_name, proj_ppg3_post, proj_ppg3_mixed, mixed_faller) %>% arrange(pick), "pd_post_2027_mock_proj_ppg.csv", row.names = FALSE, na = "")
  cat("\n2027 mock:", nrow(M), "rows,", sum(is.na(M$name)), "not matched to the mock grades\n")
}
cat("wrote pd_post_proj_ppg.csv:", nrow(A), "rows (", sum(A$source == "out-of-class"), "out-of-class )\n")
