# Mixed draft model research (2026-11-17)

Question (Kyle): how did drafted players do when their pre-draft grade was A+, A or A- but
their post-draft grade fell below A-? Then: backtest a correction for them.

Python (pandas, statsmodels, rdata), run from `../..` (the repo root) in this order:
`an.py` (join grades to NFL outcomes), `sum.py`, `m.py`, `m2.py`, `m3.py` (faller analysis),
`bt.py`, `bt2.py`, `bt3.py` (leave-one-class-out backtest of blend variants), `bt4.py`
(2024-2026 fallers), `live.py` (LOCO check of the form used in `../pd_11_mixed_model.R`).
Intermediate pickles are written next to the scripts.

Results (2010-2023):

| Group | n | Any-tier hit | PPG yrs 1-3 |
|---|---|---|---|
| A range pre and post | 82 | 76% | 12.1 |
| Fell out of A after the draft | 75 | 40% (model said ~25%) | 8.4 |
| Rose into A after the draft | 78 | 59% | 10.5 |
| Below A- in both | 814 | 15% | 5.0 |

Backtest (`backtest_metrics.csv`): a flat odds bump for pre-A fallers was best (log loss
-13, 95% CI -28.6 to +0.1, 9 of 14 classes better). The 2+ step version was weaker, and a
bump scaled by the size of the drop was worse. The live form (offset logistic on the model's
own probabilities, `live.py`) gave log loss -9.3 (CI -23.9 to +4.4), 10 of 14 classes
better, fallers 25% -> 41% vs 40% actual.

Files: `fell_out_of_A_players.csv` (all 90 fallers 2010-2026), `backtest_faller_regrades.csv`,
`fallers_2024_2026_blend.csv`, `backtest_metrics.csv`.
