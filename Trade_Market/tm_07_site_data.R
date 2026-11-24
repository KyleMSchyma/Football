# tm_07_site_data.R: write the Market Check page's "Trade market" source (prospect-actuary value-research/data/tm.js).
# R port of tm_07_site_data.py (the PC has no Python). Same output.
# Market 1:1 values from the 4-shape dynasty run (out/dynasty_add4_*.csv; Kyle 2026-11-23). Each player's log 1:1 value
# at the page's league (12 teams, 0.5 PPR, superflex, 1QB/2RB/3WR/1TE, no flex = 8 starters); the page fits one power so
# the market curve matches ours. s_pkg = power at which held-out 1-for-2 trades balance (2:1 package prices).
# Pooled rare assets are left out. 2027 rookie picks (one generic "mid" price per round, rounds 1-4) go in a separate
# "picks" list (Kyle 2026-11-24): the page ranks each round among the market's players and compares it with our slots.
# Usage: Rscript tm_07_site_data.R <out_dir> <sleeper_ids.json> <dest tm.js>   (run weekly by tm_weekly.sh)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
a <- commandArgs(TRUE); OUT <- a[1]; SLID <- a[2]; DST <- a[3]
A <- fread(file.path(OUT, "dynasty_add4_assets.csv"), colClasses = list(character = "asset"))
B <- fread(file.path(OUT, "dynasty_add4_beta.csv"))
meta <- fread(file.path(OUT, "dynasty_add4_meta.csv"))[1]
h <- fread(file.path(OUT, "dynasty_add4_holdout_by_shape.csv"))[shape == "1-for-2"][order(stretch)]
s <- meta$stretch
s_pkg <- approx(h$mean_log_gap_few_minus_many, h$stretch, xout = 0, ties = mean)$y
sl <- fromJSON(SLID)$m
x <- c(sf = 0, ppr1 = -0.5, tep = 0, teams = 0, start = 8 - 10)
PK <- A[grp == "PICK" & pick_year == 2027 & pick_round %in% 1:4][order(pick_round)]
if (nrow(PK) && "PICK" %in% B$group) PK[, lv := theta_unstretched + sum(B[group == "PICK"][match(names(x), covariate), beta] * x, na.rm = TRUE) / s]
A <- A[grp %in% c("QB", "RB", "WR", "TE")]
A[, adj := sapply(grp, function(g) sum(B[group == g][match(names(x), covariate), beta] * x))]
A[, lv := theta_unstretched + adj / s]                  # 1:1 scale betas = stretched betas / s
A[, nm := vapply(asset, function(id) { v <- sl[[id]]; if (is.null(v)) NA_character_ else sub("\\|.*$", "", v) }, "")]
A[is.na(nm) | nm == "", nm := name]
A <- A[!is.na(nm) & nm != ""][order(-lv)]
if (nrow(A) < 300) stop(sprintf("only %d players; tm.js not written", nrow(A)))
gv <- function(k, d) if (k %in% names(meta)) as.character(meta[[k]]) else d
data <- list(asof = gv("last_trade", "2026-11-23"), s_pkg = round(s_pkg, 3), trades = as.integer(meta$trades_used),
             first = gv("first_trade", "2026-05-01"),
             note = "Dynasty Daddy Trade Database, 1-for-1, 1-for-2, 2-for-2 and 2-for-3 dynasty trades",
             rows = lapply(seq_len(nrow(A)), function(i) list(A$nm[i], A$grp[i], round(A$lv[i], 4), as.integer(A$n_trades[i]))),
             picks = lapply(seq_len(nrow(PK)), function(i) list(PK$name[i], as.integer(PK$pick_round[i]), round(PK$lv[i], 4), as.integer(PK$n_trades[i]))))
tmp <- paste0(DST, ".tmp")
writeLines(paste0("window.TM = ", toJSON(data, auto_unbox = TRUE, digits = NA), ";"), tmp, useBytes = TRUE)
file.rename(tmp, DST)
message(nrow(A), " players -> ", DST)
