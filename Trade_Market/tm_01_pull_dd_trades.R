# tm_01_pull_dd_trades.R
# "Trade" value method, step 1: pull real trades from the Dynasty Daddy Trade Database.
# Permission: Dynasty Daddy's owner told Kyle he could use it (2026-11-22).
# Polite pull: one request every ~2.5 s, 500 trades per page, weekly windows, resumable.
# Raw files contain league ids: they stay in this private folder and are NEVER committed.
#
# Run:  Rscript tm_01_pull_dd_trades.R        (re-run any time; finished weeks are skipped)

suppressPackageStartupMessages({ library(httr); library(jsonlite) })

OUT   <- file.path(Sys.getenv("TM_ROOT", getwd()), "raw")   # TM_ROOT = the dd_trades folder (set by tm_weekly.sh)
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
URL   <- "https://api.dynasty-daddy.com/api/v1/trade/search"
PAUSE <- 2.5
PAGE  <- 500

# Only formats our settings can express: 8-14 teams, half/full PPR, no best ball.
# TE premium and starter count kept wide; mapped to our options in step 2.
base_body <- list(
  sideA = list(), sideB = list(),
  isSuperflex = c(FALSE, TRUE),
  starters = 6:14,
  teams = c(8, 10, 12, 14),
  ppr = c(0.5, 1),
  tep = c(0, 0.25, 0.5, 0.75, 1),
  maxAssetCount = 8,
  isBestball = list(FALSE)
)

JOBS <- list(
  list(type = "Dynasty", start = as.Date("2026-05-01")),   # from rookie drafts on
  list(type = "Redraft", start = as.Date("2026-09-01"))    # 2026 season
)
TYPES <- strsplit(Sys.getenv("TM_TYPES", "Dynasty,Redraft"), ",")[[1]]   # weekly job: TM_TYPES=Dynasty
JOBS <- Filter(function(j) j$type %in% TYPES, JOBS)
end_all <- Sys.Date() + 1

post <- function(body, tries = 5) {
  for (i in seq_len(tries)) {
    r <- tryCatch(POST(URL, body = toJSON(body, auto_unbox = TRUE), content_type_json(),
                       user_agent("ProspectActuary research (permission from Dynasty Daddy)"),
                       timeout(60)), error = function(e) NULL)
    Sys.sleep(PAUSE)
    if (!is.null(r) && status_code(r) == 200) return(fromJSON(content(r, "text", encoding = "UTF-8"), simplifyVector = FALSE))
    code <- if (is.null(r)) "no response" else status_code(r)
    message("  retry ", i, " (", code, ")"); Sys.sleep(PAUSE * 4 * i)
  }
  stop("giving up after ", tries, " tries")
}

flat <- function(tr) data.frame(
  transaction_id = tr$transaction_id,
  date = tr$transaction_date,
  platform = tr$platform %||% NA,
  league_id = tr$league_id %||% NA,
  season = tr$season %||% NA,
  league_type = tr$league_type %||% NA,
  teams = tr$teams %||% NA, starters = tr$starters %||% NA,
  ppr = tr$ppr %||% NA, tep = tr$tep %||% NA,
  sf = isTRUE(tr$is_superflex), bestball = isTRUE(tr$is_bestball),
  sidea = paste(unlist(tr$sidea), collapse = "|"),
  sideb = paste(unlist(tr$sideb), collapse = "|"),
  stringsAsFactors = FALSE)
`%||%` <- function(a, b) if (is.null(a)) b else a

for (job in JOBS) {
  starts <- seq(job$start, end_all - 1, by = "7 days")
  for (k in seq_along(starts)) {
    s <- starts[k]; e <- min(s + 7, end_all)
    f <- file.path(OUT, sprintf("%s_%s.rds", tolower(job$type), format(s)))
    done_week <- e <= Sys.Date() - 1          # a finished week is never re-pulled
    if (file.exists(f) && done_week) next
    body <- c(base_body, list(leagueType = job$type,
                              startDate = paste0(format(s), "T00:00:00Z"),
                              endDate = paste0(format(e), "T00:00:00Z"),
                              pageLength = PAGE))
    rows <- list(); p <- 1; total <- Inf
    while ((p - 1) * PAGE < total) {
      j <- post(c(body, list(page = p)))
      total <- j$total_count
      if (length(j$trades) == 0) break
      rows[[p]] <- do.call(rbind, lapply(j$trades, flat))
      message(sprintf("%s %s page %d: %d of %d", job$type, format(s), p, min(p * PAGE, total), total))
      p <- p + 1
    }
    d <- if (length(rows)) do.call(rbind, rows) else data.frame()
    if (nrow(d)) d <- d[!duplicated(d$transaction_id), ]
    attr(d, "reported_total") <- total
    saveRDS(d, f)
    message(sprintf("saved %s: %d trades (DD reported %s)", basename(f), nrow(d), total))
  }
}
message("done")
