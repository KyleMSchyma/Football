# Prospect-model prior for credible PPG (research, 2026-11-18)

Question (Kyle): should veterans' credible PPG start from the rookie models' expected PPG instead of the
draft-pick regression prior? **Answer: no.** Every version moved prediction error by under 1% and none
beat the live pick prior overall. Nothing live was changed.

| Script | What it does |
| --- | --- |
| pp_00_common.R | data, prospect-model tier odds keyed by class + pick, prior regressions, snapshot + credibility functions |
| pp_01_backtest.R | all versions: in-season test (k1/k2 refit leave-one-season-out) and next-season test (live dv_11 aging model, rolling) |
| pp_02_report.R | RMSE tables by position and NFL year, paired player bootstrap, value-ranking Spearman |
| pp_03_prior_only.R | each prior's own correlation with later PPG; weight the prior carries at week 9 |
| pp_04_2026_movers.R | 2026 credible PPG, pick prior vs mixed prior, years 1-3 |

Run from `Trade_Values/`: `Rscript prospect_prior/pp_01_backtest.R` then 02, 03, 04. Needs
`prospect_prior/data/` = nfl_weekly_raw.rds, players_raw.rds (Football2/cache) and nfl_weekly_2026.rds
(Football2_Dynasty), or set `PP_DATA`. Outputs in `out/` (CSVs and logs; .rds ignored).
Scoring: full PPR. The role layer (QB depth, status) is not applied; it does not touch the prior.
