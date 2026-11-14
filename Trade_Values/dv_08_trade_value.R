# =============================================================================
# Dynasty Model, step 8: trade value scale (sums trade fairly)
#
# The Dynasty Value Score is additive in points, but roster and lineup spots are limited, so one
# great player is worth more than two good ones (the consolidation premium). The trade value is a
# convex curve on overall rank, fit to Kyle's "anchor trades" in dv_trade_anchors.csv
# (row: the player at get_rank is worth the players at give_rank_1 + give_rank_2).
#
#   Trade value(rank r) = 100 * exp(-a * (r - 1)^b)        (stretched exponential, 2 parameters)
#
# a and b minimize the squared log-error of the anchors. Edit the anchors CSV and re-run to refit.
# Compared against 1-parameter curves (rank^-alpha, score^k) to show the extra parameter is worth it.
# =============================================================================
source("dv_common.R"); suppressMessages(library(ggplot2))
cat("== Dynasty step 8: trade value ==\n")
b <- read.csv("dv_dynasty_value_board.csv"); s <- b$score / 100
A <- read.csv("dv_trade_anchors.csv")
loss <- function(f) sum((log(f(A$get_rank)) - log(f(A$give_rank_1) + f(A$give_rank_2)))^2)
fits <- list()
o <- optimize(function(k) loss(function(r) s[r]^k), c(0.3, 8));          fits$`score^k` <- list(f = function(r) s[r]^o$minimum, par = c(k = o$minimum), loss = o$objective)
o <- optimize(function(a) loss(function(r) r^-a), c(0.01, 3));             fits$`rank^-alpha` <- list(f = function(r) r^-o$minimum, par = c(alpha = o$minimum), loss = o$objective)
o <- optim(c(log(0.2), 0.8), function(p) loss(function(r) exp(-exp(p[1]) * (r - 1)^p[2])))
fits$`stretched exponential` <- list(f = function(r) exp(-exp(o$par[1]) * (r - 1)^o$par[2]), par = c(a = exp(o$par[1]), b = o$par[2]), loss = o$value)
for (n in names(fits)) cat(sprintf("%-22s loss %.4f  params %s\n", n, fits[[n]]$loss, paste(names(fits[[n]]$par), round(fits[[n]]$par, 4), sep = "=", collapse = " ")))

f <- fits$`stretched exponential`$f
chk <- A %>% mutate(get_value = round(100 * f(get_rank), 1), give_value = round(100 * (f(give_rank_1) + f(give_rank_2)), 1),
                    give_over_get = round(give_value / get_value, 2))
cat("\nAnchor check (stretched exponential): give / get should be near 1\n"); print(chk)
write.csv(chk, "dv_trade_anchor_check.csv", row.names = FALSE)

b$trade_value <- round(100 * f(b$rank_overall), 1)
write.csv(b, "dv_dynasty_value_board.csv", row.names = FALSE)
cat("\nTrade values at selected ranks:\n")
r <- c(1, 2, 3, 5, 7, 8, 10, 12, 15, 20, 24, 30, 36, 40, 45, 50, 60, 80, 100, 150)
print(data.frame(rank = r, name = b$name[r], score = b$score[r], trade_value = b$trade_value[r]))
cat("\nHow many players at rank r equal the #1 player:\n"); print(data.frame(rank = c(5, 10, 20, 36, 50, 100), n = round(1 / f(c(5, 10, 20, 36, 50, 100)), 1)))

g <- ggplot(b %>% filter(rank_overall <= 150), aes(rank_overall, trade_value)) + geom_line(color = "#0072B2", linewidth = 1.1) +
  geom_point(data = b %>% filter(rank_overall %in% unique(unlist(A))), color = "#D55E00", size = 2.5) +
  labs(title = "Trade value curve fit to the anchor trades", subtitle = "Orange points are ranks used in the anchors",
       x = "Overall dynasty rank", y = "Trade value (#1 = 100)") + theme_minimal(base_size = 12)
ggsave("plot_trade_value_curve.png", g, width = 8, height = 5, dpi = 120)
