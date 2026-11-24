# cppg_state: last published credible PPG, for the steadiness EWMA (dv_10, 2026-11-24)

dv_10 smooths credible PPG week to week: cppg_t = 0.7 x new_t + 0.3 x published_(t-1). It reads the previous week from
`cppg_state/cppg_state_<season>_<ppr>_<te>_<ptd>_<fdQB-fdRB-fdWR-fdTE>.csv` in the model folder (one file per scoring
variant, 20 in all, since dv_13 runs dv_10 once per scoring group) and writes this week's unrounded rows back
(columns week, player_id, cppg, cppg_rep). A same-week rerun replaces that week's rows.

These 20 files are the **seed**: 2026 week 11 as published on 2026-11-24 (old method, unsmoothed). They come from a
faithful rerun of the week-11 board with the patched scripts: credible PPG identical to the live board, 0 difference. With
them in `Football2_Dynasty/cppg_state/`, the 12-01 refresh (week 12) smooths against week 11 instead of publishing unsmoothed.

The live copy lives on the PC in `Football2_Dynasty/cppg_state/` and the weekly refresh keeps it current. This folder is
only the seed and is not updated weekly.
