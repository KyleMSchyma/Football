# =============================================================================
# Dynasty Model, step 9: the public Prospect Actuary page
# Fills dv_page_template.html with the board, life tables, age PDP and backtest, and writes
# <site>/dynasty/index.html plus <site>/dynasty/data/*.csv. <site> is ../ProspectActuary on Kyle's PC,
# or ./public_page when that folder is not there.
# =============================================================================
source("dv_common.R"); suppressMessages(library(jsonlite))
cat("== Dynasty step 9: public page ==\n")
site <- if (dir.exists("../ProspectActuary")) "../ProspectActuary" else "public_page"
out <- file.path(site, "dynasty"); dir.create(file.path(out, "data"), recursive = TRUE, showWarnings = FALSE)

b <- read.csv("dv_dynasty_value_board.csv")
players <- b %>% transmute(r = rank_overall, rp = rank_pos, n = name, p = pos, tm = team, a = age_2027,
  d = ifelse(draft == "UDFA", "UDFA", ifelse(draft == "R4-7", "R4-7", draft)), sc = score, tr = as.character(tier),
  tv = trade_value, wn = win_now_3yr, e = exp_alive_seasons, s3 = S_2029, b = as.integer(grepl("^2025", basis)))
km <- read.csv("dv_km_life_tables.csv") %>% filter(grepl("^startable", view)) %>% select(view, group, t, S)
age <- read.csv("dv_pdp_age.csv") %>% transmute(pos, age, score = round(score, 2))
eff <- read.csv("dv_effect_sizes.csv") %>% filter(change == "2 years older")
age2 <- as.list(setNames(eff$score_change_pct, eff$pos))
bt <- read.csv("dv_value_backtest_metrics.csv") %>%
  mutate(players = recode(players, "all" = "Everyone", "startable at landmark" = "Startable at the time",
                          "QB startable" = "Startable QBs", "RB startable" = "Startable RBs", "WR startable" = "Startable WRs",
                          "TE startable" = "Startable TEs")) %>%
  select(players, n, spearman_model, spearman_naive, rmse_model, rmse_naive)
bt <- bind_rows(bt %>% filter(players != "Everyone"), bt %>% filter(players == "Everyone"))
wk <- max(readRDS("nfl_weekly_2026.rds")$week)
asof <- sprintf("Values as of 2026 week %d (2026 pro-rated to 17 games). Seasons valued: 2027-2036. Updated %s.", wk, format(Sys.Date(), "%B %d, %Y"))
# the findings card reads the backtest row by its original label
bt_json <- bt; bt_json$players[bt_json$players == "Startable at the time"] <- "startable at landmark"

data <- list(asof = asof, players = players, km = km, age = age, age2 = age2, bt = bt_json)
js <- toJSON(data, dataframe = "rows", auto_unbox = TRUE, digits = NA, na = "null")
js <- gsub("</", "<\\/", js, fixed = TRUE)
html <- paste(readLines("dv_page_template.html", encoding = "UTF-8"), collapse = "\n")
html <- sub("/*DATA*/", js, html, fixed = TRUE)
# the backtest table shows friendlier labels than the findings key
html <- sub('D.bt.map(r=>`<tr><td>${esc(r.players)}', 'D.bt.map(r=>`<tr><td>${esc(r.players==="startable at landmark"?"Startable at the time":r.players)}', html, fixed = TRUE)
writeLines(html, file.path(out, "index.html"), useBytes = TRUE)
write.csv(b %>% select(-player_id), file.path(out, "data", "dv_dynasty_value_board.csv"), row.names = FALSE)
file.copy(c("dv_km_life_tables.csv", "dv_value_backtest_metrics.csv", "dv_pdp_age.csv", "dv_trade_anchor_check.csv"),
          file.path(out, "data"), overwrite = TRUE)
cat("wrote", file.path(out, "index.html"), " (", round(file.size(file.path(out, "index.html")) / 1024), "KB ) players:", nrow(players), "\n")
