suppressMessages({ library(dplyr); library(ggplot2) })
th <- theme_minimal(base_size = 12) + theme(plot.title = element_text(face = "bold"), panel.grid.minor = element_blank(), plot.background = element_rect(fill = "white", colour = NA))
b <- read.csv("actx_board_compare.csv") %>% filter(rank <= 200)
lab <- b %>% filter(abs(pct) >= 12)
g <- ggplot(b, aes(rank, pct, colour = pos)) + geom_hline(yintercept = 0) + geom_point(size = 2, alpha = .8) +
  geom_text(data = lab, aes(label = name), size = 3, vjust = -0.7, show.legend = FALSE) +
  scale_colour_manual(values = c(QB = "#D55E00", RB = "#009E73", WR = "#0072B2", TE = "#E69F00")) +
  labs(x = "current dynasty rank (live board)", y = "% change in value with the still-playing terms", colour = NULL,
       title = "Still-playing fix: how the 2026 dynasty board would move (top 200)", subtitle = "Rookies and young QBs rise; veteran and backup QBs fall") + th
ggsave("actx_board_change.png", g, width = 12, height = 6.5, dpi = 130)
e <- read.csv("actx_survival_eval.csv")
g <- ggplot(e, aes(logloss, pos, colour = model)) + geom_point(size = 3.5) + scale_colour_manual(values = c(live = "#111111", "with terms" = "#D55E00"), name = NULL) +
  labs(x = "log loss of 'still playing in season +1..+5' (lower = better)", y = NULL, title = "Still-playing fix over the full 5-season horizon (week-9 snapshots 2016-2020)") + th
ggsave("actx_survival_5yr.png", g, width = 9, height = 4, dpi = 130)
