# =============================================================================
# Track record of the point-in-time values: every snapshot scored against what actually happened afterwards.
#   Rscript hv_02_track_record.R [SNAP_DIR] [OUT_DIR]       (run from the dynasty model folder, like hv_01)
#
# Redraft value  = credible PPG over replacement x expected games left this season.
#   Actual       = points scored in the rest of that season minus replacement PPG x games played
#                  (the same target as dv_10's backtest; replacement = that snapshot's own replacement line).
# Dynasty value  = rest of season + the next 5 seasons, discounted at 15% a year, upside priced with the stop-loss formula.
#   Actual       = sum over the same window of max(PPG - replacement, 0) x games, discounted the same way (dv_11's target).
#   Complete only when all 5 later seasons are over (snapshots through 2020); later snapshots are scored "so far" and
#   flagged, never mixed into the complete numbers.
# Baseline ("naive"): this season's raw PPG instead of the model's credible PPG, no injury model, no aging, no survival.
# Scores: Spearman rank correlation, hit rate of the top 24 overall (and top 12 per position), and predicted / actual totals.
# =============================================================================
suppressMessages(library(dplyr))
a <- commandArgs(trailingOnly = TRUE)
SNAP <- if (length(a) >= 1) a[1] else "history_out"; OUT <- if (length(a) >= 2) a[2] else "history_scored"
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
v <- 1 / 1.15; NFUT <- 5; POS <- c("QB", "RB", "WR", "TE")
w <- readRDS("../Football2/cache/nfl_weekly_raw.rds")
w26 <- readRDS("nfl_weekly_2026.rds"); w <- bind_rows(w, w26[, intersect(names(w26), names(w))]) %>% filter(season_type == "REG")
w <- w %>% transmute(player_id, season, week, pts = coalesce(fantasy_points_ppr, 0))
LAST <- max(w$season); LAST_WK <- max(w$week[w$season == LAST])
seas <- w %>% group_by(player_id, season) %>% summarise(g = n_distinct(week), pts = sum(pts), .groups = "drop")

files <- sort(list.files(SNAP, pattern = "^hv_\\d{4}_w\\d{2}\\.rds$", full.names = TRUE))
cat("snapshots:", length(files), "\n")
top_hit <- function(pred, act, k) { if (length(pred) < k) return(NA_real_); mean(order(-pred)[1:k] %in% order(-act)[1:k]) }
score <- function(d, kind) bind_rows(lapply(c("ALL", POS), function(ps) {
  x <- if (ps == "ALL") d else d[d$pos == ps, ]
  if (nrow(x) < 10) return(NULL)
  tibble(pos = ps, n = nrow(x), spearman = cor(x$value, x$actual, method = "spearman"),
         spearman_naive = cor(x$naive, x$actual, method = "spearman"),
         top_hit = top_hit(x$value, x$actual, if (ps == "ALL") 24 else 12),
         top_hit_naive = top_hit(x$naive, x$actual, if (ps == "ALL") 24 else 12),
         pred_total = sum(x$value), actual_total = sum(x$actual), kind = kind) }))

RES <- list(); PL <- list()
for (f in files) {
  s <- readRDS(f); S <- s$meta$season; W <- s$meta$week; rep <- setNames(s$meta$rep_ppg$rep_ppg, s$meta$rep_ppg$pos)
  ros <- w %>% filter(season == S, week > W) %>% group_by(player_id) %>% summarise(n_ros = n(), pts_ros = sum(pts), .groups = "drop")
  # ---- redraft (only seasons that are over) ----
  if (nrow(s$redraft) && S < LAST && nrow(ros) > 0) {          # (2022 week 18: a cancelled game left one "game left" that was never played)
    d <- s$redraft %>% left_join(ros, by = "player_id") %>% mutate(n_ros = coalesce(n_ros, 0L), pts_ros = coalesce(pts_ros, 0),
           actual = pts_ros - rep_ppg * n_ros, naive = (ppg - rep_ppg) * team_games_left)
    RES[[length(RES) + 1]] <- score(d %>% filter(games >= 3), "redraft") %>% mutate(season = S, week = W, date = s$meta$date, complete = TRUE)
    PL[[length(PL) + 1]] <- d %>% transmute(season = S, week = W, format = "redraft", player_id, name, pos, rank, value, actual = round(actual, 2), complete = TRUE)
  }
  # ---- dynasty ----
  done <- S + NFUT <= LAST - 1                                     # every season of the window is over (LAST is in progress)
  rp <- rep[s$dynasty$pos]
  act0 <- s$dynasty %>% select(player_id) %>% left_join(ros, by = "player_id") %>% mutate(x = pmax(coalesce(pts_ros / n_ros, 0) - rp, 0) * coalesce(n_ros, 0L)) %>% pull(x)
  actf <- sapply(1:NFUT, function(t) { a <- seas %>% filter(season == S + t); m <- a[match(s$dynasty$player_id, a$player_id), ]
    x <- pmax(m$pts / m$g - rp, 0) * m$g; x[is.na(x)] <- 0; x })
  len <- ifelse(S >= 2021, 17, 16)
  d <- s$dynasty %>% mutate(actual = act0 + as.vector(actf %*% v^(1:NFUT)),
                            naive = pmax(ppg - rp, 0) * (pmax(len - W, 0) + len * sum(v^(1:NFUT))) * pmin(games / pmax(W, 1), 1))
  if (S < LAST) {                                                  # 2026 snapshots: nothing to score yet
    RES[[length(RES) + 1]] <- score(d %>% filter(games >= 3), "dynasty") %>% mutate(season = S, week = W, date = s$meta$date, complete = done)
    PL[[length(PL) + 1]] <- d %>% transmute(season = S, week = W, format = "dynasty", player_id, name, pos, rank, value, actual = round(actual, 2), complete = done)
  }
}
R <- bind_rows(RES) %>% mutate(across(c(spearman, spearman_naive, top_hit, top_hit_naive), ~ round(.x, 3)), across(c(pred_total, actual_total), ~ round(.x)))
P <- bind_rows(PL)
write.csv(R, file.path(OUT, "hv_track_record_by_snapshot.csv"), row.names = FALSE)
saveRDS(P, file.path(OUT, "hv_track_record_players.rds"))
# summary: mean over snapshots (each Tuesday counts once), by format, position and season group
sm <- function(x) x %>% summarise(snapshots = n(), players = round(mean(n)), spearman = round(mean(spearman), 3), spearman_naive = round(mean(spearman_naive), 3),
                                  top_hit = round(mean(top_hit, na.rm = TRUE), 3), top_hit_naive = round(mean(top_hit_naive, na.rm = TRUE), 3),
                                  pred_over_actual = round(sum(pred_total) / sum(actual_total), 3), .groups = "drop")
S1 <- bind_rows(R %>% filter(complete) %>% group_by(kind, pos) %>% sm() %>% mutate(seasons = "all complete"),
                R %>% filter(complete) %>% group_by(kind, pos, seasons = as.character(season)) %>% sm(),
                R %>% filter(!complete, kind == "dynasty") %>% group_by(kind, pos) %>% sm() %>% mutate(seasons = "so far (incomplete)"))
write.csv(S1, file.path(OUT, "hv_track_record_summary.csv"), row.names = FALSE)
options(width = 200)
print(as.data.frame(S1 %>% filter(seasons %in% c("all complete", "so far (incomplete)"))))
