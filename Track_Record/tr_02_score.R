# =============================================================================
# Track Record, step 2: score the frozen 2024-2026 class predictions (rerun every January) and the Market Check logs.
#   1. checks every frozen file against MANIFEST.txt (stops if any changed)
#   2. classes: NFL results through the latest complete season (years 1-3 only), then per board
#      hit rate by grade band (A / B / C / D-F) with bootstrap intervals, Brier score vs the frozen pick-only benchmark
#      (any tier and top tier, per class), calibration by predicted-probability bin
#   3. market: for each logged week, rank correlation of our rank and of the market rank with the realized points over
#      replacement since the log (full PPR; replacement = QB24 / RB24 / WR36 / TE12 of each later season, season totals),
#      and for the disagreements (|gap| >= 25) how often our side was closer
# Writes scores/<date>_class_scores.csv, _calibration.csv, _market_scores.csv and scores/latest.json (read by the page).
# =============================================================================
suppressMessages({ library(dplyr); library(digest); library(jsonlite) })
source("tr_common.R"); TIERS <- list(QB = c(8, 16, 24), RB = c(8, 16, 24), WR = c(12, 24, 36), TE = c(6, 12, 18))
D8 <- format(Sys.Date(), "%Y-%m-%d"); dir.create("scores", showWarnings = FALSE)
man <- read.table(text = grep("^#", readLines("MANIFEST.txt"), value = TRUE, invert = TRUE), col.names = c("sha", "file", "x", "date"))
bad <- man$file[mapply(function(f, h) !file.exists(f) || digest(file = f, algo = "sha256") != h, man$file, man$sha)]
if (length(bad)) stop("frozen file changed or missing: ", paste(bad, collapse = ", "))
cat("manifest OK:", nrow(man), "frozen files\n")

res <- nfl_results(TIERS)
fz <- bind_rows(lapply(grep("^frozen/", man$file, value = TRUE), function(f) read.csv(f, stringsAsFactors = FALSE) %>%
  select(-any_of(c("best_finish_so_far", "tier_so_far", "seasons_seen", "through"))) %>% left_join(res, by = c("class", "pick")) %>% add_tier(TIERS)))
S <- score_board(fz)
S$bands <- S$bands %>% mutate(across(where(is.double), ~ round(.x, 3))); S$brier <- S$brier %>% mutate(across(where(is.double), ~ round(.x, 4)))
S$cal <- S$cal %>% mutate(across(where(is.double), ~ round(.x, 3)))
write.csv(S$bands, file.path("scores", paste0(D8, "_class_scores.csv")), row.names = FALSE)
write.csv(S$brier, file.path("scores", paste0(D8, "_class_brier.csv")), row.names = FALSE)
write.csv(S$cal, file.path("scores", paste0(D8, "_calibration.csv")), row.names = FALSE)
options(width = 200); cat("\nresults through season", max(res$through), "\n"); print(as.data.frame(S$bands)); print(as.data.frame(S$brier)); print(as.data.frame(S$cal))

# ---------- market logs ----------
w <- readRDS(file.path(CACHE, "nfl_weekly_raw.rds")) %>% filter(season_type == "REG")
w26 <- if (file.exists("../Football2_Dynasty/nfl_weekly_2026.rds")) readRDS("../Football2_Dynasty/nfl_weekly_2026.rds") %>% filter(season_type == "REG") else NULL
if (!is.null(w26)) w <- bind_rows(w, w26[, intersect(names(w26), names(w))])
w$position[w$position == "FB"] <- "RB"; N <- c(QB = 24, RB = 24, WR = 36, TE = 12)
logs <- grep("^market/", man$file, value = TRUE)
MS <- bind_rows(lapply(logs, function(f) { m <- read.csv(f, stringsAsFactors = FALSE); d0 <- as.Date(m$logged_on[1]); y0 <- as.integer(format(d0, "%Y"))
  # weeks after the log in the log's season (week of the log approximated by the stats on file then), and all later seasons
  lw <- m$log_week[1]; st <- w %>% filter(season > y0 | (season == y0 & week > lw)) %>% group_by(season, player_id, position) %>% summarise(pts = sum(fantasy_points_ppr, na.rm = TRUE), .groups = "drop") %>%
    group_by(season, position) %>% mutate(rep = sort(pts, decreasing = TRUE)[pmin(N[position[1]], n())]) %>% ungroup() %>% mutate(par = pmax(pts - rep, 0))
  r <- st %>% group_by(player_id) %>% summarise(realized_par = sum(par), seasons = n_distinct(season), .groups = "drop")
  x <- m %>% left_join(r, by = "player_id") %>% mutate(realized_par = coalesce(realized_par, 0), realized_rank = rank(-realized_par, ties.method = "average"))
  dis <- x %>% filter(abs(gap) >= 25)
  tibble(log = f, logged_on = m$logged_on[1], n = nrow(x), seasons_scored = paste(sort(unique(st$season)), collapse = " "),
         spearman_ours = cor(x$our_rank, x$realized_par, method = "spearman") * -1, spearman_market = cor(x$dd_rank, x$realized_par, method = "spearman") * -1,
         disagreements = nrow(dis), ours_closer = if (!nrow(st)) NA_real_ else mean(abs(dis$our_rank - dis$realized_rank) < abs(dis$dd_rank - dis$realized_rank)),
         note = ifelse(!nrow(st), "no games since the log yet", ifelse(max(st$season) <= y0, "log season still in progress: partial", ""))) }))
write.csv(MS, file.path("scores", paste0(D8, "_market_scores.csv")), row.names = FALSE); print(as.data.frame(MS))
writeLines(toJSON(list(scored_on = D8, through = max(res$through), bands = S$bands, brier = S$brier, cal = S$cal, market = MS,
                       counts = fz %>% count(board, class, seasons_seen)), auto_unbox = TRUE, digits = NA, na = "null"), file.path("scores", "latest.json"))
cat("wrote scores/latest.json\n")
