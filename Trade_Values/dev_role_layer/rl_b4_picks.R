# =============================================================================
# B4: rookie-pick multiplier and one calibration standard for players and picks
#   ./run.sh rl_b4_picks.R logs/b4_<tag>.txt <tag> [switches as rl_run.R] [CAL]
# 1. pick_factor() exactly as dv_13 (default scoring), then a bootstrap of it: resample draft classes, then players
#    within each class (2000 draws, seed 2026).
# 2. The same multiplier on the definition of realized value used for players in the dynasty backtest: the replacement
#    line of the season being valued (default league lines at week 9 of that season, as for players), and predicted
#    games at each season's real length (16 before 2021).
# 3. CAL: player multipliers per position = actual / predicted in the dynasty backtest (week-9 snapshots 2016-2020,
#    all earlier than 2026), picks x the refit multiplier. Writes exp/b4_<tag>.rds with the default-league board
#    (players and 2027 pick slots, before and after).
# Reads the pre / post-draft grade files in ../Football2_PreDraft and ../Football2_PostDraft (read only).
# =============================================================================
a <- commandArgs(trailingOnly = TRUE); EXP_TAG <- paste0("b4src_", a[1]); NO_WRITE <- TRUE
WIDE_POP <- FALSE; LENFIX <- "LF" %in% a; BT_MIN <- 3
ROLE_AVAIL <- "A2" %in% a; QB_START <- any(c("A3", "A3F") %in% a); QB_FUT_ONLY <- "A3F" %in% a; ROLE_SNAP <- "A4" %in% a
H_DIRECT <- "HD" %in% a; SIG_H <- "SH" %in% a; SURV4 <- "S4" %in% a
AGE_MODE <- if (any(grepl("^AGE=", a))) sub("^AGE=", "", a[grepl("^AGE=", a)][1]) else "none"
source("dv_11_dynasty_v4.R")
src <- readLines("dv_13_league_presets.R"); stop_at <- grep("^for \\(I_ in seq_along\\(RUNS_\\)\\)", src) - 1
eval(parse(text = src[1:stop_at]))                    # settings + tier_cal, pick_factor, prospect_profiles (no runs)
rp <- prospect_profiles()
pf <- pick_factor(rp)                                 # the live multiplier (prints its line)
B <- pf$bt %>% mutate(class = as.integer(class))
set.seed(2026)
boot_f <- function(x, pc = "predK", rc = "realized") replicate(2000, {
  cl <- sample(unique(x$class), replace = TRUE)
  s <- bind_rows(lapply(cl, function(k) { z <- x[x$class == k, ]; z[sample.int(nrow(z), replace = TRUE), ] }))
  sum(s[[rc]]) / sum(s[[pc]]) })
bf <- boot_f(B)
cat(sprintf("\nB4 live pick multiplier %.3f; bootstrap (classes, then players) 95%% interval %.3f - %.3f, sd %.3f (n = %d players, %d classes)\n",
            pf$f, quantile(bf, 0.025), quantile(bf, 0.975), sd(bf), nrow(B), length(unique(B$class))))
cat("by class: predicted, realized, ratio\n"); print(as.data.frame(B %>% group_by(class) %>% summarise(n = n(), pred = round(sum(predK)), real = round(sum(realized)), ratio = round(real / pred, 2))))

# ---------- same definition as players ----------
rep_y <- bv %>% distinct(season, pos, rep_ppg)                       # default-league lines at week 9 of each season
v <- 1 / (1 + I_MAIN)
same <- bind_rows(lapply(sort(unique(B$class)), function(Y) {
  x <- B %>% filter(class == Y); cy <- tier_cal(rp$hk %>% filter(class != Y)); K <- min(NK_, LAST_FULL - Y + 1)
  ry <- setNames(rep_y$rep_ppg[rep_y$season == Y], rep_y$pos[rep_y$season == Y])
  val <- function(i) { cc <- cy %>% filter(pos == x$pos[i], k <= K); a0 <- rp$a_ref$a[rp$a_ref$pos == x$pos[i]]
    d <- c(0, cumsum(sapply(2:NK_, function(k) rp$agef(x$pos[i], x$age[i] + k - 2) - rp$agef(x$pos[i], a0 + k - 2))))[cc$k]
    P <- c(x$p_top[i], x$p_top2[i] - x$p_top[i], x$p_any[i] - x$p_top2[i], 1 - x$p_any[i])
    len <- if (LENFIX) tg_of(Y + cc$k - 1) / 17 else 1
    sum(P[cc$tier] * v^cc$k * cc$G * len * stoploss(cc$mu + d, ry[x$pos[i]], cc$sd)) }
  x$pred_same <- sapply(seq_len(nrow(x)), val)
  rr <- rp$hk %>% filter(class == Y, k <= K) %>% mutate(por = pmax(ifelse(g > 0, pts / g, 0) - ry[pos], 0) * g) %>%
    group_by(pos, pick) %>% summarise(real_same = sum(v^k * por), .groups = "drop")
  x %>% left_join(rr, by = c("pos", "pick")) %>% mutate(real_same = coalesce(real_same, 0)) }))
f_same <- sum(same$real_same) / sum(same$pred_same); bs <- boot_f(same, "pred_same", "real_same")
cat(sprintf("\nB4 pick multiplier on the players' definition (season's own replacement line%s): %.3f, 95%% interval %.3f - %.3f\n",
            if (LENFIX) ", real season length" else "", f_same, quantile(bs, 0.025), quantile(bs, 0.975)))

# ---------- player multipliers (dynasty backtest) ----------
mpos <- BT_ <- bind_rows(BT) %>% group_by(pos) %>% summarise(m = sum(actual) / sum(pred)) %>% { setNames(.$m, .$pos) }
cat("\nplayer multipliers actual / predicted (dynasty backtest 2016-2020 snapshots):", paste(names(mpos), round(mpos, 3), collapse = "  "), "\n")
# leave-one-snapshot-out check: does a per-position multiplier fit on the other snapshot years improve the held-out year?
BB <- bind_rows(BT)
lo <- bind_rows(lapply(unique(BB$season), function(Y) { m <- BB %>% filter(season != Y) %>% group_by(pos) %>% summarise(m = sum(actual) / sum(pred))
  BB %>% filter(season == Y) %>% left_join(m, by = "pos") %>% mutate(pred_cal = pred * m) }))
cat("LOSO multiplier check (held-out snapshot year): RMSE raw", round(sqrt(mean((lo$pred - lo$actual)^2)), 2), " calibrated", round(sqrt(mean((lo$pred_cal - lo$actual)^2)), 2),
    "; predicted / actual raw", round(sum(lo$pred) / sum(lo$actual), 3), " calibrated", round(sum(lo$pred_cal) / sum(lo$actual), 3), "\n")
print(lo %>% group_by(pos) %>% summarise(raw = sum(pred) / sum(actual), cal = sum(pred_cal) / sum(actual), rmse_raw = sqrt(mean((pred - actual)^2)), rmse_cal = sqrt(mean((pred_cal - actual)^2))) %>%
  mutate(across(-pos, ~ round(.x, 3))) %>% as.data.frame())

# ---------- default-league board: players and 2027 pick slots ----------
rep_d <- setNames(b26$rep_ppg[match(POSITIONS, b26$pos)], POSITIONS)
pp <- rp$pp; cal <- rp$cal
pick_val <- sapply(seq_len(nrow(pp)), function(j) { cc <- cal %>% filter(pos == pp$pos[j])
  pr4 <- unlist(pp[j, c("P1", "P2", "P3", "P4")]); if (anyNA(pr4)) return(NA)
  sum(rep(pr4, each = NK_) * rep(v^(1:NK_), 4) * cc$G * stoploss(cc$mu + rep(rp$D[j, ], 4), rep_d[pp$pos[j]], cc$sd)) })
slots <- pp %>% mutate(raw = pick_val) %>% filter(!is.na(raw)) %>% arrange(desc(raw)) %>% mutate(slot = row_number()) %>% filter(slot <= 36) %>%
  transmute(prospect = paste0(name, " (", pos, ")"), name = sprintf("2027 pick %d.%02d", (slot - 1) %/% 12 + 1, (slot - 1) %% 12 + 1), pos = "PICK", age = NA_real_, raw)
saveRDS(list(f_live = pf$f, boot_live = bf, f_same = f_same, boot_same = bs, by_class = B, same = same, mpos = mpos, loso = lo,
             players = b4 %>% select(name, pos, team, age, raw = value_raw), slots = slots), paste0("exp/b4_", a[1], ".rds"))
cat("\nsaved exp/b4_", a[1], ".rds\n", sep = "")
