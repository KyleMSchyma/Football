# =============================================================================
# FABLE build part 6: post-draft tier-ladder predictions for a regrade in dev (nothing live is touched)
#   usage: Rscript pd_21_variant_ladders.R <variant> <out_dir>
#     unpen  every position: ordinal elastic net as now, but log_pick unpenalized (ordinalNet penaltyFactors 0)
#     pick   RB / WR / TE: pick-only ordinal logit (polr on log_pick); QB: unpen (keeps its college adjustment)
# Writes <out_dir>/pd21_oof_<POS>.csv (2010-2023 leave-one-class-out, like the position scripts' LOCO files) and
# <out_dir>/pd21_board_<POS>.csv (2024-2026 from the model trained on 2010-2023), columns class, round, pick, name,
# q1 (P top tier), q2 (P top two), q3 (P any tier), post_tier. Preprocessing is fit inside each fold (pd_20 loaders).
# =============================================================================
a <- commandArgs(trailingOnly = TRUE); VARIANT <- a[1]; OUT <- a[2]
src <- readLines("pd_20_pick_penalty_experiment.R"); stop_at <- grep("^MET <- list", src) - 1
eval(parse(text = src[1:stop_at]))     # libraries, load_pos(), en/ladder helpers
TIER_CUT <- list(WR = c(12, 24, 36))
load_all <- function(POS) {            # training rows + the 2024-2026 drafted rows, same tables as pd_20
  D <- load_pos(POS)
  old <- setwd(POS_DIR[[POS]]); on.exit(setwd(old))
  full <- if (POS == "WR") readRDS("wr_model_table.rds") %>% mutate(final_power5 = as.integer(final_power5), combine_invited = as.integer(combine_invited)) else {
    e <- new.env(); sys.source(paste0(tolower(POS), "_common.R"), envir = e); e$load_table() }
  D$board <- full %>% filter(draft_season >= 2024, draft_season <= 2026, !is.na(pick))
  D
}
fit_pred <- function(POS, tr, te, prep) {
  if (VARIANT == "pick" && POS != "QB") {
    f <- polr(factor(tier, levels = 1:4, ordered = TRUE) ~ log_pick, data = tr, Hess = TRUE)
    p <- matrix(predict(f, te, type = "probs"), ncol = 4)
  } else {
    P <- prep(tr, te); Xtr <- P$Xtr; Xte <- P$Xte; keep <- apply(Xtr, 2, sd) > 0; Xtr <- Xtr[, keep, drop = FALSE]; Xte <- Xte[, keep, drop = FALSE]
    ce <- colMeans(Xtr); sc <- apply(Xtr, 2, sd); Xs <- scale(Xtr, ce, sc); Xt <- scale(Xte, ce, sc)
    y <- factor(tr$tier, levels = 1:4, ordered = TRUE); folds <- split(seq_len(nrow(tr)), tr$draft_season); pf <- as.numeric(colnames(Xtr) != "log_pick")
    fit <- ordinalNet(Xs, y, family = "cumulative", link = "logit", alpha = 0.5, parallelTerms = TRUE, nonparallelTerms = FALSE,
                      nLambda = if (POS == "WR") 25 else 20, standardize = FALSE, penaltyFactors = pf)
    tune <- tryCatch(ordinalNetTune(Xs, y, lambdaVals = fit$lambdaVals, folds = folds, printProgress = FALSE, warn = FALSE, family = "cumulative",
                                    link = "logit", alpha = 0.5, parallelTerms = TRUE, nonparallelTerms = FALSE, standardize = FALSE, penaltyFactors = pf),
                     error = function(e) NULL)
    ll <- if (is.null(tune)) NULL else rowMeans(tune$loglik); best <- if (is.null(ll) || all(!is.finite(ll))) length(fit$lambdaVals) %/% 2 else which.max(ll)
    p <- matrix(predict(fit, Xt, whichLambda = best, type = "response"), ncol = 4)
  }
  data.frame(q1 = p[, 1], q2 = p[, 1] + p[, 2], q3 = p[, 1] + p[, 2] + p[, 3])
}
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
for (POS in c("QB", "RB", "WR", "TE")) {
  D <- load_all(POS); tr_all <- D$train; nm <- if ("pfr_player_name" %in% names(tr_all)) "pfr_player_name" else "player_name"
  oof <- bind_rows(lapply(sort(unique(tr_all$draft_season)), function(Y) { tr <- tr_all %>% filter(draft_season != Y); te <- tr_all %>% filter(draft_season == Y)
    cbind(te %>% transmute(class = draft_season, round, pick, name = .data[[nm]], post_tier = tier), fit_pred(POS, tr, te, D$prep)) }))
  bd <- D$board; bd$tier <- NA_integer_; if (!"pts" %in% names(bd)) bd$pts <- NA
  brd <- cbind(bd %>% transmute(class = draft_season, round, pick, name = .data[[nm]], post_tier = NA_integer_), fit_pred(POS, tr_all, bd, D$prep))
  write.csv(oof, file.path(OUT, sprintf("pd21_oof_%s.csv", POS)), row.names = FALSE); write.csv(brd, file.path(OUT, sprintf("pd21_board_%s.csv", POS)), row.names = FALSE)
  cat(POS, VARIANT, ": LOCO rows", nrow(oof), " board rows", nrow(brd), " mean q3 oof", round(mean(oof$q3), 3), " actual any-tier", round(mean(oof$post_tier <= 3), 3), "\n")
}
