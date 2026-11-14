# =============================================================================
# FABLE build part 9b: Buy / Sell page from the year-2 and year-3 usage models' summary lists
#   usage: Rscript pd_23_buy_sell_page.R <site_dir>
# Reads ../Football2_RB/rb_summary_lists.csv, ../Football2/wr_summary_lists.csv, ../Football2_TE/te_summary_lists.csv
# (the QB model has no buy / sell lists). Writes <site>/buy-sell/index.html; head and styles copied from Market Check.
# =============================================================================
suppressMessages(library(dplyr))
SITE <- commandArgs(trailingOnly = TRUE)[1]
L <- bind_rows(read.csv("../Football2_RB/rb_summary_lists.csv") %>% mutate(pos = "RB"), read.csv("../Football2/wr_summary_lists.csv") %>% mutate(pos = "WR"),
               read.csv("../Football2_TE/te_summary_lists.csv") %>% mutate(pos = "TE")) %>% filter(grepl("^Year [23] (buy|sell)", list)) %>% mutate(yr = substr(list, 1, 6), side = sub("^Year [23] ", "", list))
# players who meet both a buy and a sell rule in the same year are left off both lists ("Mixed signals")
MIXED <- L %>% group_by(yr, pos, player) %>% filter(n_distinct(side) > 1) %>% ungroup() %>% distinct(yr, player)
L <- L %>% anti_join(MIXED, by = c("yr", "player"))
RULE <- c(
  "Year 2 buy"  = "His rookie usage (role, snaps, targets or touches) points to a better year 2-3 than his rookie fantasy points do.",
  "Year 2 sell" = "Decent rookie points, but the usage behind them was thin, fading late in the year, or leaned on touchdowns.",
  "Year 3 buy"  = "Year-2 usage grew (share and snaps up) or beat what his year-2 points say about year 3.",
  "Year 3 sell" = "A good year 2 on falling usage: share and snaps went down, or the late-season trend turned.")
src <- readLines(file.path(SITE, "value-research", "index.html"), encoding = "UTF-8", warn = FALSE)
head <- src[1:grep("</style></head>", src, fixed = TRUE)[1]]
head <- sub("<title>[^<]*</title>", "<title>Buy / Sell | Prospect Actuary</title>", head)
head <- sub("section{display:flex;flex-direction:column;gap:14px}", "section{display:flex;flex-direction:column;gap:14px;min-width:0}", head, fixed = TRUE)
head <- sub(".tblwrap{overflow-x:auto;", ".tablebox{max-width:100%;overflow-x:auto;", head, fixed = TRUE)
head <- sub('<meta name="description" content="[^"]*"', '<meta name="description" content="Year-2 and year-3 buys and sells from the Prospect Actuary usage models: young RBs, WRs and TEs whose usage says more than their fantasy points"', head)
nav <- grep('nav class="pa-brand"', src, value = TRUE)[1]; foot <- grep("^<footer", src, value = TRUE)[1]
esc <- function(x) gsub(">", "&gt;", gsub("<", "&lt;", gsub("&", "&amp;", as.character(x))))
sect <- function(ls) { x <- L %>% filter(list == ls); if (!nrow(x)) return("")
  rows <- x %>% arrange(pos, desc(key_prob)) %>% mutate(tr = sprintf('<tr><td>%s</td><td>%s</td><td class="r num">%d</td><td class="r num">%.0f%%</td><td class="small muted">%s</td></tr>',
    esc(pos), esc(player), pick, 100 * key_prob, esc(note)))
  paste0('<section><h2>', ls, 's</h2><p class="small" style="max-width:72ch">', RULE[[ls]], '</p><div class="tablebox"><table><thead><tr><th>Pos</th><th>Player</th><th class="r">Pick</th><th class="r">Chance of a starter season</th><th>Why (model inputs)</th></tr></thead><tbody>',
         paste(rows$tr, collapse = ""), '</tbody></table></div>',
         { mx <- sort(MIXED$player[MIXED$yr == substr(ls, 1, 6)]); if (grepl("sell", ls) && length(mx)) paste0('<p class="small muted" style="max-width:72ch"><b>Mixed signals:</b> ',
           paste(esc(mx), collapse = ", "), ' met both a buy rule and a sell rule, so they are left off both lists.</p>') else "" }, '</section>') }
body <- paste0('
<body><div class="wrap">
<header style="display:flex;flex-direction:column;gap:14px">
  ', nav, '
  <h1>Buy / Sell</h1>
  <p class="lede" style="max-width:72ch">After a player\'s first NFL season, how he was used (snaps, targets, touches, his share of the offense, and the late-season trend) says more about his next two years than his fantasy points did. These lists come from our year-2 and year-3 usage models, tested class by class on every drafted RB, WR and TE since 2010 with each class scored by a model that never saw it.</p>
  <p class="small muted" style="max-width:72ch"><b>A sell does not mean the player is bad.</b> It means his points ran ahead of the role behind them, so his price may be higher than what players with that usage usually go on to do. A buy is the reverse. "Chance of a starter season" is the model\'s chance of at least one top-24 RB, top-36 WR or top-18 TE season in the next two years. The lists were made after the 2025 season for the 2025 class (year 2 in 2026) and the 2024 class (year 3 in 2026); they are not updated during the season. Quarterbacks are not listed.</p>
</header>
', paste(sapply(c("Year 2 buy", "Year 2 sell", "Year 3 buy", "Year 3 sell"), sect), collapse = "\n"), '
', foot, '
</div></body></html>')
dir.create(file.path(SITE, "buy-sell"), showWarnings = FALSE)
writeLines(enc2utf8(c(head, body)), file.path(SITE, "buy-sell", "index.html"), useBytes = TRUE)
cat("wrote buy-sell page:", nrow(L), "rows\n"); print(table(L$list, L$pos))
