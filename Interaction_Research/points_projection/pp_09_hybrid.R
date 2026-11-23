# Kyle 2026-11-21: hybrid = PPG model for the top 24, current tier method outside. Also a 50/50 blend of current and 3-year PPG values.
# Hybrid keeps everyone's order within each group; the top 24 (consensus rank) stay above everyone else in every version.
suppressMessages(library(dplyr))
d <- readRDS("top24_all_players.rds") %>% group_by(class) %>% mutate(cons = rank((r_current + r_ppg1 + r_ppg3) / 3, ties.method = "first")) %>% ungroup()
d <- d %>% mutate(top = cons <= 24, hyb3 = ifelse(top, 1e4 + ppg3, current), hyb1 = ifelse(top, 1e4 + ppg1, current),
  cur_cons = ifelse(top, 1e4 + current, current), blend = (current + ppg3) / 2, blend_all = (current + ppg1 + ppg3) / 3)
M <- c(current = "Current (tier odds)", ppg3 = "3-year PPG", cur_cons = "Current, top 24 held as a block", hyb3 = "Hybrid: 3-yr PPG top 24, current outside",
       hyb1 = "Hybrid: rookie PPG top 24, current outside", blend = "Blend: average of current and 3-yr PPG", blend_all = "Blend: average of all three")
sp <- function(a, b) suppressWarnings(cor(a, b, method = "spearman"))
f <- function(x, m) mean(sapply(split(x, x$class), function(z) sp(z[[m]], z$realized)))
t12 <- function(x, m) mean(sapply(split(x, x$class), function(z) sum(z$realized[order(-z[[m]])[1:12]])))
t24 <- function(x, m) mean(sapply(split(x, x$class), function(z) sum(z$realized[order(-z[[m]])[1:24]])))
set.seed(2026)
bs <- replicate(1000, { cl <- sample(unique(d$class), replace = TRUE)
  z <- bind_rows(lapply(seq_along(cl), function(j) { w <- d[d$class == cl[j], ]; w[sample.int(nrow(w), replace = TRUE), ] %>% mutate(class = j) }))
  sapply(names(M), function(m) f(z, m)) })
out <- data.frame(method = M, rho_all = sapply(names(M), function(m) f(d, m)), top12_realized = sapply(names(M), function(m) t12(d, m)),
  top24_realized = sapply(names(M), function(m) t24(d, m)),
  gap_lo = apply(bs - matrix(bs["current", ], nrow(bs), ncol(bs), byrow = TRUE), 1, quantile, .025),
  gap_hi = apply(bs - matrix(bs["current", ], nrow(bs), ncol(bs), byrow = TRUE), 1, quantile, .975),
  classes_beat_current = sapply(names(M), function(m) sum(sapply(split(d, d$class), function(z) sp(z[[m]], z$realized) > sp(z$current, z$realized)))))
out$gap <- out$rho_all - out$rho_all[1]
write.csv(out, "hybrid_test.csv", row.names = FALSE); print(out, digits = 3, row.names = FALSE)
