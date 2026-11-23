# Mixed points model: does the pre-draft view add to the post-draft 3-year log-points projection, as it does for the hit model?
# Second-stage leave-one-class-out on the out-of-class (LOCO) first-stage projections, 2010-2023 drafted players.
suppressMessages({ library(dplyr); library(tidyr); library(ggplot2) })
A <- readRDS("oof_projections.rds") %>% filter(scheme == "LOCO")
G <- read.csv("/home/user/Football/PostDraft_Model/pd_post_player_grades.csv", stringsAsFactors = FALSE, na.strings = "") %>%
  filter(!is.na(pick)) %>% distinct(position, class, pick, .keep_all = TRUE) %>%
  transmute(pos = position, class, pick, name, pre_grade, faller = mixed_faller, live_mixed = p_top + p_top2 + p_any, live_post = p_top_draft + p_top2_draft + p_any_draft)
pre <- A %>% filter(board == "pre") %>% group_by(pos) %>% mutate(pre_pct = rank(lp3) / n()) %>% ungroup() %>%
  filter(!is.na(gsis_id)) %>% distinct(pos, class, gsis_id, .keep_all = TRUE) %>% select(pos, class, gsis_id, pre_lp3 = lp3, pre_pct, pre_hit3 = hit3)
P <- A %>% filter(board == "post") %>% left_join(G, by = c("pos", "class", "pick")) %>% left_join(pre, by = c("pos", "class", "gsis_id")) %>%
  group_by(pos) %>% mutate(post_pct = rank(lp3) / n(), y = log1p(pmax(pts, 0)),
    pre_lp3 = coalesce(pre_lp3, min(pre_lp3, na.rm = TRUE)), pre_pct = coalesce(pre_pct, 0),
    faller = coalesce(faller, 0L), faller_pts = as.integer(pre_pct >= .85 & post_pct < .85)) %>% ungroup()
cat("post rows", nrow(P), " matched to pre-draft pool:", mean(!is.na(P$pre_hit3)), " fallers (grade):", sum(P$faller), " fallers (points):", sum(P$faller_pts), "\n")
# second-stage LOCO
res <- P %>% group_by(pos) %>% group_modify(function(d, k) bind_rows(lapply(sort(unique(d$class)), function(Y) {
  tr <- d[d$class != Y, ]; te <- d[d$class == Y, ]
  b1 <- coef(lm(I(y - lp3) ~ faller, data = tr))
  b2 <- coef(lm(I(y - lp3) ~ faller_pts, data = tr))
  m3 <- lm(y ~ lp3 + pre_lp3, data = tr)
  te %>% mutate(m_post = lp3, m_faller = lp3 + b1[1] + b1[2] * faller, m_faller_pts = lp3 + b2[1] + b2[2] * faller_pts,
                m_stack = predict(m3, te), b_faller = b1[2], b_faller_pts = b2[2], w_pre = coef(m3)[3]) }))) %>% ungroup()
SC <- c(m_post = "Post-draft points", m_faller = "Mixed: + grade-faller bump", m_faller_pts = "Mixed: + points-faller bump", m_stack = "Mixed: post + pre stack",
        live_post = "Live post-draft hit grade (ref.)", live_mixed = "Live mixed hit grade (ref.)")
met <- function(d) bind_rows(lapply(names(SC), function(s) data.frame(score = s, n = nrow(d),
  rho_pts = cor(d[[s]], d$pts, method = "spearman", use = "complete.obs"),
  rmse_log = if (startsWith(s, "m_")) sqrt(mean((d[[s]] - d$y)^2)) else NA_real_)))
M <- res %>% group_by(pos) %>% group_modify(~ met(.x)) %>% ungroup()
bt <- res %>% group_by(pos) %>% group_modify(function(d, k) { set.seed(2026)
  bind_rows(lapply(setdiff(names(SC)[1:4], "m_post"), function(s) { f <- function(i) cor(d[[s]][i], d$pts[i], method = "spearman") - cor(d$m_post[i], d$pts[i], method = "spearman")
    r <- function(i) sqrt(mean((d[[s]][i] - d$y[i])^2)) / sqrt(mean((d$m_post[i] - d$y[i])^2)) - 1
    b <- replicate(1000, { i <- sample.int(nrow(d), replace = TRUE); c(f(i), r(i)) })
    data.frame(score = s, d_rho = f(seq_len(nrow(d))), d_rho_lo = quantile(b[1, ], .025), d_rho_hi = quantile(b[1, ], .975),
               d_rmse = r(seq_len(nrow(d))), d_rmse_lo = quantile(b[2, ], .025), d_rmse_hi = quantile(b[2, ], .975)) })) }) %>% ungroup()
M <- M %>% left_join(bt, by = c("pos", "score"))
fl <- res %>% filter(faller == 1) %>% group_by(pos) %>% summarise(n = n(), actual_pts = expm1(mean(y)), post_pred_pts = expm1(mean(m_post)), mixed_pred_pts = expm1(mean(m_faller)),
  actual_log = mean(y), post_pred_log = mean(m_post), mixed_pred_log = mean(m_faller), bump = mean(b_faller), .groups = "drop")
coefs <- res %>% group_by(pos) %>% summarise(faller_bump_log = mean(b_faller), faller_pts_bump_log = mean(b_faller_pts), stack_pre_weight = mean(w_pre))
write.csv(M, "mixed_points_metrics.csv", row.names = FALSE); write.csv(fl, "mixed_points_fallers.csv", row.names = FALSE); write.csv(coefs, "mixed_points_coefs.csv", row.names = FALSE)
saveRDS(res, "mixed_points_oof.rds")
options(width = 200); print(as.data.frame(M %>% mutate(across(where(is.double), ~ round(.x, 3)))), row.names = FALSE); print(as.data.frame(fl), digits = 3); print(as.data.frame(coefs), digits = 3)
th <- theme_minimal(base_size = 12) + theme(plot.title = element_text(face = "bold"), panel.grid.minor = element_blank(), plot.background = element_rect(fill = "white", colour = NA))
dir.create("charts", showWarnings = FALSE)
g <- ggplot(bt %>% mutate(score = factor(SC[score], levels = SC[2:4])), aes(d_rho, score)) + geom_vline(xintercept = 0) +
  geom_errorbarh(aes(xmin = d_rho_lo, xmax = d_rho_hi), height = 0, colour = "#0072B2") + geom_point(size = 2.5, colour = "#0072B2") + facet_wrap(~pos, ncol = 4) +
  labs(x = "Spearman with actual 3-year points: mixed version minus post-draft points model (right of 0 = mixed ranks better)", y = NULL,
       title = "Does adding the pre-draft view help the post-draft points projection?", subtitle = "Drafted players 2010-2023, out-of-class; bars = 95% bootstrap interval") + th
ggsave("charts/01_mixed_points_rho.png", g, width = 13, height = 4.2, dpi = 130)
q <- fl %>% select(pos, n, Actual = actual_pts, `Post-draft points model` = post_pred_pts, `Mixed (faller bump)` = mixed_pred_pts) %>% pivot_longer(-c(pos, n))
g <- ggplot(q, aes(pos, value, fill = factor(name, levels = c("Actual", "Post-draft points model", "Mixed (faller bump)")))) + geom_col(position = "dodge", width = .75) +
  geom_text(data = fl, aes(pos, 0, label = paste0("n=", n)), inherit.aes = FALSE, vjust = 1.3, size = 3.5) +
  scale_fill_manual(values = c("#111111", "#56B4E9", "#E69F00"), name = NULL) + labs(x = NULL, y = "3-year PPR points, typical faller (mean on log scale)",
  title = "Fallers: pre-draft A-range players with a lower post-draft grade", subtitle = "Actual mean 3-year points vs what each model projected (out-of-class)") + th + theme(legend.position = "bottom")
ggsave("charts/02_mixed_points_fallers.png", g, width = 9, height = 5.5, dpi = 130)
