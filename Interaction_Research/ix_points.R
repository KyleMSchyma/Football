# 3-year points models vs tier-hit models on the same holdout players.
# Uses the designs saved by ix_post.R / ix_pre.R (same rows, same in-fold prep), adds a log-points target.
REPO <- if (dir.exists("../PreDraft_Model")) normalizePath("..") else stop("run from Interaction_Research/ inside the Football repo"); HERE <- getwd(); source(file.path(HERE, "ix_engine.R"))
a <- commandArgs(trailingOnly = TRUE); NM <- a[1]   # e.g. post_WR, pre_RB
if (startsWith(NM, "post_")) {
  src <- readLines(file.path(REPO, "PostDraft_Model/pd_20_pick_penalty_experiment.R"))
  i <- grep("^load_pos <- function", src); j <- grep("^# ---------- elastic-net variants", src) - 1
  select <- dplyr::select; eval(parse(text = src[i:j]))
  POS_DIR <- c(QB = file.path(REPO, "QB_Model"), RB = file.path(REPO, "RB_Model"), WR = file.path(REPO, "WR_Model"), TE = file.path(REPO, "TE_Model"))
  prep <- load_pos(sub("post_", "", NM))$prep; unpen <- "log_pick"; tests_l <- NULL
} else {
  old <- setwd(file.path(REPO, "PreDraft_Model")); suppressMessages(source("pd_common.R")); setwd(old)
  vars <- feats_for(sub("pre_", "", NM)); prep <- function(tr, te) { p <- fit_prep(tr, vars); list(Xtr = apply_prep(p, tr), Xte = apply_prep(p, te)) }; unpen <- character(0)
}
L <- readRDS(sprintf("%s_design.rds", NM)); D <- L$D; cont <- L$cont
D$lpts <- log1p(pmax(D$pts, 0))
out <- list()
for (sch in c("Rolling", "LOCO")) { tests <- if (sch == "LOCO") sort(unique(D$class)) else 2016:2023
  for (Y in tests) { tr <- if (sch == "LOCO") D[D$class != Y, ] else D[D$class <= Y - 3, ]; te <- D[D$class == Y, ]; P <- prep(tr, te)
    for (v in c("base", "int_all")) { E <- expand(P$Xtr, P$Xte, cont, character(0), v)
      out[[length(out) + 1]] <- data.frame(model = NM, scheme = sch, variant = v, class = Y, row = seq_len(nrow(te)),
        lpts_hat = fit_pred(E$Xtr, tr$lpts, E$Xte, "gaussian", tr$class, unpen)$p) } } }
saveRDS(bind_rows(out), sprintf("%s_logpts.rds", NM)); cat(NM, "done\n")
