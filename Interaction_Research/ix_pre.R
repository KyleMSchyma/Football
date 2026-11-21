# Pre-draft models: live chosen model family per position (QB/RB enet, TE enet part of ens, WR glm on 5 inputs) vs + squared / interactions
REPO <- if (dir.exists("../PreDraft_Model")) normalizePath("..") else stop("run from Interaction_Research/ inside the Football repo"); HERE <- getwd()
source(file.path(HERE, "ix_engine.R"))
old <- setwd(file.path(REPO, "PreDraft_Model")); suppressMessages(source("pd_common.R")); setwd(old)
pool <- readRDS(file.path(REPO, "PreDraft_Model/pd_pool.rds"))
args <- commandArgs(trailingOnly = TRUE); POSS <- if (length(args)) args else c("QB", "RB", "WR", "TE")
KEYPROD <- c(QB = "p_aya", RB = "p_scrim_share", WR = "p_dominator", TE = "p_dominator")
SIMPLE <- list(QB = c("p_aya", "p_att", "yrs_since_hs", "recruit_rating", "power5"), RB = c("p_scrim_share", "p_rush_yds", "yrs_since_hs", "recruit_rating", "power5"),
               WR = c("p_dominator", "p_rec_yds", "yrs_since_hs", "recruit_rating", "power5"), TE = c("p_dominator", "p_rec_yds", "yrs_since_hs", "recruit_rating", "power5"))
for (POS in POSS) {
  D <- pool %>% filter(position == POS, outcome_known, class %in% TRAIN_CLASSES) %>%
    mutate(y1 = as.integer(tier == 1), y2 = as.integer(tier <= 2), y3 = as.integer(tier <= 3), pts = total_pts_3yr)
  vars <- feats_for(POS); prep <- function(tr, te) { p <- fit_prep(tr, vars); list(Xtr = apply_prep(p, tr), Xte = apply_prep(p, te)) }
  X0 <- prep(D, D)$Xtr; bin <- colnames(X0)[apply(X0, 2, function(x) all(x %in% c(0, 1)))]; cont <- setdiff(colnames(X0), bin)
  key <- c("yrs_since_hs", KEYPROD[[POS]])
  cat(POS, "rows", nrow(D), "continuous", length(cont), "\n")
  saveRDS(list(D = D, X = X0, cont = cont), sprintf("pre_%s_design.rds", POS))
  R <- list(run_design(paste0("pre_", POS), D, prep, cont, key, character(0), ROLL_TESTS, "Rolling", has_pts = TRUE),
            run_design(paste0("pre_", POS), D, prep, cont, key, character(0), TRAIN_CLASSES, "LOCO", has_pts = TRUE))
  # the 5-input glm benchmark (live for WR): unpenalized glm, + squares, + all pairwise among its 4 continuous inputs
  sv <- SIMPLE[[POS]]; sc <- setdiff(sv, "power5")
  gl <- list()
  for (sch in c("Rolling", "LOCO")) for (Y in if (sch == "LOCO") TRAIN_CLASSES else ROLL_TESTS) {
    tr <- if (sch == "LOCO") D[D$class != Y, ] else D[D$class <= Y - 3, ]; te <- D[D$class == Y, ]
    P <- prep(tr, te); Xtr <- P$Xtr[, sv]; Xte <- P$Xte[, sv]
    for (v in c("base", "sq_all", "int_all", "full")) { E <- expand(Xtr, Xte, sc, sc, v)
      o <- data.frame(model = paste0("pre_", POS, "_glm5"), scheme = sch, variant = v, class = Y, row = seq_len(nrow(te)), y1 = te$y1, y2 = te$y2, y3 = te$y3, pts = te$pts)
      for (k in 1:3) { f <- suppressWarnings(glm(y ~ ., family = binomial, data = data.frame(E$Xtr, y = tr[[paste0("y", k)]], check.names = TRUE)))
        o[[paste0("p", k)]] <- as.numeric(predict(f, data.frame(E$Xte, check.names = TRUE), type = "response")) }
      o$p2 <- pmax(o$p2, o$p1); o$p3 <- pmax(o$p3, o$p2)
      o$ptsh <- as.numeric(predict(lm(y ~ ., data = data.frame(E$Xtr, y = tr$pts, check.names = TRUE)), data.frame(E$Xte, check.names = TRUE)))
      gl[[length(gl) + 1]] <- o } }
  pred <- bind_rows(R[[1]]$pred, R[[2]]$pred, bind_rows(gl))
  saveRDS(list(pred = pred, sel = bind_rows(R[[1]]$sel, R[[2]]$sel)), sprintf("pre_%s_results.rds", POS))
  S <- summarise_pred(pred); write.csv(S, sprintf("pre_%s_summary.csv", POS), row.names = FALSE)
  print(S %>% select(model, scheme, variant, AUC_mean, LL_mean, dLL_pct, dLL_lo, dLL_hi, classes_better, classes, RMSE_pts) %>% mutate(across(where(is.double), ~ round(.x, 4))), row.names = FALSE)
}
