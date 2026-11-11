# Football Prospect Models: Technical Reference

This is the complete technical record of Kyle's fantasy-football prospect models. It is
written so that another analyst, or another AI, can understand, reproduce and extend
them without reading the code. Every number below comes from the run logs, CSVs, READMEs
or saved model objects in this repository (or from Kyle's PC folders that the repository
mirrors). Nothing is estimated or rounded beyond what the logs print.

A shorter, plain-English companion is in [`MODELS_GUIDE.md`](MODELS_GUIDE.md).

---

## 0. Map of the work

| Family | Folder (repo / Kyle's PC) | Question it answers | Prediction point |
|---|---|---|---|
| Rookie WR model | `WR_Model/` / `Football2` | How will a drafted WR do in NFL years 1-3? | Draft night, end of year 1, end of year 2 |
| Rookie QB model | `QB_Model/` / `Football2_QB` | Same for QBs | Same |
| Rookie RB model | `RB_Model/` / `Football2_RB` | Same for RBs | Same |
| Rookie TE model | `TE_Model/` / `Football2_TE` | Same for TEs | Same |
| Pre-draft (college-only) model | `PreDraft_Model/` / `Football2_PreDraft` | Before anyone is drafted, how likely is each college player to have a tier season, and how strong is each class? | Before the draft (no pick, no combine) |
| All-time pre-draft player grades | `PreDraft_Model/pd_06_player_grades.R` | Letter grade A+..F for every drafted QB/RB/WR/TE 2010-2026 plus top 2027 prospects, from the college-only model | Before the draft |
| All-time post-draft player grades | `PostDraft_Model/` / `Football2_PostDraft` | Letter grade A+..F for every drafted QB/RB/WR/TE 2010-2026 from the post-draft position models, next to the pre-draft grade | After the draft |

Everything is on the `main` branch of the repo.

Out of scope: the ATPA coursework prototypes in `ATPA/Module/Rookie_Model` and
`ATPA/Module/Fantasy_Football` on Kyle's PC (weekly-points models with a neural network
and stacking). They are separate course exercises, not part of this pipeline.

**Software.** R 4.6.1. Packages: nflreadr, cfbfastR, dplyr, tidyr, stringr, ggplot2,
glmnet, ranger, pROC, MASS (polr), ordinalNet, xgboost (pre-draft only), lme4 (conference
test only). All seeds are 2026.

---

## 1. Data sources

| Source | Package / call | What it provides | Coverage notes |
|---|---|---|---|
| NFL draft picks | nflreadr `load_draft_picks` | Class, round, pick, team, pfr id, college | 2010-2026 classes |
| NFL combine | nflreadr `load_combine` | Height, weight, 40, vertical, broad jump, 3-cone, shuttle, bench | Drill skips are common and kept as flags |
| NFL players table | nflreadr `load_players` | Birth dates, gsis ids, UDFA lists | No 2012 rookie-season UDFAs in the table |
| NFL weekly stats | nflreadr `load_player_stats` (cached `nfl_weekly_raw.rds`) | Regular-season box scores and `fantasy_points_ppr` | Through the 2025 season |
| Snap counts | nflreadr `load_snap_counts` | Offensive snap share by game | Start in 2013 (not 2012) |
| College player stats | cfbfastR / College Football Data (cfbd) | Season passing, rushing, receiving by player | Usable from 2008, so classes start 2010; FCS players only logged in games vs FBS teams before 2022 |
| College team stats | cfbd | Team totals for market shares | Same |
| College usage and PPA | `cfbd_player_usage`, `cfbd_metrics_ppa_players_season` | Share of team plays, predicted points added per play | Seasons 2013-2025 only |
| Recruiting | cfbfastR recruiting | 247 composite rating (0-1 scale) and stars | About half of rows lack a cfbd athlete id; matched by name + committed school |
| 2026 college season | cfbd, pulled 2026-11-10 | In-progress season (~10 games) | Counting stats pro-rated to 12 games (scale 1.20-1.33) for the pre-draft model |

Raw pulls are cached under `cache/` (never committed). The cfbd API key lives only in
`~/.Renviron`.

### 1.1 Fantasy scoring

All targets use nflverse `fantasy_points_ppr`, regular season only. For RB, WR and TE this
is full PPR. For QBs it is standard scoring with 4-point passing TDs (plus the rare
reception). Season ranks are computed among all players at the position in that season.

### 1.2 College matching (Phase 1 of each rookie model)

Each drafted player is matched to his cfbd college career: pass 1 by normalized name and
school, pass 2 by last name + school, then hand fixes in `manual_matches.csv`. Checks
(ATPA 2.5-style data validation): one row per player, one athlete id per player, no
college season on or after the draft year, shares within [0, 1], age at draft within
20-27.

| Position | Drafted 2010-2026 | Training classes 2010-2023 | College match rate |
|---|---|---|---|
| WR | 547 | 445 | 95.1% (520 of 547) |
| QB | 198 | 163 | (11 QBs flagged `college_thin`: FCS or missing) |
| RB | 354 (fullbacks excluded) | 298 | 96.3% |
| TE | 252 | 202 | 95.2% |

---

## 2. The rookie models (WR, QB, RB, TE)

All four follow one design, built first for WRs and then adapted.

### 2.1 Population, targets and censoring

One row per drafted player, classes 2010-2026. A season with no games counts as 0
points, which is a real bust and not missing data. Three-year targets exist only for
classes with three complete NFL seasons (2010-2023); 2024-2026 are projected.

| Target | WR | QB | RB | TE |
|---|---|---|---|---|
| 3-yr points | `total_ppr_3yr` | `total_pts_3yr` | `total_pts_3yr` | `total_pts_3yr` |
| Hit flags (any season in yrs 1-3) | `hit_3yr` = top-24 | top-8 / 16 / 24 (also top-12) | top-8 / 16 / 24 | top-8 / 16 / 24 |
| Finish score | Sum of yearly WR ranks, each capped at 100 (3 best, 300 worst) | Capped at 50 (3-150) | Capped at 60 (3-180) | Capped at 60 (3-180) |
| Tier ladder (best finish yrs 1-3) | WR1 ≤12 / WR2 13-24 / WR3 25-36 / rest | QB8 / QB16 / QB24 / rest | RB8 / RB16 / RB24 / rest | TE8 / TE16 / TE24 / rest |

Kyle's tier cutoffs: QB, RB and TE use 8 / 16 / 24; WR uses 12 / 24 / 36.

Base rates in the training classes:

| Position | n | Top-tier hits | Top-two hits | Any-tier hits | Hit rate by round |
|---|---|---|---|---|---|
| WR | 445 | 39 WR1 | 68 WR2+ (top-24) | 95 WR3+ | Top-24 hit: R1 55%, R2 27%, R3 19%, R4 3%, R5 9%, R6 1%, R7 0% |
| QB | 163 | 21 top-8 | 32 top-16 | 45 top-24 | Top-24: R1 67%, R2-3 38%, R4-7 5% |
| RB | 298 | 36 top-8 | 56 top-16 | 78 top-24 | (see README) |
| TE | 202 | 22 top-8 | 42 top-16 | 55 top-24 | Top-24: every R1 TE (11 of 11), R2-3 47%, R4-7 12% |

The WR finish score has a spike: 48.3% of WRs never post a top-100 season (score 300).
Its Spearman correlation with 3-yr PPR is -0.924 (QB -0.948, RB -0.926), so it mostly
re-expresses points while rewarding consistency.

### 2.2 Features

Three feature sets per position:

- **pick-only:** `log_pick` alone (the benchmark).
- **pre-draft:** college production, breakout age, age, combine, recruiting.
- **post-draft:** pre-draft + `log_pick` + landing spot.

Log pick is used because value falls off steeply early in the draft (WR Spearman of log
pick with 3-yr PPR = -0.636; QB -0.705).

#### WR features (`wr_phase2_targets_features.R`, used in Phase 3)

| Feature | Definition |
|---|---|
| `final_dominator` | Final college season: mean of team receiving-yards share and receiving-TD share |
| `best_dominator` | Best single-season dominator |
| `final_yptpa` | Final-season receiving yards per team pass attempt |
| `breakout_age_filled` | Age on Sept 1 of the first season with dominator ≥ 0.20; if never, final age + 1 (so "never" reads as later than anyone who did) |
| `broke_out` | 1 if any season reached dominator ≥ 0.20 |
| `career_rec_yds`, `college_seasons`, `transferred` | Career totals; seasons with stats; 1 if 2+ schools |
| `early_declare` | 3 or fewer college seasons, or under 21.5 at the draft |
| `final_power5` | Final season in SEC, Big Ten, Big 12, ACC, Pac-12 or Notre Dame |
| `age_at_draft` | Decimal age on April 25 of the draft year |
| `height_in`, `weight_lb` | Combine size |
| `athletic_pc1`, `athletic_pc2` | First two principal components of forty, vertical, broad jump and speed score, fit inside each training fold |
| `miss_forty`, `miss_vertical`, `miss_broad_jump`, `combine_invited` | Skipped drills often signal something, so the flags are kept |
| `recruit_rating` | 247 composite (about half covered) |
| `college_matched` | 0 if cfbd has no record (features imputed) |
| `log_pick` (post) | log of overall pick |
| `vacated_target_share` (post) | Share of the drafting team's prior-season targets that went to players not on the team in the rookie season |
| `team_targets_prev` (post) | Drafting team's prior-season total targets |

Dropped on purpose: `final_yds_share` (Spearman 0.87 with `final_dominator` and 0.92 with
`final_yptpa`, so it is redundant).

Speed score = weight × 200 / forty⁴ (Bill Barnwell's formula).

Univariate Spearman with 3-yr PPR (WR training classes): log_pick -0.636,
breakout_age_filled -0.366, age_at_draft -0.339, career_rec_yds +0.274, recruit_rating
+0.233, best_dominator +0.197, final_yptpa +0.195, final_dominator +0.165, vacated target
share +0.111, forty -0.093, speed score +0.050.

#### QB features (`qb_common.R`)

College features come from the **primary season**: the last college season with 150+
attempts, so an injury-shortened final year is not the profile (`final_short` flags it).

- Pre-draft numeric: `age_at_draft`, `p_aya` (adjusted yards per attempt), `p_comp_pct`,
  `p_td_rate`, `p_int_rate`, `p_pass_share` (share of team pass attempts), `p_rush_yds`,
  `p_rush_td`, `best_aya`, `career_att`, `career_rush_yds`, `starter_age_filled` (age at
  first starter season, the QB analogue of breakout age), `starter_seasons`, `height_in`,
  `weight_lb`, `forty`, `recruit_rating`.
- Flags: `ever_starter`, `transferred`, `early_declare`, `p_power5`, `college_matched`,
  `combine_invited`, `miss_forty`, `final_short`, `recruit_dual` (dual-threat recruit).
- Post-draft: `log_pick`, `vacated_att_share` (share of the team's prior-season pass
  attempts thrown by players gone in the rookie season), `incumbent_pts` (prior-season
  points of the team's leading QB still on the roster).
- Tested separately: `p_ppa_pass`, `p_ppa_rush`, `p_usg_overall` (cfbd PPA and usage).
- A QB with no college season of 120+ attempts is `college_thin` (treated as missing, not
  as a bad season), because cfbd logs FCS QBs only in games against FBS teams.

Univariate Spearman with 3-yr points: log_pick -0.705, incumbent_pts -0.457, age -0.380,
forty -0.295, vacated_att_share +0.517, p_comp_pct +0.313, p_td_rate +0.297, p_ppa_pass
+0.291, best_aya +0.280.

#### RB features (`rb_common.R`)

Primary season = last season with 100+ touches (carries + receptions).

- Pre-draft numeric: `age_at_draft`, `p_rush_yds`, `p_ypc`, `p_rush_td`, `p_rec`,
  `p_rec_share`, `p_car_share`, `p_scrim_share` (share of team scrimmage yards),
  `p_td_share`, `best_scrim_share`, `career_rush_yds`, `career_rec`, `career_ypc`,
  `featured_seasons`, `breakout_age_filled` (first season with 20%+ of team scrimmage
  yards), `height_in`, `weight_lb`, `forty`, `speed_score`, `broad_jump`, `vertical`,
  `recruit_rating`.
- Flags: `ever_breakout`, `transferred`, `early_declare`, `p_power5`, `college_matched`,
  `combine_invited`, `miss_forty`, `final_short`, `recruit_apb` (all-purpose-back recruit).
- Post-draft: `log_pick`, `vacated_touch_share` (share of the team's prior-season RB
  carries + targets that left), `incumbent_pts` (prior-season PPR of the best RB still on
  the team).
- `college_thin` = no season with 60+ touches, partial team totals, or no match (42 RBs,
  e.g. Todd Gurley and LaMichael James are missing from cfbd entirely).

#### TE features (`te_common.R`)

Primary season = last season with 15+ receptions.

- Pre-draft numeric: `age_at_draft`, `p_rec`, `p_rec_yds`, `p_rec_td`, `p_ypr`,
  `p_rec_share`, `p_dominator`, `p_ypta`, `best_dominator`, `career_rec_yds`,
  `featured_seasons` (25+ catches), `breakout_age_filled` (first season with a 15%+
  dominator, lower than the WR 20% because TEs share targets with WRs), `height_in`,
  `weight_lb`, `forty`, `speed_score`, `vertical`, `broad_jump`, `cone`, `recruit_rating`.
- Flags: `ever_breakout`, `transferred`, `early_declare`, `p_power5`, `college_matched`,
  `combine_invited`, `miss_forty`, `final_short`.
- Post-draft: `log_pick`, `vacated_tgt_share`, `incumbent_pts`.
- `college_thin` = no match, no season with 3+ catches, or partial team totals (fewer than
  60 team receptions): 19 TEs.

### 2.3 Leakage-safe preprocessing (ATPA 3.7a)

Inside every training fold, and only from the training rows:

1. Median of each numeric feature.
2. A missing-value indicator `na_<feature>` for every feature that has any NA in the
   training rows.
3. Replace NA with the training median.
4. (WR only) PCA of the combine drills, centered and scaled on the training rows; the
   first two PCs become `athletic_pc1/2`.

The same fitted transform is then applied to the test rows. Nothing about the test class
enters the training fit.

### 2.4 Methods and their math

**Pick-only baseline.** Ordinary least squares `y ~ log_pick` for points and finish score
(predictions floored at 0 for points), logistic regression
`logit P(hit) = β0 + β1·log(pick)` for hit flags, and a proportional-odds model
(`MASS::polr`) on log pick for the tier ladder.

**Elastic net (the main learner; `glmnet`).** For a Gaussian target it minimizes

  (1 / 2n) Σ (yᵢ − β0 − xᵢᵀβ)² + λ [ (1 − α)/2 · ‖β‖₂² + α · ‖β‖₁ ]

and for a binary target it replaces the squared-error term with the negative mean
binomial log-likelihood, so the fitted model is a penalized logistic regression,
`P(y = 1) = 1 / (1 + exp(−(β0 + xᵀβ)))`. Settings used everywhere: α = 0.5 (equal ridge
and lasso mix, which keeps correlated college stats together while still zeroing weak
ones), glmnet's internal standardization (coefficients are reported back on the raw
scale), and λ = `lambda.min` from `cv.glmnet` with **fold ids = draft classes**, so the
penalty is tuned by leave-one-class-out inside the training data. If fewer than 4
classes are available the inner CV falls back to random 5-fold; if glmnet cannot fit
(too few positives) the prediction falls back to the training mean.

**Random forest (`ranger`).** 500 trees, `min.node.size = 10`, default mtry (√p), a
probability forest for binary targets. Used in the WR Phases 3 and 5 comparison.

**Tier ladder: penalized cumulative logit (`ordinalNet`).** With tiers j = 1 (top) .. 4
(miss),

  P(tier ≤ j | x) = 1 / (1 + exp(−(θⱼ − xᵀβ))),  j = 1, 2, 3,

with one β shared across thresholds (parallel terms, the proportional-odds assumption)
and increasing cut points θ₁ < θ₂ < θ₃. This guarantees P(top) ≤ P(top two) ≤ P(any
tier) for every player. Settings: elastic net α = 0.5, 25 λ values,
`standardize = FALSE` (inputs enter as preprocessed), λ chosen by `ordinalNetTune` with
folds = draft classes using out-of-fold log-likelihood. The WR final fits used λ index 16
(pre) and 13 (post) of 25. In Phase 10 the WR ladder is fit instead as three nested glmnet
logits (WR1, WR2+, WR3+) forced monotone, so the with/without comparison is fast and
identical in form.

**Nested binary models.** Where separate logits are fit per threshold (year-2 and year-3
models), monotonicity is imposed after prediction: P(top-16) = min(P(top-16), P(top-24))
and so on (`pmin`).

**Two-step (hurdle) finish score.**

- Step 1: logistic P(relevant). WR: any top-100 season in yrs 1-3 (51.7% of WRs). QB: any
  top-32 season. RB: any top-36 season. TE: any top-32 season (roughly a starting TE).
- Step 2: Gaussian elastic net for the finish score among relevant players only.
- Combined: E[score] = p · E[score | relevant] + (1 − p) · C, where C = 300 for WRs (the
  floor) and, for QB/RB/TE, the mean score of training players without a relevant season.
- The WR inner CV also chose between a raw and transformed step-2 target and picked
  "raw" in every fold.

### 2.5 Validation scheme

**Strict rolling origin (the headline test).** For each test class Y in 2016-2023, train
only on classes whose outcomes were already known when class Y was drafted:

| Model stage | Prediction point | Training classes for test class Y |
|---|---|---|
| Draft-time (3-yr targets) | Draft day of year Y | ≤ Y − 3 |
| Year-2 model (yrs 2-3 targets) | End of season Y | ≤ Y − 2 |
| Year-3 model (year-3 target) | End of season Y + 1 | ≤ Y − 1 |
| Year 3-4 horizon (WR) | End of season Y + 1 | ≤ Y − 2 |

WR draft-time training sizes per rolling fold: 120, 154, 189, 220, 252, 286, 314, 349 for
2016-2023. A check (`stopifnot`) asserts no fold trains on the test class or later.

**Leave-one-class-out (LOCO).** Each of the 14 classes 2010-2023 is held out in turn.
This uses future classes to predict past ones, so it is optimistic; it is reported for
comparison only.

**Metrics.**

| Metric | Formula / meaning |
|---|---|
| RMSE, MAE | √mean((ŷ − y)²), mean\|ŷ − y\| |
| R² | 1 − Σ(ŷ − y)² / Σ(y − ȳ)² |
| Spearman | Rank correlation of predicted vs actual (pooled, or within class for finish score) |
| AUC | Area under the ROC curve (pROC) |
| Brier | mean((p − y)²); lower is better |
| Log loss | −mean(y log p + (1 − y) log(1 − p)), p clipped to [1e-6, 1 − 1e-6] |
| RPS (ranked probability score) | For the ladder: mean over players of [(P̂₁ − 1{tier ≤ 1})² + (P̂₂ − 1{tier ≤ 2})² + (P̂₃ − 1{tier ≤ 3})²] / 3, using cumulative probabilities |
| Calibration | Mean predicted vs actual rate in probability bins or quintiles |

**Bootstrap comparisons.** Out-of-fold predictions from two models on the same players
are resampled with replacement (players are the unit), 2000 draws, seed 2026. The
statistic is the metric difference (model A − model B); the 95% CI is the 2.5th and
97.5th percentiles; the "share < 0" is the bootstrap probability that A is better.

**Hidden-talent back-tests.** For late picks (WR and RB Day 3 = rounds 4-7; QB rounds
2-7), each class is ranked by a score and the number of real hits in the top k per class
is counted against: ranking by earliest pick, and a random draw (expected hits).

**Model selection rule.** Within each rookie Phase 3, the best non-baseline model is the
one with the highest Spearman (regression) or lowest Brier (classification) under LOCO.
In every position the elastic net won for the post-draft set, so the boards use it.

### 2.6 Results: draft-time models (rolling origin, test classes 2016-2023)

#### WR (n = 256)

| Target / metric | Pick-only | Post-draft EN | Pre-draft EN | Post RF | Pre RF |
|---|---|---|---|---|---|
| 3-yr PPR Spearman / R² / RMSE | 0.624 / 0.340 / 181.3 | 0.613 / 0.322 / 183.8 | 0.397 / 0.104 / 211.2 | 0.567 / 0.247 / 193.6 | 0.378 / 0.083 / 213.7 |
| Top-24 hit AUC / Brier | 0.829 / 0.111 | 0.752 / 0.117 | 0.651 / 0.131 | 0.727 / 0.125 | 0.634 / 0.135 |
| Finish score within-class Spearman / RMSE | 0.581 / 67.2 | 0.560 / 68.1 | 0.327 / 77.5 | 0.495 / 72.4 | 0.306 / 78.4 |
| Hurdle finish score within-class Spearman / RMSE | 0.581 / 67.1 | 0.549 / 69.1 | 0.305 / 78.0 | - | - |
| Tier ladder RPS / AUC WR1 / WR2+ / WR3+ | 0.1084 / 0.779 / 0.826 / 0.849 | 0.1131 / 0.728 / 0.787 / 0.779 | 0.1310 / 0.587 / 0.655 / 0.660 | - | - |

LOCO (2010-2023, n = 445), for comparison: pick-only Spearman 0.630, post EN 0.639, pre EN
0.471; hit AUC 0.834 / 0.819 / 0.713.

Bootstrap (post EN − pick-only, rolling): 3-yr PPR RMSE +2.48 [−2.48, +7.58]; hit Brier
+0.0055 [−0.0054, +0.0166]; finish score RMSE +0.90 [−0.80, +2.64]; ladder RPS +0.0047
[−0.0025, +0.0121]. Pre EN − pick-only ladder RPS +0.0226 [+0.0085, +0.0389]. Two-step
post − one-step post finish-score RMSE +0.93 [−0.09, +1.86].

Calibration (LOCO, post EN hit probability): bins [0, .05] 0.039 predicted vs 0.021
actual; (.05, .15] 0.090 vs 0.075; (.15, .3] 0.211 vs 0.227; (.3, .5] 0.391 vs 0.512;
(.5, 1] 0.660 vs 0.611.

#### QB (n = 95)

| Target | Pick-only | Post EN | Pre EN |
|---|---|---|---|
| 3-yr points Spearman / RMSE | 0.667 / 205.2 | 0.556 / 228.8 | 0.369 / 275.2 |
| Top-24 AUC / Brier | 0.848 / 0.140 | 0.893 / 0.122 | 0.769 / 0.160 |
| Top-16 AUC / Brier | 0.844 / 0.112 | 0.832 / 0.118 | 0.713 / 0.139 |
| Top-8 AUC / Brier | 0.817 / 0.104 | 0.801 / 0.101 | 0.617 / 0.124 |
| Finish score Spearman (single / two-step) | 0.683 / 0.681 | 0.607 / 0.661 | 0.424 / 0.355 |
| Ladder RPS / AUC top-8 / 16 / 24 | 0.116 / 0.831 / 0.847 / 0.847 | 0.113 / 0.793 / 0.853 / 0.885 | 0.133 / 0.696 / 0.782 / 0.763 |

Bootstrap: points RMSE post − pick +23.5 [+4.8, +44.5] (post significantly worse); pre −
pick +70.0 [+27.9, +113.7]; top-24 Brier post − pick −0.017 [−0.050, +0.015]; ladder RPS
post − pick −0.0026 [−0.027, +0.022].

#### RB (n = 171)

| Target | Pick-only | Post EN | Pre EN |
|---|---|---|---|
| 3-yr PPR Spearman / RMSE | 0.679 / 191.8 | 0.640 / 196.8 | 0.387 / 233.5 |
| Top-24 AUC / Brier | 0.842 / 0.133 | 0.795 / 0.147 | 0.655 / 0.182 |
| Top-16 AUC / Brier | 0.801 / 0.128 | 0.739 / 0.135 | 0.585 / 0.161 |
| Top-8 AUC / Brier | 0.861 / 0.081 | 0.873 / 0.085 | 0.705 / 0.107 |
| Finish score Spearman | 0.638 | 0.604 | 0.362 |
| Ladder RPS / AUC RB24 | 0.113 / 0.842 | 0.121 / 0.798 | 0.149 / 0.642 |

Bootstrap: points RMSE post − pick +5.0 [−2.9, +12.7]; top-24 Brier post − pick +0.015
[+0.004, +0.025] (significantly worse); top-8 +0.004 [−0.002, +0.011]; ladder RPS post −
pick +0.008 [+0.001, +0.016] (significantly worse); two-step post − single post RMSE +2.61
[+1.33, +3.81].

#### TE (n = 113)

| Target | Pick-only | Post EN | Pre EN |
|---|---|---|---|
| 3-yr PPR Spearman / RMSE | 0.667 / 108.8 | 0.558 / 114.2 | 0.200 / 136.4 |
| Top-24 AUC / Brier | 0.866 / 0.124 | 0.816 / 0.138 | 0.698 / 0.184 |
| Top-16 AUC / Brier | 0.865 / 0.108 | 0.833 / 0.118 | 0.732 / 0.155 |
| Top-8 AUC / Brier | 0.889 / 0.070 | 0.713 / 0.079 | 0.680 / 0.082 |
| Finish score Spearman | 0.676 | 0.580 | 0.245 |
| Ladder RPS / AUC TE8 / TE24 | 0.102 / 0.887 / 0.867 | 0.111 / 0.859 / 0.821 | 0.138 / 0.751 / 0.691 |

Bootstrap: points RMSE post − pick +5.4 [−1.5, +13.2]; top-24 Brier +0.014 [−0.008, +0.036];
ladder RPS post − pick +0.009 [−0.001, +0.020]; pre − pick +0.036 [+0.016, +0.057];
two-step post − pick RMSE +3.0 [+0.3, +5.7].

**Conclusion across positions.** At the draft, draft slot carries nearly all the
predictable signal. Adding college and combine data to log pick never significantly
beats pick alone and is sometimes significantly worse (QB points, RB top-24, RB ladder).
Before the draft the college-only model has real but modest signal (WR Spearman ≈ 0.40,
QB 0.37, RB 0.39, TE 0.20).

**Why the boards still show the post-draft elastic net.** It is the best non-baseline
model under the selection rule, it ties pick-only within noise for WRs, RBs and TEs, and
it lets college profile adjust players at the same pick. The pick-only line is always
shown beside it as the honest benchmark.

### 2.7 Final draft-time coefficients (fit on all 2010-2023 classes)

These are elastic-net coefficients on the raw (unstandardized) scale, as printed in the
Phase 3 logs, sorted by absolute size. `na_*` terms are missing-value indicators. Because
inputs have different units, the size of a raw coefficient is not its importance; use
the sign and the importance lists.

**WR, pre-draft, 3-yr PPR:** intercept 927.9; recruit_rating +559.4; na_age_at_draft
−136.0; broke_out −79.3; best_dominator +68.1; college_seasons −57.8; na_recruit_rating
−57.1; na_breakout_age_filled −49.8; transferred +35.3; final_power5 +26.8; na_height_in
−23.6; breakout_age_filled −21.6; miss_forty +21.4; age_at_draft −19.9; na_weight_lb
−18.2; final_yptpa +16.0; combine_invited +12.0; athletic_pc1 +11.3; miss_vertical +4.9;
early_declare +4.0; height_in −3.5; career_rec_yds +0.057.

**WR, post-draft, 3-yr PPR:** intercept 1211.7; log_pick −116.9; na_age_at_draft −15.9;
na_recruit_rating −14.4; college_seasons −13.1; age_at_draft −10.9; breakout_age_filled
−10.2; early_declare +9.5; team_targets_prev +0.014; career_rec_yds +0.005. (A WR picked at
twice the pick number is projected about 116.9 × ln 2 ≈ 81 fewer PPR points over 3 years,
other things equal.)

**WR random-forest permutation importance (3-yr PPR):** post: log_pick 15797, breakout
age 2657, age at draft 1792, recruit rating 1472, career rec yds 1052. Pre: age at draft
3469, breakout age 3263, career rec yds 2784, recruit rating 2401, college seasons 1534.

**WR finish score (lower is better), post EN:** intercept −40.2; log_pick +41.2;
recruit_rating −19.9; na_recruit_rating +6.1; college_seasons +6.0; early_declare −5.1;
breakout_age_filled +3.5; age_at_draft +1.7; athletic_pc1 +1.6.

**QB, pre-draft, 3-yr points:** intercept 1636.3; p_td_rate +1341.8; p_comp_pct +1323.3;
forty −261.3; na_age_at_draft −123.5; age_at_draft −66.9; recruit_rating −48.0;
early_declare +42.0; na_recruit_rating +39.5; p_power5 +37.5; best_aya +14.1; weight_lb
+1.1; p_rush_yds +0.021; career_rush_yds +0.017.

**QB, post-draft, 3-yr points:** p_comp_pct +741.6; intercept 637.0; recruit_rating
−148.8; log_pick −110.9; na_incumbent_pts −30.5; p_power5 +23.7; transferred +11.2;
starter_age_filled −10.6; forty −8.3; age_at_draft −4.5; incumbent_pts −0.146; p_rush_yds
+0.057.

**QB, post-draft, top-24 (log-odds):** p_int_rate −40.08; p_comp_pct +18.18; intercept
−4.28; recruit_rating +3.85; log_pick −0.94; transferred +0.63; best_aya +0.20; p_power5
+0.23; vacated_att_share +0.12; starter_age_filled −0.29.

**RB, post-draft, 3-yr PPR:** intercept 781.8; recruit_rating −312.4; log_pick −162.4;
best_scrim_share −98.6; vacated_touch_share +54.5; transferred +49.2; early_declare +26.0;
career_ypc +11.8; p_ypc +3.8; broad_jump +3.0; p_rec +2.2.

**RB, pre-draft, 3-yr PPR:** p_td_share +289.3; na_speed_score −140.8; early_declare
+71.6; transferred +65.8; best_scrim_share −62.8; p_rec_share +60.1; combine_invited −40.0;
career_ypc +38.5; final_short −37.3; p_power5 +34.6; p_ypc +28.7; age_at_draft −23.5;
speed_score +3.6.

**RB, post-draft, top-24 (log-odds):** recruit_rating −1.87; log_pick −1.43; transferred
+0.59; early_declare +0.26; vacated_touch_share +0.25; career_ypc +0.16; p_power5 +0.16.

Note: the negative recruit_rating and best_scrim_share signs in the RB post-draft model
are conditional on log pick (highly recruited, high-share backs are already priced into
their draft slot). They are a sign the college inputs mostly add noise after the pick.

**TE, pre-draft, 3-yr PPR:** intercept 407.6; best_dominator +153.4; recruit_rating
+114.2; p_rec_share +87.3; cone −80.4; transferred −49.2; early_declare +14.6; forty −9.8;
p_ypta +9.3; age_at_draft −5.7; speed_score +2.5.

**TE, post-draft, 3-yr PPR:** intercept 1141.8; best_dominator +146.8; log_pick −95.4;
forty −75.4; cone −36.0; transferred −33.8; vacated_tgt_share +21.3; p_rec_share +16.7;
recruit_rating +10.5.

**TE, post-draft, top-24 (log-odds):** intercept 11.34; recruit_rating +4.09; log_pick
−1.60; transferred −0.87; cone −0.54; early_declare +0.32; best_dominator +0.27;
vacated_tgt_share +0.20.

### 2.8 Value score and hidden talent

- **Value score** = pre-draft prediction − pick-only prediction (WR in PPR points, QB/RB/TE
  in points and in P(top-24)). WR also uses a rank gap = within-class percentile of the
  pre-draft prediction − within-class percentile of draft slot.
- **WR back-test** (rolling 2016-2023, Day 3 only, terciles): top minus bottom tercile
  beat their slot by +49.3 PPR [−6.8, +103.4] using the value gap and +55.9 [−5.3, +114.6]
  using the rank gap. Borderline; no signal in rounds 1-3 (+38.3 [−61.9, +134.5]).
- **QB:** top minus bottom tercile +95.4 points [−21.3, +215.6].
- **RB:** −46.8 [−114.4, +20.4] (backs the college model liked did not beat their slot).
- **TE:** +14 [−36, +61].
- **Hidden-talent ladder score** (WR) = post-draft P(WR2+ or WR3+) − pick-only P. Among
  148 Day-3 WRs in the test years (9 WR3+ hits), the top 10 per class by hidden score found
  5 hits; the earliest 10 picks found 9. The known Day-3 stars ranked poorly: Tyreek Hill
  18th of 22, Hunter Renfrow 15th of 15, Puka Nacua 15th of 19.
- **RB Day 3:** 117 backs, 12 top-24 hits; top 3 per class by post hidden score caught 1,
  pre hidden 0, earliest picks 4, random 2.2.
- **TE Day 3:** 68 TEs, 8 top-24 hits; top 2 per class by hidden score caught 2-3,
  earliest picks 3, random 1.4.
- **QB rounds 2-7:** 68 QBs, 9 top-24; top 3 per class: post hidden 4, pre hidden 5,
  post P 5, earliest pick 5, random 3.3.

**College usage and PPA (tested and not adopted).** WR Phase 10, rolling, with − without:
RMSE PPR −1.5 [−8.7, +5.6]; hit Brier +0.0095 [+0.0023, +0.0187] (worse); ladder RPS
+0.0045 [−0.0006, +0.0100]. QB pre-draft hit24 Brier −0.011 [−0.021, −0.001] (LOCO within
2014-2023 only, a small gain, not carried into the main model because the features exist
only from 2013). RB −0.001 [−0.004, +0.002]; TE −0.0002 [−0.009, +0.007]. Reason they are
limited: the data exist only for 2014+ classes.

### 2.9 Year-2 model (prediction at the end of the rookie season)

**Population.** Drafted players who played as rookies (WR: classes 2013-2023 because snap
counts start in 2013, 291 training rows; QB 161; RB 296; TE as in README). Targets: best
finish in years 2-3 as tier hits (WR: WR2+ / WR3+; QB/RB/TE: top-8/16/24) and points in
years 2-3.

**Features (all known at the end of the rookie regular season).**

- WR: games, targets, receptions, yards, PPR, PPR per game, yards per target, catch
  rate, target share, air-yards share, WOPR, rookie WR finish, late-season (weeks 10+)
  target share and its trend vs weeks 1-9, average snap %, snap % over the last 6 games,
  games with 50%+ snaps, team pass attempts, plus log pick and college features.
- QB: games, starts (15+ attempts), attempts per game, YPA, ANY/A, passing EPA per
  dropback, CPOE, sack rate, TD and INT rates, rushing attempts / yards / TDs per game,
  points, points per game and per start, QB finish (capped at 50), late-season starts and
  points per game, team pass attempts.
- RB: games, carries / targets / touches per game, share of team carries and targets,
  YPC, rushing EPA per carry, yards per target, TDs per game, PPR, PPG, RB finish (cap
  60), TD share and receiving share of his points, late-season touches and PPG, snap share
  (season, last 6 games).
- TE: targets and catches per game, target share, air-yards share, WOPR, yards per target,
  receiving EPA per target, catch rate, aDOT, TD share of points, snap share (season, last
  6), late-season targets and points.
- Deliberately excluded: vacated targets entering year 2, because offseason departures
  happen after the prediction point.

**Models.** pick-only (logit / OLS on log pick); pick + rookie points
(`glm(y ~ log_pick + rookie_pts)`, the naive "he already produced" benchmark); and the
usage elastic net (α 0.5) on all features, with nested probabilities.

**Results (rolling 2016-2023).**

| Position | Model | AUC top-24* | Brier top-24* | Other |
|---|---|---|---|---|
| WR (n = 218) | Pick-only | 0.813 | 0.152 | Spearman PPR 0.550, RMSE 144.1 |
| | Pick + rookie pts | 0.912 | 0.109 | 0.732, 106.0 |
| | Usage EN | 0.913 | 0.105 | 0.709, 106.6 |
| QB (n = 94) | Pick-only | 0.857 | 0.131 | RMSE pts 166.2 |
| | Pick + rookie pts | 0.924 | 0.112 | 146.5 |
| | Usage EN | 0.955 | 0.080 | 144.2 |
| RB (n = 171) | Pick-only | 0.820 | 0.144 | RMSE pts 154.2 |
| | Pick + rookie pts | 0.862 | 0.126 | 138.5 |
| | Usage EN | 0.847 | 0.133 | 136.2 |
| TE (n = 113) | Pick-only | 0.868 | 0.115 | RMSE pts 87.9 |
| | Pick + rookie pts | 0.939 | 0.089 | 82.7 |
| | Usage EN | 0.925 | 0.103 | 83.9 |

*For WRs the column is WR3+ (top-36). WR2+ AUC: 0.787 / 0.923 / 0.915.

Bootstrap (usage − rookie points, rolling): WR Brier WR3+ −0.0043 [−0.0143, +0.0053]
(tie); QB Brier top-24 −0.033 [−0.064, −0.004] (usage significantly better); RB +0.007
[−0.004, +0.018] (tie); TE +0.014 [+0.003, +0.026] (usage significantly worse). Usage −
pick-only: WR −0.048 [−0.077, −0.019]; QB −0.052 [−0.094, −0.012]; RB points RMSE −18.0
[−27.8, −7.2].

**Final usage coefficients (top-24, log-odds) printed in the logs.**

- QB (QB2+): y1_int_rate −11.83; intercept −8.71; recruit_rating +5.87; p_comp_pct +4.98;
  log_pick −0.36; y1_starts_late +0.19; y1_cpoe +0.16; starter_age_filled −0.14;
  y1_ppg_late_starts +0.066; y1_ppg +0.066; y1_att_pg +0.049.
- RB: p_rec_share +3.82; intercept −2.86; p_scrim_share +1.31; log_pick −0.71; y1_snap_avg
  +0.68; y1_snap_last6 +0.50; y1_ypc +0.42; y1_epa_car +0.32; breakout_age_filled +0.12;
  y1_finish −0.015.
- TE: intercept 13.01; log_pick −1.26; y1_td_share_pts +0.68; y1_games +0.13; y1_finish
  −0.031; weight_lb −0.030; y1_pts +0.004.
- WR: coefficients were not printed; the board columns used are target share, air-yards
  share, snap share (season and last 6), late-season target-share trend and rookie PPR.

**Day-3 rookie finds (WR).** After their rookie seasons, Hill, Renfrow, Mooney, Gabe
Davis, St. Brown, Doubs and Nacua all ranked in their class's top 5 Day-3 WRs by the usage
model (8 of 9 Day-3 WR3+ hits in the top 5 per class; random 3.3).

### 2.10 Year-3 model (prediction at the end of year 2)

Features: year-1 and year-2 usage (as above) plus year-1 → year-2 changes (target share,
snap %, PPG; RB touches; QB EPA) and the late-season year-2 trend. Baselines: pick-only,
pick + year-2 points, pick + year-1 + year-2 points.

| Position (rolling) | Pick-only AUC / Brier | Pick + y2 pts | Pick + y1 + y2 pts | Usage EN |
|---|---|---|---|---|
| WR3+ (n = 235) | 0.793 / 0.117 | 0.916 / 0.087 | 0.928 / 0.078 | 0.905 / 0.078 |
| QB top-24 (n = 94) | 0.863 / 0.097 | 0.990 / 0.032 | 0.989 / 0.034 | 0.985 / 0.043 |
| RB top-24 (n = 171) | 0.820 / 0.118 | 0.944 / 0.084 | 0.940 / 0.085 | 0.933 / 0.092 |
| TE top-24 (n = 113) | 0.800 / 0.126 | 0.906 / 0.095 | 0.908 / 0.099 | 0.905 / 0.102 |

Year-2 points dominate at every position; the usage model ties them (e.g. WR Brier vs y1+y2
points −0.001 [−0.010, +0.007]; RB vs y2 points +0.008 [−0.001, +0.016]; TE +0.007
[−0.010, +0.022]). RB usage is slightly better at the RB8 end (AUC 0.949 vs 0.916), not
significant.

Final usage coefficients (top-24, log-odds):

- QB: y2_td_rate +4.46; y2_rush_td_pg +0.93; y2_epa_db +0.50; log_pick −0.30; y1_td_rate
  +0.27; y2_anya +0.14; p_aya +0.13; y2_starts_late +0.11.
- RB: y2_snap_last6 +1.13; log_pick −0.22; y2_tch_pg_late +0.031; y2_games +0.026;
  y2_finish −0.024; y1_tgt_pg +0.012; y2_car_pg +0.011.
- TE: y2_tgt_share +2.68; y1_tgt_share +1.67; y2_wopr +0.82; y1_snap_last6 +0.80; log_pick
  −0.39; y1_wopr +0.27; y2_rec_pg +0.076.

### 2.11 Undrafted free agents

| Position | UDFAs with an NFL game (or carry / target / attempt), rookie seasons 2010-2025 | Hits in yrs 1-3 | Effect of adding them |
|---|---|---|---|
| WR | 360 (76.1% college-matched; pick = 262 sentinel, round 8) | 8 WR3+: Victor Cruz, Josh Gordon, Robbie Chosen, Allen Hurns, Tyrell Williams, Jakobi Meyers, Willie Snead, Rod Streater | No conclusion changes; pre-draft model still ranks UDFA hits low (Chosen 19th of 52, Meyers 29th of 51) |
| QB | 38 | 0 top-24 (Kyle Allen best, QB28) | Usage AUC 0.955 → 0.958 |
| RB | 199 (183 with 3 seasons) | 8 top-24, 2 top-8 (Austin Ekeler, James Robinson); 4.4% vs 10.9% for rounds 4-7 | Year-2 usage AUC 0.847 → 0.859 |
| TE | 161 with three seasons | 7 top-24, 1 top-8 (Cameron Brate); 4.3% vs 11.6% for rounds 4-7 | Year-2 usage Brier 0.103 → 0.095 |

### 2.12 Buy / sell lists (`*_summary_lists.R`)

No new modeling; rules on the boards.

- **Year 1 prospects:** top 12 by post-draft P(hit) for the newest class, plus Day-3
  stashes = top pre-draft value gaps among rounds 4-7.
- **Year 2 buys (WR):** usage edge (P_usage − P_rookie-pts for WR3+) ≥ +0.03, or P(WR3+) ≥
  0.40 with a rookie finish worse than WR36; P ≥ 0.10. **RB/TE:** usage edge ≥ +0.05 with
  P(top-24) ≥ 0.15, or P ≥ 0.40 with a rookie finish worse than 24th; edge > −0.05.
- **Year 2 sells (WR):** rookie finish ≤ WR60 and (usage edge ≤ −0.03, or last-6 snaps
  < 50%, or falling target share, or TDs ≥ 30% of PPR). **RB/TE:** rookie finish ≤ 36 and
  edge < 0 and (edge ≤ −0.05, or last-6 snaps 5+ points below the season average, or TDs
  ≥ 35% of points).
- **Year 3 buys:** usage edge vs year-2 points ≥ +0.05 with P ≥ 0.20 (WR) / 0.15 (RB/TE), or
  rising usage (target share and snaps both up; RB touches and snaps) with P ≥ 0.25 (WR) /
  0.20 (RB/TE).
- **Year 3 sells:** year-2 finish ≤ WR48 / RB40 / TE40 and (edge ≤ −0.05, or both usage
  measures fell, or late-season trend < −0.03 / snaps 5+ points down, or TD-heavy).
- "Sell" means the usage model is less bullish than points alone; it does not mean the
  player is bad.

Current list contents are in each position README and `*_summary_lists.csv`.

---

## 3. Pre-draft (college-only) model

### 3.1 Purpose and design choices (Kyle's specification)

Grade a college class before draft capital is known. Rules: **no draft pick, no landing
spot, no combine**. Only box-score production, usage shares, age proxy and recruiting.
Use ATPA/PA techniques: model comparison, PDP/ICE, SHAP.

### 3.2 The prospect pool (`pd_01_pool_build.R`)

Every draft-eligible college player, not just drafted ones, so the model learns
P(tier hit | college profile), which includes the chance he is never drafted.

- **Class assignment:** draft year (drafted), rookie year (UDFA who played), otherwise
  last college season + 1.
- **Eligibility:** 3+ years out of high school (or linked to the NFL).
- **Production filter ("productive"):** max single-season volume ≥ QB 100 attempts, RB 50
  touches, WR 15 receptions, TE 8 receptions (or NFL-linked).
- **Pool sizes:** QB 3,953 college players → 2,806 eligible → 1,604 eligible + productive
  (191 of 191 matched drafted kept); RB 7,426 → 5,102 → 2,838 (340 of 341); WR 11,472 →
  7,932 → 4,684 (519 of 520); TE 3,969 → 2,804 → 1,752 (239 of 240).
- **Training pool (2010-2023, outcome known), as used in Phase 2:** QB 882 (hits 20 / 31 /
  44 for QB8/16/24), RB 1,618 (36 / 58 / 81), WR 2,765 (39 / 68 / 95 for WR12/24/36), TE
  997 (21 / 43 / 59). (The README lists slightly larger counts from an earlier run.)
- **Pool keeps the hitters:** QB 44 of 45 drafted QB24 hitters, RB 77 of 78, WR 91 of 95,
  TE 54 of 55.
- **Outcomes:** drafted players from the four rookie models; UDFAs rebuilt from weekly
  data and matched to college by name + school (813 UDFAs with fantasy points, 609
  matched). Non-NFL players are misses once three seasons would have passed.
- **Age proxy:** no birth dates exist for college players, so `yrs_since_hs` = class −
  high-school class year (recruiting); for unrecruited players, first season with stats −
  1 (the median gap).

### 3.3 Features (`pd_common.R`, `FEATS`)

Primary season = last season meeting the volume bar (QB 100 att, RB 50 touches, WR 15
rec, TE 15 rec), else the highest-volume season.

| Group | Features |
|---|---|
| Common | `yrs_since_hs`, `recruit_rating`, `college_seasons`, `power5`, `transferred`, `early` (≤ 3 yrs out of HS), `final_short`, `recruit_missing`, `ever_breakout` |
| QB | `p_att`, `p_comp_pct`, `p_ypa`, `p_aya`, `p_td_rate`, `p_int_rate` (rates need 50+ att), `p_pass_share`, `p_rush_yds`, `p_rush_td`, `best_aya` (150+ att seasons), `career_att`, `career_rush_yds`, `starter_seasons` (200+ att), `breakout_yrs` |
| RB | `p_car`, `p_rush_yds`, `p_ypc` (30+ car), `p_rush_td`, `p_rec`, `p_rec_yds`, `p_car_share`, `p_scrim_share`, `p_td_share`, `p_rec_share`, `best_scrim_share`, `career_rush_yds`, `career_rec`, `featured_seasons` (150+ touches), `breakout_yrs` |
| WR | `p_rec`, `p_rec_yds`, `p_rec_td`, `p_ypr` (8+ rec), `p_rec_share`, `p_dominator`, `p_ypta`, `best_dominator`, `career_rec_yds`, `career_rush_yds`, `featured_seasons` (40+ rec), `breakout_yrs` |
| TE | Same as WR without `career_rush_yds`; featured = 25+ rec |

Breakout definitions: QB pass share ≥ 50%; RB scrimmage share ≥ 20%; WR dominator ≥ 20%;
TE dominator ≥ 15%. `breakout_yrs` = college season number of the breakout, or last
season + 1 if never.

Preprocessing is the same leakage-safe median + flag scheme, except a missing flag is
created only when more than 1% of training rows are missing that feature.

### 3.4 Level-of-competition (FCS) translation

cfbd has full FCS box scores only from 2022 on. Before that, FCS players appear only in
games against FBS opponents, so the training classes hold almost no full FCS seasons and
no model can learn an FCS discount. Instead, like a minor-league translation in baseball:

- Take every player who changed teams between consecutive seasons (2022+) and landed at an
  FBS school.
- For a rate m (receiving: share of team receiving yards with 15+ rec; rushing: share of
  team rushing yards with 50+ car; passing: (yds + 20·TD − 45·INT) / att with 100+ att),
  compute r = log(m_next / m_prev).
- Factor f = exp( median r[FCS→FBS] − median r[FBS→FBS] ), capped at 1. The FBS→FBS group
  controls for "new team, one year older".

| Stat family | FCS→FBS n | FBS→FBS n | Factor |
|---|---|---|---|
| Receiving | 139 | 362 | 0.685 |
| Rushing | 62 | 206 | 0.685 |
| Passing | 27 | 107 | 0.789 |

Applied to full-coverage FCS seasons (2022+; 13,220 player-seasons): receiving and
rushing volume (rec, yds, TD; car, yds, TD) are multiplied by their factor, so shares and
yards drop while per-touch rates stay; passing yards and TDs are multiplied by 0.789, so
AY/A, Y/A and TD rate drop. G5 vs Power 5 is handled by the `power5` flag.

### 3.5 Conference as a predictor (tested in `pd_05_conference_test.R`, rejected)

Variants, each validated like Phase 2: `base` (Power 5 flag only), `tier` (+ G5 and FCS
indicators), `tier_x` (+ production × level interactions), `conf` (+ one indicator per
conference with 30+ players, shrunk by the elastic net), `cred` (ATPA 3.3 credibility:
the 5-input logistic with a random conference intercept via `lme4::glmer`, compared with
the same logistic without it, `glm5`).

Rolling mean Brier, variant − base: QB tier +0.0066 [+0.0025, +0.0120], tier_x +0.0033
[+0.0007, +0.0068], conf +0.0012 [−0.0003, +0.0029]; RB tier +0.0006 [+0.0000, +0.0012],
tier_x +0.0053 [+0.0023, +0.0092]; WR tier +0.0007 [+0.0002, +0.0013], tier_x +0.0024
[+0.0005, +0.0049]; TE tier −0.0002 [−0.0005, +0.0000]. The random-intercept SD was 0 for
QB and RB (singular fit: the data show no conference effect beyond the overall mean),
0.155 for WR and 0.599 for TE, with credibility adjustments of at most ±0.1 log-odds for WR
conferences. Conclusion: no variant helps; the base model is kept.

### 3.6 Model comparison (`pd_02_models.R`, ATPA 4.5-style)

Three binary targets per player: y1 = top tier, y2 = top two tiers, y3 = any tier. Six
candidates on the same preprocessed matrix:

| Model | Specification |
|---|---|
| `null` | Training base rate |
| `glm` | Logistic regression on 5 hand-picked inputs: QB `p_aya, p_att, yrs_since_hs, recruit_rating, power5`; RB `p_scrim_share, p_rush_yds, yrs_since_hs, recruit_rating, power5`; WR/TE `p_dominator, p_rec_yds, yrs_since_hs, recruit_rating, power5` |
| `enet` | Elastic-net logistic, α 0.5, λ by inner CV with folds = classes |
| `rf` | ranger probability forest, 500 trees, `min.node.size = 20` |
| `xgb` | xgboost, `binary:logistic`, eta 0.03, max_depth 3, min_child_weight 3, subsample 0.8, colsample_bytree 0.8; rounds by 5-fold `xgb.cv` with early stopping after 40 rounds (max 800, at least 25) |
| `ens` | Simple average of enet, rf and xgb |

Stacking with a meta-learner (ATPA 3.6) was deliberately not used: 8 rolling test classes
cannot support a second-level fit, so the equal-weight average stands in for it. Neural
networks (ATPA 3.4) were not used anywhere in these pipelines.

Probabilities are made nested after prediction: p2 = max(p2, p1), p3 = max(p3, p2).

Validation: rolling origin (test 2016-2023, train ≤ Y − 3) and LOCO. Metrics: AUC, Brier,
**Brier skill score BSS = 1 − Brier / Brier(null)**, log loss, and **gain at the top 5%**
(share of all hits captured by the top 5% of scores, a gain-chart point). **Selection
rule:** highest rolling BSS averaged over the three thresholds.

Rolling results (mean over thresholds):

| Position | enet BSS / AUC | ens | glm | rf | xgb | Chosen |
|---|---|---|---|---|---|---|
| QB (n = 515) | 0.261 / 0.908 | 0.229 / 0.892 | 0.167 / 0.869 | 0.179 / 0.861 | 0.139 / 0.870 | **enet** |
| RB (n = 973) | 0.235 / 0.905 | 0.212 / 0.896 | 0.185 / 0.876 | 0.172 / 0.873 | 0.188 / 0.869 | **enet** |
| WR (n = 1,636) | 0.124 / 0.875 | 0.118 / 0.868 | 0.128 / 0.854 | 0.106 / 0.856 | 0.069 / 0.852 | **glm** |
| TE (n = 579) | 0.124 / 0.891 | 0.123 / 0.881 | 0.062 / 0.878 | 0.077 / 0.858 | 0.095 / 0.864 | **enet** |

Chosen model, per threshold (rolling): QB8 AUC 0.883 / BSS 0.145; QB16 0.927 / 0.300; QB24
0.915 / 0.339. RB8 0.914 / 0.203; RB16 0.880 / 0.209; RB24 0.922 / 0.294. WR12 0.806 /
0.053; WR24 0.868 / 0.146; WR36 0.889 / 0.185. TE8 0.925 / 0.067; TE16 0.877 / 0.131; TE24
0.873 / 0.173.

Bootstrap (rolling): QB24 Brier enet − null −0.0168 [−0.0279, −0.0065], enet − glm −0.0045
[−0.0096, +0.0001]; RB24 enet − null −0.0146 [−0.0214, −0.0086]; WR36 glm − null −0.0064
[−0.0102, −0.0030], glm − enet +0.00003 [−0.0017, +0.0019] (a tie; the simpler model wins
the selection rule); TE24 enet − glm −0.0033 [−0.0068, −0.0002].

Why the trees lost: with 20-95 hits per position the signal is mostly monotone and
additive (more production, younger, better recruit, Power 5), which a penalized linear
logit captures with less variance. The forests and boosting chased noise; xgb had the
worst rolling BSS for WRs.

### 3.7 Final pre-draft models (refit on all 2010-2023; from the saved `pd_<pos>_models.rds`)

Coefficients are log-odds on the raw scale. `recruit_rating` is the 0-1 composite, so +1
means going from 0 to 1; a realistic spread (0.80 to 0.95) is 0.15 of that. Shares are 0-1.

**QB (elastic net).** Any tier (QB24), base rate 0.050: intercept −21.91; p_int_rate
−21.66; p_td_rate +14.00; p_comp_pct +13.37; recruit_rating +7.36; na_p_pass_share +2.75;
p_pass_share +1.62; power5 +0.80; yrs_since_hs −0.58; best_aya +0.58; recruit_missing
+0.57; college_seasons −0.36; p_ypa −0.26; transferred +0.20; early −0.13; starter_seasons
+0.057; p_rush_td −0.030; per-unit volume terms (p_att +0.0027, career_att +0.0010,
career_rush_yds +0.0006, p_rush_yds +0.0004). Top tier (QB8): p_td_rate +12.46,
p_comp_pct +12.11, yrs_since_hs −0.84, power5 +0.57, recruit_rating +0.48.

**RB (elastic net).** Any tier (RB24), base rate 0.050: intercept −8.82; na_best_scrim_share
+3.76; recruit_rating +2.45; power5 +1.57; p_td_share +1.34; final_short −1.19;
na_p_scrim_share +0.78; na_p_td_share +0.76; transferred +0.53; yrs_since_hs −0.49; p_ypc
+0.33; ever_breakout +0.17; early +0.14; p_rush_td +0.086; p_rec_yds +0.0046. Top tier
(RB8): recruit_rating +4.69, p_td_share +3.68, p_rec_share +2.69, power5 +1.07,
p_scrim_share +0.47. (The large `na_` terms identify backs whose team totals are missing in
cfbd, the same coverage gaps that hide Gurley-type players.)

**WR (logistic regression, 5 inputs).** Any tier (WR36), base rate 0.034: intercept
−10.53; recruit_rating +7.75; p_dominator +2.75; power5 +1.03; yrs_since_hs −0.77;
p_rec_yds +0.0032 per yard. Top tier (WR12): recruit_rating +9.16, p_dominator +3.85,
power5 +1.08, yrs_since_hs −0.73, p_rec_yds +0.0020. Worked reading: each extra year out
of high school multiplies the odds by e^−0.77 ≈ 0.46; 500 more primary-season receiving
yards multiplies them by e^(0.0032·500) ≈ 5.0.

**TE (elastic net).** Any tier (TE24), base rate 0.059: intercept −9.30; recruit_rating
+7.56; p_ypta +0.84; na_p_rec_share +0.57; na_p_ypr +0.55; transferred −0.48;
best_dominator +0.39; p_rec_share +0.35; final_short −0.35; yrs_since_hs −0.32;
featured_seasons +0.32; power5 +0.31; college_seasons −0.21; p_rec_td +0.089. Top tier
(TE8): p_rec_share +3.17, recruit_rating +1.47, p_ypta +0.66, early +0.44, yrs_since_hs
−0.33.

### 3.8 Interpretation (`pd_03_interpret.R`, ATPA 4.3 workflow)

- **Permutation importance:** in-sample AUC drop for the any-tier probability when one
  input (and its missing flag) is shuffled, averaged over 3 shuffles.
- **PDP + ICE:** the top three inputs on a 15-point quantile grid (5th-95th percentile);
  PDP = mean prediction, ICE = 40 random players.
- **SHAP:** for the linear chosen models the exact contribution is φⱼ = βⱼ·(xⱼ − x̄ⱼ) on
  the log-odds scale (missing flags summed into their base feature); a TreeSHAP path via
  `xgboost` `predcontrib` exists for tree models.

| Position | In-sample AUC (any tier) | Top permutation importance (AUC drop) | Top mean \|SHAP\| |
|---|---|---|---|
| QB | 0.951 | best_aya 0.034, p_comp_pct 0.023, p_pass_share 0.019, yrs_since_hs 0.009, career_rush_yds 0.008 | best_aya 0.70, p_comp_pct 0.68, yrs_since_hs 0.46, p_pass_share 0.40, power5 0.40 |
| RB | 0.938 | power5 0.030, best_scrim_share 0.022, p_rec_yds 0.017, final_short 0.012, p_rush_td 0.011 | power5 0.77, yrs_since_hs 0.40, final_short 0.40, p_rec_yds 0.38, p_rush_td 0.32 |
| WR | 0.912 | p_rec_yds 0.120, yrs_since_hs 0.027, power5 0.020, p_dominator 0.008, recruit_rating 0.007 | p_rec_yds 0.78, yrs_since_hs 0.63, power5 0.51, p_dominator 0.24, recruit_rating 0.23 |
| TE | 0.909 | recruit_rating 0.026, yrs_since_hs 0.023, p_ypta 0.012, college_seasons 0.011, career_rec_yds 0.008 | p_ypta 0.30, yrs_since_hs 0.26, featured_seasons 0.23, recruit_rating 0.22, career_rec_yds 0.17 |

### 3.9 Class grades (`pd_04_grades.R`)

- For each position and class, take the **top K prospects** by P(any tier): QB 12, RB 20,
  WR 32, TE 15 (about the number drafted per class). Using top-K rather than whole-class
  sums stops a class from looking stronger just because cfbd logged more fringe players
  (FCS coverage and the transfer portal grow the pool over time).
- E1, E2, E3 = expected top-tier, top-two and any-tier hits (sums of probabilities).
  **Tier points** = E1 + E2 + E3 (a top-tier hit counts 3, middle 2, bottom 1).
- **Depth** = expected any-tier hits from players ranked 4th or lower.
- 2010-2023 use LOCO predictions; 2024-2027 use the final model.
- **Grade** = percentile of a class's tier points among the 2010-2023 classes: A ≥ 90th,
  A− 75-90, B 60-75, C 40-60, C− 25-40, D 10-25, F < 10th (`grade_of`).
- **Overall grade:** z-score of tier points within position, averaged over the four
  positions, then graded by percentile.
- **2027:** nobody has declared, so 2027 is graded on the whole eligible pool against the
  same "eligible pool" view of 2010-2023 (every player 3+ years out of HS with stats in
  season Y − 1, whether or not he left school). P(declare) is a logistic model
  `final ~ position × yrs + yrs × volume percentile + position:volume + yrs:recruit +
  recruit_missing` (in-sample AUC 0.742); it badly understates elite juniors (Jeremiah
  Smith 0.14), so it is reported per player as a flag and not used in the 2027 grade.
- **Player deep dives (2026, 2027):** probabilities, top SHAP drivers, and the three
  nearest historical comps by standardized Euclidean distance on the feature matrix.

Results:

| Class | Overall | QB | RB | WR | TE |
|---|---|---|---|---|---|
| 2027 (projected, eligible pool) | A− | A− | C− | B | D |
| 2026 | F | C− | F | D | C |
| 2025 | A | C− | A | D | A |
| 2024 | C− | A | C− | C− | D |

Class-level validation (LOCO 2010-2023, 14 classes), correlation of expected vs actual
tier points: QB 0.224 (permutation p 0.219), RB 0.326 (p 0.127), WR 0.477 (p 0.040), TE
0.314 (p 0.132), all positions combined 0.518 (Spearman 0.597). Trust the overall grade
more than any single position's.

### 3.10 All-time pre-draft player grades (`pd_06_player_grades.R`)

- **Score** = expected tier points = P(top) + P(top two) + P(any tier) from the chosen
  model. 2010-2023 use LOCO predictions (honest out-of-sample grades); 2024-2026 the final
  model; 2027 the final model on the in-progress season, twice: pro-rated to 12 games and
  as-is (`PD_NO_SCALE=1`).
- **Grade** = percentile of the score among drafted players at the position in 2010-2023:
  A+ top 5%, A 90-95, A− 85-90, B+ 75-85, B 65-75, B− 55-65, C+ 45-55, C 35-45, C− 25-35, D
  10-25, F bottom 10%. Fixed cut points, so grades compare across classes.
- Graded: QB 156 (2010-23) + 35 (2024-26) + 14 (2027); RB 287 + 53 + 21; WR 417 + 102 + 34;
  TE 189 + 50 + 18.

Validation (drafted 2010-2023):

- Any-tier hit rate: about 59% for A-range grades, 31% for B, 14% for C-range and below.
  C, D and F hit at about the same rate, so the grade separates the top, not the bottom.
- AUC, grade vs pick vs both: QB24 0.773 / 0.874 / 0.897; RB24 0.714 / 0.822 / 0.825; WR36
  0.717 / 0.849 / 0.848; TE24 0.716 / 0.858 / 0.864.
- Nested logistic `hit ~ log(pick)` vs `hit ~ log(pick) + grade` (likelihood-ratio test):
  the grade adds significantly only for QBs (QB16 p = 0.018, QB24 p = 0.004; AIC 126 →
  120). RB, WR and TE p-values 0.16-0.93.
- Within rounds 4-7, A-range RBs, WRs and TEs still hit at 33%, 10% and 17% vs 4-11% for C
  and below.
- Notable misses: A+ with no tier season (Johnny Manziel, N'Keal Harry, Treylon Burks,
  Laquon Treadwell, Michael Mayer, Bishop Sankey); D/F that hit (Josh Allen, Carson Wentz,
  Tyreek Hill, Puka Nacua, Cooper Kupp, George Kittle, James Cook).

### 3.11 All-time post-draft player grades (`PostDraft_Model/pd_07_postdraft_grades.R`)

Lives in its own folder (`PostDraft_Model/`, PC `Football2_PostDraft`). It reads
`pd_common.R` and `pd_player_grades.csv` from the pre-draft folder.

- **Source model:** the "post" tier ladder of each position model (QB/RB/TE phase 4, WR
  phase 6): ordinal elastic net on the pre-draft feature set plus `log_pick`, vacated
  target/touch/attempt share and incumbent production (WR: vacated target share, team
  targets the year before). Probabilities made nested (P(top) ≤ P(top two) ≤ P(any)).
- **Scores:** 2010-2023 from the LOCO out-of-fold predictions (`scheme == "LOCO"`, model
  `post` / `post_enet`); 2024-2026 from the position boards (`*_finish_tier_board_2024_2026.csv`,
  `wr_tier_board_2024_2026.csv`), i.e. the final model trained on 2010-2023. Score =
  P(top) + P(top two) + P(any tier).
- **Grade:** same A+ to F cut points as 3.10, applied to the percentile of the post-draft
  score among drafted players at the position in 2010-2023.
- **Join to pre-draft:** by position, class and pick. 1,289 of 1,351 post-draft players
  match (QB 191/198, RB 340/354, WR 519/547, TE 239/252); the rest have no college stats
  match in the pre-draft pool. `grade_move` = post grade step − pre grade step.

Validation (players with both grades, 2010-2023):

- Any-tier hit rate by grade band, pre → post: A 59% → 69%, B 31% → 35%, C 14% → 9%,
  D/F 13% → 4%.
- AUC pre / pick only / post: QB24 0.773 / 0.874 / 0.905; RB24 0.714 / 0.822 / 0.790; WR36
  0.717 / 0.849 / 0.833; TE24 0.717 / 0.858 / 0.828. The post model beats pick-only only for
  QBs; for RB, WR and TE draft slot alone is slightly better.
- Spearman with 3-year PPR points, pre → post: QB 0.39 → 0.67, RB 0.44 → 0.64, WR 0.36 →
  0.61, TE 0.33 → 0.63. Spearman between pre and post scores 0.53-0.68.
- Within-class Spearman (score vs tier, averaged over 14 classes), pre → post: QB 0.45 →
  0.61, RB 0.32 → 0.51, WR 0.31 → 0.49, TE 0.35 → 0.51. Class-total correlations are noisy
  (14 classes) and not reported as evidence.

Outputs: `pd_post_player_grades.csv`, `pd_post_grade_validation.csv`,
`pd_post_vs_pre_metrics.csv`, `pd_post_class_summary.csv`, `pd_post_grade_vs_pick.csv`,
`pd_post_grade_by_round.csv`, `pd_post_grade_scale.csv`, `plot_post_vs_pre.png`,
`pd_post_player_grades.html`, `phase7_log.txt` (all in `PostDraft_Model/`).

---

## 3b. Dynasty value model (`Dynasty_Model/`, scripts `dv_01` to `dv_07`)

Full results tables are in `Dynasty_Model/README.md` and the `dv_*_log.txt` files.

**Target.** Dynasty value of an active player at landmark season s (2026, pro-rated through
week 9; or 2025 for players with fewer than 3 games in 2026, valued one season further out):

  DVS = sum_{t=1..10} v^(t-1) S(t) m(t),  v = 1/1.15

- Season points: nflverse `fantasy_points_ppr`, regular season, scaled to a 17-game pace
  (`pts17 = pts * 17 / team games`; 16-game seasons through 2020).
- Startable: positional rank by pts17 <= QB24 / RB24 / WR36 / TE12. Replacement points
  `rep_pts` = pts17 of the player at that rank. PAR = pts17 - rep_pts; PAR+ = max(PAR, 0).
- Death event D (seasons after the landmark): first t with seasons t-1 and t both below the
  line (no games = below; past the data = retired = below). The rookie season never counts as
  below for this rule. Alive in season t means D > t. Administrative censoring at 2025.
- S(t) = P(D > t | landmark features); m(t) = E[PAR+_{s+t} | D > t, landmark features].
- Outputs also: win-now = sum_{t<=3} S m (i = 0); rebuild i = 0; contend i = 30%;
  e = sum_t S(t) (curtate expectation over 10 seasons). Score = 100 * DVS / max DVS.

**Population.** QB/RB/WR/TE (FB folded into RB) with a regular-season game 2006-2026: 3,070
players, 1,180 undrafted. Landmarks: every player-season played, 12,212 (11,030 with follow-up).
Features at the landmark (`FEATS` in `dv_common.R`): position, age (Sept 1), years since rookie
season, draft bucket (R1, R2, R3, R4-7, UDFA), PAR, previous-season PAR, startable now and last
season, career startable seasons, PPG, share of team games played, opportunities per game
(pass attempts for QBs + carries + targets), per-game pace PAR (`ppg*17 - rep_pts`), best PAR of
the last three seasons. PAR terms capped to [-300, 400].

**Survival models** (`dv_03`), train landmarks 2007-2017, test 2018-2024:
- Discrete-time logistic hazard GLM on person-period rows (20,242 rows): logit h(t) =
  ns(t; knots 2, 4; boundary 1, 18) + pos + ns(age,3) + pos:age + exp + draft + ns(par,3) +
  par_prev + startable + startable_prev + n_startable + games_frac + opp_pg + pos:par +
  t:startable + t:age + ns(par_rate,3) + ns(par_best3,3). Rows where t = 1 and the player is
  startable or a rookie are structural zeros (cannot die) and are dropped. S(t) = prod (1 - h).
- Cox PH with cluster(player_id); pos*(age + par) + I(age^2) + I(PAR+^2/100) + the rest.
  cox.zph global p ~ 4e-280 (startable chi-sq 595): PH rejected.
- Survival forest: ranger, 500 trees, min node 25, mtry 4, log-rank splitting. S(t) rebuilt as
  prod(1 - delta CHF) because exp(-CHF) overstated survival by ~24 points at t = 1.
- Blend = 0.5 GLM + 0.5 forest (used). Test C-index (expected life) all/startable:
  GLM 0.954/0.713, Cox 0.917/0.701, forest 0.946/0.748, blend 0.954/0.741, KM-by-position
  0.557/0.561. Brier at t = 3: blend 0.055 vs KM 0.099. Strict split (training outcomes cut at
  2017) within 0.01 on every metric.

**Production model** (`dv_04`) on alive person-periods (9,804, 45% zeros): Tweedie GLM, log
link, p = 1.5 (p = 1.3 / 1.7 within 1 RMSE point): y ~ pos * ns(t) + ns(age_t,3) + pos:age_t +
exp + draft + ns(par,3) + par_prev + startable + n_startable + ppg + games_frac + opp_pg +
pos:par + t:par + t:ppg + t:startable + ns(par_rate,3) + ns(par_best3,3); vs ranger regression
(500 trees, min node 20, mtry 5). Test RMSE / Gini: GLM 49.6 / 0.589, forest 49.3 / 0.597,
blend 48.7 / 0.611 (used), naive last-season 65.9 / 0.466.

**Backtest** (`dv_05`): models fit on 2007-2017, landmarks 2018-2022, predicted vs realized
3-season PAR+ (alive seasons only). Startable players (n = 480): Spearman 0.583 vs naive 0.460,
RMSE 118 vs 196. All players: Spearman 0.551 vs naive 0.646 (naive orders starters above all
non-starters), RMSE 56 vs 84. A/E by predicted decile: top decile 1.00; overall 11% high.

**Interpretation** (`dv_06`, `dv_07`): PDP/ICE of the score over age by position, PDP of
per-game pace, kernel SHAP (kernelshap, 25 background players) for the top 25, and
finite-difference effect sizes (`dv_effect_sizes.csv`): +2 years of age = -3% QB / -23% RB /
-24% WR / -9% TE; +50 PAR this season = +25% / +33% / +30% / +63%; undrafted instead of actual
draft slot = -17% to -21%.

---

## 4. ATPA / PA course concepts used

| Concept (course module) | Where it is used |
|---|---|
| Data validation, domain and range checks (ATPA 2.5) | Phase 1 PASS/FAIL checks in every model |
| Missing values, imputation (ATPA 2.6, 3.7a) | In-fold median imputation + missing flags; flags often carry signal (skipped drills, missing team totals) |
| Leakage-safe preprocessing (ATPA 3.7a) | Medians, flags and PCA fit inside each training fold |
| Regularized GLMs (PA: elastic net, lasso, ridge) | Main learner everywhere; α 0.5, λ by grouped CV |
| Logistic regression, link functions (PA) | Hit models, the 5-input WR pre-draft model |
| Ordinal / cumulative logit | Tier ladders (polr, ordinalNet) |
| Hurdle / two-part models | Two-step finish score |
| PCA (PA) | WR combine drills → `athletic_pc1/2` |
| Mixed models and credibility (ATPA 3.3) | Random conference intercept (`glmer`) in the conference test |
| Tree ensembles (PA: RF, boosting) | RF in rookie WR; RF and xgboost in the pre-draft comparison |
| Stacking (ATPA 3.6) | Considered; replaced by an equal-weight average because 8 test classes can't fit a meta-learner |
| Neural networks (ATPA 3.4) | Not used |
| Model-agnostic interpretation (ATPA 4.3) | Permutation importance, PDP + ICE, SHAP, gain at top 5% |
| Model comparison case study (ATPA 4.5) | Null / simple GLM / enet / RF / XGB / ensemble with a fixed selection rule |
| Time-aware validation | Strict rolling origin by draft class; LOCO as an optimistic check |
| Bootstrap inference | Paired bootstrap CIs for every model-vs-benchmark difference |
| Calibration, Brier, log loss, Brier skill, RPS | Probability quality, not just ranking |
| Business framing (ATPA 4.4) | Boards and buy/sell lists turn probabilities into decisions |

---

## 5. Known caveats

1. **Small samples.** 14 training classes; 20-40 top-tier hits per position. TE8 (22
   hits) and QB tiers are noisy. Single-position class grades are noisy.
2. **College coverage.** cfbd is unusable before 2008 (classes start 2010) and logs FCS
   players only in games vs FBS teams before 2022. Some FBS players are missing entirely
   (Todd Gurley, LaMichael James, Anthony Dixon) or partial (Duke Johnson; Ray Davis 2023;
   Cam Newton's 2010 Auburn season). These are flagged `college_thin` / imputed.
3. **Age.** Rookie models use real birth dates; the pre-draft model uses years out of high
   school, so some lower-level transfers look younger than they are.
4. **Snap counts start in 2013**, so 2010-2012 rookies have imputed snap features.
5. **Two-way and positional quirks.** Travis Hunter's college receiving understates him
   (he also played defense). cfbd lists many TEs as WR, RB or "?" (checked in
   `suspicious_matches.csv`). Darren Waller is in the WR data (drafted as a WR).
6. **2026 college season** was pulled about 10 games in and pro-rated to 12 games; re-pull
   after the season.
7. **Landing-spot features** use rookie-season rosters, which are known by Week 1, but
   in-season moves can creep in, so they live only in the post-draft set.
8. **LOCO is optimistic** (it trains on future classes); the rolling-origin numbers are
   the honest ones.
9. **P(declare)** understates elite underclassmen; it is a flag only.
10. **Fullbacks** listed as "RB" in the draft data land in the RB `college_thin` group;
    "FB" are excluded.

---

## 6. Reproducing

Set `CFBD_API_KEY` in `~/.Renviron`. On Kyle's PC run scripts with
`R_ENVIRON_USER=C:/Users/kylem/Documents/.Renviron` and
`C:/Program Files/R/R-4.6.1/bin/Rscript.exe` (each folder's `run.sh script.R log.txt` does
this). Order: WR Phase 1 (builds the shared cache, ~30 min first run) → each position's
Phases 1-7 (+ summary lists) → pre-draft `pd_01` (and `PD_NO_SCALE=1` for the as-is pool) →
`pd_02_models.R QB|RB|WR|TE` → `pd_03` → `pd_04` → `pd_05` (optional) → `pd_06` →
post-draft `PostDraft_Model/pd_07_postdraft_grades.R` (run from that folder). The QB,
RB and TE scripts read `../Football2/cache` (PC) or `../WR_Model/cache` (repo).
