# Rookie-year targets: year-1 PPR points (regular season) and year-1 positional finish, from the nflverse weekly cache.
suppressMessages(library(dplyr))
UP <- Sys.getenv("PC_DATA", "../..")   # folder holding Football2/cache (on the PC: Documents/R Studio)
w <- readRDS(file.path(UP, "Football2/cache/nfl_weekly_raw.rds")) %>% filter(season_type == "REG")
w$position[w$position == "FB"] <- "RB"
s <- w %>% filter(position %in% c("QB", "RB", "WR", "TE")) %>% group_by(player_id, season) %>%
  summarise(pos = names(which.max(table(position))), pts = sum(coalesce(fantasy_points_ppr, 0)), .groups = "drop") %>%
  group_by(season, pos) %>% mutate(finish = rank(-pts, ties.method = "min")) %>% ungroup()
saveRDS(s, "season_finish.rds"); cat("seasons", range(s$season), "rows", nrow(s), "\n")
