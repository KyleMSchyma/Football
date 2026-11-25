# =============================================================================
# One-time (safe to rerun) switch of saved grade files to the five-grade scale (Kyle 2026-11-25).
#   A+ = top 5% | A = 85-95 | B = 65-85 | C = 25-65 | D = bottom 25%   (percentile within position, drafted 2010-2023)
#   old -> new: A+ -> A+; A, A- -> A; B+, B -> B; B-, C+, C, C- -> C; D, F -> D. The bands nest exactly, so mapping the
#   letters gives the same grade as re-cutting the percentile. Scores, percentiles and odds are NOT changed.
# Why: Grade_Tier_Research (F#46): outcomes form five groups; B+ = B, the B-to-B- step is a cliff, C+/C/C- are flat.
# The model scripts (pd_06, pd_07, pd_09, pd_11) now write the new scale themselves; this script converts files written
# before that, so nothing has to be refit:
#   pre-draft folder : pd_player_grades.csv (grade, grade_asis), pd_player_probs_drafted.csv, and rebuilds
#                      pd_grade_validation.csv, pd_grade_by_round.csv, pd_grade_scale.csv (same definitions as pd_06)
#   post-draft folder: pd_post_player_grades.csv, pd_post_2027_mock_grades{,_best,_worst}.csv, pd_post_2027_mock_check*.csv
#                      (every *grade* letter column; grade_move / grade_move_draft recomputed in five-grade steps), and
#                      rebuilds pd_post_grade_validation.csv, pd_post_grade_by_round.csv, pd_post_grade_scale.csv (pd_11 definitions)
# Usage: Rscript pd_15_grade_scale5.R <pre-draft dir> <post-draft dir> [more dirs ...]   (a dir is skipped if its files are absent)
#   repo: Rscript pd_15_grade_scale5.R ../PreDraft_Model .      PC: Rscript pd_15_grade_scale5.R ../Football2_PreDraft .
# Class grades (pd_class_grades.csv, pd_overall_grades.csv) are a different scale and are left alone.
# =============================================================================
suppressMessages(library(dplyr))
MAP5 <- c("A+" = "A+", "A" = "A", "A-" = "A", "B+" = "B", "B" = "B", "B-" = "C", "C+" = "C", "C" = "C", "C-" = "C", "D" = "D", "F" = "D")
GRADES5 <- c("D", "C", "B", "A", "A+")
SCALE_ROW <- c("A+" = "A+", "A-" = "A", "B" = "B", "C-" = "C", "F" = "D")   # old scale row that starts each new grade
to5 <- function(g) { out <- unname(MAP5[g]); ifelse(is.na(g) | g == "", NA_character_, ifelse(is.na(out), g, out)) }   # keeps "UDFA" etc.; blank = missing
gidx5 <- function(g) match(g, GRADES5)
rd <- function(f) read.csv(f, stringsAsFactors = FALSE, check.names = FALSE)   # default na.strings keeps "" strings as written
wr <- function(d, f) write.csv(d, f, row.names = FALSE, na = "")
bootp <- function(y, B = 2000) { set.seed(2026); if (length(y) < 2) return(c(NA, NA)); unname(quantile(replicate(B, mean(sample(y, replace = TRUE))), c(.025, .975))) }
round_band <- function(r) case_when(r == 1 ~ "Round 1", r <= 3 ~ "Rounds 2-3", TRUE ~ "Rounds 4-7")
conv_scale <- function(f) { s <- rd(f); if (all(s$grade %in% GRADES5)) return(invisible(NULL))
  s <- s %>% filter(grade %in% names(SCALE_ROW)) %>% mutate(grade = unname(SCALE_ROW[grade])); wr(s, f); cat("  ", f, ":", nrow(s), "rows\n") }
vtab <- function(H, gcol, p3col) H %>% mutate(grade = factor(.data[[gcol]], levels = rev(GRADES5))) %>% group_by(position, grade) %>%
  summarize(n = n(), mean_pick = round(mean(pick, na.rm = TRUE)), top_rate = mean(y1), top2_rate = mean(y2), any_rate = mean(y3),
            any_lo = bootp(y3)[1], any_hi = bootp(y3)[2], exp_any = mean(.data[[p3col]]), mean_ppr_3yr = mean(nfl_ppr_pts, na.rm = TRUE), .groups = "drop") %>%
  mutate(grade = as.character(grade), across(where(is.double), ~ round(.x, 3)))
btab <- function(H, gcol) H %>% mutate(round_band = round_band(round), band = factor(.data[[gcol]], levels = rev(GRADES5))) %>%
  group_by(position, round_band, band) %>% summarize(n = n(), any_rate = round(mean(y3), 3), top2_rate = round(mean(y2), 3), .groups = "drop") %>%
  mutate(band = as.character(band))
yy <- function(d) d %>% mutate(y1 = as.integer(nfl_tier == 1), y2 = as.integer(nfl_tier <= 2), y3 = as.integer(nfl_tier <= 3))

# Edit the letter and grade_move fields in place, token by token, so every other field keeps its exact text
# (quoted "" vs empty NA, number formatting, line endings): downstream scripts read these files with different na rules.
split_csv <- function(l) { m <- gregexpr('"(?:[^"]|"")*"|[^,]*', l, perl = TRUE)[[1]]
  st <- as.integer(m); ln <- attr(m, "match.length"); keep <- c(TRUE, st[-1] > st[-length(st)] + ln[-length(ln)]); substring(l, st[keep], st[keep] + ln[keep] - 1) }
unq <- function(t) ifelse(grepl('^".*"$', t), gsub('""', '"', substr(t, 2, nchar(t) - 1)), t)
conv_file <- function(path) {
  raw <- readBin(path, "raw", file.info(path)$size); crlf <- any(raw == as.raw(13))
  L <- readLines(path, encoding = "UTF-8", warn = FALSE); if (!length(L)) return(invisible(NULL))
  hdr <- unq(split_csv(L[1])); body <- lapply(L[-1], split_csv)
  if (any(lengths(body) != length(hdr))) stop("field count mismatch in ", path)
  M <- do.call(rbind, body); V <- M; V[] <- unq(M)
  gcols <- which(grepl("grade", hdr) & !grepl("move", hdr) & apply(V, 2, function(v) all(v == "" | v %in% c(names(MAP5), "UDFA"))))
  for (j in gcols) { nv <- to5(V[, j]); ch <- !is.na(nv) & nv != V[, j]; M[ch, j] <- paste0('"', nv[ch], '"'); V[ch, j] <- nv[ch] }
  for (mv in c("grade_move", "grade_move_draft")) { j <- match(mv, hdr); if (is.na(j)) next
    pg <- V[, match(if (mv == "grade_move") "post_grade" else "post_grade_draft", hdr)]; pr <- V[, match("pre_grade", hdr)]
    d <- gidx5(pg) - gidx5(pr); ok <- !is.na(d); M[ok, j] <- as.character(d[ok]) }
  out <- c(L[1], apply(M, 1, paste, collapse = ","))
  con <- file(path, open = "wb"); writeLines(out, con, sep = if (crlf) "\r\n" else "\n", useBytes = TRUE); close(con)
  cat("  ", basename(path), ":", length(gcols), "grade columns\n")
}

for (dir in commandArgs(trailingOnly = TRUE)) {
  cat("==", dir, "\n")
  p <- function(x) file.path(dir, x)
  # ---- pre-draft files (pd_06 definitions: drafted 2010-2023; exp_any = mean of the unconditional p_any) ----
  if (file.exists(p("pd_player_grades.csv"))) {
    conv_file(p("pd_player_grades.csv")); if (file.exists(p("pd_player_probs_drafted.csv"))) conv_file(p("pd_player_probs_drafted.csv"))
    g <- read.csv(p("pd_player_grades.csv"), stringsAsFactors = FALSE, na.strings = "")
    cat("  grades:", paste(names(table(g$grade)), table(g$grade), collapse = " "), "\n")
    H <- g %>% filter(status == "drafted", class <= 2023, !is.na(nfl_tier)) %>% yy()
    wr(vtab(H, "grade", "p_any"), p("pd_grade_validation.csv")); wr(btab(H, "grade"), p("pd_grade_by_round.csv"))
    if (file.exists(p("pd_grade_scale.csv"))) conv_scale(p("pd_grade_scale.csv"))
  }
  # ---- post-draft files (pd_11 definitions, on the mixed grade) ----
  if (file.exists(p("pd_post_player_grades.csv"))) {
    for (x in c("pd_post_player_grades.csv", "pd_post_2027_mock_grades.csv", "pd_post_2027_mock_grades_best.csv", "pd_post_2027_mock_grades_worst.csv",
                "pd_post_2027_mock_check.csv", "pd_post_2027_mock_check_best.csv", "pd_post_2027_mock_check_worst.csv")) if (file.exists(p(x))) conv_file(p(x))
    f <- read.csv(p("pd_post_player_grades.csv"), stringsAsFactors = FALSE, na.strings = "")
    cat("  post grades:", paste(names(table(f$post_grade)), table(f$post_grade), collapse = " "), "\n")
    H <- f %>% filter(class <= 2023, !is.na(nfl_tier)) %>% yy()
    wr(vtab(H, "post_grade", "p_any"), p("pd_post_grade_validation.csv")); wr(btab(H, "post_grade"), p("pd_post_grade_by_round.csv"))
    if (file.exists(p("pd_post_grade_scale.csv"))) conv_scale(p("pd_post_grade_scale.csv"))
  }
}
cat("done\n")
