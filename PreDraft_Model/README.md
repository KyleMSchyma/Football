# Pre-Draft Rookie Model (college data only)

A "prior-draft" companion to the QB, RB, WR and TE rookie models (`../QB_Model`,
`../RB_Model`, `../WR_Model`, `../TE_Model`). It answers: before draft capital is known,
how good does a college class look from its analytics alone? It uses **no draft pick, no
landing spot and no combine data**: only college box-score production, usage shares, age
(years out of high school) and recruiting.

Results write-up: https://claude.ai/artifact/LpjqTZULpQXjUzYEnTzFYr

## Design

- **Who is modeled:** every draft-eligible college player (3+ years out of high school) at
  each position, classes 2010-2027, not just drafted players. A player's class is his
  draft year (drafted), rookie year (undrafted free agent who played) or last college
  season + 1. Players who never reached the NFL are misses. So the model learns
  P(tier hit | college profile), which includes the chance he gets drafted at all.
  Training pool (2010-2023): QB 882, RB 1,629, WR 2,785, TE 1,002.
- **Targets:** a top-tier / top-two-tier / any-tier season in NFL years 1-3, with Kyle's
  cutoffs (QB/RB/TE 8/16/24, WR 12/24/36). Drafted players' outcomes come from the four
  existing models; UDFA outcomes are rebuilt from weekly data and matched to college by
  name + school.
- **Features** (`pd_common.R`, `FEATS`): primary-season production and team shares,
  career totals, breakout timing, years out of HS, recruiting rating, Power 5, transfers,
  short final year. Leakage-safe preprocessing (medians and missing flags fit on training
  rows only).
- **Model comparison** (ATPA 4.5 style): base rate, 5-input logistic regression, elastic
  net, random forest, XGBoost and their average. Strict rolling origin (test classes
  2016-2023, train on classes <= Y - 3) plus leave-one-class-out; AUC, Brier, Brier skill,
  log loss, gain at the top 5%, bootstrap CIs. The best rolling Brier skill is "chosen":
  elastic net for QB, RB and TE, logistic regression for WR.
- **Interpretation** (ATPA 4.3 style): permutation importance, PDP + ICE for the top three
  inputs, SHAP values (exact linear contributions for the chosen linear models; TreeSHAP
  code path for xgboost).
- **Class grades:** expected tier points (top-tier hit = 3, middle 2, bottom 1) over the
  top K prospects per class (QB 12, RB 20, WR 32, TE 15), graded by percentile against
  2010-2023 (A top 10% ... F bottom 10%). Depth = expected any-tier hits beyond the top 3.
  2027 is graded on the whole eligible pool against the same eligible-pool view of
  2010-2023, since nobody has declared yet.
- **2026 college season:** pulled 2026-11-10, about 10 games in; counting stats scaled to
  12 games.

## Results

| Class | Overall | QB | RB | WR | TE |
|---|---|---|---|---|---|
| 2027 (projected) | A- | A- | C- | B | D |
| 2026 | F | C- | F | D | C |
| 2025 | A | C- | A | D | A |
| 2024 | C- | A | C- | C- | D |

Validation: player-level rolling AUC about 0.85-0.91 and Brier skill 0.12-0.24 by
position. Class level (2010-2023, 14 classes): correlation of expected vs actual class
tier points QB 0.22, RB 0.33, WR 0.48 (permutation p = 0.04), TE 0.31, all positions
combined 0.52. Trust the overall grade more than any single position's.

## How to run

The scripts read the raw caches built by the WR pipeline (`../WR_Model/cache`, not
committed) and the model tables of the four position models. New pulls (2026 college
season, 2026 team stats, 2023-2026 recruiting) go to `./cache` (not committed). Put
`CFBD_API_KEY` in `~/.Renviron`; `run.sh script.R log.txt [args]` runs a script with it.

| Order | Script | What it does |
|---|---|---|
| 1 | `pd_01_pool_build.R` | Prospect pool for every class 2010-2027, outcomes, features, P(last season) data, eligible pool |
| 2 | `pd_02_models.R QB` (also RB, WR, TE) | Model comparison, rolling + LOCO validation, class backtest, final fit, 2024-2027 board (about 2-3 min each) |
| 3 | `pd_03_interpret.R` | Permutation importance, PDP/ICE, SHAP |
| 4 | `pd_04_grades.R` | Class grades, depth, overall grade, player deep dives |
| - | `pd_05_conference_test.R` | Conference as a predictor: tier indicators, tier x production, conference indicators, credibility (random conference intercept) |

Outputs: `pd_class_grades.csv`, `pd_overall_grades.csv`, `pd_eligible_pool_grades.csv`,
`pd_class_validation.csv`, `pd_player_deep_dive.csv`, per position `pd_<pos>_board.csv`
(every 2024-2027 prospect), `pd_<pos>_metrics.csv`, `pd_<pos>_class_metrics.csv`,
`pd_<pos>_importance.csv`, `pd_<pos>_shap_prospects.csv`, plots `plot_*.png`, and the run
logs.

## Caveats

- **Level of competition:** conference inputs (tier indicators, tier x production,
  conference indicators, a credibility random conference intercept) were tested in
  `pd_05_conference_test.R` and did not help: cfbd has full FCS box scores only from 2022,
  so training holds almost no full FCS seasons. Instead, 2022+ FCS production is translated
  to an FBS scale with factors estimated from FCS-to-FBS vs FBS-to-FBS transfers
  (receiving and rushing 0.685, passing 0.789; `pd_level_translation.rds`, Phase 1). G5 vs
  Power 5 is handled by the Power 5 flag.
- **Age:** no birth dates exist for college players, so age is years out of high school
  (recruiting class year; for unrecruited players, first season with stats minus one).
  Some transfers from lower levels look younger than they are.
- **P(declare)** for 2027 uses production and recruiting only and badly understates elite
  juniors (Jeremiah Smith 0.14). It is reported per player as a flag; the 2027 grade does
  not use it.
- **Coverage:** cfbd only logs lower-division games against FBS teams, and the pool grows
  over time with FCS coverage and the transfer portal, which is why grades use the top K
  prospects rather than whole-class sums.
- **Small samples:** 20-40 top-tier hits per position in 14 classes. Single-position
  class grades are noisy.

## Player grades (Phase 6)

`pd_06_player_grades.R` scores every drafted QB/RB/WR/TE from the 2010-2026 classes with the
pre-draft model, ranks them within position and gives each a letter grade; the top 2027
prospects (QB 12, RB 20, WR 32, TE 15) are inserted into the same rankings as projected.

Results page: https://claude.ai/artifact/XAVUw32K3yMb7atWgpov3i

- **Score** = expected tier points = P(top) + P(top two) + P(any tier), from the chosen model.
  2010-2023 use leave-one-class-out predictions (each class scored by a model that never saw
  it); 2024-2027 use the final model trained on 2010-2023.
- **Grade** = percentile of the score among drafted players at the position in 2010-2023:
  A+ top 5%, A 90-95, A- 85-90, B+ 75-85, B 65-75, B- 55-65, C+ 45-55, C 35-45, C- 25-35,
  D 10-25, F bottom 10%. Fixed cut points, so grades compare across classes.
- **2027** is scored twice: pro-rated (counting stats scaled to 12 games, the default pool)
  and as-is (stats through about week 10; `PD_NO_SCALE=1 ./run.sh pd_01_pool_build.R log.txt`
  writes `pd_pool_asis.rds` and the other Phase 1 outputs with an `_asis` suffix).
- **NFL outcomes** sit next to every historical player: best finish in years 1-3 (2024-2025:
  so far), tier, 3-year PPR points. FCS players before 2022 are flagged "thin college data".

Findings (drafted 2010-2023): any-tier hit rate is 59% for A-range grades, 31% for B and
14% for C-range and below. C, D and F hit at about the same rate, so the grade separates the
top, not the bottom. Draft slot predicts better (AUC 0.81-0.87 vs 0.67-0.78) and the grade
adds significantly to log(pick) only for QBs (QB16 p = 0.018, QB24 p = 0.004). Within Rounds
4-7, A-range RBs, WRs and TEs still hit at 10-33% vs 4-11% for C and below.

Outputs: `pd_player_grades.csv` (every graded player), `pd_grade_scale.csv`,
`pd_grade_validation.csv`, `pd_grade_vs_pick.csv`, `pd_grade_by_round.csv`,
`plot_grade_hit_rates.png`, `pd_player_grades.html` (offline copy of the results page),
`phase6_log.txt`.

## Post-draft player grades (Phase 7)

`pd_07_postdraft_grades.R` builds the same A+ to F board for every drafted player 2010-2026
from the post-draft tier ladders of the four position models (college profile + draft pick +
landing spot), and puts it next to the pre-draft grade (`grade_move` = grade steps moved).
2010-2023 use LOCO predictions, 2024-2026 the position boards. 2027 is excluded. The page
above has the board and a per-class view.

Findings (players with both grades, 2010-2023): any-tier hit rate by grade band, pre to post,
A 59% to 69%, B 31% to 35%, C 14% to 9%, D/F 13% to 4%. Within-class rank correlation with
actual tier rises from 0.31-0.45 to 0.49-0.61. The post model beats pick-only for QBs (QB16
AUC 0.91 vs 0.87) and trails it slightly for RB, WR and TE.

Outputs: `pd_post_player_grades.csv`, `pd_post_grade_validation.csv`,
`pd_post_vs_pre_metrics.csv`, `pd_post_class_summary.csv`, `pd_post_grade_vs_pick.csv`, `pd_post_grade_by_round.csv`, `pd_post_grade_scale.csv`, `plot_post_vs_pre.png`, `pd_post_player_grades.html` (offline copy of the post-draft page: https://claude.ai/artifact/CXjjafaBwrK84knShtR4n6),
`phase7_log.txt`.
