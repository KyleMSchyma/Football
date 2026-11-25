# Do A+, A and A- grades mean different things? (research, 2026-11-25)

Kyle asked whether the top three grade tiers on the rookie boards really differ. Research only: grades, values and the
site are unchanged.

**Data.** `PostDraft_Model/pd_post_player_grades.csv`, drafted QB/RB/WR/TE 2010-2023 (1,108 players, outcomes complete),
every grade out-of-class (LOCO). Three grade systems on the same players: pre-draft, plain post-draft (`*_draft`
columns) and the mixed "Adjusted" grade the site shows. Outcomes in NFL years 1-3: top tier (QB8/RB8/WR12/TE6), top two
tiers (QB16/RB16/WR24/TE12), any tier (QB24/RB24/WR36/TE18), and PPR points per game (`pd_post_proj_ppg.csv`
`actual_ppg3`, 0 if no games). Run: `python3 gt_01_tier_tests.py` (numpy, pandas, scipy, statsmodels, matplotlib).

## Answer

| Comparison | Pre-draft | Post-draft | Adjusted (site default) |
|---|---|---|---|
| **A+ vs A** | Real gap. Top tier 48% vs 20% (p=.005), PPG 11.6 vs 8.8 (p=.02) | Real gap. Any tier 91% vs 64% (p=.002), top tier 55% vs 29% (p=.009), PPG 13.5 vs 10.9 (p<.001) | Real gap. Any tier 91% vs 62% (p=.001), top tier 55% vs 26% (p=.003), PPG 13.5 vs 10.6 (p<.001) |
| **A vs A-** | No gap; A- did slightly better (any tier 59% vs 48%, p=.36) | Lean, borderline. Any tier 64% vs 44% (p=.04), top tier p=.07, PPG p=.08 | Lean, not significant. Any tier 62% vs 47% (p=.08), top-2 tiers p=.045, PPG p=.16 |
| **A- vs B+** | Real gap (any tier 59% vs 34%, p=.006) | No gap (44% vs 45%) | Small, not significant (47% vs 39%, p=.40) |

p-values: Cochran-Mantel-Haenszel test stratified by position (hit rates), within-position permutation test (PPG).

- **A+ is a genuinely different group** in all three models: about 9 in 10 post-draft A+ players hit a tier and over
  half hit the top tier.
- **A vs A- is mostly a lean, not a proven split.** The adjusted and post-draft grades point the right way on every
  outcome (A beats A- by 8-21 points), but with ~55-75 players per grade the tests can only detect gaps of about 21-26
  points (`gt_power.csv`), so the honest read is "probably a bit better, not proven". In the pre-draft grades the
  order is noise.
- **The percentile itself still carries information inside the A range** (`gt_trend_within_A.csv`): within the top
  15%, each 10 percentile points multiply the odds of any tier by ~9 (adjusted) and the top tier by ~6 (p<.0001). So
  the information is there; the 5-point A / A- bins are just too narrow to show it reliably.
- **By position** (`gt_adjacent_tests_by_position.csv`) samples are 8-30 per grade, so most single-position tests are
  noise. RB A+ vs A is the clearest real gap (adjusted: top tier 13/15 vs 4/16).

## Better splits?

Leave-one-class-out Brier scores of grade hit rates (`gt_alternative_splits*.csv`, class-bootstrap CIs):

- Merging A+, A and A- into one A band is **significantly worse** in the post and adjusted grades (Brier +.003 to +.004,
  CI above 0). The A+ line must stay.
- Two bands (A+ top 5%, A 85-95%) ties the current three (adjusted -.0007, CI -.0029 to +.0012). Other cuts (A+ 97%,
  A+ 92 / A 85 / A- 75, A+ 90%) are no better. **No alternative beats the current split.**

Recommendation: keep the grade scale. Read A+ as a real step up, A vs A- as a tiebreaker, and use the Proj. PPG and
Value columns (continuous) to separate players inside the A range.

## Files

| File | What |
|---|---|
| `gt_tier_outcomes.csv` | n, mean pick, hit rates (Wilson 95% CIs) and PPG (95% CI) by system, position and grade A+..B+ |
| `gt_adjacent_tests.csv` | pooled adjacent-grade tests (CMH odds ratio and p, PPG permutation p) |
| `gt_adjacent_tests_by_position.csv` | Fisher exact and Mann-Whitney by position |
| `gt_trend_within_A.csv` | logistic / OLS slope of outcome on percentile inside the A range |
| `gt_power.csv` | smallest hit-rate gap detectable at 80% power with these sample sizes |
| `gt_percentile_curve.csv` | hit rates in finer percentile bins |
| `gt_alternative_splits.csv`, `gt_alternative_splits_bootstrap.csv` | LOCO Brier of alternative cut points, with class-bootstrap CIs |
| `plot_tier_outcomes.png`, `plot_percentile_curve.png`, `plot_tier_by_position.png` | charts |

---

# Part 2: B and C grades (2026-11-25)

Kyle asked for the same tests on B+/B/B- and C+/C/C-. Script `gt_02_bc_tiers.py` (same data and tests as Part 1;
adjacent pairs include the band edges A- vs B+, B- vs C+, C- vs D, D vs F).

## Answer (Adjusted grade; post-draft is the same story)

| Grade | n | Any tier | Top-2 tiers | PPG yrs 1-3 |
|---|---|---|---|---|
| A- | 76 | 47% | 34% | 9.9 |
| B+ | 101 | 39% | 27% | 8.1 |
| B | 105 | 40% | 26% | 7.6 |
| **B-** | 115 | **16%** | **10%** | **5.0** |
| C+ | 107 | 9% | 6% | 3.9 |
| C | 107 | 12% | 6% | 4.5 |
| C- | 107 | 6% | 3% | 3.4 |
| D | 158 | 4% | 3% | 2.6 |
| F | 109 | 2% | 2% | 2.1 |

- **B+ vs B: no difference** (39% vs 40%, p=.96; PPG p=.26).
- **B vs B-: the biggest cliff below A+** (40% vs 16%, p<.001; PPG 7.6 vs 5.0, p<.001). Post-draft the same (40% vs 15%).
- **B- vs C+: small lean** (16% vs 9%, p=.22; PPG p=.05). B- behaves more like a C than a B.
- **C+, C, C-: hit rates are flat and not different** (9%, 12%, 6%; every pair p>.14). C vs C- differs a little in PPG
  (4.5 vs 3.4, p=.009), which is mostly depth/backup points, not fantasy starters.
- **C- vs D and D vs F: not different** in hit rates (all near zero).
- Pre-draft grades: a smooth gentle slope with no significant adjacent gaps in B or C except C+ vs C (20% vs 10%, p=.05).
- Within the B band the percentile still matters (adjusted any-tier odds x1.8 per 10 pctile, p=.0001); within C it
  does not for hits (p=.26).

## Better splits?

LOCO Brier (top-2 and any tier), class-bootstrap CIs, rest of the scale fixed (`gt_bc_alternative_splits.csv`):

- Merging B+ and B (65-85) is **significantly better** for post and adjusted any tier (adjusted -.0015, CI -.0034 to
  -.0002).
- Merging B- into one C band (B 65-85 / C 25-65) is better still (adjusted any tier -.0023, CI -.0045 to -.0004; post
  -.0027, CI -.0044 to -.0012). **Caveat:** this cut was chosen after seeing these results, so the gain is optimistic.
- Merging C+/C/C- into one band ties or slightly helps; merging the whole B band into one is not better.

The outcomes fall into about five real groups: **A+ | A, A- | B+, B | B-, C+, C, C- | D, F**. Fewer, wider grades
would describe them as well as the current eleven. Recommendation: no change unless Kyle wants it; if he does, a
data-led scale (e.g. A+ / A / B / C / D) should be re-tested on the 2024 class after the R3 retrain before going live.

Files: `gt_bc_tier_outcomes.csv`, `gt_bc_adjacent_tests.csv`, `gt_bc_adjacent_tests_by_position.csv`,
`gt_bc_trend_within_band.csv`, `gt_bc_alternative_splits.csv`, `plot_bc_tier_outcomes.png`, `plot_bc_tier_by_position.png`.
