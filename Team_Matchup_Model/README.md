# Team matchup model: projecting team fantasy points from offense and opponent defense

Research and backtest only (nothing on the site uses it yet). Write-up: https://claude.ai/artifact/7qkYEDDyJsjw25gQfRksnA

**Question:** can a team's weekly fantasy points (Total, Passing, Rushing, Receiving, QB, RB, WR, TE) be projected from
its offense's points and the opponent defense's points allowed, using only data available before kickoff?

**Answer:** modestly. Multiplicative Bühlmann credibility (league avg x credibility-weighted offense relativity x
credibility-weighted defense relativity) explains about 9% of weekly variance on Total (RMSE 22.6 vs 23.9 for league
average; MAE 17.9 on a mean of 83.4). The predictable ceiling, from a crossed random-effects variance decomposition,
is only 15-24% by split. GLM (log-link Poisson ridge, refit weekly) and mixed model (BLUP) tie credibility; LightGBM
is 1-2 R² points behind on every split. Naive baselines (team season-to-date average, offense + defense - league)
are worse than league average.

Scoring: full PPR, 4-pt passing TD, regular season. Tuning 2017-2022, test 2023 through week 10 of 2026.

## Run order (Python: pandas, scikit-learn, statsmodels, lightgbm, shap)

1. `build.py [path/to/prospect-actuary]` – team-game table from `data/teams/{season}.json` -> games.pkl
2. `feats.py` – point-in-time offense / defense averages (season-to-date with last-season decay, last 3) -> feats.pkl
3. `varcomp.py` – Bühlmann k (offense, defense) and crossed random-effects variance components -> varcomp.json
4. `models.py <targets...>` – baselines, credibility, weekly-refit GLM and mixed model (run per target in parallel,
   with OMP_NUM_THREADS=1; then merge preds_stat_*.pkl to preds_stat.pkl as in the thread) -> tune.json
5. `gbm.py` – LightGBM, retrained before each season on prior seasons only
6. `evaluate.py` – RMSE / MAE / R² per split and model -> results.csv, eval_out.txt
7. `interp.py` – SHAP importance (shap_importance.json, shap_tot.png), PDP + ICE (pdp_tot.png)

Model codes in results.csv: league, std (team season-to-date), naive (off + def - league), credB (pure Bühlmann k),
cred (tuned k), mixed, glm, gbm, blend (GLM/GBM average).
