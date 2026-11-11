# =============================================================================
# League-customizable trade values (Kyle 2026-11-11): precompute every scoring preset for the Trade Values page
#
# Settings on the page: teams 8/10/12/14; 0.5 PPR or PPR; TE premium none/0.5/1.0; passing TD 4/5/6; superflex on/off;
# start 2-3 RB, 2-3 WR, 1-2 TE; 0-3 FLEX.
#
# Scoring changes points per game, so it needs the model refits (credibility k's, draft-capital potential, aging, staying in
# the league, availability). Every fit is per position and each scoring knob touches one position group only:
#   QB  -> passing TD points (4 / 5 / 6)                    3 variants
#   RB, WR -> points per catch (0.5 / 1)                    2 variants
#   TE  -> points per catch incl. premium (0.5 / 1 / 1.5 / 2)  4 variants
# so 4 model runs cover all 18 presets (2 x 3 x 3). QB catches are scored at full PPR and RB/WR passing TDs at 4 points in
# every preset (both are rounding error).
# Lineup settings are computed in the browser from these projections: replacement lines by filling every team's lineup
# (rep_lines in dv_10), then points over replacement x expected games, with the stop-loss upside for dynasty.
#
# Also builds the 2027 rookie pick profiles (template classes 2016-2025, projected from draft slot) and the backtests of
# the scoring presets and of several lineup settings. Writes dv_league_presets.rds (read by dv_12), dv_league_backtest.csv,
# dv_scoring_backtest.csv, dv_anchor_check.csv.
# =============================================================================
RUNS_ <- list(
  list(sc = list(ppr = 1,   te = 1,   ptd = 4), keys = c(QB = "p4", RB = "r1",   WR = "r1",   TE = "t1")),    # default, writes the usual CSVs
  list(sc = list(ppr = 0.5, te = 0.5, ptd = 5), keys = c(QB = "p5", RB = "r0.5", WR = "r0.5", TE = "t0.5")),
  list(sc = list(ppr = 1,   te = 1.5, ptd = 6), keys = c(QB = "p6", TE = "t1.5")),
  list(sc = list(ppr = 1,   te = 2,   ptd = 4), keys = c(TE = "t2")))
LG_TEST_ <- list(
  "12 teams, superflex, 2 RB 3 WR 1 TE, no flex (default)" = list(teams = 12, qb = 1, rb = 2, wr = 3, te = 1, flex = 0, sf = 1),
  "12 teams, 1 QB, 2 RB 3 WR 1 TE, 1 flex"                 = list(teams = 12, qb = 1, rb = 2, wr = 3, te = 1, flex = 1, sf = 0),
  "10 teams, 1 QB, 2 RB 2 WR 1 TE, 2 flex"                 = list(teams = 10, qb = 1, rb = 2, wr = 2, te = 1, flex = 2, sf = 0),
  "14 teams, superflex, 2 RB 3 WR 1 TE, 1 flex"            = list(teams = 14, qb = 1, rb = 2, wr = 3, te = 1, flex = 1, sf = 1),
  "8 teams, 1 QB, 2 RB 2 WR 1 TE, 1 flex"                  = list(teams = 8,  qb = 1, rb = 2, wr = 2, te = 1, flex = 1, sf = 0))
T0_ <- Sys.time(); OUT_ <- list(); SCBT_ <- list()

# ---------- rookie pick profiles: what a rookie drafted at each NFL slot projects to, for 2027-2030 ----------
rookie_profiles <- function() {
  pr_ <- readRDS(file.path(SHARED, "players_raw.rds")) %>%
    transmute(player_id = gsis_id, pos = ifelse(position == "FB", "RB", position), draft_year, draft_pick, birth_date = as.Date(birth_date)) %>%
    filter(pos %in% POSITIONS, !is.na(draft_pick), !is.na(draft_year))
  # rookie-season games (zero when he never plays), by position and draft slot
  rk <- pr_ %>% filter(draft_year %in% 2012:2025) %>%
    left_join(seas %>% select(player_id, season, g), by = c("player_id", "draft_year" = "season")) %>%
    mutate(g = coalesce(g, 0L), tg = ifelse(draft_year >= 2021, 17, 16), g = pmin(g, tg), lpick = log(draft_pick))
  gfit <- lapply(setNames(POSITIONS, POSITIONS), function(ps) glm(cbind(g, tg - g) ~ ns(lpick, 3), family = binomial, data = rk %>% filter(pos == ps)))
  # rookie-season PPG uncertainty: residual sd of the draft-capital potential fit, rookies only
  pf <- POT_CACHE[[as.character(CUR)]]; if (is.null(pf)) { invisible(potential_ppg(CUR, data.frame(pos = "QB", lpick = 1, exp = 0))); pf <- POT_CACHE[[as.character(CUR)]] }
  sdr <- sapply(POSITIONS, function(ps) { m <- pf[[ps]]; e0 <- m$model$`factor(exp)` == "0"
    sqrt(sum(m$weights[e0] * residuals(m)[e0]^2) / sum(m$weights[e0])) })
  tmpl <- pr_ %>% filter(draft_year %in% 2016:2025) %>% group_by(draft_year) %>% arrange(draft_pick, .by_group = TRUE) %>%
    slice_head(n = 60) %>% ungroup() %>%
    mutate(age = as.numeric(as.Date(paste0(draft_year, "-09-01")) - birth_date) / 365.25, lpick = log(draft_pick), exp = 0) %>%
    group_by(pos) %>% mutate(age = ifelse(is.na(age), median(age, na.rm = TRUE), age)) %>% ungroup()
  tmpl$mu1 <- potential_ppg(CUR, tmpl)
  tmpl$G1 <- NA_real_
  for (ps in POSITIONS) { i <- which(tmpl$pos == ps); tmpl$G1[i] <- 17 * predict(gfit[[ps]], tmpl[i, ], type = "response") }
  SG <- matrix(0, nrow(tmpl), 4); MU <- matrix(0, nrow(tmpl), 4); SG[, 1] <- tmpl$G1; MU[, 1] <- tmpl$mu1
  for (ps in POSITIONS) { i <- which(tmpl$pos == ps); if (!length(i)) next
    f <- F[[ps]]; x <- tmpl[i, ]; cp <- x$mu1; av <- x$G1 / 17; S <- rep(1, length(i))
    for (k in 1:3) {                                    # 2028-2030, from the rookie season (2027) forward
      nd <- data.frame(cppg = cp, age = x$age + k - 1, exp = k - 1, lpick = x$lpick, avail = av)
      S <- S * predict(f$act, nd, type = "response"); ppg_k <- predict(f$prod, nd); av_k <- predict(f$av, nd, type = "response")
      SG[i, k + 1] <- S * 17 * av_k; MU[i, k + 1] <- ppg_k; cp <- ppg_k; av <- av_k } }
  sdR <- lapply(setNames(POSITIONS, POSITIONS), function(ps) sqrt(sdr[ps]^2 + F[[ps]]$sig^2 * (0:3)))
  list(tmpl = tmpl %>% select(player_id, pos, draft_year, draft_pick, age), SG = SG, MU = MU, sdR = sdR)
}

for (I_ in seq_along(RUNS_)) {
  SC <- RUNS_[[I_]]$sc; NO_WRITE <- I_ > 1
  cat(sprintf("\n\n######## scoring run %d: %.1f per RB/WR catch, %.1f per TE catch, %d per passing TD ########\n", I_, SC$ppr, SC$te, SC$ptd))
  source("dv_11_dynasty_v4.R")
  keys <- RUNS_[[I_]]$keys
  # players: every 2026 player (the replacement pool needs them all); dynasty projection where age is known
  mi <- match(b26$player_id, d26$player_id)
  pl <- b26 %>% transmute(player_id, name, pos, team, age, games = n_cur, ppg = ppg_cur, pool = as.integer(n_cur >= MIN_G_REP),
                          cppg, G0 = tg_left * cavail, dp = p$draft_pick[match(player_id, p$player_id)])
  dy <- cbind(pr$G[mi, 2:5, drop = FALSE], pr$ppg[mi, 2:5, drop = FALSE])[, c(1, 5, 2, 6, 3, 7, 4, 8)]   # SG1, mu1, ..., SG4, mu4
  dy <- cbind(dy, S4 = pr$S[mi, 5])                                   # chance he is still playing in 2030
  dy[is.na(mi), ] <- NA
  rp <- rookie_profiles()
  sdk <- lapply(setNames(POSITIONS, POSITIONS), function(ps) c(sd0 = unname(setNames(m1$rmse_credibility, m1$pos)[ps]), sig = F[[ps]]$sig))
  OUT_[[I_]] <- list(keys = keys, pl = pl, dy = dy, rp = rp, sdk = sdk, chk = tibble(player_id = d26$player_id, dyn = pr$value),
                     chk_rd = tibble(player_id = b26$player_id, rd = b26$value))
  SCBT_[[I_]] <- bind_rows(
    m3 %>% transmute(pos, test = "redraft value (weeks 10-18)", n, spearman_model, spearman_naive),
    res %>% filter(group %in% POSITIONS) %>% transmute(pos = group, test = "dynasty value (5 seasons)", n, spearman_model = spearman_v4, spearman_naive)) %>%
    filter(pos %in% names(keys)) %>% mutate(key = keys[pos], .before = 1)
  # lineup-setting backtest (default scoring only): same tests with each league's replacement lines
  if (I_ == 1) {
    LGBT_ <- bind_rows(lapply(names(LG_TEST_), function(nm) { lg <- LG_TEST_[[nm]]
      rv <- bind_rows(lapply(BT_YEARS, function(y) value_board(bt %>% filter(season == y), lg))) %>% filter(n_cur >= 3) %>%
        mutate(actual = pts_ros - rep_ppg * n_ros, naive = (ppg_cur - rep_ppg) * tg_left)
      bd <- bt_dyn(lg)
      tibble(setting = nm,
             redraft_spearman_model = cor(rv$value, rv$actual, method = "spearman"), redraft_spearman_naive = cor(rv$naive, rv$actual, method = "spearman"),
             dynasty_spearman_model = cor(bd$pred, bd$actual, method = "spearman"), dynasty_spearman_naive = cor(bd$naive, bd$actual, method = "spearman"),
             dynasty_pred_over_actual = sum(bd$pred) / sum(bd$actual)) }))
    cat("\nLINEUP-SETTING BACKTEST (default scoring):\n"); print(as.data.frame(LGBT_ %>% mutate(across(where(is.numeric), ~ round(.x, 3)))))
    REP_CHECK_ <- rep_lines(b26)   # must equal the QB24 / RB24 / WR36 / TE12 lines
    cat("\ndefault league via rep_lines():\n"); print(REP_CHECK_)
    stopifnot(isTRUE(all.equal(unname(REP_CHECK_$rep_ppg), unname(b26$rep_ppg[match(POSITIONS, b26$pos)]))))
  }
}

# ---------- assemble: one row per player, values per scoring key ----------
ids <- unique(unlist(lapply(OUT_, function(o) o$pl$player_id)))
base <- OUT_[[1]]$pl %>% select(player_id, name, pos, team, age, games, ppg, pool, dp)
rd <- list(); dyl <- list(); sdk <- list(); pk <- list(); sdR <- list()
for (o in OUT_) for (ps in names(o$keys)) { key <- paste0(ps, "_", o$keys[[ps]])   # e.g. RB_r1: RB and WR share a scoring but not a fit
  i <- which(o$pl$pos == ps)
  rd[[key]]  <- setNames(lapply(i, function(j) c(o$pl$ppg[j], o$pl$cppg[j], o$pl$G0[j])), o$pl$player_id[i])   # 2026 PPG, credible PPG, exp. games left
  dyl[[key]] <- setNames(lapply(i, function(j) o$dy[j, ]), o$pl$player_id[i])
  sdk[[key]] <- o$sdk[[ps]]
  ri <- which(o$rp$tmpl$pos == ps)
  pk[[key]]  <- lapply(ri, function(j) c(o$rp$SG[j, 1], o$rp$MU[j, 1], o$rp$SG[j, 2], o$rp$MU[j, 2], o$rp$SG[j, 3], o$rp$MU[j, 3], o$rp$SG[j, 4], o$rp$MU[j, 4]))
  names(pk[[key]]) <- paste(o$rp$tmpl$draft_year[ri], o$rp$tmpl$draft_pick[ri])
  sdR[[key]] <- o$rp$sdR[[ps]] }
# after Week 18 there are no games left: keep the redraft numbers from the last week that had games
rd_frozen <- NULL
if (max(sapply(unlist(rd, recursive = FALSE), `[`, 3)) <= 0 && file.exists("dv_league_presets.rds")) { old <- readRDS("dv_league_presets.rds")
  rd_frozen <- if (!is.null(old$rd_frozen)) old$rd_frozen else old$rd
  cat("\nregular season over: the redraft sheet keeps the projections from the last week with games left\n") }
presets <- list(base = base, rd = rd, rd_frozen = rd_frozen, dy = dyl, sdk = sdk, picks = list(tmpl = OUT_[[1]]$rp$tmpl %>% select(pos, draft_year, draft_pick), p = pk, sdR = sdR),
                v = 1 / (1 + I_MAIN), week = CUT26, made = Sys.time())
saveRDS(presets, "dv_league_presets.rds")
write.csv(LGBT_, "dv_league_backtest.csv", row.names = FALSE)
SCB <- bind_rows(SCBT_) %>% mutate(across(where(is.numeric), ~ round(.x, 3)))
write.csv(SCB, "dv_scoring_backtest.csv", row.names = FALSE)
cat("\nSCORING-PRESET BACKTEST (default lineup lines):\n"); print(as.data.frame(SCB))

# ---------- the page's math, in R: value of every player and pick for a league setting ----------
stoploss <- function(mu, r, s) { z <- (mu - r) / s; s * dnorm(z) + (mu - r) * pnorm(z) }
league_values <- function(P, lg, ppr = 1, tep = 0, ptd = 4) {
  key <- c(QB = paste0("QB_p", ptd), RB = paste0("RB_r", ppr), WR = paste0("WR_r", ppr), TE = paste0("TE_t", ppr + tep))
  b <- P$base; k <- key[b$pos]
  g_ <- function(kk, id, j) { x <- P$rd[[kk]][[id]]; if (is.null(x)) NA_real_ else x[j + 1] }   # skip the 2026 PPG
  b$cppg <- mapply(g_, k, b$player_id, 1); b$G0 <- mapply(g_, k, b$player_id, 2)
  b$n_cur <- ifelse(b$pool == 1, 99, 0)
  rp <- rep_lines(b, lg); b$rep <- rp$rep_ppg[match(b$pos, rp$pos)]
  b$redraft <- (b$cppg - b$rep) * b$G0
  b$dynasty <- sapply(seq_len(nrow(b)), function(j) { x <- P$dy[[k[j]]][[b$player_id[j]]]; if (is.null(x) || anyNA(x)) return(NA)
    s <- P$sdk[[k[j]]]; sum(P$v^(0:4) * c(b$G0[j], x[c(1, 3, 5, 7)]) * stoploss(c(b$cppg[j], x[c(2, 4, 6, 8)]), b$rep[j], c(s[1], s[2] * sqrt(1:4)))) })
  tm <- P$picks$tmpl; tk <- key[tm$pos]
  tm$val <- sapply(seq_len(nrow(tm)), function(j) { x <- P$picks$p[[tk[j]]][[paste(tm$draft_year[j], tm$draft_pick[j])]]
    sum(P$v^(1:4) * x[c(1, 3, 5, 7)] * stoploss(x[c(2, 4, 6, 8)], rp$rep_ppg[match(tm$pos[j], rp$pos)], P$picks$sdR[[tk[j]]])) })
  slots <- tm %>% group_by(draft_year) %>% arrange(desc(val), .by_group = TRUE) %>% mutate(slot = row_number()) %>% group_by(slot) %>% summarise(val = mean(val))
  list(players = b, slots = slots, rep = rp)
}
lv <- league_values(presets, LG_DEFAULT)
c1 <- OUT_[[1]]$chk; c2 <- OUT_[[1]]$chk_rd
cat("\npage math vs dv_10 / dv_11 (default league), max abs difference: dynasty",
    signif(max(abs(lv$players$dynasty[match(c1$player_id, lv$players$player_id)] - c1$dyn)), 3), " redraft",
    signif(max(abs(lv$players$redraft[match(c2$player_id, lv$players$player_id)] - c2$rd)), 3), "\n")

# anchor check (Kyle's trade anchors, dv_trade_anchors.csv): value of rank 1 vs the two-player package
anc <- read.csv("dv_trade_anchors.csv")
AC <- bind_rows(lapply(names(LG_TEST_), function(nm) { L <- league_values(presets, LG_TEST_[[nm]])
  bind_rows(lapply(c("redraft", "dynasty"), function(sh) { v <- sort(L$players[[sh]], decreasing = TRUE)
    anc %>% mutate(setting = nm, sheet = sh, get_value = v[get_rank], give_value = v[give_rank_1] + v[give_rank_2], ratio = round(give_value / get_value, 2)) })) }))
write.csv(AC, "dv_anchor_check.csv", row.names = FALSE)
cat("\nANCHOR CHECK (ratio = package / single player; Kyle's anchors say about 1.0):\n"); print(as.data.frame(AC %>% select(setting, sheet, get_rank, give_rank_1, give_rank_2, ratio)))
n12 <- 12; s <- lv$slots$val; top <- max(lv$players$dynasty, na.rm = TRUE)
cat("\ndefault league, 2027 rookie pick values (100k scale): \n")
for (r in 1:3) { sl <- (r - 1) * n12 + 1:n12; th <- split(sl, rep(1:3, each = 4))
  cat(sprintf("  round %d  early %6.0f  mid %6.0f  late %6.0f\n", r, 1e5 * mean(s[th[[1]]]) / top, 1e5 * mean(s[th[[2]]]) / top, 1e5 * mean(s[th[[3]]]) / top)) }
cat("\nelapsed:", round(as.numeric(difftime(Sys.time(), T0_, units = "mins")), 1), "min\n")
