# replacement-line gate limits for the weekly refresh: default-league lines at week 9 of 2016-2025, +-2 PPG
NO_WRITE <- TRUE; sink("NUL"); source("dv_10_ros_value.R"); sink()
L <- bv %>% distinct(season, pos, rep_ppg) %>% group_by(pos) %>% summarise(hist_min = min(rep_ppg), hist_max = max(rep_ppg), lo = floor(min(rep_ppg) - 2), hi = ceiling(max(rep_ppg) + 2))
print(L); write.csv(L, "../Weekly_Refresh_dev/rf_gate_limits.csv", row.names = FALSE)
