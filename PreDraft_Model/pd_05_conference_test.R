# =============================================================================
# Pre-Draft Model -- Phase 5: does the level of competition help? (Kyle's question)
#
# Each player's primary college season is tagged with its conference and a tier:
#   P5 (SEC, Big Ten, Big 12, ACC, Pac-12, Notre Dame, Big East while a BCS league),
#   G5 (rest of FBS), FCS. (Division II players don't appear: cfbd only logs their
#   games against FBS teams, so they never pass the production filter.)
# Variants, each fit with the position's chosen model type and the same leakage-safe
# preprocessing, validated exactly like Phase 2 (strict rolling origin 2016-2023 + LOCO):
#   base     the current model (Power 5 flag only)
#   tier     + G5 and FCS indicators (P5 is the reference level)
#   tier_x   tier + production x level interactions, so a 1,000-yard season can be
#            worth less at G5 / FCS than in a Power 5 league (the "discount" idea)
#   conf     + one indicator per conference (30+ pool players; rarer ones pooled into
#            "other"), shrunk by the elastic net
#   cred     credibility / mixed-model version (ATPA 3.3): the 5-input logistic model
#            with a random intercept per conference (lme4::glmer), so each conference's
#            adjustment is a credibility-weighted blend of its own experience and the
#            overall mean. Compared against the same 5-input logistic without it (glm5).
# Outputs: pd_conference_test_metrics.csv, pd_conference_test_class.csv,
#          pd_conference_effects.csv (credibility estimates by conference)
# =============================================================================
source("pd_common.R")
suppressMessages({ library(glmnet); library(lme4); library(pROC) })
set.seed(2026)

pool <- readRDS("pd_pool.rds") %>% mutate(lvl_g5 = as.integer(level == "G5"), lvl_fcs = as.integer(level %in% c("FCS", "Lower")))
KTOP <- c(QB = 12, RB = 20, WR = 32, TE = 15)
PROD <- list(QB = c("best_aya", "p_comp_pct"), RB = c("p_rush_yds", "p_rec_yds"),
             WR = c("p_rec_yds", "p_dominator"), TE = c("p_ypta", "p_rec_yds"))
gain_tbl <- list(); cls_tbl <- list(); eff_tbl <- list()

for (POS in POSITIONS) {
  S <- readRDS(sprintf("pd_%s_models.rds", POS)); type <- S$chosen
  d <- pool %>% filter(position == POS)
  big_conf <- names(which(table(d$conf[d$outcome_known]) >= 30))
  d <- d %>% mutate(conf_g = ifelse(conf %in% big_conf, conf, "other"))
  for (v in PROD[[POS]]) {   # interactions on the imputed scale are built inside the prep below
    d[[paste0(v, "_x_g5")]] <- d[[v]] * d$lvl_g5; d[[paste0(v, "_x_fcs")]] <- d[[v]] * d$lvl_fcs }
  conf_dummies <- paste0("cf_", make.names(setdiff(sort(unique(d$conf_g)), "other")))
  for (k in seq_along(conf_dummies)) d[[conf_dummies[k]]] <- as.integer(make.names(d$conf_g) == sub("^cf_", "", conf_dummies[k]))
  train <- d %>% filter(outcome_known, class %in% TRAIN_CLASSES)
  VARS <- list(base = S$vars, tier = c(S$vars, "lvl_g5", "lvl_fcs"),
               tier_x = c(S$vars, "lvl_g5", "lvl_fcs", paste0(rep(PROD[[POS]], each = 2), c("_x_g5", "_x_fcs"))),
               conf = c(S$vars, conf_dummies))
  simple <- S$simple_vars
  cat("\n=====", POS, ": model type", type, "; conferences with 30+ players:", length(big_conf), "=====\n")
  print(as.data.frame(train %>% group_by(level) %>% summarize(n = n(), any_tier = sum(tier <= 3), rate = round(mean(tier <= 3), 3))), row.names = FALSE)

  fit_pred <- function(tr, te, variant) {
    out <- matrix(NA, nrow(te), 3)
    for (k in 1:3) {
      y <- as.integer(tr$tier <= k)
      if (variant %in% c("glm5", "cred")) {
        p <- fit_prep(tr, simple); Xtr <- scale(apply_prep(p, tr)[, simple]); ce <- attr(Xtr, "scaled:center"); sc <- attr(Xtr, "scaled:scale")
        Xte <- scale(apply_prep(p, te)[, simple], ce, sc)
        dtr <- data.frame(Xtr, y = y, conf = tr$conf_g); dte <- data.frame(Xte, conf = te$conf_g)
        f <- as.formula(paste("y ~", paste(simple, collapse = " + "), if (variant == "cred") "+ (1 | conf)"))
        out[, k] <- if (variant == "glm5") predict(suppressWarnings(glm(f, binomial, dtr)), dte, type = "response") else {
          m <- tryCatch(suppressWarnings(suppressMessages(glmer(f, dtr, family = binomial, nAGQ = 1,
                        control = glmerControl(optimizer = "bobyqa", calc.derivs = FALSE)))), error = function(e) NULL)
          if (is.null(m)) predict(suppressWarnings(glm(update(f, . ~ . - (1 | conf)), binomial, dtr)), dte, type = "response")
          else predict(m, dte, type = "response", allow.new.levels = TRUE) }
      } else {
        vars <- VARS[[variant]]; p <- fit_prep(tr, vars); Xtr <- apply_prep(p, tr); Xte <- apply_prep(p, te)
        if (type == "glm") {
          sv <- c(simple, setdiff(vars, S$vars))
          out[, k] <- predict(suppressWarnings(glm(y ~ ., binomial, data.frame(Xtr[, sv, drop = FALSE], y = y))),
                              data.frame(Xte[, sv, drop = FALSE]), type = "response")
        } else {
          f <- tryCatch(suppressWarnings(cv.glmnet(Xtr, y, family = "binomial", alpha = 0.5, foldid = as.integer(factor(tr$class)))), error = function(e) NULL)
          out[, k] <- if (is.null(f)) mean(y) else as.numeric(predict(f, Xte, s = "lambda.min", type = "response"))
        }
      }
    }
    out[, 2] <- pmax(out[, 2], out[, 1]); out[, 3] <- pmax(out[, 3], out[, 2]); out
  }
  variants <- c("base", "tier", "tier_x", "conf", "glm5", "cred")
  oof <- list()
  for (scheme in c("Rolling", "LOCO")) for (Y in if (scheme == "LOCO") TRAIN_CLASSES else ROLL_TESTS) {
    tr <- if (scheme == "LOCO") filter(train, class != Y) else filter(train, class <= Y - 3); te <- filter(train, class == Y)
    pr <- lapply(variants, function(v) fit_pred(tr, te, v))
    oof[[length(oof) + 1]] <- bind_rows(lapply(seq_along(variants), function(i)
      data.frame(scheme = scheme, variant = variants[i], class = Y, athlete_id = te$athlete_id, name = te$name, level = te$level,
                 tier = te$tier, p1 = pr[[i]][, 1], p2 = pr[[i]][, 2], p3 = pr[[i]][, 3])))
  }
  oof <- bind_rows(oof)
  base_rate <- function(tr_classes, k) NA
  m <- oof %>% group_by(scheme, variant) %>%
    summarize(AUC_top = aucf(as.integer(tier == 1), p1), AUC_mid = aucf(as.integer(tier <= 2), p2), AUC_any = aucf(as.integer(tier <= 3), p3),
              Brier_top = brier(p1, tier == 1), Brier_mid = brier(p2, tier <= 2), Brier_any = brier(p3, tier <= 3),
              Brier_any_nonP5 = brier(p3[level != "P5"], tier[level != "P5"] <= 3), .groups = "drop") %>%
    mutate(position = POS, mean_AUC = (AUC_top + AUC_mid + AUC_any) / 3, mean_Brier = (Brier_top + Brier_mid + Brier_any) / 3)
  print(as.data.frame(m %>% select(scheme, variant, mean_AUC, mean_Brier, Brier_any, Brier_any_nonP5) %>% mutate(across(where(is.double), ~ round(.x, 5)))), row.names = FALSE)
  r <- oof %>% filter(scheme == "Rolling"); n <- sum(r$variant == "base")
  for (v in c("tier", "tier_x", "conf")) {
    a <- r %>% filter(variant == v); b <- r %>% filter(variant == "base")
    ci <- boot_ci(function(i) mean(((a$p1 - (a$tier == 1))^2 + (a$p2 - (a$tier <= 2))^2 + (a$p3 - (a$tier <= 3))^2)[i]) / 3 -
                              mean(((b$p1 - (b$tier == 1))^2 + (b$p2 - (b$tier <= 2))^2 + (b$p3 - (b$tier <= 3))^2)[i]) / 3, n)
    cat(sprintf("rolling mean Brier, %s minus base: %+.5f  95%% CI [%+.5f, %+.5f]\n", v, ci[1], ci[2], ci[3]))
  }
  a <- r %>% filter(variant == "cred"); b <- r %>% filter(variant == "glm5")
  ci <- boot_ci(function(i) mean(((a$p3 - (a$tier <= 3))^2)[i]) - mean(((b$p3 - (b$tier <= 3))^2)[i]), n)
  cat(sprintf("rolling any-tier Brier, credibility (random conference) minus plain 5-input logistic: %+.5f  95%% CI [%+.5f, %+.5f]\n", ci[1], ci[2], ci[3]))
  gain_tbl[[POS]] <- m

  # class level (LOCO, top K, expected tier points vs actual)
  ct <- oof %>% filter(scheme == "LOCO") %>% group_by(variant, class) %>% arrange(desc(p3), .by_group = TRUE) %>%
    summarize(exp_pts = sum(head(p1 + p2 + p3, KTOP[POS])), act_pts = sum(tier == 1) + sum(tier <= 2) + sum(tier <= 3), .groups = "drop") %>%
    group_by(variant) %>% summarize(position = POS, class_corr = cor(exp_pts, act_pts), class_spearman = cor(exp_pts, act_pts, method = "spearman"), .groups = "drop")
  cat("class-level correlation (LOCO):\n"); print(as.data.frame(ct %>% mutate(across(where(is.double), ~ round(.x, 3)))), row.names = FALSE)
  cls_tbl[[POS]] <- ct

  # credibility estimates per conference (full training data, any-tier model)
  p <- fit_prep(train, simple); X <- scale(apply_prep(p, train)[, simple])
  mm <- tryCatch(glmer(as.formula(paste("y ~", paste(simple, collapse = " + "), "+ (1 | conf)")),
                       data.frame(X, y = as.integer(train$tier <= 3), conf = train$conf_g), family = binomial,
                       control = glmerControl(optimizer = "bobyqa")), error = function(e) NULL)
  if (!is.null(mm)) {
    re <- ranef(mm)$conf; cat("random-intercept SD:", round(sqrt(VarCorr(mm)$conf[1]), 3), "\n")
    eff_tbl[[POS]] <- data.frame(position = POS, conference = rownames(re), effect_logodds = round(re[, 1], 3),
                                 n = as.integer(table(train$conf_g)[rownames(re)])) %>% arrange(desc(effect_logodds))
    print(eff_tbl[[POS]], row.names = FALSE)
  }
}
write.csv(bind_rows(gain_tbl) %>% mutate(across(where(is.double), ~ round(.x, 5))), "pd_conference_test_metrics.csv", row.names = FALSE)
write.csv(bind_rows(cls_tbl), "pd_conference_test_class.csv", row.names = FALSE)
write.csv(bind_rows(eff_tbl), "pd_conference_effects.csv", row.names = FALSE)
