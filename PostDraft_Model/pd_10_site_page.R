# =============================================================================
# Post-draft grade page data: rebuild the two data lines of the public post-draft page
# (window.PD = players + validation tables, window.MOCK27 = 2027 mock draft) from
# pd_post_player_grades.csv, pd_post_grade_*.csv and pd_post_2027_mock_grades.csv.
# Only those two lines are replaced, so the page's design, branding and links stay as they are
# (same idea as Weekly_Refresh/rf_02_predraft_page.R for the pre-draft page).
# Usage: Rscript pd_10_site_page.R page1.html [page2.html ...]
# Env DATA_DIR overrides where the CSVs are read from (default: this folder).
# =============================================================================
suppressMessages({ library(dplyr); library(jsonlite) })
dd <- Sys.getenv("DATA_DIR", ".")
rd <- function(x) read.csv(file.path(dd, x), stringsAsFactors = FALSE, na.strings = c("", "NA"))
f <- rd("pd_post_player_grades.csv")
P <- f %>% transmute(pos = position, rk = post_rank_all, cls = class, rkc = post_rank_class, st = 0L,
  name, col = college, rd = round, pk = pick, sc = post_score, pct = post_pctile, g = post_grade,
  pt = p_top, p2 = p_top2, pa = p_any, out = nfl_outcome, tier = nfl_tier, pts = nfl_ppr_pts,
  fl = as.integer(!is.na(data_flag)))
band <- function(g) ifelse(g %in% c("A+","A","A-"), "A", ifelse(g %in% c("B+","B","B-"), "B", ifelse(g %in% c("C+","C","C-"), "C", "DF")))
BS <- f %>% filter(class <= 2023, !is.na(nfl_tier)) %>% mutate(b = band(post_grade)) %>% group_by(position, b) %>%
  summarize(n = n(), any = round(mean(nfl_tier <= 3), 3), top = round(mean(nfl_tier == 1), 3), .groups = "drop")
pd_line <- paste0("window.PD=", toJSON(list(players = P, val = rd("pd_post_grade_validation.csv"), vp = rd("pd_post_grade_vs_pick.csv"),
  byr = rd("pd_post_grade_by_round.csv"), scale = rd("pd_post_grade_scale.csv"), bands = BS),
  dataframe = "rows", na = "null", auto_unbox = TRUE, digits = 4), ";")
mk <- rd("pd_post_2027_mock_grades.csv") %>% arrange(pick) %>%
  transmute(pick, rd = round, team, name, pos = position, school, post = post_grade, pre = pre_grade, move = grade_move,
            ptop = p_top, pany = p_any, sc = post_score, pct = post_pctile, p2 = p_top2)
mk_line <- paste0("window.MOCK27=", toJSON(mk, dataframe = "rows", na = "null", auto_unbox = TRUE, digits = 4), ";")
fix <- function(x) gsub("</", "<\\/", x, fixed = TRUE)
for (pg in commandArgs(trailingOnly = TRUE)) {
  h <- readLines(pg, encoding = "UTF-8", warn = FALSE)
  i <- grep("^window[.]PD=", h); j <- grep("^window[.]MOCK27=", h)
  if (length(i) != 1) stop("expected one window.PD= line in ", pg)
  h[i] <- fix(pd_line); if (length(j) == 1) h[j] <- fix(mk_line)
  eol <- if (any(readBin(pg, "raw", 4000) == as.raw(13))) "\r\n" else "\n"   # keep the page's line endings
  con <- file(pg, open = "wb"); writeLines(h, con, sep = eol, useBytes = TRUE); close(con)
  cat("updated", pg, ":", nrow(P), "players,", nrow(mk), "mock picks\n")
}
