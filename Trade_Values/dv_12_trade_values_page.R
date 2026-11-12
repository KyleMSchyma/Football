# =============================================================================
# Prospect Actuary "Trade Values" page (IN DEVELOPMENT): Redraft and Dynasty sheets, customizable by league
# Reads dv_league_presets.rds (dv_13: projections for every scoring preset + 2027 rookie pick profiles) and the default
# boards (dv_ros_2026_board.csv from dv_10, dv_v4_board.csv from dv_11), fills tv_page_template.html,
# writes <site>/trade-values/index.html, <site>/trade-values/data/*.csv and <site>/trade-values/data/tv.js (read by /trade-calculator/).
# The page computes replacement lines, values and pick values in the browser for the league settings a visitor picks.
# =============================================================================
source("dv_common.R"); suppressMessages(library(jsonlite))
site <- if (dir.exists("../ProspectActuary")) "../ProspectActuary" else "public_page"
out <- file.path(site, "trade-values"); dir.create(file.path(out, "data"), recursive = TRUE, showWarnings = FALSE)
P <- readRDS("dv_league_presets.rds")
r3 <- function(x) round(unname(x), 3)
keys_of <- function(ps) names(P$rd)[startsWith(names(P$rd), paste0(ps, "_"))]
pl <- lapply(seq_len(nrow(P$base)), function(i) { b <- P$base[i, ]
  k <- setNames(lapply(keys_of(b$pos), function(key) { x <- c(P$rd[[key]][[b$player_id]], P$dy[[key]][[b$player_id]])
    if (anyNA(x[4:12])) r3(x[1:3]) else r3(x) }), keys_of(b$pos))
  o <- list(n = b$name, p = b$pos, tm = b$team, a = if (is.na(b$age)) NULL else round(b$age, 1),
            dp = if (is.na(b$dp) || b$dp >= 262) NULL else b$dp, g = b$games, pool = b$pool, k = k)
  if (!is.null(P$rd_frozen)) { o$r <- setNames(lapply(keys_of(b$pos), function(key) { x <- P$rd_frozen[[key]][[b$player_id]]
    if (is.null(x)) NULL else r3(x) }), keys_of(b$pos)) }
  o })
# 2027 rookie picks (pre-draft model, no draft capital): per prospect his tier probabilities and age adjustment per scoring key,
# per scoring key the tier calibration (games, PPG, spread by tier and season). Names stay off the page (Kyle: picks only).
pp <- P$picks$pp
pros <- lapply(seq_len(nrow(pp)), function(j) { ps <- pp$pos[j]
  list(p = ps, P = r3(unlist(pp[j, c("P1", "P2", "P3", "P4")])), d = setNames(lapply(keys_of(ps), function(key) r3(P$picks$D[[key]][[as.character(j)]])), keys_of(ps))) })
cal <- lapply(P$picks$cal, function(x) lapply(x, r3))
wk <- max(subset(readRDS("nfl_weekly_2026.rds"), season_type == "REG")$week)
asof <- sprintf("2026 stats through week %d. Updated %s.%s", wk, format(Sys.Date(), "%B %d, %Y"),
                if (wk >= 18) " The regular season is over, so redraft values are frozen at the last week with games left." else "")
js <- toJSON(list(asof = asof, v = P$v, players = pl, sd = lapply(P$sdk, r3), picks = list(cal = cal, pros = pros)),
             auto_unbox = TRUE, digits = NA, na = "null", null = "null")
js <- gsub("</", "<\\/", js, fixed = TRUE)
html <- sub("/*DATA*/", js, paste(readLines("tv_page_template.html", encoding = "UTF-8"), collapse = "\n"), fixed = TRUE)
writeLines(html, file.path(out, "index.html"), useBytes = TRUE)
# same data as a standalone script for the Trade Calculator page (/trade-calculator/ loads ../trade-values/data/tv.js)
writeLines(paste0("window.TV = ", js, ";"), file.path(out, "data", "tv.js"), useBytes = TRUE)
# downloads: the default league (12 teams, superflex, full PPR, QB24 / RB24 / WR36 / TE12 lines)
r <- read.csv("dv_ros_2026_board.csv") %>% filter(value_100k > 0)
d <- read.csv("dv_v4_board.csv") %>% filter(value_100k >= 500)
write.csv(r %>% select(rank, rank_pos, name, pos, team, games_2026, ppg_2026, credible_ppg, replacement_ppg, por_per_game,
                       exp_games_left, trade_value = value_100k), file.path(out, "data", "redraft_trade_values.csv"), row.names = FALSE)
write.csv(d %>% select(rank, rank_pos, name, pos, team, age, draft_pick, credible_ppg, ppg_2027, ppg_2028, ppg_2030, still_playing_2030 = S_2030,
                       trade_value = value_100k), file.path(out, "data", "dynasty_trade_values.csv"), row.names = FALSE)
cat("wrote", file.path(out, "index.html"), " players:", length(pl), " 2027 prospects:", length(pros),
    " page size:", round(file.size(file.path(out, "index.html")) / 1024), "KB\n")
# Value Research page: refresh the Dynasty Daddy snapshot it compares against (a failure keeps last week's copy)
tryCatch(source("dv_14_value_research_data.R"), error = function(e) cat("Value Research: Dynasty Daddy pull failed:", conditionMessage(e), "\n"))
