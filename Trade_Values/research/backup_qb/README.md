# Backup QB values (research, 2026-11-24)

Research only. Nothing here changes the live trade values or the site. Report with every chart and table:
https://claude.ai/artifact/M1h5RGzxeiZFTRwNNNzGk7

Kyle's ask (2026-11-23/24): QBs tagged Backup get 0 redraft value; injured starters on IR keep redraft value with at
least 4 fewer games (model 4, adjust later); for future value, keep young consistently good backups and backups with
high draft capital and few snaps. Fit the chance a backup becomes a starter within 1-2 years, multiply by the value of
starting, backtest, compare models (ATPA workflow). Also check Drake Maye's Backup tag.

## Scripts (Python 3: pandas, scikit-learn, statsmodels, xgboost, shap, rdata, matplotlib)

| Script | What it does | Outputs |
|---|---|---|
| `bq_01_build.py RAW` | One row per QB-season 2002-2026: starts, PPG, PPG in starts, QB24 line, backup flag, career features, outcomes (starter in y+1 / y+1..y+2, realized 5-season future value) | `bq_qb_seasons.csv`, `bq_rep_line.csv` |
| `bq_02_start_models.py` | P(backup becomes a starter within 2 years): base rates, 7 models, time split + leave-one-season-out + longer history, bootstrap, coefficients, permutation importance, SHAP, PDP/ICE | `bq_02_log.txt`, `bq_02_metrics.csv`, `bq_02_m1/m2_coefficients.csv`, `bq_02_test_predictions.csv`, `figs/eda_*`, `figs/model_roc_calibration.png`, `figs/varimp_permutation.png`, `figs/shap_summary_gbm.png`, `figs/pdp_ice.png` |
| `bq_03_value_backtest.py` | Future value = P(start) x value of starting (V1-V5) vs the live model's point-in-time snapshots, 2016-2020 backups; 2026 Backup-tagged QBs | `bq_03_log.txt`, `bq_03_value_backtest.csv`, `bq_03_test_rows.csv`, `bq_03_backups_2026.csv`, `figs/value_backtest.png` |
| `bq_04_redraft_rules.py RAW` | Rule A (Backup = 0) and rule B (IR starters: team games left - 4) on 2016-2025 snapshots | `bq_04_log.txt`, `bq_04_rule_a_backup_zero.csv`, `bq_04_rule_b_ir_starters.csv`, `figs/ir_starters_games.png`, `figs/backup_ros_realized.png` |

`RAW` holds nflverse files (open data), downloaded from `https://github.com/nflverse/nflverse-data/releases/download/`:
`player_stats/player_stats.parquet` (saved as `ps_all_old.parquet`), `stats_player/stats_player_week_{2025,2026}.parquet`
(`ps_2025/2026.parquet`), `rosters/roster_{2002..2026}.parquet` (`ros_YYYY.parquet`), `draft_picks/draft_picks.parquet`,
`players/players.parquet`, `depth_charts/depth_charts_2026.parquet`, `injuries/injuries_2026.parquet`,
`weekly_rosters/roster_weekly_2026.parquet`; plus `games.csv` from `https://raw.githubusercontent.com/nflverse/nfldata/master/data/games.csv`
(starting QB ids). Run order: bq_01, bq_02, bq_03, bq_04. bq_03 and bq_04 read `../../history/snapshots/hv_*.rds`.

## Definitions

- Scoring half PPR, 4-pt pass TD, no first-down bonus (the reference QB scoring). QB24 line = 24th-best season PPG among
  QBs with 5+ games.
- Backup season = started fewer than half his team's games, did not start the team's first game, on a roster at season
  end (not CUT / practice squad / FA / retired). Starts = nflverse listed starting QB.
- Spot-start PPG (credible) = points over the QB24 line in his starts / (starts + 3).
- Realized future value = sum over the next 5 seasons of (1/1.15)^h x max(games x (PPG - QB24 line), 0), same target
  shape as dv_11.

## Results (details and charts in the report)

1. **Maye:** ESPN chart flipped him QB1 -> QB3 on 2026-11-22 during NE's bye; active, no injury status, listed week 12
   starter. Data glitch. Guard idea: a QB who started his team's last game, is active and has no injury status stays depth 1.
2. **Starter chance:** 707 backup seasons 2012-2023, 10.6% start within 2 years. Kyle's five-factor logistic regression:
   test 2020-2023 AUC 0.836, Brier skill 14.9%; no model beat it with a bootstrap interval excluding 0. Starts and
   credible spot-start PPG are the strongest terms; age and years in league correlate 0.97 (read together: entering
   young matters); draft pick weak once starts are in.
3. **Future value (2016-2020 backups):** hurdle V2 (M1 chance x gamma-GLM value if starting) RMSE 36.6 vs live 39.8
   (bootstrap -3.2 [-6.2, 0.0]); total 0.94 of realized vs live 0.67. Young (<=25) picks 1-64: live 0.29, V2 0.51.
   Veterans 30+: live 1.07, V2 0.76. Tweedie GLM rejected (explodes), Tweedie GBM too low.
4. **Rule A:** Backup = 0 raises redraft RMSE only from 7.54 to 7.85 (2,974 snapshot rows); ~10% of backups produce
   value after takeovers nobody can foresee.
5. **Rule B:** IR starters 2022-2025 played 0.8 of 6.7 games left; rule says 2.9, live 1.7. Return rate 71% with 11+
   games left, ~22% with 7 or fewer. Rule x 0.59 has the lowest value RMSE in 2022-2025 (7.99 vs live 8.66).
