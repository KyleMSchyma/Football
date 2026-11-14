# =============================================================================
# Track Record page for the site: <site>/track-record/index.html from scores/latest.json and the frozen files.
#   usage: Rscript tr_03_page.R <site_dir>     (the head and styles are copied from the Market Check page so the look matches)
# =============================================================================
suppressMessages({ library(dplyr); library(jsonlite) })
SITE <- commandArgs(trailingOnly = TRUE)[1]; S <- fromJSON("scores/latest.json")
src <- readLines(file.path(SITE, "value-research", "index.html"), encoding = "UTF-8", warn = FALSE)
head_end <- grep("</style></head>", src, fixed = TRUE)[1]; head <- src[1:head_end]
head <- sub("<title>[^<]*</title>", "<title>Track Record | Prospect Actuary</title>", head)
head <- sub('<meta name="description" content="[^"]*"', '<meta name="description" content="Prospect Actuary track record: predictions for the 2024, 2025 and 2026 draft classes frozen on 2026-11-13 and scored against what happened"', head)
nav <- grep('nav class="pa-brand"', src, value = TRUE)[1]
foot <- grep("^<footer", src, value = TRUE)[1]
esc <- function(x) gsub("<", "&lt;", gsub("&", "&amp;", as.character(x)))
pct <- function(x) ifelse(is.na(x), "–", sprintf("%.0f%%", 100 * x))
tbl <- function(d, cols, labs) paste0('<div class="tablebox"><table><thead><tr>', paste0("<th>", labs, "</th>", collapse = ""), "</tr></thead><tbody>",
  paste(apply(d[, cols, drop = FALSE], 1, function(r) paste0("<tr>", paste0("<td>", esc(r), "</td>", collapse = ""), "</tr>")), collapse = ""), "</tbody></table></div>")
b <- S$bands %>% mutate(board = factor(board, c("pre-draft", "post-draft")), band = factor(band, c("A", "B", "C", "D/F"))) %>% arrange(board, band) %>%
  transmute(board, band, n, so_far = pct(any_tier_so_far), ci = paste0(pct(lo), " – ", pct(hi)), top = pct(top_tier_so_far), expected = pct(expected_any_3yrs))
br <- S$brier %>% arrange(board, class) %>% transmute(board, class, n, seasons_seen, model = sprintf("%.3f", brier_any_model), pick = sprintf("%.3f", brier_any_pick),
  better = ifelse(brier_any_model < brier_any_pick, "model", "draft pick"))
cal <- S$cal %>% transmute(board, bin, n, predicted = pct(mean_predicted_3yrs), so_far = pct(any_tier_so_far))
body <- paste0('
<body><div class="wrap">
<header style="display:flex;flex-direction:column;gap:14px">
  ', nav, '
  <h1>Track Record</h1>
  <p class="lede" style="max-width:72ch">Every grade on this site was tested on past draft classes, but those classes were also used to choose the models, so their scores flatter us a little. The <b>2024, 2025 and 2026 classes</b> were never used for any choice. Their predictions were frozen on <b>2026-11-13</b> (pre-draft and post-draft probabilities, grades and values, with a hash so they cannot be edited) and are scored here against what actually happened. This is the true holdout.</p>
  <p class="small muted" style="max-width:72ch"><b>Read with care: the samples are still small.</b> The 2024 class has played two of its three seasons, the 2025 class one, the 2026 class none that are complete. "Hit" means at least one top-tier fantasy season in years 1-3 (QB, RB top 24; WR top 36; TE top 18), so rates will rise as more seasons are played. Results run through the ', S$through, ' season; scored on ', S$scored_on, '.</p>
</header>
<section><h2>Hit rate by grade so far</h2>
<p class="small" style="max-width:72ch">"Expected" is the frozen probability of a hit over all three seasons, so "so far" should still be below it for classes that have not finished.</p>
', tbl(b, c("board", "band", "n", "so_far", "ci", "top", "expected"), c("Board", "Grade", "Players", "Any tier so far", "95% range", "Top tier so far", "Expected (3 yrs)")), '
</section>
<section><h2>Model vs draft pick</h2>
<p class="small" style="max-width:72ch">Brier score of the frozen any-tier probability against a pick-only benchmark frozen at the same time (lower is better). With one or two seasons played this is an early read.</p>
', tbl(br, c("board", "class", "n", "seasons_seen", "model", "pick", "better"), c("Board", "Class", "Players", "Seasons", "Model", "Draft pick", "Better so far")), '
</section>
<section><h2>Calibration so far</h2>
', tbl(cal, c("board", "bin", "n", "predicted", "so_far"), c("Board", "Predicted (3 yrs)", "Players", "Mean predicted", "Hit so far")), '
</section>
<section><h2>Market Check log</h2>
<p class="small" style="max-width:72ch">Each week we also save where our dynasty ranks and the market\'s disagree (top 150 on either side). Once games are played we score which side was closer to the points each player actually scored over replacement. First log: 2026-11-13, ', S$market$n[1], ' players, ', S$market$disagreements[1], ' disagreements of 25 ranks or more. No games have been played since, so there is nothing to score yet.</p>
</section>
', foot, '
</div></body></html>')
dir.create(file.path(SITE, "track-record"), showWarnings = FALSE)
writeLines(enc2utf8(c(head, body)), file.path(SITE, "track-record", "index.html"), useBytes = TRUE)
cat("wrote", file.path(SITE, "track-record", "index.html"), "\n")
