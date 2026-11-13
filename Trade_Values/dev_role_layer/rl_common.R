# =============================================================================
# Role layer: shared functions used by dv_10 (rest of season) and dv_11 (dynasty) when a role switch is on.
#
# Switches (set before sourcing dv_10 / dv_11; all FALSE reproduces the live model exactly):
#   ROLE_AVAIL  A2  expected games from current status (reserve / Out / Doubtful / Questionable / starter / backup)
#   QB_START    A3  QBs valued as P(start) x value as a starter (start = 15+ pass attempts)
#   ROLE_SNAP   A4  RB / WR / TE: depth rank and snap share adjust credible PPG and the role part of availability
#
# Information timing (backtests): roster status and the injury report as of the last completed week (week CUT),
# depth chart published for week CUT + 1. The live 2026 board uses the latest roster week available (CUT + 1
# when the refresh runs after it is posted) and the latest depth-chart snapshot.
# Every fitted piece here is fit only on snapshot seasons before the season being predicted (2012 onward).
# =============================================================================
suppressMessages(library(dplyr))
for (v_ in c("ROLE_AVAIL", "QB_START", "ROLE_SNAP", "QB_FUT_ONLY")) if (!exists(v_)) assign(v_, FALSE)
RL_RW    <- readRDS("cache_role/role_week.rds")
RL_RS    <- readRDS("cache_role/roster_status_week.rds")
RL_INJ   <- readRDS("cache_role/injury_week.rds")
RL_TW    <- readRDS("cache_role/team_weeks.rds")
RL_DEPTH <- readRDS("cache_role/depth_week.rds")
OFF_ST   <- c("CUT", "DEV", "RET", "UFA", "RFA", "TRC", "TRD", "TRT")
UNAV_ST  <- c("SUS", "EXE", "NWT", "E14", "E01", "RSN", "RSR")
HEALTHY  <- c("starter", "backup2", "backup3")
RL_FIRST <- 2012                                   # first season with injury reports, weekly rosters and depth charts

# ---------- status of every rostered QB / RB / WR / TE at a snapshot ----------
role_snapshot <- function(yr, cut, now = FALSE) {
  sw <- if (now) cut + 1 else cut                                   # roster week used for status
  tws <- RL_TW %>% filter(season == yr)
  rsy <- RL_RS %>% filter(season == yr, week <= sw)
  tl <- rsy %>% group_by(r_team) %>% summarise(tlw = max(week), .groups = "drop")
  st <- rsy %>% group_by(player_id) %>% slice_max(week, n = 1, with_ties = FALSE) %>% ungroup() %>%
    left_join(tl, by = "r_team") %>% transmute(player_id, team = r_team, status, abbr, gone = week < tlw)
  lastg <- tws %>% filter(week <= cut) %>% group_by(team) %>% summarise(lw = max(week), .groups = "drop")
  st <- st %>% left_join(lastg, by = "team") %>%
    left_join(RL_INJ %>% filter(season == yr) %>% select(week, player_id, report_status), by = c("lw" = "week", "player_id"))
  dy <- RL_DEPTH %>% filter(season == yr)
  dy <- if (now && any(dy$week == 99)) dy %>% filter(week == 99) else dy %>% filter(week <= cut + 1)
  dd <- dy %>% group_by(team) %>% filter(week == max(week)) %>% ungroup()
  st <- st %>% left_join(dd %>% select(team, player_id, depth_rank, dc_pos), by = c("team", "player_id")) %>%
    mutate(cat = case_when(gone | status %in% OFF_ST ~ "off_roster",
                           status %in% c("RES", "PUP", UNAV_ST) | (grepl("^R", coalesce(abbr, "")) & status != "RET") ~ "reserve",
                           report_status %in% "Out" ~ "out", report_status %in% "Doubtful" ~ "doubtful",
                           report_status %in% "Questionable" ~ "questionable",
                           coalesce(depth_rank, 9L) == 1 ~ "starter", coalesce(depth_rank, 9L) == 2 ~ "backup2", TRUE ~ "backup3"),
           depth3 = ifelse(is.na(depth_rank), 3L, pmin(depth_rank, 3L)))
  # is the team's depth-chart QB1 unavailable? (for backup QBs)
  q1 <- dd %>% filter(dc_pos == "QB", depth_rank == 1) %>% left_join(st %>% select(player_id, cat), by = "player_id") %>%
    group_by(team) %>% summarise(qb1_out = as.integer(any(coalesce(cat, "off_roster") %in% c("reserve", "out", "doubtful", "off_roster"))), .groups = "drop")
  st <- st %>% left_join(q1, by = "team") %>% mutate(qb1_out = ifelse(depth3 >= 2, coalesce(qb1_out, 0L), 0L))
  # this season so far, from the player-week table
  rwy <- RL_RW %>% filter(season == yr)
  l4w <- tws %>% filter(week <= cut) %>% group_by(team) %>% slice_max(week, n = 4) %>% ungroup() %>% select(team, week) %>% mutate(l4 = 1L)
  cur <- rwy %>% filter(week <= cut) %>% left_join(l4w, by = c("team", "week")) %>% group_by(player_id) %>% arrange(week, .by_group = TRUE) %>%
    summarise(tg_role = sum(!class %in% c("off_roster", "missed_other")), inj_miss_cur = sum(class == "missed_injured"),
              healthy_miss_cur = sum(class == "missed_healthy"), starts_cur = sum(qb_start), starts_l4 = sum(qb_start * coalesce(l4, 0L)),
              snap_season = if (any(played == 1 & off_snaps > 0)) mean(off_pct[played == 1 & off_snaps > 0]) else NA_real_,
              snap_l4 = if (any(played == 1 & off_snaps > 0)) mean(tail(off_pct[played == 1 & off_snaps > 0], 4)) else NA_real_, .groups = "drop")
  his <- RL_RW %>% filter(season >= yr - 3, season <= yr - 1) %>% group_by(player_id, season) %>% filter(any(played == 1)) %>% ungroup() %>%
    group_by(player_id) %>% summarise(tg_role_h = sum(!class %in% c("off_roster", "missed_other")), inj_miss_h = sum(class == "missed_injured"), .groups = "drop")
  fut <- rwy %>% filter(week > cut) %>% group_by(player_id) %>%
    summarise(inj_miss_ros = sum(class == "missed_injured"), starts_ros = sum(qb_start), .groups = "drop")
  st %>% select(player_id, cat, depth_rank, depth3, qb1_out, report_status, roster_status = status) %>%
    full_join(cur, by = "player_id") %>% left_join(his, by = "player_id") %>% left_join(fut, by = "player_id")
}

# attach role columns to dv_10 snapshot rows (columns: player_id, season, pos, n_cur, tg_cur, tg_left, ...)
role_join <- function(d, now = FALSE) {
  bind_rows(lapply(sort(unique(d$season)), function(y) {
    x <- d %>% filter(season == y)
    r <- role_snapshot(y, if (now) CUT26 else CUT, now)
    x %>% select(-any_of(setdiff(names(r), "player_id"))) %>% left_join(r, by = "player_id") }))
}
role_fill <- function(d) d %>% mutate(
  cat = coalesce(cat, "backup3"), depth3 = coalesce(depth3, 3L), qb1_out = coalesce(qb1_out, 0L),
  across(c(tg_role, inj_miss_cur, healthy_miss_cur, starts_cur, starts_l4, tg_role_h, inj_miss_h, inj_miss_ros, starts_ros), ~ coalesce(.x, 0L)),
  catg = factor(ifelse(cat %in% HEALTHY, "healthy", cat), levels = c("healthy", "questionable", "doubtful", "out", "reserve", "off_roster")),
  depthf = factor(depth3, levels = 1:3))

# ---------- A2: expected share of remaining games played ----------
# rate = role x health
#   role   = share of healthy games he plays: Z3 x this season's share + (1 - Z3) x average for his position and depth rank
#            Z3 = healthy games so far / (healthy games so far + k3)
#   health = injury-only availability, credibility-weighted: Z4 x (1 - injury misses / games on a roster, this season and
#            the last 3) + (1 - Z4) x position average; Z4 = roster games / (roster games + k4). Depth-chart misses are not
#            counted against a player's health.
#   Out / Doubtful / Questionable / reserve list: health is replaced by the average ratio actual / role for that status;
#   off a roster: the average share for that position.
ra_role <- function(d, f, k3) {
  hg <- pmax(d$tg_cur - d$inj_miss_cur, 0); rh <- ifelse(hg > 0, pmin(d$n_cur / pmax(hg, 1), 1), 0)
  rm <- f$role_mean[cbind(match(d$pos, rownames(f$role_mean)), d$depth3)]
  if (!is.null(f$snap)) rm <- snap_role(d, f$snap, rm)
  hg / (hg + k3) * rh + k3 / (hg + k3) * rm
}
ra_health <- function(d, f, k4) {
  ge <- d$tg_role + d$tg_role_h; h <- ifelse(ge > 0, 1 - (d$inj_miss_cur + d$inj_miss_h) / pmax(ge, 1), 0)
  hp <- f$h_pos[d$pos]; ge / (ge + k4) * h + k4 / (ge + k4) * hp
}
ra_fit <- function(tr, snap = FALSE) {
  tr <- role_fill(tr) %>% filter(tg_left > 0)
  hl <- tr %>% filter(cat %in% HEALTHY)
  rmx <- hl %>% group_by(pos, depth3) %>% summarise(m = min(sum(n_ros) / max(sum(pmax(tg_left - inj_miss_ros, 0)), 1), 1), .groups = "drop")
  role_mean <- matrix(NA, 4, 3, dimnames = list(POSITIONS, 1:3)); role_mean[cbind(match(rmx$pos, POSITIONS), rmx$depth3)] <- rmx$m
  h_pos <- sapply(POSITIONS, function(ps) { x <- hl %>% filter(pos == ps); 1 - sum(x$inj_miss_ros) / sum(x$tg_left) })
  f <- list(role_mean = role_mean, h_pos = h_pos, k = matrix(NA, 4, 2, dimnames = list(POSITIONS, c("k3", "k4"))))
  if (snap) f$snap <- snap_fit(hl)
  for (ps in POSITIONS) {
    x <- hl %>% filter(pos == ps, n_cur >= 2)
    o <- optim(log(c(6, 40)), function(q) { p <- pmin(ra_role(x, f, exp(q[1])) * ra_health(x, f, exp(q[2])), 1); sum(x$tg_left * (x$rate_ros - p)^2) })
    f$k[ps, ] <- exp(o$par)
  }
  # status ratios (actual / role) for the injured statuses, shrunk toward the all-position ratio (30 player-weeks)
  ij <- tr %>% filter(cat %in% c("questionable", "doubtful", "out", "reserve")) %>%
    mutate(r = pmin(ra_role(pick(everything()), f, f$k[pos, "k3"]), 1))
  pooled <- ij %>% group_by(cat) %>% summarise(rp = sum(rate_ros * tg_left) / sum(r * tg_left), .groups = "drop")
  f$hcat <- ij %>% group_by(pos, cat) %>% summarise(n = n(), A = sum(rate_ros * tg_left), B = sum(r * tg_left), .groups = "drop") %>%
    left_join(pooled, by = "cat") %>% mutate(h = ifelse(B > 0, (n * A / B + 30 * rp) / (n + 30), rp)) %>% select(pos, cat, h, n)
  f$off <- tr %>% filter(cat == "off_roster") %>% group_by(pos) %>% summarise(m = sum(rate_ros * tg_left) / sum(tg_left), n = n(), .groups = "drop")
  f
}
ra_pred <- function(d, f) {
  d <- role_fill(d); k3 <- f$k[d$pos, "k3"]; k4 <- f$k[d$pos, "k4"]
  r <- ra_role(d, f, k3); h <- ra_health(d, f, k4)
  hc <- f$hcat$h[match(paste(d$pos, d$cat), paste(f$hcat$pos, f$hcat$cat))]
  out <- ifelse(d$cat %in% HEALTHY, r * h, r * coalesce(hc, h))
  off <- f$off$m[match(d$pos, f$off$pos)]
  pmin(ifelse(d$cat == "off_roster", coalesce(off, 0.2), out), 1)
}

# ---------- A4: snap share and depth rank for RB / WR / TE ----------
# availability role part: average share of healthy games played by position x depth rank, adjusted by snap share
# (logistic, fit on healthy players: season-to-date snap share and the last 4 games, missing -> position mean)
snap_fit <- function(hl) lapply(setNames(c("RB", "WR", "TE"), c("RB", "WR", "TE")), function(ps) {
  x <- hl %>% filter(pos == ps) %>% mutate(y = pmin(n_ros / pmax(tg_left - inj_miss_ros, 1), 1), w = pmax(tg_left - inj_miss_ros, 0))
  mu <- mean(x$snap_season, na.rm = TRUE)
  x <- x %>% mutate(s1 = coalesce(snap_season, mu), s4 = coalesce(snap_l4, snap_season, mu) - s1, miss = as.integer(is.na(snap_season)))
  list(mu = mu, g = suppressWarnings(glm(y ~ factor(depth3) + s1 + s4 + miss, family = quasibinomial, weights = w, data = x %>% filter(w > 0))))
})
snap_role <- function(d, S, rm) {
  for (ps in names(S)) { i <- which(d$pos == ps); if (!length(i)) next; s <- S[[ps]]
    x <- d[i, ] %>% mutate(s1 = coalesce(snap_season, s$mu), s4 = coalesce(snap_l4, snap_season, s$mu) - s1, miss = as.integer(is.na(snap_season)))
    rm[i] <- predict(s$g, newdata = x, type = "response") }
  rm
}
# credible PPG adjustment: residual (later PPG - credible PPG) on snap share and depth, weighted by later games
# (QBs included unless QB_START is on, which has its own depth adjustment of PPG in starts)
SP_POS <- if (QB_START) c("RB", "WR", "TE") else POSITIONS
sp_fit <- function(tr) lapply(setNames(SP_POS, SP_POS), function(ps) {
  x <- role_fill(tr) %>% filter(pos == ps, n_ros >= 3)
  mu <- mean(x$snap_season, na.rm = TRUE)
  x <- x %>% mutate(s1 = coalesce(snap_season, mu) - mu, s4 = coalesce(snap_l4, snap_season, mu) - coalesce(snap_season, mu), res = ppg_ros - cppg)
  list(mu = mu, m = lm(res ~ s1 + s4 + factor(depth3), data = x, weights = n_ros))
})
sp_pred <- function(d, S) {
  adj <- rep(0, nrow(d)); d <- role_fill(d)
  for (ps in names(S)) { i <- which(d$pos == ps); if (!length(i)) next; s <- S[[ps]]
    x <- d[i, ] %>% mutate(s1 = coalesce(snap_season, s$mu) - s$mu, s4 = coalesce(snap_l4, snap_season, s$mu) - coalesce(snap_season, s$mu))
    adj[i] <- predict(s$m, newdata = x) }
  adj
}

# ---------- A3: QB starts ----------
# start = 15+ pass attempts. PPG in starts only, credibility-weighted like dv_10 (k1s, k2s), prior = draft-slot
# potential fit on PPG in starts. P(start) for each remaining game: logistic on status, depth rank, QB1 unavailable,
# starts in the last 4 team games, share of team games started so far, draft pick, age, first two years.
qs_fit <- function(tr) {
  x <- role_fill(tr) %>% filter(pos == "QB", tg_left > 0) %>% mutate(y = pmin(starts_ros / tg_left, 1))
  suppressWarnings(glm(y ~ catg + depthf + qb1_out + I(starts_l4 / 4) + I(pmin(starts_cur / pmax(tg_cur, 1), 1)) + lpick + age_s + I(exp <= 1),
                       family = quasibinomial, weights = tg_left, data = x %>% mutate(catg = droplevels(catg))))
}
qs_pred <- function(d, g) {
  d <- role_fill(d); lv <- g$xlevels$catg
  d$catg <- factor(ifelse(as.character(d$catg) %in% lv, as.character(d$catg), "healthy"), levels = lv)
  as.vector(predict(g, newdata = d, type = "response"))
}
