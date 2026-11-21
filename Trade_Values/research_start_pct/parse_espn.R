# Parse ESPN kona_player_info feeds into ownership CSVs; summarize Dynasty Daddy + board files.
suppressMessages(library(jsonlite))
setwd("C:/Users/kylem/Documents/R Studio/Football2/research_start_pct")
pos_map <- c("1" = "QB", "2" = "RB", "3" = "WR", "4" = "TE")
parse_year <- function(y) {
  j <- fromJSON(sprintf("espn_players_%d.json", y), simplifyVector = FALSE)
  rows <- lapply(j$players, function(p) {
    pl <- p$player; o <- pl$ownership
    g <- function(x) if (is.null(x)) NA_real_ else as.numeric(x)
    data.frame(espn_id = pl$id, name = pl$fullName,
               position = unname(pos_map[as.character(pl$defaultPositionId)]),
               pro_team_id = g(pl$proTeamId),
               percent_owned = g(o$percentOwned), percent_started = g(o$percentStarted),
               percent_change = g(o$percentChange), stringsAsFactors = FALSE)
  })
  d <- do.call(rbind, rows)
  cat(y, ": total players", nrow(d), "\n")
  d[!is.na(d$position), ]
}
for (y in c(2026, 2025, 2024)) {
  d <- parse_year(y)
  cat(y, ": QB/RB/WR/TE", nrow(d), " started>0:", sum(d$percent_started > 0, na.rm = TRUE),
      " NA started:", sum(is.na(d$percent_started)), " owned>0:", sum(d$percent_owned > 0, na.rm = TRUE), "\n")
  print(table(d$position))
  d <- d[order(-d$percent_started, -d$percent_owned), ]
  if (y == 2026) write.csv(d, "espn_ownership_2026.csv", row.names = FALSE)
  else write.csv(d, sprintf("espn_ownership_%d_check.csv", y), row.names = FALSE)
  print(head(d, 8), row.names = FALSE)
  if (y == 2026) {
    n <- nrow(d); mid <- which(d$percent_started < 50 & d$percent_started > 5)
    cat("--- samples ---\n")
    print(d[c(1:3, mid[c(1, length(mid) %/% 2, length(mid))], which(d$percent_started > 0 & d$percent_started < 1)[1:2], n - 1, n), ], row.names = FALSE)
    cat("quantiles started:\n"); print(quantile(d$percent_started, c(0, .5, .75, .9, .95, 1), na.rm = TRUE))
  }
}
cat("\n=== dd.js ===\n")
dd <- fromJSON(sub(";\\s*$", "", sub("^window.DD = ", "", paste(readLines("dd.js", warn = FALSE), collapse = ""))))
cat("asof", dd$asof, " dynasty rows", nrow(dd$dynasty), " redraft rows", nrow(dd$redraft), "\n"); print(head(dd$dynasty, 3))
for (f in c("dv_v4_board.csv", "dv_ros_2026_board.csv", "dv_dynasty_value_board_v2.csv")) {
  x <- read.csv(f); cat("\n===", f, "rows", nrow(x), "\n"); cat(names(x), sep = ", "); cat("\n")
}
