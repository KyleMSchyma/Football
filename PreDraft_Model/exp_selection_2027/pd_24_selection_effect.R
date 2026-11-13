# =============================================================================
# FABLE build part 10 (finding 5): the pre-draft "youth" selection effect and two fixes for the 2027 board / picks (dev only)
#   1. Quantify: score the eligible pool of classes 2016-2023 (every player 3+ years out of high school with college stats
#      the season before, whether or not he left school; pd_01 PART 6) with the final pre-draft model of each position.
#      (a) players who entered the draft: mean predicted P(any tier) vs actual hit rate, by position and years out of HS
#      (b) players who stayed: predicted P(any tier) mass assigned to them (realized hit rate in that class is 0 by
#          construction). Note: entrants of 2010-2023 are the model's training rows, so (a) is in-sample.
#   2. Fix A: multiply by a refit P(declare) (eligible pool 2010-2023: position x years out of HS, production percentile,
#      recruiting rating, and the model's own P(any tier); no consensus-list feature exists for past classes on the PC).
#      Checked on the eligible pool 2016-2023 with the declare model fit on classes <= Y - 1 only.
#      Fix B: keep the 2027 pick pool to mocked players plus prospects with P(declare) >= 0.5.
#   3. 2027 effect: the pre-draft 2027 board under each, and the default-league rookie pick curve 1.01-3.12
#      (dev presets from Football2_Dynasty_dev, 100k = the top player there).
# Writes pd24_*.csv.  Run from Football2_PostDraft_exp.
# =============================================================================
suppressMessages({ library(dplyr); library(tidyr) })
PRE <- normalizePath("../Football2_PreDraft"); DYN <- normalizePath("../Football2_Dynasty_dev")
old <- setwd(PRE); source("pd_common.R"); source("pd_model_fns.R")
elig <- readRDS("pd_eligible_pool.rds"); pool <- readRDS("pd_pool.rds"); dec <- readRDS("pd_declare.rds")
S <- lapply(setNames(POSITIONS, POSITIONS), function(P) readRDS(sprintf("pd_%s_models.rds", P))); setwd(old)
el <- bind_rows(lapply(POSITIONS, function(P) { d <- elig %>% filter(position == P, class >= 2010, class <= 2023)
  pr <- predict_all(S[[P]], d); ch <- S[[P]]$chosen
  d %>% mutate(p_any = pr[[paste0("p3_", ch)]], p_top = pr[[paste0("p1_", ch)]]) }))
el <- el %>% mutate(tier = mapply(function(p, b) if (is.na(b)) 4L else as.integer(sum(b > TIERS[[p]]) + 1L), position, best_finish_3yr),
                    hit = as.integer(entered == 1 & tier <= 3), yrs = pmin(yrs_since_hs, 5))
cat("eligible pool rows 2010-2023:", nrow(el), " entered:", sum(el$entered), "\n")
# ---------- 1. quantify (2016-2023) ----------
q <- el %>% filter(class >= 2016) %>% group_by(position, yrs, entered) %>%
  summarise(n = n(), mean_pred_any = mean(p_any), predicted_hits = sum(p_any), actual_hits = sum(hit), actual_rate = mean(hit), .groups = "drop") %>%
  mutate(group = ifelse(entered == 1, "declared", "stayed"), across(where(is.double), ~ round(.x, 3)))
write.csv(q, "pd24_selection_quantify.csv", row.names = FALSE)
options(width = 200); cat("\n(a) declared vs (b) stayed, eligible pool 2016-2023 (yrs = years out of HS, 5 = 5+):\n"); print(as.data.frame(q %>% select(position, yrs, group, n, mean_pred_any, predicted_hits, actual_hits, actual_rate)), row.names = FALSE)
cat("\npredicted hit mass on players who stayed, share of all predicted mass in their class:\n")
print(as.data.frame(el %>% filter(class >= 2016) %>% group_by(position) %>% summarise(mass_stayers = sum(p_any[entered == 0]), mass_all = sum(p_any), share_stayers = round(mass_stayers / mass_all, 3),
  actual_hits = sum(hit), .groups = "drop")), row.names = FALSE)
# ---------- 2. fix A: refit P(declare), rolling by class ----------
el <- el %>% group_by(position, class) %>% mutate(vol = case_when(position == "QB" ~ p_att, position == "RB" ~ p_car + p_rec, TRUE ~ p_rec), vol_pct = percent_rank(vol)) %>% ungroup() %>%
  mutate(yb = factor(pmin(pmax(yrs_since_hs, 3), 6)), rr = coalesce(recruit_rating, 0), rr_na = as.integer(is.na(recruit_rating)), lp = qlogis(pmin(pmax(p_any, 1e-4), 1 - 1e-4)))
fdec <- function(d) glm(entered ~ position * yb + vol_pct + rr + rr_na + lp + yb:lp, family = binomial, data = d)
el$p_dec <- NA_real_
for (Y in 2016:2023) { m <- fdec(el %>% filter(class < Y)); i <- which(el$class == Y); el$p_dec[i] <- predict(m, el[i, ], type = "response") }
chk <- el %>% filter(class >= 2016) %>% mutate(p_fixA = p_any * p_dec) %>% group_by(position) %>%
  summarise(n = n(), actual_hits = sum(hit), pred_raw = sum(p_any), pred_fixA = sum(p_fixA), brier_raw = mean((p_any - hit)^2), brier_fixA = mean((p_fixA - hit)^2),
            declare_auc = { y <- entered; p <- p_dec; r <- rank(p); n1 <- sum(y); n0 <- sum(1 - y); (sum(r[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0) }, .groups = "drop") %>%
  mutate(across(where(is.double), ~ round(.x, 4)))
write.csv(chk, "pd24_fixA_check.csv", row.names = FALSE)
cat("\nFix A on the eligible pool 2016-2023 (target: hit in that class, 0 for stayers; declare model fit on earlier classes):\n"); print(as.data.frame(chk), row.names = FALSE)
# ---------- 3. 2027: board and pick curve ----------
mdec <- fdec(el)                                                      # all eligible classes 2010-2023
g27 <- read.csv(file.path(PRE, "pd_player_grades.csv"), stringsAsFactors = FALSE) %>% filter(class == 2027)
p27 <- pool %>% filter(class == 2027) %>% group_by(position) %>% mutate(vol = case_when(position == "QB" ~ p_att, position == "RB" ~ p_car + p_rec, TRUE ~ p_rec)) %>% ungroup()
vref <- el %>% filter(class == 2023)
p27 <- p27 %>% rowwise() %>% mutate(vol_pct = mean(vref$vol[vref$position == position] < vol)) %>% ungroup() %>%
  mutate(yb = factor(pmin(pmax(yrs_since_hs, 3), 6), levels = levels(el$yb)), rr = coalesce(recruit_rating, 0), rr_na = as.integer(is.na(recruit_rating)))
p27$p_any <- NA_real_
for (P in POSITIONS) { i <- which(p27$position == P); pr <- predict_all(S[[P]], p27[i, ]); p27$p_any[i] <- pr[[paste0("p3_", S[[P]]$chosen)]] }
p27 <- p27 %>% mutate(lp = qlogis(pmin(pmax(p_any, 1e-4), 1 - 1e-4)))
p27$p_dec_new <- predict(mdec, p27, type = "response")
g27 <- g27 %>% left_join(p27 %>% select(position, name, p_dec_new), by = c("position", "name"))
b27 <- g27 %>% transmute(position, name, college, yrs_out_of_hs, grade, p_any, p_declare_old = p_declare, p_declare_new = round(p_dec_new, 3),
                         p_any_fixA = round(p_any * coalesce(p_dec_new, p_declare, 1), 3)) %>% arrange(desc(p_any))
write.csv(b27, "pd24_board_2027.csv", row.names = FALSE)
cat("\n2027 board, top 25 by current P(any tier):\n"); print(as.data.frame(head(b27, 25)), row.names = FALSE)
# pick curve, default league, from the dev presets (the page's math in R)
grab <- function(file, nms) for (e in parse(file)) if (is.call(e) && identical(deparse(e[[1]]), "<-") && is.name(e[[2]]) && as.character(e[[2]]) %in% nms) eval(e, globalenv())
grab(file.path(DYN, "dv_10_ros_value.R"), c("rep_lines", "MIN_G_REP", "LG_DEFAULT")); grab(file.path(DYN, "dv_13_league_presets.R"), c("stoploss", "league_values"))
PR <- readRDS(file.path(DYN, "dv_league_presets.rds")); top <- max(league_values(PR, LG_DEFAULT)$players$dynasty, na.rm = TRUE)
nk <- function(x) gsub("[^a-z]", "", tolower(x))
pp <- PR$picks$pp; pre_rows <- !grepl("^post-draft", pp$source)
pd <- b27$p_declare_new[match(paste(nk(pp$name), pp$pos), paste(nk(b27$name), b27$position))]; pd[is.na(pd)] <- 1
curve <- function(P2, label) { PR2 <- PR; PR2$picks$pp <- P2
  # D (age adjustments) is keyed by the row index of pp; keep the original rows and their keys
  L <- league_values(PR2, LG_DEFAULT); s <- L$slots %>% head(36)
  tibble(version = label, slot = seq_len(nrow(s)), pick = sprintf("%d.%02d", (slot - 1) %/% 12 + 1, (slot - 1) %% 12 + 1), name = s$name, pos = s$pos, source = s$source,
         value_100k = round(1e5 * s$val / top)) }
A <- pp; A[pre_rows, c("P1", "P2", "P3")] <- A[pre_rows, c("P1", "P2", "P3")] * pd[pre_rows]; A$P4 <- 1 - A$P1 - A$P2 - A$P3
B <- pp; B[pre_rows & pd < 0.5, c("P1", "P2", "P3")] <- 0; B$P4 <- 1 - B$P1 - B$P2 - B$P3     # dropped prospects get zero value (row keys kept)
CV <- bind_rows(curve(pp, "current"), curve(A, "A: x P(declare)"), curve(B, "B: mocked + P(declare) >= 0.5"))
write.csv(CV, "pd24_pick_curve.csv", row.names = FALSE)
cat("\npick curve, default league (100k scale):\n"); print(as.data.frame(CV %>% select(version, pick, value_100k) %>% pivot_wider(names_from = version, values_from = value_100k)), row.names = FALSE)
cat("\nprospects removed by B (P(declare) < 0.5, pre-draft priced):", sum(pre_rows & pd < 0.5), "of", sum(pre_rows), "\n")
