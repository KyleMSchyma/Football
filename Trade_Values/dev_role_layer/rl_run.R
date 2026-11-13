# =============================================================================
# Experiment driver: ./run.sh rl_run.R logs/<tag>.txt <tag> [A2] [A3] [A4] [HD] [SH] [S4] [AGE=mono|pool37] [LG]
#   A2 = ROLE_AVAIL, A3 = QB_START, A4 = ROLE_SNAP, HD = H_DIRECT, SH = SIG_H, S4 = SURV4, LG = also run the
#   five league setups of dv_13. Writes exp/dv10_<tag>.rds, exp/dv11_<tag>.rds (and exp/lg_<tag>.rds). Never writes
#   the model's CSV / RDS outputs (NO_WRITE).
# =============================================================================
a <- commandArgs(trailingOnly = TRUE); EXP_TAG <- a[1]; NO_WRITE <- TRUE
WIDE_POP <- "WIDE" %in% a; LENFIX <- "LF" %in% a
BT_MIN <- if (WIDE_POP) 0 else if ("MIN1" %in% a) 1 else 3   # WIDE: also rostered players with 0 games so far   # MIN1: score every player with 1+ game by week 9 (live backtests: 3+)
ROLE_AVAIL <- "A2" %in% a; QB_START <- any(c("A3", "A3F") %in% a); QB_FUT_ONLY <- "A3F" %in% a; ROLE_SNAP <- "A4" %in% a   # A3F: QB starter layer for future seasons only
QB_DEPTH <- any(c("QD", "QDS") %in% a); QB_SS <- if ("QDA" %in% a) "avg" else "QDS" %in% a; if ("QDA" %in% a) QB_DEPTH <- TRUE; H_DIRECT <- "HD" %in% a; SIG_H <- "SH" %in% a; SURV4 <- "S4" %in% a
AGE_MODE <- if (any(grepl("^AGE=", a))) sub("^AGE=", "", a[grepl("^AGE=", a)][1]) else "none"
cat("run", EXP_TAG, ": A2", ROLE_AVAIL, " A3", QB_START, " A4", ROLE_SNAP, " HD", H_DIRECT, " SH", SIG_H, " S4", SURV4, " AGE", AGE_MODE, "\n")
t0 <- Sys.time()
source("dv_11_dynasty_v4.R")
if ("LG" %in% a) {
  LG_TEST_ <- list(
    "12 teams, superflex, 2 RB 3 WR 1 TE, no flex (default)" = list(teams = 12, qb = 1, rb = 2, wr = 3, te = 1, flex = 0, sf = 1),
    "12 teams, 1 QB, 2 RB 3 WR 1 TE, 1 flex"                 = list(teams = 12, qb = 1, rb = 2, wr = 3, te = 1, flex = 1, sf = 0),
    "10 teams, 1 QB, 2 RB 2 WR 1 TE, 2 flex"                 = list(teams = 10, qb = 1, rb = 2, wr = 2, te = 1, flex = 2, sf = 0),
    "14 teams, superflex, 2 RB 3 WR 1 TE, 1 flex"            = list(teams = 14, qb = 1, rb = 2, wr = 3, te = 1, flex = 1, sf = 1),
    "8 teams, 1 QB, 2 RB 2 WR 1 TE, 1 flex"                  = list(teams = 8,  qb = 1, rb = 2, wr = 2, te = 1, flex = 1, sf = 0))
  LGX <- lapply(names(LG_TEST_), function(nm) { lg <- LG_TEST_[[nm]]
    rv <- bind_rows(lapply(BT_YEARS, function(y) value_board(bt %>% filter(season == y), lg))) %>% filter(n_cur >= BT_MIN) %>%
      mutate(actual = pts_ros - rep_ppg * n_ros, naive = (ppg_cur - rep_ppg) * tg_left)
    list(setting = nm, rv = rv %>% select(season, player_id, pos, value, actual, naive), bd = bt_dyn(lg) %>% select(season, player_id, pos, age, exp, pred, actual, naive)) })
  saveRDS(LGX, paste0("exp/lg_", EXP_TAG, ".rds"))
}
cat("\nrun time:", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), "min\n")
