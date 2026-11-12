# =============================================================================
# Pre-Draft (college-only) Rookie Model -- shared settings and helpers
#
# No draft capital and no combine: every feature is something you could know
# from college box scores and recruiting before a player declares.
# =============================================================================
suppressMessages({ library(dplyr); library(tidyr); library(stringr) })
select <- dplyr::select
mycols <- c("#E69F00", "#56B4E9", "#009E73", "#F0E442", "#0072B2", "#D55E00", "#CC79A7")

POSITIONS <- c("QB", "RB", "WR", "TE")
# Kyle's tier cutoffs (per position): QB and RB 8/16/24, WR 12/24/36, TE 6/12/18 (TE changed from 8/16/24 on 2026-11-12)
TIERS <- list(QB = c(8, 16, 24), RB = c(8, 16, 24), WR = c(12, 24, 36), TE = c(6, 12, 18))
tier_labels <- function(pos) paste0(pos, TIERS[[pos]])
TRAIN_CLASSES <- 2010:2023       # three complete NFL seasons by 2025
ROLL_TESTS    <- 2016:2023       # strict rolling origin: train on classes <= Y - 3
# folder layout: Kyle's PC (Football2, Football2_QB, ...) or the GitHub repo (WR_Model, QB_Model, ...)
POS_DIR <- if (dir.exists("../WR_Model")) c(QB = "../QB_Model", RB = "../RB_Model", WR = "../WR_Model", TE = "../TE_Model") else
  c(QB = "../Football2_QB", RB = "../Football2_RB", WR = "../Football2", TE = "../Football2_TE")
SHARED <- file.path(POS_DIR[["WR"]], "cache")

# per-position college features (no combine, no draft info)
FEATS <- list(
  common = c("yrs_since_hs", "recruit_rating", "college_seasons", "power5", "transferred", "early",
             "final_short", "recruit_missing", "ever_breakout"),
  QB = c("p_att", "p_comp_pct", "p_ypa", "p_aya", "p_td_rate", "p_int_rate", "p_pass_share", "p_rush_yds",
         "p_rush_td", "best_aya", "career_att", "career_rush_yds", "starter_seasons", "breakout_yrs"),
  RB = c("p_car", "p_rush_yds", "p_ypc", "p_rush_td", "p_rec", "p_rec_yds", "p_car_share", "p_scrim_share",
         "p_td_share", "p_rec_share", "best_scrim_share", "career_rush_yds", "career_rec", "featured_seasons",
         "breakout_yrs"),
  WR = c("p_rec", "p_rec_yds", "p_rec_td", "p_ypr", "p_rec_share", "p_dominator", "p_ypta", "best_dominator",
         "career_rec_yds", "career_rush_yds", "featured_seasons", "breakout_yrs"),
  TE = c("p_rec", "p_rec_yds", "p_rec_td", "p_ypr", "p_rec_share", "p_dominator", "p_ypta", "best_dominator",
         "career_rec_yds", "featured_seasons", "breakout_yrs"))
feats_for <- function(pos) c(FEATS$common, FEATS[[pos]])

# --- leakage-safe preprocessing: medians and missing flags fit on training rows only ---
fit_prep <- function(d, vars) {
  med <- sapply(vars, function(v) median(as.numeric(d[[v]]), na.rm = TRUE)); med[is.na(med)] <- 0
  flag <- vars[sapply(vars, function(v) mean(is.na(d[[v]])) > 0.01)]
  list(vars = vars, med = med, flag = flag)
}
apply_prep <- function(p, d) {
  cols <- list()
  for (v in p$vars) {
    x <- as.numeric(d[[v]])
    if (v %in% p$flag) cols[[paste0("na_", v)]] <- as.integer(is.na(x))
    x[is.na(x)] <- p$med[v]; cols[[v]] <- x
  }
  as.matrix(as.data.frame(cols))
}

aucf  <- function(y, p) if (length(unique(y)) < 2 || sd(p) == 0) NA else
  as.numeric(pROC::auc(pROC::roc(y, p, quiet = TRUE, direction = "<")))
brier <- function(p, y) mean((p - y)^2)
logloss <- function(p, y) { p <- pmin(pmax(p, 1e-6), 1 - 1e-6); -mean(y * log(p) + (1 - y) * log(1 - p)) }
boot_ci <- function(f, n, B = 2000, seed = 2026) {
  set.seed(seed); pt <- f(seq_len(n)); dd <- replicate(B, f(sample.int(n, replace = TRUE)))
  c(est = pt, lo = unname(quantile(dd, .025, na.rm = TRUE)), hi = unname(quantile(dd, .975, na.rm = TRUE)))
}
check <- function(label, ok, detail = "") { cat(sprintf("[%s] %s %s\n", ifelse(ok, "PASS", "FAIL"), label, detail)); invisible(ok) }

norm_name <- function(x) {
  x %>% str_to_lower() %>% str_replace_all("[.']", "") %>%
    str_replace_all("\\s+(jr|sr|ii|iii|iv|v)\\.?$", "") %>% str_replace_all("[^a-z ]", "") %>% str_squish()
}
school_alias <- c(
  "central florida" = "ucf", "southern california" = "usc", "louisiana state" = "lsu",
  "mississippi" = "ole miss", "southern methodist" = "smu", "texas christian" = "tcu",
  "brigham young" = "byu", "nevadalas vegas" = "unlv", "alabamabirmingham" = "uab",
  "texasel paso" = "utep", "texassan antonio" = "utsa", "miami fl" = "miami",
  "north carolina state" = "nc state", "louisianamonroe" = "ul monroe", "louisianalafayette" = "louisiana",
  "middle tennessee state" = "middle tennessee", "florida international" = "fiu",
  "massachusetts" = "umass", "connecticut" = "uconn", "app state" = "appalachian state")
norm_school <- function(x) {
  s <- x %>% str_to_lower() %>% str_replace_all("\\bst\\.?$", "state") %>%
    str_replace_all("\\bst\\.?\\s", "state ") %>% str_replace_all("[^a-z ]", "") %>% str_squish()
  ifelse(s %in% names(school_alias), unname(school_alias[s]), s)
}

# letter grade from a historical percentile
grade_of <- function(pct) cut(pct, c(-Inf, .1, .25, .4, .6, .75, .9, Inf),
                              labels = c("F", "D", "C-", "C", "B", "A-", "A"), right = FALSE) %>% as.character()
