# =============================================================================
# Dynasty Model, step 5: the Dynasty Value Score
#
#   DVS = sum_{t=1}^{10} v^(t-1) * S(t) * E[PAR+_t | alive],   v = 1/1.15
#   S(t)   = average of the hazard GLM and the survival forest
#   E[PAR+]= average of the Tweedie GLM and the production forest
# Part A: backtest on held-out landmarks 2018-2022 (models fit on 2007-2017), 3-season value vs what happened
# Part B: score every active QB/RB/WR/TE as of the 2026 season (through the latest week in the data)
# =============================================================================
source("dv_common.R"); suppressMessages({ library(ranger); library(statmod); library(ggplot2) })
cat("== Dynasty step 5: value score ==\n")
lm <- readRDS("dv_landmarks.rds"); pp <- readRDS("dv_person_period.rds")

# ---------------- A. backtest ----------------
sm_tr <- readRDS("dv_survival_models_train.rds"); pm_tr <- readRDS("dv_production_models_train.rds")
bt <- lm %>% filter(season %in% 2018:2022, !is.na(time))
real <- pp %>% filter(lm_season %in% 2018:2022, t <= 3) %>% group_by(player_id, lm_season) %>%
  summarise(actual3 = sum(y * (1 - event)), .groups = "drop")
bt <- bt %>% left_join(real, by = c("player_id", "season" = "lm_season")) %>% mutate(actual3 = coalesce(actual3, 0))
vp <- value_parts(sm_tr, pm_tr, bt, i = 0, offset = rep(0, nrow(bt)))
bt$pred3 <- vp$win_now; bt$naive3 <- 3 * pmax(bt$par, 0)
ev <- function(d, lab) data.frame(players = lab, n = nrow(d),
  spearman_model = cor(d$pred3, d$actual3, method = "spearman"), spearman_naive = cor(d$naive3, d$actual3, method = "spearman"),
  rmse_model = sqrt(mean((d$pred3 - d$actual3)^2)), rmse_naive = sqrt(mean((d$naive3 - d$actual3)^2)),
  mean_pred = mean(d$pred3), mean_actual = mean(d$actual3))
bres <- bind_rows(ev(bt, "all"), ev(bt %>% filter(startable == 1), "startable at landmark"),
                  lapply(POSITIONS, function(ps) ev(bt %>% filter(pos == ps, startable == 1), paste(ps, "startable")))) %>%
  mutate(across(where(is.numeric), ~ round(.x, 3)))
cat("\nBACKTEST: predicted vs actual PAR+ over the next 3 seasons (landmarks 2018-2022, models fit on 2007-2017)\n")
print(bres); write.csv(bres, "dv_value_backtest_metrics.csv", row.names = FALSE)
# actual vs expected by predicted decile (an actuarial A/E table)
ae <- bt %>% mutate(decile = ntile(pred3, 10)) %>% group_by(decile) %>%
  summarise(n = n(), expected = mean(pred3), actual = mean(actual3), AE = actual / expected) %>% mutate(across(where(is.numeric), ~ round(.x, 2)))
cat("\nActual / Expected by decile of predicted 3-season value:\n"); print(ae); write.csv(ae, "dv_value_backtest_AE.csv", row.names = FALSE)
g <- ggplot(ae, aes(expected, actual)) + geom_abline(lty = 2, color = "grey50") + geom_point(size = 3, color = "#0072B2") + geom_line(color = "#0072B2") +
  labs(title = "Backtest: expected vs actual points above replacement over the next 3 seasons",
       subtitle = "Held-out landmarks 2018-2022, grouped into 10 bins by predicted value", x = "Expected (model)", y = "Actual") + theme_minimal(base_size = 12)
ggsave("plot_value_backtest.png", g, width = 8, height = 5, dpi = 120)
write.csv(bt %>% select(season, name, pos, age, startable, par, pred3, naive3, actual3) %>% mutate(across(where(is.numeric), ~ round(.x, 1))),
          "dv_value_backtest_players.csv", row.names = FALSE)

# ---------------- B. active players ----------------
sm <- readRDS("dv_survival_models.rds"); pm <- readRDS("dv_production_models.rds")
ACTIVE_STATUS <- c("ACT", "RES", "PUP", "INA", "NWT", "DEV", "SUS", "EXE")
cur <- lm %>% filter(season == CUR)
latest_week <- max(readRDS("nfl_weekly_2026.rds")$week)
# players with 3+ games in 2026 are valued from their 2026 pace; others (injured, suspended, buried) from 2025
a26 <- cur %>% filter(games >= 3, !roster_status %in% c("RET")) %>% mutate(basis = paste0("2026 through week ", latest_week), offset = 0)
a25 <- lm %>% filter(season == LAST_FULL, roster_status %in% ACTIVE_STATUS, !player_id %in% a26$player_id) %>%
  mutate(basis = "2025 season (under 3 games in 2026)", offset = 1)
act <- bind_rows(a26, a25)
cat("\nactive players valued:", nrow(act), " (2026 basis:", nrow(a26), ", 2025 basis:", nrow(a25), ")\n")
vp <- value_parts(sm, pm, act, i = I_MAIN, offset = act$offset)
board <- bind_cols(act %>% select(player_id, name, pos, team, latest_team, age, exp, draft, draft_pick, games, rank, startable, par, basis), vp) %>%
  mutate(team = coalesce(latest_team, team)) %>% select(-latest_team)
board$age_2027 <- round(board$age + ifelse(board$basis == "2025 season (under 3 games in 2026)", 2, 1), 1)
top <- max(board$dvs)
board <- board %>% mutate(score = round(100 * dvs / top, 1),
                          rank_overall = rank(-dvs, ties.method = "first")) %>%
  group_by(pos) %>% mutate(rank_pos = rank(-dvs, ties.method = "first")) %>% ungroup() %>%
  mutate(rank_win_now = rank(-win_now, ties.method = "first"), rank_rebuild = rank(-dvs_0, ties.method = "first"),
         tier = cut(score, c(-Inf, 10, 25, 45, 70, Inf), labels = c("Depth", "Flex", "Starter", "Core", "Cornerstone"))) %>%
  arrange(rank_overall)
out <- board %>% transmute(rank_overall, rank_pos, name, pos, team, age_2027, exp, draft, draft_pick, basis,
  current_rank = rank, current_par = round(par, 1), score, tier, dvs_points = round(dvs, 1),
  win_now_3yr = round(win_now, 1), rebuild_value_i0 = round(dvs_0, 1), contend_value_i30 = round(dvs_30, 1),
  exp_alive_seasons = round(e_life, 2), S_2027 = round(S1, 3), S_2029 = round(S3, 3), S_2031 = round(S5, 3),
  exp_par_2027 = round(par_next, 1), rank_win_now, rank_rebuild, player_id)
write.csv(out, "dv_dynasty_value_board.csv", row.names = FALSE)
cat("\nTOP 40 DYNASTY VALUES (i = 15%):\n")
print(out %>% select(rank_overall, name, pos, team, age_2027, score, dvs_points, win_now_3yr, exp_alive_seasons, S_2029, exp_par_2027) %>% head(40), n = 40)
for (ps in POSITIONS) { cat("\nTop 12", ps, "\n")
  print(out %>% filter(pos == ps) %>% select(rank_pos, rank_overall, name, team, age_2027, score, win_now_3yr, exp_alive_seasons) %>% head(12)) }
cat("\nScore by tier:\n"); print(table(out$tier, out$pos))

# value vs age picture
g <- ggplot(out %>% filter(score >= 5), aes(age_2027, score, color = pos)) + geom_point(alpha = .75) + scale_color_manual(values = mycols) +
  geom_text(data = out %>% group_by(pos) %>% slice_head(n = 4), aes(label = name), size = 3, vjust = -0.8, show.legend = FALSE) +
  labs(title = "Dynasty Value Score vs age (players scoring 5+)", x = "Age in 2027", y = "Dynasty Value Score (top = 100)", color = NULL) +
  theme_minimal(base_size = 12)
ggsave("plot_value_vs_age.png", g, width = 9, height = 6, dpi = 120)
