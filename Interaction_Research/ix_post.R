# Post-draft models (QB/RB/WR/TE): current post-draft elastic net (log_pick unpenalized, as live) vs + squared / interaction terms
REPO <- if (dir.exists("../PreDraft_Model")) normalizePath("..") else stop("run from Interaction_Research/ inside the Football repo"); HERE <- getwd()
source(file.path(HERE, "ix_engine.R"))
src <- readLines(file.path(REPO, "PostDraft_Model/pd_20_pick_penalty_experiment.R"))
a <- grep("^load_pos <- function", src); b <- grep("^# ---------- elastic-net variants", src) - 1
select <- dplyr::select; eval(parse(text = src[a:b]))
POS_DIR <- c(QB = file.path(REPO, "QB_Model"), RB = file.path(REPO, "RB_Model"), WR = file.path(REPO, "WR_Model"), TE = file.path(REPO, "TE_Model"))
args <- commandArgs(trailingOnly = TRUE); POSS <- if (length(args)) args else c("QB", "RB", "WR", "TE")
for (POS in POSS) {
  L <- load_pos(POS)
  D <- L$train %>% mutate(class = draft_season, y1 = as.integer(tier == 1), y2 = as.integer(tier <= 2), y3 = as.integer(tier <= 3)) %>% filter(class <= 2023)
  X0 <- L$prep(D, D)$Xtr
  bin <- colnames(X0)[apply(X0, 2, function(x) all(x %in% c(0, 1)))]
  cont <- setdiff(colnames(X0), bin)
  key <- intersect(c("log_pick", "age_at_draft"), cont)
  cat(POS, "rows", nrow(D), "continuous", length(cont), ":", paste(cont, collapse = ", "), "\n")
  saveRDS(list(D = D, X = X0, cont = cont), sprintf("post_%s_design.rds", POS))
  R1 <- run_design(paste0("post_", POS), D, L$prep, cont, key, "log_pick", 2016:2023, "Rolling")
  R2 <- run_design(paste0("post_", POS), D, L$prep, cont, key, "log_pick", sort(unique(D$class)), "LOCO")
  saveRDS(list(pred = bind_rows(R1$pred, R2$pred), sel = bind_rows(R1$sel, R2$sel)), sprintf("post_%s_results.rds", POS))
  S <- summarise_pred(bind_rows(R1$pred, R2$pred)); write.csv(S, sprintf("post_%s_summary.csv", POS), row.names = FALSE)
  print(S %>% select(scheme, variant, AUC_mean, LL_mean, dLL_pct, dLL_lo, dLL_hi, classes_better, classes, RMSE_pts) %>% mutate(across(where(is.double), ~ round(.x, 4))), row.names = FALSE)
}
