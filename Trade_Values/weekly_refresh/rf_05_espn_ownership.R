# =============================================================================
# Weekly refresh step 3d: ESPN % rostered and % started, for the "Market adjusted" values toggle (Kyle 2026-11-20)
#
#   1. one request to ESPN's public fantasy player feed (kona_player_info, default-league ownership for every player)
#   2. archive: <weekly_refresh>/espn_archive/espn_ownership_<date>.csv  (QB/RB/WR/TE: % rostered, % started, % change)
#      % started is this week's lineups only (byes and unset lineups pull it down), so it is archived every Tuesday and
#      not used yet; once a few weeks exist, a per-player average over non-bye healthy weeks can join the multiplier.
#   3. <site>/trade-values/data/own.js  (window.TVOWN), read by shared/engine.js when a league has "Market adjusted" on:
#        rel = min(1, % rostered / % rostered at the position's starter line)   lines: QB12, RB30, WR42, TE12 by % rostered
#        multiplier = LO at rel <= R0, rising linearly to 1 at rel >= R1        (0.85 / 0.5 / 0.9)
#      Sized from the Dynasty Daddy market gap on 2026-11-19: players rostered under a quarter of their position line sold
#      for a median 0.82x our value, those at 90%+ of it for 1.03x (Trade_Values/research_start_pct/).
#      Lines are read against the position because ESPN leagues are mostly 1QB: raw % rostered undersells QBs.
#
# Players are matched to the trade-values data (tv.js) by name + position (suffixes, accents and punctuation ignored).
# A tv.js player with no ESPN match gets no adjustment (the engine treats him as 1).
# Guarded in refresh.sh: on any error last week's own.js stays and the refresh goes on.
#
# usage: Rscript rf_05_espn_ownership.R <site folder>      (default: $SITE_DIR)
# =============================================================================
suppressMessages(library(jsonlite))
args <- commandArgs(trailingOnly = TRUE)
SITE <- if (length(args) >= 1) args[1] else Sys.getenv("SITE_DIR")
HERE <- tryCatch(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))), error = function(e) getwd())
if (is.na(HERE) || !nzchar(HERE)) HERE <- getwd()
SEASON <- as.integer(Sys.getenv("ESPN_SEASON", "2026"))
LINE <- c(QB = 12, RB = 30, WR = 42, TE = 12); LO <- 0.85; R0 <- 0.5; R1 <- 0.9
TODAY <- format(Sys.Date(), "%Y-%m-%d")
stopifnot(dir.exists(file.path(SITE, "trade-values", "data")))

# ---------- 1. ESPN feed (one request) ----------
url <- sprintf("https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/seasons/%d/segments/0/leaguedefaults/3?view=kona_player_info", SEASON)
filt <- '{"players":{"limit":2000,"sortPercOwned":{"sortPriority":1,"sortAsc":false}}}'
TEST_CSV <- Sys.getenv("ESPN_TEST_CSV")            # testing / backfill: an ownership CSV saved earlier instead of the request
if (nzchar(TEST_CSV)) { es <- read.csv(TEST_CSV, stringsAsFactors = FALSE, encoding = "UTF-8"); TODAY <- Sys.getenv("ESPN_TEST_DATE", TODAY)
} else {
  tmp <- tempfile(fileext = ".json")
  download.file(url, tmp, method = "libcurl", quiet = TRUE, headers = c("X-Fantasy-Filter" = filt, "Accept" = "application/json"))
  j <- fromJSON(tmp, simplifyVector = FALSE)
  pos_map <- c("1" = "QB", "2" = "RB", "3" = "WR", "4" = "TE")
  num <- function(x) if (is.null(x)) NA_real_ else as.numeric(x)
  es <- do.call(rbind, lapply(j$players, function(p) { pl <- p$player; o <- pl$ownership
    data.frame(espn_id = pl$id, name = pl$fullName, position = unname(pos_map[as.character(pl$defaultPositionId)]),
               pro_team_id = num(pl$proTeamId), percent_owned = num(o$percentOwned), percent_started = num(o$percentStarted),
               percent_change = num(o$percentChange), stringsAsFactors = FALSE) }))
}
es <- es[!is.na(es$position) & !is.na(es$percent_owned), ]
if (nrow(es) < 500) stop("ESPN returned only ", nrow(es), " QB/RB/WR/TE rows; keeping last week's own.js")
cat("ESPN rows (QB/RB/WR/TE):", nrow(es), "\n")

# ---------- 2. archive ----------
arch <- file.path(HERE, "espn_archive"); dir.create(arch, showWarnings = FALSE)
write.csv(cbind(date = TODAY, season = SEASON, es[order(-es$percent_owned), ]), file.path(arch, sprintf("espn_ownership_%s.csv", TODAY)), row.names = FALSE)
cat("archived", file.path(arch, sprintf("espn_ownership_%s.csv", TODAY)), "\n")

# ---------- 3. own.js ----------
key <- function(n, p) { n <- tolower(iconv(n, "UTF-8", "ASCII//TRANSLIT", sub = ""))
  n <- gsub("\\b(jr|sr|ii|iii|iv|v)\\b", "", n); paste0(gsub("[^a-z]", "", n), "|", p) }
es$k <- key(es$name, es$position)
es <- es[order(-es$percent_owned), ]; es <- es[!duplicated(es$k), ]
lines <- sapply(names(LINE), function(p) { v <- sort(es$percent_owned[es$position == p], decreasing = TRUE); v[min(LINE[[p]], length(v))] })
cat("% rostered at the position lines:", paste(names(lines), round(lines, 1), collapse = ", "), "\n")
tvtxt <- paste(readLines(file.path(SITE, "trade-values", "data", "tv.js"), warn = FALSE, encoding = "UTF-8"), collapse = "")
tv <- fromJSON(sub(";\\s*$", "", sub("^window\\.TV\\s*=\\s*", "", tvtxt)), simplifyVector = FALSE)
tvp <- unique(do.call(rbind, lapply(tv$players, function(x) data.frame(n = x$n, p = x$p, pool = if (is.null(x$pool)) 0 else x$pool, stringsAsFactors = FALSE))))
tvp$k <- key(tvp$n, tvp$p)
m <- match(tvp$k, es$k)
cat(sprintf("matched %d of %d trade-value players (%d of %d in the replacement pool)\n", sum(!is.na(m)), nrow(tvp),
            sum(!is.na(m) & tvp$pool == 1), sum(tvp$pool == 1)))
miss <- tvp$n[is.na(m) & tvp$pool == 1]; if (length(miss)) cat("not matched (no adjustment):", paste(head(miss, 40), collapse = "; "), "\n")
ok <- !is.na(m)
o <- setNames(lapply(which(ok), function(i) c(round(es$percent_owned[m[i]], 2), round(es$percent_started[m[i]], 2))), paste0(tvp$n[ok], "|", tvp$p[ok]))
out <- list(asof = TODAY, src = "ESPN default-league ownership", season = SEASON, lines = as.list(round(lines, 2)), line_ranks = as.list(LINE),
            lo = LO, r0 = R0, r1 = R1, o = o)
writeLines(paste0("window.TVOWN = ", toJSON(out, auto_unbox = TRUE, digits = NA), ";"), file.path(SITE, "trade-values", "data", "own.js"), useBytes = TRUE)
rel <- pmin(1, es$percent_owned / lines[es$position]); mult <- pmin(1, pmax(LO, LO + (1 - LO) * (rel - R0) / (R1 - R0)))
cat(sprintf("own.js written: %d players; discounted (multiplier < 1) among matched: %d\n", length(o), sum(mult[m[ok]] < 1, na.rm = TRUE)))
