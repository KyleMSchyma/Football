# =============================================================================
# Point-in-time value history (Kyle 2026-11-16): shared pieces
#
# Goal: rebuild the redraft and dynasty trade values for every past Tuesday (2016 week 1 onward) exactly as the weekly
# refresh would have produced them that day, using only information available then.
#
# How: the LIVE model scripts (dv_common, dv_10, dv_11, rl_common, rl_dv10, rl_dv11_ext) are copied into a
# scratch folder with a short, fixed list of edits (HV_EDITS below). Every edit must match the live text exactly
# once, or the run stops, so a later change to the live scripts can never be silently skipped. Then readRDS() is
# wrapped so that every data file the scripts read is cut to the as-of date: all earlier seasons, and only weeks
# 1..W of the snapshot season. Draft information is cut to players drafted by then.
#
# So at snapshot (S, W):
#   * every model is fit only on seasons before S (credibility constants k1..k4 on the week-9 snapshots of
#     max(2009, S - 10)..S - 1, the draft-capital prior on the 10 seasons before each, the role layer on 2012..S - 1,
#     the aging / still-playing / availability models on season ends through S - 2 with outcomes through S - 1);
#     the fitted models never see a single game of season S
#   * the board itself uses season S weeks 1..W (stats, roster status, injury report, depth chart for week <= W)
#   * games per season: 16 before 2021, 17 from 2021 (the 17-game season was announced in March 2021, so a 2020
#     snapshot still assumes 16-game future seasons)
#
# Edits that are not about information (documented in history/README.md):
#   * the replacement pool needs 6+ games played; before week 10 nobody may have 6, so the pool needs
#     min(6, max(1, floor(0.6 x W))) games (6 from week 10 on, so the live board is unchanged)
#   * the role layer needs injury reports and depth charts, which start in 2012: role models are fit on 2012+ only
#   * the weekly data cache starts in 2006, so early snapshots have fewer training seasons than today's model
# =============================================================================
HV_FILES <- c("dv_common.R", "dv_10_ros_value.R", "dv_11_dynasty_v4.R", "rl_common.R", "rl_dv10.R", "rl_dv11_ext.R")

HV_EDITS <- list(
  list("dv_common.R", "LAST_FULL <- 2025", "LAST_FULL <- HV_S - 1"),
  list("dv_common.R", "CUR       <- 2026", "CUR       <- HV_S"),
  list("dv_10_ros_value.R", 'source("dv_common.R")', 'source(file.path(HV_GEN, "dv_common.R"))'),
  list("dv_10_ros_value.R", 'CUT26 <- max(readRDS("nfl_weekly_2026.rds") %>% filter(season_type == "REG") %>% pull(week))', "CUT26 <- HV_W"),
  list("dv_10_ros_value.R", "BT_YEARS <- 2016:2025", "BT_YEARS <- max(HV_FIRST_BT, HV_S - 10):(HV_S - 1)"),
  list("dv_10_ros_value.R", "MIN_G_REP <- 6", "MIN_G_REP <- min(6, max(1, floor(0.6 * HV_W)))"),
  list("dv_10_ros_value.R", "if (yr == CUR) cur$tg_left <- 17 - cur$tg_cur", "if (yr == CUR) cur$tg_left <- HV_LEN - cur$tg_cur"),
  list("dv_10_ros_value.R", "if (yr == CUR) x$tg_left <- 17 - x$tg_cur", "if (yr == CUR) x$tg_left <- HV_LEN - x$tg_cur"),
  list("dv_10_ros_value.R", "filter(season %in% 2021:2025)", "filter(season %in% (HV_S - 5):(HV_S - 1))"),
  list("dv_10_ros_value.R", 'as.Date("2026-09-01")', 'as.Date(paste0(CUR, "-09-01"))'),
  list("dv_10_ros_value.R", 'source("rl_dv10.R")', 'source(file.path(HV_GEN, "rl_dv10.R"))'),
  list("rl_dv10.R", 'source("rl_common.R")', 'source(file.path(HV_GEN, "rl_common.R"))'),
  list("rl_dv10.R", 'bt_x <- bind_rows(lapply(RL_FIRST:(min(BT_YEARS) - 1), function(y) snapshot(y) %>% left_join(targets(y), by = "player_id")))',
                    'bt_x <- bind_rows(c(lapply(hv_seq(RL_FIRST, min(BT_YEARS) - 1), function(y) snapshot(y) %>% left_join(targets(y), by = "player_id")), list(bt[0, ])))'),
  list("rl_dv10.R", "RL_ALL <- qb_starts(role_join(bind_rows(bt_x, bt)))", "RL_ALL <- qb_starts(role_join(bind_rows(bt_x, bt))) %>% filter(season >= RL_FIRST)"),
  list("rl_dv10.R", "bt <- bind_rows(lapply(BT_YEARS, function(Y) rl_apply(RL_ALL %>% filter(season == Y), RL_ALL %>% filter(season < Y))))",
                    "bt <- bind_rows(bt %>% filter(season < RL_FIRST + 2) %>% mutate(cppg_rep = cppg), bind_rows(lapply(BT_YEARS[BT_YEARS >= RL_FIRST + 2], function(Y) rl_apply(RL_ALL %>% filter(season == Y), RL_ALL %>% filter(season < Y)))))"),
  list("rl_dv10.R", "role_join(s %>% mutate(season = CUR), now = TRUE)", "role_join(s %>% mutate(season = CUR), now = HV_NOW)"),
  list("rl_common.R", "r <- role_snapshot(y, if (now) CUT26 else CUT, now)", "r <- role_snapshot(y, if (now || y == CUR) CUT26 else CUT, now)"),
  list("dv_11_dynasty_v4.R", 'source("dv_10_ros_value.R")', 'source(file.path(HV_GEN, "dv_10_ros_value.R"))'),
  list("dv_11_dynasty_v4.R", "GLEN_ <- rep(17, NFUT)", "GLEN_ <- rep(HV_LEN, NFUT)"),
  list("dv_11_dynasty_v4.R", "SE <- bind_rows(lapply(2009:2025, season_end))", "SE <- bind_rows(lapply(2009:(CUR - 1), season_end))"),
  list("dv_11_dynasty_v4.R", 'source("rl_dv11_ext.R")', 'source(file.path(HV_GEN, "rl_dv11_ext.R"))'),
  list("dv_11_dynasty_v4.R", "BT <- bt_dyn()", "if (!HV_SKIP_BT) { BT <- bt_dyn()"),
  list("dv_11_dynasty_v4.R", 'if (WRITE) write.csv(res, "dv_v4_backtest.csv", row.names = FALSE)', 'if (WRITE) write.csv(res, "dv_v4_backtest.csv", row.names = FALSE) }'),
  list("dv_11_dynasty_v4.R", "F <- fix_sig(fit_future(2024))", "F <- fix_sig(fit_future(CUR - 2))")
)
HV_FIRST_BT <- 2009                        # first week-9 snapshot season with 3 earlier seasons in the cache (data start 2006)
hv_seq <- function(a, b) if (b >= a) a:b else integer(0)
hv_len <- function(s) ifelse(s >= 2021, 17L, 16L)

# copy the live scripts (src) into gen with the edits; stops if any edit does not match exactly once
hv_generate <- function(src, gen) {
  dir.create(gen, showWarnings = FALSE, recursive = TRUE)
  txt <- setNames(lapply(HV_FILES, function(f) paste(gsub("\r", "", readLines(file.path(src, f), warn = FALSE)), collapse = "\n")), HV_FILES)
  for (e in HV_EDITS) {
    n <- lengths(regmatches(txt[[e[[1]]]], gregexpr(e[[2]], txt[[e[[1]]]], fixed = TRUE)))
    if (n != 1) stop(sprintf("history edit does not match exactly once (%d matches) in %s: %s", n, e[[1]], e[[2]]))
    txt[[e[[1]]]] <- sub(e[[2]], e[[3]], txt[[e[[1]]]], fixed = TRUE)
  }
  for (f in HV_FILES) writeLines(txt[[f]], file.path(gen, f))
  tmp <- tempfile(); writeLines(paste(HV_FILES, tools::md5sum(file.path(src, HV_FILES))), tmp)
  substr(unname(tools::md5sum(tmp)), 1, 10)                  # model version: hash of the live scripts used
}

# as-of cut of any table the scripts read: all earlier seasons, season S weeks 1..W; players drafted after S removed
hv_cut <- function(x, S, W) {
  if (!is.data.frame(x)) return(x)
  if (all(c("season", "week") %in% names(x))) return(x[x$season < S | (x$season == S & x$week <= W), , drop = FALSE])
  if ("season" %in% names(x)) return(x[x$season <= S, , drop = FALSE])   # not used by the value scripts today; kept strict
  if ("rookie_season" %in% names(x)) return(x[is.na(x$rookie_season) | x$rookie_season <= S, , drop = FALSE])
  x
}
