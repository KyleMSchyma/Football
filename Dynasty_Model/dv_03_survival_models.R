# =============================================================================
# Dynasty Model, step 3: survival models for S(t) = P(still alive in season t)
#
#   1. Kaplan-Meier by position             (baseline, no player detail)
#   2. Discrete-time logistic hazard GLM    (one row per player x future season at risk)
#   3. Cox proportional hazards             (robust SEs clustered on player)
#   4. Survival random forest (ranger)      (non-parametric comparison)
# Train on landmark seasons 2007-2017, test on 2018-2024 (outcomes through 2025).
# Metrics: Harrell's C on expected lifetime, plus AUC and Brier for "alive at t" (t = 1, 2, 3, 5)
# =============================================================================
source("dv_common.R"); suppressMessages({ library(ranger); library(ggplot2) })
cat("== Dynasty step 3: survival models ==\n")
lm <- readRDS("dv_landmarks.rds"); pp <- readRDS("dv_person_period.rds")
lm_fit <- lm %>% filter(!is.na(time))
# structural zeros: a player startable at the landmark (or a rookie) cannot die in season 1
pp <- pp %>% mutate(free = t == 1 & (startable == 1 | exp == 0))

# ---------- prediction helpers: S(t), t = 1..H for each row of nd (S_glm, S_rsf live in dv_common.R) ----------
S_cox <- function(fit, nd) {
  sf <- survfit(fit, newdata = nd); s <- summary(sf, times = 1:H, extend = TRUE)
  matrix(s$surv, ncol = H, byrow = TRUE)
}
S_km <- function(fit, nd) {
  out <- matrix(NA, nrow(nd), H)
  for (ps in POSITIONS) { s <- summary(fit[paste0("pos=", ps)], times = 1:H, extend = TRUE)$surv
    out[nd$pos == ps, ] <- matrix(s, sum(nd$pos == ps), H, byrow = TRUE) }
  out
}
cox_formula <- Surv(time, status) ~ pos * (age + par) + I(age^2) + I(pmax(par, 0)^2 / 100) + exp + draft + par_prev +
  startable + startable_prev + n_startable + games_frac + opp_pg + par_rate + par_best3 + cluster(player_id)

fit_all <- function(lmd, ppd, imp = "none") {
  list(km  = survfit(Surv(time, status) ~ pos, data = lmd),
       glm = glm(hz_formula, family = binomial, data = ppd %>% filter(!free)),
       cox = coxph(cox_formula, data = lmd, ties = "efron", model = TRUE),
       rsf = ranger(Surv(time, status) ~ ., data = lmd[, c("time", "status", FEATS)], num.trees = 500,
                    min.node.size = 25, mtry = 4, importance = imp, seed = 2026))
}
predict_all <- function(m, nd) list(KM = S_km(m$km, nd), GLM = S_glm(m$glm, nd), Cox = S_cox(m$cox, nd), RSF = S_rsf(m$rsf, nd))

# ---------- train / test ----------
tr <- lm_fit %>% filter(season %in% TRAIN_LM); te <- lm_fit %>% filter(season %in% TEST_LM)
# censor training follow-up at 2017 + horizon? No: the test set uses later SEASONS, but training outcomes may
# run into 2018-2025. That is allowed here because the split is by landmark, and the test landmarks are new
# player-seasons. A stricter time split (outcomes <= 2017) is reported as a check below.
m_tr <- fit_all(tr, pp %>% filter(lm_season %in% TRAIN_LM))
saveRDS(m_tr, "dv_survival_models_train.rds")   # used by the value backtest in step 5
cat("train landmarks:", nrow(tr), " test landmarks:", nrow(te), "\n")
P <- predict_all(m_tr, te); P$Blend <- (P$GLM + P$RSF) / 2   # simple 50/50 model average

eval_model <- function(S, d) {
  eL <- rowSums(S)
  C <- concordance(Surv(d$time, d$status) ~ eL)$concordance
  res <- data.frame(metric = "C-index (expected life)", t = NA, value = C)
  for (k in c(1, 2, 3, 5)) {
    ok <- d$season + k <= LAST_FULL
    y <- as.integer(!(d$status[ok] == 1 & d$time[ok] <= k)); p <- S[ok, k]
    res <- rbind(res, data.frame(metric = c("AUC alive", "Brier alive", "mean pred - actual"), t = k,
                                 value = c(aucf(y, p), brier(p, y), mean(p) - mean(y))))
  }
  res
}
met <- bind_rows(lapply(names(P), function(n) eval_model(P[[n]], te) %>% mutate(model = n)))
met_w <- met %>% mutate(value = round(value, 4)) %>% pivot_wider(names_from = model, values_from = value)
cat("\nTEST metrics (landmarks 2018-2024):\n"); print(as.data.frame(met_w))

# same metrics on startable-at-landmark players only (the ones dynasty managers care about)
sti <- te$startable == 1
met_st <- bind_rows(lapply(names(P), function(n) eval_model(P[[n]][sti, ], te[sti, ]) %>% mutate(model = n))) %>%
  mutate(value = round(value, 4)) %>% pivot_wider(names_from = model, values_from = value)
cat("\nTEST metrics, startable players only:\n"); print(as.data.frame(met_st))

# strict check: training outcomes censored at the end of 2017 (no peeking past the split)
cens <- function(d, end) d %>% mutate(over = season + time > end,
                                      status = ifelse(over, 0, status), time = ifelse(over, end - season, time)) %>%
  filter(time >= 1)
tr_s <- cens(tr, 2017); pp_s <- pp %>% filter(lm_season %in% TRAIN_LM, lm_season + t <= 2017)
m_s <- fit_all(tr_s, pp_s); P_s <- predict_all(m_s, te); P_s$Blend <- (P_s$GLM + P_s$RSF) / 2
met_s <- bind_rows(lapply(names(P_s), function(n) eval_model(P_s[[n]], te) %>% mutate(model = n))) %>%
  filter(metric != "mean pred - actual") %>% mutate(value = round(value, 4)) %>% pivot_wider(names_from = model, values_from = value)
cat("\nSTRICT time split (training outcomes stop at 2017):\n"); print(as.data.frame(met_s))

write.csv(bind_rows(met %>% mutate(set = "test_all"),
                    bind_rows(lapply(names(P), function(n) eval_model(P[[n]][sti, ], te[sti, ]) %>% mutate(model = n))) %>% mutate(set = "test_startable"),
                    bind_rows(lapply(names(P_s), function(n) eval_model(P_s[[n]], te) %>% mutate(model = n))) %>% mutate(set = "test_strict")),
          "dv_survival_metrics.csv", row.names = FALSE)

# calibration by decile of predicted S(3), test set
ok3 <- te$season + 3 <= LAST_FULL
cal <- bind_rows(lapply(c("GLM", "Cox", "RSF", "Blend"), function(n) {
  data.frame(p = P[[n]][ok3, 3], y = as.integer(!(te$status[ok3] == 1 & te$time[ok3] <= 3))) %>%
    mutate(bin = ntile(p, 10)) %>% group_by(bin) %>% summarise(pred = mean(p), actual = mean(y), n = n()) %>% mutate(model = n) }))
write.csv(cal, "dv_survival_calibration.csv", row.names = FALSE)
g <- ggplot(cal, aes(pred, actual, color = model)) + geom_abline(lty = 2, color = "grey50") + geom_point(size = 2) + geom_line() +
  scale_x_continuous(labels = scales::percent) + scale_y_continuous(labels = scales::percent) +
  labs(title = "Calibration on held-out seasons: predicted vs actual chance still alive after 3 seasons",
       x = "Predicted", y = "Actual") + theme_minimal(base_size = 11)
ggsave("plot_survival_calibration.png", g, width = 8, height = 5, dpi = 120)

# PH assumption check for Cox
cat("\nCox PH test (cox.zph), global and worst terms:\n")
z <- tryCatch(cox.zph(m_tr$cox), error = function(e) NULL)
if (!is.null(z)) print(head(z$table[order(z$table[, "p"]), ], 8))

# ---------- refit on every landmark 2007-2024 for scoring ----------
m_all <- fit_all(lm_fit, pp, imp = "permutation")
saveRDS(m_all, "dv_survival_models.rds")
cat("\nFinal hazard GLM (all landmarks): odds ratios for the main terms\n")
co <- summary(m_all$glm)$coefficients
or <- data.frame(term = rownames(co), coef = co[, 1], se = co[, 2], p = co[, 4]) %>%
  mutate(odds_ratio = exp(coef)) %>% mutate(across(where(is.numeric), ~ signif(.x, 3)))
print(or, row.names = FALSE); write.csv(or, "dv_hazard_glm_coefficients.csv", row.names = FALSE)
cat("\nRSF permutation importance (all landmarks):\n")
imp <- sort(m_all$rsf$variable.importance, decreasing = TRUE); print(round(imp, 4))
write.csv(data.frame(feature = names(imp), importance = imp), "dv_rsf_importance.csv", row.names = FALSE)
