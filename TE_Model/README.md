# Rookie TE Model

This uses the same design as the WR, QB and RB models (`../WR_Model`, `../QB_Model`,
`../RB_Model`), adapted to tight ends. It predicts PPR points and TE finish tiers over a
tight end's first three NFL seasons. It then runs year-2 and year-3 follow-up models built
on NFL usage, plus a check on undrafted TEs.

- **Data window:** draft classes 2010-2026 (252 drafted TEs). The 2010-2023 classes are
  the training data (202 TEs). In years 1-3, 46 of them had a top-18 season, 35 a top-12
  season and 14 a top-6 season (under the old 8/16/24 cutoffs: 55 / 42 / 22).
- **Tier cutoffs (Kyle's):** TE6 / TE12 / TE18 / rest (tier 1 = TE1-6, tier 2 = TE7-12, tier 3 =
  TE13-18), using full-PPR season ranks among TEs. Changed from TE8 / TE16 / TE24 on
  2026-11-12: a 12-team league starts only 12 TEs, so TE16 and TE24 seasons were below
  replacement. The cutoffs are one setting, `TE_CUT` in `te_common.R`; columns are named
  after them (`hit6/hit12/hit18_3yr`, `p_top6/12/18_*`).
- **Validation:** strict rolling origin, where each class is scored using only classes
  whose outcomes were already known, with test classes 2016-2023 (n = 113). Leave-one-
  class-out results and bootstrap CIs (2000 draws, seed 2026) are reported too. All
  imputation and missing-value flags are fit inside each training fold.
- **Sample size warning:** this is the smallest of the four position samples (about 15
  TEs per class). The TE6 tier is the thinnest target in any position model: 14 hits in 14
  classes, none at all in 2012, 2014, 2015 or 2020, and only 8 in the 2016-2023 rolling
  test years. Treat the TE6 numbers as very noisy.

## What it predicts

| Target | Definition |
|---|---|
| `total_pts_3yr` | Regular-season PPR points in NFL years 1-3 |
| `hit18_3yr` / `hit12_3yr` / `hit6_3yr` | Any top-18 / top-12 / top-6 TE season in years 1-3 |
| `finish_sum_3yr` | Sum of season TE finishes in years 1-3, each capped at 60 (3 = best, 180 = never top-60) |
| Tier ladder | P(TE6), P(TE12), P(TE18) for the best finish in years 1-3 (cumulative logit, so the three are always nested) |
| Year-2 model | After the rookie season: P(TE6 / TE12 / TE18) and PPR points in years 2-3 |
| Year-3 model | After year 2: P(TE6 / TE12 / TE18) and PPR points in year 3 |

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
| 3 | `te_phase3_model.R` | 3-yr points and TE18/12/6 hit models, value-score back-test, PPA check, projections |
| 4 | `te_phase4_finish_tiers.R` | Finish score (single and two-step), TE6/12/18 tier ladder, Day-3 hidden-talent back-test (about 10 minutes) |
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

All numbers below use the TE6 / TE12 / TE18 tiers (rerun 2026-11-12). The 8/16/24 versions
are in git history and in `_backup_te_8_16_24_2026-11-12` on Kyle's PC.

### Draft-time models: rolling origin, test classes 2016-2023 (n = 113)

| Target | Pick-only | Post-draft elastic net | Pre-draft elastic net |
|---|---|---|---|
| 3-yr PPR points: Spearman / RMSE | 0.667 / 108.8 | 0.558 / 114.2 | 0.200 / 136.4 |
| Top-18 TE season: AUC / Brier | 0.861 / 0.111 | 0.822 / 0.120 | 0.709 / 0.160 |
| Top-12 TE season: AUC / Brier | 0.872 / 0.100 | 0.816 / 0.115 | 0.676 / 0.139 |
| Top-6 TE season: AUC / Brier | 0.875 / 0.055 | 0.763 / 0.064 | 0.669 / 0.066 |
| Finish score: Spearman | 0.676 | 0.580 | 0.245 |
| Tier ladder: RPS / AUC TE6 / AUC TE18 | 0.087 / 0.864 / 0.864 | 0.096 / 0.830 / 0.819 | 0.119 / 0.718 / 0.702 |

Old 8/16/24 ladder for comparison (rolling): RPS 0.102 / 0.111 / 0.138, AUC TE8 0.887 / 0.859 /
0.751, AUC TE24 0.867 / 0.821 / 0.691 (pick / post / pre). Brier and RPS are lower now
mainly because the base rates are lower; the ranking (AUC) is about the same or slightly
worse at the top tier.

Bootstrap checks (rolling origin; a negative difference means the first model is better):

| Comparison | Difference | 95% CI |
|---|---|---|
| 3-yr points: post-draft minus pick-only RMSE | +5.4 | [-1.5, +13.2] |
| Top-18: post-draft minus pick-only Brier | +0.009 | [-0.007, +0.025] |
| Top-6: post-draft minus pick-only Brier | +0.009 | [+0.002, +0.019] |
| Tier ladder: post-draft minus pick-only RPS | +0.010 | [+0.000, +0.019] |
| Tier ladder: pre-draft minus pick-only RPS | +0.032 | [+0.014, +0.054] |
| Finish score: two-step post-draft minus pick-only RMSE | +3.0 | [+0.3, +5.7] |

**Finding:** the same story as WRs, QBs and RBs. Draft capital carries the signal at draft
time, and adding college and combine data never beats pick alone. With the tighter tiers
the post-draft ladder is now significantly (just) worse than pick alone, and so is the
post-draft top-6 model. Every first-round TE from 2010-2023 (11 of 11) had a top-18 season
in years 1-3 (27% a top-6 season), against 37% of rounds 2-3 and 9% of rounds 4-7. College
PPA/usage adds nothing (top-18 Brier change +0.005, CI [-0.003, +0.013]). The value score
doesn't work either: TEs the college model liked more than their slot did not beat their
slot (top tercile minus bottom = +14 points, CI [-36, +61]).

What the college model does like: recruiting rating, a fast forty and 3-cone, receiving
share and not having transferred.

**Hidden talent on Day 3:** among the 68 TEs drafted in rounds 4-7 in the test years,
there were 6 top-18 tight ends (George Kittle, Dalton Schultz, Jake Ferguson, Isaiah
Likely, Cade Otton, Chris Herndon). Taking the top 2 per class by college-model "hidden"
score caught 2 of them, the same as taking the earliest picks (2), against 1.0 at random.

### Year-2 model: rookie usage → years 2-3 (rolling, n = 113)

| Model | AUC TE18 | Brier TE18 | AUC TE12 | AUC TE6 | RMSE pts |
|---|---|---|---|---|---|
| Pick-only | 0.856 | 0.110 | 0.823 | 0.765 | 87.9 |
| Pick + rookie points | 0.925 | 0.088 | 0.878 | 0.687 | 82.7 |
| Usage elastic net | 0.901 | 0.101 | 0.845 | 0.694 | 83.9 |

Bootstrap checks (rolling origin):

- **Rookie points minus pick-only:** TE18 Brier = -0.022, CI [-0.041, -0.002], so the
  rookie season significantly improves on draft slot.
- **Usage minus rookie points:** TE18 Brier = +0.013, CI [+0.002, +0.025], so the usage
  model is significantly *worse* than rookie points alone.
- **TE6 (11 hits in years 2-3):** usage minus pick-only Brier +0.005, CI [+0.001, +0.010].
  The top tier is too thin for any of these models to rank well (AUC 0.69-0.76).

**Finding:** like WRs and RBs, not QBs. After year 1, rookie points capture the signal.
Of the 105 TEs who finished outside the top 18 as rookies, 17 reached it in years 2-3.
Taking the top 2 per class caught 9 with rookie points or pick only and 7 with the usage
model (random: 2.4).

### Year-3 model: years 1-2 → year 3 (rolling, n = 113)

| Model | AUC TE18 | Brier TE18 | AUC TE6 | RMSE pts |
|---|---|---|---|---|
| Pick-only | 0.795 | 0.103 | 0.686 | 50.2 |
| Pick + year-2 points | 0.884 | 0.084 | 0.975 | 39.2 |
| Pick + year-1 + year-2 points | 0.886 | 0.088 | 0.968 | 40.1 |
| Usage elastic net | 0.878 | 0.087 | 0.895 | 40.3 |

**Finding:** year-2 points dominate. The usage model ties them (TE18 Brier difference
+0.003, CI [-0.009, +0.014]). Its biggest coefficients are year-1 and year-2 air-yard and
target share and WOPR, which is useful for reading the board. Only 9 year-3 TE6 seasons in
training.

### Undrafted TEs

- **Hit rates:** 161 UDFA TEs (2010-2023) had a target and three complete seasons. Of
  these, 4 had a top-18 season and none a top-6 season in years 1-3. Three reached the
  top 18 in years 2-3: Cameron Brate, Larry Donnell and Juwan Johnson.
- **Effect on the year-2 model:** training with UDFAs slightly improves the drafted-player
  results (usage Brier 0.101 → 0.099, AUC 0.901 → 0.906). No 2024-2025 UDFA TE shows up
  (best: Brevyn Spann-Ford, P(top 18) 0.05).
- Darren Waller is not in either list: he was drafted as a WR.

### Current boards

| Board | Leaders |
|---|---|
| 2026 class, `te_projections_2024_2026.csv` + `te_finish_tier_board_2024_2026.csv`, P(top-18 in yrs 1-3) | Kenyon Sadiq (pick 16) 0.86 (P(TE6) 0.43), Oscar Delp (73) 0.47, Eli Stowers (54) 0.39, Sam Roush (69) 0.37, Eli Raridon (95) 0.31 |
| 2026 Day-3 stashes (college model vs slot) | Dallen Bentley, Jaren Kanak, Tanner Koziol |
| 2025 class, year-2 outlook, `te_year2_breakout_board.csv`, P(top-18 in 2026-27) | Tyler Warren 0.93, Colston Loveland 0.91, Harold Fannin 0.78, Mason Taylor 0.56, Oronde Gadsden II 0.48, Gunnar Helm 0.40 |
| 2025 class buys | Jackson Hawes, Mitchell Evans (small P, but usage ahead of rookie points) |
| 2025 class sells | Harold Fannin (0.78 vs 0.93 on rookie points), Mason Taylor (0.56 vs 0.69), Colston Loveland, Tyler Warren. "Sell" means the usage model is less bullish than rookie points; it doesn't mean the player is bad. |
| 2024 class, year 3 (2026), `te_year3_board.csv` | Brock Bowers 0.76 (P(TE6) 0.17), Theo Johnson 0.32 (buy: rising targets and snaps), AJ Barner 0.26, Ja'Tavion Sanders 0.14. Sells: Brock Bowers, AJ Barner (usage below year-2 points) |

The buy/sell rules keep their old probability thresholds (0.15 / 0.40) and finish windows
(TE36 / TE40), now applied to P(top 18).

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
