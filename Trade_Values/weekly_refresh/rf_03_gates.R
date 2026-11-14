# =============================================================================
# Weekly refresh, output gates (FABLE build). Runs after the values and the page are rebuilt and BEFORE anything is
# committed or pushed. Any failed gate makes this script exit with an error, and refresh.sh then stops with nothing pushed.
#   usage: Rscript rf_03_gates.R    (env: DYN_DIR, SITE_DIR, ARCHIVE_DIR)
# Gates
#   1. the latest week of 2026 stats has every team that finished a game that week (nflverse schedule)
#   2. no missing values: board values, every player's projections in the page data, every 2027 pick value
#   3. default-league replacement lines inside the range seen at the same point of 2016-2025 (+-2 PPG)
#   4. rookie-pick multiplier between 0.7 and 1.6 (its 2016-2022 bootstrap interval is about 0.80-1.47)
#   5. top-50 turnover vs last week's archive at most 15 players on each sheet (2021-2025, weeks 8-17: the redraft
#      top 50 lost at most 8 players from one week to the next, median 3-4); skipped before week 8 and in week 1 of archiving
#   6. reconciliation: the R page math matches dv_10 / dv_11 (dv_13 log, < 0.001), and the built Trade Values page,
#      run in headless Edge, matches R for five test leagues within 100 points on the 100,000 scale (rounding of the
#      stored data gives up to about 40)
# Writes gates_report.txt in the log folder (refresh.sh passes the path as the first argument).
# =============================================================================
suppressMessages({ library(dplyr); library(jsonlite) })
a <- commandArgs(trailingOnly = TRUE); rep_file <- if (length(a)) a[1] else "gates_report.txt"
DYN <- normalizePath(Sys.getenv("DYN_DIR", "../Football2_Dynasty")); SITE <- normalizePath(Sys.getenv("SITE_DIR", "../ProspectActuary"))
ARCH <- Sys.getenv("ARCHIVE_DIR", file.path(getwd(), "archive"))
res <- list(); gate <- function(name, ok, detail) { res[[length(res) + 1]] <<- data.frame(gate = name, pass = isTRUE(ok), detail = detail); cat(sprintf("[%s] %s: %s\n", if (isTRUE(ok)) "PASS" else "FAIL", name, detail)) }
FORCE <- Sys.getenv("FORCE_GATE_FAIL") != ""

# 1. teams in the latest week
w <- readRDS(file.path(DYN, "nfl_weekly_2026.rds")) %>% filter(season_type == "REG"); wk <- max(w$week)
sch <- tryCatch(as.data.frame(nflreadr::load_schedules(2026)), error = function(e) readRDS(file.path(DYN, "cache_role/schedules.rds")))
done <- sch %>% filter(season == 2026, game_type == "REG", week == wk, !is.na(result))
teams <- unique(c(done$home_team, done$away_team)); have <- unique(w$team[w$week == wk])
miss <- setdiff(teams, have)
gate("1 latest week complete", length(teams) > 0 && !length(miss), sprintf("week %d: %d teams finished a game, %d in the stats%s", wk, length(teams),
     length(intersect(teams, have)), if (length(miss)) paste0("; missing ", paste(miss, collapse = " ")) else ""))

# 2. missing values
rb <- read.csv(file.path(DYN, "dv_ros_2026_board.csv")); db <- read.csv(file.path(DYN, "dv_v4_board.csv")); P <- readRDS(file.path(DYN, "dv_league_presets.rds"))
na_rd <- sum(sapply(P$rd, function(k) sum(sapply(k, function(x) anyNA(x[2:3])))))
pool_ids <- P$base$player_id[P$base$pool == 1]
na_dy <- sum(sapply(P$dy, function(k) sum(sapply(k[intersect(names(k), pool_ids)], anyNA))))
pk_na <- sum(is.na(unlist(P$picks$pp[, c("P1", "P2", "P3", "P4")]))) + sum(sapply(P$picks$cal, function(x) anyNA(unlist(x))))
gate("2 no missing values", !anyNA(rb$value_100k) && !anyNA(db$value_100k) && na_rd == 0 && na_dy == 0 && pk_na == 0 && !FORCE,
     sprintf("NA: redraft board %d, dynasty board %d, page redraft inputs %d, pool players' dynasty inputs %d, pick inputs %d%s",
             sum(is.na(rb$value_100k)), sum(is.na(db$value_100k)), na_rd, na_dy, pk_na, if (FORCE) " (FORCE_GATE_FAIL set)" else ""))

# 3. replacement lines
lim <- read.csv(file.path(getwd(), "rf_gate_limits.csv"))
rp <- rb %>% distinct(pos, replacement_ppg) %>% left_join(lim, by = "pos")
okr <- all(rp$replacement_ppg >= rp$lo & rp$replacement_ppg <= rp$hi)
gate("3 replacement lines", okr, paste(sprintf("%s %.2f [%.1f-%.1f]", rp$pos, rp$replacement_ppg, rp$lo, rp$hi), collapse = ", "))

# 4. pick multiplier
f <- P$picks$f; gate("4 pick multiplier", is.numeric(f) && f >= 0.7 && f <= 1.6, sprintf("%.3f%s", f, if (!is.null(P$picks$f_ci)) sprintf(" (95%% %.2f-%.2f)", P$picks$f_ci[1], P$picks$f_ci[2]) else ""))

# 5. top-50 turnover vs the last archive
prev <- sort(list.files(ARCH, pattern = "_dynasty\\.csv$"), decreasing = TRUE)
if (wk < 8 || !length(prev)) gate("5 top-50 turnover", TRUE, if (wk < 8) "skipped before week 8" else "no earlier archive yet (first archived week)") else {
  pd <- read.csv(file.path(ARCH, prev[1])); pr <- read.csv(file.path(ARCH, sub("_dynasty", "_redraft", prev[1])))
  t_d <- length(setdiff(head(pd$name[order(-pd$value_100k)], 50), head(db$name[order(-db$value_100k)], 50)))
  t_r <- length(setdiff(head(pr$name[order(-pr$value_100k)], 50), head(rb$name[order(-rb$value_100k)], 50)))
  gate("5 top-50 turnover", t_d <= 15 && t_r <= 15, sprintf("vs %s: dynasty %d, redraft %d players left the top 50 (limit 15)", sub("_dynasty.csv", "", prev[1]), t_d, t_r)) }

# 6. reconciliation: R page math vs the models, then the built page in headless Edge vs R
lg <- readLines(file.path(DYN, "dv_13_log.txt"), warn = FALSE); l <- grep("page math vs dv_10 / dv_11", lg, value = TRUE)
nums <- as.numeric(regmatches(l, gregexpr("[0-9.]+(e-?[0-9]+)?", l))[[1]]); nums <- tail(nums, 2)
gate("6a R page math = models", length(nums) == 2 && all(nums < 1e-3), sprintf("max abs diff dynasty %s, redraft %s", nums[1], nums[2]))
edge <- c("C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe", "C:/Program Files/Microsoft/Edge/Application/msedge.exe"); edge <- edge[file.exists(edge)][1]
exp_js <- file.path(DYN, "dv_15_expected.js"); chk_js <- file.path(DYN, "dv_15_check.js")
if (is.na(edge) || !file.exists(exp_js)) gate("6b page vs R (browser)", FALSE, "Edge or dv_15_expected.js not found") else {
  html <- paste(readLines(file.path(SITE, "trade-values", "index.html"), encoding = "UTF-8", warn = FALSE), collapse = "\n")
  chk <- sub("^//[^\n]*\n", "", paste(readLines(chk_js, warn = FALSE), collapse = "\n")); chk <- sub(";\\s*$", "", trimws(chk))
  m <- gregexpr("<script>[\\s\\S]*?</script>", html, perl = TRUE); sc <- regmatches(html, m)[[1]]; j <- grep("function compute()", sc, fixed = TRUE)[1]
  s <- sc[j]; k <- tail(gregexpr("})();", s, fixed = TRUE)[[1]], 1)
  s2 <- paste0(substr(s, 1, k - 1), "\ntry { document.title = 'DV15:' + JSON.stringify(", chk, "); } catch(e) { document.title = 'DV15ERR:' + e.message; }\n", substr(s, k, nchar(s)))
  html2 <- sub(s, s2, html, fixed = TRUE)
  html2 <- sub("<head>", paste0("<head><base href=\"file:///", gsub("\\\\", "/", file.path(SITE, "trade-values")), "/\"><script>",
                                paste(readLines(exp_js, warn = FALSE), collapse = "\n"), "</script>"), html2, fixed = TRUE)
  tmp <- file.path(tempdir(), "dv15_check.html"); writeLines(html2, tmp, useBytes = TRUE)
  # Edge is a GUI program: its --dump-dom output is only captured when PowerShell starts it with a redirected stdout.
  # A separate profile folder keeps it from attaching to an Edge window the user has open.
  outf <- normalizePath(file.path(tempdir(), "dv15_dom.txt"), mustWork = FALSE); prof <- normalizePath(file.path(tempdir(), "edge_profile"), mustWork = FALSE)
  url <- paste0("file:///", gsub(" ", "%20", gsub("\\\\", "/", normalizePath(tmp))))
  ps <- sprintf("Start-Process -FilePath '%s' -ArgumentList '--headless=new','--disable-gpu','--no-first-run','--user-data-dir=%s','--allow-file-access-from-files','--virtual-time-budget=20000','--dump-dom','%s' -RedirectStandardOutput '%s' -Wait -NoNewWindow",
                normalizePath(edge), prof, url, outf)
  system2("powershell.exe", c("-NoProfile", "-Command", shQuote(ps, type = "cmd")), stdout = FALSE, stderr = FALSE)
  out <- if (file.exists(outf)) readLines(outf, warn = FALSE, encoding = "UTF-8") else character(0)
  ttl <- regmatches(paste(out, collapse = "\n"), regexpr("<title>[^<]*</title>", paste(out, collapse = "\n")))
  ttl <- gsub("&quot;", "\"", gsub("&amp;", "&", sub("</title>", "", sub("<title>", "", ttl))))
  if (!length(ttl) || !startsWith(ttl, "DV15:")) gate("6b page vs R (browser)", FALSE, paste("page check did not run:", substr(paste(ttl, collapse = ""), 1, 200))) else {
    r <- fromJSON(sub("^DV15:", "", ttl)); mx <- max(c(r$dynasty_max_diff, r$redraft_max_diff, r$pick_max_diff))
    write.csv(r, file.path(dirname(rep_file), "dv15_browser_check.csv"), row.names = FALSE)
    gate("6b page vs R (browser)", mx < 100 && all(r$n_dynasty > 100), sprintf("5 leagues, max |page - R| players %.1f / %.1f (dynasty / redraft), picks %.1f, on the 100k scale (limit 100)",
         max(r$dynasty_max_diff), max(r$redraft_max_diff), max(r$pick_max_diff))) } }

R <- bind_rows(res); write.csv(R, rep_file, row.names = FALSE)
if (!all(R$pass)) { cat("\nGATES FAILED:", paste(R$gate[!R$pass], collapse = "; "), "\n"); quit(status = 2) }
cat("\nall gates passed\n")
