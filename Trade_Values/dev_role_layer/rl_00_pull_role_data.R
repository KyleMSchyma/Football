# =============================================================================
# Role layer, step 0: pull depth charts, injury reports, weekly rosters and snap counts from nflverse (nflreadr)
# Caches raw pulls in cache_role/ (one file per source; 2026 is re-pulled every run, history only if missing).
# Usage: ./run.sh rl_00_pull_role_data.R rl_00_log.txt
# =============================================================================
suppressMessages(library(dplyr))
dir.create("cache_role", showWarnings = FALSE)
YRS <- 2012:2026
# bind pieces whose column types differ between seasons (character wins); date-times kept as text
safe_bind <- function(L) {
  L <- lapply(L, function(x) { x[] <- lapply(x, function(c) if (inherits(c, "POSIXt") || inherits(c, "Date")) as.character(c) else c); x })
  nm <- unique(unlist(lapply(L, names)))
  bad <- nm[sapply(nm, function(n) length(unique(unlist(lapply(L, function(x) if (n %in% names(x)) class(x[[n]])[1]))))) > 1]
  L <- lapply(L, function(x) { for (n in intersect(bad, names(x))) x[[n]] <- as.character(x[[n]]); x })
  bind_rows(L)
}
pull <- function(name, f, yrs = YRS) {
  fn <- file.path("cache_role", paste0(name, ".rds"))
  old <- if (file.exists(fn)) readRDS(fn) else NULL
  need <- if (is.null(old)) yrs else 2026
  got <- lapply(need, function(y) tryCatch({ x <- as.data.frame(f(y)); if (!"season" %in% names(x) || all(is.na(x$season))) x$season <- y; x },
                                           error = function(e) { cat(name, y, "failed:", conditionMessage(e), "\n"); NULL }))
  got <- Filter(function(x) !is.null(x) && nrow(x), got)
  if (!length(got)) {                                  # weekly refresh: a failed pull keeps last week's file
    if (is.null(old)) stop(name, ": pull failed and no cached file")
    cat(name, ": PULL FAILED, REUSED last cached file (seasons through ", max(old$season, na.rm = TRUE), ")\n", sep = ""); return(invisible(old)) }
  got <- safe_bind(got)
  if (!is.null(old)) got <- safe_bind(list(old %>% filter(season != 2026), got))
  saveRDS(got, fn)
  cat(name, ": ", nrow(got), " rows; seasons ", paste(sort(unique(got$season)), collapse = " "), "\n", sep = "")
  invisible(got)
}
dc  <- pull("depth_charts", function(y) nflreadr::load_depth_charts(y))
inj <- pull("injuries", function(y) nflreadr::load_injuries(y))
ros <- pull("rosters_weekly", function(y) nflreadr::load_rosters_weekly(y))
snp <- pull("snap_counts", function(y) nflreadr::load_snap_counts(y), 2013:2026)
sch <- pull("schedules", function(y) nflreadr::load_schedules(y))
cat("\ncolumns:\n"); for (x in list(dc = dc, inj = inj, ros = ros, snp = snp, sch = sch)) print(names(x))
