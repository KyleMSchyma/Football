# =============================================================================
# Prospect-model prior for credible PPG (Kyle 2026-11-18, "Bühlmann-Straub prior swap")
#
# Today (dv_10): historical PPG is blended toward a "potential" prior = PPG ~ ns(log pick) + years in league,
# per position, fit on the 10 seasons before the snapshot season, weight g_h / (g_h + k2).
# Here the prior is replaced by the rookie models' tier probabilities:
#   pick     current prior (draft slot + years in league)
#   post     post-draft model only (P(top tier), P(top 2 tiers), P(any tier)), LOCO, + years in league
#   mixed    the live MIXED DRAFT MODEL probabilities (post-draft + faller bump), LOCO, + years in league
#   pick+mixed  both
#   pre+pick pre-draft model probabilities (college only) + draft slot
#   rolling  post-draft model, strict rolling-origin predictions (models trained on classes <= Y - 3); leak check
# Players with no prospect-model row (undrafted, drafted before 2010, rolling gaps) keep the pick prior.
# The prior's PPG calibration is a games-weighted regression fit on the 10 seasons before the snapshot season,
# exactly like the pick prior. History window: last 3 seasons (live) or last 5 seasons.
#
# Tests (all out of sample):
#   A  in-season: weeks 1-9 -> PPG in weeks 10-18, 2016-2025, k1/k2 refit leave-one-season-out
#   B  season ahead: credible PPG at season end -> next-season PPG through the dv_11 aging model,
#      rolling (fit on seasons < y, test season y + 1), 2016-2025
#   C  rest-of-season value Spearman (availability unchanged)
# Run from Trade_Values/ (or Football2_Dynasty/) with DATA pointing at the nflverse caches.
source("prospect_prior/pp_00_common.R")   # data, prospect probabilities, prior models, snapshot + credibility functions

SNAP <- list(); for (nh in c(3, 5)) SNAP[[as.character(nh)]] <- bind_rows(lapply(BT_YEARS, function(y) snapshot(y, nh)))
cat("snapshot rows (3 / 5 seasons):", sapply(SNAP, nrow), "\n")
SPECS <- expand.grid(v = names(VARS), nh = c(3, 5), stringsAsFactors = FALSE)
SPECS <- SPECS %>% filter(nh == 3 | v %in% c("pick", "mixed", "pick_mixed"))

A <- list(); KK <- list()
for (s in seq_len(nrow(SPECS))) { v <- SPECS$v[s]; nh <- SPECS$nh[s]; tag <- paste0(v, "_h", nh)
  d <- SNAP[[as.character(nh)]]
  d$prior <- NA_real_; d$used <- FALSE
  for (y in BT_YEARS) { i <- which(d$season == y); pr <- prior_ppg(y, d[i, ], v); d$prior[i] <- pr; d$used[i] <- attr(pr, "used") }
  d$cppg <- NA_real_
  for (ps in POSITIONS) { dp <- d %>% filter(pos == ps, n_ros >= 3)
    KK[[paste(tag, ps)]] <- tibble(variant = tag, pos = ps, k1 = fit_k(dp)[1], k2 = fit_k(dp)[2])        # all seasons (what would go live)
    for (y in BT_YEARS) { k <- fit_k(dp %>% filter(season != y)); i <- which(d$pos == ps & d$season == y)   # leave-one-season-out
      d$cppg[i] <- cred_ppg(d[i, ], k[1], k[2]) } }
  d$cavail <- NA_real_   # availability: identical for every variant (k3, k4 fit on all seasons as live)
  for (ps in POSITIONS) { i <- which(d$pos == ps); d2 <- d[i, ] %>% filter(n_cur >= 2)
    o <- optim(c(log(8), log(16)), function(q) { pr <- cred_avail(d2, exp(q[1]), exp(q[2])); sum(d2$tg_left * (d2$rate_ros - pr)^2) })
    d$cavail[i] <- cred_avail(d[i, ], exp(o$par[1]), exp(o$par[2])) }
  A[[tag]] <- d %>% mutate(variant = tag) %>% select(variant, season, player_id, name, pos, exp, draft_pick, n_cur, g_h, ppg_cur, prior, used, cppg, cavail, tg_left, n_ros, pts_ros, ppg_ros)
  cat("done", tag, "\n") }
A <- bind_rows(A); KK <- bind_rows(KK)
saveRDS(list(A = A, K = KK), file.path(OUT, "pp_A_insample.rds"))

# ---------- test B: season-end credible PPG -> next-season PPG (dv_11 aging model, rolling) ----------
age_ns <- function(a) ns(a, knots = c(25, 28, 31), Boundary.knots = c(21, 38))
season_end <- function(y, v, nh, K) {
  d <- seasP %>% filter(season == y, g >= 1) %>% left_join(hist_tab(y, nh), by = "player_id") %>% left_join(p, by = "player_id") %>%
    mutate(g_h = coalesce(g_h, 0), exp = pmax(0, y - coalesce(rookie_season, y)), lpick = log(coalesce(draft_pick, 262)),
           age = as.numeric(as.Date(paste0(y, "-09-01")) - birth_date) / 365.25, ppg = pts / g)
  d$prior <- prior_ppg(y, d, v); d$used <- attr(d$prior, "used")
  k <- K[match(d$pos, K$pos), ]
  hist <- ifelse(d$g_h > 0, d$g_h / (d$g_h + k$k2) * coalesce(d$ppg_h, 0) + k$k2 / (d$g_h + k$k2) * d$prior, d$prior)
  d$cppg <- d$g / (d$g + k$k1) * d$ppg + k$k1 / (d$g + k$k1) * hist
  nx <- seas %>% filter(season == y + 1) %>% transmute(player_id, g_next = g, ppg_next = pts / g)
  d %>% left_join(nx, by = "player_id") %>% filter(!is.na(age)) }
B <- list()
for (s in seq_len(nrow(SPECS))) { v <- SPECS$v[s]; nh <- SPECS$nh[s]; tag <- paste0(v, "_h", nh)
  K <- KK %>% filter(variant == tag)
  SE <- bind_rows(lapply(2009:2025, function(y) season_end(y, v, nh, K) %>% mutate(season = y)))
  for (y in 2015:2024) for (ps in POSITIONS) {               # fit on season-ends < y, predict season y + 1
    tr <- SE %>% filter(season < y, season >= y - 10, pos == ps, !is.na(ppg_next), g_next >= 4)
    te <- SE %>% filter(season == y, pos == ps, !is.na(ppg_next), g_next >= 4)
    m <- lm(ppg_next ~ cppg + age_ns(age) + factor(pmin(exp, 3)) + lpick:I(exp <= 2), data = tr, weights = g_next)
    m0 <- lm(ppg_next ~ cppg, data = tr, weights = g_next)
    B[[paste(tag, y, ps)]] <- te %>% transmute(variant = tag, season = y, player_id, pos, exp, draft_pick, used, prior, cppg, g, ppg, g_next, ppg_next,
      pred = predict(m, newdata = te), pred_raw = predict(m0, newdata = te)) } }
B <- bind_rows(B)
saveRDS(list(A = A, B = B, K = KK), file.path(OUT, "pp_results.rds"))
cat("saved\n")
