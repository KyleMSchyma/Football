# =============================================================================
# Check for the grade boards' league-aware Value column (../shared/league-value.js on the site).
# For several leagues, prices every board row in R the way the browser does (the row's rounded tier
# probabilities and 0.1-grid age from dv_rookie_board_values.csv, the dv_13 age table, replacement lines and
# the 100k scale from league_values()) and, for 2027 prospects, the rookie-pick value from league_values().
# Writes dv_board_value_check.csv (compared against the pages in a browser) and prints board vs pick differences.
# =============================================================================
suppressMessages(library(dplyr)); POSITIONS <- c("QB", "RB", "WR", "TE")
grab <- function(file, nms) for (e in parse(file)) if (is.call(e) && identical(deparse(e[[1]]), "<-") && is.name(e[[2]]) &&
  as.character(e[[2]]) %in% nms) eval(e, globalenv())
grab("dv_10_ros_value.R", c("rep_lines", "MIN_G_REP", "LG_DEFAULT")); grab("dv_13_league_presets.R", c("stoploss", "league_values"))
P <- readRDS("dv_league_presets.rds"); B <- read.csv("dv_rookie_board_values.csv", stringsAsFactors = FALSE)
LG <- list(
  default = list(lg = LG_DEFAULT, ppr = 1, tep = 0, ptd = 4),
  oneQB   = list(lg = modifyList(LG_DEFAULT, list(sf = 0)), ppr = 1, tep = 0, ptd = 4),
  halfPPR = list(lg = LG_DEFAULT, ppr = 0.5, tep = 0, ptd = 4),
  TEP1    = list(lg = LG_DEFAULT, ppr = 1, tep = 1, ptd = 4),
  teams10 = list(lg = modifyList(LG_DEFAULT, list(teams = 10)), ppr = 1, tep = 0, ptd = 4))
out <- list()
for (nm in names(LG)) { L <- LG[[nm]]
  lv <- league_values(P, L$lg, ppr = L$ppr, tep = L$tep, ptd = L$ptd)
  top <- max(lv$players$dynasty, na.rm = TRUE)
  key <- c(QB = paste0("QB_p", L$ptd, "f0"), RB = paste0("RB_r", L$ppr, "f0"), WR = paste0("WR_r", L$ppr, "f0"), TE = paste0("TE_t", L$ppr + L$tep, "f0"))
  rep <- setNames(lv$rep$rep_ppg, lv$rep$pos)
  val <- sapply(seq_len(nrow(B)), function(j) { ps <- B$position[j]; k <- key[[ps]]; cc <- P$picks$cal[[k]]
    q <- c(B$p_top[j], max(B$p_top2[j], B$p_top[j])); q <- c(q, max(B$p_any[j], q[2])); pr4 <- c(q[1], q[2] - q[1], q[3] - q[2], 1 - q[3])
    i <- min(length(P$agetab$grid), max(1, round((B$age[j] - P$agetab$grid[1]) / 0.1) + 1)); d <- c(0, round(P$agetab$t[[k]][i, ], 3))
    sum(rep(pr4, each = 4) * rep(P$v^(1:4), 4) * cc$G * stoploss(cc$mu + rep(d, 4), rep[[ps]], cc$sd)) })
  sl <- lv$slots %>% transmute(nmk = gsub("[^a-z]", "", tolower(name)), pos, pick_value = 1e5 * val / top)
  o <- B %>% mutate(league = nm, value_R = 1e5 * val / top, nmk = gsub("[^a-z]", "", tolower(name))) %>%
    left_join(sl, by = c("nmk", "position" = "pos")) %>% mutate(pick_value = ifelse(class == 2027 & board != "post", pick_value, NA))
  cat(sprintf("%-8s rep QB/RB/WR/TE %s | 2027 board vs pick value: max abs diff %.1f (n = %d) | default-league board CSV vs R: %s\n", nm,
              paste(round(rep, 2), collapse = "/"), max(abs(o$value_R - o$pick_value), na.rm = TRUE), sum(!is.na(o$pick_value)),
              if (nm == "default") sprintf("max abs diff %.1f", max(abs(o$value_R - B$value_100k))) else "-"))
  out[[nm]] <- o %>% select(league, board, row, position, class, name, value_R, pick_value)
}
write.csv(bind_rows(out), "dv_board_value_check.csv", row.names = FALSE)

# =============================================================================
# FABLE build (2026-11-13): browser vs R reconciliation of the player and pick values for the five test leagues of
# dv_13 (default scoring). Writes dv_15_expected.js (window.DV15 = R values per league); the check page
# (dv_15_check.js, run inside the trade-values page) recomputes them with the page's own compute() and reports the
# max absolute difference per league on the 100k scale.
# =============================================================================
grab("dv_13_league_presets.R", c("LG_TEST_"))
exp15 <- lapply(names(LG_TEST_), function(nm) { lg <- LG_TEST_[[nm]]; L <- league_values(P, lg)
  top_d <- max(L$players$dynasty, na.rm = TRUE); top_r <- max(L$players$redraft, na.rm = TRUE)
  pl <- L$players %>% filter(!is.na(dynasty) | !is.na(redraft))
  list(name = nm, S = list(teams = lg$teams, ppr = 1, tep = 0, ptd = 4, sf = lg$sf, rb = lg$rb, wr = lg$wr, te = lg$te, flex = lg$flex,
                           fdQB = 0, fdRB = 0, fdWR = 0, fdTE = 0),
       players = lapply(seq_len(nrow(pl)), function(i) list(n = pl$name[i], p = pl$pos[i], d = if (is.na(pl$dynasty[i])) NULL else 1e5 * pl$dynasty[i] / top_d,
                                                             r = if (is.na(pl$redraft[i]) || pl$redraft[i] <= 0) NULL else 1e5 * pl$redraft[i] / top_r)),
       picks = 1e5 * head(L$slots$val, 3 * lg$teams) / top_d) })
writeLines(paste0("window.DV15 = ", jsonlite::toJSON(exp15, auto_unbox = TRUE, digits = NA, null = "null"), ";"), "dv_15_expected.js", useBytes = TRUE)
cat("wrote dv_15_expected.js for", length(exp15), "leagues\n")
