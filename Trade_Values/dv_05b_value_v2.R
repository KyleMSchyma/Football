# =============================================================================
# Dynasty Model, step 5b: version 2 of the score (Kyle, 2026-11-11)
#
#   Dynasty value = Fantasy Value x a(5)
#   Fantasy Value (FV) = expected points above the startable line next season (production model, t = 1)
#   a(5) = sum_{t=1..5} v^(t-1) S(t), v = 1/1.15   (5-year temporary annuity factor; max 3.86)
# Also reports FV_now = this season's pace above the line (2026 pro-rated), and compares ranks with the
# 10-season version in dv_dynasty_value_board.csv.
# =============================================================================
source("dv_common.R"); suppressMessages({ library(ranger); library(statmod) })
cat("== Dynasty step 5b: value v2 (FV x 5-year annuity factor) ==\n")
H5 <- 5; v <- 1 / (1 + I_MAIN)
lm <- readRDS("dv_landmarks.rds"); sm <- readRDS("dv_survival_models.rds"); pm <- readRDS("dv_production_models.rds")
old <- read.csv("dv_dynasty_value_board.csv")
act <- lm %>% filter(player_id %in% old$player_id) %>%
  inner_join(old %>% select(player_id, basis), by = "player_id") %>%
  filter((season == CUR & !grepl("^2025", basis)) | (season == LAST_FULL & grepl("^2025", basis))) %>%
  mutate(offset = ifelse(season == LAST_FULL, 1, 0))
HH <- H5 + 1
S <- (S_glm(sm$glm, act, HH) + S_rsf(sm$rsf, act, HH)) / 2
M <- M_prod(pm, act, HH)
res <- t(sapply(seq_len(nrow(act)), function(r) {
  k <- (act$offset[r] + 1):(act$offset[r] + H5); s <- S[r, k]
  c(fv = M[r, k[1]], a5 = sum(v^(0:(H5 - 1)) * s), S1 = s[1], S3 = s[3], S5 = s[5])
}))
b <- bind_cols(act %>% select(player_id, name, pos, age, par, basis), as.data.frame(res)) %>%
  mutate(fv_now = pmax(par, 0), dv = fv * a5, score = round(100 * dv / max(dv), 1),
         rank_v2 = rank(-dv, ties.method = "first")) %>%
  left_join(old %>% select(player_id, team, age_2027, rank_v1 = rank_overall, score_v1 = score), by = "player_id") %>%
  group_by(pos) %>% mutate(rank_pos_v2 = rank(-dv, ties.method = "first")) %>% ungroup() %>% arrange(rank_v2)
out <- b %>% transmute(rank_v2, rank_pos_v2, name, pos, team, age_2027, basis, fv_next = round(fv, 1), fv_now = round(fv_now, 1),
  annuity_5 = round(a5, 2), dynasty_value = round(dv, 1), score, S_2027 = round(S1, 3), S_2029 = round(S3, 3), S_2031 = round(S5, 3),
  rank_v1, score_v1, move = rank_v1 - rank_v2, player_id)
write.csv(out, "dv_dynasty_value_board_v2.csv", row.names = FALSE)
options(width = 200)
cat("\nTop 50, version 2 (FV = expected next-season PAR+, a(5) = 5-year annuity factor):\n")
print(out %>% select(rank_v2, name, pos, team, age_2027, fv_next, fv_now, annuity_5, score, rank_v1, move) %>% head(50), n = 50)
cat("\nPosition mix of the top 24 / 50 / 100, v1 vs v2:\n")
for (k in c(24, 50, 100)) cat(k, " v1:", paste(names(table(out$pos[out$rank_v1 <= k])), table(out$pos[out$rank_v1 <= k]), collapse = " "),
                              "  v2:", paste(names(table(out$pos[out$rank_v2 <= k])), table(out$pos[out$rank_v2 <= k]), collapse = " "), "\n")
cat("\nAnnuity factor by position, startable players (median):\n")
print(b %>% filter(par >= 0) %>% group_by(pos) %>% summarise(n = n(), a5_median = round(median(a5), 2), a5_min = round(min(a5), 2), a5_max = round(max(a5), 2)))
cat("\nBiggest risers / fallers in the top 60 (v2 vs v1):\n")
print(out %>% filter(rank_v2 <= 60 | rank_v1 <= 60) %>% arrange(desc(move)) %>% select(name, pos, age_2027, rank_v1, rank_v2, move) %>% head(8))
print(out %>% filter(rank_v2 <= 60 | rank_v1 <= 60) %>% arrange(move) %>% select(name, pos, age_2027, rank_v1, rank_v2, move) %>% head(8))
