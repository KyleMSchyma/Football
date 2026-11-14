# Patch the dev copies of pd_07 / pd_09 (Football2_PostDraft_dev_<variant>) to grade from the pd_21 ladders.
# usage: Rscript pd_21_patch_dev.R <dev_dir> <variant>
a <- commandArgs(trailingOnly = TRUE); D <- a[1]; V <- a[2]
rep1 <- function(f, old, new) { s <- paste(readLines(f, warn = FALSE), collapse = "\n")
  n <- lengths(regmatches(s, gregexpr(old, s, fixed = TRUE))); if (n != 1) stop(f, " pattern count ", n, ": ", substr(old, 1, 70))
  writeLines(sub(old, new, s, fixed = TRUE), f) }
f7 <- file.path(D, "pd_07_postdraft_grades.R")
rep1(f7, '  s <- src[[POS]]
  o <- read.csv(s$oof, stringsAsFactors = FALSE)
  if (POS == "WR") {
    o <- o %>% filter(scheme == "LOCO", model == "post_enet") %>%
      transmute(class = draft_season, round, pick, name = pfr_player_name, q1 = p_wr1, q2 = p_wr2plus, q3 = p_wr3plus, post_tier = tier)
  } else {
    o <- o %>% filter(scheme == "LOCO") %>%
      transmute(class = draft_season, round, pick, name = pfr_player_name, q1 = .data[[s$cols[1]]], q2 = .data[[s$cols[2]]], q3 = .data[[s$cols[3]]], post_tier = tier)
  }
  b <- read.csv(s$board, stringsAsFactors = FALSE) %>%
    transmute(class = draft_season, round, pick, name = pfr_player_name, q1 = .data[[s$cols[1]]], q2 = .data[[s$cols[2]]], q3 = .data[[s$cols[3]]], post_tier = NA_integer_)',
sprintf('  # FABLE dev (%s): ladders from pd_21_variant_ladders.R in this folder
  o <- read.csv(sprintf("pd21_oof_%%s.csv", POS), stringsAsFactors = FALSE)
  b <- read.csv(sprintf("pd21_board_%%s.csv", POS), stringsAsFactors = FALSE) %%>%% mutate(post_tier = NA_integer_)', V))
f9 <- file.path(D, "pd_09_mock_2027.R")
rep1(f9, 'fit_ladder <- function(L) {
  Xs <- scale(L$X, L$ce, L$sc)', sprintf('VARIANT <- "%s"   # FABLE dev: unpen = log_pick unpenalized; pick = pick-only ordinal logit for RB / WR / TE
fit_ladder <- function(L) {
  if (VARIANT == "pick" && L$pos != "QB") return(list(polr = MASS::polr(factor(tier, levels = 1:4, ordered = TRUE) ~ log_pick, data = L$train, Hess = TRUE), best = NA, fit = list(lambdaVals = NA)))
  Xs <- scale(L$X, L$ce, L$sc); PF <- as.numeric(colnames(L$X) != "log_pick")', V))
rep1(f9, 'fit <- ordinalNet(Xs, y, family = "cumulative", link = "logit", alpha = 0.5, parallelTerms = TRUE,
                    nonparallelTerms = FALSE, nLambda = L$nlam, standardize = FALSE)',
'fit <- ordinalNet(Xs, y, family = "cumulative", link = "logit", alpha = 0.5, parallelTerms = TRUE,
                    nonparallelTerms = FALSE, nLambda = L$nlam, standardize = FALSE, penaltyFactors = PF)')
rep1(f9, 'nonparallelTerms = FALSE, standardize = FALSE), error = function(e) NULL)
  ll <- if (is.null(tune)) NULL else rowMeans(tune$loglik)
  best <- if (is.null(ll) || all(!is.finite(ll))) length(fit$lambdaVals) %/% 2 else which.max(ll)
  list(fit = fit, best = best)',
'nonparallelTerms = FALSE, standardize = FALSE, penaltyFactors = PF), error = function(e) NULL)
  ll <- if (is.null(tune)) NULL else rowMeans(tune$loglik)
  best <- if (is.null(ll) || all(!is.finite(ll))) length(fit$lambdaVals) %/% 2 else which.max(ll)
  list(fit = fit, best = best)')
rep1(f9, '  pr <- matrix(predict(F$fit, scale(L$prep(d), L$ce, L$sc), whichLambda = F$best, type = "response"), ncol = 4)',
'  pr <- if (!is.null(F$polr)) matrix(predict(F$polr, data.frame(log_pick = L$prep(d)[, "log_pick"]), type = "probs"), ncol = 4) else
    matrix(predict(F$fit, scale(L$prep(d), L$ce, L$sc), whichLambda = F$best, type = "response"), ncol = 4)')
rep1(f9, '  list(tbl = tbl, train = train, X = X, ce = colMeans(X), sc = sc, nlam = nlam, prep = prep, all_num = all_num)',
'  list(tbl = tbl, train = train, X = X, ce = colMeans(X), sc = sc, nlam = nlam, prep = prep, all_num = all_num, pos = POS)')
cat("patched", D, V, "\n")
