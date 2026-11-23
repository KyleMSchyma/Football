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
# =============================================================================
suppressMessages({ library(dplyr); library(tidyr); library(splines) })
select <- dplyr::select
POSITIONS <- c("QB", "RB", "WR", "TE")
DATA <- Sys.getenv("PP_DATA", "prospect_prior/data")         # nfl_weekly_raw.rds, players_raw.rds, nfl_weekly_2026.rds
REPO <- Sys.getenv("PP_REPO", "..")            # Football repo root (prospect model outputs)
OUT  <- Sys.getenv("PP_OUT", "prospect_prior/out"); dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
CUT <- 9; BT_YEARS <- 2016:2025; CUR <- 2026

w <- readRDS(file.path(DATA, "nfl_weekly_raw.rds")); w26 <- readRDS(file.path(DATA, "nfl_weekly_2026.rds"))
w <- bind_rows(w, w26[, intersect(names(w26), names(w))]) %>% filter(season_type == "REG")
w$position[w$position == "FB"] <- "RB"
w <- w %>% filter(position %in% POSITIONS) %>% select(player_id, name = player_display_name, position, season, week, team, pts = fantasy_points_ppr)
w$pts[is.na(w$pts)] <- 0
tw <- w %>% distinct(season, team, week)
team_n <- function(yr, lo, hi) tw %>% filter(season == yr, week >= lo, week <= hi) %>% count(team, name = "tg")
seas <- w %>% group_by(player_id, season) %>% summarise(g = n_distinct(week), pts = sum(pts), team = last(team), .groups = "drop") %>%
  left_join(tw %>% count(season, team, name = "tg_season"), by = c("season", "team"))
seasP <- seas %>% inner_join(w %>% count(player_id, season, position) %>% group_by(player_id, season) %>%
  slice_max(n, n = 1, with_ties = FALSE) %>% select(player_id, season, pos = position), by = c("player_id", "season"))
p <- readRDS(file.path(DATA, "players_raw.rds")) %>% transmute(player_id = gsis_id, draft_pick, draft_year, rookie_season,
                                                               birth_date = as.Date(birth_date))

# ---------- prospect-model probabilities, keyed by draft class + pick ----------
pg <- read.csv(file.path(REPO, "PostDraft_Model/pd_post_player_grades.csv"), stringsAsFactors = FALSE)
PR <- list(
  mixed = pg %>% transmute(class, pick, q1 = p_top, q2 = p_top2, q3 = p_any),
  post  = pg %>% transmute(class, pick, q1 = coalesce(p_top_draft, p_top), q2 = coalesce(p_top2_draft, p_top2), q3 = coalesce(p_any_draft, p_any)))
pre <- read.csv(file.path(REPO, "PreDraft_Model/pd_player_grades.csv"), stringsAsFactors = FALSE) %>% filter(status == "drafted")
PR$pre <- pre %>% transmute(class, pick, q1 = p_top, q2 = p_top2, q3 = p_any)
cols <- list(QB = c("p_top8_post", "p_top16_post", "p_top24_post"), RB = c("p_top8_post", "p_top16_post", "p_top24_post"),
             TE = c("p_top6_post", "p_top12_post", "p_top18_post"))
PR$rolling <- bind_rows(lapply(POSITIONS, function(P) {
  if (P == "WR") read.csv(file.path(REPO, "WR_Model/phase6_oof_predictions.csv")) %>% filter(scheme == "Rolling", model == "post_enet") %>%
    transmute(class = draft_season, pick, q1 = p_wr1, q2 = p_wr2plus, q3 = p_wr3plus)
  else read.csv(file.path(REPO, sprintf("%s_Model/phase4_oof_predictions.csv", P))) %>% filter(scheme == "Rolling") %>%
    transmute(class = draft_season, pick, q1 = .data[[cols[[P]][1]]], q2 = .data[[cols[[P]][2]]], q3 = .data[[cols[[P]][3]]]) }))
PR <- lapply(PR, function(x) x %>% filter(!is.na(q3)) %>% mutate(q2 = pmax(q2, q1), q3 = pmax(q3, q2)) %>% distinct(class, pick, .keep_all = TRUE))
attach_q <- function(d, src) { x <- PR[[src]]; i <- match(paste(d$draft_year, d$draft_pick), paste(x$class, x$pick))
  d$q1 <- x$q1[i]; d$q2 <- x$q2[i]; d$q3 <- x$q3[i]; d }

# ---------- prior models ----------
# variant -> (probability source, formula). exp capped at 4 as in the live pick prior.
VARS <- list(pick = list(src = NA, f = ppg ~ ns(lpick, knots = log(c(32, 100)), Boundary.knots = log(c(1, 262))) + factor(exp)),
             post = list(src = "post", f = ppg ~ q1 + q2 + q3 + factor(exp)),
             mixed = list(src = "mixed", f = ppg ~ q1 + q2 + q3 + factor(exp)),
             pick_mixed = list(src = "mixed", f = ppg ~ ns(lpick, knots = log(c(32, 100)), Boundary.knots = log(c(1, 262))) + q1 + q2 + q3 + factor(exp)),
             pick_pre = list(src = "pre", f = ppg ~ ns(lpick, knots = log(c(32, 100)), Boundary.knots = log(c(1, 262))) + q1 + q2 + q3 + factor(exp)),
             rolling = list(src = "rolling", f = ppg ~ q1 + q2 + q3 + factor(exp)))
TRN <- seasP %>% filter(g >= 1) %>% inner_join(p, by = "player_id") %>%
  mutate(exp = pmin(pmax(season - coalesce(rookie_season, season), 0), 4), lpick = log(coalesce(draft_pick, 262)), ppg = pts / g)
FITS <- list()
prior_fit <- function(yr, v) { key <- paste(yr, v); if (!is.null(FITS[[key]])) return(FITS[[key]])
  tr <- TRN %>% filter(season < yr, season >= yr - 10)
  fp <- lapply(setNames(POSITIONS, POSITIONS), function(ps) lm(VARS$pick$f, data = tr %>% filter(pos == ps), weights = g))
  fv <- NULL
  if (!is.na(VARS[[v]]$src)) { tq <- attach_q(tr, VARS[[v]]$src) %>% filter(!is.na(q3))
    fv <- lapply(setNames(POSITIONS, POSITIONS), function(ps) { x <- tq %>% filter(pos == ps)
      if (nrow(x) < 40 || length(unique(x$exp)) < 2) NULL else lm(VARS[[v]]$f, data = x, weights = g) }) }
  FITS[[key]] <<- list(pick = fp, v = fv); FITS[[key]] }
prior_ppg <- function(yr, d, v) {
  f <- prior_fit(yr, v); nd <- d %>% mutate(exp = pmin(pmax(exp, 0), 4), lpick = log(coalesce(draft_pick, 262)))
  out <- rep(NA_real_, nrow(d)); used <- rep(FALSE, nrow(d))
  if (!is.na(VARS[[v]]$src)) nd <- attach_q(nd, VARS[[v]]$src)
  for (ps in POSITIONS) { i <- which(d$pos == ps); if (!length(i)) next
    x <- nd[i, ]; x$exp <- factor(x$exp, levels = 0:4)
    out[i] <- predict(f$pick[[ps]], newdata = x)
    m <- f$v[[ps]]
    if (!is.null(m)) { j <- which(!is.na(x$q3) & as.character(x$exp) %in% m$xlevels$`factor(exp)`)
      if (length(j)) { out[i[j]] <- predict(m, newdata = x[j, ]); used[i[j]] <- TRUE } } }
  attr(out, "used") <- used; pmax(out, 0) }

# ---------- in-season snapshots (dv_10 definitions, PPG part) ----------
hist_tab <- function(yr, nh) seas %>% filter(season >= yr - nh, season <= yr - 1) %>% group_by(player_id) %>%
  summarise(g_h = sum(g), pts_h = sum(pts), tg_h = sum(tg_season, na.rm = TRUE), .groups = "drop") %>% mutate(ppg_h = pts_h / g_h, avail_h = pmin(g_h / tg_h, 1))
snapshot <- function(yr, nh) {
  cur <- w %>% filter(season == yr, week <= CUT) %>% group_by(player_id) %>%
    summarise(name = last(name), pos = names(which.max(table(position))), team = last(team), n_cur = n_distinct(week), pts_cur = sum(pts), .groups = "drop") %>%
    left_join(team_n(yr, 1, CUT) %>% rename(tg_cur = tg), by = "team") %>% left_join(team_n(yr, CUT + 1, 18) %>% rename(tg_left = tg), by = "team") %>%
    mutate(ppg_cur = pts_cur / n_cur, rate_cur = pmin(n_cur / tg_cur, 1))
  if (yr == CUR) cur$tg_left <- 17 - cur$tg_cur          # 2026: schedule not played yet
  d <- cur %>% left_join(hist_tab(yr, nh), by = "player_id") %>% left_join(p, by = "player_id") %>%
    mutate(g_h = coalesce(g_h, 0), tg_h = coalesce(tg_h, 0), season = yr, exp = pmax(0, yr - coalesce(rookie_season, yr)))
  pa <- seasP %>% filter(season >= yr - 3, season <= yr - 1) %>% group_by(pos) %>% summarise(pos_avail = sum(g) / sum(tg_season, na.rm = TRUE))
  tg <- w %>% filter(season == yr, week > CUT) %>% group_by(player_id) %>% summarise(n_ros = n_distinct(week), pts_ros = sum(pts), .groups = "drop")
  d %>% left_join(pa, by = "pos") %>% left_join(tg, by = "player_id") %>%
    mutate(n_ros = coalesce(n_ros, 0L), pts_ros = coalesce(pts_ros, 0), rate_ros = pmin(n_ros / tg_left, 1), ppg_ros = ifelse(n_ros > 0, pts_ros / n_ros, NA)) %>%
    filter(tg_left > 0)
}
cred_ppg <- function(d, k1, k2) { hist <- ifelse(d$g_h > 0, d$g_h / (d$g_h + k2) * coalesce(d$ppg_h, 0) + k2 / (d$g_h + k2) * d$prior, d$prior)
  d$n_cur / (d$n_cur + k1) * d$ppg_cur + k1 / (d$n_cur + k1) * hist }
cred_avail <- function(d, k3, k4) { hist <- d$tg_h / (d$tg_h + k4) * coalesce(d$avail_h, 0) + k4 / (d$tg_h + k4) * d$pos_avail
  d$tg_cur / (d$tg_cur + k3) * d$rate_cur + k3 / (d$tg_cur + k3) * hist }
fit_k <- function(d) { o <- optim(c(log(4), log(8)), function(q) { pr <- cred_ppg(d, exp(q[1]), exp(q[2])); sum(d$n_ros * (d$ppg_ros - pr)^2) }); exp(o$par) }
