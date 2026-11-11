# =============================================================================
# Dynasty Model, step 7: plain-English effect sizes
# GLM coefficients on spline terms and correlated inputs (par, par_rate, par_best3) are hard to read
# one at a time, so this asks the fitted models a simple question instead: for today's startable
# players, how much do expected alive seasons and the score change when one input changes and
# everything else stays the same? (a finite-difference partial dependence)
# =============================================================================
source("dv_common.R"); suppressMessages({ library(ranger); library(statmod) })
cat("== Dynasty step 7: effect sizes ==\n")
sm <- readRDS("dv_survival_models.rds"); pm <- readRDS("dv_production_models.rds")
lm <- readRDS("dv_landmarks.rds"); board <- read.csv("dv_dynasty_value_board.csv"); top <- max(board$dvs_points)
base <- lm %>% filter(season == CUR, games >= 3, startable == 1)
avg <- function(d) { v <- value_parts(sm, pm, d, offset = rep(0, nrow(d))); c(e_life = mean(v$e_life), score = mean(100 * v$dvs / top)) }
b0 <- avg(base)
shift <- list(
  "2 years older"                          = function(d) { d$age <- d$age + 2; d$exp <- d$exp + 2; d },
  "+50 points above replacement this year" = function(d) { d$par <- d$par + 50; d$par_rate <- d$par_rate + 50; d$par_best3 <- pmax(d$par_best3, d$par); d },
  "+50 on best season of the last three"   = function(d) { d$par_best3 <- d$par_best3 + 50; d },
  "same points, but missed 1 in 4 games"   = function(d) { d$games_frac <- 0.75; d },
  "had gone undrafted"                     = function(d) { d$draft <- factor("UDFA", levels(lm$draft)); d })
res <- bind_rows(lapply(names(shift), function(n) bind_rows(lapply(POSITIONS, function(ps) {
  d <- base %>% filter(pos == ps); a <- avg(d); b <- avg(shift[[n]](d))
  data.frame(change = n, pos = ps, e_life_before = a[1], e_life_after = b[1], score_before = a[2], score_after = b[2]) }))))
res <- res %>% mutate(e_life_change = e_life_after - e_life_before, score_change_pct = 100 * (score_after / score_before - 1)) %>%
  mutate(across(where(is.numeric), ~ round(.x, 2)))
print(res %>% select(change, pos, e_life_change, score_change_pct), row.names = FALSE)
write.csv(res, "dv_effect_sizes.csv", row.names = FALSE)
