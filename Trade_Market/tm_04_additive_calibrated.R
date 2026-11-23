# tm_04_additive_calibrated.R
# "Trade" value method, step 4: additive market values that compare directly with our 100k values.
#
# Problem: tm_02's additive fit left a consolidation bias in holdout trades (the side with fewer assets priced
# 20-30% too low), and its values were flatter than ours.
# Synthetic tests (made-up trades with known values, see README) showed this bias appears EVEN WHEN THE TRUE MARKET IS
# PERFECTLY ADDITIVE. Two causes, both in the estimator, not the market:
#   1. Shrinkage of each asset toward its position average (LAMBDA0 = 2 in tm_02) pulls stars down and depth up.
#   2. The data are accepted trades, which are all roughly fair, so a fit that squeezes every value toward the
#      others always looks a bit "fairer". Log values come out compressed (attenuated).
# Rejected along the way (see README): a per-asset roster cost (package = sum of (v - c)) is mathematically the same
# additive model, so c cannot be estimated; a depth discount (2nd asset counts lambda, 3rd lambda^2...) cannot be
# fitted because lambda = 0 with equal values makes every trade look fair.
#
# Fix here: light shrinkage (LAMBDA0 = 0.05), then a single stretch s applied to the fitted log values
# (v' = v^s, the reference asset stays at 1), with s chosen so the 14-day HOLDOUT trades show no consolidation bias
# (mean log gap of the fewer-asset side = 0). On synthetic additive data this recovers the true spread
# (slope of true on fitted log value 0.97; unstretched 1.11; tm_02 settings 1.24).
# Everything else (data, filters, format betas, H = 7 days, k = 2) is as tm_02.
#
# Outputs: out/<type>_add_*.csv (aggregates only, no league ids).
# Run: Rscript tm_04_additive_calibrated.R dynasty   and   Rscript tm_04_additive_calibrated.R redraft
suppressPackageStartupMessages({ library(data.table) })
set.seed(2026)
args <- commandArgs(TRUE)
TYPE <- if (length(args)) tolower(args[1]) else "dynasty"
ROOT <- Sys.getenv("TM_ROOT", file.path(Sys.getenv("USERPROFILE"), "Documents", "R Studio", "Football2", "research", "dd_trades"))
RAW  <- file.path(ROOT, "raw"); OUTD <- file.path(ROOT, "out")
dir.create(OUTD, showWarnings = FALSE, recursive = TRUE)
TAG  <- Sys.getenv("TM_TAG", "add")   # output tag, e.g. "add4" for the 4-shape run
out  <- function(x, name) fwrite(x, file.path(OUTD, sprintf("%s_%s_%s.csv", TYPE, TAG, name)))
say  <- function(...) message(format(Sys.time(), "%H:%M:%S "), sprintf(...))

HOLD_DAYS <- 14; MIN_APPEAR <- 25; DELTA <- 0.7
LAMBDA0 <- as.numeric(Sys.getenv("TM_LAMBDA0", "0.05"))   # shrinkage of each asset toward its group mean (long-run fit)
H_GRID <- c(3, 7, 14, 30, 60, 120); K_GRID <- c(2, 10, 50)
REF <- Sys.getenv("TM_REF", "2027mid1stpi")   # redraft has almost no picks: falls back below

# ---------------- data ----------------
files <- list.files(RAW, sprintf("^%s_.*\\.rds$", TYPE), full.names = TRUE)
d <- rbindlist(lapply(files, function(f) as.data.table(readRDS(f))), fill = TRUE)
d <- unique(d, by = "transaction_id")
d[, when := as.POSIXct(substr(date, 1, 19), format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")]
n_raw <- nrow(d)
d <- d[!is.na(when) & sidea != "" & sideb != "" &
         teams %in% c(8, 10, 12, 14) & ppr %in% c(0.5, 1) & tep <= 1 & !bestball &
         starters >= 6 & starters <= 14]
samp <- as.numeric(Sys.getenv("TM_SAMPLE", "1"))
if (samp < 1) d <- d[sample(.N, round(.N * samp))]
say("%s: %d raw trades, %d usable (both sides non-empty, compatible format), %d leagues",
    TYPE, n_raw, nrow(d), uniqueN(d$league_id))

# format mix (for the write-up)
d[, league_id := NULL]   # never needed again; never written

# ---------------- assets ----------------
long <- rbind(d[, .(asset = unlist(strsplit(sidea, "|", fixed = TRUE)), side = 1L), by = transaction_id],
              d[, .(asset = unlist(strsplit(sideb, "|", fixed = TRUE)), side = -1L), by = transaction_id])
long <- long[asset != ""]
# optional: keep only some trade shapes, e.g. TM_SHAPES="1-1,1-2,2-2,2-3" (Kyle 2026-11-23: big-step trades distort)
SHAPES <- Sys.getenv("TM_SHAPES", "")
if (nzchar(SHAPES)) {
  keep <- trimws(strsplit(SHAPES, ",")[[1]])
  sz0 <- long[, .(a = sum(side > 0), b = sum(side < 0)), by = transaction_id][, shape := paste0(pmin(a, b), "-", pmax(a, b))]
  ids_keep <- sz0[shape %in% keep, transaction_id]
  long <- long[transaction_id %in% ids_keep]; d <- d[transaction_id %in% ids_keep]
  say("trade shapes kept (%s): %d trades", SHAPES, nrow(d))
}

ids <- tryCatch({
  x <- as.data.table(nflreadr::load_ff_playerids())
  x[!is.na(sleeper_id), .(asset = as.character(sleeper_id), name, pos = position)][!duplicated(asset)]
}, error = function(e) { say("player id table unavailable: %s", conditionMessage(e)); data.table(asset = character(), name = character(), pos = character()) })

pk <- regmatches(unique(long$asset), regexec("^(\\d{4})(early|mid|late)?(\\d)(st|nd|rd|th)pi$", unique(long$asset)))
picks <- rbindlist(lapply(pk, function(m) if (length(m)) data.table(asset = m[1], pick_year = as.integer(m[2]), pick_tier = ifelse(m[3] == "", "unk", m[3]), pick_round = as.integer(m[4]))))
# picks whose slot is known appear as "2026.1.1.pi" (year.round.slot): tier from slot (1-4 early, 5-8 mid, 9+ late)
pk2 <- regmatches(unique(long$asset), regexec("^(\\d{4})\\.(\\d+)\\.(\\d+)\\.pi$", unique(long$asset)))
picks <- rbind(picks, rbindlist(lapply(pk2, function(m) if (length(m)) data.table(asset = m[1], pick_year = as.integer(m[2]),
  pick_tier = c("early", "mid", "late")[pmin(3, (as.integer(m[4]) - 1) %/% 4 + 1)], pick_round = as.integer(m[3])))), fill = TRUE)
A <- long[, .(n_trades = uniqueN(transaction_id)), by = asset]
A <- merge(A, ids, by = "asset", all.x = TRUE)
if (nrow(picks)) A <- merge(A, picks, by = "asset", all.x = TRUE) else A[, `:=`(pick_year = NA_integer_, pick_tier = NA_character_, pick_round = NA_integer_)]
A[, grp := fifelse(!is.na(pick_year), "PICK", fifelse(pos %in% c("QB", "RB", "WR", "TE"), pos, "OTH"))]
A[grp == "PICK", name := fifelse(grepl("^\\d{4}\\.", asset), sprintf("%d pick %s", pick_year, sub("^\\d{4}\\.(\\d+)\\.(\\d+)\\.pi$", "\\1.\\2", asset)),
                                 sprintf("%d %s %s", pick_year, pick_tier, c("1st","2nd","3rd","4th","5th","6th","7th")[pmin(pick_round, 7)]))]
# rare assets are pooled per group so their trades still count
A[, model_asset := fifelse(n_trades >= MIN_APPEAR, asset, paste0("RARE_", grp))]
say("%d distinct assets, %d modelled individually", nrow(A), sum(A$n_trades >= MIN_APPEAR))

long <- merge(long, A[, .(asset, model_asset, grp)], by = "asset")
long <- long[, .(n = .N), by = .(transaction_id, model_asset, grp, side)]   # same pooled asset twice -> count
M <- unique(long[, .(model_asset, grp)])[order(model_asset)]
M[, ai := .I]
if (!REF %in% M$model_asset) {   # fallback: pin the most-traded individually modelled asset
  REF <- A[n_trades >= MIN_APPEAR][order(-n_trades), asset][1]
  say("reference asset not found; pinning the most-traded asset instead: %s", REF)
}
GROUPS <- c("QB", "RB", "WR", "TE", "PICK", "OTH"); M[, gi := match(grp, GROUPS)]
long <- merge(long, M[, .(model_asset, ai, gi)], by = "model_asset")

d <- d[transaction_id %in% long$transaction_id][order(when)]
d[, ti := .I]
long <- merge(long, d[, .(transaction_id, ti)], by = "transaction_id")
setorder(long, ti)
X <- cbind(sf = as.numeric(d$sf) - 1, ppr1 = d$ppr - 1, tep = d$tep, teams = (d$teams - 12) / 2, start = d$starters - 10)
NK <- ncol(X); nA <- nrow(M); nG <- length(GROUPS)
tmax <- max(d$when)
d[, age := as.numeric(difftime(tmax, when, units = "days"))]
iref <- M[model_asset == REF, ai]


H_FIX <- as.numeric(Sys.getenv("TM_H", "7")); K_FIX <- as.numeric(Sys.getenv("TM_K", "2"))
NB <- NK * nG


# par = theta (nA), beta (NK x nG), [mu (nG), long fit only]; lam fixed (1 = additive, as tm_02)
make_obj <- function(rows, w, prior = NULL, k = 0, lam = 1) {
  L <- long[ti %in% rows]
  tmap <- match(L$ti, rows)
  ai <- L$ai; gi <- L$gi; sd <- L$side; cn <- L$n
  key <- tmap * 2L + (sd > 0)                      # one key per trade side
  Xr <- X[rows, , drop = FALSE]
  Xe <- lapply(seq_len(NK), function(j) Xr[tmap, j])
  nmax <- max(cn)
  long_fit <- is.null(prior)
  function(par) {
    th <- par[1:nA]; B <- matrix(par[nA + 1:NB], NK, nG); off <- nA + NB
    if (long_fit) { mu <- par[off + 1:nG]; off <- off + nG }
    eta <- th[ai]; for (j in 1:NK) eta <- eta + Xe[[j]] * B[j, gi]
    v <- exp(eta)
    if (lam < 1) {
      o <- order(key, -v, method = "radix")
      ko <- key[o]; co <- cn[o]
      cs <- cumsum(co); first <- !duplicated(ko)
      start_k <- (cs - co)[first][cumsum(first)]   # count of assets before each side
      s <- integer(length(o)); s[o] <- (cs - co) - start_k   # copies of better assets ahead of this row
      wt <- numeric(length(o))
      for (jj in 0:(nmax - 1)) { m <- cn > jj; wt[m] <- wt[m] + lam^(s[m] + jj) }
    } else wt <- cn
    e <- wt * v
    SA <- rowsum(e * (sd > 0), tmap, reorder = TRUE)[, 1]
    SB <- rowsum(e * (sd < 0), tmap, reorder = TRUE)[, 1]
    r <- log(SA) - log(SB)
    hub <- ifelse(abs(r) <= DELTA, r^2 / 2, DELTA * (abs(r) - DELTA / 2))
    f <- sum(w * hub)
    psi <- w * pmax(-DELTA, pmin(DELTA, r))
    S <- ifelse(sd > 0, SA[tmap], SB[tmap])
    de <- psi[tmap] * sd * e / S
    gth <- numeric(nA); gs <- rowsum(de, ai); gth[as.integer(rownames(gs))] <- gs[, 1]
    gB <- matrix(0, NK, nG)
    for (j in 1:NK) { gg <- rowsum(de * Xe[[j]], gi); gB[j, as.integer(rownames(gg))] <- gg[, 1] }
    if (long_fit) {
      dev <- th - mu[M$gi]
      f <- f + LAMBDA0 * sum(dev^2) + 0.5 * sum(B^2)
      gth <- gth + 2 * LAMBDA0 * dev; gB <- gB + B
      gmu <- -2 * LAMBDA0 * as.numeric(tapply(dev, factor(M$gi, levels = 1:nG), sum)); gmu[is.na(gmu)] <- 0
      g <- c(gth, as.numeric(gB), gmu)
    } else {
      dev <- th - prior$theta; dB <- B - prior$beta
      f <- f + k * sum(dev^2) + k * sum(dB^2)
      gth <- gth + 2 * k * dev; gB <- gB + 2 * k * dB
      g <- c(gth, as.numeric(gB))
    }
    g[iref] <- 0
    attr(f, "gradient") <- g; attr(f, "r") <- r
    f
  }
}
fit <- function(obj, start, maxit = 150) {
  last_p <- NULL; last_v <- NULL
  ev <- function(p) { p[iref] <- 0; if (is.null(last_p) || !identical(p, last_p)) { last_v <<- obj(p); last_p <<- p }; last_v }
  o <- optim(start, function(p) as.numeric(ev(p)), function(p) attr(ev(p), "gradient"), method = "L-BFGS-B",
             control = list(maxit = maxit, factr = 1e8))
  o$par[iref] <- 0; o
}
unpack <- function(par, long_fit) list(theta = par[1:nA], beta = matrix(par[nA + 1:NB], NK, nG),
                                       mu = if (long_fit) par[nA + NB + 1:nG] else NULL)
pvec <- function(p) c(p$theta, as.numeric(p$beta))
fit_pair <- function(rows, ages, lam, maxit_long = 300, maxit = 200, warm = NULL) {
  start <- if (!is.null(warm)) c(warm$theta, as.numeric(warm$beta), warm$mu) else rep(0, nA + NB + nG)
  oL <- fit(make_obj(rows, rep(1, length(rows)), lam = lam), start, maxit_long)
  pl <- unpack(oL$par, TRUE)
  oC <- fit(make_obj(rows, 0.5^(ages / H_FIX), prior = pl, k = K_FIX, lam = lam), pvec(pl), maxit)
  list(long = pl, cred = unpack(oC$par, FALSE), conv = c(oL$convergence, oC$convergence), lam = lam)
}
resid_for <- function(rows, p, lam) {
  ob <- make_obj(rows, rep(1, length(rows)), prior = p, k = 0, lam = lam)
  attr(ob(pvec(p)), "r")
}
hub_mean <- function(r) mean(ifelse(abs(r) <= DELTA, r^2 / 2, DELTA * (abs(r) - DELTA / 2)))
if (Sys.getenv("TM_STOP_BEFORE_HOLDOUT") == "1") stop_here <- TRUE else stop_here <- FALSE

if (!stop_here) {
# ---------------- holdout: how much stretch removes the consolidation bias ----------------
train <- d[age > HOLD_DAYS, ti]; hold <- d[age <= HOLD_DAYS, ti]
GS <- as.numeric(Sys.getenv("TM_GRID_SAMPLE", "0.3"))
if (GS < 1) train <- sort(sample(train, round(length(train) * GS)))
age_tr <- d$age[train] - HOLD_DAYS
say("holdout: %d training, %d holdout trades", length(train), length(hold))
sz <- long[ti %in% hold, .(nA = sum(n[side > 0]), nB = sum(n[side < 0])), by = ti][match(hold, ti)]
sz[, shape := paste0(pmin(nA, nB), "-for-", pmax(nA, nB))]
stretch <- function(p, s) list(theta = s * p$theta, beta = s * p$beta)   # v' = v^s, reference asset stays at 1
fp <- fit_pair(train, age_tr, 1)
S_GRID <- seq(1, 3, by = 0.05)
res <- rbindlist(lapply(S_GRID, function(s) {
  r <- resid_for(hold, stretch(fp$cred, s), 1)
  fm <- fifelse(sz$nA < sz$nB, r, fifelse(sz$nB < sz$nA, -r, NA_real_))   # < 0: fewer-asset side priced too low
  data.table(stretch = s, holdout_huber = hub_mean(r), holdout_mae = mean(abs(r)), holdout_pct_within_10pct = mean(abs(r) < log(1.1)),
             uneven_trades = sum(!is.na(fm)), consolidation_gap = mean(fm, na.rm = TRUE), shape = sz$shape, r = r, fm = fm)[
    , `:=`(shape_trades = .N, shape_gap = mean(fm, na.rm = TRUE), shape_mae = mean(abs(r))), by = shape]
}))
out(unique(res[, .(stretch, holdout_huber, holdout_mae, holdout_pct_within_10pct, uneven_trades, consolidation_gap)]), "holdout")
top_shapes <- res[stretch == 1, .N, by = shape][order(-N)][1:min(.N, 10), shape]
out(unique(res[shape %in% top_shapes, .(stretch, shape, trades = shape_trades, mean_log_gap_few_minus_many = shape_gap, mae = shape_mae)]), "holdout_by_shape")
g <- unique(res[, .(stretch, consolidation_gap)])
S_BEST <- if (all(g$consolidation_gap > 0)) 1 else if (all(g$consolidation_gap < 0)) max(S_GRID) else
  approx(g$consolidation_gap, g$stretch, xout = 0, ties = mean)$y
say("holdout gap at stretch 1: %+.4f; chosen stretch %.3f", g$consolidation_gap[1], S_BEST)

# ---------------- final fit on all trades, then stretch ----------------
fp <- fit_pair(d$ti, d$age, 1, maxit_long = 800, maxit = 400)
pc <- stretch(fp$cred, S_BEST)
M[, `:=`(theta = pc$theta, theta_unstretched = fp$cred$theta)]
assets <- merge(A, M[, .(model_asset, theta, theta_unstretched)], by = "model_asset", all.x = TRUE)[n_trades >= MIN_APPEAR]
out(assets[order(-theta), .(asset, name, pos, grp, pick_year, pick_tier, pick_round, n_trades,
                            theta = round(theta, 4), theta_unstretched = round(theta_unstretched, 4))], "assets")
out(data.table(group = rep(GROUPS, each = NK), covariate = rep(colnames(X), nG), beta = round(as.numeric(pc$beta), 4)), "beta")
out(data.table(type = TYPE, trades_used = nrow(d), H = H_FIX, k = K_FIX, ref = REF, lambda0 = LAMBDA0, stretch = S_BEST,
               converged_long = fp$conv[1], converged = fp$conv[2]), "meta")
say("done")
}
