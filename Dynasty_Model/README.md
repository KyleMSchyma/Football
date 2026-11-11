# Dynasty Value Model

How much is a player worth in a dynasty league, counting both how good he is and how long he will
stay useful? This model answers that the way an actuary prices a life annuity, and gives every
active NFL QB, RB, WR and TE (drafted or undrafted) a **Dynasty Value Score**.

## The idea in one paragraph

An actuary values an annuity by adding up every future payment, each one multiplied by the chance
the person is still alive to receive it and discounted back to today. Here, each future NFL season
is a "payment" of fantasy points above replacement. A player is "alive" while he is still a
startable fantasy asset. So a star with two good years left and a young player with a long runway
can end up with the same value, and the score shows why.

## The formula

```
Dynasty Value = sum over the next 10 seasons (t = 1 is 2027) of
                v^(t-1)  x  S(t)  x  E[ PAR+ in season t | still alive ]
```

| Piece | Meaning | Where it comes from |
|---|---|---|
| `S(t)` | Chance the player is still startable-alive in season t | Survival models (steps 2-3) |
| `PAR+` | Full-PPR points above the replacement line, 17-game pace, floored at 0 | Production model (step 4) |
| `v = 1/1.15` | Discount factor: a season two years out is worth 76% of next season | Main score uses 15% |

- **Startable lines (Kyle's):** QB24, RB24, WR36, TE12, by full-PPR season points among the
  position. QB24 means this is a **superflex** ranking; in a 1QB league QBs would rank lower.
- **Replacement line:** the points of the QB24 / RB24 / WR36 / TE12 that season. PAR+ works like
  an insurance deductible: only points above the line count, so a player below it is worth zero
  that season, not a negative.
- **When a career "ends" (the death event):** two straight seasons below the line. Not playing
  counts as below, so retirement and long injuries are included. **Rookie free pass:** the rookie
  season never counts toward the two-in-a-row rule (8% of players who missed in years 1 and 2
  later became startable, so a slow start alone should not end a career).
- **Score:** dynasty value scaled so the top player is 100. The board also gives the raw value in
  PAR points, a **win-now value** (next 3 seasons, no discount), a **rebuild value** (i = 0%), a
  **contend value** (i = 30%), and **expected alive seasons** (the sum of S(t), the actuarial
  curtate life expectancy).

## Data

- nflverse weekly player stats 2006-2025 (via `nflreadr`, cached by the WR pipeline in
  `../Football2/cache`), plus the 2026 season through week 9, pulled into `nfl_weekly_2026.rds`.
- nflverse player table for birth dates, draft round and roster status. Undrafted players are
  included (1,180 of the 3,070 QB/RB/WR/TE in the data).
- Every player-season is a **landmark**: what we knew about him that season, then what happened
  over the following seasons. 12,212 landmarks; 11,030 have at least one season of follow-up.
- The 2026 season is pro-rated to a 17-game pace by each team's games played so far.

## Steps

| Script | What it does |
|---|---|
| `dv_common.R` | Settings, features, model formulas, and the annuity function `value_parts()` |
| `dv_01_data_build.R` | Season totals, ranks, startable flags, replacement lines, landmarks, death times |
| `dv_02_kaplan_meier.R` | Kaplan-Meier life tables by position, draft round and age |
| `dv_03_survival_models.R` | Hazard GLM, Cox, survival forest; train 2007-2017, test 2018-2024 |
| `dv_04_production.R` | Tweedie GLM vs random forest for expected PAR+ |
| `dv_05_value_score.R` | Backtest of the value score, then the board for every active player |
| `dv_06_interpret.R` | PDP / ICE plots and SHAP explanations for the top 25 |
| `dv_07_effect_sizes.R` | Plain-English "what if" effects of age, production, missed games and draft round |

Run them in order from this folder (`./run.sh dv_01_data_build.R dv_01_log.txt` and so on).
Step 6 takes about 15-20 minutes because of kernel SHAP; everything else takes under 2 minutes.

## Step 2: Kaplan-Meier (the raw life tables)

Kaplan-Meier uses no player detail, only who was still alive each season. It is the "life table"
of fantasy careers (`dv_km_life_tables.csv`, `plot_km_*.png`).

**Once a player is startable, how long does it last?** (median seasons alive, and expected alive
seasons out of the next 10)

| Position | Median | Expected alive seasons | Alive 3 seasons later | Alive 5 seasons later |
|---|---|---|---|---|
| QB | 5 | 5.1 | 66% | 49% |
| WR | 4 | 3.6 | 56% | 32% |
| TE | 3 | 3.4 | 47% | 29% |
| RB | 3 | 3.0 | 47% | 23% |

Age matters most for RBs: a startable RB aged 28-30 has a 33% chance of being alive three seasons
later, against 56% for one aged 24 or younger. QBs barely age before 31.

**From the rookie season**, draft capital dominates (log-rank test p < 2e-16): first-round picks
average 3.8 alive seasons, second-rounders 2.7, third-rounders 2.0, rounds 4-7 1.3 and undrafted
players 1.1.

## Step 3: survival models for S(t)

| Model | What it is (PA/ATPA terms) |
|---|---|
| Kaplan-Meier by position | Baseline with no player detail |
| **Discrete-time logistic hazard GLM** | A logistic regression on one row per player per future season at risk; the hazard h(t) = P(career ends in season t, given alive until then); S(t) = product of (1 - h(k)) |
| Cox proportional hazards | Semi-parametric; standard errors clustered on player |
| **Survival random forest** (ranger, log-rank splits) | Non-parametric comparison |
| **Blend** | 50/50 average of the GLM and the forest. This is what the score uses |

Held-out test, landmarks 2018-2024 (4,248 player-seasons), models fit on 2007-2017:

| Metric | KM | GLM | Cox | Forest | Blend |
|---|---|---|---|---|---|
| C-index, all players | 0.557 | 0.954 | 0.917 | 0.946 | 0.954 |
| C-index, startable players | 0.561 | 0.713 | 0.701 | 0.748 | 0.741 |
| AUC, alive after 3 seasons | 0.609 | 0.942 | 0.938 | 0.947 | 0.947 |
| Brier, alive after 3 seasons | 0.099 | 0.057 | 0.057 | 0.055 | 0.055 |
| Brier, alive after 5 seasons | 0.060 | 0.043 | 0.044 | 0.043 | 0.041 |

- The very high all-player C-index is mostly the easy part: telling a starter from a deep backup.
  The **startable-only** row (about 0.74) is the honest measure of how well the model separates
  one fantasy starter's shelf life from another's.
- Calibration is close: predicted minus actual survival is within 1 to 3 percentage points at
  every horizon (`plot_survival_calibration.png`).
- A stricter split, where the training outcomes also stop at 2017, gives almost the same numbers,
  so there is no leakage from later seasons.
- **Why the Cox model lost:** the proportional hazards assumption fails badly (cox.zph global
  p < 1e-200; "startable this season" is the worst offender). Being startable now protects a
  player a lot next season but much less four seasons out. The discrete-time GLM handles this with
  a `t x startable` interaction, which Cox cannot.
- Survival forest note: ranger reports S(t) = exp(-cumulative hazard), which overstates survival
  when one-season hazards are large (many backups die after one season). The code rebuilds S(t)
  as a product of one-season hazards instead, which fixed a 24-point calibration bias.

Hazard GLM coefficients are in `dv_hazard_glm_coefficients.csv` (odds ratios), and the forest's
permutation importance is in `dv_rsf_importance.csv` (years in the league, best recent season,
last season's production and draft round matter most). The production inputs overlap a lot
(this season's total, per-game pace and best recent season move together), so single GLM
coefficients are hard to read on their own. `dv_07_effect_sizes.R` asks the fitted models a
simpler question instead: for today's startable players, what happens to the score if one fact
changes and everything else stays the same?

| Change | QB | RB | WR | TE |
|---|---|---|---|---|
| 2 years older | -3% | -23% | -24% | -9% |
| +50 points above replacement this season | +25% | +33% | +30% | +63% |
| +50 points on his best season of the last three | +21% | +19% | +18% | +22% |
| Same points, but missed 1 game in 4 | -19% | -15% | -15% | -13% |
| Had gone undrafted | -21% | -17% | -20% | -18% |

Draft capital still matters years later, even after production is known, and missing games is
treated as a warning sign on its own.

## Step 4: production model, E[PAR+ | alive]

PAR+ is zero in 45% of alive seasons and has a long right tail, the same shape as insurance
losses (many policies with no claim, a few large claims). So the main model is a **Tweedie GLM**
with a log link (the compound Poisson-gamma "pure premium" model), compared with a random forest.

Held-out test, alive seasons from landmarks 2018-2024:

| Model | RMSE | Spearman | Gini | Mean bias |
|---|---|---|---|---|
| Tweedie GLM, p = 1.5 | 49.6 | 0.527 | 0.589 | +3.7 |
| Random forest | 49.3 | 0.544 | 0.597 | +0.6 |
| **Blend (used)** | **48.7** | **0.549** | **0.611** | +2.2 |
| Naive: last season repeats | 65.9 | 0.402 | 0.466 | +8.1 |

The model beats "he'll do what he did last year" at every horizon, mainly because it expects hot
seasons to cool off and old players to decline (`plot_production_aging_curves.png`).

## Step 5: backtest of the full score

For landmarks 2018-2022, models fit only on 2007-2017 predicted each player's PAR+ over the next
three seasons. That was compared with what actually happened (`dv_value_backtest_*.csv`).

| Players | Spearman, model | Spearman, naive (3 x this season) | RMSE model | RMSE naive |
|---|---|---|---|---|
| Startable at the time (480) | **0.583** | 0.460 | **118** | 196 |
| QB startable | 0.552 | 0.435 | 151 | 224 |
| RB startable | 0.538 | 0.400 | 105 | 213 |
| WR startable | 0.564 | 0.384 | 109 | 180 |
| TE startable | 0.576 | 0.538 | 91 | 135 |
| Everyone (3,064) | 0.551 | 0.646 | **56** | 84 |

- For the players dynasty managers actually trade, the model ranks the next three seasons
  clearly better than the naive rule and roughly halves the error.
- Across everyone, the naive rule ranks better. It puts every current starter above every
  non-starter, while the model sometimes puts a young non-starter with upside above an old
  starter, and those bets lost more often than they won in 2018-2022.
- **Actual vs expected (A/E):** the top decile came in at A/E = 1.00 and the next two at 0.75.
  The lower deciles are over-predicted in relative terms, but those are players expected to
  score only 1 to 8 PAR points, so the miss is small in points. Overall the model was 11% high.

## Step 6: opening the black box

- **PDP / ICE by age** (`plot_pdp_ice_age.png`, `dv_pdp_age.csv`): for today's startable players,
  moving from age 25 to 31 cuts the average score by 10% for QBs, 57% for RBs, 56% for WRs and 36%
  for TEs. Expected alive seasons for a startable RB fall from 3.6 at 25 to 2.4 at 31.
- **PDP of this season's pace** (`plot_pdp_pace.png`).
- **Effect sizes** (`dv_effect_sizes.csv`): see the table under step 3.
- **SHAP** (`dv_shap_top25_why.csv`, `plot_shap_importance.png`): kernel SHAP splits each top-25
  player's score into contributions from each input, starting from the average player (score
  2.3). Across the top 25, the biggest movers are per-game pace above replacement (28 score
  points on average), best season of the last three (20), position (15, mostly the QB boost in
  superflex), and season-total pace (12). Age moves older players down by about 19 to 25 points
  (Goff, Mahomes, Prescott). One caution: the production inputs move together, and kernel SHAP
  sometimes splits credit between them oddly (for example a negative "season pace" next to a
  large positive "per-game pace"). Read the production rows as one group.

## The board

`dv_dynasty_value_board.csv` has all 657 active players. Players with 3+ games in 2026 are valued
from their 2026 pace; the other 212 (injured, suspended or not yet playing) are valued from their
2025 season, starting one season further out.

Top 10: Josh Allen 100, Joe Burrow 94.7, Drake Maye 90.6, C.J. Stroud 82.1, Jordan Love 79.3,
Trevor Lawrence 79.2, Jaxon Smith-Njigba 78.3 (WR1), Brock Purdy 76.4, Lamar Jackson 60.5,
Jayden Daniels 57.1. Top RB: Jahmyr Gibbs (23rd). Top TE: Trey McBride (33rd).

Tiers on the score: Cornerstone 70+, Core 45-70, Starter 25-45, Flex 10-25, Depth under 10.

## Caveats

- **Superflex by design.** QB24 as the startable line, plus QBs' long careers, puts 12 QBs in the
  top 20. Use positional ranks for a 1QB league until a QB12 version exists.
- **2026 is a partial season** (through week 9), pro-rated to 17 games. A player having a bad or
  injured 2026 is one bad season from "career over" under the two-in-a-row rule, so his score can
  swing a lot once the season finishes. Re-run after week 18.
- **Players valued from 2025** (under 3 games in 2026) are not penalized for 2026 yet, because we
  do not know how 2026 will count. Treat their scores as optimistic.
- **Very old QBs** (40+) are extrapolations: the age curves are fit on few players that old.
- The death rule has a comeback blind spot: about a quarter of veterans who "die" later have
  another startable season. Their later seasons are not counted.
- Points are full PPR with the nflverse default scoring (4-point passing TDs).
