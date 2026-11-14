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
dd <- list(asof = format(Sys.Date(), "%Y-%m-%d"), dynasty = pull("dynasty"), redraft = pull("redraft"))
writeLines(paste0("window.DD = ", toJSON(dd, auto_unbox = TRUE, digits = NA), ";"), file.path(out, "dd.js"), useBytes = TRUE)
cat("wrote", file.path(out, "dd.js"), " dynasty:", length(dd$dynasty), " redraft:", length(dd$redraft), "\n")
