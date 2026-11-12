# =============================================================================
# TE Model -- Phase 6: year-3 model (end of year 2 -> year 3)
#
# Prediction point: end of the TE's NFL year-2 regular season.
# Population: drafted TEs, classes 2010-2024 (all, including those who sat).
#   Training: classes 2010-2023 (year 3 complete through 2025).
#   Scoring: 2024 class for year 3 = 2026. No 2026 data is used.
# Features: Phase 5 usage for year 1 and year 2 separately, year-1 -> year-2
#   changes (targets per game, points per game, snap share, target share), draft/college
#   features. Nothing from the offseason after year 2.
# Targets: year-3 TE finish as top 6, top 12 and top 18 (Kyle's TE tiers), nested logistic
#   elastic nets with P(top 6) <= P(top 12) <= P(top 18); year-3 fantasy points (Gaussian).
# Baselines: pick_only; pick + year-2 points; pick + year-1 and year-2 points.
# Rolling rule: class Y is scored at the end of season Y + 1. Year-3 outcomes
#   known then are for classes c with c + 2 <= Y + 1, i.e. c <= Y - 1. Test
#   classes 2016-2023; leave-one-class-out also reported.
# Outputs: phase6_cv_metrics.csv, phase6_oof_predictions.csv, te_year3_board.csv
# =============================================================================
source("te_common.R"); source("te_usage.R")
set.seed(2026)

tbl <- load_table()
base <- tbl %>% filter(draft_season <= 2024, !is.na(gsis_id))
d <- base %>% inner_join(usage_year(base, 1), by = c("gsis_id", "draft_season")) %>%
  inner_join(usage_year(base, 2), by = c("gsis_id", "draft_season")) %>%
  left_join(outcome_year(base, 3), by = c("gsis_id", "draft_season")) %>%
  filter(y2_season_complete) %>%
  mutate(d_tgt = y2_tgt_pg - y1_tgt_pg, d_ppg = y2_ppg - y1_ppg,
         d_snap = y2_snap_avg - y1_snap_avg, d_tshare = y2_tgt_share - y1_tgt_share,
         y_t6 = as.integer(o3_finish <= TE_CUT[1]), y_t12 = as.integer(o3_finish <= TE_CUT[2]), y_t18 = as.integer(o3_finish <= TE_CUT[3]))
train <- d %>% filter(o3_complete, draft_season <= 2023)
cat("training rows (2010-2023):", nrow(train), " year-3 top-6:", sum(train$y_t6), " top-12:", sum(train$y_t12), " top-18:", sum(train$y_t18), "\n")

feats <- c(draft_feats, usage_feats(1), usage_feats(2), "d_tgt", "d_ppg", "d_snap", "d_tshare")

predict_all <- function(tr, te) {
  o <- data.frame(row.names = seq_len(nrow(te)))
  for (spec in list(c("pick", "log_pick"), c("y2pts", "log_pick + y2_pts"), c("y12pts", "log_pick + y1_pts + y2_pts"))) {
    f2 <- as.formula(paste("y_t18 ~", spec[2])); f16 <- as.formula(paste("y_t12 ~", spec[2])); f1 <- as.formula(paste("y_t6 ~", spec[2])); fp <- as.formula(paste("o3_pts ~", spec[2]))
    o[[paste0(spec[1], "_p2")]] <- predict(glm(f2, binomial, tr), te, type = "response")
    o[[paste0(spec[1], "_p12")]] <- pmin(predict(glm(f16, binomial, tr), te, type = "response"), o[[paste0(spec[1], "_p2")]])
    o[[paste0(spec[1], "_p1")]] <- pmin(predict(glm(f1, binomial, tr), te, type = "response"), o[[paste0(spec[1], "_p12")]])
    o[[paste0(spec[1], "_pts")]] <- pmax(0, predict(lm(fp, tr), te))
  }
  p <- prep_fit_u(tr, feats); Xtr <- prep_apply_u(p, tr); Xte <- prep_apply_u(p, te)
  o$use_p2 <- enet_pred(enet_fit(Xtr, tr$y_t18, "binomial", tr$draft_season), Xte, tr$y_t18)
  o$use_p12 <- pmin(enet_pred(enet_fit(Xtr, tr$y_t12, "binomial", tr$draft_season), Xte, tr$y_t12), o$use_p2)
  o$use_p1 <- pmin(enet_pred(enet_fit(Xtr, tr$y_t6, "binomial", tr$draft_season), Xte, tr$y_t6), o$use_p12)
  o$use_pts <- pmax(0, enet_pred(enet_fit(Xtr, tr$o3_pts, "gaussian", tr$draft_season), Xte, tr$o3_pts))
  o
}
run_cv <- function(scheme) {
  res <- list(); tests <- if (scheme == "LOCO") 2010:2023 else 2016:2023
  for (Y in tests) {
    tr <- if (scheme == "LOCO") filter(train, draft_season != Y) else filter(train, draft_season <= Y - 1)
    te <- filter(train, draft_season == Y)
    if (scheme == "Rolling") stopifnot(max(tr$draft_season) + 2 <= Y + 1)
    res[[length(res) + 1]] <- cbind(te %>% select(draft_season, round, pick, pfr_player_name, y1_tgt_pg, y1_finish, y2_tgt_pg,
                                                  y2_finish, y2_pts, o3_finish, o3_pts, y_t6, y_t12, y_t18),
                                    scheme = scheme, ntrain = nrow(tr), predict_all(tr, te))
  }
  bind_rows(res)
}
oof <- bind_rows(run_cv("Rolling"), run_cv("LOCO"))
write.csv(oof, "phase6_oof_predictions.csv", row.names = FALSE)

labs <- c(pick = "pick_only", y2pts = "pick+y2_pts", y12pts = "pick+y1+y2_pts", use = "usage_enet")
metric_rows <- function(o) bind_rows(lapply(names(labs), function(m) {
  p2 <- o[[paste0(m, "_p2")]]; p12 <- o[[paste0(m, "_p12")]]; p1 <- o[[paste0(m, "_p1")]]; pp <- o[[paste0(m, "_pts")]]
  data.frame(model = labs[m], n = nrow(o), AUC_top18 = aucf(o$y_t18, p2), Brier_top18 = brier(p2, o$y_t18),
             AUC_top12 = aucf(o$y_t12, p12), Brier_top12 = brier(p12, o$y_t12),
             AUC_top6 = aucf(o$y_t6, p1), Brier_top6 = brier(p1, o$y_t6),
             Spearman_pts = cor(pp, o$o3_pts, method = "spearman"), RMSE_pts = rmse(pp, o$o3_pts))
}))
metrics <- bind_rows(lapply(c("Rolling", "LOCO"), function(s) cbind(scheme = s, metric_rows(filter(oof, scheme == s))))) %>%
  mutate(across(where(is.double), ~ round(.x, 4)))
cat("\n===== Year-3 model: cross-validated performance =====\n"); print(metrics, row.names = FALSE)
write.csv(metrics, "phase6_cv_metrics.csv", row.names = FALSE)

r <- filter(oof, scheme == "Rolling"); n <- nrow(r)
cat("\n===== Bootstrap, rolling origin (negative = usage better) =====\n")
for (b in c("pick", "y2pts", "y12pts")) {
  cat(sprintf("Brier top18 usage - %-7s %s\n", b, boot_diff(function(i) brier(r$use_p2[i], r$y_t18[i]) - brier(r[[paste0(b, "_p2")]][i], r$y_t18[i]), n)))
  cat(sprintf("Brier top6  usage - %-7s %s\n", b, boot_diff(function(i) brier(r$use_p1[i], r$y_t6[i]) - brier(r[[paste0(b, "_p1")]][i], r$y_t6[i]), n)))
  cat(sprintf("RMSE pts   usage - %-7s %s\n", b, boot_diff(function(i) rmse(r$use_pts[i], r$o3_pts[i]) - rmse(r[[paste0(b, "_pts")]][i], r$o3_pts[i]), n)))
}

sub <- filter(r, y2_finish > TE_CUT[3])
cat("\n===== Outside top-18 in year 2, rolling 2016-2023:", nrow(sub), "TEs,", sum(sub$y_t18), "jumped to the top 18 in year 3 =====\n")
for (k in c(2, 3)) {
  hits <- function(col) sub %>% group_by(draft_season) %>% arrange(desc(.data[[col]]), pick, .by_group = TRUE) %>% slice_head(n = k) %>% ungroup()
  a <- hits("use_p2"); b <- hits("y2pts_p2")
  cat(sprintf("top %d per class -> usage %d | year-2 pts %d | random %.1f\n", k, sum(a$y_t18), sum(b$y_t18),
              sum(tapply(sub$y_t18, sub$draft_season, function(z) min(k, length(z)) * mean(z)))))
  cat("  usage hits:", paste0(a$pfr_player_name[a$y_t18 == 1], " (", a$draft_season[a$y_t18 == 1], ")", collapse = ", "), "\n")
}
cat("  all year-3 jumps in this group:", paste0(sub$pfr_player_name[sub$y_t18 == 1], " (", sub$draft_season[sub$y_t18 == 1], ")", collapse = ", "), "\n")

# --- Board: 2024 class for 2026 ---------------------------------------------------------
sc <- d %>% filter(draft_season == 2024); pf <- predict_all(train, sc)
board <- bind_cols(sc %>% select(pfr_player_name, draft_season, round, pick, draft_team, college,
                                 y1_tgt_pg, y1_ppg, y1_finish, y2_games, y2_tgt_pg, y2_rec_pg, y2_tgt_share, y2_wopr, y2_ppg, y2_finish,
                                 y2_ypt, y2_epa_tgt, y2_adot, y2_td_share_pts, y2_snap_avg, y2_snap_last6, y2_ppg_late, d_tgt, d_ppg, d_snap, d_tshare), pf) %>%
  mutate(across(where(is.double), ~ round(.x, 3)), usage_edge_top18 = round(use_p2 - y2pts_p2, 3)) %>%
  rename(p_top18_pick_only = pick_p2, p_top6_pick_only = pick_p1, p_top18_y2pts = y2pts_p2, p_top12_y2pts = y2pts_p12, p_top6_y2pts = y2pts_p1,
         p_top18_usage = use_p2, p_top12_usage = use_p12, p_top6_usage = use_p1, pts_y3_usage = use_pts, pts_y3_y2pts = y2pts_pts) %>%
  arrange(desc(p_top18_usage))
write.csv(board, "te_year3_board.csv", row.names = FALSE)
cat("\n===== 2024 class: year-3 (2026) outlook =====\n")
print(as.data.frame(board %>% select(pfr_player_name, pick, y1_finish, y2_games, y2_tgt_pg, y2_ppg, y2_finish, y2_snap_avg, y2_snap_last6,
                                     d_tgt, d_snap, p_top18_usage, p_top12_usage, p_top6_usage, pts_y3_usage, p_top18_y2pts, p_top12_y2pts, usage_edge_top18)), row.names = FALSE)
p <- prep_fit_u(train, feats); X <- prep_apply_u(p, train)
co <- coef(enet_fit(X, train$y_t18, "binomial", train$draft_season), s = "lambda.min"); nz <- co[which(co[, 1] != 0), 1]
cat("\nusage model (top 18) nonzero coefficients:\n"); print(round(nz[order(-abs(nz))], 4))
