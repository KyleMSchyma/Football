# =============================================================================
# Post-Draft Model -- Phase 9: post-draft grades for the 2027 class from a mock draft
#
# Nobody in the 2027 class has been drafted, so a mock draft stands in for the draft:
# each mocked QB/RB/WR/TE gets the mock's pick as his draft capital and the mock's
# team as his landing spot, and goes through the same post-draft model as every
# drafted player (the "post" tier ladder of each position model, refit on 2010-2023
# exactly as in pd_08_post_predictors.R).
#
# Inputs for a 2027 prospect
#   college profile   the 2027 rows of the pre-draft board (../PreDraft_Model/pd_<POS>_board.csv).
#                     Its columns are built the same way as the position models' columns
#                     (checked on the 2024-2026 drafted players: correlations .83-1.00,
#                     about 90-100% identical; see the check below)
#   age               not on the board, estimated from years since high school with a fit on
#                     the 2024-2026 drafted players (same for breakout age / QB starter age)
#   combine           not run yet: average tester at the position (training median for each
#                     drill, combine_invited = 1, no missing-drill flags). Height and weight
#                     come from the mock where it lists them, else the training median
#   draft pick        the mock's pick (log_pick = log(pick))
#   landing spot      the mock's team. Departures after 2026 are unknown, so the vacated share
#                     is the 2010-2023 training median and every 2026 player is assumed to
#                     stay: incumbent_pts = best 2026 PPR points at the position on that team,
#                     team_targets_prev = team's 2026 targets, both pro-rated to 17 games
# Grade = percentile of the post score among drafted players at the position, 2010-2023
#   (same reference and cut points as pd_07_postdraft_grades.R).
# Check: the 2024-2026 drafted players are scored the same way (board features, estimated
#   age, average combine, estimated landing spot) and compared with their real post scores.
#   The estimated inputs score QB and TE about 0.1 low on that check, so the final grade maps
#   the estimated score to the real-score scale with a per-position linear fit on the check
#   (post_grade_raw keeps the uncalibrated grade). Probabilities (p_top/p_top2/p_any) are raw.
# Outputs: pd_post_2027_mock_grades.csv, pd_post_2027_mock_check.csv,
#          pd_post_2027_mock_inputs.csv (every model input per mocked player), phase9_log.txt
# Run:     MOCK_FILE=<csv> ./run.sh pd_09_mock_2027.R phase9_log.txt
#   MOCK_FILE columns: round, pick, team, team_abbr (nflverse), player, pos, school,
#   height_in, weight_lb (blank if unknown). MOCK_NAME labels the source in the output.
# =============================================================================
suppressMessages({ library(dplyr); library(tidyr); library(pROC); library(ordinalNet) })
select <- dplyr::select
REPO <- dir.exists("../WR_Model")
POS_DIR <- if (REPO) c(QB = "../QB_Model", RB = "../RB_Model", WR = "../WR_Model", TE = "../TE_Model") else
  c(QB = "../Football2_QB", RB = "../Football2_RB", WR = "../Football2", TE = "../Football2_TE")
PRE_DIR <- if (REPO) "../PreDraft_Model" else "../Football2_PreDraft"
MOCK_FILE <- Sys.getenv("MOCK_FILE", "mock_2027/mock_2027_fantasy_positions.csv")
MOCK_NAME <- Sys.getenv("MOCK_NAME", "mock draft")
TIERS <- list(QB = c(8, 16, 24), RB = c(8, 16, 24), WR = c(12, 24, 36), TE = c(6, 12, 18))
GRADE_CUTS <- c(0, .10, .25, .35, .45, .55, .65, .75, .85, .90, .95, 1.0001)
GRADES     <- c("F", "D", "C-", "C", "C+", "B-", "B", "B+", "A-", "A", "A+")
grade_from_pct <- function(p) as.character(cut(p, GRADE_CUTS, labels = GRADES, right = FALSE))
gidx <- function(g) match(g, GRADES)
check <- function(label, ok, detail = "") { cat(sprintf("[%s] %s %s\n", ifelse(ok, "PASS", "FAIL"), label, detail)); invisible(ok) }
team_map <- c(GNB = "GB", KAN = "KC", NOR = "NO", NWE = "NE", SFO = "SF", TAM = "TB",
              LAR = "LA", RAM = "LA", STL = "LA", LVR = "LV", OAK = "LV", SDG = "LAC", SD = "LAC")
fix_team <- function(x) ifelse(x %in% names(team_map), unname(team_map[x]), x)
nkey <- function(x) gsub("[^a-z]", "", tolower(gsub("\\b(jr|sr|ii|iii|iv)\\.?$", "", tolower(x))))

# --- NFL weekly stats: 2023-2025 (check) and 2026 to date (2027 landing spots) -----------
read_first <- function(paths) { for (p in paths) if (file.exists(p)) return(readRDS(p)); NULL }
weekly <- read_first(c("../Football2/cache/nfl_weekly_raw.rds", "../WR_Model/cache/nfl_weekly_raw.rds"))
if (is.null(weekly)) weekly <- as.data.frame(nflreadr::load_player_stats(2023:2025, summary_level = "week"))
w26 <- read_first(c("../Football2_Dynasty/nfl_weekly_2026.rds", "../Trade_Values/nfl_weekly_2026.rds"))
if (is.null(w26)) w26 <- as.data.frame(nflreadr::load_player_stats(2026, summary_level = "week"))
keep <- c("season", "week", "season_type", "player_id", "position", "team", "attempts", "carries", "targets", "fantasy_points_ppr")
if (!"team" %in% names(weekly) && "recent_team" %in% names(weekly)) weekly$team <- weekly$recent_team
if (!"team" %in% names(w26) && "recent_team" %in% names(w26)) w26$team <- w26$recent_team
reg <- bind_rows(weekly %>% select(any_of(keep)) %>% filter(season %in% 2023:2025),
                 w26 %>% select(any_of(keep)) %>% filter(season == 2026)) %>%
  filter(season_type == "REG") %>% mutate(team = fix_team(team), across(c(attempts, carries, targets, fantasy_points_ppr), ~ coalesce(as.numeric(.x), 0)))
cat("2026 weeks in the data:", paste(range(reg$week[reg$season == 2026]), collapse = "-"), "\n")
# landing spot from season S-1 assuming nobody leaves; pro-rated to 17 team games
land_est <- function(S1) {
  r <- reg %>% filter(season == S1)
  tg <- r %>% group_by(team) %>% summarize(team_games = n_distinct(week), .groups = "drop")
  pl <- r %>% group_by(team, player_id) %>% summarize(pos = first(position), pts = sum(fantasy_points_ppr), tgt = sum(targets), .groups = "drop")
  pl %>% group_by(team) %>% summarize(
      inc_QB = max(c(0, pts[pos == "QB"])), inc_RB = max(c(0, pts[pos == "RB"])), inc_TE = max(c(0, pts[pos == "TE"])),
      team_targets_prev = sum(tgt), .groups = "drop") %>%
    left_join(tg, by = "team") %>% mutate(k = 17 / team_games, across(c(inc_QB, inc_RB, inc_TE, team_targets_prev), ~ .x * k)) %>%
    mutate(next_season = S1 + 1L)
}
LAND <- bind_rows(lapply(2023:2026, land_est))
cat("teams with 2026 data:", sum(LAND$next_season == 2027), " games played range:", paste(range(LAND$team_games[LAND$next_season == 2027]), collapse = "-"), "\n")

# --- each position's training table + exact post-draft preprocessing (from pd_08) --------
load_pos <- function(POS) {
  old <- setwd(POS_DIR[[POS]]); on.exit(setwd(old))
  e <- new.env()
  if (POS == "WR") {
    tbl <- readRDS("wr_model_table.rds") %>%
      mutate(final_power5 = as.integer(final_power5), combine_invited = as.integer(combine_invited)) %>%
      left_join(read.csv("phase5_finish_targets.csv") %>% select(draft_season, pick, finish_y1, finish_y2, finish_y3, finish_sum_3yr),
                by = c("draft_season", "pick")) %>%
      mutate(best_finish = pmin(finish_y1, finish_y2, finish_y3, na.rm = TRUE),
             tier = case_when(best_finish <= 12 ~ 1L, best_finish <= 24 ~ 2L, best_finish <= 36 ~ 3L, TRUE ~ 4L))
    train <- tbl %>% filter(!is.na(finish_sum_3yr))
    drills   <- c("forty", "vertical", "broad_jump", "speed_score")
    pre_num  <- c("age_at_draft", "final_dominator", "best_dominator", "final_yptpa", "breakout_age_filled", "career_rec_yds",
                  "college_seasons", "height_in", "weight_lb", "recruit_rating")
    pre_flag <- c("broke_out", "transferred", "early_declare", "final_power5", "college_matched", "combine_invited",
                  "miss_forty", "miss_vertical", "miss_broad_jump")
    post_num <- c("log_pick", "vacated_target_share", "team_targets_prev")
    num <- c(pre_num, post_num)
    fit_prep <- function(d) {
      med  <- sapply(c(num, drills), function(v) median(d[[v]], na.rm = TRUE))
      flag <- num[sapply(num, function(v) any(is.na(d[[v]])))]
      dm <- as.matrix(d[, drills]); for (v in drills) dm[is.na(dm[, v]), v] <- med[v]
      list(num = num, med = med, flag = flag, pca = prcomp(dm, center = TRUE, scale. = TRUE))
    }
    apply_prep <- function(p, d) {
      out <- data.frame(row.names = seq_len(nrow(d)))
      for (v in p$num) { x <- d[[v]]
        if (v %in% p$flag) out[[paste0("na_", v)]] <- as.integer(is.na(x))
        x[is.na(x)] <- p$med[v]; out[[v]] <- x }
      dm <- as.matrix(d[, drills]); for (v in drills) dm[is.na(dm[, v]), v] <- p$med[v]
      pcs <- predict(p$pca, dm)[, 1:2, drop = FALSE]
      out$athletic_pc1 <- pcs[, 1]; out$athletic_pc2 <- pcs[, 2]
      for (v in pre_flag) out[[v]] <- as.integer(coalesce(as.numeric(d[[v]]), 0))
      as.matrix(out)
    }
    pp <- fit_prep(train); X <- apply_prep(pp, train)
    sc <- apply(X, 2, sd); sc[sc == 0] <- 1; nlam <- 25
    prep <- function(d) apply_prep(pp, d)
    all_num <- c(num, drills)
  } else {
    sys.source(paste0(tolower(POS), "_common.R"), envir = e)
    tbl <- e$load_table()
    train <- tbl %>% filter(!is.na(finish_sum_3yr))
    num <- c(e$pre_num, e$post_num)
    pp <- e$fit_prep(train, num); X <- e$apply_prep(pp, train)
    X <- X[, apply(X, 2, sd) > 0, drop = FALSE]; sc <- apply(X, 2, sd); nlam <- 20
    cols <- colnames(X)
    prep <- function(d) e$apply_prep(pp, d)[, cols, drop = FALSE]
    all_num <- num
  }
  list(tbl = tbl, train = train, X = X, ce = colMeans(X), sc = sc, nlam = nlam, prep = prep, all_num = all_num, pos = POS)
}
VARIANT <- "unpen"   # FABLE dev: unpen = log_pick unpenalized; pick = pick-only ordinal logit for RB / WR / TE
fit_ladder <- function(L) {
  if (VARIANT == "pick" && L$pos != "QB") return(list(polr = MASS::polr(factor(tier, levels = 1:4, ordered = TRUE) ~ log_pick, data = L$train, Hess = TRUE), best = NA, fit = list(lambdaVals = NA)))
  Xs <- scale(L$X, L$ce, L$sc); PF <- as.numeric(colnames(L$X) != "log_pick")
  y <- factor(L$train$tier, levels = 1:4, ordered = TRUE)
  fit <- ordinalNet(Xs, y, family = "cumulative", link = "logit", alpha = 0.5, parallelTerms = TRUE,
                    nonparallelTerms = FALSE, nLambda = L$nlam, standardize = FALSE, penaltyFactors = PF)
  folds <- split(seq_len(nrow(Xs)), L$train$draft_season)
  tune <- tryCatch(ordinalNetTune(Xs, y, lambdaVals = fit$lambdaVals, folds = folds, printProgress = FALSE, warn = FALSE,
                                  family = "cumulative", link = "logit", alpha = 0.5, parallelTerms = TRUE,
                                  nonparallelTerms = FALSE, standardize = FALSE, penaltyFactors = PF), error = function(e) NULL)
  ll <- if (is.null(tune)) NULL else rowMeans(tune$loglik)
  best <- if (is.null(ll) || all(!is.finite(ll))) length(fit$lambdaVals) %/% 2 else which.max(ll)
  list(fit = fit, best = best)
}
score <- function(F, L, d) {   # tier probabilities -> q1..q3 (cumulative) and post score
  pr <- if (!is.null(F$polr)) matrix(predict(F$polr, data.frame(log_pick = L$prep(d)[, "log_pick"]), type = "probs"), ncol = 4) else
    matrix(predict(F$fit, scale(L$prep(d), L$ce, L$sc), whichLambda = F$best, type = "response"), ncol = 4)
  q1 <- pr[, 1]; q2 <- pr[, 1] + pr[, 2]; q3 <- q2 + pr[, 3]
  data.frame(q1 = q1, q2 = q2, q3 = q3, post_score = q1 + q2 + q3)
}

# --- turn pre-draft board rows into post-draft model inputs -----------------------------
# board: rows of pd_<POS>_board.csv; pick / team / height / weight from the draft (or mock)
VAC_COL <- c(QB = "vacated_att_share", RB = "vacated_touch_share", TE = "vacated_tgt_share", WR = "vacated_target_share")
build <- function(POS, b, L, AM, land) {
  med <- function(v) median(as.numeric(L$train[[v]]), na.rm = TRUE)
  d <- b %>% mutate(
    age_at_draft = predict(AM$age, newdata = b),
    recruit_rating = as.numeric(recruit_rating), college_matched = 1L, combine_invited = 1L,
    miss_forty = 0L, miss_vertical = 0L, miss_broad_jump = 0L,
    p_power5 = as.integer(power5), final_power5 = as.integer(power5),
    early_declare = as.integer(college_seasons <= 3 | age_at_draft < 22),
    height_in = coalesce(as.numeric(height_in), med("height_in")), weight_lb = coalesce(as.numeric(weight_lb), med("weight_lb")),
    log_pick = log(pick))
  for (v in intersect(c("forty", "vertical", "broad_jump", "cone", "speed_score"), names(L$train))) d[[v]] <- med(v)
  if (POS == "QB") d <- d %>% mutate(ever_starter = as.integer(ever_breakout), recruit_dual = 0L,
                                     starter_age_filled = predict(AM$brk, newdata = b))
  if (POS == "RB") d <- d %>% mutate(career_ypc = p_ypc, recruit_apb = 0L, breakout_age_filled = predict(AM$brk, newdata = b))
  if (POS == "TE") d <- d %>% mutate(breakout_age_filled = predict(AM$brk, newdata = b))
  if (POS == "WR") d <- d %>% mutate(final_dominator = p_dominator, final_yptpa = p_ypta, broke_out = as.integer(ever_breakout),
                                     breakout_age_filled = predict(AM$brk, newdata = b))
  # landing spot
  d <- if ("class" %in% names(land)) d %>% left_join(land, by = c("team_abbr" = "team", "class")) else d %>% left_join(land, by = c("team_abbr" = "team"))
  d[[VAC_COL[[POS]]]] <- med(VAC_COL[[POS]])
  if (POS != "WR") d$incumbent_pts <- d[[paste0("inc_", POS)]]
  miss <- setdiff(L$all_num, names(d)); if (length(miss)) stop(POS, ": inputs not built: ", paste(miss, collapse = ", "))
  d
}

pre_grades <- read.csv(file.path(PRE_DIR, "pd_player_grades.csv"), stringsAsFactors = FALSE, na.strings = "")
post_all   <- read.csv("pd_post_player_grades.csv", stringsAsFactors = FALSE, na.strings = "")
mock <- read.csv(MOCK_FILE, stringsAsFactors = FALSE, na.strings = "") %>% mutate(key = nkey(player))
cat("mock rows (QB/RB/WR/TE):", nrow(mock), " from", MOCK_FILE, "\n")

res <- list(); chk <- list(); unmatched <- list(); inputs <- list()
for (POS in c("QB", "RB", "WR", "TE")) {
  cat("\n=====", POS, "=====\n")
  L <- load_pos(POS); F <- fit_ladder(L)
  cat("training rows:", nrow(L$train), " lambda index", F$best, "of", length(F$fit$lambdaVals), "\n")
  board <- read.csv(file.path(PRE_DIR, sprintf("pd_%s_board.csv", POS)), stringsAsFactors = FALSE) %>%
    mutate(athlete_id = as.character(athlete_id), key = nkey(name))
  ref <- post_all %>% filter(position == POS, class <= 2023) %>% pull(post_score)
  pct <- function(v) sapply(v, function(s) mean(ref < s) + 0.5 * mean(ref == s))

  # age / breakout-age estimates from the 2024-2026 drafted players (board x model table)
  tb <- L$tbl %>% mutate(athlete_id = as.character(athlete_id)) %>% filter(draft_season >= 2024, !is.na(athlete_id))
  jj <- tb %>% select(athlete_id, draft_season, pick, draft_team, age_at_draft, any_of(c("breakout_age_filled", "starter_age_filled"))) %>%
    inner_join(board %>% filter(class >= 2024) %>% select(-pick), by = c("athlete_id", "draft_season" = "class"))
  brk_col <- if (POS == "QB") "starter_age_filled" else "breakout_age_filled"
  AM <- list(age = lm(age_at_draft ~ yrs_since_hs, data = jj),
             brk = lm(as.formula(paste(brk_col, "~ yrs_since_hs + breakout_yrs + ever_breakout")), data = jj))
  cat(sprintf("age fit: n=%d R2=%.2f resid SD %.2f yrs | %s fit R2=%.2f resid SD %.2f\n", nrow(jj), summary(AM$age)$r.squared, sigma(AM$age),
              brk_col, summary(AM$brk)$r.squared, sigma(AM$brk)))

  # --- check on 2024-2026: real post score vs the same pipeline the mock rows get ---------
  real <- post_all %>% filter(position == POS, class >= 2024) %>% select(class, pick, post_score_real = post_score)
  cb <- jj %>% mutate(team_abbr = fix_team(draft_team)) %>% rename(class = draft_season) %>%
    select(-any_of(c("age_at_draft", "breakout_age_filled", "starter_age_filled")))
  cb <- build(POS, cb %>% mutate(height_in = NA, weight_lb = NA), L, AM, LAND %>% rename(class = next_season))
  cb <- bind_cols(cb, score(F, L, cb)) %>% inner_join(real, by = c("class", "pick"))
  rho <- cor(cb$post_score, cb$post_score_real, method = "spearman")
  cat(sprintf("check 2024-2026 (n=%d): Spearman real vs estimated post score %.3f, mean abs diff %.3f, mean diff %+.3f, same grade %.0f%%, within one grade %.0f%%\n",
              nrow(cb), rho, mean(abs(cb$post_score - cb$post_score_real)), mean(cb$post_score - cb$post_score_real),
              100 * mean(grade_from_pct(pct(cb$post_score)) == grade_from_pct(pct(cb$post_score_real))),
              100 * mean(abs(gidx(grade_from_pct(pct(cb$post_score))) - gidx(grade_from_pct(pct(cb$post_score_real)))) <= 1)))
  chk[[POS]] <- cb %>% transmute(position = POS, class, pick, name, team = team_abbr, post_score_real = round(post_score_real, 3),
                                 post_score_est = round(post_score, 3), grade_real = grade_from_pct(pct(post_score_real)),
                                 grade_est = grade_from_pct(pct(post_score)))

  # --- the 2027 mock ----------------------------------------------------------------------
  m <- mock %>% filter(pos == POS)
  b27 <- board %>% filter(class == 2027) %>% select(-pick, -round)
  mm <- m %>% left_join(b27, by = "key", suffix = c("", ".board"))
  dup <- mm %>% count(pick) %>% filter(n > 1)
  if (nrow(dup)) { cat("name matches more than one board row at picks", paste(dup$pick, collapse = ","), "-- keeping the same-school row\n")
    mm <- mm %>% group_by(pick) %>% arrange(desc(nkey(school) == nkey(p_team)), .by_group = TRUE) %>% slice(1) %>% ungroup() }
  um <- mm %>% filter(is.na(athlete_id)); if (nrow(um)) unmatched[[POS]] <- um %>% select(pick, player, pos, school)
  mm <- mm %>% filter(!is.na(athlete_id)) %>% mutate(class = 2027L)
  cat("mock", POS, ":", nrow(m), " matched to the 2027 board:", nrow(mm), "\n")
  if (!nrow(mm)) next
  d <- build(POS, mm, L, AM, LAND %>% filter(next_season == 2027) %>% select(-next_season))
  check(paste(POS, "landing spot found for every mocked team"), all(!is.na(d$team_targets_prev)))
  s <- score(F, L, d)
  inputs[[POS]] <- data.frame(position = POS, pick = d$pick, name = d$player, round(L$prep(d), 4), check.names = FALSE) %>%
    pivot_longer(-c(position, pick, name), names_to = "input", values_to = "value")
  pg <- pre_grades %>% filter(class == 2027, position == POS) %>% mutate(key = nkey(name)) %>%
    select(key, pre_grade = grade, pre_score = score, pre_pctile = pctile, pre_rank_class = pos_rank_class)
  res[[POS]] <- bind_cols(d, s) %>% mutate(pre_score_board = p1 + p2 + p3) %>% left_join(pg, by = "key") %>% mutate(position = POS, post_pctile = pct(post_score), post_grade = grade_from_pct(post_pctile))
}

# --- calibration: the estimated inputs run low for QB and TE on the 2024-2026 check, so the
# grade uses a per-position linear map from estimated to real post score fitted on that check
# (rank order is kept; post_score_raw / post_grade_raw keep the uncalibrated values)
C <- bind_rows(chk)
cal <- lapply(split(C, C$position), function(x) lm(post_score_real ~ post_score_est, data = x))
cat("\ncalibration (real = a + b * estimated, 2024-2026 drafted players):\n")
for (P in names(cal)) { cf <- coef(cal[[P]]); x <- C[C$position == P, ]; fit <- fitted(cal[[P]])
  ref <- post_all %>% filter(position == P, class <= 2023) %>% pull(post_score); pc <- function(v) sapply(v, function(s) mean(ref < s) + 0.5 * mean(ref == s))
  cat(sprintf("  %s a=%+.3f b=%.3f | same grade raw %.0f%% -> calibrated %.0f%%, within one grade %.0f%% -> %.0f%%\n", P, cf[1], cf[2],
    100 * mean(x$grade_est == x$grade_real), 100 * mean(grade_from_pct(pc(fit)) == x$grade_real),
    100 * mean(abs(gidx(x$grade_est) - gidx(x$grade_real)) <= 1), 100 * mean(abs(gidx(grade_from_pct(pc(fit))) - gidx(x$grade_real)) <= 1))) }
res <- lapply(names(res), function(P) { r <- res[[P]]
  ref <- post_all %>% filter(position == P, class <= 2023) %>% pull(post_score); pc <- function(v) sapply(v, function(s) mean(ref < s) + 0.5 * mean(ref == s))
  r %>% mutate(post_score_raw = post_score, post_grade_raw = post_grade,
               post_score = pmax(predict(cal[[P]], newdata = data.frame(post_score_est = post_score_raw)), 0.01),
               post_pctile = pc(post_score), post_grade = grade_from_pct(post_pctile)) })

# pre-draft grade for prospects outside the published 2027 pre-draft list: from the pre-draft grade scale
pscale <- read.csv(file.path(PRE_DIR, "pd_grade_scale.csv"), stringsAsFactors = FALSE)
pre_from_scale <- function(pos, sc) mapply(function(p, v) { g <- pscale %>% filter(position == p, min_score <= v); if (nrow(g)) g$grade[1] else "F" }, pos, sc)
out <- bind_rows(res) %>% mutate(pre_grade = ifelse(is.na(pre_grade), pre_from_scale(position, pre_score_board), pre_grade)) %>%
  mutate(q2 = pmax(q2, q1), q3 = pmax(q3, q2), grade_move = gidx(post_grade) - gidx(pre_grade)) %>%
  group_by(position) %>% mutate(post_rank_class = rank(-post_score, ties.method = "first")) %>% ungroup() %>%
  transmute(position, post_rank_class, pre_rank_class, name = player, board_name = name, school, board_school = p_team,
            round, pick, team, team_abbr, post_grade, post_score = round(post_score, 3), post_pctile = round(post_pctile, 3),
            post_grade_raw, post_score_raw = round(post_score_raw, 3),
            pre_grade, pre_score = round(coalesce(pre_score, pre_score_board), 3), pre_pctile = round(pre_pctile, 3), grade_move,
            p_top = round(q1, 3), p_top2 = round(q2, 3), p_any = round(q3, 3),
            age_est = round(age_at_draft, 1), incumbent_pts_2026 = round(coalesce(incumbent_pts, NA_real_), 1),
            team_targets_2026 = round(team_targets_prev), height_in, weight_lb,
            source = MOCK_NAME, score_source = "final post model (trained 2010-2023), mock pick as draft capital") %>%
  arrange(pick)
write.csv(out, "pd_post_2027_mock_grades.csv", row.names = FALSE, na = "")
write.csv(bind_rows(chk), "pd_post_2027_mock_check.csv", row.names = FALSE, na = "")
write.csv(bind_rows(inputs), "pd_post_2027_mock_inputs.csv", row.names = FALSE, na = "")

cat("\n===== 2027 post-draft grades from the mock (", MOCK_NAME, ") =====\n")
print(as.data.frame(out %>% select(pick, name, position, team_abbr, pre_grade, post_grade_raw, post_grade, grade_move, p_top, p_any, incumbent_pts_2026)), row.names = FALSE)
cat("\nschool differs between mock and board:\n")
print(as.data.frame(out %>% filter(nkey(school) != nkey(board_school)) %>% select(pick, name, school, board_school)), row.names = FALSE)
cat("\nnot matched to the 2027 pre-draft board:\n"); print(as.data.frame(bind_rows(unmatched)), row.names = FALSE)
check("every mocked QB/RB/WR/TE graded", nrow(out) == nrow(mock), sprintf("(%d of %d)", nrow(out), nrow(mock)))
check("probabilities ordered", all(out$p_top <= out$p_top2 & out$p_top2 <= out$p_any))
cat("\ndone\n")
