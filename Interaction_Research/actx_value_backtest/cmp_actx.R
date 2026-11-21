suppressMessages(library(dplyr))
L <- readRDS("exp/dv11_live.rds"); X <- readRDS("exp/dv11_actx.rds")
ev <- function(B, tag) bind_rows(lapply(1:5, function(t) data.frame(pos = B$pos, t = t, S = B$S[, t], y = as.numeric(B$AG[, t] >= 1)))) %>%
  mutate(S = pmin(pmax(S, 1e-4), 1 - 1e-4)) %>% group_by(pos) %>%
  summarise(brier = mean((S - y)^2), logloss = -mean(y * log(S) + (1 - y) * log(1 - S)), pred_alive = mean(S), actual_alive = mean(y), .groups = "drop") %>% mutate(model = tag)
E <- bind_rows(ev(L$BT, "live"), ev(X$BT, "with terms")); print(as.data.frame(E %>% mutate(across(where(is.double), ~ round(.x, 4)))))
ae <- function(B, tag) B %>% group_by(pos) %>% summarise(pred = sum(pred), actual = sum(actual), AE = actual / pred, sp = cor(pred, actual, method = "spearman"), .groups = "drop") %>% mutate(model = tag)
print(as.data.frame(bind_rows(ae(L$BT, "live"), ae(X$BT, "with terms")) %>% mutate(across(where(is.double), ~ round(.x, 3)))))
b <- L$b4 %>% select(name, pos, age, exp, draft_pick, rank, value_100k) %>% inner_join(X$b4 %>% select(name, pos, rank_x = rank, value_x = value_100k), by = c("name", "pos")) %>%
  mutate(dval = value_x - value_100k, pct = round(100 * (value_x / value_100k - 1), 1), drank = rank - rank_x)
top <- b %>% filter(rank <= 200)
cat("\ntop-200 on live board: median |% change|", median(abs(top$pct)), " max", max(abs(top$pct)), " rank moves >=5:", sum(abs(top$drank) >= 5), "\n")
print(top %>% summarise(spearman_rank = cor(rank, rank_x)))
cat("\nbiggest risers (top 200):\n"); print(as.data.frame(top %>% arrange(desc(pct)) %>% head(12)), row.names = FALSE)
cat("\nbiggest fallers (top 200):\n"); print(as.data.frame(top %>% arrange(pct) %>% head(12)), row.names = FALSE)
cat("\nby position, top 200 median % change:\n"); print(as.data.frame(top %>% group_by(pos) %>% summarise(n = n(), med = median(pct), mean = round(mean(pct), 1))))
write.csv(b %>% arrange(rank), "actx_board_compare.csv", row.names = FALSE); write.csv(E, "actx_survival_eval.csv", row.names = FALSE)
