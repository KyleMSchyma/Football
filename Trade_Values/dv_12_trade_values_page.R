# =============================================================================
# Prospect Actuary "Trade Values" page (IN DEVELOPMENT): Redraft and Dynasty sheets
# Reads dv_ros_2026_board.csv (dv_10) and dv_v4_board.csv (dv_11), fills tv_page_template.html,
# writes <site>/trade-values/index.html and <site>/trade-values/data/*.csv
# =============================================================================
source("dv_common.R"); suppressMessages(library(jsonlite))
site <- if (dir.exists("../ProspectActuary")) "../ProspectActuary" else "public_page"
out <- file.path(site, "trade-values"); dir.create(file.path(out, "data"), recursive = TRUE, showWarnings = FALSE)
r <- read.csv("dv_ros_2026_board.csv") %>% filter(value_100k > 0)
d <- read.csv("dv_v4_board.csv") %>% filter(value_100k >= 500)
red <- r %>% transmute(r = rank, n = name, p = pos, rp = rank_pos, tm = team, g = games_2026, ppg = ppg_2026, cppg = credible_ppg,
                       por = por_per_game, eg = exp_games_left, v = value_100k)
dyn <- d %>% transmute(r = rank, n = name, p = pos, rp = rank_pos, tm = team, a = age, dp = ifelse(draft_pick >= 262 | is.na(draft_pick), NA, draft_pick),
                       cppg = credible_ppg, p27 = ppg_2027, p30 = ppg_2030, s30 = S_2030, v = value_100k)
wk <- max(subset(readRDS("nfl_weekly_2026.rds"), season_type == "REG")$week)
asof <- sprintf("2026 stats through week %d. Updated %s.%s", wk, format(Sys.Date(), "%B %d, %Y"),
                if (wk >= 18) " The regular season is over, so redraft values are frozen at the last week with games left." else "")
js <- toJSON(list(asof = asof, redraft = red, dynasty = dyn), dataframe = "rows", auto_unbox = TRUE, digits = NA, na = "null")
js <- gsub("</", "<\\/", js, fixed = TRUE)
html <- sub("/*DATA*/", js, paste(readLines("tv_page_template.html", encoding = "UTF-8"), collapse = "\n"), fixed = TRUE)
writeLines(html, file.path(out, "index.html"), useBytes = TRUE)
write.csv(r %>% select(rank, rank_pos, name, pos, team, games_2026, ppg_2026, credible_ppg, replacement_ppg, por_per_game,
                       exp_games_left, trade_value = value_100k), file.path(out, "data", "redraft_trade_values.csv"), row.names = FALSE)
write.csv(d %>% select(rank, rank_pos, name, pos, team, age, draft_pick, credible_ppg, ppg_2027, ppg_2028, ppg_2030, still_playing_2030 = S_2030,
                       trade_value = value_100k), file.path(out, "data", "dynasty_trade_values.csv"), row.names = FALSE)
cat("wrote", file.path(out, "index.html"), " redraft rows:", nrow(red), " dynasty rows:", nrow(dyn), "\n")
