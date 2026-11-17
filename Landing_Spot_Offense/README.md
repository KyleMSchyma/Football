# Do rookies produce more when they land on a high-scoring fantasy offense?

Research only (2026-11-17). Nothing on the site or in the models changed.

**Question (Kyle):** if a rookie lands on a team that had a high-scoring fantasy offense the
year before, does he score more, by position and post-draft grade? And since the post-draft
model already knows the draft pick and the landing spot (vacated share, incumbent
production), does team offense add anything **beyond** the post-draft grade?

## Short answer

**No, not in a way worth using.**

1. **On its own, a good offense goes with *worse* rookie production, not better.** Rookies
   drafted by the bottom third of offenses scored about 4.6 PPR points per team game as
   rookies. Rookies drafted by the top third scored about 2.6. That is because bad offenses
   pick earlier (better players) and have open jobs. Good offenses pick later and already
   have starters.
2. **Once you hold the post-draft grade fixed, team offense adds almost nothing.** Within
   each grade, rookies on good and bad offenses score about the same. Adding team offense
   to the grade made out-of-sample predictions better for QBs by about 1% and worse or no
   better for RB, WR and TE.
3. **The one real pattern is QBs in year one.** A QB who goes to a team that already scored
   a lot usually sits behind a starter (J.J. McCarthy, Jordan Love, Jimmy Garoppolo, Hendon
   Hooker all scored about zero as rookies). By years 1 to 3 that gap mostly closes.
4. **Possible small signals, probably noise:** TEs and WRs on good offenses did slightly
   better over years 1 to 3 (TE odds of ever hitting a tier +39% per step up in offense,
   not statistically reliable; WRs on teams with strong WR scoring +0.3 points per game,
   borderline). With about 30 tests run, one or two "significant" results are expected by
   chance, and neither improved predictions out of sample.

**Recommendation:** don't add prior-year team offense to the post-draft model or the rookie
pick values. The draft pick and the existing landing-spot inputs already capture what the
team situation tells us.

## Data

- **Players:** every drafted QB, RB, WR and TE 2010-2026 from
  `../PostDraft_Model/pd_post_player_grades.csv` (1,351 players). Scores for 2010-2023 are
  leave-one-class-out, so the grade never saw the player's own class. Drafting team from
  nflverse `draft_picks` (all 1,351 matched on class + pick).
- **Team offense:** total fantasy points per game of the drafting team the season **before**
  the draft (full PPR, 4-pt pass TD, regular season, all players, same scoring as
  /team-analytics/). Expressed as standard deviations from that season's league average, so
  2010 and 2025 compare fairly. A "same position" version uses only the team's points at the
  rookie's position (for example team WR points for a WR).
- **Outcomes:** rookie PPR points per team game (missed games count as zero, classes
  2010-2025, 1,271 players); points per game played (6+ games); points per 17 games over
  years 1-3 (classes 2010-2023); and whether the player ever reached a tier (QB24 / RB24 /
  WR36 / TE18).

## Results

### 1. Raw: rookie points per team game by prior-year team offense

| Position | Bottom third | Middle third | Top third | Avg pick (bottom to top) |
|---|---|---|---|---|
| QB | 6.4 | 3.5 | 0.9 | 84 to 158 |
| RB | 5.2 | 3.7 | 3.2 | 121 to 145 |
| WR | 4.3 | 3.3 | 3.0 | 117 to 132 |
| TE | 2.7 | 2.3 | 2.0 | 125 to 147 |

Every position goes down as offense goes up. The average pick column shows why: good
offenses draft later.

### 2. By post-draft grade (all positions)

| Grade | Bottom third | Middle third | Top third |
|---|---|---|---|
| A | 9.6 | 8.4 | 6.7 |
| B | 5.0 | 4.4 | 4.2 |
| C | 2.3 | 1.9 | 1.7 |
| D/F | 1.3 | 0.7 | 0.8 |

The grade matters far more than the offense: an A-graded rookie on a top offense still
outscores a B-graded rookie on a bad one. Within a grade the gap is small and, except for
A-graded QBs and RBs, mostly within noise. `plot_lso_grade_band.png` shows each position;
`lso_by_grade_band.csv` has the counts (some cells are tiny, e.g. one A-graded QB went to a
top-third offense).

### 3. Beyond the grade (regression holding the post-draft score fixed)

Effect of a team offense one standard deviation above average (`lso_regressions.csv`):

| Position | Rookie pts/team game | Years 1-3 pts/game | Odds of ever hitting a tier |
|---|---|---|---|
| QB | **-0.9** (reliable) | -0.5 (not reliable) | 0.69x (not reliable) |
| RB | -0.4 (not reliable) | +0.1 | 1.14x |
| WR | -0.1 | +0.1 (+0.3 using team WR points, borderline) | 1.08x |
| TE | +0.1 | +0.3 (borderline) | 1.39x (not reliable) |

Explained variance barely moves: for rookie points it goes from 53.5% to 55.2% for QBs and
by less than 1 point for the others. Whether the grade is high or low didn't change the
offense effect (no interaction).

### 4. Out-of-sample model comparison (leave one draft class out)

| Position | Grade only (RMSE) | Grade + team offense | Hit model AUC, grade only | + team offense |
|---|---|---|---|---|
| QB | 3.96 | 3.91 | 0.887 | 0.880 |
| RB | 3.79 | 3.79 | 0.801 | 0.800 |
| WR | 3.35 | 3.36 | 0.836 | 0.832 |
| TE | 2.26 | 2.27 | 0.813 | 0.801 |

A gradient-boosted model gave the same picture (`lso_model_comparison.csv`). The partial
dependence plots (`plot_lso_pdp_ice.png`) are bumpy with no consistent upward slope, which is
what noise looks like.

## How to explain it to a non-technical audience

"Good offenses don't make rookies better, they make rookies wait. Teams that scored a lot
last year pick later and already have starters, so their rookies play less. Once you know
where a player was drafted and how open the depth chart is, which our post-draft grade
already includes, last year's team scoring tells you nothing more."

## Files

| File | What it is |
|---|---|
| `lso_01_build.py` | Builds `lso_players.csv` and `lso_team_offense.csv` (set `NFLVERSE_DIR`) |
| `lso_02_analyze.py` | Splits, regressions, logistic, LOCO comparison, PDP/ICE; writes the CSVs, plots and `lso_results_log.txt` |
| `lso_players.csv` | One row per player: grade, team, prior-year offense, outcomes |
| `lso_team_offense.csv` | Team fantasy points per game by season 2009-2026, total and by position |

Data: nflverse (via the nflverse-data releases) and our post-draft grades.
