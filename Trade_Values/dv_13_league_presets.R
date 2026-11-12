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
# Also builds the 2027 rookie pick values from the pre-draft model (no draft capital) and the backtests of
# the scoring presets and of several lineup settings. Writes dv_league_presets.rds (read by dv_12), dv_league_backtest.csv,
# dv_scoring_backtest.csv, dv_anchor_check.csv.
# =============================================================================
# First-down bonus (Kyle 2026-11-12): 0 / 0.25 / 0.5 / 0.75 / 1 per rushing or receiving first down, set per position.
# Per-position scoring variants: QB 3 TD x 5 FD = 15, RB / WR 2 PPR x 5 FD = 10, TE 4 catch values x 5 FD = 20, so 20 runs.
# Keys look like QB_p4f0, RB_r1f0.25, TE_t1.5f1. Run 1 is the default (full PPR, no premium, 4-pt TD, no FD bonus).
FD_ <- c(0, 0.25, 0.5, 0.75, 1)
qbv <- expand.grid(fd = FD_, ptd = c(4, 5, 6)); rwv <- expand.grid(fd = FD_, ppr = c(1, 0.5)); tev <- expand.grid(fd = FD_, te = c(1, 0.5, 1.5, 2))
RUNS_ <- lapply(1:20, function(i) {
  q <- qbv[min(i, 15), ]; r <- rwv[min(i, 10), ]; t <- tev[i, ]
  keys <- c(QB = paste0("p", q$ptd, "f", q$fd), RB = paste0("r", r$ppr, "f", r$fd), WR = paste0("r", r$ppr, "f", r$fd), TE = paste0("t", t$te, "f", t$fd))
  keys <- keys[c(if (i <= 15) "QB", if (i <= 10) c("RB", "WR"), "TE")]      # later runs only add the positions with more variants
  list(sc = list(ppr = r$ppr, te = t$te, ptd = q$ptd, fd = c(QB = q$fd, RB = r$fd, WR = r$fd, TE = t$fd)), keys = keys) })
LG_TEST_ <- list(
  "12 teams, superflex, 2 RB 3 WR 1 TE, no flex (default)" = list(teams = 12, qb = 1, rb = 2, wr = 3, te = 1, flex = 0, sf = 1),
  "12 teams, 1 QB, 2 RB 3 WR 1 TE, 1 flex"                 = list(teams = 12, qb = 1, rb = 2, wr = 3, te = 1, flex = 1, sf = 0),
  "10 teams, 1 QB, 2 RB 2 WR 1 TE, 2 flex"                 = list(teams = 10, qb = 1, rb = 2, wr = 2, te = 1, flex = 2, sf = 0),
  "14 teams, superflex, 2 RB 3 WR 1 TE, 1 flex"            = list(teams = 14, qb = 1, rb = 2, wr = 3, te = 1, flex = 1, sf = 1),
  "8 teams, 1 QB, 2 RB 2 WR 1 TE, 1 flex"                  = list(teams = 8,  qb = 1, rb = 2, wr = 2, te = 1, flex = 1, sf = 0))
T0_ <- Sys.time(); OUT_ <- list(); SCBT_ <- list()

# ---------- 2027 rookie picks (Kyle 2026-11-12: mocked players from the post-draft model with the mock pick, the rest pre-draft) ----------
# Each 2027 prospect on the pre-draft board has P(tier 1), P(tier 1-2), P(any tier) for his first three NFL seasons
# (QB/RB tiers = top 8 / 16 / 24, TE = top 6 / 12 / 18 since 2026-11-12, WR = top 12 / 24 / 36; the per-tier calibration below
# is read from pd_player_grades.csv nfl_tier, so it follows whatever cutoffs pd_common.R TIERS sets). Tier outcomes are turned into points with what past drafted
# players in that tier actually did (classes 2010-2022, seasons 1-4: games per 17, PPG, PPG spread), so
#   value = sum over tiers of P(tier) x sum_{k=1..4} v^k x games_tier,k x E[(PPG_tier,k + age adj_k - replacement)+]
# Age adjustment: the aging model's age curve, his age vs the average rookie's age at his position, applied season by season.
# Age = 18.6 + years out of high school (college data has no birth dates). Every prospect is assumed to declare.
# The page ranks the prospects for the chosen league: pick 1.01 = the best value, 1.02 the second, and so on.
PD_DIR <- "../Football2_PreDraft"; MOCK_DIR <- "../Football2_PostDraft"
prospect_profiles <- function() {
  gr <- read.csv(file.path(PD_DIR, "pd_player_grades.csv"), stringsAsFactors = FALSE)
  pr_ <- readRDS(file.path(SHARED, "players_raw.rds")) %>%
    transmute(player_id = gsis_id, pos = ifelse(position == "FB", "RB", position), draft_year, draft_pick, birth_date = as.Date(birth_date)) %>%
    filter(pos %in% POSITIONS, !is.na(draft_pick))
  h <- gr %>% filter(status == "drafted", class %in% 2010:2022, !is.na(nfl_tier), !is.na(pick)) %>%
    transmute(pos = position, class, pick, tier = pmin(nfl_tier, 4)) %>%
    inner_join(pr_, by = c("pos", "class" = "draft_year", "pick" = "draft_pick")) %>%
    mutate(age0 = as.numeric(as.Date(paste0(class, "-09-01")) - birth_date) / 365.25)
  hk <- bind_rows(lapply(1:4, function(k) h %>% mutate(k = k, season = class + k - 1))) %>%
    left_join(seas %>% select(player_id, season, g, pts, tg_season), by = c("player_id", "season")) %>%
    mutate(g = coalesce(g, 0L), pts = coalesce(pts, 0), tg = coalesce(tg_season, ifelse(season >= 2021, 17L, 16L)), g17 = pmin(g / tg, 1) * 17)
  cal <- hk %>% group_by(pos, tier, k) %>%
    summarise(n = n(), G = mean(g17), mu = if (sum(g) > 0) sum(pts) / sum(g) else 0,
              sd = if (sum(g > 0) > 2) sqrt(sum(g[g > 0] * (pts[g > 0] / g[g > 0] - sum(pts) / sum(g))^2) / sum(g)) else NA_real_, .groups = "drop") %>%
    group_by(pos, k) %>% mutate(sd = ifelse(is.na(sd) | sd < 1, max(sd, na.rm = TRUE), sd)) %>% ungroup() %>% arrange(pos, tier, k)
  a_ref <- h %>% group_by(pos) %>% summarise(a = mean(age0, na.rm = TRUE))
  agef <- function(ps, a) predict(F[[ps]]$prod, data.frame(cppg = 0, age = a, exp = 0, lpick = 0))   # only the age curve matters (differences)
  pp <- gr %>% filter(class == 2027) %>%
    transmute(name, pos = position, college, age = 18.6 + yrs_out_of_hs, score, grade,
              P1 = p_top, P2 = p_top2 - p_top, P3 = p_any - p_top2, P4 = 1 - p_any, source = "pre-draft")
  # Kyle 2026-11-12: players in the mock draft are priced from the POST-draft model with the mock pick as draft capital
  # (pd_09_mock_2027.R output, its age estimate too); everyone else keeps the pre-draft probabilities above.
  mk_file <- file.path(MOCK_DIR, "pd_post_2027_mock_grades.csv")
  if (file.exists(mk_file)) {
    nm <- function(x) gsub("[^a-z]", "", tolower(sub(" (jr|sr|ii|iii|iv)\\.?$", "", x, ignore.case = TRUE)))
    mk <- read.csv(mk_file, stringsAsFactors = FALSE) %>%
      transmute(name = board_name, pos = position, college = board_school, age = age_est, score = post_score, grade = post_grade,
                P1 = p_top, P2 = p_top2 - p_top, P3 = p_any - p_top2, P4 = 1 - p_any, source = paste0("post-draft, mock pick ", round, ".", pick))
    hit <- paste(nm(pp$name), pp$pos) %in% paste(nm(mk$name), mk$pos)
    cat(sprintf("\n2027 picks: %d mocked players priced post-draft (%d matched to the pre-draft board), %d priced pre-draft\n",
                nrow(mk), sum(hit), sum(!hit)))
    pp <- bind_rows(mk, pp[!hit, ])
  }
  D <- t(sapply(seq_len(nrow(pp)), function(i) { ps <- pp$pos[i]; a0 <- a_ref$a[a_ref$pos == ps]
    d <- sapply(2:4, function(k) agef(ps, pp$age[i] + k - 2) - agef(ps, a0 + k - 2)); c(0, cumsum(d)) }))
  list(cal = cal, pp = pp, D = D, a_ref = a_ref)
}

for (I_ in seq_along(RUNS_)) {
  SC <- RUNS_[[I_]]$sc; NO_WRITE <- I_ > 1
  cat(sprintf("\n\n######## scoring run %d: %.1f per RB/WR catch, %.1f per TE catch, %d per passing TD, first-down bonus %s ########\n", I_, SC$ppr, SC$te, SC$ptd,
              paste(names(SC$fd), SC$fd, collapse = " ")))
  source("dv_11_dynasty_v4.R")
  keys <- RUNS_[[I_]]$keys
  # players: every 2026 player (the replacement pool needs them all); dynasty projection where age is known
  mi <- match(b26$player_id, d26$player_id)
  pl <- b26 %>% transmute(player_id, name, pos, team, age, games = n_cur, ppg = ppg_cur, pool = as.integer(n_cur >= MIN_G_REP),
                          cppg, G0 = tg_left * cavail, dp = p$draft_pick[match(player_id, p$player_id)])
  dy <- cbind(pr$G[mi, 2:5, drop = FALSE], pr$ppg[mi, 2:5, drop = FALSE])[, c(1, 5, 2, 6, 3, 7, 4, 8)]   # SG1, mu1, ..., SG4, mu4
  dy <- cbind(dy, S4 = pr$S[mi, 5])                                   # chance he is still playing in 2030
  dy[is.na(mi), ] <- NA
  rp <- prospect_profiles()
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
  cc <- o$rp$cal %>% filter(pos == ps)                                 # tier-major: tier 1 seasons 1-4, tier 2 ...
  pk[[key]]  <- list(G = cc$G, mu = cc$mu, sd = cc$sd)
  ri <- which(o$rp$pp$pos == ps)
  sdR[[key]] <- setNames(lapply(ri, function(j) o$rp$D[j, ]), ri) }   # age adjustment per prospect, seasons 1-4
# after Week 18 there are no games left: keep the redraft numbers from the last week that had games
rd_frozen <- NULL
if (max(sapply(unlist(rd, recursive = FALSE), `[`, 3)) <= 0 && file.exists("dv_league_presets.rds")) { old <- readRDS("dv_league_presets.rds")
  rd_frozen <- if (!is.null(old$rd_frozen)) old$rd_frozen else old$rd
  cat("\nregular season over: the redraft sheet keeps the projections from the last week with games left\n") }
presets <- list(base = base, rd = rd, rd_frozen = rd_frozen, dy = dyl, sdk = sdk, picks = list(pp = OUT_[[1]]$rp$pp, cal = pk, D = sdR),
                v = 1 / (1 + I_MAIN), week = CUT26, made = Sys.time())
saveRDS(presets, "dv_league_presets.rds")
write.csv(LGBT_, "dv_league_backtest.csv", row.names = FALSE)
SCB <- bind_rows(SCBT_) %>% mutate(across(where(is.numeric), ~ round(.x, 3)))
write.csv(SCB, "dv_scoring_backtest.csv", row.names = FALSE)
cat("\nSCORING-PRESET BACKTEST (default lineup lines):\n"); print(as.data.frame(SCB))

# ---------- the page's math, in R: value of every player and pick for a league setting ----------
stoploss <- function(mu, r, s) { z <- (mu - r) / s; s * dnorm(z) + (mu - r) * pnorm(z) }
league_values <- function(P, lg, ppr = 1, tep = 0, ptd = 4, fd = c(QB = 0, RB = 0, WR = 0, TE = 0)) {
  key <- c(QB = paste0("QB_p", ptd, "f", fd[["QB"]]), RB = paste0("RB_r", ppr, "f", fd[["RB"]]), WR = paste0("WR_r", ppr, "f", fd[["WR"]]),
           TE = paste0("TE_t", ppr + tep, "f", fd[["TE"]]))
  b <- P$base; k <- key[b$pos]
  g_ <- function(kk, id, j) { x <- P$rd[[kk]][[id]]; if (is.null(x)) NA_real_ else x[j + 1] }   # skip the 2026 PPG
  b$cppg <- mapply(g_, k, b$player_id, 1); b$G0 <- mapply(g_, k, b$player_id, 2)
  b$n_cur <- ifelse(b$pool == 1, 99, 0)
  rp <- rep_lines(b, lg); b$rep <- rp$rep_ppg[match(b$pos, rp$pos)]
  b$redraft <- (b$cppg - b$rep) * b$G0
  b$dynasty <- sapply(seq_len(nrow(b)), function(j) { x <- P$dy[[k[j]]][[b$player_id[j]]]; if (is.null(x) || anyNA(x)) return(NA)
    s <- P$sdk[[k[j]]]; sum(P$v^(0:4) * c(b$G0[j], x[c(1, 3, 5, 7)]) * stoploss(c(b$cppg[j], x[c(2, 4, 6, 8)]), b$rep[j], c(s[1], s[2] * sqrt(1:4)))) })
  pp <- P$picks$pp; tk <- key[pp$pos]
  pp$val <- sapply(seq_len(nrow(pp)), function(j) { cc <- P$picks$cal[[tk[j]]]; d <- P$picks$D[[tk[j]]][[as.character(j)]]
    pr4 <- unlist(pp[j, c("P1", "P2", "P3", "P4")]); r <- rp$rep_ppg[match(pp$pos[j], rp$pos)]
    sum(rep(pr4, each = 4) * rep(P$v^(1:4), 4) * cc$G * stoploss(cc$mu + rep(d, 4), r, cc$sd)) })
  pp <- pp %>% arrange(desc(val)) %>% mutate(slot = row_number())
  list(players = b, slots = pp, rep = rp)
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
top <- max(lv$players$dynasty, na.rm = TRUE); dr <- rank(-lv$players$dynasty, na.last = "keep")
cat("\ntier calibration (default scoring): games per 17 and PPG by tier, seasons 1-4\n")
print(as.data.frame(OUT_[[1]]$rp$cal %>% mutate(across(c(G, mu, sd), ~ round(.x, 1)))), row.names = FALSE)
cat("\ndefault league, 2027 rookie picks (mocked players post-draft, the rest pre-draft; 100k scale; 'like' = the dynasty rank of a player with that value):\n")
print(lv$slots %>% head(36) %>% mutate(pick = sprintf("%d.%02d", (slot - 1) %/% 12 + 1, (slot - 1) %% 12 + 1),
  value = round(1e5 * val / top), like = sapply(val, function(x) sum(lv$players$dynasty > x, na.rm = TRUE) + 1),
  p_tier1 = round(P1, 2), p_any = round(1 - P4, 2), age = round(age, 1)) %>% select(pick, name, pos, grade, age, p_tier1, p_any, value, like, source) %>% as.data.frame(), row.names = FALSE)
cat("\nelapsed:", round(as.numeric(difftime(Sys.time(), T0_, units = "mins")), 1), "min\n")
