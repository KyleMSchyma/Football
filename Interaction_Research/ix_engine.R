# =============================================================================
# Interaction / squared-term experiment engine (research only; reads repo tables, writes CSVs here)
# For a design: base matrix from the model's own in-fold prep, then add
#   sq_key   squares of the 2 key continuous inputs (log_pick + age for post-draft; age/yrs_since_hs + top production for pre)
#   sq_all   squares of every continuous input
#   int_key  key input x every other continuous input
#   int_all  every pairwise product of continuous inputs
#   full     sq_all + int_all
# Continuous inputs are standardised on the training fold BEFORE squaring/multiplying (keeps x and x^2 from being collinear).
# Models: elastic-net logistic (alpha .5, lambda.min, folds = classes) per hit threshold y1/y2/y3, and gaussian
# elastic net on 3-yr points where available. Penalty factor 0 for any 'unpen' column (log_pick in the live post model).
# =============================================================================
suppressMessages({ library(dplyr); library(glmnet); library(pROC) })
aucf  <- function(y, p) if (length(unique(y)) < 2 || sd(p) == 0) NA else as.numeric(auc(roc(y, p, quiet = TRUE, direction = "<")))
brier <- function(p, y) mean((p - y)^2)
ll    <- function(p, y) { p <- pmin(pmax(p, 1e-6), 1 - 1e-6); -mean(y * log(p) + (1 - y) * log(1 - p)) }
VARIANTS <- c("base", "sq_key", "sq_all", "int_key", "int_all", "full")

expand <- function(Xtr, Xte, cont, key, variant) {
  cont <- intersect(cont, colnames(Xtr)); key <- intersect(key, cont)
  mu <- colMeans(Xtr[, cont, drop = FALSE]); s <- apply(Xtr[, cont, drop = FALSE], 2, sd); s[s == 0] <- 1
  Ztr <- scale(Xtr[, cont, drop = FALSE], mu, s); Zte <- scale(Xte[, cont, drop = FALSE], mu, s)
  add <- function(Z) { out <- list()
    sqv <- switch(variant, sq_key = key, sq_all = cont, full = cont, character(0))
    for (v in sqv) out[[paste0(v, "^2")]] <- Z[, v]^2
    prs <- if (variant == "int_key") { do.call(rbind, lapply(key, function(k) cbind(k, setdiff(cont, k)))) }
           else if (variant %in% c("int_all", "full")) t(combn(cont, 2)) else NULL
    if (!is.null(prs)) { prs <- unique(t(apply(prs, 1, sort)))
      for (i in seq_len(nrow(prs))) out[[paste0(prs[i, 1], ":", prs[i, 2])]] <- Z[, prs[i, 1]] * Z[, prs[i, 2]] }
    if (!length(out)) return(NULL); as.matrix(as.data.frame(out, check.names = FALSE)) }
  a <- add(Ztr); b <- add(Zte)
  if (is.null(a)) list(Xtr = Xtr, Xte = Xte) else list(Xtr = cbind(Xtr, a), Xte = cbind(Xte, b))
}

fit_pred <- function(Xtr, ytr, Xte, fam, classes, unpen) {
  keep <- apply(Xtr, 2, sd) > 0; Xtr <- Xtr[, keep, drop = FALSE]; Xte <- Xte[, keep, drop = FALSE]
  pf <- as.numeric(!colnames(Xtr) %in% unpen)
  f <- tryCatch(suppressWarnings(cv.glmnet(Xtr, ytr, family = fam, alpha = 0.5, foldid = as.integer(factor(classes)), penalty.factor = pf)), error = function(e) NULL)
  if (is.null(f)) return(list(p = rep(mean(ytr), nrow(Xte)), nz = NA))
  cf <- coef(f, s = "lambda.min"); nz <- rownames(cf)[as.vector(cf != 0)]
  list(p = as.numeric(predict(f, Xte, s = "lambda.min", type = "response")), nz = setdiff(nz, "(Intercept)"))
}

# D: data.frame with class, y1, y2, y3, (pts); prep(tr, te) -> list(Xtr, Xte); cont, key: continuous column names
run_design <- function(label, D, prep, cont, key, unpen = character(0), tests, scheme, has_pts = TRUE, variants = VARIANTS) {
  rows <- list(); sel <- list()
  for (Y in tests) {
    tr <- if (scheme == "LOCO") D[D$class != Y, ] else D[D$class <= Y - 3, ]; te <- D[D$class == Y, ]
    if (!nrow(te)) next
    P <- prep(tr, te)
    for (v in variants) { E <- expand(P$Xtr, P$Xte, cont, key, v)
      o <- data.frame(model = label, scheme = scheme, variant = v, class = Y, row = seq_len(nrow(te)), y1 = te$y1, y2 = te$y2, y3 = te$y3,
                      pts = if (has_pts) te$pts else NA)
      for (k in 1:3) { r <- fit_pred(E$Xtr, tr[[paste0("y", k)]], E$Xte, "binomial", tr$class, unpen); o[[paste0("p", k)]] <- r$p
        if (k == 3 && v != "base") sel[[length(sel) + 1]] <- data.frame(model = label, scheme = scheme, variant = v, class = Y, term = r$nz) }
      o$p2 <- pmax(o$p2, o$p1); o$p3 <- pmax(o$p3, o$p2)
      o$ptsh <- if (has_pts) fit_pred(E$Xtr, tr$pts, E$Xte, "gaussian", tr$class, unpen)$p else NA
      rows[[length(rows) + 1]] <- o }
    cat(label, scheme, Y, "done\n")
  }
  list(pred = bind_rows(rows), sel = bind_rows(sel))
}

summarise_pred <- function(pr, B = 1000) {
  base <- pr %>% filter(variant == "base")
  bind_rows(lapply(split(pr, list(pr$model, pr$scheme, pr$variant), drop = TRUE), function(d) {
    b <- base %>% filter(model == d$model[1], scheme == d$scheme[1]); stopifnot(nrow(b) == nrow(d))
    m <- data.frame(model = d$model[1], scheme = d$scheme[1], variant = d$variant[1], n = nrow(d))
    for (k in 1:3) { y <- d[[paste0("y", k)]]; p <- d[[paste0("p", k)]]
      m[[paste0("AUC", k)]] <- aucf(y, p); m[[paste0("LL", k)]] <- ll(p, y); m[[paste0("Brier", k)]] <- brier(p, y) }
    m$LL_mean <- mean(c(m$LL1, m$LL2, m$LL3)); m$AUC_mean <- mean(c(m$AUC1, m$AUC2, m$AUC3))
    m$RMSE_pts <- if (all(is.na(d$pts))) NA else sqrt(mean((d$ptsh - d$pts)^2, na.rm = TRUE))
    # paired bootstrap of mean log-loss (3 thresholds) vs base; negative = variant better
    lld <- function(i) mean(sapply(1:3, function(k) ll(d[[paste0("p", k)]][i], d[[paste0("y", k)]][i]) - ll(b[[paste0("p", k)]][i], b[[paste0("y", k)]][i])))
    set.seed(2026); bs <- replicate(B, lld(sample.int(nrow(d), replace = TRUE)))
    m$dLL <- lld(seq_len(nrow(d))); m$dLL_lo <- quantile(bs, .025); m$dLL_hi <- quantile(bs, .975)
    m$dLL_pct <- 100 * m$dLL / mean(c(ll(b$p1, b$y1), ll(b$p2, b$y2), ll(b$p3, b$y3)))
    m$classes_better <- sum(sapply(split(seq_len(nrow(d)), d$class), function(i) lld(i) < 0)); m$classes <- length(unique(d$class))
    m }))
}
