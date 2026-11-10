# Rookie TE Model

This uses the same design as the WR, QB and RB models (`../WR_Model`, `../QB_Model`,
`../RB_Model`), adapted to tight ends. It predicts PPR points and TE finish tiers over a
tight end's first three NFL seasons. It then runs year-2 and year-3 follow-up models built
on NFL usage, plus a check on undrafted TEs.

- **Data window:** draft classes 2010-2026 (252 drafted TEs). The 2010-2023 classes are
  the training data (202 TEs). In years 1-3, 55 of them had a top-24 season, 42 a top-16
  season and 22 a top-8 season.
- **Tier cutoffs (Kyle's):** TE8 / TE16 / TE24 / rest, using full-PPR season ranks among
  TEs.
- **Validation:** strict rolling origin, where each class is scored using only classes
  whose outcomes were already known, with test classes 2016-2023 (n = 113). Leave-one-
  class-out results and bootstrap CIs (2000 draws, seed 2026) are reported too. All
  imputation and missing-value flags are fit inside each training fold.
- **Sample size warning:** this is the smallest of the four position samples (about 15
  TEs per class, 22 top-8 hits in 14 classes). Treat the TE8 numbers as noisy.

## What it predicts

| Target | Definition |
|---|---|
| `total_pts_3yr` | Regular-season PPR points in NFL years 1-3 |
| `hit24_3yr` / `hit16_3yr` / `hit8_3yr` | Any top-24 / top-16 / top-8 TE season in years 1-3 |
| `finish_sum_3yr` | Sum of season TE finishes in years 1-3, each capped at 60 (3 = best, 180 = never top-60) |
| Tier ladder | P(TE8), P(TE16), P(TE24) for the best finish in years 1-3 (cumulative logit, so the three are always nested) |
| Year-2 model | After the rookie season: P(TE8 / TE16 / TE24) and PPR points in years 2-3 |
| Year-3 model | After year 2: P(TE8 / TE16 / TE24) and PPR points in year 3 |

Each draft-time target is modeled three ways:

- **pick-only:** draft position alone (the baseline)
- **pre-draft:** college production, breakout age, age, combine (including speed score)
  and recruiting
- **post-draft:** the pre-draft inputs plus draft pick and landing spot (vacated TE
  targets, the returning TE's prior-season points)

## How to run

The scripts read the raw caches built by the WR pipeline from `../Football2/cache` (this
repo's `../WR_Model/cache`, which is not committed). They write the new TE pulls (draft
picks, recruiting) to `./cache`. Put `CFBD_API_KEY` in `~/.Renviron`. `run.sh script.R
log.txt` runs a script with that file.

| Order | Script | What it does |
|---|---|---|
| 1 | `te_phase1_data_build.R` | TE draft picks, college match (95.2%), recruiting, combine, validation |
| 2 | `te_phase2_targets_features.R` | Targets and features, writes `te_model_table.rds` |
| 3 | `te_phase3_model.R` | 3-yr points and TE24/16/8 hit models, value-score back-test, PPA check, projections |
| 4 | `te_phase4_finish_tiers.R` | Finish score (single and two-step), TE8/16/24 tier ladder, Day-3 hidden-talent back-test (about 10 minutes) |
| 5 | `te_phase5_year2_breakout.R` | Rookie usage → years 2-3 |
| 6 | `te_phase6_year3.R` | Years 1-2 usage → year 3 |
| 7 | `te_phase7_udfa.R` | Undrafted TEs |
| - | `te_summary_lists.R` | Year 1 prospects and Year 2 / Year 3 buy and sell lists (`te_summary_lists.csv`) |

Shared code lives in `te_common.R` (feature sets and model helpers) and `te_usage.R` (NFL
usage features). Each script's console output is saved as `phaseN_run_log.txt`.

**TE features**

- **College (primary season):** this is the last season with 15+ receptions. Features are
  receptions, receiving yards and TDs, yards per catch, share of team receptions, the
  receiving dominator (mean of team receiving-yard and receiving-TD shares) and receiving
  yards per team pass attempt.
- **Career:** career receiving yards, seasons with 25+ catches, best-season dominator and
  breakout age. Breakout age is the age at the first season with a 15%+ dominator (lower
  than the WR model's 20%, since TEs share targets with WRs).
- **Combine:** height, weight, forty, speed score (weight × 200 / forty⁴), vertical, broad
  jump and 3-cone.
- **NFL usage (year-2 and year-3 models):** targets and catches per game, share of team
  targets and air yards, WOPR, yards per target, receiving EPA per target, catch rate,
  aDOT, how much of his points came from TDs, snap share (season and last 6 games, from
  2013 on), and late-season (weeks 10+) targets and points.
- **Two-step finish score:** step 1 is P(any top-32 TE season in years 1-3), roughly "the
  starting TE on his team" (the RB model used top 36).

## Results (from the CSVs in this folder)

### Draft-time models: rolling origin, test classes 2016-2023 (n = 113)

| Target | Pick-only | Post-draft elastic net | Pre-draft elastic net |
|---|---|---|---|
| 3-yr PPR points: Spearman / RMSE | 0.667 / 108.8 | 0.558 / 114.2 | 0.200 / 136.4 |
| Top-24 TE season: AUC / Brier | 0.866 / 0.124 | 0.816 / 0.138 | 0.698 / 0.184 |
| Top-16 TE season: AUC / Brier | 0.865 / 0.108 | 0.833 / 0.118 | 0.732 / 0.155 |
| Top-8 TE season: AUC / Brier | 0.889 / 0.070 | 0.713 / 0.079 | 0.680 / 0.082 |
| Finish score: Spearman | 0.676 | 0.580 | 0.245 |
| Tier ladder: RPS / AUC TE8 / AUC TE24 | 0.102 / 0.887 / 0.867 | 0.111 / 0.859 / 0.821 | 0.138 / 0.751 / 0.691 |

Bootstrap checks (rolling origin; a negative difference means the first model is better):

| Comparison | Difference | 95% CI |
|---|---|---|
| 3-yr points: post-draft minus pick-only RMSE | +5.4 | [-1.5, +13.2] |
| Top-24: post-draft minus pick-only Brier | +0.014 | [-0.008, +0.036] |
| Top-8: post-draft minus pick-only Brier | +0.009 | [-0.004, +0.023] |
| Tier ladder: post-draft minus pick-only RPS | +0.009 | [-0.001, +0.020] |
| Tier ladder: pre-draft minus pick-only RPS | +0.036 | [+0.016, +0.057] |
| Finish score: two-step post-draft minus pick-only RMSE | +3.0 | [+0.3, +5.7] |

**Finding:** the same story as WRs, QBs and RBs. Draft capital carries the signal at draft
time, and adding college and combine data never beats pick alone (the differences lean
worse, though most CIs cross zero). Every first-round TE from 2010-2023 (11 of 11) had a
top-24 season in years 1-3, against 47% of rounds 2-3 and 12% of rounds 4-7. College
PPA/usage adds nothing (top-24 Brier change -0.0002, CI [-0.009, +0.007]). The value
score doesn't work either: TEs the college model liked more than their slot did not beat
their slot (top tercile minus bottom = +14 points, CI [-36, +61]).

What the college model does like: best-season dominator, recruiting rating, a fast forty
and 3-cone, and not having transferred.

**Hidden talent on Day 3:** among the 68 TEs drafted in rounds 4-7 in the test years,
there were 8 top-24 tight ends (George Kittle, Dalton Schultz, Jake Ferguson, Isaiah
Likely, Cade Otton, Chig Okonkwo, Chris Herndon, Ian Thomas). Taking the top 2 per class
by college-model "hidden" score caught 2-3 of them, the same as taking the earliest picks
(3) and only a little above random (1.4).

### Year-2 model: rookie usage → years 2-3 (rolling, n = 113)

| Model | AUC TE24 | Brier TE24 | AUC TE16 | AUC TE8 | RMSE pts |
|---|---|---|---|---|---|
| Pick-only | 0.868 | 0.115 | 0.856 | 0.839 | 87.9 |
| Pick + rookie points | 0.939 | 0.089 | 0.924 | 0.865 | 82.7 |
| Usage elastic net | 0.925 | 0.103 | 0.909 | 0.817 | 83.9 |

Bootstrap checks (rolling origin):

- **Rookie points minus pick-only:** TE24 Brier = -0.027, CI [-0.052, -0.001], so the
  rookie season significantly improves on draft slot.
- **Usage minus rookie points:** TE24 Brier = +0.014, CI [+0.003, +0.026], so the usage
  model is significantly *worse* than rookie points alone.

**Finding:** like WRs and RBs, not QBs. After year 1, rookie points capture the signal.
Of the 99 TEs who finished outside the top 24 as rookies, 17 reached it in years 2-3.
Taking the top 2 per class caught 8 of them for all three models (random: 2.5).

### Year-3 model: years 1-2 → year 3 (rolling, n = 113)

| Model | AUC TE24 | Brier TE24 | AUC TE8 | RMSE pts |
|---|---|---|---|---|
| Pick-only | 0.800 | 0.126 | 0.762 | 50.2 |
| Pick + year-2 points | 0.906 | 0.095 | 0.944 | 39.2 |
| Pick + year-1 + year-2 points | 0.908 | 0.099 | 0.946 | 40.1 |
| Usage elastic net | 0.905 | 0.102 | 0.939 | 40.3 |

**Finding:** year-2 points dominate. The usage model ties them (TE24 Brier difference
+0.007, CI [-0.010, +0.022]). Its biggest coefficients are year-2 and year-1 target share,
WOPR and late-season snap share, which is useful for reading the board.

### Undrafted TEs

- **Hit rates:** 161 UDFA TEs (2010-2023) had a target and three complete seasons. Of
  these, 7 had a top-24 season and 1 a top-8 season (Cameron Brate) in years 1-3 (4.3%,
  vs 11.6% for rounds 4-7). The others: Larry Donnell, Timothy Wright, Juwan Johnson, Jake
  Ballard, Taysom Hill and Jacob Hollister.
- **Effect on the year-2 model:** training with UDFAs slightly improves the drafted-player
  results (usage Brier 0.103 → 0.095, AUC 0.925 → 0.930). No 2024-2025 UDFA TE shows up
  (best: Brevyn Spann-Ford, P(top 24) 0.09).
- Darren Waller is not in either list: he was drafted as a WR.

### Current boards

| Board | Leaders |
|---|---|
| 2026 class, `te_projections_2024_2026.csv` + `te_finish_tier_board_2024_2026.csv`, P(top-24 in yrs 1-3) | Kenyon Sadiq (pick 16) 0.96 (P(TE8) 0.75), Eli Stowers (54) 0.67, Marlin Klein (59) 0.47, Sam Roush (69) 0.43, Eli Raridon (95) 0.42, Oscar Delp (73) 0.42 |
| 2026 Day-3 stashes (college model vs slot) | Dallen Bentley, Jaren Kanak, Tanner Koziol |
| 2025 class, year-2 outlook, `te_year2_breakout_board.csv`, P(top-24 in 2026-27) | Colston Loveland 0.99, Tyler Warren 0.98, Harold Fannin 0.91, Mason Taylor 0.77, Oronde Gadsden II 0.63, Gunnar Helm 0.61 |
| 2025 class buys | Gunnar Helm (0.61 vs 0.51 on rookie points), Mitchell Evans, Jackson Hawes |
| 2025 class sells | Mason Taylor (0.77 vs 0.85 on rookie points), Harold Fannin (0.91 vs 0.98). "Sell" means the usage model is less bullish than rookie points; it doesn't mean the player is bad. |
| 2024 class, year 3 (2026), `te_year3_board.csv` | Brock Bowers 0.90 (P(TE8) 0.28), Theo Johnson 0.54 and AJ Barner 0.45 (both buys: rising targets and snaps), Ja'Tavion Sanders 0.19. No sells |

The full lists are in `te_summary_lists.csv` and `summary_lists_log.txt`. Also in this
folder: `te_udfa_board.csv`, the OOF prediction files, and the plots
`plot_p2_pts_vs_pick.png`, `plot_p2_pts_vs_dominator.png` and
`plot_p2_pts_vs_speed_score.png`.

## Data caveats

- **College coverage:** 12 drafted TEs have no cfbd match, mostly FCS / Division II
  players (Julius Thomas, Adam Shaheen, Adam Trautman, Seth DeValve) plus Rico Gathers
  (basketball) and a few FBS gaps (Nate Byham, Mickey Shuler, A.J. Derby). cfbd only logs
  FCS players' games against FBS teams, so Dallas Goedert, Nick Boyle and others have only
  partial rows.
- **How thin data is handled:** these 19 TEs are flagged `college_thin` and their college
  stats are imputed in-fold. Thin means no match, no season with 3+ catches, or partial
  team totals (fewer than 60 team receptions).
- **Positions in cfbd:** cfbd lists many college TEs as "WR", "RB" or "?" (Jordan
  Cameron, Charles Clay, Vance McDonald). These matches are checked in
  `suspicious_matches.csv` and kept.
- **Snap counts:** these start in 2013, so the 2010-2012 rookies have no snap-share
  features. Those are imputed with a missing-value flag.
- **UDFA list:** it comes from the nflreadr players table, which has no 2012 rookie-season
  UDFA TEs.
