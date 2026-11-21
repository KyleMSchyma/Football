# Kyle 2026-11-21: which method ranks best inside the top 24 and outside it? Segments use a common yardstick:
# consensus rank = mean of the three methods' class ranks (top 24 by consensus vs everyone else). Within each segment and class:
# Spearman with realized value, then averaged over classes; paired bootstrap (classes, then players) of each PPG method minus current.
suppressMessages(library(dplyr))
d <- readRDS("top24_all_players.rds") %>% group_by(class) %>% mutate(cons = rank((r_current + r_ppg1 + r_ppg3) / 3, ties.method = "first"),
  seg = ifelse(cons <= 24, "Top 24 (consensus)", "Outside top 24")) %>% ungroup()
M <- c(current = "Current (tier odds)", ppg1 = "Rookie-year PPG", ppg3 = "3-year PPG")
sp <- function(a, b) suppressWarnings(cor(a, b, method = "spearman"))
f <- function(x, m) mean(sapply(split(x, x$class), function(z) sp(z[[m]], z$realized)), na.rm = TRUE)
set.seed(2026)
out <- bind_rows(lapply(unique(d$seg), function(s) { x <- d[d$seg == s, ]
  bs <- replicate(1000, { cl <- sample(unique(x$class), replace = TRUE)
    z <- bind_rows(lapply(seq_along(cl), function(j) { w <- x[x$class == cl[j], ]; w[sample.int(nrow(w), replace = TRUE), ] %>% mutate(class = j) }))
    c(f(z, "current"), f(z, "ppg1"), f(z, "ppg3")) })
  bind_rows(lapply(seq_along(M), function(i) { m <- names(M)[i]
    data.frame(segment = s, method = M[[m]], n = nrow(x), rho = f(x, m),
      gap = f(x, m) - f(x, "current"), gap_lo = quantile(bs[i, ] - bs[1, ], .025), gap_hi = quantile(bs[i, ] - bs[1, ], .975),
      classes_beat_current = sum(sapply(split(x, x$class), function(z) sp(z[[m]], z$realized) > sp(z$current, z$realized)), na.rm = TRUE),
      pred_over_actual = sum(x[[m]]) / sum(x$realized)) })) }))
write.csv(out, "top24_split.csv", row.names = FALSE); print(out, digits = 3, row.names = FALSE)
