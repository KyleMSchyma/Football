# =============================================================================
# B4 board: default league (12 teams superflex) dynasty board, players and 2027 pick slots, top 60, before and after
#   ./run.sh rl_board60.R logs/board60.txt <before_tag> <after_tag>    (exp/b4_<tag>.rds from rl_b4_picks.R)
# before: live model, players as projected, picks x the live multiplier.
# after : the dev model, players x per-position multiplier (actual / predicted in the dynasty backtest), picks x the
#         multiplier refit on the same definition of realized value. 100k = the top player in each board.
# =============================================================================
suppressMessages(library(dplyr)); options(width = 200)
a <- commandArgs(trailingOnly = TRUE)
mk <- function(tag, cal) { e <- readRDS(paste0("exp/b4_", tag, ".rds"))
  pl <- e$players %>% mutate(value = raw * (if (cal) e$mpos[pos] else 1), prospect = "")
  pk <- e$slots %>% mutate(value = raw * (if (cal) e$f_same else e$f_live), team = "")
  bind_rows(pl, pk) %>% filter(!is.na(value)) %>% arrange(desc(value)) %>% mutate(rank = row_number(), value_100k = round(1e5 * value / max(value[pos != "PICK"]))) }
B <- mk(a[1], FALSE); A <- mk(a[2], TRUE)
eb <- readRDS(paste0("exp/b4_", a[1], ".rds")); ea <- readRDS(paste0("exp/b4_", a[2], ".rds"))
cat(sprintf("before: pick multiplier %.3f (95%% %.2f-%.2f), players unscaled\n", eb$f_live, quantile(eb$boot_live, .025), quantile(eb$boot_live, .975)))
cat(sprintf("after : pick multiplier %.3f (95%% %.2f-%.2f), players x %s\n", ea$f_same, quantile(ea$boot_same, .025), quantile(ea$boot_same, .975),
            paste(names(ea$mpos), round(ea$mpos, 3), collapse = " ")))
J <- full_join(B %>% select(name, pos, rank_before = rank, value_before = value_100k),
               A %>% select(name, pos, team, age, prospect, rank_after = rank, value_after = value_100k), by = c("name", "pos")) %>%
  filter(pmin(rank_before, rank_after, na.rm = TRUE) <= 60) %>% arrange(rank_after)
print(as.data.frame(J %>% mutate(age = round(age, 1))), row.names = FALSE)
write.csv(J, "rl_board60_before_after.csv", row.names = FALSE)
cat("\npicks in the top 60: before", sum(B$pos[B$rank <= 60] == "PICK"), " after", sum(A$pos[A$rank <= 60] == "PICK"),
    "\nposition mix top 60 before:", paste(names(table(B$pos[B$rank <= 60])), table(B$pos[B$rank <= 60]), collapse = " "),
    "\nposition mix top 60 after: ", paste(names(table(A$pos[A$rank <= 60])), table(A$pos[A$rank <= 60]), collapse = " "), "\n")
