# Rookie-year-only backtest: hit model (P(top)+P(top2)+P(any) for a year-1 tier finish) vs points models (year-1 PPR points,
# raw and log), same rows, inputs, prep and holdouts as the 3-year runs. Usage: Rscript ix_rookie.R post_WR
REPO <- if (dir.exists("../PreDraft_Model")) normalizePath("..") else stop("run from Interaction_Research/ inside the Football repo"); HERE <- getwd(); source(file.path(HERE, "ix_engine.R"))
NM <- commandArgs(trailingOnly = TRUE)[1]; POS <- sub("^(pre|post)_", "", NM)
TIERS <- list(QB = c(8, 16, 24), RB = c(8, 16, 24), WR = c(12, 24, 36), TE = c(6, 12, 18))
if (startsWith(NM, "post_")) {
  src <- readLines(file.path(REPO, "PostDraft_Model/pd_20_pick_penalty_experiment.R"))
  i <- grep("^load_pos <- function", src); j <- grep("^# ---------- elastic-net variants", src) - 1
  select <- dplyr::select; eval(parse(text = src[i:j]))
  POS_DIR <- c(QB = file.path(REPO, "QB_Model"), RB = file.path(REPO, "RB_Model"), WR = file.path(REPO, "WR_Model"), TE = file.path(REPO, "TE_Model"))
  prep <- load_pos(POS)$prep; unpen <- "log_pick"
} else {
  old <- setwd(file.path(REPO, "PreDraft_Model")); suppressMessages(source("pd_common.R")); setwd(old)
  vars <- feats_for(POS); prep <- function(tr, te) { p <- fit_prep(tr, vars); list(Xtr = apply_prep(p, tr), Xte = apply_prep(p, te)) }; unpen <- character(0)
}
L <- readRDS(sprintf("%s_design.rds", NM)); D <- L$D; cont <- L$cont
S <- readRDS("season_finish.rds") %>% filter(pos == POS) %>% select(gsis_id = player_id, class = season, r_pts = pts, r_fin = finish)
D <- D %>% select(-any_of(c("r_pts", "r_fin"))) %>% left_join(S, by = c("gsis_id", "class")) %>%
  mutate(r_pts = coalesce(r_pts, 0), r_fin = coalesce(r_fin, 999L), ct = list(TIERS[[POS]]),
         r1 = as.integer(r_fin <= TIERS[[POS]][1]), r2 = as.integer(r_fin <= TIERS[[POS]][2]), r3 = as.integer(r_fin <= TIERS[[POS]][3]), lr = log1p(pmax(r_pts, 0))) %>% select(-ct)
stopifnot(nrow(D) == nrow(L$D))
cat(NM, "rows", nrow(D), " year-1 hits:", sum(D$r1), sum(D$r2), sum(D$r3), "\n")
out <- list()
for (sch in c("Rolling", "LOCO")) { tests <- if (sch == "LOCO") sort(unique(D$class)) else 2016:2023
  for (Y in tests) { tr <- if (sch == "LOCO") D[D$class != Y, ] else D[D$class <= Y - 3, ]; te <- D[D$class == Y, ]; P <- prep(tr, te)
    o <- data.frame(model = NM, scheme = sch, class = Y, row = seq_len(nrow(te)), r1 = te$r1, r2 = te$r2, r3 = te$r3, r_pts = te$r_pts)
    q <- sapply(c("r1", "r2", "r3"), function(k) fit_pred(P$Xtr, tr[[k]], P$Xte, "binomial", tr$class, unpen)$p)
    q[, 2] <- pmax(q[, 2], q[, 1]); q[, 3] <- pmax(q[, 3], q[, 2]); o$hit_score <- rowSums(q)
    o$pts_lin <- fit_pred(P$Xtr, tr$r_pts, P$Xte, "gaussian", tr$class, unpen)$p
    o$logpts <- fit_pred(P$Xtr, tr$lr, P$Xte, "gaussian", tr$class, unpen)$p
    E <- expand(P$Xtr, P$Xte, cont, character(0), "int_all")
    o$logpts_int <- fit_pred(E$Xtr, tr$lr, E$Xte, "gaussian", tr$class, unpen)$p
    out[[length(out) + 1]] <- o } }
saveRDS(bind_rows(out), sprintf("%s_rookie.rds", NM)); cat(NM, "done\n")
