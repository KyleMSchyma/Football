# =============================================================================
# dv_11 extensions (Football2_Dynasty_dev), used by the B2 / B3 switches
#   act_p       still-playing probability; AGE_MODE "mono" makes it non-increasing in age after 30
#   se_h        season-end rows with the outcome of season y + h
#   fit_direct  B2(i): direct models for season y + h (h = 1..NFUT) on year-y features, residual sd per h
#   sig_h_fit   B2(ii): sd of h-year-ahead PPG residuals of the recursive projection (instead of sig x sqrt(h))
# All fits use outcomes up to last_y + 1, the same information as fit_future(last_y).
# =============================================================================
act_p <- function(m, nd) {
  p <- predict(m, nd, type = "response")
  if (AGE_MODE == "mono") for (k in 1:15) { i <- which(nd$age - k >= 30); if (!length(i)) break
    n2 <- nd[i, , drop = FALSE]; n2$age <- nd$age[i] - k; p[i] <- pmin(p[i], predict(m, n2, type = "response")) }
  p
}
se_h <- function(h) SE %>% select(player_id, season, pos, cppg, age, exp, lpick, avail) %>%
  left_join(seas %>% transmute(player_id, season = season - h, g_o = g, ppg_o = pts / g, tg_o = tg_season), by = c("player_id", "season")) %>%
  mutate(g_o = coalesce(g_o, 0L), played_o = as.integer(g_o >= MIN_ALIVE), rate_o = ifelse(played_o == 1, pmin(g_o / tg_o, 1), NA))
SEH_ <- lapply(1:NFUT, se_h)
fit_direct <- function(last_y) {
  out <- setNames(vector("list", 4), POSITIONS)
  for (ps in POSITIONS) out[[ps]] <- lapply(1:NFUT, function(h) {
    x <- SEH_[[h]] %>% filter(pos == ps, season + h <= last_y + 1)
    prod <- lm(ppg_o ~ cppg + age_ns(age) + factor(pmin(exp, 3)) + lpick:I(exp <= 2), data = x %>% filter(g_o >= 4), weights = g_o)
    act  <- glm(played_o ~ cppg + age_ns(age) + factor(pmin(exp, 3)) + lpick, data = x, family = binomial)
    av   <- glm(rate_o ~ avail + age_ns(age) + cppg, data = x %>% filter(played_o == 1), family = quasibinomial, weights = tg_o)
    r <- residuals(prod); list(prod = prod, act = act, av = av, sig = sqrt(sum(prod$weights * r^2) / sum(prod$weights)), n = nrow(x)) })
  out
}
sig_h_fit <- function(f, ps, last_y) sapply(1:NFUT, function(h) {
  x <- SEH_[[h]] %>% filter(pos == ps, season + h <= last_y + 1, g_o >= 4)
  cp <- x$cppg; av <- x$avail
  for (t in 1:h) { nd <- data.frame(cppg = cp, age = x$age + t - 1, exp = x$exp + t - 1, lpick = x$lpick, avail = av)
    if (isTRUE(QB_DEPTH)) { nd$depthf <- if (t == 1) x$depthf else factor(rep("unk", nrow(x)), levels = c("1", "2", "3", "unk")); nd$ss <- x$ss }
    pp <- predict(f$prod, nd); av <- predict(f$av, nd, type = "response"); cp <- pp }
  sqrt(sum(x$g_o * (x$ppg_o - cp)^2) / sum(x$g_o)) })
