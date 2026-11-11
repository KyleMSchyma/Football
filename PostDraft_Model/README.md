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
  spot (vacated share, incumbent production), with tiers QB/RB/TE 8/16/24 and WR 12/24/36.
- **Scores:** 2010-2023 use leave-one-class-out (LOCO) predictions, and 2024-2026 use the
  final post model (trained on 2010-2023) from each position's board. Score = expected tier
  points = P(top) + P(top two) + P(any tier). 2027 is excluded because nobody has been
  drafted yet.
- **Grade:** the same A+ to F cut points as the pre-draft grades, applied to the
  percentile of the post-draft score among drafted players at the position in 2010-2023.
- **Join to pre-draft:** by position, class and pick (1,289 of 1,351 players match).
  `grade_move` = post grade step minus pre grade step.

## Findings (players with both grades, 2010-2023)

Any-tier hit rate by grade band, pre to post: A 59% to 69%, B 31% to 35%, C 14% to 9%,
D/F 13% to 4%. Within-class rank correlation with actual tier rises from 0.31-0.45 to
0.49-0.61. The post model beats pick-only for QBs (QB16 AUC 0.91 vs 0.87) and trails it
slightly for RB, WR and TE.

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
