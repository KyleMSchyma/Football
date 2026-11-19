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
# Mixed draft model (pd_11_mixed_model.R): mixed_faller = pre-draft A range that fell below A- after the draft
mixcols <- function(d) { if (!"mixed_faller" %in% names(d)) d$mixed_faller <- 0L
  if (!"post_grade_draft" %in% names(d)) d$post_grade_draft <- d$post_grade
  for (cc in c("post_score", "post_pctile", "p_top", "p_top2", "p_any")) if (!paste0(cc, "_draft") %in% names(d)) d[[paste0(cc, "_draft")]] <- d[[cc]]
  d }
# dr = the plain post-draft model's values for boosted (mixed) rows, for the page's Post-draft / Mixed toggle
# qv (2027 mock rows, pd_12_mock_range.R) = the plain post-draft model's value probabilities: odds at the average pick weighted
# by the share of our mocks that draft him; the page's Post-draft view prices the row from them (parity with the mixed view)
drf <- function(mx, g, sc, pc, q1, q2, q3, v1 = NULL, v2 = NULL, v3 = NULL) I(lapply(seq_along(mx), function(i) {
  wv <- !is.null(v1) && !is.na(v1[i]) && (is.na(q3[i]) || abs(v3[i] - q3[i]) > 1e-6 || abs(v1[i] - q1[i]) > 1e-6)
  if ((is.na(mx[i]) || mx[i] != 1) && !wv) return(NULL)
  r <- list(g = g[i], sc = sc[i], pct = pc[i], q = c(q1[i], q2[i], q3[i])); if (wv) r$qv <- c(v1[i], v2[i], v3[i]); r }))
f <- mixcols(f)
# Cross-position Value column (dv_13_league_presets.R, default league, 100k trade-value scale); joined by key, not row order.
vf <- c("../Football2_Dynasty/dv_rookie_board_values.csv", "../Trade_Values/dv_rookie_board_values.csv"); vf <- vf[file.exists(vf)][1]
V <- if (!is.na(vf)) read.csv(vf, stringsAsFactors = FALSE, na.strings = c("", "NA")) else
  data.frame(board = character(0), position = character(0), class = integer(0), pick = integer(0), name = character(0), value_100k = numeric(0),
             p_top = numeric(0), p_top2 = numeric(0), p_any = numeric(0), age = numeric(0))
f <- f %>% left_join(V %>% filter(board == "post") %>% distinct(position, class, pick, .keep_all = TRUE) %>%
                       select(position, class, pick, v = value_100k, vq1 = p_top, vq2 = p_top2, vq3 = p_any, ag = age), by = c("position", "class", "pick"))
P <- f %>% transmute(pos = position, rk = post_rank_all, cls = class, rkc = post_rank_class, st = 0L,
  name, col = college, rd = round, pk = pick, sc = post_score, pct = post_pctile, g = post_grade,
  pt = p_top, p2 = p_top2, pa = p_any, out = nfl_outcome, tier = nfl_tier, pts = nfl_ppr_pts,
  fl = as.integer(!is.na(data_flag)), mx = as.integer(coalesce(mixed_faller, 0L)), gd = post_grade_draft,
  dr = drf(mixed_faller, post_grade_draft, post_score_draft, post_pctile_draft, p_top_draft, p_top2_draft, p_any_draft), v = v,
  vq = I(lapply(seq_along(vq1), function(i) if (is.na(vq1[i])) NULL else c(vq1[i], vq2[i], vq3[i]))), ag = ag)
band <- function(g) ifelse(g %in% c("A+","A","A-"), "A", ifelse(g %in% c("B+","B","B-"), "B", ifelse(g %in% c("C+","C","C-"), "C", "DF")))
BS <- f %>% filter(class <= 2023, !is.na(nfl_tier)) %>% mutate(b = band(post_grade)) %>% group_by(position, b) %>%
  summarize(n = n(), any = round(mean(nfl_tier <= 3), 3), top = round(mean(nfl_tier == 1), 3), .groups = "drop")
pd_line <- paste0("window.PD=", toJSON(list(players = P, val = rd("pd_post_grade_validation.csv"), vp = rd("pd_post_grade_vs_pick.csv"),
  byr = rd("pd_post_grade_by_round.csv"), scale = rd("pd_post_grade_scale.csv"), bands = BS),
  dataframe = "rows", na = "null", auto_unbox = TRUE, digits = 4), ";")
mk <- mixcols(rd("pd_post_2027_mock_grades.csv"))
for (cc in c("p_top", "p_top2", "p_any")) if (!paste0(cc, "_value_draft") %in% names(mk)) mk[[paste0(cc, "_value_draft")]] <- NA_real_
# rg = the pick range across our saved mocks (pd_12_mock_range.R): best / worst pick and their tier odds, mixed and plain
# post-draft (bd / wd), for the mock table's "average pick (best-worst)" and "value (best-worst)" (Kyle 2026-11-18)
if (!"best_pick" %in% names(mk)) mk$best_pick <- NA_integer_
rgf <- function(d) I(lapply(seq_len(nrow(d)), function(i) { x <- d[i, ]; if (is.na(x$best_pick)) return(NULL)
  q <- function(pre, suf = "") { v <- c(x[[paste0(pre, "p_top", suf)]], x[[paste0(pre, "p_top2", suf)]], x[[paste0(pre, "p_any", suf)]]); if (any(is.na(v))) NULL else v }
  list(pb = x$best_pick, pw = if (is.na(x$worst_pick)) NA_integer_ else x$worst_pick, ud = identical(x$worst_case, "undrafted"),
       nd = x$n_drafted, nm = x$n_mocks, b = q("best_"), w = q("worst_"), bd = q("best_", "_draft"), wd = q("worst_", "_draft")) }))
mk$rg <- rgf(mk)
mk <- mk %>% arrange(pick) %>%
  left_join(V %>% filter(board == "mock") %>% distinct(pick, name, .keep_all = TRUE) %>% select(pick, name, v = value_100k, vq1 = p_top, vq2 = p_top2, vq3 = p_any, ag = age), by = c("pick", "name")) %>%
  transmute(pick, rd = round, team, name, pos = position, school, post = post_grade, pre = pre_grade, move = grade_move,
            ptop = p_top, pany = p_any, sc = post_score, pct = post_pctile, p2 = p_top2, mx = as.integer(coalesce(mixed_faller, 0L)), gd = post_grade_draft,
            dr = drf(mixed_faller, post_grade_draft, post_score_draft, post_pctile_draft, p_top_draft, p_top2_draft, p_any_draft,
                     p_top_value_draft, p_top2_value_draft, p_any_value_draft), v = v,
            vq = I(lapply(seq_along(vq1), function(i) if (is.na(vq1[i])) NULL else c(vq1[i], vq2[i], vq3[i]))), ag = ag, rg = rg)
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
