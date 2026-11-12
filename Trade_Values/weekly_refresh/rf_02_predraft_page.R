# Weekly refresh step: put the latest pre-draft grades (Football2_PreDraft/pd_player_grades.csv etc.) into the
# pre-draft grade pages. Only the one "window.PD=..." data line of each page is replaced, so the page's
# design, branding and links stay as they are.  usage: Rscript rf_02_predraft_page.R page1.html [page2.html ...]
suppressMessages({ library(dplyr); library(jsonlite) })
pre <- "../Football2_PreDraft"
f <- read.csv(file.path(pre, "pd_player_grades.csv"), stringsAsFactors = FALSE, na.strings = "")
# Cross-position Value column (dv_13_league_presets.R, default league, 100k trade-value scale); joined by key, not row order.
vf <- c("../Football2_Dynasty/dv_rookie_board_values.csv", "../Trade_Values/dv_rookie_board_values.csv"); vf <- vf[file.exists(vf)][1]
if (!is.na(vf)) {
  V <- read.csv(vf, stringsAsFactors = FALSE, na.strings = c("", "NA")) %>% filter(board == "pre") %>%
    distinct(position, class, name, college, .keep_all = TRUE) %>% select(position, class, name, college, v = value_100k, vsrc = source, vq1 = p_top, vq2 = p_top2, vq3 = p_any, vag = age)
  f <- f %>% left_join(V, by = c("position", "class", "name", "college"))
} else f <- f %>% mutate(v = NA_real_, vsrc = NA_character_, vq1 = NA_real_, vq2 = NA_real_, vq3 = NA_real_, vag = NA_real_)
P <- f %>% transmute(pos = position, rk = pos_rank_all, cls = class, rkc = pos_rank_class, st = as.integer(status != "drafted"),
  name, col = college, lvl = level, yrs = yrs_out_of_hs, rd = round, pk = pick, sc = score, pct = pctile, g = grade,
  pt = p_top, p2 = p_top2, pa = p_any, sca = score_asis, ga = grade_asis, pdec = p_declare, out = nfl_outcome,
  tier = nfl_tier, pts = nfl_ppr_pts, done = as.integer(outcome_complete), fl = as.integer(!is.na(data_flag)),
  cl = as.integer(!is.na(community_list)), v = v, vq = I(lapply(seq_along(vq1), function(i) if (is.na(vq1[i])) NULL else c(vq1[i], vq2[i], vq3[i]))), ag = vag,
  vs = ifelse(is.na(vsrc), NA, ifelse(grepl("mock", vsrc), "mock", ifelse(grepl("^post", vsrc), "post", "pre"))))
rd <- function(x) read.csv(file.path(pre, x))
band <- function(g) ifelse(g %in% c("A+","A","A-"), "A", ifelse(g %in% c("B+","B","B-"), "B", ifelse(g %in% c("C+","C","C-"), "C", "DF")))
BS <- f %>% filter(status == "drafted", class <= 2023) %>% mutate(b = band(grade)) %>% group_by(position, b) %>%
  summarize(n = n(), any = round(mean(nfl_tier <= 3), 3), top = round(mean(nfl_tier == 1), 3), .groups = "drop")
line <- paste0("window.PD=", toJSON(list(players = P, val = rd("pd_grade_validation.csv"), vp = rd("pd_grade_vs_pick.csv"),
  byr = rd("pd_grade_by_round.csv"), scale = rd("pd_grade_scale.csv"), bands = BS), dataframe = "rows", na = "null", auto_unbox = TRUE, digits = 4), ";")
line <- gsub("</", "<\\/", line, fixed = TRUE)
for (pg in commandArgs(trailingOnly = TRUE)) {
  h <- readLines(pg, encoding = "UTF-8", warn = FALSE); i <- grep("^window[.]PD=", h)
  if (length(i) != 1) stop("expected one window.PD= line in ", pg)
  h[i] <- line; con <- file(pg, open = "wb"); writeLines(h, con, useBytes = TRUE); close(con)
  cat("updated", pg, ":", nrow(P), "players,", sum(P$st == 1), "projected 2027\n")
}
