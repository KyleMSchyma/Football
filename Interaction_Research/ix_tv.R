# Trade values: dynasty aging model (dv_11 prod / act) and draft-capital prior (dv_10 potential_fit) vs + squared / interaction terms.
# Rebuilds dv_11's season-end table (default scoring: full PPR) from the PC caches; holdout = rolling by season.
suppressMessages({ library(dplyr); library(splines) })
UP <- Sys.getenv("PC_DATA", "../..")   # folder holding Football2/cache and Football2_Dynasty (on the PC: Documents/R Studio)
POSITIONS <- c("QB", "RB", "WR", "TE")
K <- as.matrix(read.csv("../Trade_Values/dv_ros_credibility_k.csv", row.names = 1))
w <- readRDS(file.path(UP, "Football2/cache/nfl_weekly_raw.rds")); w26 <- readRDS(file.path(UP, "Football2_Dynasty/nfl_weekly_2026.rds"))
w <- bind_rows(w, w26[, intersect(names(w26), names(w))]) %>% filter(season_type == "REG"); w$position[w$position == "FB"] <- "RB"
w <- w %>% filter(position %in% POSITIONS) %>% transmute(player_id, position, season, week, team, pts = coalesce(fantasy_points_ppr, 0))
tw <- w %>% distinct(season, team, week)
seas <- w %>% group_by(player_id, season) %>% summarise(g = n_distinct(week), pts = sum(pts), team = last(team), .groups = "drop") %>%
  left_join(tw %>% count(season, team, name = "tg_season"), by = c("season", "team"))
p <- readRDS(file.path(UP, "Football2/cache/players_raw.rds")) %>% transmute(player_id = gsis_id, draft_pick, rookie_season, birth_date = as.Date(birth_date))
seasP <- seas %>% inner_join(w %>% count(player_id, season, position) %>% group_by(player_id, season) %>% slice_max(n, n = 1, with_ties = FALSE) %>%
                               select(player_id, season, pos = position), by = c("player_id", "season"))
pot_form <- list(base = ppg ~ ns(lpick, knots = log(c(32, 100)), Boundary.knots = log(c(1, 262))) + factor(exp),
                 int  = ppg ~ ns(lpick, knots = log(c(32, 100)), Boundary.knots = log(c(1, 262))) + factor(exp) + lpick:factor(exp))
pot_tr <- function(yr) seasP %>% filter(season < yr, season >= yr - 10, g >= 1) %>% inner_join(p, by = "player_id") %>%
  mutate(exp = pmin(pmax(season - coalesce(rookie_season, season), 0), 4), lpick = log(coalesce(draft_pick, 262)), ppg = pts / g)
potential_ppg <- function(yr, d) { tr <- pot_tr(yr); out <- rep(NA_real_, nrow(d))
  for (ps in POSITIONS) { i <- which(d$pos == ps); f <- lm(pot_form$base, data = tr %>% filter(pos == ps), weights = g)
    out[i] <- predict(f, data.frame(lpick = d$lpick[i], exp = pmin(d$exp[i], 4))) }; out }
season_end <- function(y) {
  cur <- seasP %>% filter(season == y, g >= 1)
  his <- seas %>% filter(season >= y - 3, season <= y - 1) %>% group_by(player_id) %>% summarise(g_h = sum(g), pts_h = sum(pts), .groups = "drop") %>% mutate(ppg_h = pts_h / g_h)
  d <- cur %>% left_join(his, by = "player_id") %>% left_join(p, by = "player_id") %>%
    mutate(g_h = coalesce(g_h, 0), exp = pmax(0, y - coalesce(rookie_season, y)), lpick = log(coalesce(draft_pick, 262)),
           age = as.numeric(as.Date(paste0(y, "-09-01")) - birth_date) / 365.25, ppg = pts / g)
  d$prior_ppg <- potential_ppg(y, d); k <- K[d$pos, , drop = FALSE]
  hist <- ifelse(d$g_h > 0, d$g_h / (d$g_h + k[, "k2"]) * coalesce(d$ppg_h, 0) + k[, "k2"] / (d$g_h + k[, "k2"]) * d$prior_ppg, d$prior_ppg)
  d$cppg <- d$g / (d$g + k[, "k1"]) * d$ppg + k[, "k1"] / (d$g + k[, "k1"]) * hist
  nx <- seas %>% filter(season == y + 1) %>% transmute(player_id, g_next = g, ppg_next = pts / g)
  d %>% left_join(nx, by = "player_id") %>% mutate(g_next = coalesce(g_next, 0L), played_next = as.integer(g_next >= 1))
}
SE <- bind_rows(lapply(2009:2024, season_end)) %>% filter(!is.na(age))   # outcomes through 2025 (complete seasons)
cat("season-end rows", nrow(SE), "\n")
age_ns <- function(a) ns(a, knots = c(25, 28, 31), Boundary.knots = c(21, 38))
B <- "cppg + age_ns(age) + factor(pmin(exp, 3))"
PROD <- list(live = paste("ppg_next ~", B, "+ lpick:I(exp <= 2)"))
PROD$cppg_sq   <- paste(PROD$live, "+ I(cppg^2)")
PROD$cppg_x_age <- paste(PROD$live, "+ cppg:age")
PROD$cppg_x_exp <- paste(PROD$live, "+ cppg:factor(pmin(exp, 3))")
PROD$cppg_ns   <- paste("ppg_next ~ ns(cppg, 3) + age_ns(age) + factor(pmin(exp, 3)) + lpick:I(exp <= 2)")
PROD$all       <- paste(PROD$live, "+ I(cppg^2) + cppg:age + cppg:factor(pmin(exp, 3))")
ACT <- list(live = paste("played_next ~", B, "+ lpick"))
ACT$cppg_sq <- paste(ACT$live, "+ I(cppg^2)"); ACT$cppg_x_age <- paste(ACT$live, "+ cppg:age"); ACT$lpick_x_exp <- paste(ACT$live, "+ lpick:factor(pmin(exp, 3))")
ACT$all <- paste(ACT$live, "+ I(cppg^2) + cppg:age + lpick:factor(pmin(exp, 3))")
TESTS <- 2014:2024
res <- list()
for (ps in POSITIONS) for (ty in TESTS) {
  tr <- SE %>% filter(pos == ps, season <= ty - 1); te <- SE %>% filter(pos == ps, season == ty)
  trp <- tr %>% filter(g_next >= 4); tep <- te %>% filter(g_next >= 4)
  for (nm in names(PROD)) { f <- lm(as.formula(PROD[[nm]]), data = trp, weights = g_next); e <- predict(f, tep) - tep$ppg_next
    res[[length(res) + 1]] <- data.frame(part = "prod (next-season PPG)", pos = ps, season = ty, variant = nm, n = nrow(tep), sse = sum(tep$g_next * e^2), w = sum(tep$g_next)) }
  for (nm in names(ACT)) { f <- suppressWarnings(glm(as.formula(ACT[[nm]]), data = tr, family = binomial)); q <- pmin(pmax(predict(f, te, type = "response"), 1e-6), 1 - 1e-6)
    res[[length(res) + 1]] <- data.frame(part = "act (still playing)", pos = ps, season = ty, variant = nm, n = nrow(te), sse = -sum(te$played_next * log(q) + (1 - te$played_next) * log(1 - q)), w = nrow(te)) }
}
# draft-capital prior (dv_10 potential_fit): test season yr, train on the 10 seasons before
for (ps in POSITIONS) for (yr in 2015:2025) { tr <- pot_tr(yr) %>% filter(pos == ps)
  te <- seasP %>% filter(season == yr, g >= 1, pos == ps) %>% inner_join(p, by = "player_id") %>%
    mutate(exp = pmin(pmax(season - coalesce(rookie_season, season), 0), 4), lpick = log(coalesce(draft_pick, 262)), ppg = pts / g)
  for (nm in names(pot_form)) { f <- lm(pot_form[[nm]], data = tr, weights = g); e <- predict(f, te) - te$ppg
    res[[length(res) + 1]] <- data.frame(part = "prior (draft-capital PPG)", pos = ps, season = yr, variant = nm, n = nrow(te), sse = sum(te$g * e^2), w = sum(te$g)) } }
R <- bind_rows(res); saveRDS(R, "tv_results.rds")
S <- R %>% group_by(part, pos, variant) %>% summarise(metric = ifelse(first(part) == "act (still playing)", sum(sse) / sum(w), sqrt(sum(sse) / sum(w))), n = sum(n), .groups = "drop") %>%
  group_by(part, pos) %>% mutate(base = metric[variant %in% c("live", "base")], pct_vs_live = round(100 * (metric / base - 1), 2)) %>% ungroup()
# seasons better than live
SB <- R %>% group_by(part, pos, season) %>% mutate(b = sse[variant %in% c("live", "base")]) %>% group_by(part, pos, variant) %>% summarise(seasons_better = sum(sse < b), seasons = n(), .groups = "drop")
S <- S %>% left_join(SB, by = c("part", "pos", "variant")); write.csv(S, "tv_summary.csv", row.names = FALSE)
print(as.data.frame(S %>% mutate(metric = round(metric, 4)) %>% select(-base)), row.names = FALSE)
