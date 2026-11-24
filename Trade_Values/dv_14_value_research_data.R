# =============================================================================
# Prospect Actuary "Value Research" page: weekly snapshot of Dynasty Daddy trade values
# Pulls the public Dynasty Daddy values API (https://dynasty-daddy.com/help/api-documentation; no key,
# "please cache responses") once per weekly refresh and writes <site>/value-research/data/dd.js, which the
# page reads. Only skill players with a superflex value above 0 are kept: [name_id, position, team, sf_trade_value].
# Run from dv_12_trade_values_page.R. A failure here leaves the previous dd.js in place.
# =============================================================================
suppressMessages(library(jsonlite))
site <- if (exists("SITE_DIR")) SITE_DIR else if (nzchar(Sys.getenv("SITE_DIR"))) Sys.getenv("SITE_DIR") else if (dir.exists("../ProspectActuary")) "../ProspectActuary" else "public_page"
out <- file.path(site, "value-research", "data"); dir.create(out, recursive = TRUE, showWarnings = FALSE)
pull <- function(kind) {
  x <- fromJSON(sprintf("https://api.dynasty-daddy.com/api/v1/values/%s", kind))
  x <- x[x$position %in% c("QB", "RB", "WR", "TE") & !is.na(x$sf_trade_value) & x$sf_trade_value > 0, ]
  x <- x[order(-x$sf_trade_value), ]
  if (nrow(x) < 100) stop("Dynasty Daddy ", kind, " values look incomplete (", nrow(x), " players)")
  lapply(seq_len(nrow(x)), function(i) list(x$name_id[i], x$position[i], ifelse(is.na(x$team[i]), "", x$team[i]), x$sf_trade_value[i]))
}
# 2027 rookie picks, rounds 1-4 (Kyle 2026-11-24, Nov 28 batch): Market Check ranks each round among the market's players.
# Kept as [name_id, position, sf_trade_value]; a failure or an unexpected format leaves the list empty (players unaffected).
pull_picks <- function() tryCatch({
  x <- fromJSON("https://api.dynasty-daddy.com/api/v1/values/dynasty")
  k <- grepl("^2027", x$name_id) & grepl("(1st|2nd|3rd|4th)", tolower(paste(x$name_id, x$full_name))) & !is.na(x$sf_trade_value) & x$sf_trade_value > 0
  x <- x[k, ]; x <- x[order(-x$sf_trade_value), ]
  lapply(seq_len(nrow(x)), function(i) list(x$name_id[i], x$position[i], x$sf_trade_value[i]))
}, error = function(e) { message("Dynasty Daddy picks: ", conditionMessage(e)); list() })
dd <- list(asof = format(Sys.Date(), "%Y-%m-%d"), dynasty = pull("dynasty"), redraft = pull("redraft"), picks = pull_picks())
writeLines(paste0("window.DD = ", toJSON(dd, auto_unbox = TRUE, digits = NA), ";"), file.path(out, "dd.js"), useBytes = TRUE)
cat("wrote", file.path(out, "dd.js"), " dynasty:", length(dd$dynasty), " redraft:", length(dd$redraft), " 2027 picks:", length(dd$picks), "\n")
