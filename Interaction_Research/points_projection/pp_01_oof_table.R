# One table of out-of-class projections per drafted player (post-draft pool) and per pre-draft pool player:
# 3-year hit score, 3-year log points, year-1 hit score, year-1 log points (LOCO and rolling), from the research runs in ../interactions_squared.
suppressMessages({ library(dplyr); library(tidyr) })
IX <- "../interactions_squared"
one <- function(nm) {
  D <- readRDS(file.path(IX, sprintf("%s_design.rds", nm)))$D
  D <- D %>% group_by(class) %>% mutate(row = row_number()) %>% ungroup()
  R <- readRDS(file.path(IX, sprintf("%s_results.rds", nm)))$pred %>% filter(variant == "base") %>% transmute(scheme, class, row, hit3 = p1 + p2 + p3, p1, p2, p3)
  L <- readRDS(file.path(IX, sprintf("%s_logpts.rds", nm))) %>% filter(variant == "base") %>% transmute(scheme, class, row, lp3 = lpts_hat)
  K <- readRDS(file.path(IX, sprintf("%s_rookie.rds", nm))) %>% transmute(scheme, class, row, hit1 = hit_score, lp1 = logpts, r_pts)
  keep <- intersect(c("gsis_id", "pick", "age_at_draft", "pts", "tier", "name", "pfr_player_name", "player", "drafted"), names(D))
  R %>% left_join(L, by = c("scheme", "class", "row")) %>% left_join(K, by = c("scheme", "class", "row")) %>%
    left_join(D %>% select(class, row, all_of(keep)), by = c("class", "row")) %>%
    mutate(model = nm, board = sub("_.*", "", nm), pos = sub(".*_", "", nm))
}
A <- bind_rows(lapply(c(outer(c("post", "pre"), c("QB", "RB", "WR", "TE"), paste, sep = "_")), one))
saveRDS(A, "oof_projections.rds")
print(A %>% count(model, scheme))
