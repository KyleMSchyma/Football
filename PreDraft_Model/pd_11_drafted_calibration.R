# =============================================================================
# Pre-Draft Model -- Phase 11: probabilities conditional on being drafted
#
# Why: the pre-draft model is trained on every draft-eligible college player, so its tier
#   probabilities (p_top, p_top2, p_any) include the chance a player is never drafted. Among
#   players who WERE drafted they run about 30-40% low. Rookie-pick pricing and the
#   cross-position Value column only apply to drafted (or mocked) players, so they need
#   P(tier | profile, drafted).
# How: per position and cumulative tier k (top, top two, any), a logistic recalibration
#     P(hit_k | drafted) = plogis(a + b * logit(p_k))
#   fit on drafted 2010-2023 players using their out-of-class (LOCO) pre-draft predictions.
#   Two parameters per fit, so it moves the level and the spread but keeps the ranking.
#   After recalibration the three are forced to stay nested (top <= top two <= any).
# Validation: leave-one-class-out and strict rolling origin (test class Y in 2016-2023, fit
#   on classes <= Y - 3), Brier and calibration by quintile, before vs after.
# The original unconditional probabilities and the grades are NOT changed.
# Inputs:  pd_player_grades.csv (pd_06)
# Outputs: pd_player_probs_drafted.csv (every board row: p_top_d, p_top2_d, p_any_d),
#          pd_drafted_calibration.csv (coefficients), pd_drafted_calibration_check.csv,
#          pd_drafted_calibration_bins.csv; log phase11_log.txt
# =============================================================================
source("pd_common.R")
g <- read.csv("pd_player_grades.csv", stringsAsFactors = FALSE, na.strings = "")
H <- g %>% filter(status == "drafted", class %in% TRAIN_CLASSES, !is.na(nfl_tier))
PC <- c("p_top", "p_top2", "p_any")
clampq <- function(p) qlogis(pmin(pmax(p, 1e-4), 1 - 1e-4))
fit1 <- function(d, k) suppressWarnings(glm(as.integer(d$nfl_tier <= k) ~ clampq(d[[PC[k]]]), family = binomial))
pred1 <- function(f, p) plogis(coef(f)[1] + coef(f)[2] * clampq(p))
nest <- function(m) { m[, 2] <- pmax(m[, 2], m[, 1]); m[, 3] <- pmax(m[, 3], m[, 2]); m }
recal <- function(tr, te) nest(sapply(1:3, function(k) pred1(fit1(tr, k), te[[PC[k]]])))

# --- validation -----------------------------------------------------------------------
oof <- list()
for (POS in POSITIONS) {
  d <- H %>% filter(position == POS)
  for (Y in TRAIN_CLASSES) {
    te <- d %>% filter(class == Y); if (!nrow(te)) next
    loco <- recal(d %>% filter(class != Y), te)
    roll <- if (Y %in% ROLL_TESTS) recal(d %>% filter(class <= Y - 3), te) else matrix(NA_real_, nrow(te), 3)
    oof[[length(oof) + 1]] <- data.frame(position = POS, class = Y, name = te$name, tier = te$nfl_tier,
      raw1 = te$p_top, raw2 = te$p_top2, raw3 = te$p_any, loco1 = loco[, 1], loco2 = loco[, 2], loco3 = loco[, 3],
      roll1 = roll[, 1], roll2 = roll[, 2], roll3 = roll[, 3])
  }
}
oof <- bind_rows(oof)
chk <- bind_rows(lapply(c(POSITIONS, "All"), function(POS) {
  d <- if (POS == "All") oof else filter(oof, position == POS)
  bind_rows(lapply(1:3, function(k) {
    y <- as.integer(d$tier <= k); r <- !is.na(d[[paste0("roll", k)]])
    data.frame(position = POS, target = if (POS == "All") c("top", "top two", "any")[k] else tier_labels(POS)[k],
      n = nrow(d), hits = sum(y), actual = mean(y),
      mean_raw = mean(d[[paste0("raw", k)]]), mean_loco = mean(d[[paste0("loco", k)]]),
      brier_raw = brier(d[[paste0("raw", k)]], y), brier_loco = brier(d[[paste0("loco", k)]], y),
      n_roll = sum(r), actual_roll = mean(y[r]), mean_raw_roll = mean(d[[paste0("raw", k)]][r]),
      mean_roll = mean(d[[paste0("roll", k)]][r]),
      brier_raw_roll = brier(d[[paste0("raw", k)]][r], y[r]), brier_roll = brier(d[[paste0("roll", k)]][r], y[r]),
      auc_raw = aucf(y, d[[paste0("raw", k)]]), auc_loco = aucf(y, d[[paste0("loco", k)]]))
  }))
})) %>% mutate(across(where(is.double), ~ round(.x, 4)))
options(width = 220)
cat("===== Drafted 2010-2023: raw pre-draft probabilities vs drafted-recalibrated (LOCO and rolling 2016-2023) =====\n")
print(chk, row.names = FALSE)
write.csv(chk, "pd_drafted_calibration_check.csv", row.names = FALSE)

cat("\n===== Brier change, recalibrated minus raw (bootstrap 95% CI; negative = recalibration better) =====\n")
for (POS in POSITIONS) for (k in 1:3) {
  d <- filter(oof, position == POS); y <- as.integer(d$tier <= k)
  ci <- boot_ci(function(i) brier(d[[paste0("loco", k)]][i], y[i]) - brier(d[[paste0("raw", k)]][i], y[i]), nrow(d))
  dr <- d %>% filter(!is.na(roll1)); yr <- as.integer(dr$tier <= k)
  cr <- boot_ci(function(i) brier(dr[[paste0("roll", k)]][i], yr[i]) - brier(dr[[paste0("raw", k)]][i], yr[i]), nrow(dr))
  cat(sprintf("%-5s LOCO %+.4f [%+.4f, %+.4f] | rolling %+.4f [%+.4f, %+.4f]\n", tier_labels(POS)[k], ci[1], ci[2], ci[3], cr[1], cr[2], cr[3]))
}

bins <- bind_rows(lapply(POSITIONS, function(POS) {
  d <- filter(oof, position == POS)
  bind_rows(lapply(c("raw3", "loco3"), function(col) d %>% mutate(q = ntile(.data[[col]], 5)) %>% group_by(q) %>%
    summarize(n = n(), mean_pred = mean(.data[[col]]), actual = mean(tier <= 3), .groups = "drop") %>%
    mutate(position = POS, version = ifelse(col == "raw3", "raw", "recalibrated (LOCO)"), .before = 1)))
})) %>% mutate(across(c(mean_pred, actual), ~ round(.x, 3)))
cat("\n===== Calibration by quintile, P(any tier), drafted 2010-2023 =====\n")
print(as.data.frame(bins %>% tidyr::pivot_wider(names_from = version, values_from = c(n, mean_pred, actual)) %>%
  select(position, q, n = `n_raw`, `mean_pred_raw`, `actual_raw`, `mean_pred_recalibrated (LOCO)`, `actual_recalibrated (LOCO)`)), row.names = FALSE)
write.csv(bins, "pd_drafted_calibration_bins.csv", row.names = FALSE)

# --- final fit (all drafted 2010-2023) applied to every board row ------------------------------
coefs <- bind_rows(lapply(POSITIONS, function(POS) { d <- filter(H, position == POS)
  bind_rows(lapply(1:3, function(k) { f <- fit1(d, k)
    data.frame(position = POS, target = tier_labels(POS)[k], n = nrow(d), hits = sum(d$nfl_tier <= k),
               a = unname(coef(f)[1]), b = unname(coef(f)[2])) })) })) %>% mutate(across(c(a, b), ~ round(.x, 4)))
cat("\n===== Final recalibration (logit scale): P(hit | drafted) = plogis(a + b * logit(p)) =====\n"); print(coefs, row.names = FALSE)
write.csv(coefs, "pd_drafted_calibration.csv", row.names = FALSE)

out <- bind_rows(lapply(POSITIONS, function(POS) {
  d <- filter(g, position == POS); m <- recal(filter(H, position == POS), d)
  d %>% transmute(position, class, status, name, college, round, pick, grade, p_top, p_top2, p_any,
                  p_top_d = round(m[, 1], 4), p_top2_d = round(m[, 2], 4), p_any_d = round(m[, 3], 4))
}))
write.csv(out, "pd_player_probs_drafted.csv", row.names = FALSE)
cat("\n2027 projected prospects, raw vs drafted-recalibrated P(any tier), top 5 per position:\n")
print(as.data.frame(out %>% filter(class == 2027) %>% group_by(position) %>% arrange(desc(p_any_d), .by_group = TRUE) %>%
  slice_head(n = 5) %>% select(position, name, college, grade, p_top, p_top_d, p_any, p_any_d)), row.names = FALSE)
check("one recalibrated row per board row", nrow(out) == nrow(g))
check("recalibrated probabilities nested", all(out$p_top_d <= out$p_top2_d + 1e-9 & out$p_top2_d <= out$p_any_d + 1e-9))
check("ranking within position kept for P(any tier)", all(sapply(POSITIONS, function(POS) {
  d <- filter(out, position == POS); cor(d$p_any, d$p_any_d, method = "spearman") > 0.999 })))
