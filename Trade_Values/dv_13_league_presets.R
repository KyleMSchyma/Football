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
# Age-adjustment tables for the grade boards' Value column under any league (Kyle 2026-11-12): per scoring key, the cumulative
# age adjustment to PPG in seasons 2-4 (season 1 = 0) for ages AGE_GRID_, same formula as the 2027 pick profiles.
AGE_GRID_ <- round(seq(18.5, 31, by = 0.1), 1); AGET_ <- list()

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
# Kyle 2026-11-13: picks are valued over their first 5 NFL seasons (2027-2031), the same calendar window as every player
# (rest of 2026 + 2027-2031). Season 5 of the tier calibration comes from the 2010-2021 classes (the ones with 5 seasons played).
NK_ <- 5
tier_cal <- function(hk) hk %>% group_by(pos, tier, k) %>%
  summarise(n = n(), G = mean(g17), mu = if (sum(g) > 0) sum(pts) / sum(g) else 0,
            sd = if (sum(g > 0) > 2) sqrt(sum(g[g > 0] * (pts[g > 0] / g[g > 0] - sum(pts) / sum(g))^2) / sum(g)) else NA_real_, .groups = "drop") %>%
  group_by(pos, k) %>% mutate(sd = ifelse(is.na(sd) | sd < 1, max(sd, na.rm = TRUE), sd)) %>% ungroup() %>% arrange(pos, tier, k)
# Pick calibration (Kyle 2026-11-13): one multiplier on the pick (and rookie board) values so that, on the 2016-2022 classes,
# the predicted value of rookie-draft slots 1.01-1.12 equals what those players actually produced. Post-draft probabilities
# (out-of-class), tier calibration refit without the class being tested, default league lines, seasons played so far (<= 5).
pick_factor <- function(rp) {
  gpo <- read.csv(file.path(MOCK_DIR, "pd_post_player_grades.csv"), stringsAsFactors = FALSE)
  rep_d <- setNames(b26$rep_ppg[match(POSITIONS, b26$pos)], POSITIONS)
  out <- bind_rows(lapply(2016:2022, function(Y) {
    x <- gpo %>% filter(class == Y, !is.na(p_top), !is.na(pick)) %>% transmute(pos = position, class, pick, p_top, p_top2, p_any) %>%
      distinct(pos, pick, .keep_all = TRUE) %>%
      inner_join(rp$pr_ %>% distinct(pos, draft_year, draft_pick, .keep_all = TRUE) %>% select(pos, draft_year, draft_pick, birth_date),
                 by = c("pos", "class" = "draft_year", "pick" = "draft_pick")) %>%
      mutate(age = as.numeric(as.Date(paste0(Y, "-09-01")) - birth_date) / 365.25,
             age = ifelse(is.na(age), rp$a_ref$a[match(pos, rp$a_ref$pos)], age))
    cy <- tier_cal(rp$hk %>% filter(class != Y)); K <- min(NK_, LAST_FULL - Y + 1)
    val <- function(i, KK) { cc <- cy %>% filter(pos == x$pos[i], k <= KK); a0 <- rp$a_ref$a[rp$a_ref$pos == x$pos[i]]
      d <- c(0, cumsum(sapply(2:NK_, function(k) rp$agef(x$pos[i], x$age[i] + k - 2) - rp$agef(x$pos[i], a0 + k - 2))))[cc$k]
      P <- c(x$p_top[i], x$p_top2[i] - x$p_top[i], x$p_any[i] - x$p_top2[i], 1 - x$p_any[i])
      sum(P[cc$tier] * v^cc$k * cc$G * stoploss(cc$mu + d, rep_d[x$pos[i]], cc$sd)) }
    x$full <- sapply(seq_len(nrow(x)), val, KK = NK_); x$predK <- sapply(seq_len(nrow(x)), val, KK = K)
    rr <- rp$hk %>% filter(class == Y, k <= K) %>% mutate(por = pmax(ifelse(g > 0, pts / g, 0) - rep_d[pos], 0) * g) %>%
      group_by(pos, pick) %>% summarise(realized = sum(v^k * por), .groups = "drop")
    x %>% left_join(rr, by = c("pos", "pick")) %>% mutate(realized = coalesce(realized, 0)) %>% arrange(desc(full)) %>% slice_head(n = 12) }))
  f <- sum(out$realized) / sum(out$predK)
  cat(sprintf("\npick calibration: rookie-draft slots 1.01-1.12 of 2016-2022 predicted %.0f, realized %.0f -> multiplier %.2f\n",
              mean(out$predK), mean(out$realized), f))
  list(f = f, bt = out)
}
prospect_profiles <- function() {
  gr <- read.csv(file.path(PD_DIR, "pd_player_grades.csv"), stringsAsFactors = FALSE)
  pr_ <- readRDS(file.path(SHARED, "players_raw.rds")) %>%
    transmute(player_id = gsis_id, pos = ifelse(position == "FB", "RB", position), draft_year, draft_pick, birth_date = as.Date(birth_date)) %>%
    filter(pos %in% POSITIONS, !is.na(draft_pick))
  h <- gr %>% filter(status == "drafted", class %in% 2010:2022, !is.na(nfl_tier), !is.na(pick)) %>%
    transmute(pos = position, class, pick, tier = pmin(nfl_tier, 4)) %>%
    inner_join(pr_, by = c("pos", "class" = "draft_year", "pick" = "draft_pick")) %>%
    mutate(age0 = as.numeric(as.Date(paste0(class, "-09-01")) - birth_date) / 365.25)
  hk <- bind_rows(lapply(1:NK_, function(k) h %>% mutate(k = k, season = class + k - 1))) %>% filter(season <= LAST_FULL) %>%
    left_join(seas %>% select(player_id, season, g, pts, tg_season), by = c("player_id", "season")) %>%
    mutate(g = coalesce(g, 0L), pts = coalesce(pts, 0), tg = coalesce(tg_season, ifelse(season >= 2021, 17L, 16L)), g17 = pmin(g / tg, 1) * 17)
  cal <- tier_cal(hk)
  a_ref <- h %>% group_by(pos) %>% summarise(a = mean(age0, na.rm = TRUE))
  agef <- function(ps, a) predict(F[[ps]]$prod, data.frame(cppg = 0, age = a, exp = 0, lpick = 0, ss = 0, depthf = factor("unk", levels = c("1", "2", "3", "unk"))))   # depthf, ss: QB_DEPTH models (constants cancel)   # only the age curve matters (differences)
  # Kyle 2026-11-12 (second change): the pre-draft probabilities include the chance of going undrafted, so among drafted
  # players they ran ~30-40% low. Rookie picks are drafted players, so use the drafted-recalibrated versions
  # (pd_11_drafted_calibration.R: logistic recalibration of logit(p) per position and tier on drafted 2010-2023).
  dp_file <- file.path(PD_DIR, "pd_player_probs_drafted.csv")
  g27 <- gr %>% filter(class == 2027)
  if (file.exists(dp_file)) {
    dp <- read.csv(dp_file, stringsAsFactors = FALSE) %>% filter(class == 2027) %>% distinct(position, name, college, .keep_all = TRUE)
    g27 <- g27 %>% left_join(dp %>% select(position, name, college, p_top_d, p_top2_d, p_any_d), by = c("position", "name", "college")) %>%
      mutate(p_top = coalesce(p_top_d, p_top), p_top2 = coalesce(p_top2_d, p_top2), p_any = coalesce(p_any_d, p_any))
  }
  pp <- g27 %>%
    transmute(name, pos = position, college, age = 18.6 + yrs_out_of_hs, score, grade,
              P1 = p_top, P2 = p_top2 - p_top, P3 = p_any - p_top2, P4 = 1 - p_any,
              source = if (file.exists(dp_file)) "pre-draft (drafted-recalibrated)" else "pre-draft")
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
  # FABLE 2026-11-13 (finding 5): 2027 prospects priced from the PRE-draft model are multiplied by their chance of declaring
  # (Football2_PreDraft/pd_12_declare_2027.R); mocked prospects (post-draft, mock pick) are left as they are.
  pp$p_declare <- 1
  dfile <- file.path(PD_DIR, "pd_declare_2027.csv")
  if (file.exists(dfile)) {
    nk_ <- function(x) gsub("[^a-z]", "", tolower(sub(" (jr|sr|ii|iii|iv)\\.?$", "", x, ignore.case = TRUE)))
    dd <- read.csv(dfile, stringsAsFactors = FALSE) %>% distinct(position, name, college, .keep_all = TRUE)
    pre_ <- !grepl("^post-draft", pp$source)
    m_ <- match(paste(nk_(pp$name), pp$pos, pp$college), paste(nk_(dd$name), dd$position, dd$college))
    m2 <- match(paste(nk_(pp$name), pp$pos), paste(nk_(dd$name), dd$position)); m_[is.na(m_)] <- m2[is.na(m_)]
    f_ <- ifelse(pre_ & !is.na(m_), dd$p_declare_refit[m_], 1); pp$p_declare <- f_
    pp$P1 <- pp$P1 * f_; pp$P2 <- pp$P2 * f_; pp$P3 <- pp$P3 * f_; pp$P4 <- 1 - pp$P1 - pp$P2 - pp$P3
    pp$source <- ifelse(pre_ & !is.na(m_), paste0(pp$source, " x P(declare)"), pp$source)
    cat(sprintf("2027 picks: %d pre-draft-priced prospects multiplied by P(declare) (mean %.2f); %d not matched\n", sum(pre_ & !is.na(m_)),
                mean(f_[pre_ & !is.na(m_)]), sum(pre_ & is.na(m_))))
  }
  D <- t(sapply(seq_len(nrow(pp)), function(i) { ps <- pp$pos[i]; a0 <- a_ref$a[a_ref$pos == ps]
    d <- sapply(2:NK_, function(k) agef(ps, pp$age[i] + k - 2) - agef(ps, a0 + k - 2)); c(0, cumsum(d)) }))
  list(cal = cal, pp = pp, D = D, a_ref = a_ref, agef = agef, pr_ = pr_, hk = hk)
}

# ---------- Value column for the pre-draft and post-draft rankings boards (Kyle 2026-11-12) ----------
# One expected dynasty value per board player so rookies can be compared ACROSS positions (grades are within-position
# percentiles). Same math as the 2027 rookie picks, default league and default scoring, 100k trade-value scale:
#   value = sum over tiers of P(tier) x the tier's calibrated seasons 1-4 (games, PPG over replacement, discount), age-adjusted.
# Probabilities: post-draft where the player is drafted (classes 2010-2026) or in the 2027 mock, otherwise the
# drafted-recalibrated pre-draft ones. Age: real age on Sept 1 of the draft year where the birth date is known, else
# 18.6 + years out of high school. For past classes this is the value AT DRAFT TIME in today's default league (today's
# replacement lines, tier outcomes of the 2010-2022 classes), not what the player is worth now.
board_profiles <- function(rp) {
  nm <- function(x) gsub("[^a-z]", "", tolower(sub(" (jr|sr|ii|iii|iv)\\.?$", "", x, ignore.case = TRUE)))
  gr <- read.csv(file.path(PD_DIR, "pd_player_grades.csv"), stringsAsFactors = FALSE, na.strings = "")
  dp <- read.csv(file.path(PD_DIR, "pd_player_probs_drafted.csv"), stringsAsFactors = FALSE, na.strings = "")
  po <- read.csv(file.path(MOCK_DIR, "pd_post_player_grades.csv"), stringsAsFactors = FALSE, na.strings = "")
  mk <- read.csv(file.path(MOCK_DIR, "pd_post_2027_mock_grades.csv"), stringsAsFactors = FALSE, na.strings = "")
  postp <- po %>% filter(!is.na(pick)) %>% distinct(position, class, pick, .keep_all = TRUE) %>%
    transmute(position, class, pick, q1 = p_top, q2 = p_top2, q3 = p_any)
  pre <- gr %>% mutate(row = row_number()) %>%
    left_join(dp %>% transmute(position, class, name, college, d1 = p_top_d, d2 = p_top2_d, d3 = p_any_d) %>%
                distinct(position, class, name, college, .keep_all = TRUE), by = c("position", "class", "name", "college")) %>%
    left_join(postp, by = c("position", "class", "pick")) %>%
    mutate(mk_i = ifelse(class == 2027, match(paste(nm(name), position), paste(nm(mk$board_name), mk$position)), NA_integer_),
           src = case_when(!is.na(q1) ~ "post-draft", !is.na(mk_i) ~ "post-draft (mock pick)", TRUE ~ "pre-draft (drafted-recalibrated)"),
           P1 = case_when(!is.na(q1) ~ q1, !is.na(mk_i) ~ mk$p_top[mk_i], TRUE ~ d1),
           P12 = case_when(!is.na(q1) ~ q2, !is.na(mk_i) ~ mk$p_top2[mk_i], TRUE ~ d2),
           P123 = case_when(!is.na(q1) ~ q3, !is.na(mk_i) ~ mk$p_any[mk_i], TRUE ~ d3),
           age_hs = 18.6 + yrs_out_of_hs, age_mk = ifelse(is.na(mk_i), NA, mk$age_est[mk_i]))
  post <- po %>% mutate(row = row_number()) %>%
    left_join(gr %>% filter(!is.na(pick)) %>% distinct(position, class, pick, .keep_all = TRUE) %>% select(position, class, pick, yrs_out_of_hs),
              by = c("position", "class", "pick")) %>%
    mutate(src = "post-draft", P1 = p_top, P12 = p_top2, P123 = p_any, age_hs = 18.6 + yrs_out_of_hs, age_mk = NA_real_)
  b <- bind_rows(pre %>% transmute(board = "pre", row, position, class, name, college, pick, src, P1, P12, P123, age_hs, age_mk),
                 post %>% transmute(board = "post", row, position, class, name, college, pick, src, P1, P12, P123, age_hs, age_mk),
                 mk %>% transmute(board = "mock", row = row_number(), position, class = 2027L, name, college = school, pick,
                                  src = "post-draft (mock pick)", P1 = p_top, P12 = p_top2, P123 = p_any, age_hs = NA_real_, age_mk = age_est)) %>%
    left_join(rp$pr_ %>% distinct(pos, draft_year, draft_pick, .keep_all = TRUE) %>% select(pos, draft_year, draft_pick, birth_date),
              by = c("position" = "pos", "class" = "draft_year", "pick" = "draft_pick")) %>%
    mutate(age_bd = as.numeric(as.Date(paste0(class, "-09-01")) - birth_date) / 365.25,
           age = round(coalesce(age_mk, age_bd, age_hs, rp$a_ref$a[match(position, rp$a_ref$pos)]), 1),   # 0.1 grid = the pages' age table
           P12 = pmax(P12, P1), P123 = pmax(P123, P12),
           P1_ = P1, P2_ = P12 - P1, P3_ = P123 - P12, P4_ = 1 - P123)
  # FABLE 2026-11-13: same P(declare) multiplier for 2027 rows priced from the pre-draft model (the boards' Value column)
  dfile <- file.path(PD_DIR, "pd_declare_2027.csv")
  if (file.exists(dfile)) {
    dd <- read.csv(dfile, stringsAsFactors = FALSE) %>% distinct(position, name, college, .keep_all = TRUE)
    i_ <- which(b$class == 2027 & grepl("^pre-draft", b$src))
    m_ <- match(paste(nm(b$name[i_]), b$position[i_], b$college[i_]), paste(nm(dd$name), dd$position, dd$college))
    f_ <- coalesce(dd$p_declare_refit[m_], 1)
    b$P1_[i_] <- b$P1_[i_] * f_; b$P2_[i_] <- b$P2_[i_] * f_; b$P3_[i_] <- b$P3_[i_] * f_; b$P4_[i_] <- 1 - b$P1_[i_] - b$P2_[i_] - b$P3_[i_]
    b$P1[i_] <- b$P1[i_] * f_; b$P12[i_] <- b$P12[i_] * f_; b$P123[i_] <- b$P123[i_] * f_
    b$src[i_] <- paste0(b$src[i_], " x P(declare)")
  }
  D <- matrix(0, nrow(b), NK_)
  for (ps in POSITIONS) { i <- which(b$position == ps); if (!length(i)) next; a0 <- rp$a_ref$a[rp$a_ref$pos == ps]
    d <- sapply(2:NK_, function(k) rp$agef(ps, b$age[i] + k - 2) - rp$agef(ps, a0 + k - 2)); D[i, ] <- cbind(0, t(apply(matrix(d, ncol = NK_ - 1), 1, cumsum))) }
  list(b = b, D = D)
}

# FABLE build: the pick multiplier on the same definition of realized value as the players' dynasty backtest (each
# season's own default-league replacement line at week 9, real season length when LENFIX), with a bootstrap interval
# (resample classes, then players; 2000 draws, seed 2026). The old definition (2026 lines, 17 games) is kept as f_old.
pick_factor0 <- pick_factor
pick_factor <- function(rp) {
  old <- pick_factor0(rp); B <- old$bt %>% mutate(class = as.integer(class))
  rep_y <- bv %>% distinct(season, pos, rep_ppg)
  same <- bind_rows(lapply(sort(unique(B$class)), function(Y) {
    x <- B %>% filter(class == Y); cy <- tier_cal(rp$hk %>% filter(class != Y)); K <- min(NK_, LAST_FULL - Y + 1)
    ry <- setNames(rep_y$rep_ppg[rep_y$season == Y], rep_y$pos[rep_y$season == Y])
    val <- function(i) { cc <- cy %>% filter(pos == x$pos[i], k <= K); a0 <- rp$a_ref$a[rp$a_ref$pos == x$pos[i]]
      d <- c(0, cumsum(sapply(2:NK_, function(k) rp$agef(x$pos[i], x$age[i] + k - 2) - rp$agef(x$pos[i], a0 + k - 2))))[cc$k]
      P <- c(x$p_top[i], x$p_top2[i] - x$p_top[i], x$p_any[i] - x$p_top2[i], 1 - x$p_any[i])
      len <- if (isTRUE(LENFIX)) ifelse(Y + cc$k - 1 >= 2021, 17, 16) / 17 else 1
      sum(P[cc$tier] * v^cc$k * cc$G * len * stoploss(cc$mu + d, ry[x$pos[i]], cc$sd)) }
    x$predK <- sapply(seq_len(nrow(x)), val)
    rr <- rp$hk %>% filter(class == Y, k <= K) %>% mutate(por = pmax(ifelse(g > 0, pts / g, 0) - ry[pos], 0) * g) %>%
      group_by(pos, pick) %>% summarise(realized = sum(v^k * por), .groups = "drop")
    x %>% select(-realized) %>% left_join(rr, by = c("pos", "pick")) %>% mutate(realized = coalesce(realized, 0)) }))
  f <- sum(same$realized) / sum(same$predK); set.seed(2026)
  bs <- replicate(2000, { cl <- sample(unique(same$class), replace = TRUE)
    s <- bind_rows(lapply(cl, function(k) { z <- same[same$class == k, ]; z[sample.int(nrow(z), replace = TRUE), ] })); sum(s$realized) / sum(s$predK) })
  ci <- unname(quantile(bs, c(0.025, 0.975)))
  cat(sprintf("pick multiplier, players' definition of realized value: %.3f (95%% bootstrap %.2f-%.2f); old definition %.3f\n", f, ci[1], ci[2], old$f))
  list(f = f, ci = ci, f_old = old$f, bt = same)
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
                          cppg, G0 = tg_left * cavail, dp = p$draft_pick[match(player_id, p$player_id)],
                          st = status_tag(if ("cat" %in% names(b26)) b26$cat else rep(NA, nrow(b26)), b26$pos, if ("depth_rank" %in% names(b26)) b26$depth_rank else NA, if ("snap_season" %in% names(b26)) b26$snap_season else NA))
  dy <- cbind(pr$G[mi, 2:(NFUT + 1), drop = FALSE], pr$ppg[mi, 2:(NFUT + 1), drop = FALSE])[, as.vector(rbind(1:NFUT, NFUT + 1:NFUT))]   # SG1, mu1, ..., SG_NFUT, mu_NFUT
  dy <- cbind(dy, S4 = pr$S[mi, 5])                                   # chance he is still playing in 2030
  dy[is.na(mi), ] <- NA
  rp <- prospect_profiles()
  if (I_ == 1) { BOARD_ <- board_profiles(rp); PICKF_ <- pick_factor(rp) }     # default scoring run: board ages + pick calibration
  for (ps in names(keys)) { a0 <- rp$a_ref$a[rp$a_ref$pos == ps]
    d <- sapply(2:NK_, function(k) rp$agef(ps, AGE_GRID_ + k - 2) - rp$agef(ps, a0 + k - 2))
    AGET_[[paste0(ps, "_", keys[[ps]])]] <- t(apply(matrix(d, ncol = NK_ - 1), 1, cumsum)) }
  sdk <- lapply(setNames(POSITIONS, POSITIONS), function(ps) c(sd0 = unname(setNames(m1$rmse_credibility, m1$pos)[ps]), sig = F[[ps]]$sig,
                                                                 if (!is.null(F[[ps]]$sig_h)) setNames(F[[ps]]$sig_h, paste0("sd", 1:NFUT))))   # FABLE: [sd0, sig, sd1..sd5]; old pages read only [sd0, sig]
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
base <- OUT_[[1]]$pl %>% select(player_id, name, pos, team, age, games, ppg, pool, dp, st)
rd <- list(); dyl <- list(); sdk <- list(); pk <- list(); sdR <- list()
for (o in OUT_) for (ps in names(o$keys)) { key <- paste0(ps, "_", o$keys[[ps]])   # e.g. RB_r1: RB and WR share a scoring but not a fit
  i <- which(o$pl$pos == ps)
  rd[[key]]  <- setNames(lapply(i, function(j) c(o$pl$ppg[j], o$pl$cppg[j], o$pl$G0[j])), o$pl$player_id[i])   # 2026 PPG, credible PPG, exp. games left
  dyl[[key]] <- setNames(lapply(i, function(j) o$dy[j, ]), o$pl$player_id[i])
  sdk[[key]] <- o$sdk[[ps]]
  cc <- o$rp$cal %>% filter(pos == ps)                                 # tier-major: tier 1 seasons 1-NK_, tier 2 ...
  pk[[key]]  <- list(G = cc$G, mu = cc$mu, sd = cc$sd)
  ri <- which(o$rp$pp$pos == ps)
  sdR[[key]] <- setNames(lapply(ri, function(j) o$rp$D[j, ]), ri) }   # age adjustment per prospect, seasons 1-4
# after Week 18 there are no games left: keep the redraft numbers from the last week that had games
rd_frozen <- NULL
if (max(sapply(unlist(rd, recursive = FALSE), `[`, 3)) <= 0 && file.exists("dv_league_presets.rds")) { old <- readRDS("dv_league_presets.rds")
  rd_frozen <- if (!is.null(old$rd_frozen)) old$rd_frozen else old$rd
  cat("\nregular season over: the redraft sheet keeps the projections from the last week with games left\n") }
presets <- list(base = base, rd = rd, rd_frozen = rd_frozen, dy = dyl, sdk = sdk, picks = list(pp = OUT_[[1]]$rp$pp, cal = pk, D = sdR, nk = NK_, f = PICKF_$f, f_ci = PICKF_$ci, f_live_def = PICKF_$f_old), nf = NFUT,
                agetab = list(grid = AGE_GRID_, t = AGET_),
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
    s <- P$sdk[[k[j]]]; nf <- P$nf; sum(P$v^(0:nf) * c(b$G0[j], x[2 * (1:nf) - 1]) * stoploss(c(b$cppg[j], x[2 * (1:nf)]), b$rep[j], c(s[1], if (length(s) > 2) s[2 + 1:nf] else s[2] * sqrt(1:nf)))) })
  pp <- P$picks$pp; tk <- key[pp$pos]
  pp$val <- sapply(seq_len(nrow(pp)), function(j) { cc <- P$picks$cal[[tk[j]]]; d <- P$picks$D[[tk[j]]][[as.character(j)]]
    pr4 <- unlist(pp[j, c("P1", "P2", "P3", "P4")]); r <- rp$rep_ppg[match(pp$pos[j], rp$pos)]
    nk <- P$picks$nk; P$picks$f * sum(rep(pr4, each = nk) * rep(P$v^(1:nk), 4) * cc$G * stoploss(cc$mu + rep(d, 4), r, cc$sd)) })
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
cat("\ntier calibration (default scoring): games per 17 and PPG by tier, seasons 1-5\n")
print(as.data.frame(OUT_[[1]]$rp$cal %>% mutate(across(c(G, mu, sd), ~ round(.x, 1)))), row.names = FALSE)
cat("\ndefault league, 2027 rookie picks (mocked players post-draft, the rest pre-draft; 100k scale; 'like' = the dynasty rank of a player with that value):\n")
print(lv$slots %>% head(36) %>% mutate(pick = sprintf("%d.%02d", (slot - 1) %/% 12 + 1, (slot - 1) %% 12 + 1),
  value = round(1e5 * val / top), like = sapply(val, function(x) sum(lv$players$dynasty > x, na.rm = TRUE) + 1),
  p_tier1 = round(P1, 2), p_any = round(1 - P4, 2), age = round(age, 1)) %>% select(pick, name, pos, grade, age, p_tier1, p_any, value, like, source) %>% as.data.frame(), row.names = FALSE)

# ---------- board Value column: default league and scoring, 100k scale (read by the pre/post-draft page builders) ----------
if (exists("BOARD_")) {
  dkey <- c(QB = "QB_p4f0", RB = "RB_r1f0", WR = "WR_r1f0", TE = "TE_t1f0")
  bb <- BOARD_$b; rep_d <- lv$rep$rep_ppg[match(bb$position, lv$rep$pos)]
  bb$value <- sapply(seq_len(nrow(bb)), function(j) { cc <- presets$picks$cal[[dkey[[bb$position[j]]]]]
    pr4 <- c(bb$P1_[j], bb$P2_[j], bb$P3_[j], bb$P4_[j]); if (anyNA(pr4)) return(NA_real_)
    nk <- presets$picks$nk; presets$picks$f * sum(rep(pr4, each = nk) * rep(presets$v^(1:nk), 4) * cc$G * stoploss(cc$mu + rep(BOARD_$D[j, ], 4), rep_d[j], cc$sd)) })
  bb <- bb %>% mutate(value_100k = round(1e5 * value / top), age = round(age, 1),
                      across(c(P1, P12, P123), ~ round(.x, 4))) %>%
    select(board, row, position, class, name, college, pick, source = src, p_top = P1, p_top2 = P12, p_any = P123, age, value_100k)
  write.csv(bb, "dv_rookie_board_values.csv", row.names = FALSE)
  chk27 <- bb %>% filter(board == "pre", class == 2027) %>% mutate(nmk = gsub("[^a-z]", "", tolower(name)))
  sl <- lv$slots %>% mutate(nmk = gsub("[^a-z]", "", tolower(name)), v = round(1e5 * val / top))
  m27 <- inner_join(chk27, sl %>% select(nmk, pos, v), by = c("nmk", "position" = "pos"))
  cat(sprintf("\nboard values: %d pre-board rows, %d post-board rows; 2027 board value vs rookie-pick value, max abs diff %s (n = %d)\n",
              sum(bb$board == "pre"), sum(bb$board == "post"), max(abs(m27$value_100k - m27$v)), nrow(m27)))
  cat("\n2027 pre-draft board, top 30 by Value (default league, 100k scale):\n")
  print(as.data.frame(bb %>% filter(board == "pre", class == 2027) %>% arrange(desc(value_100k)) %>% head(30) %>%
    select(name, position, college, source, p_top, p_any, age, value_100k)), row.names = FALSE)
}
cat("\nelapsed:", round(as.numeric(difftime(Sys.time(), T0_, units = "mins")), 1), "min\n")
