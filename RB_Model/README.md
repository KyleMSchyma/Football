# Rookie RB Model

This uses the same design as the WR and QB models (`../WR_Model`, `../QB_Model`), adapted to
running backs. It predicts PPR points and RB finish tiers over a back's first three NFL
seasons. It then runs year-2 and year-3 follow-up models built on NFL usage, plus a check
on undrafted RBs.

- **Data window:** draft classes 2010-2026 (354 drafted RBs; fullbacks listed as "FB" are
  excluded). The 2010-2023 classes are the training data (298 RBs). In years 1-3, 78 of
  them had a top-24 season, 56 a top-16 season and 36 a top-8 season.
- **Tier cutoffs (Kyle's):** RB8 / RB16 / RB24 / rest, using full-PPR season ranks among
  RBs.
- **Validation:** strict rolling origin, where each class is scored using only classes
  whose outcomes were already known, with test classes 2016-2023 (n = 171). Leave-one-
  class-out results and bootstrap CIs (2000 draws, seed 2026) are reported too. All
  imputation and missing-value flags are fit inside each training fold.

## What it predicts

| Target | Definition |
|---|---|
| `total_pts_3yr` | Regular-season PPR points in NFL years 1-3 |
| `hit24_3yr` / `hit16_3yr` / `hit8_3yr` | Any top-24 / top-16 / top-8 RB season in years 1-3 |
| `finish_sum_3yr` | Sum of season RB finishes in years 1-3, each capped at 60 (3 = best, 180 = never top-60) |
| Tier ladder | P(RB8), P(RB16), P(RB24) for the best finish in years 1-3 (cumulative logit, so the three are always nested) |
| Year-2 model | After the rookie season: P(RB8 / RB16 / RB24) and PPR points in years 2-3 |
| Year-3 model | After year 2: P(RB8 / RB16 / RB24) and PPR points in year 3 |

Each draft-time target is modeled three ways:

- **pick-only:** draft position alone (the baseline)
- **pre-draft:** college production, breakout age, age, combine (including speed score)
  and recruiting
- **post-draft:** the pre-draft inputs plus draft pick and landing spot (vacated RB
  touches, the returning RB's prior-season points)

## How to run

The scripts read the raw caches built by the WR pipeline from `../Football2/cache` (this
repo's `../WR_Model/cache`, which is not committed). They write the new RB pulls (draft
picks, recruiting) to `./cache`. Put `CFBD_API_KEY` in `~/.Renviron`. `run.sh script.R
log.txt` runs a script with that file.

| Order | Script | What it does |
|---|---|---|
| 1 | `rb_phase1_data_build.R` | RB draft picks, college match (96.3%), recruiting, combine, validation |
| 2 | `rb_phase2_targets_features.R` | Targets and features, writes `rb_model_table.rds` |
| 3 | `rb_phase3_model.R` | 3-yr points and RB24/16/8 hit models, value-score back-test, PPA check, projections |
| 4 | `rb_phase4_finish_tiers.R` | Finish score (single and two-step), RB8/16/24 tier ladder, Day-3 hidden-talent back-test |
| 5 | `rb_phase5_year2_breakout.R` | Rookie usage → years 2-3 |
| 6 | `rb_phase6_year3.R` | Years 1-2 usage → year 3 |
| 7 | `rb_phase7_udfa.R` | Undrafted RBs |
| - | `rb_summary_lists.R` | Year 1 prospects and Year 2 / Year 3 buy and sell lists (`rb_summary_lists.csv`) |

Shared code lives in `rb_common.R` (feature sets and model helpers) and `rb_usage.R` (NFL
usage features). Each script's console output is saved as `phaseN_run_log.txt`.

**RB features**

- **College (primary season):** this is the last season with 100+ touches. Features are
  carries, yards per carry, rushing TDs, receptions, and share of team carries, receptions,
  scrimmage yards and TDs (the RB "dominator").
- **Career:** career totals and breakout age. Breakout age is the age at the first season
  with 20%+ of team scrimmage yards.
- **Combine:** speed score (weight × 200 / forty⁴), plus the other combine measurements.
- **NFL usage (year-2 and year-3 models):** touches, carries and targets per game, share
  of team carries and targets, snap share (season and last 6 games, from 2013 on), YPC,
  rushing EPA per carry, how much of his points came from TDs and from receiving, and
  late-season (weeks 10+) touches and points.

## Results (from the CSVs in this folder)

### Draft-time models: rolling origin, test classes 2016-2023 (n = 171)

| Target | Pick-only | Post-draft elastic net | Pre-draft elastic net |
|---|---|---|---|
| 3-yr PPR points: Spearman / RMSE | 0.679 / 191.8 | 0.640 / 196.8 | 0.387 / 233.5 |
| Top-24 RB season: AUC / Brier | 0.842 / 0.133 | 0.795 / 0.147 | 0.655 / 0.182 |
| Top-16 RB season: AUC / Brier | 0.801 / 0.128 | 0.739 / 0.135 | 0.585 / 0.161 |
| Top-8 RB season: AUC / Brier | 0.861 / 0.081 | 0.873 / 0.085 | 0.705 / 0.107 |
| Finish score: Spearman | 0.638 | 0.604 | 0.362 |
| Tier ladder: RPS / AUC RB24 | 0.113 / 0.842 | 0.121 / 0.798 | 0.149 / 0.642 |

Bootstrap checks (rolling origin; a negative difference means the first model is better):

| Comparison | Difference | 95% CI |
|---|---|---|
| 3-yr points: post-draft minus pick-only RMSE | +5.0 | [-2.9, +12.7] |
| Top-24: post-draft minus pick-only Brier | +0.015 | [+0.004, +0.025] |
| Top-8: post-draft minus pick-only Brier | +0.004 | [-0.002, +0.011] |
| Tier ladder: post-draft minus pick-only RPS | +0.008 | [+0.001, +0.016] |

**Finding:** as with WRs and QBs, draft capital carries the signal at draft time. For the
top-24 hit model and the tier ladder, adding college and combine data makes the model
significantly *worse* than pick alone. College PPA/usage adds nothing (top-24 Brier change
-0.001, CI [-0.004, +0.002]). The value score doesn't work for RBs either: backs the
college model liked more than their draft slot did not beat their slot. Top tercile minus
bottom tercile = -47 points, CI [-114, +20].

**Hidden talent on Day 3:** among the 117 RBs drafted in rounds 4-7 in the test years,
there were 12 top-24 backs (Aaron Jones, Kyren Williams, Chase Brown, Rhamondre Stevenson,
Isiah Pacheco, and others). Taking the top 2 or 3 per class by college-model "hidden"
score caught 0-1 of them. Taking the earliest picks caught 2-4.

### Year-2 model: rookie usage → years 2-3 (rolling, n = 171)

| Model | AUC RB24 | Brier RB24 | AUC RB8 | RMSE pts |
|---|---|---|---|---|
| Pick-only | 0.820 | 0.144 | 0.840 | 154.2 |
| Pick + rookie points | 0.862 | 0.126 | 0.850 | 138.5 |
| Usage elastic net | 0.847 | 0.133 | 0.814 | 136.2 |

Bootstrap checks (rolling origin; a negative difference means the usage model is better):

- **Usage minus pick-only:** points RMSE = -18.0, CI [-27.8, -7.2], so the usage model is
  significantly better.
- **Usage minus rookie points:** RB24 Brier = +0.007, CI [-0.004, +0.018], so there is no
  gain.

**Finding:** this is like WRs, not QBs. After year 1, rookie points capture most of the
signal. The usage model leans on snap share (season and last 6 games), YPC and rushing
EPA, but it doesn't beat rookie points on its own.

### Year-3 model: years 1-2 → year 3 (rolling, n = 171)

| Model | AUC RB24 | Brier RB24 | AUC RB8 | RMSE pts |
|---|---|---|---|---|
| Pick-only | 0.820 | 0.118 | 0.797 | 83.1 |
| Pick + year-2 points | 0.944 | 0.084 | 0.916 | 56.9 |
| Pick + year-1 + year-2 points | 0.940 | 0.085 | 0.934 | 57.1 |
| Usage elastic net | 0.933 | 0.092 | 0.949 | 59.9 |

**Finding:** year-2 points dominate. Usage is slightly better at the RB8 end
(AUC 0.949), but the difference isn't significant. Brier vs year-2 points = -0.004, CI
[-0.013, +0.004].

### Undrafted RBs

- **Hit rates:** 183 UDFA RBs (2010-2023) had a carry. Of these, 8 had a top-24 season and
  2 a top-8 season in years 1-3 (4.4%, vs 10.9% for rounds 4-7). The two top-8 UDFAs were
  Austin Ekeler and James Robinson.
- **Effect on the year-2 model:** training the year-2 model with UDFAs slightly improves
  the drafted-player results (usage AUC 0.847 → 0.859).

### Current boards

| Board | Leaders |
|---|---|
| 2026 class, `rb_projections_2024_2026.csv` + `rb_finish_tier_board_2024_2026.csv`, P(top-24 in yrs 1-3) | Jeremiyah Love (pick 3) 0.99 (P(RB8) 0.95), Jadarian Price (32) 0.72, Emmett Johnson (161) 0.37, Jonah Coleman (108) 0.30 |
| 2026 Day-3 stashes (college model vs slot) | Seth McGowan, Emmett Johnson, Adam Randall |
| 2025 class, year-2 outlook, `rb_year2_breakout_board.csv`, P(top-24 in 2026-27) | Ashton Jeanty 0.84, Omarion Hampton 0.81, TreVeyon Henderson 0.67, RJ Harvey 0.66 |
| 2025 class buys | Hampton, Woody Marks, Cam Skattebo, Kyle Monangai (usage model above rookie points) |
| 2025 class sells | Quinshon Judkins (0.48 vs 0.68 on rookie points), Jeanty, Henderson, Jacory Croskey-Merritt. "Sell" means the usage model is less bullish than rookie points; it doesn't mean the player is bad. |
| 2024 class, year 3 (2026), `rb_year3_board.csv` | Tyrone Tracy Jr. 0.34, Bucky Irving 0.29, Kimani Vidal 0.19, all listed as buys. No 2024 back finished top-24 in 2025 |

The full lists are in `rb_summary_lists.csv` and `summary_lists_log.txt`. Also in this
folder: `rb_udfa_board.csv`, the OOF prediction files, and the plots
`plot_p2_pts_vs_pick.png`, `plot_p2_pts_vs_dominator.png` and
`plot_p2_pts_vs_speed_score.png`.

## Data caveats

- **College coverage:** cfbd has no college rows for some well-known backs, including Todd
  Gurley, LaMichael James and Anthony Dixon. It has only partial rows for others, such as
  Duke Johnson and Ray Davis's 2023 Kentucky season. It also only logs FCS backs' games
  against FBS teams (Tarik Cohen, Chase Edmonds, David Johnson, Terrance West).
- **How thin data is handled:** these 42 RBs are flagged `college_thin` and their college
  stats are imputed in-fold. Thin means no season with 60+ touches, partial team totals,
  or no match. Some fullbacks listed as "RB" in the draft data also land here.
- **Snap counts:** these start in 2013, so the 2010-2012 rookies have no snap-share
  features. Those are imputed with a missing-value flag.
- **UDFA list:** it comes from the nflreadr players table, which has no 2012 rookie-season
  UDFA RBs.
