# =============================================================================
# TEST ONLY (Kyle 2026-11-13): why the 2027 1.01 looks undervalued, and what fixes it. Nothing here feeds the site.
#
# Variants, all in Kyle's league (10 teams, PPR, TE premium +1, 4-pt pass TD, superflex, 2 RB 3 WR 1 TE 2 FLEX):
#   current  players: rest of 2026 + 2027-2030          picks: 2027-2030 (seasons 1-4)
#   A        players: as current                          picks: 2027-2031 (seasons 1-5) + tier calibration
#   B        players: rest of 2026 + 2027-2031           picks: 2027-2031 (seasons 1-5) + tier calibration  (same calendar window)
# Tier calibration: actual vs tier-implied points (seasons 1-4) on 2010-2022 drafted players, by model probabilities,
#   fit leave-one-class-out; the fitted ratio scales the prospect's projected PPG.
# Backtest: classes 2016-2022 (post-draft probabilities = what the model knew after the draft), rookie draft order by each
#   variant's value, slots 1.01-1.12: predicted vs realized discounted points over replacement.
# =============================================================================
SC <- list(ppr = 1, te = 2, ptd = 4, fd = c(QB = 0, RB = 0, WR = 0, TE = 0)); NO_WRITE <- TRUE
source("dv_11_dynasty_v4.R")
cat("\n\n================ PICK FIX TEST ================\n")
LG <- list(teams = 10, qb = 1, rb = 2, wr = 3, te = 1, flex = 2, sf = 1)
RP <- rep_lines(b26, LG); rep_of <- setNames(RP$rep_ppg, RP$pos); print(RP)
sd0 <- setNames(m1$rmse_credibility, m1$pos)

# ---------- players: 4 vs 5 future seasons ----------
d26k <- d26 %>% mutate(rep_ppg = rep_of[pos])
NFUT <- 4; p4 <- project(d26k, F, sd0)
NFUT <- 5; p5 <- project(d26k, F, sd0)
pl <- d26k %>% transmute(name, pos, age, v4 = p4$value, v5 = p5$value)

# ---------- tier calibration, seasons 1-5 ----------
gr  <- read.csv("../Football2_PreDraft/pd_player_grades.csv", stringsAsFactors = FALSE)
gpo <- read.csv("../Football2_PostDraft/pd_post_player_grades.csv", stringsAsFactors = FALSE)
pr_ <- readRDS(file.path(SHARED, "players_raw.rds")) %>%
  transmute(player_id = gsis_id, pos = ifelse(position == "FB", "RB", position), draft_year, draft_pick, birth_date = as.Date(birth_date)) %>%
  filter(pos %in% POSITIONS, !is.na(draft_pick))
h <- gr %>% filter(status == "drafted", class %in% 2010:2022, !is.na(nfl_tier), !is.na(pick)) %>%
  transmute(pos = position, class, pick, tier = pmin(nfl_tier, 4)) %>%
  inner_join(pr_, by = c("pos", "class" = "draft_year", "pick" = "draft_pick")) %>%
  mutate(age0 = as.numeric(as.Date(paste0(class, "-09-01")) - birth_date) / 365.25)
hk <- bind_rows(lapply(1:5, function(k) h %>% mutate(k = k, season = class + k - 1))) %>% filter(season <= 2025) %>%
  left_join(seas %>% select(player_id, season, g, pts, tg_season), by = c("player_id", "season")) %>%
  mutate(g = coalesce(g, 0L), pts = coalesce(pts, 0), tg = coalesce(tg_season, ifelse(season >= 2021, 17L, 16L)), g17 = pmin(g / tg, 1) * 17)
calf <- function(dat) dat %>% group_by(pos, tier, k) %>%
  summarise(G = mean(g17), mu = if (sum(g) > 0) sum(pts) / sum(g) else 0,
            sd = if (sum(g > 0) > 2) sqrt(sum(g[g > 0] * (pts[g > 0] / g[g > 0] - sum(pts) / sum(g))^2) / sum(g)) else NA_real_, .groups = "drop") %>%
  group_by(pos, k) %>% mutate(sd = ifelse(is.na(sd) | sd < 1, max(sd, na.rm = TRUE), sd)) %>% ungroup() %>% arrange(pos, tier, k)
CAL <- calf(hk)
a_ref <- h %>% group_by(pos) %>% summarise(a = mean(age0, na.rm = TRUE)); a_ref <- setNames(a_ref$a, a_ref$pos)
agef <- function(ps, a) predict(F[[ps]]$prod, data.frame(cppg = 0, age = a, exp = 0, lpick = 0))
adj <- function(ps, age) { d <- sapply(2:5, function(k) agef(ps, age + k - 2) - agef(ps, a_ref[ps] + k - 2)); c(0, cumsum(d)) }

# value of one prospect: P = tier probs (4), seasons 1..K, PPG multiplier f
pval <- function(ps, P, age, K, f = 1, cal = CAL, rep = rep_of[ps]) {
  cc <- cal %>% filter(pos == ps, k <= K); d <- adj(ps, age)[cc$k]
  sum(P[cc$tier] * v^cc$k * cc$G * stoploss(f * cc$mu + d, rep, cc$sd)) }
implied4 <- function(ps, P, cal = CAL) { cc <- cal %>% filter(pos == ps, k <= 4); sum(P[cc$tier] * cc$G * cc$mu) }

# ---------- calibration fit: actual 4-season points vs implied, by source of probabilities ----------
act4 <- hk %>% filter(k <= 4) %>% group_by(pos, class, pick) %>% summarise(actual = sum(pts), .groups = "drop")
mkP <- function(x) cbind(x$p_top, x$p_top2 - x$p_top, x$p_any - x$p_top2, 1 - x$p_any)
hist_set <- function(src) { x <- (if (src == "post") gpo else gr %>% filter(status == "drafted")) %>% filter(class %in% 2010:2022, !is.na(pick), !is.na(p_top)) %>%
    transmute(pos = position, class, pick, name, p_top, p_top2, p_any) %>% inner_join(act4, by = c("pos", "class", "pick"))
  Pm <- mkP(x); x$implied <- sapply(seq_len(nrow(x)), function(i) implied4(x$pos[i], Pm[i, ])); x }
HP <- list(post = hist_set("post"), pre = hist_set("pre"))
# ratio actual/implied as a smooth function of implied points (weighted by implied), leave-one-class-out
fit_ratio <- function(x) lm(actual ~ 0 + implied + I(implied^2), data = x)
ratio_of <- function(fit, imp) pmax(predict(fit, data.frame(implied = imp)) / imp, 0.5)
for (s in names(HP)) { x <- HP[[s]]; fit <- fit_ratio(x)
  cat(sprintf("\ncalibration (%s-draft probabilities): actual / implied at implied = 300, 500, 700, 900 points: %s\n", s,
      paste(round(ratio_of(fit, c(300, 500, 700, 900)), 2), collapse = " / ")))
  print(x %>% mutate(b = cut(p_top, c(0, .1, .2, .4, .6, 1))) %>% group_by(b) %>% summarise(n = n(), implied = round(mean(implied)), actual = round(mean(actual)))) }
FIT <- lapply(HP, fit_ratio)

# ---------- 2027 prospects (as on the page: mocked = post-draft, rest = pre-draft) ----------
nm <- function(x) gsub("[^a-z]", "", tolower(sub(" (jr|sr|ii|iii|iv)\\.?$", "", x, ignore.case = TRUE)))
pp <- gr %>% filter(class == 2027) %>% transmute(name, pos = position, age = 18.6 + yrs_out_of_hs, p_top, p_top2, p_any, src = "pre")
mk <- read.csv("../Football2_PostDraft/pd_post_2027_mock_grades.csv", stringsAsFactors = FALSE) %>%
  transmute(name = board_name, pos = position, age = age_est, p_top, p_top2, p_any, src = "post")
pp <- bind_rows(mk, pp[!(paste(nm(pp$name), pp$pos) %in% paste(nm(mk$name), mk$pos)), ])
Pm <- mkP(pp); pp$implied <- sapply(seq_len(nrow(pp)), function(i) implied4(pp$pos[i], Pm[i, ]))
pp$f <- sapply(seq_len(nrow(pp)), function(i) ratio_of(FIT[[pp$src[i]]], pp$implied[i]))
pp$cur <- sapply(seq_len(nrow(pp)), function(i) pval(pp$pos[i], Pm[i, ], pp$age[i], 4))
pp$k5  <- sapply(seq_len(nrow(pp)), function(i) pval(pp$pos[i], Pm[i, ], pp$age[i], 5))
pp$fix <- sapply(seq_len(nrow(pp)), function(i) pval(pp$pos[i], Pm[i, ], pp$age[i], 5, pp$f[i]))
slots <- function(x) sort(x, decreasing = TRUE)
rank_in <- function(val, pv) sum(pv > val) + 1
res <- tibble(variant = c("current (picks 4 seasons, no calibration)", "window only (picks 5 seasons)", "A: picks 5 seasons + calibration",
                          "B: everyone through 2031 + calibration"),
  players = c("v4", "v4", "v4", "v5"), picks = c("cur", "k5", "fix", "fix")) %>% rowwise() %>%
  mutate(top = max(pl[[players]]), v101 = slots(pp[[picks]])[1], v106 = slots(pp[[picks]])[6], v112 = slots(pp[[picks]])[12], v124 = slots(pp[[picks]])[24],
         rank_101 = rank_in(v101, pl[[players]]), rank_106 = rank_in(v106, pl[[players]]), rank_112 = rank_in(v112, pl[[players]])) %>% ungroup() %>%
  mutate(value_101 = round(1e5 * v101 / top), value_106 = round(1e5 * v106 / top), value_112 = round(1e5 * v112 / top), value_212 = round(1e5 * v124 / top))
cat("\nKyle's league: 2027 pick values (100k = top player) and where they rank among players\n")
print(as.data.frame(res %>% select(variant, value_101, rank_101, value_106, rank_106, value_112, rank_112, value_212)))
for (who in c("Ashton Jeanty", "Jeremiyah Love", "Ja'Marr Chase", "Jaxon Smith-Njigba")) { i <- which(pl$name == who)
  cat(sprintf("  %-20s current %6.0f (rank %d)   through 2031 %6.0f (rank %d)\n", who, 1e5 * pl$v4[i] / max(pl$v4), rank_in(pl$v4[i], pl$v4) ,
              1e5 * pl$v5[i] / max(pl$v5), rank_in(pl$v5[i], pl$v5))) }
cat("\n1.01 =", pp$name[which.max(pp$fix)], " calibration multiplier on PPG:", round(pp$f[which.max(pp$fix)], 2), "\n")

# ---------- backtest: rookie-draft slots 1.01-1.12, classes 2016-2022 ----------
# realized: discounted points over replacement in seasons 1..K (as many as have been played, up to 5; 2021-2022 classes are cut short)
real_k <- hk %>% mutate(por = pmax(ifelse(g > 0, pts / g, 0) - rep_of[pos], 0) * g * 17 / tg)
BT <- bind_rows(lapply(2016:2022, function(Y) {
  x <- gpo %>% filter(class == Y, !is.na(p_top), !is.na(pick)) %>% transmute(pos = position, class, pick, name, p_top, p_top2, p_any) %>%
    inner_join(pr_ %>% select(pos, draft_year, draft_pick, birth_date), by = c("pos", "class" = "draft_year", "pick" = "draft_pick")) %>%
    mutate(age = as.numeric(as.Date(paste0(Y, "-09-01")) - birth_date) / 365.25, age = ifelse(is.na(age), 22, age))
  calY <- calf(hk %>% filter(class != Y)); xo <- HP$post %>% filter(class != Y); fitY <- fit_ratio(xo)
  Pm <- mkP(x); x$implied <- sapply(seq_len(nrow(x)), function(i) implied4(x$pos[i], Pm[i, ], calY)); x$f <- ratio_of(fitY, x$implied)
  x$cur <- sapply(seq_len(nrow(x)), function(i) pval(x$pos[i], Pm[i, ], x$age[i], 4, 1, calY))
  x$fix <- sapply(seq_len(nrow(x)), function(i) pval(x$pos[i], Pm[i, ], x$age[i], 5, x$f[i], calY))
  K <- min(5, 2025 - Y + 1)
  rr <- real_k %>% filter(class == Y, k <= K) %>% group_by(pos, pick) %>% summarise(realized = sum(v^k * por), .groups = "drop")
  x <- x %>% left_join(rr, by = c("pos", "pick")) %>% mutate(realized = coalesce(realized, 0), K = K)
  # predicted value over the same seasons that have been played, for a fair comparison
  x$fixK <- sapply(seq_len(nrow(x)), function(i) pval(x$pos[i], Pm[i, ], x$age[i], K, x$f[i], calY))
  x$curK <- sapply(seq_len(nrow(x)), function(i) pval(x$pos[i], Pm[i, ], x$age[i], min(K, 4), 1, calY))
  bind_rows(x %>% arrange(desc(cur)) %>% mutate(slot = row_number(), variant = "current"),
            x %>% arrange(desc(fix)) %>% mutate(slot = row_number(), variant = "fix (A)")) %>% filter(slot <= 12) }))
cat("\nBACKTEST, rookie-draft slots 1.01-1.12 of the 2016-2022 classes (Kyle's league lines; seasons played so far, up to 5)\n")
saveRDS(BT, "dv_15_bt_debug.rds"); BT <- BT %>% mutate(pred = ifelse(variant == "current", curK, fixK))
print(as.data.frame(BT %>% group_by(variant) %>% summarise(n = n(),
  predicted = round(mean(pred)), realized_avg = round(mean(realized)),
  pred_over_real = round(sum(pred) / sum(realized), 2),
  spearman = round(cor(pred, realized, method = "spearman"), 2))))
print(as.data.frame(BT %>% mutate(grp = cut(slot, c(0, 3, 6, 12), labels = c("1.01-1.03", "1.04-1.06", "1.07-1.12"))) %>%
  group_by(variant, grp) %>% summarise(predicted = round(mean(pred)), realized = round(mean(realized)), .groups = "drop")))
cat("\npast 1.01s under the fix:\n"); print(as.data.frame(BT %>% filter(variant == "fix (A)", slot == 1) %>% transmute(class, name, pos, predicted = round(fixK), realized = round(realized))))
cat("\nrealized value by rookie-draft slot (model order, post-draft probabilities), 2016-2022, Kyle's league lines:\n")
print(as.data.frame(BT %>% filter(variant == "fix (A)") %>% group_by(slot) %>% summarise(predicted = round(mean(fixK)), realized = round(mean(realized)),
  median_real = round(median(realized)), who = paste(substr(name, 1, 14), collapse = ", "))), row.names = FALSE)
