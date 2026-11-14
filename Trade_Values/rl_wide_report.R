# =============================================================================
# Wider scoring population and the QB starter layer (coordinator follow-up, 2026-11-13)
#   ./run.sh rl_wide_report.R logs/wide_report.txt
# Needs exp/ runs: base_w, a2_w, a23_w (WIDE: rostered players incl. 0 games), base, a2, a23 (live 3+ sample),
# base_lf / base (season-length fix). Writes rl_wide_groups.csv, rl_backup_qbs.csv, rl_named_qbs.csv, rl_lenfix_totals.csv.
# =============================================================================
suppressMessages(library(dplyr)); options(width = 200)
RL_EVAL_LIB <- TRUE; source("rl_eval.R"); source("dv_common.R")
TAGS <- c(current = "base_w", A2 = "a2_w", `A2+A3` = "a23_w", `A2+A3 future only` = "a23f_w")
ld <- function(t) list(r = readRDS(paste0("exp/dv10_", t, ".rds"))$bv, d = readRDS(paste0("exp/dv11_", t, ".rds"))$BT)
X <- lapply(TAGS, ld)
grp <- function(x, pc, ac) x %>% mutate(games = ifelse(n_cur <= 2, "0-2 games", "3+ games")) %>% group_by(pos, games) %>%
  summarise(n = n(), spearman = suppressWarnings(cor(.data[[pc]], .data[[ac]], method = "spearman")), pred_t = sum(.data[[pc]]), actual_t = sum(.data[[ac]]), .groups = "drop") %>%
  transmute(pos, games, n, pred = pred_t, actual = actual_t, ratio = pred / actual, spearman)
G <- bind_rows(lapply(names(X), function(m) bind_rows(grp(X[[m]]$r, "value", "actual") %>% mutate(test = "redraft wk10-18"),
                                                    grp(X[[m]]$d, "pred", "actual") %>% mutate(test = "dynasty 5 seasons")) %>% mutate(method = m)))
G <- G %>% select(test, pos, games, method, n, pred, actual, ratio, spearman) %>% arrange(test, pos, games, method) %>% mutate(across(c(pred, actual, ratio, spearman), ~ round(.x, 3)))
cat("WIDER POPULATION (rostered at week 9 with a draft pick or prior-season games; 2016-2025 redraft, 2016-2020 dynasty)\n")
print(as.data.frame(G), row.names = FALSE); write.csv(G, "rl_wide_groups.csv", row.names = FALSE)

# paired tests on the wider population: A2 vs A2+A3 (and current vs A2), by position
pc <- function(a, b, lab) bind_rows(cmp_rows(X[[a]]$r, X[[b]]$r, "redraft wk10-18"), cmp_rows(X[[a]]$d, X[[b]]$d, "dynasty 5 seasons", "pred")) %>%
  mutate(comparison = lab, .before = 1)
P <- bind_rows(pc("current", "A2", "current -> A2"), pc("A2", "A2+A3", "A2 -> A2+A3"), pc("A2", "A2+A3 future only", "A2 -> A2+A3 future only")) %>%
  mutate(across(c(base, variant, diff, lo, hi), ~ round(.x, 4)), sig = ifelse(lo > 0, "+", ifelse(hi < 0, "-", "")))
cat("\nPAIRED TESTS, wider population (diff = second - first; 95% player bootstrap):\n"); print(as.data.frame(P), row.names = FALSE)
write.csv(P, "rl_wide_paired.csv", row.names = FALSE)

# backup QBs: depth rank 2+ at the snapshot (depth chart for week 10)
source("rl_common.R")
dep <- bind_rows(lapply(2016:2025, function(y) role_snapshot(y, 9) %>% transmute(season = y, player_id, depth3, cat)))
bq <- bind_rows(lapply(names(X), function(m) bind_rows(
  X[[m]]$r %>% filter(pos == "QB") %>% left_join(dep, by = c("season", "player_id")) %>% filter(coalesce(depth3, 3L) >= 2) %>%
    summarise(n = n(), ratio = sum(value) / sum(actual), mean_pred = mean(value), mean_actual = mean(actual)) %>% mutate(test = "redraft wk10-18"),
  X[[m]]$d %>% filter(pos == "QB") %>% left_join(dep, by = c("season", "player_id")) %>% filter(coalesce(depth3, 3L) >= 2) %>%
    summarise(n = n(), ratio = sum(pred) / sum(actual), mean_pred = mean(pred), mean_actual = mean(actual)) %>% mutate(test = "dynasty 5 seasons")) %>%
  mutate(method = m))) %>% select(test, method, everything()) %>% mutate(across(where(is.numeric), ~ round(.x, 2)))
cat("\nQBs at depth rank 2+ at the snapshot (wider population): mean predicted vs actual value\n"); print(as.data.frame(bq), row.names = FALSE)
write.csv(bq, "rl_backup_qbs.csv", row.names = FALSE)

# named QBs: default-league ranks, live sample runs (the 2026 board)
NM <- c("Justin Fields", "Tua Tagovailoa", "Marcus Mariota", "Jameis Winston", "Carson Wentz", "Anthony Richardson", "Deshaun Watson")
nq <- bind_rows(lapply(c(current = "base", A2 = "a2", `A2+A3` = "a23", `A2+A3 future only` = "a23f"), function(t) { e <- readRDS(paste0("exp/dv11_", t, ".rds"))
  red <- e$d26 %>% arrange(desc(value)) %>% mutate(redraft_rank = row_number())
  e$b4 %>% select(name, pos, dynasty_rank = rank, value_100k) %>% filter(name %in% NM) %>%
    left_join(red %>% select(name, redraft_rank, any_of(c("cat", "depth_rank"))), by = "name") %>% mutate(method = t) }), .id = "m") %>%
  mutate(method = m) %>% select(name, method, dynasty_rank, value_100k, redraft_rank, any_of(c("cat", "depth_rank"))) %>% arrange(name, method)
cat("\nNAMED QBs, default league (12 teams superflex), 2026 board:\n"); print(as.data.frame(nq), row.names = FALSE)
write.csv(nq, "rl_named_qbs.csv", row.names = FALSE)

# season-length fix: dynasty backtest totals with every future season at 17 games vs its real length
lf <- bind_rows(lapply(c(`17 games (live)` = "base", `real length` = "base_lf", `A2, 17 games` = "a2", `A2, real length` = "a2_lf"), function(t) {
  b <- readRDS(paste0("exp/dv11_", t, ".rds"))$BT
  bind_rows(b %>% group_by(pos) %>% summarise(spearman = cor(pred, actual, method = "spearman"), pred = sum(pred), actual = sum(actual), .groups = "drop"),
            b %>% summarise(pos = "all", pred = sum(pred), actual = sum(actual), spearman = cor(pred, actual, method = "spearman"))) }), .id = "run") %>%
  mutate(ratio = round(pred / actual, 3), pred = round(pred), actual = round(actual), spearman = round(spearman, 3))
cat("\nSEASON-LENGTH FIX, dynasty backtest (week-9 snapshots 2016-2020, 3+ games):\n"); print(as.data.frame(lf), row.names = FALSE)
write.csv(lf, "rl_lenfix_totals.csv", row.names = FALSE)
