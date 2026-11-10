# Rookie QB Model

This is the same design as the WR model (`../WR_Model`), adapted to quarterbacks. It
predicts fantasy points and finish tiers over a QB's first three NFL seasons, then runs
year-2 and year-3 follow-up models built on NFL usage.

- **Data window:** draft classes 2010-2026. The 2010-2023 classes are training data
  (163 QBs; 45 had a top-24 season and 25 a top-12 season in years 1-3).
- **Tier cutoffs:** top 8 / top 16 / top 24 / rest.
- **Validation:** strict rolling origin (each class is scored using only classes whose
  outcomes were already known), plus leave-one-class-out, with bootstrap CIs.

## How to run

The scripts read the raw caches built by the WR pipeline from `../Football2/cache` (this
repo's `../WR_Model/cache`, which is not committed). They write new QB pulls to `./cache`.
Put `CFBD_API_KEY` in `~/.Renviron`. `run.sh script.R log.txt` runs a script with that file.

| Order | Script |
|---|---|
| 1 | `qb_phase1_data_build.R`: QB draft picks, college match, validation |
| 2 | `qb_phase2_targets_features.R`: targets and features (`qb_model_table.rds`) |
| 3 | `qb_phase3_model.R`: 3-yr points and top-8/16/24 hit models; projections |
| 4 | `qb_phase4_finish_tiers.R`: finish score, two-step model and tier ladder |
| 5 | `qb_phase5_year2_breakout.R`: rookie usage → years 2-3 |
| 6 | `qb_phase6_year3.R`: years 1-2 usage → year 3 |
| 7 | `qb_phase7_udfa.R`: undrafted QBs |

Shared code lives in `qb_common.R` and `qb_usage.R`. The `backup_qb_phase*_v1.R` files are
earlier versions, kept for reference.

## Results (from the CSVs in this folder)

### Draft-time models: rolling origin, test classes 2016-2023 (n = 95)

| Target | Pick-only | Post-draft elastic net | Pre-draft elastic net |
|---|---|---|---|
| 3-yr fantasy points: Spearman / RMSE | 0.667 / 205.2 | 0.556 / 228.8 | 0.369 / 275.2 |
| Top-24 QB season: AUC / Brier | 0.848 / 0.140 | 0.893 / 0.122 | 0.769 / 0.160 |
| Top-8 QB season: AUC / Brier | 0.817 / 0.104 | 0.801 / 0.101 | 0.617 / 0.124 |

Bootstrap checks (rolling origin):

- **3-yr points:** post-draft minus pick-only RMSE = +23.5, 95% CI [+4.8, +44.5], so
  post-draft is significantly worse.
- **Top-24 QB:** post-draft minus pick-only Brier = -0.017, 95% CI [-0.050, +0.015], so
  there is no detectable gain.

**Finding:** as with WRs, draft capital carries the signal at draft time.

### Year-2 model: rookie usage → top-24 QB season in years 2-3 (rolling, n = 94)

| Model | AUC top-24 | Brier top-24 |
|---|---|---|
| Pick-only | 0.857 | 0.131 |
| Pick + rookie points | 0.924 | 0.112 |
| Usage elastic net | 0.955 | 0.080 |

Bootstrap checks (rolling origin):

- **Usage minus pick-only:** Brier top-24 = -0.052, 95% CI [-0.094, -0.012]
- **Usage minus rookie points:** Brier top-24 = -0.033, 95% CI [-0.064, -0.004]

**Finding:** unlike the WR model, the QB usage model significantly beats rookie points
alone.

### Year-3 model: years 1-2 → year 3 (rolling, n = 94)

| Model | AUC top-24 | Brier top-24 | RMSE pts |
|---|---|---|---|
| Pick-only | 0.863 | 0.097 | 84.4 |
| Pick + year-2 points | 0.990 | 0.032 | 53.1 |
| Usage elastic net | 0.985 | 0.043 | 56.2 |

**Finding:** by year 3, a QB's year-2 points are the dominant signal.

### Undrafted QBs

There were 19 undrafted test QBs and none reached top-24. Adding them doesn't change the
drafted-player results (usage AUC 0.955 → 0.958).

### Current boards

| Board | Leaders |
|---|---|
| 2026 class, `qb_projections_2024_2026.csv`, P(top-24 in yrs 1-3) | Fernando Mendoza (pick 1) 0.99, Carson Beck 0.40, Drew Allar 0.32, Ty Simpson 0.28, Taylen Green 0.28 |
| 2025 class, year-2 outlook, `qb_year2_breakout_board.csv`, P(top-24 in 2026-27) | Jaxson Dart 0.94, Cam Ward 0.86, Tyler Shough 0.72 (rookie points alone: 0.56); buy-lows Riley Leonard 0.28 (0.06) and Shedeur Sanders 0.25 (0.16) |
| 2024 class, year 3 (2026), `qb_year3_board.csv` | Caleb Williams 0.96, Drake Maye 0.95, Bo Nix 0.89; Jayden Daniels 0.38 after a QB34 year 2 |

Also in this folder: `qb_finish_tier_board_2024_2026.csv` and `qb_udfa_board.csv`.

## Data caveats

- College data is unusable before 2008, so the classes start in 2010.
- cfbd only logs FCS QBs' games against FBS teams, so those QBs are treated as missing.
- Cam Newton's 2010 Auburn season is missing.
