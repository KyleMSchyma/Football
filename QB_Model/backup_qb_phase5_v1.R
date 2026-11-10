# =============================================================================
# QB Model -- Phase 5: year-2 breakout model (rookie usage -> years 2-3)
#
# Question: once a QB's ROOKIE regular season is over, how likely is a QB1 (top
#   12) or QB2+ (top 24) season in NFL years 2-3, and how many fantasy points
#   will he score in years 2-3?
# Population: every drafted QB, classes 2010-2025 (rookies who never played are
#   kept: a redshirt year is information, e.g. Mahomes, Love).
#   Training: classes 2010-2023 (years 2-3 complete through 2025).
#   Scoring: 2025 class for 2026-27.
# Features, all known at the end of the rookie regular season: rookie games,
#   starts (15+ attempts), attempts per game, fantasy points, per game and per
#   start, QB finish, YPA, ANY/A, EPA per dropback, CPOE, sack / TD / INT rates,
#   rushing yards and TDs per game, rushing share of his points, late-season
#   (weeks 10+) starts and points per start; draft and college features.
#   NOT used: offseason moves (trades, signings, cuts) after the prediction point.
# Models: pick_only (log pick); rookie_pts (log pick + rookie fantasy points);
#   usage (elastic net on everything; P(QB1) forced <= P(QB2+)).
# Validation: rolling origin -- class Y is scored at the end of season Y; year-3
#   outcomes known then are for classes C with C + 2 <= Y, so train on C <= Y - 2.
#   Test classes 2016-2023. Leave-one-class-out also reported.
# Outputs: phase5_cv_metrics.csv, phase5_oof_predictions.csv, qb_year2_breakout_board.csv
# =============================================================================
source("qb_common.R"); source("qb_usage.R")
set.seed(2026)

tbl <- load_table()
base <- tbl %>% filter(draft_season <= 2025, !is.na(gsis_id))
u1 <- usage_year(base, 1)
d <- base %>% inner_join(u1, by = c("gsis_id", "draft_season")) %>%
  left_join(outcome_year(base, 2), by = c("gsis_id", "draft_season")) %>%
  left_join(outcome_year(base, 3), by = c("gsis_id", "draft_season")) %>%
  mutate(complete = coalesce(o3_complete, FALSE),
         best_23 = pmin(o2_finish, o3_finish), pts_23 = o2_pts + o3_pts,
         y_qb1 = as.integer(best_23 <= 12), y_qb2 = as.integer(best_23 <= 24))
train <- d %>% filter(complete, draft_season <= 2023)
cat("drafted QBs by class:\n"); print(table(d$draft_season))
cat("training rows (2010-2023):", nrow(train), " played as rookies:", sum(train$y1_played),
    " QB1 in yrs 2-3:", sum(train$y_qb1), " QB2+:", sum(train$y_qb2), "\n")

feats <- c(draft_feats, usage_feats(1))

predict_all <- function(tr, te) {
  o <- data.frame(row.names = seq_len(nrow(te)))
  o$pick_p2 <- predict(glm(y_qb2 ~ log_pick, binomial, tr), te, type = "response")
  o$pick_p1 <- pmin(predict(glm(y_qb1 ~ log_pick, binomial, tr), te, type = "response"), o$pick_p2)
  o$pick_pts <- pmax(0, predict(lm(pts_23 ~ log_pick, tr), te))
  o$rpts_p2 <- predict(glm(y_qb2 ~ log_pick + y1_pts, binomial, tr), te, type = "response")
  o$rpts_p1 <- pmin(predict(glm(y_qb1 ~ log_pick + y1_pts, binomial, tr), te, type = "response"), o$rpts_p2)
  o$rpts_pts <- pmax(0, predict(lm(pts_23 ~ log_pick + y1_pts, tr), te))
  p <- prep_fit_u(tr, feats); Xtr <- prep_apply_u(p, tr); Xte <- prep_apply_u(p, te)
  o$use_p2 <- enet_pred(enet_fit(Xtr, tr$y_qb2, "binomial", tr$draft_season), Xte, tr$y_qb2)
  o$use_p1 <- pmin(enet_pred(enet_fit(Xtr, tr$y_qb1, "binomial", tr$draft_season), Xte, tr$y_qb1), o$use_p2)
  o$use_pts <- pmax(0, enet_pred(enet_fit(Xtr, tr$pts_23, "gaussian", tr$draft_season), Xte, tr$pts_23))
  o
}
run_cv <- function(scheme) {
  res <- list(); tests <- if (scheme == "LOCO") 2010:2023 else 2016:2023
  for (Y in tests) {
    tr <- if (scheme == "LOCO") filter(train, draft_season != Y) else filter(train, draft_season <= Y - 2)
    te <- filter(train, draft_season == Y)
    if (scheme == "Rolling") stopifnot(max(tr$draft_season) + 2 <= Y)
    res[[length(res) + 1]] <- cbind(te %>% select(draft_season, round, pick, pfr_player_name, y1_games, y1_starts,
                                                  y1_pts, y1_finish, best_23, y_qb1, y_qb2, pts_23),
                                    scheme = scheme, ntrain = nrow(tr), predict_all(tr, te))
  }
  bind_rows(res)
}
oof <- bind_rows(run_cv("Rolling"), run_cv("LOCO"))
write.csv(oof, "phase5_oof_predictions.csv", row.names = FALSE)

metric_rows <- function(o) bind_rows(lapply(c("pick", "rpts", "use"), function(m) {
  p2 <- o[[paste0(m, "_p2")]]; p1 <- o[[paste0(m, "_p1")]]; pp <- o[[paste0(m, "_pts")]]
  data.frame(model = c(pick = "pick_only", rpts = "pick+rookie_pts", use = "usage_enet")[m], n = nrow(o),
             AUC_QB2 = aucf(o$y_qb2, p2), Brier_QB2 = brier(p2, o$y_qb2),
             AUC_QB1 = aucf(o$y_qb1, p1), Brier_QB1 = brier(p1, o$y_qb1),
             Spearman_pts = cor(pp, o$pts_23, method = "spearman"), RMSE_pts = rmse(pp, o$pts_23))
}))
metrics <- bind_rows(lapply(c("Rolling", "LOCO"), function(s) cbind(scheme = s, metric_rows(filter(oof, scheme == s))))) %>%
  mutate(across(where(is.double), ~ round(.x, 4)))
cat("\n===== Year-2 breakout: cross-validated performance =====\n"); print(metrics, row.names = FALSE)
write.csv(metrics, "phase5_cv_metrics.csv", row.names = FALSE)

r <- filter(oof, scheme == "Rolling"); n <- nrow(r)
cat("\n===== Bootstrap, rolling origin (negative = usage better) =====\n")
cat("Brier QB2+ usage - pick_only: ", boot_diff(function(i) brier(r$use_p2[i], r$y_qb2[i]) - brier(r$pick_p2[i], r$y_qb2[i]), n), "\n")
cat("Brier QB2+ usage - rookie_pts:", boot_diff(function(i) brier(r$use_p2[i], r$y_qb2[i]) - brier(r$rpts_p2[i], r$y_qb2[i]), n), "\n")
cat("Brier QB1  usage - pick_only: ", boot_diff(function(i) brier(r$use_p1[i], r$y_qb1[i]) - brier(r$pick_p1[i], r$y_qb1[i]), n), "\n")
cat("Brier QB1  usage - rookie_pts:", boot_diff(function(i) brier(r$use_p1[i], r$y_qb1[i]) - brier(r$rpts_p1[i], r$y_qb1[i]), n), "\n")
cat("RMSE pts   usage - pick_only: ", boot_diff(function(i) rmse(r$use_pts[i], r$pts_23[i]) - rmse(r$pick_pts[i], r$pts_23[i]), n), "\n")
cat("RMSE pts   usage - rookie_pts:", boot_diff(function(i) rmse(r$use_pts[i], r$pts_23[i]) - rmse(r$rpts_pts[i], r$pts_23[i]), n), "\n")
cat("Brier QB2+ rookie_pts - pick: ", boot_diff(function(i) brier(r$rpts_p2[i], r$y_qb2[i]) - brier(r$pick_p2[i], r$y_qb2[i]), n), "\n")

# --- Hidden talent: QBs outside the top 24 as rookies --------------------------------
sub <- filter(r, y1_finish > 24)
cat("\n===== Outside top-24 as rookies, rolling 2016-2023:", nrow(sub), "QBs,", sum(sub$y_qb2), "reached QB2+ in yrs 2-3 =====\n")
for (k in c(2, 3)) {
  hits <- function(col) sub %>% group_by(draft_season) %>% arrange(desc(.data[[col]]), pick, .by_group = TRUE) %>% slice_head(n = k) %>% ungroup()
  a <- hits("use_p2"); b <- hits("rpts_p2"); cc <- hits("pick_p2")
  cat(sprintf("top %d per class -> usage %d | rookie pts %d | pick only %d | random %.1f\n", k, sum(a$y_qb2), sum(b$y_qb2), sum(cc$y_qb2),
              sum(tapply(sub$y_qb2, sub$draft_season, function(z) min(k, length(z)) * mean(z)))))
  cat("  usage hits:", paste0(a$pfr_player_name[a$y_qb2 == 1], " (", a$draft_season[a$y_qb2 == 1], ")", collapse = ", "), "\n")
}
cat("  all QB2+ in this group:", paste0(sub$pfr_player_name[sub$y_qb2 == 1], " (", sub$draft_season[sub$y_qb2 == 1], ")", collapse = ", "), "\n")
known <- c("Josh Allen", "Lamar Jackson", "Jalen Hurts", "Patrick Mahomes", "Brock Purdy", "Jared Goff", "Dak Prescott",
           "Joe Burrow", "Justin Herbert", "Trevor Lawrence", "Kyler Murray", "Baker Mayfield", "Sam Darnold")
kr <- r %>% group_by(draft_season) %>% mutate(n_class = n(), rk_usage = rank(-use_p2, ties.method = "min"),
                                              rk_rpts = rank(-rpts_p2, ties.method = "min"), rk_pick = rank(pick)) %>%
  ungroup() %>% filter(pfr_player_name %in% known) %>%
  select(draft_season, pick, pfr_player_name, y1_starts, y1_finish, best_23, use_p2, rpts_p2, n_class, rk_usage, rk_rpts, rk_pick) %>%
  mutate(across(c(use_p2, rpts_p2), ~ round(.x, 3)))
cat("\n===== Known names (rolling origin): P(QB2+ in yrs 2-3) and rank in class =====\n"); print(as.data.frame(kr), row.names = FALSE)

# --- Year-2-only check: 2024 class (trained on <= 2022) ------------------------------
c24 <- d %>% filter(draft_season == 2024); p24 <- predict_all(filter(train, draft_season <= 2022), c24)
y2q2 <- as.integer(c24$o2_finish <= 24)
cat("\n===== Year-2-only check, 2024 class (n =", nrow(c24), "): actual QB2+ in 2025 =", sum(y2q2), "=====\n")
for (m in c("pick", "rpts", "use")) cat(sprintf("%-5s AUC %.3f  Brier %.4f\n", m, aucf(y2q2, p24[[paste0(m, "_p2")]]), brier(p24[[paste0(m, "_p2")]], y2q2)))

# --- Final fit (2010-2023) -> 2025 class board -----------------------------------------
sc <- d %>% filter(draft_season == 2025); pf <- predict_all(train, sc)
board <- bind_cols(sc %>% select(pfr_player_name, draft_season, round, pick, draft_team, college,
                                 y1_games, y1_starts, y1_att_pg, y1_pts, y1_ppg, y1_pts_per_start, y1_finish, y1_anya,
                                 y1_epa_db, y1_cpoe, y1_sack_rate, y1_rush_ypg, y1_starts_late, y1_ppg_late_starts), pf) %>%
  mutate(across(where(is.double), ~ round(.x, 3)), usage_edge_qb2 = round(use_p2 - rpts_p2, 3),
         buy_low = y1_finish > 24 & use_p2 >= 0.15 & usage_edge_qb2 > 0) %>%
  rename(p_qb2_pick_only = pick_p2, p_qb1_pick_only = pick_p1, pts23_pick_only = pick_pts,
         p_qb2_rookie_pts = rpts_p2, p_qb1_rookie_pts = rpts_p1, pts23_rookie_pts = rpts_pts,
         p_qb2_usage = use_p2, p_qb1_usage = use_p1, pts23_usage = use_pts) %>% arrange(desc(p_qb2_usage))
write.csv(board, "qb_year2_breakout_board.csv", row.names = FALSE)
cat("\n===== 2025 class: P(QB2+ / QB1 in 2026-27), usage model =====\n")
print(as.data.frame(board %>% select(pfr_player_name, pick, y1_starts, y1_ppg, y1_pts_per_start, y1_finish, y1_anya, y1_epa_db,
                                     y1_rush_ypg, y1_starts_late, p_qb2_usage, p_qb1_usage, pts23_usage, p_qb2_rookie_pts, usage_edge_qb2)), row.names = FALSE)

p <- prep_fit_u(train, feats); X <- prep_apply_u(p, train)
co <- coef(enet_fit(X, train$y_qb2, "binomial", train$draft_season), s = "lambda.min"); nz <- co[which(co[, 1] != 0), 1]
cat("\nusage model (QB2+) nonzero coefficients:\n"); print(round(nz[order(-abs(nz))], 4))
