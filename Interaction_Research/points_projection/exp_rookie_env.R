# Dev only: build the dv_13 rookie-value environment (default scoring) and save what the points-vs-tiers value backtest needs.
NO_WRITE <- TRUE
src <- readLines("dv_13_league_presets.R"); i <- grep("^for \\(I_ in seq_along\\(RUNS_\\)\\)", src)
eval(parse(text = src[1:(i - 1)]))
SC <- RUNS_[[1]]$sc
source("dv_11_dynasty_v4.R")
rp <- prospect_profiles()
gpo <- read.csv(file.path(MOCK_DIR, "pd_post_player_grades.csv"), stringsAsFactors = FALSE)
rep_y <- bv %>% distinct(season, pos, rep_ppg)
rep_d <- setNames(b26$rep_ppg[match(POSITIONS, b26$pos)], POSITIONS)
agegrid <- lapply(setNames(POSITIONS, POSITIONS), function(ps) { a <- seq(19, 30, by = 0.1); list(a = a, f = sapply(a, function(x) rp$agef(ps, x))) })
live_pf <- pick_factor(rp)
saveRDS(list(hk = rp$hk, a_ref = rp$a_ref, pr_ = rp$pr_, agegrid = agegrid, gpo = gpo, rep_y = rep_y, rep_d = rep_d, v = v, LENFIX = LENFIX,
             NK = NK_, LAST_FULL = LAST_FULL, live_pf = live_pf, stoploss = stoploss, tier_cal = tier_cal), "exp/rookie_env.rds")
cat("saved env; rep_y seasons", range(rep_y$season), " LENFIX", LENFIX, " v", v, "\n")
