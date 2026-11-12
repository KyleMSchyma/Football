# Post-Draft Player Grades

The post-draft companion to [`../PreDraft_Model`](../PreDraft_Model/README.md). It gives
every drafted QB, RB, WR and TE from 2010-2026 an A+ to F letter grade from the
**post-draft** version of each position model (college profile + draft pick + landing
spot), and puts it next to the pre-draft (college-only) grade so you can see how much
draft capital moved each player and each class.

Results page: https://claude.ai/artifact/CXjjafaBwrK84knShtR4n6 (offline copy:
`pd_post_player_grades.html`). It uses the same layout as the pre-draft grades page.

**What drives the model:** [PREDICTORS.md](PREDICTORS.md) explains, position by position,
which inputs the post-draft model leans on (permutation importance, odds per SD, PDP/ICE and
SHAP), how much draft capital dominates, and which high ranks come from data artifacts.
`pd_08_post_predictors.R` rebuilds it.

## Design

- **Source model:** the "post" tier ladder of each position model (QB/RB/TE phase 4, WR
  phase 6). It is an ordinal elastic net on college features + age + log(pick) + landing
  spot (vacated share, incumbent production), with tiers QB/RB 8/16/24, TE 6/12/18 (since 2026-11-12) and WR 12/24/36.
- **Scores:** 2010-2023 use leave-one-class-out (LOCO) predictions, and 2024-2026 use the
  final post model (trained on 2010-2023) from each position's board. Score = expected tier
  points = P(top) + P(top two) + P(any tier). 2027 is graded separately from a mock
  draft (see below).
- **Grade:** the same A+ to F cut points as the pre-draft grades, applied to the
  percentile of the post-draft score among drafted players at the position in 2010-2023.
- **Join to pre-draft:** by position, class and pick (1,289 of 1,351 players match).
  `grade_move` = post grade step minus pre grade step.

## Findings (players with both grades, 2010-2023)

Any-tier hit rate by grade band, pre to post: A 59% to 66%, B 28% to 34%, C 14% to 10%,
D/F 13% to 4% (TE alone, TE18 tiers: A 46% to 59%, B 33% to 33%, C 14% to 16%, D/F 11% to 0%). Within-class rank correlation with actual tier rises from 0.31-0.45 to
0.49-0.61. The post model beats pick-only for QBs (QB16 AUC 0.91 vs 0.87) and trails it
slightly for RB, WR and TE.

## 2027 class from a mock draft (`pd_09_mock_2027.R`)

Nobody in the 2027 class has been drafted yet, so a mock draft stands in for the draft. Each
mocked QB, RB, WR and TE takes the mock's pick as his draft capital and the mock's team as his
landing spot, then goes through the same post-draft model as every drafted player. The current
run uses the **Renner 2027 mock (post-deadline)**, which has 30 fantasy-position picks in
rounds 1-3. All 30 match the 2027 pre-draft board.

Inputs that don't exist yet are estimated:

- **College profile:** the player's 2027 row on the pre-draft board. On the 2024-2026 drafted
  players these columns match the position models' own columns almost exactly.
- **Age, breakout age and QB starter age:** fit from years since high school on the 2024-2026
  drafted players.
- **Combine:** the player is treated as an average tester at his position. Height and weight
  come from the mock for round 1 and are the position median otherwise.
- **Landing spot:** departures after 2026 are unknown. The vacated share is the 2010-2023
  median, every 2026 player is assumed to stay, and 2026 stats through week 9 are pro-rated to
  17 games.

**Check:** the 2024-2026 drafted players were scored the same way and compared with their real
post-draft scores. Spearman is QB .96, RB .95, WR .98 and TE .92. The estimate ran low for QB
and TE (by about 0.1), so the final grade maps the estimated score onto the real-score scale
with a per-position linear fit from that check. `post_grade_raw` keeps the uncalibrated grade.
After calibration, the share of players landing within one grade of their real grade is
QB 74%, RB 96%, WR 97% and TE 88%. The tier probabilities (`p_top`, `p_top2`, `p_any`) are
uncalibrated.

**Mock file:** the mock itself isn't stored here. The script reads it from `MOCK_FILE`
(columns: round, pick, team, team_abbr, player, pos, school, height_in, weight_lb), and the
picks it used appear in `pd_post_2027_mock_grades.csv`.

```bash
MOCK_FILE=mock_2027/mock_2027_fantasy_positions.csv MOCK_NAME="Renner 2027 mock (post-deadline)" ./run.sh pd_09_mock_2027.R phase9_log.txt
```

| File | What it holds |
|---|---|
| `pd_09_mock_2027.R` | The script |
| `pd_post_2027_mock_grades.csv` | One row per mocked player: pick, team, post-draft grade (calibrated and raw), pre-draft grade, `grade_move`, tier probabilities, estimated inputs |
| `pd_post_2027_mock_check.csv` | 2024-2026 check: real vs estimated post score and grade |
| `pd_post_2027_mock_inputs.csv` | Every model input for every mocked player (long format) |
| `phase9_log.txt` | Console log of the last run |

## Running it

Needs the four position models' outputs (`../QB_Model`, `../RB_Model`, `../WR_Model`,
`../TE_Model`) and the pre-draft grades (`../PreDraft_Model/pd_player_grades.csv`, from
`pd_06_player_grades.R`). It also reuses `../PreDraft_Model/pd_common.R`. From this folder:

```bash
./run.sh pd_07_postdraft_grades.R phase7_log.txt
./run.sh pd_08_post_predictors.R phase8_log.txt
```

`pd_08_post_predictors.R` only needs the position folders' model tables
(`qb_model_table.rds`, `rb_model_table.rds`, `te_model_table.rds`, `wr_model_table.rds` +
`phase5_finish_targets.csv`) and their `*_common.R` helpers. It refits the final post ladder
on 2010-2023 and takes about 1.5 minutes.

The script finds its sibling folders under either the repo names (`PreDraft_Model`, ...)
or Kyle's PC names (`Football2_PreDraft`, ...). The file name keeps its old `pd_07` prefix
from when it was Phase 7 of the pre-draft model, so older links and logs still match.

## Files

| File | What it holds |
|---|---|
| `pd_07_postdraft_grades.R` | The script |
| `pd_post_player_grades.csv` | Every graded player, with the pre-draft grade and `grade_move` |
| `pd_post_grade_scale.csv` | Grade cut points and score thresholds by position |
| `pd_post_grade_validation.csv` | Hit rates by post-draft grade, 2010-2023 |
| `pd_post_vs_pre_metrics.csv` | AUC and Spearman: pre-draft vs post-draft vs pick only |
| `pd_post_grade_vs_pick.csv` | Grade vs pick only vs pick + grade: AUC, Spearman, likelihood-ratio test |
| `pd_post_grade_by_round.csv` | Hit rates by grade band within draft-round bands |
| `pd_post_class_summary.csv` | Per class: average grade move, expected vs actual tier points |
| `plot_post_vs_pre.png` | Pre-draft vs post-draft percentile by position |
| `pd_post_player_grades.html` | Offline copy of the results page |
| `phase7_log.txt` | Console log of the last run |
| `PREDICTORS.md` | What drives the post-draft model, by position |
| `pd_08_post_predictors.R` | Refits the final post ladders and builds the predictor tables and plots |
| `pd_post_<pos>_importance.csv` | Permutation importance (AUC drop) with coefficients and odds per SD |
| `pd_post_<pos>_coefs.csv` | Every model column's ordinal coefficient, odds per SD and SD |
| `pd_post_<pos>_pdp_ice.csv` | PDP (id 0) and 40 ICE curves for the top 3 inputs |
| `pd_post_predictors_summary.csv` | Training n, hits, inputs kept, log-pick dominance by position |
| `plot_post_<pos>_importance.png`, `plot_post_<pos>_pdp_ice.png`, `plot_post_<pos>_shap.png` | Predictor plots |
| `phase8_log.txt` | Console log of the predictors run |
