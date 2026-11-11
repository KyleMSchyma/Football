# =============================================================================
# Dynasty Model, step 2: Kaplan-Meier "life tables" (no covariates, just the data)
#
# Two views:
#   A. Career curves from the rookie season, by position and by draft capital
#   B. "Once startable" curves: players who were startable in a season, by position x age band.
#      This is the dynasty question: I own a startable player today, how long does it last?
# Event = second straight season below QB24 / RB24 / WR36 / TE12 (not playing counts as below).
# =============================================================================
source("dv_common.R"); suppressMessages(library(ggplot2))
cat("== Dynasty step 2: Kaplan-Meier ==\n")
lm <- readRDS("dv_landmarks.rds") %>% filter(!is.na(time), season <= LAST_FULL - 1)

life_table <- function(fit, label) {
  sm <- summary(fit, times = 1:10, extend = TRUE)
  data.frame(group = sub("^[^=]*=", "", as.character(sm$strata)), t = sm$time, at_risk = sm$n.risk,
             S = round(sm$surv, 3), lo = round(sm$lower, 3), hi = round(sm$upper, 3), view = label)
}
km_plot <- function(fit, title, file, colors = NULL) {
  d <- data.frame(t = fit$time, S = fit$surv, lo = fit$lower, hi = fit$upper,
                  group = rep(sub("^[^=]*=", "", names(fit$strata)), fit$strata))
  d <- bind_rows(d %>% distinct(group) %>% mutate(t = 0, S = 1, lo = 1, hi = 1), d) %>% filter(t <= 10)
  g <- ggplot(d, aes(t, S, color = group, fill = group)) + geom_step(linewidth = 1) +
    geom_ribbon(aes(ymin = lo, ymax = hi), alpha = .08, color = NA, stat = "identity") +
    scale_x_continuous(breaks = 0:10) + scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
    labs(title = title, x = "Seasons from the starting point", y = "Still startable-alive", color = NULL, fill = NULL) +
    theme_minimal(base_size = 12)
  if (!is.null(colors)) g <- g + scale_color_manual(values = colors) + scale_fill_manual(values = colors)
  ggsave(file, g, width = 8, height = 5, dpi = 120)
}

# ---- A. from the rookie season ----
rk <- lm %>% filter(exp == 0, season >= 2007)
fa <- survfit(Surv(time, status) ~ pos, data = rk)
fb <- survfit(Surv(time, status) ~ draft, data = rk)
cat("rookies:", nrow(rk), "\n"); print(fa); print(fb)
cat("log-rank by position:\n"); print(survdiff(Surv(time, status) ~ pos, data = rk))
cat("log-rank by draft capital:\n"); print(survdiff(Surv(time, status) ~ draft, data = rk))
km_plot(fa, "Career survival from the rookie season, by position", "plot_km_rookie_by_pos.png", mycols)
km_plot(fb, "Career survival from the rookie season, by draft capital", "plot_km_rookie_by_draft.png")

# ---- B. once startable ----
st <- lm %>% filter(startable == 1) %>%
  mutate(age_band = cut(age, c(0, 24, 27, 30, 50), labels = c("<=24", "25-27", "28-30", "31+"), right = FALSE))
fc <- survfit(Surv(time, status) ~ pos, data = st)
cat("\nstartable player-seasons:", nrow(st), "\n"); print(fc)
km_plot(fc, "Once startable: how long a startable player stays alive, by position", "plot_km_startable_by_pos.png", mycols)
tabs <- list(life_table(fa, "rookie_by_pos"), life_table(fb, "rookie_by_draft"), life_table(fc, "startable_by_pos"))
for (ps in POSITIONS) {
  f <- survfit(Surv(time, status) ~ age_band, data = st %>% filter(pos == ps))
  km_plot(f, paste0("Once startable ", ps, "s: survival by age"), paste0("plot_km_startable_", ps, "_by_age.png"))
  tabs[[length(tabs) + 1]] <- life_table(f, paste0("startable_", ps, "_by_age"))
  cat(ps, "by age band:\n"); print(f)
}
lt <- bind_rows(tabs)
write.csv(lt, "dv_km_life_tables.csv", row.names = FALSE)
cat("\n'Once startable' life table (S at 1, 3, 5 seasons):\n")
print(lt %>% filter(t %in% c(1, 3, 5), grepl("startable", view)) %>% select(view, group, t, S) %>%
        pivot_wider(names_from = t, values_from = S, names_prefix = "S"))
# curtate life expectancy e = sum S(t), t = 1..10
cat("\nexpected startable-alive seasons (sum of S(t), t = 1..10):\n")
print(lt %>% group_by(view, group) %>% summarise(e = round(sum(S), 2), .groups = "drop"), n = 40)
