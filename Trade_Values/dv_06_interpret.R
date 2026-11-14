# =============================================================================
# Dynasty Model, step 6: opening the black box
#   1. Partial dependence (PDP) + ICE: how survival S(3) and the value score move with age, by position
#   2. Partial dependence of the score on this season's pace (par_rate)
#   3. SHAP (kernel SHAP) for the top of the board: which facts pushed each player's score up or down
# Variable importance lives in dv_rsf_importance.csv (survival forest) and dv_production_rf_importance.csv.
# =============================================================================
source("dv_common.R"); suppressMessages({ library(ranger); library(statmod); library(ggplot2); library(kernelshap) })
cat("== Dynasty step 6: interpretation ==\n")
sm <- readRDS("dv_survival_models.rds"); pm <- readRDS("dv_production_models.rds")
lm <- readRDS("dv_landmarks.rds"); board <- read.csv("dv_dynasty_value_board.csv")
act <- lm %>% filter(season == CUR, games >= 3)
dvs_fun <- function(d) value_parts(sm, pm, d, offset = rep(0, nrow(d)))$dvs
top <- max(board$dvs_points)

# ---- 1. PDP / ICE by age, startable players only ----
pd <- list(); ice <- list()
for (ps in POSITIONS) {
  base <- act %>% filter(pos == ps, startable == 1)
  for (a in seq(22, 36, 1)) {
    d <- base; shift <- a - d$age; d$age <- a; d$exp <- pmax(0, d$exp + round(shift))
    vp <- value_parts(sm, pm, d, offset = rep(0, nrow(d)))
    pd[[length(pd) + 1]] <- data.frame(pos = ps, age = a, S3 = mean(vp$S3), score = mean(100 * vp$dvs / top), e_life = mean(vp$e_life))
    ice[[length(ice) + 1]] <- data.frame(pos = ps, age = a, name = base$name, score = 100 * vp$dvs / top)
  }
}
pd <- bind_rows(pd); ice <- bind_rows(ice)
write.csv(pd %>% mutate(across(where(is.numeric), ~ round(.x, 3))), "dv_pdp_age.csv", row.names = FALSE)
cat("\nPDP: average for today's startable players if they were this age (S3 = alive 3 seasons out):\n")
print(pd %>% filter(age %in% c(23, 25, 27, 29, 31, 33)) %>% mutate(across(c(S3, score, e_life), ~ round(.x, 2))) %>%
        pivot_wider(id_cols = age, names_from = pos, values_from = c(score, e_life)))
g <- ggplot() + geom_line(data = ice, aes(age, score, group = name), color = "grey75", alpha = .5) +
  geom_line(data = pd, aes(age, score, color = pos), linewidth = 1.4) + facet_wrap(~ pos, scales = "free_y") +
  scale_color_manual(values = mycols, guide = "none") +
  labs(title = "How age moves the Dynasty Value Score (PDP in color, each grey line is one current startable player)",
       x = "Age (all else held at the player's 2026 profile)", y = "Dynasty Value Score") + theme_minimal(base_size = 11)
ggsave("plot_pdp_ice_age.png", g, width = 10, height = 6.5, dpi = 120)
g <- ggplot(pd, aes(age, S3, color = pos)) + geom_line(linewidth = 1.2) + scale_color_manual(values = mycols) +
  scale_y_continuous(labels = scales::percent) +
  labs(title = "Chance a currently startable player is still alive three seasons out, by age (PDP)", x = "Age", y = "S(3)", color = NULL) +
  theme_minimal(base_size = 12)
ggsave("plot_pdp_survival_age.png", g, width = 8, height = 5, dpi = 120)

# ---- 2. PDP of this season's per-game pace ----
pr <- list()
for (ps in POSITIONS) { base <- act %>% filter(pos == ps, startable == 1)
  for (r in seq(-50, 250, 25)) { d <- base; d$par_rate <- r
    pr[[length(pr) + 1]] <- data.frame(pos = ps, par_rate = r, score = mean(100 * dvs_fun(d) / top)) } }
pr <- bind_rows(pr); write.csv(pr, "dv_pdp_pace.csv", row.names = FALSE)
g <- ggplot(pr, aes(par_rate, score, color = pos)) + geom_line(linewidth = 1.2) + scale_color_manual(values = mycols) +
  labs(title = "PDP: Dynasty Value Score vs this season's per-game pace above replacement",
       x = "Per-game pace above replacement (x17 games)", y = "Dynasty Value Score", color = NULL) + theme_minimal(base_size = 12)
ggsave("plot_pdp_pace.png", g, width = 8, height = 5, dpi = 120)

# ---- 3. SHAP for the top 25 (kernel SHAP, background = 25 random active players) ----
set.seed(2026)
X_feats <- setdiff(FEATS, character(0))
explain <- act %>% filter(player_id %in% head(board$player_id[board$basis != "2025 season (under 3 games in 2026)"], 25))
bg <- act %>% slice_sample(n = 25)
pf <- function(object, newdata) { d <- as.data.frame(newdata); d$pos <- factor(d$pos, POSITIONS)
  d$draft <- factor(d$draft, levels(lm$draft)); 100 * dvs_fun(d) / top }
t0 <- Sys.time()
ks <- if (file.exists("dv_shap_kernel.rds")) readRDS("dv_shap_kernel.rds") else {
  k <- kernelshap(object = NULL, X = explain[, X_feats], bg_X = bg[, X_feats], pred_fun = pf, verbose = FALSE)
  saveRDS(k, "dv_shap_kernel.rds"); k }   # cached: about 18 minutes to compute
cat("\nkernel SHAP time:", round(difftime(Sys.time(), t0, units = "mins"), 1), "min\n")
sv <- as.data.frame(ks$S); sv$name <- explain$name; sv$position <- as.character(explain$pos)
sv$baseline <- as.numeric(ks$baseline); sv$score <- sv$baseline + rowSums(ks$S)
long <- sv %>% pivot_longer(all_of(X_feats), names_to = "feature", values_to = "shap")
labels <- c(pos = "position", age = "age", exp = "years in NFL", draft = "draft round", par = "season pace above replacement",
            par_prev = "last season above replacement", startable = "startable this season", startable_prev = "startable last season",
            n_startable = "career startable seasons", ppg = "points per game", games_frac = "share of games played",
            opp_pg = "opportunities per game", par_rate = "per-game pace above replacement", par_best3 = "best season of last three")
why <- long %>% group_by(name, position) %>% arrange(desc(abs(shap)), .by_group = TRUE) %>%
  summarise(score = round(first(score), 1), why = paste(paste0(labels[feature[1:3]], " ", ifelse(shap[1:3] > 0, "+", ""), round(shap[1:3], 1)), collapse = "; "),
            .groups = "drop") %>% arrange(desc(score))
cat("\nbaseline (average background player):", round(sv$baseline[1], 1), "\n"); print(as.data.frame(why))
write.csv(long %>% mutate(feature_label = labels[feature], shap = round(shap, 2)), "dv_shap_top25.csv", row.names = FALSE)
write.csv(why, "dv_shap_top25_why.csv", row.names = FALSE)
imp <- long %>% group_by(feature) %>% summarise(mean_abs_shap = mean(abs(shap))) %>% arrange(desc(mean_abs_shap)) %>% mutate(label = labels[feature])
cat("\nmean |SHAP| over the top 25:\n"); print(imp)
g <- ggplot(imp, aes(reorder(label, mean_abs_shap), mean_abs_shap)) + geom_col(fill = "#0072B2") + coord_flip() +
  labs(title = "What drives the score at the top of the board (mean |SHAP|, top 25 players)", x = NULL, y = "Average score points moved") +
  theme_minimal(base_size = 12)
ggsave("plot_shap_importance.png", g, width = 8, height = 5, dpi = 120)
