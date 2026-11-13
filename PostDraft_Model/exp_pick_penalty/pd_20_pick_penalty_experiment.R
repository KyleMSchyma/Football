# =============================================================================
# FABLE Review finding 3: does the post-draft model shrink its best input (log_pick) too hard?
# New experiment script; reads each position folder's training table and preprocessing, changes nothing there.
#
# Strict rolling origin (as the position Phase 3/4 scripts): test class Y = 2016..2023, train on classes <= Y - 3,
# all preprocessing fit inside the fold. Models compared on the same rows:
#   pick     pick-only benchmark (lm / logistic on log_pick; polr for the ladder)
#   cur      current post-draft elastic net (alpha 0.5, lambda.min by class-grouped CV); ladder = ordinalNet, max CV loglik
#   i        log_pick unpenalized (glmnet penalty.factor 0; ordinalNet penaltyFactors 0)
#   ii       pick-only fit first, elastic net on the other inputs with the pick-only linear predictor as an offset
#            (points and hits; ordinalNet has no offset argument, so the ladder has no (ii))
#   iii      lambda.1se in place of lambda.min (ladder: the most penalized lambda within 1 SE of the best fold-mean loglik)
#   iv       i + iii
# Targets: 3-year fantasy points (RMSE, Spearman); hit = any season in the top tier 1 / 1-2 / 1-3 in years 1-3
# (QB, RB top 8 / 16 / 24; TE 6 / 12 / 18; WR 12 / 24 / 36) as separate logistic elastic nets (Brier, AUC); and the
# 4-level ordinal ladder (RPS). Paired bootstrap of each variant minus cur and minus pick (players resampled, 2000 draws,
# seed 2026). Writes pd20_metrics.csv, pd20_bootstrap.csv.  Run: Rscript pd_20_pick_penalty_experiment.R [QB RB WR TE]
# =============================================================================
suppressMessages({ library(dplyr); library(glmnet); library(ordinalNet); library(MASS); library(pROC) })
select <- dplyr::select
POS_DIR <- c(QB = "../Football2_QB", RB = "../Football2_RB", WR = "../Football2", TE = "../Football2_TE")
args <- commandArgs(trailingOnly = TRUE); POSS <- if (length(args)) args else c("WR", "QB", "RB", "TE")
aucf  <- function(y, p) if (length(unique(y)) < 2 || sd(p) == 0) NA else as.numeric(auc(roc(y, p, quiet = TRUE, direction = "<")))
brier <- function(p, y) mean((p - y)^2); rmse <- function(p, y) sqrt(mean((p - y)^2))

# ---------- per-position data and in-fold preprocessing ----------
load_pos <- function(POS) {
  old <- setwd(POS_DIR[[POS]]); on.exit(setwd(old))
  if (POS == "WR") {
    tbl <- readRDS("wr_model_table.rds") %>% mutate(final_power5 = as.integer(final_power5), combine_invited = as.integer(combine_invited)) %>%
      left_join(read.csv("phase5_finish_targets.csv") %>% select(draft_season, pick, finish_y1, finish_y2, finish_y3, finish_sum_3yr), by = c("draft_season", "pick")) %>%
      mutate(best_finish = pmin(finish_y1, finish_y2, finish_y3, na.rm = TRUE),
             tier = case_when(best_finish <= 12 ~ 1L, best_finish <= 24 ~ 2L, best_finish <= 36 ~ 3L, TRUE ~ 4L), pts = total_ppr_3yr)
    drills <- c("forty", "vertical", "broad_jump", "speed_score")
    pre_num <- c("age_at_draft", "final_dominator", "best_dominator", "final_yptpa", "breakout_age_filled", "career_rec_yds", "college_seasons", "height_in", "weight_lb", "recruit_rating")
    pre_flag <- c("broke_out", "transferred", "early_declare", "final_power5", "college_matched", "combine_invited", "miss_forty", "miss_vertical", "miss_broad_jump")
    num <- c(pre_num, "log_pick", "vacated_target_share", "team_targets_prev")
    prep <- function(tr, te) {      # wr_phase3 fit_prep / apply_prep, fit on tr
      med <- sapply(c(num, drills), function(v) median(tr[[v]], na.rm = TRUE)); flag <- num[sapply(num, function(v) any(is.na(tr[[v]])))]
      dm <- as.matrix(tr[, drills]); for (v in drills) dm[is.na(dm[, v]), v] <- med[v]; pca <- prcomp(dm, center = TRUE, scale. = TRUE)
      ap <- function(d) { out <- data.frame(row.names = seq_len(nrow(d)))
        for (v in num) { x <- d[[v]]; if (v %in% flag) out[[paste0("na_", v)]] <- as.integer(is.na(x)); x[is.na(x)] <- med[v]; out[[v]] <- x }
        dm <- as.matrix(d[, drills]); for (v in drills) dm[is.na(dm[, v]), v] <- med[v]; pcs <- predict(pca, dm)[, 1:2, drop = FALSE]
        out$athletic_pc1 <- pcs[, 1]; out$athletic_pc2 <- pcs[, 2]
        for (v in pre_flag) out[[v]] <- as.integer(coalesce(as.numeric(d[[v]]), 0)); as.matrix(out) }
      list(Xtr = ap(tr), Xte = ap(te)) }
    train <- tbl %>% filter(!is.na(total_ppr_3yr), !is.na(finish_sum_3yr))
  } else {
    e <- new.env(); sys.source(paste0(tolower(POS), "_common.R"), envir = e)
    train <- e$load_table() %>% filter(!is.na(finish_sum_3yr), !is.na(total_pts_3yr)) %>% mutate(pts = total_pts_3yr)
    num <- c(e$pre_num, e$post_num)
    prep <- function(tr, te) { p <- e$fit_prep(tr, num); list(Xtr = e$apply_prep(p, tr), Xte = e$apply_prep(p, te)) }
  }
  list(train = train, prep = prep)
}

# ---------- elastic-net variants for one target ----------
en_variants <- function(Xtr, ytr, Xte, fam, classes, off_tr, off_te) {
  foldid <- as.integer(factor(classes)); keep <- apply(Xtr, 2, sd) > 0; Xtr <- Xtr[, keep, drop = FALSE]; Xte <- Xte[, keep, drop = FALSE]
  pf <- as.numeric(colnames(Xtr) != "log_pick")
  pr <- function(f, X, s, newoffset = NULL) if (is.null(f)) rep(mean(ytr), nrow(X)) else
    as.numeric(predict(f, X, s = s, type = "response", newoffset = newoffset))
  f0 <- tryCatch(cv.glmnet(Xtr, ytr, family = fam, alpha = 0.5, foldid = foldid), error = function(e) NULL)
  f1 <- tryCatch(cv.glmnet(Xtr, ytr, family = fam, alpha = 0.5, foldid = foldid, penalty.factor = pf), error = function(e) NULL)
  nop <- colnames(Xtr) != "log_pick"
  f2 <- tryCatch(cv.glmnet(Xtr[, nop, drop = FALSE], ytr, family = fam, alpha = 0.5, foldid = foldid, offset = off_tr), error = function(e) NULL)
  ii <- if (is.null(f2)) { if (fam == "binomial") plogis(off_te) else off_te } else pr(f2, Xte[, nop, drop = FALSE], "lambda.min", off_te)
  data.frame(cur = pr(f0, Xte, "lambda.min"), i = pr(f1, Xte, "lambda.min"), ii = ii, iii = pr(f0, Xte, "lambda.1se"), iv = pr(f1, Xte, "lambda.1se"))
}
# ---------- ordinal ladder variants ----------
ladder_variants <- function(Xtr, tr, Xte, te) {
  keep <- apply(Xtr, 2, sd) > 0; Xtr <- Xtr[, keep, drop = FALSE]; Xte <- Xte[, keep, drop = FALSE]
  ce <- colMeans(Xtr); sc <- apply(Xtr, 2, sd); Xs <- scale(Xtr, ce, sc); Xt <- scale(Xte, ce, sc)
  y <- factor(tr$tier, levels = 1:4, ordered = TRUE); folds <- split(seq_len(nrow(tr)), tr$draft_season)
  pf <- as.numeric(colnames(Xtr) != "log_pick")
  one <- function(pfac) {
    fit <- ordinalNet(Xs, y, family = "cumulative", link = "logit", alpha = 0.5, parallelTerms = TRUE, nonparallelTerms = FALSE,
                      nLambda = 20, standardize = FALSE, penaltyFactors = pfac)
    tune <- tryCatch(ordinalNetTune(Xs, y, lambdaVals = fit$lambdaVals, folds = folds, printProgress = FALSE, warn = FALSE, family = "cumulative",
                                    link = "logit", alpha = 0.5, parallelTerms = TRUE, nonparallelTerms = FALSE, standardize = FALSE, penaltyFactors = pfac),
                     error = function(e) NULL)
    nl <- length(fit$lambdaVals)
    if (is.null(tune)) { bmin <- b1se <- nl %/% 2 } else {
      L <- tune$loglik; m <- rowMeans(L); m[!is.finite(m)] <- -Inf; bmin <- which.max(m)
      se <- sd(L[bmin, ]) / sqrt(ncol(L)); b1se <- min(which(m >= m[bmin] - se)) }   # lambdaVals decrease: smaller index = more penalty
    q <- function(b) { p <- matrix(predict(fit, Xt, whichLambda = b, type = "response"), ncol = 4); cbind(p[, 1], p[, 1] + p[, 2], p[, 1] + p[, 2] + p[, 3]) }
    list(min = q(bmin), se = q(b1se)) }
  a <- one(rep(1, ncol(Xs))); b <- one(pf)
  pk <- predict(polr(factor(tier, levels = 1:4, ordered = TRUE) ~ log_pick, data = tr, Hess = TRUE), te, type = "probs")
  pk <- cbind(pk[, 1], pk[, 1] + pk[, 2], pk[, 1] + pk[, 2] + pk[, 3])
  list(pick = pk, cur = a$min, i = b$min, iii = a$se, iv = b$se)
}

MET <- list(); BOOT <- list(); set.seed(2026)
for (POS in POSS) {
  cat("\n=====", POS, "=====\n"); D <- load_pos(POS); train <- D$train
  rows <- list()
  for (Y in 2016:2023) {
    tr <- train %>% filter(draft_season <= Y - 3); te <- train %>% filter(draft_season == Y); stopifnot(max(tr$draft_season) <= Y - 3)
    if (!nrow(te)) next
    P <- D$prep(tr, te)
    o <- te %>% transmute(pos = POS, draft_season, pick, pts, tier, y1 = as.integer(tier == 1), y2 = as.integer(tier <= 2), y3 = as.integer(tier <= 3))
    # points
    lmf <- lm(pts ~ log_pick, data = tr); o$pts_pick <- pmax(0, predict(lmf, te))
    ev <- en_variants(P$Xtr, tr$pts, P$Xte, "gaussian", tr$draft_season, predict(lmf, tr), predict(lmf, te))
    for (m in names(ev)) o[[paste0("pts_", m)]] <- pmax(0, ev[[m]])
    # hits by tier
    for (k in 1:3) { yk <- as.integer(tr$tier <= k); g <- glm(yk ~ log_pick, binomial, data = tr)
      o[[paste0("h", k, "_pick")]] <- predict(g, te, type = "response")
      ev <- if (sum(yk) >= 3) en_variants(P$Xtr, yk, P$Xte, "binomial", tr$draft_season, predict(g, tr), predict(g, te)) else
        as.data.frame(setNames(replicate(5, rep(mean(yk), nrow(te)), simplify = FALSE), c("cur", "i", "ii", "iii", "iv")))
      for (m in names(ev)) o[[paste0("h", k, "_", m)]] <- ev[[m]] }
    # ladder
    lv <- ladder_variants(P$Xtr, tr, P$Xte, te)
    for (m in names(lv)) for (k in 1:3) o[[paste0("l", k, "_", m)]] <- lv[[m]][, k]
    rows[[as.character(Y)]] <- o; cat(Y, "train", nrow(tr), "test", nrow(te), "\n")
  }
  R <- bind_rows(rows); write.csv(R, sprintf("pd20_oof_%s.csv", POS), row.names = FALSE)
  M <- c("pick", "cur", "i", "ii", "iii", "iv")
  rps <- function(m, i = seq_len(nrow(R))) if (m == "ii") NA else mean(((R[[paste0("l1_", m)]][i] - R$y1[i])^2 + (R[[paste0("l2_", m)]][i] - R$y2[i])^2 + (R[[paste0("l3_", m)]][i] - R$y3[i])^2) / 3)
  met <- bind_rows(lapply(M, function(m) data.frame(pos = POS, model = m, n = nrow(R),
    pts_RMSE = rmse(R[[paste0("pts_", m)]], R$pts), pts_Spearman = cor(R[[paste0("pts_", m)]], R$pts, method = "spearman"),
    hit1_Brier = brier(R[[paste0("h1_", m)]], R$y1), hit1_AUC = aucf(R$y1, R[[paste0("h1_", m)]]),
    hit2_Brier = brier(R[[paste0("h2_", m)]], R$y2), hit2_AUC = aucf(R$y2, R[[paste0("h2_", m)]]),
    hit3_Brier = brier(R[[paste0("h3_", m)]], R$y3), hit3_AUC = aucf(R$y3, R[[paste0("h3_", m)]]), ladder_RPS = rps(m))))
  print(met %>% mutate(across(where(is.double), ~ round(.x, 4)))); MET[[POS]] <- met
  # paired bootstrap: variant - cur and variant - pick, players resampled
  idx <- replicate(2000, sample.int(nrow(R), replace = TRUE), simplify = FALSE)
  stat <- function(m, i) c(pts_RMSE = rmse(R[[paste0("pts_", m)]][i], R$pts[i]), hit1_Brier = brier(R[[paste0("h1_", m)]][i], R$y1[i]),
                           hit2_Brier = brier(R[[paste0("h2_", m)]][i], R$y2[i]), hit3_Brier = brier(R[[paste0("h3_", m)]][i], R$y3[i]), ladder_RPS = rps(m, i))
  for (m in c("i", "ii", "iii", "iv")) for (ref in c("cur", "pick")) {
    pt <- stat(m, seq_len(nrow(R))) - stat(ref, seq_len(nrow(R))); bd <- t(sapply(idx, function(i) stat(m, i) - stat(ref, i)))
    BOOT[[length(BOOT) + 1]] <- data.frame(pos = POS, variant = m, vs = ref, metric = names(pt), diff = pt,
      lo = apply(bd, 2, quantile, .025, na.rm = TRUE), hi = apply(bd, 2, quantile, .975, na.rm = TRUE)) }
}
MT <- bind_rows(MET) %>% mutate(across(where(is.double), ~ round(.x, 4))); BT <- bind_rows(BOOT) %>% mutate(across(c(diff, lo, hi), ~ round(.x, 4)),
  verdict = ifelse(is.na(diff), "n/a", ifelse(hi < 0, "better", ifelse(lo > 0, "worse", "tie"))))
fs <- function(f, x) { if (file.exists(f)) x <- bind_rows(read.csv(f) %>% filter(!pos %in% POSS), x); write.csv(x, f, row.names = FALSE) }
fs("pd20_metrics.csv", MT); fs("pd20_bootstrap.csv", BT)
options(width = 200); cat("\nBOOTSTRAP (diff = variant - reference; negative = variant better; 95% interval):\n"); print(BT, row.names = FALSE)
