# =============================================================================
# Comparison of two experiment runs (exp/*_<tag>.rds): ./run.sh rl_eval.R logs/cmp_<b>_<v>.txt <base_tag> <variant_tag> [LG]
# By position: Spearman, RMSE, predicted / actual totals for the redraft backtest (dv_10, weeks 10-18, 2016-2025) and
# the dynasty backtest (dv_11, five seasons from week-9 snapshots 2016-2020), with paired bootstrap intervals on the
# difference (players as the unit, 2000 draws, seed 2026). Optional: the five dv_13 league setups. Market Check sanity
# check: 2026 rank correlation with the Dynasty Daddy snapshot (top 150) and the ten biggest gaps.
# Writes rl_cmp_<b>_<v>.csv.
# =============================================================================
suppressMessages(library(dplyr))
NB <- 2000
mets <- function(p, a) c(spearman = suppressWarnings(cor(p, a, method = "spearman")), rmse = sqrt(mean((p - a)^2)), ratio = sum(p) / sum(a))
paired_boot <- function(b, v, ids, seed = 2026) {
  set.seed(seed); u <- unique(ids); rows <- split(seq_along(ids), factor(ids, levels = u))
  m0 <- mets(b$p, b$a); m1 <- mets(v$p, v$a)
  D <- t(replicate(NB, { s <- unlist(rows[sample.int(length(u), length(u), replace = TRUE)], use.names = FALSE)
    mets(v$p[s], v$a[s]) - mets(b$p[s], b$a[s]) }))
  tibble(metric = names(m0), base = m0, variant = m1, diff = m1 - m0,
         lo = apply(D, 2, quantile, 0.025, na.rm = TRUE), hi = apply(D, 2, quantile, 0.975, na.rm = TRUE))
}
cmp_rows <- function(B, V, test, pa = "value", aa = "actual", keys = c("season", "player_id")) {
  j <- inner_join(B %>% select(all_of(keys), pos, pb = all_of(pa), ab = all_of(aa)), V %>% select(all_of(keys), pv = all_of(pa), av = all_of(aa)), by = keys)
  stopifnot(nrow(j) == nrow(B), nrow(j) == nrow(V), isTRUE(all.equal(j$ab, j$av)))   # same rows, same target
  grp <- c(split(seq_len(nrow(j)), j$pos), list(all = seq_len(nrow(j))))
  bind_rows(lapply(names(grp), function(g) { i <- grp[[g]]
    paired_boot(list(p = j$pb[i], a = j$ab[i]), list(p = j$pv[i], a = j$ab[i]), j$player_id[i]) %>% mutate(test = test, pos = g, n = length(i), .before = 1) }))
}
# ---------- Market Check: Dynasty Daddy superflex dynasty values (snapshot used by the Value Research page) ----------
nkey <- function(x) { x <- iconv(x, to = "ASCII//TRANSLIT"); x <- tolower(gsub("[.'’-]", "", x))
  x <- gsub("\\b(jr|sr|ii|iii|iv|v)\\b", "", x); gsub("[^a-z]", "", x) }
dd_read <- function(f = "../ProspectActuary/value-research/data/dd.js") {
  js <- sub(";\\s*$", "", sub("^window.DD = ", "", paste(readLines(f, warn = FALSE), collapse = "")))
  x <- jsonlite::fromJSON(js)$dynasty
  tibble(key = x[, 1], pos = x[, 2], dd_value = as.numeric(x[, 4])) %>% arrange(desc(dd_value)) %>% mutate(dd_rank = row_number())
}
market <- function(b4, dd = dd_read()) {
  ours <- b4 %>% mutate(key = paste0(nkey(name), tolower(pos))) %>% select(key, name, pos, team, our_rank = rank)
  m <- inner_join(dd %>% select(key, dd_rank), ours, by = "key")
  top <- m %>% filter(dd_rank <= 150)
  gaps <- m %>% filter(dd_rank <= 150 | our_rank <= 150) %>% mutate(gap = dd_rank - our_rank) %>% arrange(desc(abs(gap)))
  list(rho = cor(top$dd_rank, top$our_rank, method = "spearman"), n = nrow(top), gaps = gaps,
       higher = gaps %>% filter(gap > 0) %>% head(10), lower = gaps %>% filter(gap < 0) %>% head(10))
}

if (!exists("RL_EVAL_LIB")) {
  a <- commandArgs(trailingOnly = TRUE); bt_ <- a[1]; vt_ <- a[2]; BT_MIN <- if ("WIDE" %in% a) 0 else if ("MIN1" %in% a) 1 else 3
  b10 <- readRDS(paste0("exp/dv10_", bt_, ".rds"))$bv %>% filter(n_cur >= BT_MIN); v10 <- readRDS(paste0("exp/dv10_", vt_, ".rds"))$bv %>% filter(n_cur >= BT_MIN)
  b11 <- readRDS(paste0("exp/dv11_", bt_, ".rds")); v11 <- readRDS(paste0("exp/dv11_", vt_, ".rds"))
  if ("Y13" %in% a) { b10 <- b10 %>% filter(exp <= 2); v10 <- v10 %>% filter(exp <= 2); b11$BT <- b11$BT %>% filter(exp <= 2); v11$BT <- v11$BT %>% filter(exp <= 2) }   # players in NFL years 1-3
  R <- bind_rows(cmp_rows(b10, v10, "redraft wk10-18"), cmp_rows(b11$BT, v11$BT, "dynasty 5 seasons", "pred"))
  if ("LG" %in% a && file.exists(paste0("exp/lg_", vt_, ".rds"))) {
    LB <- readRDS(paste0("exp/lg_", bt_, ".rds")); LV <- readRDS(paste0("exp/lg_", vt_, ".rds"))
    for (k in seq_along(LB)) R <- bind_rows(R,
      cmp_rows(LB[[k]]$rv, LV[[k]]$rv, paste("redraft |", LB[[k]]$setting)) %>% filter(pos == "all"),
      cmp_rows(LB[[k]]$bd, LV[[k]]$bd, paste("dynasty |", LB[[k]]$setting), "pred") %>% filter(pos == "all"))
  }
  R <- R %>% mutate(across(c(base, variant, diff, lo, hi), ~ round(.x, 4)), sig = ifelse(lo > 0, "+", ifelse(hi < 0, "-", "")))
  options(width = 200); cat("comparison", bt_, "->", vt_, "(diff = variant - base; 95% paired bootstrap, players as unit)\n")
  print(as.data.frame(R), row.names = FALSE)
  write.csv(R, paste0("rl_cmp_", bt_, "_", vt_, ".csv"), row.names = FALSE)
  mb <- market(b11$b4); mv <- market(v11$b4)
  cat(sprintf("\nMarket Check (Dynasty Daddy SF dynasty, top 150 by DD): rank correlation %s %.3f -> %s %.3f (matched %d / %d)\n", bt_, mb$rho, vt_, mv$rho, mb$n, mv$n))
  cat("\nten biggest 'we are higher than the market' gaps,", bt_, ":\n"); print(as.data.frame(mb$higher %>% select(name, pos, team, our_rank, dd_rank, gap)), row.names = FALSE)
  cat("\n", vt_, ":\n"); print(as.data.frame(mv$higher %>% select(name, pos, team, our_rank, dd_rank, gap)), row.names = FALSE)
  cat("\nten biggest 'we are lower' gaps,", bt_, ":\n"); print(as.data.frame(mb$lower %>% select(name, pos, team, our_rank, dd_rank, gap)), row.names = FALSE)
  cat("\n", vt_, ":\n"); print(as.data.frame(mv$lower %>% select(name, pos, team, our_rank, dd_rank, gap)), row.names = FALSE)
}
