# What would change on today's board? 2026 credible PPG with the live pick prior vs the mixed-model prior (live k's for each).
source("prospect_prior/pp_00_common.R")
CUT <- max(w$week[w$season == CUR]); cat("2026 through week", CUT, "\n")
d <- snapshot(CUR, 3)
K <- read.csv(file.path(OUT, "pp_constants.csv"))
res <- lapply(c("pick", "mixed"), function(v) { x <- d; x$prior <- prior_ppg(CUR, x, v); x$used <- attr(x$prior, "used")
  k <- K %>% filter(variant == paste0(v, "_h3")); kk <- k[match(x$pos, k$pos), ]
  x$cppg <- cred_ppg(x, kk$k1, kk$k2); x %>% transmute(player_id, name, pos, exp, draft_pick, n_cur, g_h, ppg_cur, used, !!paste0("prior_", v) := prior, !!paste0("cppg_", v) := cppg) })
m <- res[[1]] %>% inner_join(res[[2]] %>% select(player_id, used_m = used, prior_mixed, cppg_mixed), by = "player_id") %>%
  mutate(diff = cppg_mixed - cppg_pick) %>% filter(exp <= 2, used_m) %>% arrange(desc(abs(diff)))
options(width = 200); print(m %>% mutate(across(where(is.double), ~ round(.x, 2))) %>% select(-used, -used_m) %>% head(25))
cat("\nyears 1-3 with a prospect prior:", nrow(m), "  mean |change| in credible PPG:", round(mean(abs(m$diff)), 2), "  share moving 0.5+ PPG:", round(mean(abs(m$diff) >= .5), 3), "\n")
write.csv(m, file.path(OUT, "pp_2026_movers_yrs1to3.csv"), row.names = FALSE)
