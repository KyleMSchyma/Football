# =============================================================================
# Projected 3-year PPG for the pre-draft board (Kyle 2026-11-23: "Proj. PPG" next to the grade; parity with the
# post-draft and mixed boards, PostDraft_Model/pd_13_proj_ppg.R). Display only: grades and Value do not use it.
#
# Target: PPR points per game over NFL seasons 1-3 for players who reached the NFL and played (1+ game), weighted by
# games. So it reads "points per game IF he plays"; the chance of making it is what the grade and its odds cover.
# Games and points come from the position model tables (games_3yr, total 3-yr PPR), joined by gsis_id.
# Model: elastic net (alpha 0.5, folds = classes) on the pre-draft grade's college inputs and in-fold prep (pd_common.R).
# Classes 2010-2023: out-of-class (each class predicted by a model fit without it); 2024-2027: final model on 2010-2023.
# Run after pd_01 (and pd_06); reads pd_pool.rds, writes pd_proj_ppg.csv (read by Weekly_Refresh/rf_02_predraft_page.R).
# =============================================================================
suppressMessages(source("pd_common.R")); suppressMessages(library(glmnet))
pool <- readRDS("pd_pool.rds")
rdt <- function(dir, f) { old <- setwd(dir); on.exit(setwd(old)); readRDS(f) }
G <- bind_rows(lapply(names(POS_DIR), function(P) { f <- c(WR = "wr_model_table.rds", QB = "qb_model_table.rds", RB = "rb_model_table.rds", TE = "te_model_table.rds")[[P]]
  t <- rdt(POS_DIR[[P]], f); pts <- if ("total_ppr_3yr" %in% names(t)) t$total_ppr_3yr else t$total_pts_3yr
  data.frame(gsis_id = t$gsis_id, g3 = t$games_3yr, p3 = pts) })) %>% filter(!is.na(gsis_id), !is.na(g3)) %>% distinct(gsis_id, .keep_all = TRUE)
enet <- function(X, y, w, cls, Xte) { keep <- apply(X, 2, sd) > 0; X <- X[, keep, drop = FALSE]; Xte <- Xte[, keep, drop = FALSE]
  set.seed(2026); f <- cv.glmnet(X, y, weights = w, alpha = 0.5, foldid = as.integer(factor(cls)))
  as.numeric(predict(f, Xte, s = "lambda.min")) }
OUT <- list()
for (POS in POSITIONS) { vars <- feats_for(POS); d <- pool %>% filter(position == POS) %>% left_join(G, by = "gsis_id")
  tr0 <- d %>% filter(class %in% TRAIN_CLASSES, !is.na(g3), g3 > 0) %>% mutate(ppg = p3 / g3)
  oof <- bind_rows(lapply(TRAIN_CLASSES, function(Y) { tr <- tr0 %>% filter(class != Y); te <- d %>% filter(class == Y); if (!nrow(te)) return(NULL)
    p <- fit_prep(tr, vars); te %>% transmute(position, class, name, college = p_team, proj = enet(apply_prep(p, tr), tr$ppg, pmin(tr$g3, 51), tr$class, apply_prep(p, te)),
      source = "out-of-class", actual_ppg3 = ifelse(!is.na(g3) & g3 > 0, p3 / g3, NA), games_3yr = g3) }))
  new <- d %>% filter(class > max(TRAIN_CLASSES)); p <- fit_prep(tr0, vars)
  fin <- new %>% transmute(position, class, name, college = p_team, proj = enet(apply_prep(p, tr0), tr0$ppg, pmin(tr0$g3, 51), tr0$class, apply_prep(p, new)),
      source = sprintf("final model (%d-%d)", min(TRAIN_CLASSES), max(TRAIN_CLASSES)), actual_ppg3 = NA_real_, games_3yr = NA_real_)
  OUT[[POS]] <- bind_rows(oof, fin)
  o <- oof %>% filter(!is.na(actual_ppg3))
  cat(sprintf("%s: %d players who played; out-of-class 3-yr PPG Spearman %.3f, games-weighted RMSE %.2f; %d rows 2024+\n", POS, nrow(o),
              cor(o$proj, o$actual_ppg3, method = "spearman"), sqrt(weighted.mean((o$proj - o$actual_ppg3)^2, o$games_3yr)), nrow(fin)))
}
A <- bind_rows(OUT) %>% mutate(proj_ppg3 = round(pmax(proj, 0), 1), actual_ppg3 = round(actual_ppg3, 1)) %>% select(-proj)
write.csv(A, "pd_proj_ppg.csv", row.names = FALSE, na = "")
cat("wrote pd_proj_ppg.csv:", nrow(A), "rows\n")
