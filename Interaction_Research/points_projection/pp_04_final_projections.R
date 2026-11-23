# Projected 3-year PPR points for every board row (display only; research, nothing live).
#  past classes (2010-2023): the out-of-class (LOCO) projection from the backtest, so the board shows what the model would have said
#  2024-2027: a final model trained on 2010-2023 (same rows, inputs and in-fold prep as the backtests; elastic net on log(1 + points))
#  post-draft: drafted 2024-2026 from the position model tables; 2027 mock rows from pd_09's model inputs (pd_post_2027_mock_inputs.csv)
#  mixed: post-draft + the faller bump on the log scale (fit on all 2010-2023 out-of-class rows), for mixed_faller rows only
# Points shown = expected 3-year PPR points: a quasi-Poisson GLM of actual points on ns(log projection, 3), fit per board and position on
# the out-of-class rows (log projection clamped to that range), so the number is calibrated in points.
REPO <- "/home/user/Football"; IX <- "/mnt/project-files/research/interactions_squared"
suppressMessages({ library(dplyr); library(tidyr); library(glmnet) })
source(file.path(IX, "ix_engine.R"))
POS4 <- c("QB", "RB", "WR", "TE")
A <- readRDS("oof_projections.rds") %>% filter(scheme == "LOCO")
suppressMessages(library(splines))
CAL <- lapply(split(A %>% filter(board == "post" | drafted == 1 | is.na(drafted) | TRUE), paste(A$board, A$pos)), function(d) {
  d$pts0 <- pmax(d$pts, 0); list(m = glm(pts0 ~ ns(lp3, 3), family = quasipoisson, data = d), r = range(d$lp3)) })
MXc <- readRDS("mixed_points_oof.rds") %>% group_by(pos) %>% group_modify(~ data.frame(bump = unname(coef(lm(I(y - lp3) ~ faller, data = .x))[2]))) %>% ungroup()
print(MXc)
nk <- function(x) gsub("[^a-z]", "", tolower(sub(" (jr|sr|ii|iii|iv)\\.?$", "", x, ignore.case = TRUE)))
# ---------- pre-draft ----------
old <- setwd(file.path(REPO, "PreDraft_Model")); suppressMessages(source("pd_common.R")); setwd(old)
pool <- readRDS(file.path(REPO, "PreDraft_Model/pd_pool.rds"))
pre <- bind_rows(lapply(POS4, function(POS) {
  D <- readRDS(file.path(IX, sprintf("pre_%s_design.rds", POS)))$D; vars <- feats_for(POS)
  p <- fit_prep(D, vars); new <- pool %>% filter(position == POS, class >= 2024)
  f <- fit_pred(apply_prep(p, D), log1p(pmax(D$pts, 0)), apply_prep(p, new), "gaussian", D$class, character(0))
  oof <- A %>% filter(model == paste0("pre_", POS)) %>% arrange(class, row)
  D <- D %>% group_by(class) %>% mutate(row = row_number()) %>% ungroup() %>% left_join(oof %>% select(class, row, lp3), by = c("class", "row"))
  bind_rows(D %>% transmute(position = POS, class, name, p_team, nfl_college, lp3, src = "out-of-class"),
            new %>% transmute(position = POS, class, name, p_team, nfl_college, lp3 = f$p, src = "final model (2010-2023)")) }))
# ---------- post-draft ----------
src <- readLines(file.path(REPO, "PostDraft_Model/pd_20_pick_penalty_experiment.R"))
i <- grep("^load_pos <- function", src); j <- grep("^# ---------- elastic-net variants", src) - 1
s <- paste(src[i:j], collapse = "\n")
s <- sub("train <- tbl %>%", "full <- tbl; train <- tbl %>%", s, fixed = TRUE)
s <- sub("train <- e$load_table() %>%", "full <- e$load_table(); train <- full %>%", s, fixed = TRUE)
s <- sub("list(train = train, prep = prep)", "list(train = train, prep = prep, full = full)", s, fixed = TRUE)
select <- dplyr::select; eval(parse(text = s))
POS_DIR <- c(QB = file.path(REPO, "QB_Model"), RB = file.path(REPO, "RB_Model"), WR = file.path(REPO, "WR_Model"), TE = file.path(REPO, "TE_Model"))
MI <- read.csv(file.path(REPO, "PostDraft_Model/pd_post_2027_mock_inputs.csv"), stringsAsFactors = FALSE) %>%
  pivot_wider(id_cols = c(position, pick, name), names_from = input, values_from = value)
post <- bind_rows(lapply(POS4, function(POS) { L <- load_pos(POS)
  D <- readRDS(file.path(IX, sprintf("post_%s_design.rds", POS)))$D
  P <- L$prep(D, L$full %>% filter(draft_season >= 2024)); new <- L$full %>% filter(draft_season >= 2024)
  m <- MI %>% filter(position == POS); Xm <- matrix(0, nrow(m), ncol(P$Xtr), dimnames = list(NULL, colnames(P$Xtr)))
  miss <- setdiff(colnames(P$Xtr), names(m)); for (cc in intersect(colnames(P$Xtr), names(m))) Xm[, cc] <- as.numeric(m[[cc]])
  cat(POS, "post: train", nrow(D), "new drafted", nrow(new), "mock", nrow(m), " mock columns missing:", paste(miss, collapse = ","), "\n")
  y <- log1p(pmax(D$pts, 0))
  f <- fit_pred(P$Xtr, y, rbind(P$Xte, Xm), "gaussian", D$class, "log_pick")
  oof <- A %>% filter(model == paste0("post_", POS))
  bind_rows(oof %>% transmute(position = POS, class, pick, lp3, src = "out-of-class"),
            data.frame(position = POS, class = new$draft_season, pick = new$pick, lp3 = f$p[seq_len(nrow(new))], src = "final model (2010-2023)"),
            data.frame(position = POS, class = 2027L, pick = m$pick, mock_name = m$name, lp3 = f$p[nrow(new) + seq_len(nrow(m))], src = "final model, mock pick")) }))
# ---------- attach to the grade files ----------
pts_of <- function(lp, b, p) { out <- rep(NA_real_, length(lp))
  for (key in unique(paste(b, p))) { i <- which(paste(b, p) == key & !is.na(lp)); C <- CAL[[key]]
    out[i] <- predict(C$m, data.frame(lp3 = pmin(pmax(lp[i], C$r[1]), C$r[2])), type = "response") }
  round(out) }
gr <- read.csv(file.path(REPO, "PreDraft_Model/pd_player_grades.csv"), stringsAsFactors = FALSE, na.strings = "")
pre_k <- pre %>% mutate(k = paste(position, class, nk(name))) %>% distinct(k, .keep_all = TRUE)
gpre <- gr %>% mutate(k = paste(position, class, nk(name))) %>% left_join(pre_k %>% select(k, lp3, src), by = "k") %>%
  mutate(proj_pts_3yr = pts_of(lp3, "pre", position))
cat("pre-draft board rows", nrow(gpre), " with projection:", sum(!is.na(gpre$lp3)), "\n"); print(gpre %>% group_by(class >= 2024) %>% summarise(cover = mean(!is.na(lp3))))
po <- read.csv(file.path(REPO, "PostDraft_Model/pd_post_player_grades.csv"), stringsAsFactors = FALSE, na.strings = "")
gpost <- po %>% left_join(post %>% filter(is.na(mock_name)) %>% distinct(position, class, pick, .keep_all = TRUE) %>% select(position, class, pick, lp3, src), by = c("position", "class", "pick")) %>%
  mutate(bump = MXc$bump[match(position, MXc$pos)], proj_pts_3yr_post = pts_of(lp3, "post", position),
         proj_pts_3yr_mixed = pts_of(lp3 + ifelse(coalesce(mixed_faller, 0L) == 1, bump, 0), "post", position))
cat("post-draft rows", nrow(gpost), " with projection:", sum(!is.na(gpost$lp3)), "\n")
mk <- read.csv(file.path(REPO, "PostDraft_Model/pd_post_2027_mock_grades.csv"), stringsAsFactors = FALSE, na.strings = "")
gmk <- mk %>% left_join(post %>% filter(!is.na(mock_name)) %>% select(position, pick, board_name = mock_name, lp3), by = c("position", "pick", "board_name")) %>%
  mutate(bump = MXc$bump[match(position, MXc$pos)], proj_pts_3yr_post = pts_of(lp3, "post", position),
         proj_pts_3yr_mixed = pts_of(lp3 + ifelse(coalesce(mixed_faller, 0L) == 1, bump, 0), "post", position))
cat("mock rows", nrow(gmk), " with projection:", sum(!is.na(gmk$lp3)), "\n")
write.csv(gpre %>% select(position, class, name, college, status, pick, grade, score, proj_pts_3yr, nfl_ppr_pts, proj_source = src), "proj_points_predraft.csv", row.names = FALSE, na = "")
write.csv(gpost %>% select(position, class, name, college, pick, pre_grade, post_grade, mixed_faller, proj_pts_3yr_post, proj_pts_3yr_mixed, nfl_ppr_pts, proj_source = src), "proj_points_postdraft.csv", row.names = FALSE, na = "")
write.csv(gmk %>% select(position, pick, name, board_name, post_grade, mixed_faller, proj_pts_3yr_post, proj_pts_3yr_mixed), "proj_points_2027_mock.csv", row.names = FALSE, na = "")
# calibration check of the displayed number on past classes
cal <- bind_rows(gpre %>% filter(class <= 2023, !is.na(nfl_ppr_pts), !is.na(proj_pts_3yr), status == "drafted") %>% transmute(board = "pre (drafted)", position, p = proj_pts_3yr, a = nfl_ppr_pts),
                 gpost %>% filter(class <= 2023, !is.na(nfl_ppr_pts), !is.na(proj_pts_3yr_mixed)) %>% transmute(board = "post (mixed)", position, p = proj_pts_3yr_mixed, a = nfl_ppr_pts)) %>%
  group_by(board, position) %>% summarise(n = n(), mean_proj = mean(p), mean_actual = mean(a), rho = cor(p, a, method = "spearman"), .groups = "drop")
print(as.data.frame(cal), digits = 3); write.csv(cal, "proj_points_calibration.csv", row.names = FALSE)
print(gpre %>% filter(class == 2027) %>% arrange(desc(proj_pts_3yr)) %>% select(position, name, college, grade, proj_pts_3yr) %>% head(15))
print(gmk %>% arrange(pick) %>% select(pick, position, name, post_grade, proj_pts_3yr_post, proj_pts_3yr_mixed) %>% head(15))
