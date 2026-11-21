# Interaction, squared-term and correlation research (2026-11-20)

Question (Kyle): do any of our models need correlation handling, interaction terms or squared terms?
Inspired by the ATPA pairs plot (`pairs(auto)`). **Research only: nothing live was changed.**
Full write-up with every chart: https://claude.ai/artifact/NsvDr1nxQ78NeP47kMdmcw

## Answer

| Model | Verdict | Holdout effect |
| --- | --- | --- |
| Pre-draft QB, RB, TE (elastic net) | Don't add x² / interactions | up to 10% worse log loss, none better |
| Pre-draft WR (live 5-input GLM) | Don't add | 0-3% worse (LOCO), 4-15% worse (rolling) |
| Post-draft QB, RB, WR, TE | Don't add | small, sign flips between holdouts; TE ~1.3% better, too small |
| Trade values: still playing next season (dv_11) | One-step gain, but no gain at the value level (see below) | -0.4% to -2.4% log loss one season ahead |
| Trade values: next-season PPG, draft-capital prior | Don't add | within 1% |
| Collinearity (all models) | No fix needed for prediction | explain grouped inputs together |

Why so little: random forests and XGBoost (which find interactions and curves on their own) already lost to the
elastic net in the pre-draft comparison, and the trade value models already use splines for age and draft pick.

## What was checked

- **Holdout tests** (`ix_post.R`, `ix_pre.R`, engine `ix_engine.R`): each model refit with five add-ons
  (x² on 2 key inputs, x² on every input, key input × others, all pairwise products, all of it). Same tables,
  in-fold prep and holdouts as the live scripts: leave-one-class-out 2010-2023 and strict rolling origin
  (train on classes ≤ Y-3, Y = 2016-2023). Added inputs standardized on the training fold before squaring.
  Paired bootstrap (1,000 player resamples) for intervals. Results: `*_summary.csv`, `all_rookie_summaries.csv`.
  - The live post-draft model is an ordinal elastic net (ordinalNet); these tests use three elastic-net logistics
    (one per tier cut, as pd_20 does). Base and add-on versions use the same method.
- **Collinearity** (`ix_diag.R`): correlation heatmaps and VIF. Pre-draft QB VIF reaches 171,593 because adjusted
  yards per attempt is built from YPA, TD rate and INT rate. Elastic net spreads the weight; for explaining, use
  SHAP / PDP and describe groups (e.g. "receiving volume") rather than single coefficients.
- **Curvature** (`ix_diag.R`, `ix_extra.R`): logistic GAM smooth vs straight line per input. 2 of 133 checks
  curved (post-draft WR log pick, pre-draft RB carries); x² didn't help either on holdout.
- **Interactions in trees** (`ix_diag.R`, `ix_extra.R`): Friedman H on a random forest, top 6 inputs. Most pairs
  0.05-0.15; the only pairs above 0.2 are the same stat measured twice (final vs best season), largely an artifact
  of correlated inputs (2-D PDPs fill in impossible combinations). All draft-pick pairs H < 0.09.
- **Trade values** (`ix_tv.R`): rebuilds the dv_11 season-end table; rolling by season 2014-2024. `tv_summary.csv`.

## Follow-up 1: still-playing fix at the value level (`actx_value_backtest/`)

Added to dv_11's still-playing glm (and the QB depth version): credible PPG², credible PPG × age,
draft pick × years in league. `run_actx.R` patches dv_11 in memory (the file is not changed) and runs the
week-9 snapshot backtest (2016-2020, 5 seasons); `cmp_actx.R` compares. The live run reproduces the PC's
`dv_v4_backtest.csv` exactly.

| | Live | With terms |
| --- | --- | --- |
| Spearman, predicted vs actual 5-season value (all) | 0.699 | 0.700 |
| Actual / predicted total, QB | 0.917 | 0.877 (worse) |
| Actual / predicted total, RB | 1.110 | 1.087 (better) |
| Actual / predicted total, WR | 1.015 | 0.998 |
| 5-season "still playing" log loss QB / RB / WR / TE | .464 / .572 / .563 / .582 | .478 / .581 / .557 / .577 |

The one-season gain does not carry through the 5-season compounding: ranking is unchanged, QB and RB survival
gets slightly worse, WR and TE slightly better. On the 2026 board the top 200 move a median 3.6%: rookies and
young QBs rise (Mendoza +30%, Dart +15%), veteran and backup QBs fall (Winston -29%, Rodgers -24%).
`actx_board_compare.csv`, charts `actx_board_change.png`, `actx_survival_5yr.png`.

## Follow-up 2: 3-year points models vs tier-hit models (`ix_points.R`, `ix_points_eval.R`)

Same holdout players. Hit model = elastic-net P(top) + P(top two) + P(any tier) (the grade score). Points models:
elastic net on 3-year points, on log(1 + points), each with and without all pairwise interactions.
`points_vs_hits.csv`, charts `12_points_vs_hits_rho.png`, `13_points_vs_hits_metrics.png`.

- **Pre-draft: the log-points model ranks players by actual 3-year points better than the hit model** for WR
  (Spearman +0.024 LOCO / +0.064 rolling, intervals above 0) and TE (+0.069 / +0.084, above 0); RB and QB +0.01 to
  +0.03 (borderline). Its tier AUCs are about equal or slightly better.
- Interactions only help raw points because points are skewed and multiplicative; on the log scale they add
  little or nothing.
- **Post-draft: no clear difference** (draft pick dominates both).
- Model parity: a points-based pre-draft score would need a post-draft and mixed counterpart before going live.
