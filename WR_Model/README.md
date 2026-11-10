# Rookie WR Model

Predicts how drafted rookie wide receivers turn out for fantasy football (PPR) over their
first three NFL seasons. It also looks for "hidden talent": players who outperform their
draft slot.

- **Data window:** draft classes 2010-2026. The 2010-2023 classes have complete 3-year
  outcomes and are the training data (445 WRs). The 2024-2026 classes are projected.
- **Sources:** nflreadr (draft picks, combine, players, weekly stats, snap counts) and
  cfbfastR / College Football Data (college player stats, recruiting).

## What it predicts

| Target | Definition |
|---|---|
| `total_ppr_3yr` | Regular-season PPR points in NFL years 1-3 |
| `hit_3yr` | Any top-24 WR PPR season in years 1-3 |
| `finish_sum_3yr` | Sum of season-end WR finishes in years 1-3, each capped at 100 (3 = best, 300 = never top-100) |
| Tier ladder | P(WR1 = top 12), P(WR2+ = top 24), P(WR3+ = top 36) for best finish in years 1-3 |
| Year-2 breakout | After the rookie season: P(WR2+ / WR3+) and PPR in years 2-3 |

Each target is modeled three ways:

- **pick-only:** draft position alone (the baseline)
- **pre-draft:** college production, breakout age, age, combine and recruiting
- **post-draft:** the pre-draft inputs plus draft pick and landing spot

## How to run

1. Put your College Football Data API key in `~/.Renviron` as `CFBD_API_KEY=...`.
2. Install the packages: `nflreadr`, `cfbfastR`, `dplyr`, `tidyr`, `stringr`, `ggplot2`,
   `glmnet`, `ranger`, `pROC`, `MASS` and `ordinalNet`.
3. Run each script with `Rscript`, from this folder, in this order:

| Order | Script | What it does |
|---|---|---|
| 1 | `wr_phase1_data_build.R` | Pulls and caches raw data into `cache/` (the first run takes ~30 min), matches WRs to their college careers, runs the validation checks |
| 2 | `wr_phase2_targets_features.R` | Builds the targets and features, writes `wr_model_table.rds` |
| 3 | `wr_phase3_model.R` | PPR and hit models, leave-one-class-out; projections. Run `Rscript wr_phase3_model.R rolling` for the rolling-origin check |
| 4 | `wr_phase4_value_score.R` | Value score: college model vs draft slot |
| 5 | `wr_phase5_finish_score.R` | Finish-score model. `Rscript wr_phase5_finish_score.R 60` runs the cap-60 sensitivity |
| 5b | `wr_phase5b_finish_hurdle.R` | Two-step (hurdle) finish-score model |
| 6 | `wr_phase6_tier_ladder.R` | WR1/WR2/WR3 tier ladder (penalized ordinal logit) and Day-3 hidden-talent back-test |
| 7 | `wr_phase7_year2_breakout.R` | Year-2 breakout model built from rookie usage and snap counts |
| 8 | `wr_phase8_year3.R` | Year-3 model built from year-1 and year-2 usage |
| 9 | `wr_phase9_udfa.R` | Adds undrafted WRs to the draft-time and year-2 models |
| 10 | `wr_phase10_cfbd_usage.R` | Tests college usage share and PPA (expected points added) as pre-draft features |
| - | `wr_summary_lists.R` | Year 1 prospects and Year 2 / Year 3 buy and sell lists (`wr_summary_lists.csv`) |

Phases 7-10 read `cache/snap_counts_raw.rds`, `cache/cfbd_usage_raw.rds` and
`cache/cfbd_ppa_raw.rds`. Phase 10 pulls the last two with `cfbd_player_usage` and
`cfbd_metrics_ppa_players_season` (seasons 2013-2025).

Hand-fixed college matches go in `manual_matches.csv` (`pfr_player_id,athlete_id`). The
`cache/` folder is not committed; it rebuilds when you run Phase 1.

**Validation:** every preprocessing step (imputation, missing flags, combine-drill PCA) is
fit inside each training fold. The main test is *strict rolling origin*: each test class is
scored using only classes whose outcomes were already known at the time. That means classes
up to Y - 3 for the draft-time models, and up to Y - 2 for the year-2 model.
Leave-one-class-out results are reported as well.

## Results

### Draft-time models: rolling origin, test classes 2016-2023 (n = 256)

| Target / metric | Pick-only | Post-draft elastic net | Pre-draft elastic net |
|---|---|---|---|
| 3-yr PPR: Spearman / R² | 0.624 / 0.340 | 0.613 / 0.322 | 0.397 / 0.104 |
| Hit (top-24): AUC / Brier | 0.829 / 0.111 | 0.752 / 0.117 | 0.651 / 0.131 |
| Finish score: within-class Spearman / RMSE | 0.581 / 67.2 | 0.560 / 68.1 | 0.327 / 77.5 |
| Finish score, hurdle (two-step): within-class Spearman / RMSE | 0.581 / 67.1 | 0.549 / 69.1 | 0.305 / 78.0 |
| Tier ladder: RPS / AUC WR2+ | 0.1084 / 0.826 | 0.1131 / 0.787 | 0.1310 / 0.655 |

Bootstrap checks (rolling origin, 2000 draws, seed 2026):

- **3-yr PPR:** post-draft minus pick-only RMSE = +2.48, 95% CI [-2.48, +7.58]
- **Hit model:** post-draft minus pick-only Brier = +0.0055, 95% CI [-0.0054, +0.0166]
- **Finish score:** post-draft minus pick-only RMSE = +0.90, 95% CI [-0.80, +2.64]
- **Tier ladder:** post-draft minus pick-only RPS = +0.0047, 95% CI [-0.0025, +0.0121]

**Finding:** once you know the draft pick, college and combine data add nothing measurable.
Before the draft, the college-only model has real but modest signal: Spearman about 0.4 for
3-year PPR.

### Value score: Day-3 back-test

Value score = pre-draft projection minus pick-only projection. Among Day-3 picks
(rounds 4-7), the top tercile beat its draft slot by more than the bottom tercile:

- by the PPR gap: +49.3 PPR over 3 years, 95% CI [-6.8, +103.4]
- by the rank gap: +55.9, 95% CI [-5.3, +114.6]

It is borderline, and there is no signal in rounds 1-3. In the tier-ladder back-test,
ranking Day-3 WRs by the college "hidden" score found fewer WR3+ hits than simply taking
the earliest Day-3 picks: 5 vs 9 in the top 10 per class.

### Year-2 breakout: rolling origin, test classes 2016-2023 (n = 218)

| Model | AUC WR3+ | Brier WR3+ | AUC WR2+ | Spearman PPR yrs 2-3 | RMSE PPR |
|---|---|---|---|---|---|
| Pick-only | 0.813 | 0.152 | 0.787 | 0.550 | 144.1 |
| Pick + rookie fantasy points | 0.912 | 0.109 | 0.923 | 0.732 | 106.0 |
| Full rookie-usage elastic net | 0.913 | 0.105 | 0.915 | 0.709 | 106.6 |

**Finding:** rookie-season production is the strongest signal found anywhere in this
project.

- **Against pick-only:** the usage model is significantly better (Brier WR3+ -0.048, 95% CI
  [-0.077, -0.019]).
- **Against rookie points alone:** it ties (Brier WR3+ -0.004, 95% CI [-0.014, +0.005]).
- **Day-3 stars:** after their rookie seasons, Hill, Renfrow, Mooney, Gabe Davis, St. Brown,
  Doubs and Nacua all ranked in their class's top 5 Day-3 WRs.

### Year-3 model: rolling origin, test classes 2016-2023 (n = 235)

The rolling rule here trains on classes up to Y - 1.

| Model | AUC WR3+ | Brier WR3+ | AUC WR2+ | Spearman yr-3 PPR | RMSE |
|---|---|---|---|---|---|
| Pick-only | 0.793 | 0.117 | 0.777 | 0.491 | 83.5 |
| Pick + year-2 PPR | 0.916 | 0.087 | 0.903 | 0.774 | 59.4 |
| Pick + year-1 + year-2 PPR | 0.928 | 0.078 | 0.922 | 0.773 | 57.4 |
| Usage elastic net | 0.905 | 0.078 | 0.906 | 0.770 | 57.4 |

- **Against pick + year-1 + year-2 PPR:** the usage model ties (Brier WR3+ -0.001, 95% CI
  [-0.010, +0.007]).
- **Breakouts:** 15 players outside the top 36 in year 2 reached WR3+ in year 3. The usage
  model and the points-only baselines each caught 12 of them in each class's top 5,
  including Kupp, Deebo Samuel, Nico Collins and Drake London.

### Undrafted WRs (Phase 9)

- **Data:** 360 undrafted WRs who played at least one NFL game, rookie seasons 2010-2025.
  76.1% were matched to college stats.
- **Hits:** 8 reached WR3+ in years 1-3: Victor Cruz, Josh Gordon, Robbie Chosen,
  Allen Hurns, Tyrell Williams, Jakobi Meyers, Willie Snead and Rod Streater.
- **Effect on the models:** including them changes no conclusion. The pre-draft model
  still ranks undrafted hits low (Chosen 19th of 52, Meyers 29th of 51). After one
  season, rookie production finds them.

### College usage / PPA features (Phase 10)

- **Rolling origin, with minus without:** RMSE PPR -1.5, 95% CI [-8.7, +5.6]; Brier hit
  +0.0095, 95% CI [+0.002, +0.019]. That is no gain, and slightly worse on the hit model.
- **Leave-one-class-out (2015-23):** within ±0.01.
- **Day-3 stars:** their ranks did not improve.
- **Why it's limited:** the features exist only for the 2014+ classes.

### Buy / sell lists (`wr_summary_lists.csv`)

| List | Players |
|---|---|
| Year 1 prospects (2026) | Carnell Tate, Jordyn Tyson, KC Concepcion, Makai Lemon. Day-3 stashes: Barion Brown, Kevin Coleman, Elijah Sarratt, Skyler Bell, Deion Burks, Malik Benson |
| Year 2 buys (2025 class) | Elic Ayomanor, Chimere Dike, Pat Bryant, Jack Bech, Tre Harris |
| Year 2 sells (2025 class) | Jayden Higgins (soft; TD-dependent), Luther Burden (soft), Tez Johnson. Travis Hunter flagged as a two-way player |
| Year 3 buys (2024 class) | Adonai Mitchell, Malik Nabers (injury discount), Brian Thomas, Ladd McConkey, Marvin Harrison Jr., Xavier Worthy |
| Year 3 sells (2024 class) | Troy Franklin (models disagree; late-season snaps fell to 46%), Rome Odunze (soft) |
| Undrafted stash | Jalen Coker (2024): P(WR3+ in yrs 2-3) 0.13 |

### 2026 class, top projections (post-draft model)

| Player | Pick | Projected 3-yr PPR | P(top-24 season) |
|---|---|---|---|
| Carnell Tate | 4 | 594 | 80% |
| Jordyn Tyson | 8 | 537 | 71% |
| KC Concepcion | 24 | 400 | 44% |
| Makai Lemon | 20 | 392 | 44% |

**Day-3 stash list for 2026** (largest positive value gaps): Barion Brown (pick 190),
Kevin Coleman (177), Elijah Sarratt (115), Skyler Bell (125), Deion Burks (254).

**2025 buy-low** (year-2 model): Elic Ayomanor (pick 136). He played 81% of snaps with an
18% target share but finished only WR54. His P(WR3+ in 2026-27) is 0.50, against 0.26 from
rookie points alone.

## Files

| Kind | Files |
|---|---|
| Boards | `wr_projections_2024_2026.csv`, `wr_value_board_2024_2026.csv`, `wr_finish_board_2024_2026.csv`, `wr_finish_hurdle_board_2024_2026.csv`, `wr_tier_board_2024_2026.csv`, `wr_year2_breakout_board.csv`, `wr_year3_board.csv`, `wr_udfa_board.csv`, `wr_pre_draft_usage_board_2024_2026.csv`, `wr_summary_lists.csv` |
| Metrics | `phase*_cv_metrics.csv`, `phase3_rolling_vs_loco_metrics.csv` |
| Out-of-fold predictions | `phase*_oof_predictions.csv` |
| Back-tests | `phase4_backtest_players.csv`, `phase6_hidden_talent_backtest.csv`, `phase7_hidden_talent_backtest.csv` |
| Data | `wr_base.rds`, `wr_college_seasons.rds`, `wr_model_table.rds`, `wr_feature_dictionary.csv`, `unmatched_wrs.csv`, `suspicious_matches.csv` |
| Plots | `plot_p2_*.png`, `plot_p3_*.png` |
| Logs | `phase*_run_log*.txt` |

Known data caveats:

- The college data source has almost no player stats before 2008, so the classes start at
  2010.
- 27 drafted WRs have no college match. They are imputed and flagged with `college_matched = 0`.
- Travis Hunter's college receiving stats understate him because he also played defense.
