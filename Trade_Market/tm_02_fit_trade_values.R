# tm_02_fit_trade_values.R
# "Trade" value method, step 2: fit trade-implied asset values from real trades
# (Dynasty Daddy Trade Database pull, tm_01). Fully separate from the model-based values.
#
# Model (per league type):
#   value of asset a in a league with settings x:  v = exp(theta_a + x . beta_g(a))
#     x = (SF-1, fullPPR-1, TEprem, (teams-12)/2, starters-10), so theta_a is the value at the
#     site default league (12 teams, SF, full PPR, no TEP, 10 starters); g = QB/RB/WR/TE/PICK/OTH.
#   each trade is assumed roughly fair:  r = log(sum v side A) - log(sum v side B) ~ 0
#   loss = sum_t w_t * Huber(r_t)  (+ penalties below)
#   Long-run fit: w = 1, theta shrunk to a position mean (lambda0); "2027mid1stpi" pinned at 0.
#   Credibility fit: w = 0.5^(age/H) (recent trades count more) and theta shrunk to the
#     long-run theta with weight k: an asset with recent weighted info I gets about
#     Z = I/(I+k) of its recent price (Buhlmann-style credibility).
#   H and k picked on a time holdout (last HOLD_DAYS days), compared with long-run and
#     last-30-days-only fits. Also checks a consolidation exponent alpha (sum of v^alpha).
#
# Outputs (aggregates only, NO league ids, NO raw trades) go to research/dd_trades/out/<type>_*.csv
# Run:  Rscript tm_02_fit_trade_values.R dynasty     and     Rscript tm_02_fit_trade_values.R redraft
# Optional env TM_ROOT overrides the data folder; TM_SAMPLE (0-1) subsamples trades for a quick test.

suppressPackageStartupMessages({ library(data.table) })
set.seed(2026)
args <- commandArgs(TRUE)
TYPE <- if (length(args)) tolower(args[1]) else "dynasty"
ROOT <- Sys.getenv("TM_ROOT", file.path(Sys.getenv("USERPROFILE"), "Documents", "R Studio", "Football2", "research", "dd_trades"))
RAW  <- file.path(ROOT, "raw"); OUTD <- file.path(ROOT, "out")
dir.create(OUTD, showWarnings = FALSE, recursive = TRUE)
out  <- function(x, name) fwrite(x, file.path(OUTD, sprintf("%s_%s.csv", TYPE, name)))
say  <- function(...) message(format(Sys.time(), "%H:%M:%S "), sprintf(...))

HOLD_DAYS <- 14; MIN_APPEAR <- 25; DELTA <- 0.7; LAMBDA0 <- 2
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
out(d[, .N, by = .(teams, sf, ppr, tep, starters)][order(-N)], "format_mix")
out(d[, .N, by = .(week = as.Date(cut(as.Date(when), "week")))][order(week)], "weekly_volume")
d[, league_id := NULL]   # never needed again; never written

# ---------------- assets ----------------
long <- rbind(d[, .(asset = unlist(strsplit(sidea, "|", fixed = TRUE)), side = 1L), by = transaction_id],
              d[, .(asset = unlist(strsplit(sideb, "|", fixed = TRUE)), side = -1L), by = transaction_id])
long <- long[asset != ""]

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

# ---------------- objective ----------------
# par = theta (nA), beta (NK x nG), mu (nG, long fit only), log_alpha (optional)
make_obj <- function(rows, w, prior_theta = NULL, prior_beta = NULL, k = 0, fit_alpha = FALSE) {
  L <- long[ti %in% rows]
  tmap <- match(L$ti, rows)      # 1..length(rows)
  ai <- L$ai; gi <- L$gi; sd <- L$side; cn <- L$n
  Xr <- X[rows, , drop = FALSE]
  Xe <- lapply(seq_len(NK), function(j) Xr[tmap, j])
  nt <- length(rows)
  function(par) {
    th <- par[1:nA]; B <- matrix(par[nA + 1:(NK * nG)], NK, nG)
    off <- nA + NK * nG
    mu <- if (is.null(prior_theta)) par[off + 1:nG] else NULL
    if (is.null(prior_theta)) off <- off + nG
    al <- if (fit_alpha) exp(par[off + 1]) else 1
    eta <- th[ai]; for (j in 1:NK) eta <- eta + Xe[[j]] * B[j, gi]
    e <- cn * exp(al * eta)
    SA <- rowsum(e * (sd > 0), tmap, reorder = TRUE)[, 1]
    SB <- rowsum(e * (sd < 0), tmap, reorder = TRUE)[, 1]
    r <- (log(SA) - log(SB)) / al
    hub <- ifelse(abs(r) <= DELTA, r^2 / 2, DELTA * (abs(r) - DELTA / 2))
    f <- sum(w * hub)
    psi <- w * pmax(-DELTA, pmin(DELTA, r)) / al
    S <- ifelse(sd > 0, SA[tmap], SB[tmap])
    de <- psi[tmap] * sd * al * e / S                 # d loss / d eta per entry
    gth <- numeric(nA); gs <- rowsum(de, ai); gth[as.integer(rownames(gs))] <- gs[, 1]
    gB <- matrix(0, NK, nG)
    for (j in 1:NK) { gg <- rowsum(de * Xe[[j]], gi); gB[j, as.integer(rownames(gg))] <- gg[, 1] }
    if (is.null(prior_theta)) {
      dev <- th - mu[M$gi]
      f <- f + LAMBDA0 * sum(dev^2) + 0.5 * sum(B^2)
      gth <- gth + 2 * LAMBDA0 * dev; gB <- gB + B
      gmu <- -2 * LAMBDA0 * as.numeric(tapply(dev, factor(M$gi, levels = 1:nG), sum)); gmu[is.na(gmu)] <- 0
      g <- c(gth, as.numeric(gB), gmu)
    } else {
      dev <- th - prior_theta; dB <- B - prior_beta
      f <- f + k * sum(dev^2) + k * sum(dB^2)
      gth <- gth + 2 * k * dev; gB <- gB + 2 * k * dB
      g <- c(gth, as.numeric(gB))
    }
    if (fit_alpha) {   # numeric derivative for alpha is fine (one parameter); filled by caller
      g <- c(g, 0)
    }
    g[iref] <- 0
    attr(f, "gradient") <- g
    attr(f, "r") <- r
    f
  }
}
fit <- function(obj, start, maxit = 150) {
  last_p <- NULL; last_v <- NULL
  ev <- function(p) { p[iref] <- 0; if (is.null(last_p) || !identical(p, last_p)) { last_v <<- obj(p); last_p <<- p }; last_v }
  fn <- function(p) as.numeric(ev(p))
  gr <- function(p) attr(ev(p), "gradient")
  o <- optim(start, fn, gr, method = "L-BFGS-B", control = list(maxit = maxit, factr = 1e8))
  o$par[iref] <- 0; o
}
start_long <- c(rep(0, nA), rep(0, NK * nG), rep(0, nG))
residuals_for <- function(rows, par_theta, par_beta, alpha = 1) {
  ob <- make_obj(rows, rep(1, length(rows)), prior_theta = par_theta, prior_beta = par_beta, k = 0)
  attr(ob(c(par_theta, as.numeric(par_beta))), "r") * 1
}
hub_mean <- function(r) mean(ifelse(abs(r) <= DELTA, r^2 / 2, DELTA * (abs(r) - DELTA / 2)))

# ---------------- holdout: choose H and k ----------------
cut_age <- HOLD_DAYS
train <- d[age > cut_age, ti]; hold <- d[age <= cut_age, ti]
GS <- as.numeric(Sys.getenv("TM_GRID_SAMPLE", "0.3"))   # training subsample for the H/k grid (speed)
if (GS < 1) train <- sort(sample(train, round(length(train) * GS)))
age_tr <- d$age[train] - cut_age
say("holdout: %d training trades, %d holdout trades (last %d days)", length(train), length(hold), HOLD_DAYS)
oL <- fit(make_obj(train, rep(1, length(train))), start_long)
thL <- oL$par[1:nA]; BL <- matrix(oL$par[nA + 1:(NK * nG)], NK, nG)
val <- list()
rL <- residuals_for(hold, thL, BL)
val[[1]] <- data.table(model = "long-run (all trades equal)", H = Inf, k = NA, holdout_huber = hub_mean(rL), holdout_mae = mean(abs(rL)), holdout_pct_within_10pct = mean(abs(rL) < log(1.1)))
w30 <- as.numeric(age_tr <= 30)
o30 <- fit(make_obj(train[w30 > 0], rep(1, sum(w30 > 0))), start_long)
r30 <- residuals_for(hold, o30$par[1:nA], matrix(o30$par[nA + 1:(NK * nG)], NK, nG))
val[[2]] <- data.table(model = "last 30 days only", H = 30, k = NA, holdout_huber = hub_mean(r30), holdout_mae = mean(abs(r30)), holdout_pct_within_10pct = mean(abs(r30) < log(1.1)))
for (H in H_GRID) for (k in K_GRID) {
  w <- 0.5^(age_tr / H)
  o <- fit(make_obj(train, w, prior_theta = thL, prior_beta = BL, k = k), c(thL, as.numeric(BL)))
  rr <- residuals_for(hold, o$par[1:nA], matrix(o$par[nA + 1:(NK * nG)], NK, nG))
  val[[length(val) + 1]] <- data.table(model = "credibility (recency-weighted, shrunk to long-run)", H = H, k = k,
                                       holdout_huber = hub_mean(rr), holdout_mae = mean(abs(rr)), holdout_pct_within_10pct = mean(abs(rr) < log(1.1)))
  say("H=%d k=%g holdout MAE %.4f", H, k, mean(abs(rr)))
}
val <- rbindlist(val); out(val, "holdout_grid")
best <- val[!is.na(k)][which.min(holdout_huber)]
H_BEST <- best$H; K_BEST <- best$k
say("best: H=%g k=%g (long-run MAE %.4f, best MAE %.4f)", H_BEST, K_BEST, val$holdout_mae[1], best$holdout_mae)

# holdout residual by trade shape (consolidation check), using the best model's training fit
w <- 0.5^(age_tr / H_BEST)
oB <- fit(make_obj(train, w, prior_theta = thL, prior_beta = BL, k = K_BEST), c(thL, as.numeric(BL)))
rB <- residuals_for(hold, oB$par[1:nA], matrix(oB$par[nA + 1:(NK * nG)], NK, nG))
sz <- long[ti %in% hold, .(nA = sum(n[side > 0]), nB = sum(n[side < 0])), by = ti]
sz <- sz[match(hold, ti)]
sz[, r := rB]
# orient so "few" is the side with fewer assets; positive r_few = few side was priced above model
sz[, few_minus_many := fifelse(nA < nB, r, fifelse(nB < nA, -r, NA_real_))]
sz[, shape := paste0(pmin(nA, nB), "-for-", pmax(nA, nB))]
out(sz[, .(trades = .N, mean_log_gap_few_minus_many = mean(few_minus_many, na.rm = TRUE), mae = mean(abs(r))), by = shape][order(-trades)][1:min(.N, 12)], "holdout_by_shape")
fwrite(data.table(r = round(rB, 4), shape = sz$shape)[sample(.N, min(.N, 50000))], file.path(OUTD, sprintf("%s_holdout_residual_sample.csv", TYPE)))

# ---------------- final fit on all trades ----------------
all <- d$ti
oF_L <- fit(make_obj(all, rep(1, length(all))), c(thL, as.numeric(BL), rep(0, nG)), maxit = 800)
thFL <- oF_L$par[1:nA]; BFL <- matrix(oF_L$par[nA + 1:(NK * nG)], NK, nG)
wF <- 0.5^(d$age / H_BEST)
oF <- fit(make_obj(all, wF, prior_theta = thFL, prior_beta = BFL, k = K_BEST), c(thFL, as.numeric(BFL)), maxit = 400)
thF <- oF$par[1:nA]; BF <- matrix(oF$par[nA + 1:(NK * nG)], NK, nG)

# credibility weight per asset: weighted appearances (I) and Z = I/(I+k)
info <- long[, .(I = sum(wF[ti] * n)), by = ai]
M <- merge(M, info, by = "ai", all.x = TRUE); M[is.na(I), I := 0]; setorder(M, ai)
M[, `:=`(theta_long = thFL, theta = thF, Z = I / (I + K_BEST))]
recent30 <- long[d$age[ti] <= 30, .(trades_last30 = uniqueN(ti)), by = ai]
M <- merge(M, recent30, by = "ai", all.x = TRUE); M[is.na(trades_last30), trades_last30 := 0L]

assets <- merge(A, M[, .(model_asset, theta_long, theta, I, Z, trades_last30)], by = "model_asset", all.x = TRUE)
assets <- assets[n_trades >= MIN_APPEAR]
out(assets[order(-theta), .(asset, name, pos, grp, pick_year, pick_tier, pick_round, n_trades, trades_last30,
                            weighted_info = round(I, 1), Z = round(Z, 3), theta_long = round(theta_long, 4), theta = round(theta, 4))], "assets")
beta <- data.table(group = rep(GROUPS, each = NK), covariate = rep(colnames(X), nG),
                   beta_long = round(as.numeric(BFL), 4), beta = round(as.numeric(BF), 4))
out(beta, "beta")
out(data.table(type = TYPE, trades_used = nrow(d), first = min(d$when), last = tmax, H = H_BEST, k = K_BEST,
               ref = REF, delta = DELTA, min_appear = MIN_APPEAR, converged_long = oF_L$convergence, converged = oF$convergence), "meta")

# value-over-time snapshots for the top assets: refit monthly with data up to each month end
snaps <- seq(as.Date(cut(as.Date(min(d$when)) + 31, "month")), as.Date(tmax), by = "month")
top <- assets[order(-theta)][1:min(60, .N), model_asset]
ser <- list()
for (s in as.list(snaps)) {
  rows <- d[as.Date(when) < s, ti]; if (length(rows) < 20000) next
  ag <- as.numeric(difftime(as.POSIXct(s), d$when[rows], units = "days"))
  oS <- fit(make_obj(rows, 0.5^(ag / H_BEST), prior_theta = thFL, prior_beta = BFL, k = K_BEST), c(thFL, as.numeric(BFL)), maxit = 200)
  ser[[length(ser) + 1]] <- data.table(asof = s, model_asset = M$model_asset, theta = oS$par[1:nA])[model_asset %in% top]
  say("snapshot %s done", format(s))
}
ser[[length(ser) + 1]] <- data.table(asof = as.Date(tmax), model_asset = M$model_asset, theta = thF)[model_asset %in% top]
ser <- merge(rbindlist(ser), A[, .(model_asset = asset, name, grp)], by = "model_asset")
out(ser[, .(asof, asset = model_asset, name, grp, theta = round(theta, 4))], "value_over_time")
say("done")
