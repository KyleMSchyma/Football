# =============================================================================
# FABLE build part 9 (finding 4): year-2 / year-3 usage-model tier probabilities as the starting prior for young players
# Sourced by dv_10 when USAGE_PRIOR is TRUE. For a week-9 snapshot of season S:
#   year 2 (exp 1, class S-1): the year-2 breakout model's prediction for class S-1, made at the end of its rookie season
#   year 3 (exp 2, class S-2): the year-3 model's prediction for class S-2, made at the end of season S-1
#   rookies (exp 0): unchanged (no completed NFL season yet; mid-season usage is not in these models), draft-slot prior
# Only the strict rolling-origin predictions are used (models trained on classes <= Y - 2 in the position scripts), so the
# backtest never sees a model fit on its own or later classes. Classes without a rolling prediction keep the current prior.
# Tier probabilities -> PPG with a tier calibration in the spirit of the rookie-pick pricing (dv_13): mean PPG in NFL season k
# of drafted players by tier (tier = best finish in years 1-3), using only classes whose 3 seasons ended before S.
#   prior PPG = sum over tiers P(tier) x mu(pos, tier, k)
# WR's usage models give top-24 and top-36 only, so WR tiers 1 and 2 are priced together (mu of tiers 1-2 pooled).
# =============================================================================
U_DIRS <- c(QB = "../Football2_QB", RB = "../Football2_RB", WR = "../Football2", TE = "../Football2_TE")
U_FILES <- list(y2 = c(QB = "phase5_oof_predictions.csv", RB = "phase5_oof_predictions.csv", TE = "phase5_oof_predictions.csv", WR = "phase7_oof_predictions.csv"),
                y3 = c(QB = "phase6_oof_predictions.csv", RB = "phase6_oof_predictions.csv", TE = "phase6_oof_predictions.csv", WR = "phase8_oof_predictions.csv"))
U_TIERS <- list(QB = c(8, 16, 24), RB = c(8, 16, 24), WR = c(12, 24, 36), TE = c(6, 12, 18))
USAGE <- bind_rows(lapply(names(U_FILES), function(kk) bind_rows(lapply(POSITIONS, function(ps) {
  x <- read.csv(file.path(U_DIRS[[ps]], U_FILES[[kk]][[ps]])) %>% filter(scheme == "Rolling")
  if (ps == "WR") x %>% transmute(pos = ps, class = draft_season, pick, p_top = NA_real_, p_top2 = use_p2, p_any = use_p3)
  else { mid <- intersect(c("use_p16", "use_p12"), names(x)); x %>% transmute(pos = ps, class = draft_season, pick, p_top = use_p1, p_top2 = .data[[mid]], p_any = use_p2) }
})) %>% mutate(k = if (kk == "y2") 2L else 3L))) %>% distinct(pos, class, pick, k, .keep_all = TRUE)
# tier calibration: season-k PPG by tier (best finish years 1-3), drafted players
U_fin <- seasP %>% group_by(season, pos) %>% mutate(finish = rank(-pts, ties.method = "min")) %>% ungroup()
U_dr <- readRDS(file.path(SHARED, "players_raw.rds")) %>% transmute(player_id = gsis_id, class = draft_year, pick = draft_pick) %>% filter(!is.na(pick), class >= 2006)
U_hist <- U_dr %>% inner_join(U_fin %>% select(player_id, season, pos, g, pts, finish), by = "player_id") %>% mutate(k = season - class + 1) %>% filter(k >= 1, k <= 3) %>%
  group_by(player_id) %>% mutate(best = min(finish), pos = names(which.max(table(pos)))) %>% ungroup() %>%
  mutate(tier = mapply(function(p, b) as.integer(sum(b > U_TIERS[[p]]) + 1L), pos, best))
usage_cal <- function(S) U_hist %>% filter(class + 2 <= S - 1) %>% group_by(pos, tier, k) %>% summarise(mu = sum(pts) / sum(g), .groups = "drop")
usage_prior <- function(d, S) {
  cal <- usage_cal(S); out <- rep(NA_real_, nrow(d))
  u <- USAGE %>% filter(class + k - 1 == S)                      # predictions made at the end of season S - 1 for season S
  i <- match(paste(d$pos, S - d$exp, d$draft_pick, d$exp + 1), paste(u$pos, u$class, u$pick, u$k))
  for (r in which(!is.na(i) & d$exp %in% 1:2)) { x <- u[i[r], ]; mu <- cal %>% filter(pos == x$pos, k == x$k); m <- setNames(mu$mu, mu$tier)
    if (length(m) < 4 || anyNA(m[as.character(1:4)])) next
    P <- if (is.na(x$p_top)) { p12 <- min(x$p_top2, x$p_any); c(p12, 0, x$p_any - p12, 1 - x$p_any) } else
      { a <- x$p_top; b <- max(x$p_top2, a); cc <- max(x$p_any, b); c(a, b - a, cc - b, 1 - cc) }
    if (is.na(x$p_top)) m[1] <- (m[1] * sum(U_hist$pos == x$pos & U_hist$tier == 1) + m[2] * sum(U_hist$pos == x$pos & U_hist$tier == 2)) /
                                 sum(U_hist$pos == x$pos & U_hist$tier <= 2)
    out[r] <- sum(P * m[as.character(1:4)]) }
  out
}
