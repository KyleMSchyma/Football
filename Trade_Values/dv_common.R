# =============================================================================
# Dynasty Value Model -- shared settings and helpers
#
# A player's dynasty value is priced like an actuarial life annuity:
#   value = sum over future seasons t of  v^(t-1) * S(t) * E[PAR+ in season t | still alive]
# S(t)  = chance the player is still a "living" startable asset in season t (survival models)
# PAR+  = PPR points above the replacement line (QB24 / RB24 / WR36 / TE12), floored at 0
# v     = 1 / (1 + i), the discount factor
# =============================================================================
suppressMessages({ library(dplyr); library(tidyr); library(survival); library(splines) })
select <- dplyr::select
mycols <- c(QB = "#D55E00", RB = "#009E73", WR = "#0072B2", TE = "#CC79A7")

POSITIONS <- c("QB", "RB", "WR", "TE")
STARTABLE <- c(QB = 24, RB = 24, WR = 36, TE = 12)   # Kyle's startable lines
H         <- 10                                       # seasons in the annuity
I_MAIN    <- 0.15                                     # main discount rate
I_ALT     <- c(0, 0.30)                               # rebuild / contend views
LAST_FULL <- 2025                                     # last complete season
CUR       <- 2026                                     # season in progress (scoring landmark)
TRAIN_LM  <- 2007:2017                                # landmark seasons used to fit
TEST_LM   <- 2018:2024                                # landmark seasons held out

# folder layout: Kyle's PC (Football2_Dynasty, raw cache in ../Football2/cache) or the repo (Dynasty_Model)
SHARED <- if (dir.exists("../WR_Model/cache")) "../WR_Model/cache" else "../Football2/cache"

# Draft capital buckets (UDFA = undrafted free agent)
draft_bucket <- function(rd) factor(ifelse(is.na(rd), "UDFA", ifelse(rd == 1, "R1", ifelse(rd == 2, "R2",
  ifelse(rd == 3, "R3", "R4-7")))), levels = c("R1", "R2", "R3", "R4-7", "UDFA"))

# Model features measured at the landmark season (everything known "today")
FEATS <- c("pos", "age", "exp", "draft", "par", "par_prev", "startable", "startable_prev",
           "n_startable", "ppg", "games_frac", "opp_pg", "par_rate", "par_best3")

# discrete-time hazard design: one row per player-landmark-season at risk
hz_formula <- event ~ ns(t, knots = c(2, 4), Boundary.knots = c(1, 18)) + pos + ns(age, 3) + pos:age + exp + draft + ns(par, 3) + par_prev +
  startable + startable_prev + n_startable + games_frac + opp_pg + pos:par + t:startable + t:age +
  ns(par_rate, 3) + ns(par_best3, 3)
# Tweedie production design: E[PAR+ in season s+t | alive]
pr_formula <- y ~ pos * ns(t, knots = c(2, 4), Boundary.knots = c(1, 18)) + ns(age_t, 3) + pos:age_t + exp + draft + ns(par, 3) + par_prev +
  startable + n_startable + ppg + games_frac + opp_pg + pos:par + t:par + t:ppg + t:startable +   # t: terms let a hot season fade further out
  ns(par_rate, 3) + ns(par_best3, 3)

aucf  <- function(y, p) if (length(unique(y)) < 2) NA else {
  r <- rank(p); n1 <- sum(y == 1); n0 <- sum(y == 0); (sum(r[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0) }
brier <- function(p, y) mean((p - y)^2)

# ---------------- prediction helpers shared by steps 3, 5, 6 ----------------
# S(t), t = 1..H, from the discrete-time hazard GLM: S(t) = prod_{k<=t} (1 - h(k))
S_glm <- function(fit, nd, HH = H) {
  g <- nd[rep(seq_len(nrow(nd)), each = HH), ]; g$t <- rep(1:HH, nrow(nd))
  h <- predict(fit, newdata = g, type = "response")
  h[g$t == 1 & (g$startable == 1 | g$exp == 0)] <- 0          # cannot die in season 1 (startable now, or rookie free pass)
  m <- matrix(1 - h, ncol = HH, byrow = TRUE); t(apply(m, 1, cumprod))
}
# S(t) from the survival forest. ranger reports S = exp(-Nelson-Aalen CHF), which overstates survival when
# one-season hazards are large, so CHF increments (d/n per season = discrete hazards) are turned into a product-limit curve.
S_rsf <- function(fit, nd, HH = H) {
  pr <- predict(fit, data = nd); tt <- pr$unique.death.times
  chf <- sapply(1:HH, function(k) if (any(tt <= k)) pr$chf[, max(which(tt <= k))] else rep(0, nrow(nd)))
  h <- pmin(pmax(cbind(chf[, 1], t(apply(chf, 1, diff))), 0), 1)
  t(apply(1 - h, 1, cumprod))
}
# E[PAR+ in season t | alive], t = 1..H, averaged over the Tweedie GLM and the random forest
M_prod <- function(pm, nd, HH = H) {
  g <- nd[rep(seq_len(nrow(nd)), each = HH), ]; g$t <- rep(1:HH, nrow(nd)); g$age_t <- g$age + g$t
  p <- (predict(pm$glm, newdata = g, type = "response") + predict(pm$rf, data = g)$predictions) / 2
  matrix(p, ncol = HH, byrow = TRUE)
}
# The annuity. offset = seasons already elapsed before the first season we value
# (0 for a 2026 landmark; 1 for a player valued from his 2025 season because he has barely played in 2026).
value_parts <- function(sm, pm, nd, i = I_MAIN, offset = 0) {
  HH <- H + max(offset)
  S <- (S_glm(sm$glm, nd, HH) + S_rsf(sm$rsf, nd, HH)) / 2
  M <- M_prod(pm, nd, HH)
  out <- lapply(seq_len(nrow(nd)), function(r) {
    k <- (offset[r] + 1):(offset[r] + H); s <- S[r, k]   # unconditional: 2026 is still unknown for these players
    s <- pmin(s, 1); m <- M[r, k]; v <- (1 / (1 + i))^(0:(H - 1))
    c(dvs = sum(v * s * m), dvs_0 = sum(s * m), dvs_30 = sum((1 / 1.3)^(0:(H - 1)) * s * m),
      win_now = sum(s[1:3] * m[1:3]), e_life = sum(s), S1 = s[1], S3 = s[3], S5 = s[5], par_next = m[1])
  })
  as.data.frame(do.call(rbind, out))
}
