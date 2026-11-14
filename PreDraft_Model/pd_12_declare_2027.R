# =============================================================================
# Pre-Draft Model -- Phase 12 (FABLE build 2026-11-13, finding 5): chance each 2027 prospect declares, for pricing
#
# The pre-draft model is trained on players in the class they left school, so it learned "young and productive at exit"
# partly from the decision to leave. Scored on every eligible player of 2016-2023 (pd_01 PART 6), it gave about half of
# its predicted hits to players who then stayed in school; predicted hits were about 2x actual. Multiplying by a P(declare)
# fit on earlier classes brought predicted totals in line (QB 27 vs 26, RB 41 vs 51, TE 24 vs 25, WR 45 vs 56).
# This script refits that P(declare) on every eligible class 2010-2023 and scores the 2027 pool:
#   entered ~ position x years out of HS (3..6+) + production percentile + recruiting rating (+ missing flag)
#             + the pre-draft model's own logit P(any tier) (+ its interaction with years out of HS)
# Writes pd_declare_2027.csv (position, name, college, athlete_id, p_declare_refit). dv_13 multiplies the tier
# probabilities of 2027 prospects priced from the PRE-draft model by it (rookie pick values and the boards' Value column);
# prospects in the mock draft (priced post-draft) are left as they are. Run after pd_06 / pd_11 (refresh.sh does).
# =============================================================================
source("pd_common.R"); source("pd_model_fns.R")
elig <- readRDS("pd_eligible_pool.rds"); pool <- readRDS("pd_pool.rds")
S <- lapply(setNames(POSITIONS, POSITIONS), function(P) readRDS(sprintf("pd_%s_models.rds", P)))
score <- function(d) { d$p_any <- NA_real_
  for (P in POSITIONS) { i <- which(d$position == P); if (!length(i)) next; pr <- predict_all(S[[P]], d[i, ]); d$p_any[i] <- pr[[paste0("p3_", S[[P]]$chosen)]] }
  d %>% mutate(lp = qlogis(pmin(pmax(p_any, 1e-4), 1 - 1e-4))) }
vol_of <- function(d) case_when(d$position == "QB" ~ d$p_att, d$position == "RB" ~ d$p_car + d$p_rec, TRUE ~ d$p_rec)
el <- score(elig %>% filter(class >= 2010, class <= 2023)) %>% mutate(vol = vol_of(.)) %>% group_by(position, class) %>% mutate(vol_pct = percent_rank(vol)) %>% ungroup() %>%
  mutate(yb = factor(pmin(pmax(yrs_since_hs, 3), 6)), rr = coalesce(recruit_rating, 0), rr_na = as.integer(is.na(recruit_rating)))
m <- glm(entered ~ position * yb + vol_pct + rr + rr_na + lp + yb:lp, family = binomial, data = el)
ref <- el %>% filter(class == 2023)
p27 <- score(pool %>% filter(class == 2027)) %>% mutate(vol = vol_of(.))
p27$vol_pct <- mapply(function(ps, v) mean(ref$vol[ref$position == ps] < v), p27$position, p27$vol)
p27 <- p27 %>% mutate(yb = factor(pmin(pmax(yrs_since_hs, 3), 6), levels = levels(el$yb)), rr = coalesce(recruit_rating, 0), rr_na = as.integer(is.na(recruit_rating)))
p27$p_declare_refit <- round(predict(m, p27, type = "response"), 4)
out <- p27 %>% transmute(position, name, college = p_team, athlete_id, yrs_since_hs, p_any = round(p_any, 4), p_declare_refit)
write.csv(out, "pd_declare_2027.csv", row.names = FALSE)
cat("pd_declare_2027.csv:", nrow(out), "prospects; mean P(declare) by years out of HS:\n")
print(as.data.frame(out %>% group_by(position, yrs = pmin(yrs_since_hs, 6)) %>% summarise(n = n(), p_declare = round(mean(p_declare_refit), 3), .groups = "drop")), row.names = FALSE)
