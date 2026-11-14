# =============================================================================
# Track Record, step 1 (FABLE Review finding 7): freeze today's predictions for the 2024, 2025 and 2026 classes.
# These classes were never used to choose a model, cut-off or constant, so they are the true holdout.
#   frozen/<date>_predraft_2024_2026.csv   pre-draft (college-only) probabilities, score, grade, Value (100k scale)
#   frozen/<date>_postdraft_2024_2026.csv  post-draft probabilities, score, grade, Value
#     both with the pick-only benchmark probabilities (logistic on log pick, fit on 2010-2023 drafted players, per position
#     and tier) and the NFL result so far (best season finish and tier in years 1-3, complete seasons only)
#   market/<date>_market_check.csv         this week's Market Check: our dynasty rank vs Dynasty Daddy (superflex), gaps
#   MANIFEST.txt                           SHA-256 of every frozen file; the scoring scripts refuse a file whose hash changed
# Never overwrite a frozen file: a new freeze gets a new date. Reads model outputs only.
#   usage: Rscript tr_01_freeze.R  (from this folder; FREEZE_DATE env overrides the date)
# =============================================================================
suppressMessages({ library(dplyr); library(digest) })
D8 <- Sys.getenv("FREEZE_DATE", format(Sys.Date(), "%Y-%m-%d")); dir.create("frozen", showWarnings = FALSE); dir.create("market", showWarnings = FALSE)
PRE <- "../Football2_PreDraft"; POST <- "../Football2_PostDraft"; DYN <- "../Football2_Dynasty"
source("tr_common.R")
TIERS <- list(QB = c(8, 16, 24), RB = c(8, 16, 24), WR = c(12, 24, 36), TE = c(6, 12, 18))

# pick-only benchmark: P(top) / P(top two) / P(any tier) ~ log(pick), per position, drafted 2010-2023 with complete outcomes
hist <- read.csv(file.path(POST, "pd_post_player_grades.csv"), stringsAsFactors = FALSE) %>% filter(class <= 2023, !is.na(nfl_tier), !is.na(pick))
pick_only <- function(d) bind_rows(lapply(split(d, d$position), function(x) { h <- hist %>% filter(position == x$position[1])
  for (k in 1:3) { m <- glm(I(nfl_tier <= k) ~ log(pick), binomial, data = h); x[[c("pk_top", "pk_top2", "pk_any")[k]]] <- round(predict(m, x, type = "response"), 4) }; x }))
vals <- read.csv(file.path(DYN, "dv_rookie_board_values.csv"), stringsAsFactors = FALSE)
res <- nfl_results(TIERS)                                    # tr_common.R: best finish / tier in years 1-3 from complete seasons

pre <- read.csv(file.path(PRE, "pd_player_grades.csv"), stringsAsFactors = FALSE) %>% filter(status == "drafted", class %in% 2024:2026) %>%
  left_join(vals %>% filter(board == "pre") %>% distinct(position, class, name, college, .keep_all = TRUE) %>% select(position, class, name, college, value_100k),
            by = c("position", "class", "name", "college")) %>%
  transmute(board = "pre-draft", position, class, name, college, round, pick, p_top, p_top2, p_any, score, grade, value_100k) %>% pick_only() %>%
  left_join(res, by = c("class", "pick")) %>% add_tier(TIERS)
post <- read.csv(file.path(POST, "pd_post_player_grades.csv"), stringsAsFactors = FALSE) %>% filter(class %in% 2024:2026) %>%
  left_join(vals %>% filter(board == "post") %>% distinct(position, class, pick, .keep_all = TRUE) %>% select(position, class, pick, value_100k), by = c("position", "class", "pick")) %>%
  transmute(board = "post-draft", position, class, name, college, round, pick, p_top, p_top2, p_any, score = post_score, grade = post_grade, value_100k) %>% pick_only() %>%
  left_join(res, by = c("class", "pick")) %>% add_tier(TIERS)
files <- c(file.path("frozen", paste0(D8, "_predraft_2024_2026.csv")), file.path("frozen", paste0(D8, "_postdraft_2024_2026.csv")))
for (f in files) if (file.exists(f)) stop("frozen file already exists, refusing to overwrite: ", f)
write.csv(pre %>% mutate(frozen_on = D8), files[1], row.names = FALSE); write.csv(post %>% mutate(frozen_on = D8), files[2], row.names = FALSE)

# Market Check log: the published dynasty board (live folder) vs the Dynasty Daddy snapshot the page compares against
nkey <- function(x) { x <- iconv(x, to = "ASCII//TRANSLIT"); x <- tolower(gsub("[.'’-]", "", x)); x <- gsub("\\b(jr|sr|ii|iii|iv|v)\\b", "", x); gsub("[^a-z]", "", x) }
js <- sub(";\\s*$", "", sub("^window.DD = ", "", paste(readLines("../ProspectActuary/value-research/data/dd.js", warn = FALSE), collapse = "")))
J <- jsonlite::fromJSON(js); dd <- J$dynasty
dd <- tibble(key = dd[, 1], pos = dd[, 2], dd_value = as.numeric(dd[, 4])) %>% arrange(desc(dd_value)) %>% mutate(dd_rank = row_number())
ours <- read.csv(file.path(DYN, "dv_v4_board.csv"), stringsAsFactors = FALSE) %>% mutate(key = paste0(nkey(name), tolower(pos)))
ids <- read.csv(file.path(DYN, "dv_ros_2026_board.csv"), stringsAsFactors = FALSE) %>% transmute(key = paste0(nkey(name), tolower(pos)), player_id)   # the dynasty board file has no ids
mk <- inner_join(ours %>% select(key, name, pos, team, age, our_rank = rank, our_value = value_100k), dd %>% select(key, dd_rank, dd_value), by = "key") %>%
  filter(our_rank <= 150 | dd_rank <= 150) %>% mutate(gap = dd_rank - our_rank, logged_on = D8, dd_snapshot = J$asof,
  log_week = max(subset(readRDS(file.path(DYN, "nfl_weekly_2026.rds")), season_type == "REG")$week),   # stats through this week when logged
  player_id = ids$player_id[match(key, ids$key)]) %>% arrange(desc(abs(gap))) %>% select(-key)
mf <- file.path("market", paste0(D8, "_market_check.csv")); if (file.exists(mf)) stop("market log exists: ", mf); write.csv(mk, mf, row.names = FALSE)
files <- c(files, mf)
man <- if (file.exists("MANIFEST.txt")) readLines("MANIFEST.txt") else c("# SHA-256 of every frozen Track Record file. Never edit a listed file; freeze again under a new date.")
writeLines(c(man, sprintf("%s  %s  frozen %s", sapply(files, function(f) digest(file = f, algo = "sha256")), files, D8)), "MANIFEST.txt")
cat("froze", nrow(pre), "pre-draft and", nrow(post), "post-draft rows (2024-2026) and", nrow(mk), "Market Check rows; results through season", max(res$through, na.rm = TRUE), "\n")
print(post %>% group_by(class) %>% summarise(n = n(), seasons = max(seasons_seen), any_tier_so_far = sum(tier_so_far <= 3, na.rm = TRUE), .groups = "drop"))
