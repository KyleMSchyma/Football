# Fable Review

An end-to-end review of the Prospect Actuary process, written 2026-11-13: the rookie models,
the trade values, the validation, the weekly refresh and the public site. It is a review
only. No model, value or page was changed.

**What was reviewed.** `MODELS_TECHNICAL_REFERENCE.md`, `MODELS_GUIDE.md`, the scripts and
output files in every model folder (most closely `Trade_Values/dv_10`, `dv_11`, `dv_13`,
`dv_common.R` and `weekly_refresh/`), and every page of the live site rendered at desktop
and phone width.

**What was not done.** Nothing was rerun, because the data cache lives on the PC. Where a
finding says "likely cause", that is a hypothesis to test, not a result.

---

## The short version

The foundations are better than most public fantasy work. The models are tested the way
they would have been used (class by class, no peeking), every model is compared with "just
use the draft pick", and the docs say so plainly when the simple benchmark wins. That
honesty is the brand, and it is worth protecting.

The weak spots are mostly in the newest part, the trade values, which were built quickly
and have had less testing than the rookie models. In priority order:

| # | Finding | Why it matters | Effort |
|---|---|---|---|
| 1 | Players and rookie picks are calibrated to different standards | Every pick-for-player trade in the calculator is tilted about 15-20% toward the player side | Medium |
| 2 | The values have no idea who is a starter | Backup quarterbacks rank about 100-170 spots above the market | Medium |
| 3 | The post-draft model penalizes its own best input | A likely accuracy gain is being left on the table for RB, WR and TE | Small |
| 4 | The year-2 and year-3 usage models are the best thing in the project and are not used | The dynasty values and the site ignore the strongest signal you have | Medium |
| 5 | The pre-draft "youth" effect is partly a selection effect | Non-mocked 2027 underclassmen, and the picks priced from them, are overstated | Medium |
| 6 | Published hit rates use the optimistic test, and three pages disagree on the number | Small overclaim on the home page | Small |
| 7 | There is no untouched holdout and no public track record | Every reported score is a little optimistic; a track record would fix that and sell the site | Small |
| 8 | Old quarterbacks age too slowly | Stafford (38.6) is given a 24% chance of playing at 42 | Small |
| 9 | Values look more precise than they are | A five-digit number hides a wide error band | Small |
| 10 | The refresh pushes to the live site with no output checks and no failure alert | One bad data pull publishes itself | Small |

Each is explained below, followed by smaller items, presentation ideas and things worth
adding.

---

## What is already strong

Keep these, and say them louder on the site.

- **The benchmark discipline.** Pick-only is fit as a real model and shown beside every
  result. The docs report that college data adds nothing measurable after the pick, and
  that it is significantly worse in places (QB points, RB top-24, RB ladder, TE top-6).
  Most public models never run this test.
- **Rolling-origin validation by draft class**, with a check in code that no fold trains
  on the test class or later.
- **Leakage-safe preprocessing.** Medians, missing flags and the PCA are fit inside each
  training fold.
- **Paired bootstrap intervals** on every model-versus-benchmark difference, and ties are
  called ties.
- **Simple models win ties.** The WR pre-draft model is a five-input logistic regression
  because it tied the elastic net.
- **The dynasty value is a genuine actuarial construction**: discount × survival ×
  expected games × expected excess over a retention (stop-loss). It is a life annuity with
  a deductible, and it is the most original idea on the site.
- **The browser math is reconciled to R** (`dv_15`), to within a few points on a 100,000
  scale. That is real model governance.
- **Negative results are published**: the Day-3 hidden-talent score, the conference test,
  usage and PPA features, the hurdle model.

---

## Priority findings

### 1. Players and rookie picks are on different levels

**What I found.** The dynasty backtest (`dv_v4_backtest.csv`) shows predicted value running
ahead of what players actually produced:

| Group | Predicted ÷ actual |
|---|---|
| QB | 1.32 |
| TE | 1.22 |
| WR | 1.18 |
| RB | 1.12 |
| All players, default league | 1.20 |
| Across the five league setups | 1.16 to 1.28 |

Player values are left at that level. Rookie picks, on the other hand, are multiplied by
1.11 in `pick_factor()` so that past picks match what they actually produced. So picks are
calibrated to reality and players sit about 20% above it, and the calculator adds the two
on one scale. Relative to realized production, a pick is priced roughly 15-20% too cheap
against a veteran.

Two related points:

- The 1.11 multiplier comes from 84 players (12 slots × 7 classes) whose outcomes are
  heavy-tailed, and the 2020-2022 classes have shortened windows. No interval is reported.
  I have not computed one, but with a sample like this a range as wide as 0.9 to 1.3 would
  not be surprising.
- The site guide says the totals ran "13-21% high". The current file says 16-28%. The
  guide number looks stale from before the window was extended to 2031.

**Why it matters.** The whole promise of the calculator is that values add across players
and picks. That only holds if both sides are measured against the same yardstick.

**What to do.**

1. Build a calibration table for players: predicted versus actual value by decile of
   predicted value and by position. This shows whether the 20% is everywhere or only in
   the tail.
2. Apply one calibration standard to both sides, either a per-position multiplier for
   players fit on earlier snapshots, or drop the pick multiplier and calibrate everything
   together.
3. Bootstrap the pick multiplier by class and report the interval.

**Likely causes to test** (hypotheses): the projection is a one-year model fed its own
output five times, although it was fit on noisier inputs than the predictions it is given;
the uncertainty inside the stop-loss grows like a random walk (`sig × sqrt(t)`) while
real PPG reverts to the mean, which inflates upside for everyone; and "still playing" means
any game at all. A direct model for each horizon (year y features predicting year y+2,
y+3 and so on) would avoid the first two and is a clean comparison.

### 2. The values do not know who is a starter

**What I found.** A "game" is any week with a stat line, and availability is games with a
stat line divided by team games. Nothing tells the model who starts. The result shows up
on your own Market Check page: seven of the ten biggest "we're higher than the market"
names are quarterbacks, most of them backups.

| Player | 2026 games | 2026 PPG | Credible PPG | Our rank | Market rank |
|---|---|---|---|---|---|
| Justin Fields | 1 | −2.1 | 13.1 | 93 | 260 |
| Marcus Mariota | 3 | 11.5 | 13.4 | 105 | 263 |
| Tua Tagovailoa | 1 | −0.6 | 12.8 | 102 | 254 |
| Jameis Winston | 7 | 10.5 | 11.3 | 135 | 252 |

Three things stack up for these players: the draft-slot prior (Fields' "potential" is 16.4
PPG), a credible PPG that lands right at the QB replacement line of 13.4, and the stop-loss
upside over six seasons. In superflex that adds up to a top-100 asset who is not playing.

The same gap is behind the known injury item. In the redraft file, Davante Adams, Mike
Evans, DeVonta Smith and Jalen Hurts are all flagged `missed_last2` and still carry 20,000
to 34,000 points at 54-71% availability, because the flag is computed and never used.

**What to do.** Add a role layer before the value formula:

- QB: a start is a game with 15 or more attempts (already defined in the QB year-2 model).
  Value = P(starts) × value as a starter.
- RB, WR, TE: snap share from `load_snap_counts`, which the rookie models already use.
- Injuries: weekly rosters are already pulled by the refresh, and their status field shows
  who is on a reserve list. Cut the rest-of-season games for those players.

This is the same machinery as the handcuff idea already on your list (value as a starter ×
chance of starting). Build the role layer once and both come out of it.

### 3. The post-draft model shrinks the draft pick along with everything else

**What I found.** No script sets `penalty.factor`, so in every elastic net and in the
`ordinalNet` ladder, `log_pick` is penalized exactly like the weak college inputs. The
penalty is chosen to quiet twenty noisy features, and it pulls the one strong feature
toward zero at the same time. That is a plausible reason the post-draft model loses to
pick-only for RB, WR and TE even though it contains the pick.

**What to do.** Three cheap experiments under the existing rolling-origin test:

1. Leave `log_pick` unpenalized (`penalty.factor = 0` for that column).
2. Fit pick-only first, then fit the elastic net to what it misses (pick as an offset).
3. Use `lambda.1se` in place of `lambda.min`. With 14 classes the minimum of the CV curve
   is noisy, and the one-standard-error rule is the standard small-sample choice.

If none beats pick-only for RB, WR and TE, the honest move is to price those positions
from pick-only and keep the college adjustment for QBs, the one position where the
likelihood-ratio test says it adds something (p = 0.004 for QB24).

### 4. The strongest models in the project are not used

**What I found.** The year-2 and year-3 usage models have the best results anywhere in the
repo (rolling AUC 0.85 to 0.96, and the QB usage model significantly beats rookie points).
They found Hill, Nacua, St. Brown and Renfrow after one season. But:

- They are not on the site at all. The buy and sell lists live only in READMEs.
- The dynasty values do not use them. For a second-year player the value formula knows his
  draft slot and his fantasy points, and nothing about target share, snap share or
  late-season role.

**What to do.** Publish the buy and sell lists as a page (it is the most shareable content
you have). Then feed the year-2 and year-3 tier probabilities into the dynasty value for
players in their first three seasons, the same way the 2027 picks are priced from tier
probabilities. Your planned Bühlmann-Straub change (prospect-model PPG as the credibility
prior) is the natural place to do it: use the usage model as the prior for young
players, not only the draft-time model.

### 5. The pre-draft "youth" effect is partly a selection effect

**What I found.** In the training pool, a player's class is the year he left school. So a
player three years out of high school appears in training only if he declared early, and
players who declare early are the ones the NFL already wanted. The model learns "young at
exit means good" (for WRs, each extra year multiplies the odds by 0.46), and part of that
is the declare decision, which is itself a signal of draft stock.

For 2027 nobody has declared, and every eligible underclassman is scored as if he had. An
ordinary third-year player gets the bonus that in training belonged to players good enough
to leave. The technical reference already notes that the declare model understates elite
juniors and is not used.

**Why it matters.** The top 30 are protected because they are priced from the mock. Below
that, the board and the round-2 and round-3 picks rest on these probabilities. It may also
explain why the pick curve is almost flat from 1.07 (22,642) to 2.09 (16,716): a large pool
of similar-looking young prospects.

**What to do.** Either label the 2027 pre-draft numbers clearly as "if he declares", or
restrict the pick pool to players who appear on a public big board, or (best) fit a version
on the eligible-pool view that already exists in `pd_01` so that the training rows match
how 2027 is scored.

### 6. Published hit rates use the optimistic test, and the numbers disagree

**What I found.**

- The guide says rolling-origin is "the honest score". The grade hit rates on the home
  page come from leave-one-class-out, which trains on later classes. The technical
  reference itself calls that optimistic. For WRs the gap is real: post-draft hit AUC is
  0.819 leave-one-out and 0.752 rolling; pre-draft 0.713 versus 0.651.
- The home page says the hit rates are "honest out-of-sample results". True in the sense
  that the model never saw that class, but it did see the future.
- The post-draft A-range hit rate is 69% on the home page and in `MODELS_GUIDE.md`, and
  66% in the site guide and the technical reference.

**What to do.** Publish the rolling-origin hit-rate-by-grade table (2016-2023) beside the
current one, change the wording to "a model that never saw that class", and generate every
published number from one CSV so pages cannot drift apart.

### 7. No untouched holdout, and no public track record

**What I found.** The 2016-2023 rolling folds were used to choose models, tier cutoffs, the
drafted recalibration, the credibility constants and the pick multiplier. The TE change is
the clearest case: the tiers moved to 6/12/18, then the model choice was re-run and
switched to the ensemble on the strength of 8 top-6 hits. Each choice is defensible. Taken
together, the test set has been looked at many times, so every reported score is somewhat
flattering. The credibility constants are also fit and scored on the same seasons
(2016-2025), and those constants are then used inside the dynasty backtest for 2016-2020.

**What to do.** This is cheap and doubles as marketing:

- Freeze the 2024, 2025 and 2026 class predictions with a date, and score them every
  January on a public **Track Record** page. Those classes are a true holdout.
- Archive each week's trade values as a dated file. Today the refresh overwrites them.
- Log the Market Check disagreements each week and score them later. "When we disagreed
  with the market, who was right?" is the single most convincing test of the trade values,
  and the only one that measures edge over the market, not over a naive baseline.

### 8. Old quarterbacks age too slowly

**What I found.** Matthew Stafford (38.6) is given a 24% chance of playing in 2030 at 15.4
PPG. Kirk Cousins (38.0) gets 32%. Aaron Rodgers (42.7) gets 3%, which is sensible. The age
spline has its boundary at 38 and is linear beyond it, and the only data past 39 come from
Brady, Brees and Rodgers, who are survivors by definition.

**What to do.** Force the survival curve to be non-increasing with age after about 30, or
pool everyone 37 and older. More generally, survival and aging have never been validated on
their own: add a table of predicted versus actual "still playing t years later" by age band
and position, and projected versus actual PPG by age band.

### 9. Values look more precise than they are

**What I found.** The site shows 89,355. The redraft backtest error is about 19-26 fantasy
points of rest-of-season value per player, and the dynasty totals run 20% high. The calculator declares a
winner on any difference.

**What to do.** Round to the nearest 100 or 500. Show tier breaks or a range. In the
calculator, call a trade "too close to call" inside a band taken from the backtest error
(for example, totals within 10%). Insurance pricing has the same convention: a point
estimate comes with a range.

### 10. The refresh publishes without checking its own output

**What I found.** `refresh.sh` has good guards on the repo state, the old dynasty page and
the API key. It has none on the numbers. The only data check is that the pull has more than
1,000 rows and has not gone backwards a week. Results go straight to the live site, and a
failure writes a text file on the PC that nobody is told about.

**What to do.**

- Gate the push on output checks: the newest week has every team that played, no missing
  values, replacement lines and the pick multiplier inside a sensible range, and the top 50
  has not turned over by more than a set amount.
- Make `dv_15` (the browser-versus-R reconciliation) part of the gate.
- Send yourself a notification on failure.
- Write a "biggest movers" file each week. It is a sanity check and ready-made content.
- Longer term, a scheduled GitHub Action would remove the dependency on the PC being on.

---

## Smaller statistical points

- **Credibility constants are fit at week 9 only** and used every week through week 18. In
  theory k should not depend on the week. Fit it at weeks 4, 6, 12 and 14 to confirm. If k
  moves a lot, the blend is missing something (most likely a role change).
- **k4 for WRs is 186 team games**, which means a receiver's own injury history is almost
  ignored and the position average does the work. That is a finding worth stating on the
  site: "injury-prone" has very little predictive value for WRs in this data.
- **The classic Bühlmann k** (EPV ÷ VHM) is computed in `dv_10` and never reported. Showing
  it beside the fitted k is a good teaching point for the guide.
- **Credibility on points only.** Points are noisy because touchdowns are. Targets, carries
  and snap share settle faster. A credibility blend on opportunity, then converted to
  points, should beat one on raw PPG. Worth one test.
- **The 100,000 scale is tied to the top player.** If he gets hurt, everyone else's number
  rises though nothing about them changed, and week-to-week comparisons break. Anchor the
  scale to something stable, such as the average of the top 12.
- **The 15% discount rate is a judgment call with no sensitivity shown.** `dv_common.R`
  already defines 0% and 30% alternatives. Put them on the site as Contending / Balanced /
  Rebuilding. It is a real feature and it makes the assumption visible.
- **Section 3.8 mixes in-sample and out-of-sample numbers.** The interpretation table
  reports in-sample AUC (0.91-0.95) and in-sample permutation importance. Label them or
  recompute on held-out predictions.
- **Single-position class grades are not statistically supported.** Their correlations with
  reality have p-values of 0.13 to 0.22. Only the WR and overall grades clear the bar.
  Either show the overall grade only or mark position grades as low confidence.
- **TE top-6 rests on 14 hits**, with none in four of the 14 classes. Any TE top-tier
  probability is close to a base rate with a small tilt.
- **Stop-loss gives every one of the 566 players a positive dynasty value.** About 12% of
  all value sits below rank 150. That is fine in principle, but it is worth checking
  against realized value in that range as part of the calibration table in finding 1.

---

## Pipeline and repository

- **The repo is a copy, not the source.** Scripts live in PC folders and the refresh copies
  them in. Paths such as `../Football2_PreDraft` mean a fresh clone cannot run. Pick one
  home for the code.
- **The technical reference has no trade-values section.** Credibility, aging, survival,
  replacement lines and pick pricing are documented only in code comments and the site
  guide. They deserve their own section with the backtest tables.
- **Pin package versions** (`renv`). A column rename in nflreadr would otherwise break the
  refresh or, worse, change results quietly.
- **Housekeeping.** `README.md` is one line. Backup scripts
  (`wr_phase1_data_build_backup_v1/v2`, `backup_qb_*`) can go, since git keeps history.

---

## Presentation

The writing is already clear, and the "How to explain it" lines are the best sentences on
the site. The suggestions below are about order and emphasis.

1. **Lead with an answer, not a method.** The home page opens with how the site is built.
   A first-time visitor wants something to look at: the top five 2027 prospects, this
   week's biggest value movers, one trade example. Put the method one click down. Your
   planned three-level split (quick look, deep dive, research) is the right fix and is the
   highest-value presentation change.
2. **Show a calibration chart.** "When we said 30%, it happened 28% of the time" is the
   most persuasive picture you can show a non-technical reader, and you already have the
   numbers.
3. **Show the annuity.** For each player, a small bar split by season (rest of 2026, 2027,
   2028 and so on) explains at a glance why a 22-year-old and a 30-year-old with the same
   points differ. It makes the actuarial idea visible without a word of math.
4. **Add a "why this value" panel** per player: this year's PPG, his history, how much
   weight each gets, and the age curve. That is the credibility formula told as a story.
5. **Say chances the way people talk.** "About 1 in 3" beside 31%.
6. **Rename the jargon in table headers.** "Credible PPG" could be "Expected PPG" with a
   tooltip. "Still playing 2030" is good as it is.
7. **Replace the three "In development" banners** with a short, specific "Known limits"
   line once findings 1 and 2 are handled. A vague warning costs more trust than a precise
   one.
8. **Put "How to explain it" first** in each guide section, then the detail. The guide is
   long, and that line is what most readers came for.
9. **Add a limitations and reliance box**, in the spirit of ASOP 41 and ASOP 56: intended
   use, data relied on, main assumptions (15% discount, replacement lines, all prospects
   declare), and what the model does not see (role, injuries, scheme, coaching). It is
   standard actuarial practice and it fits the brand exactly.
10. **Tell users which players are not valued yet** (Jayden Higgins, Travis Hunter, Brandon
    Aiyuk), so a missing name does not look like a bug.

The site loads cleanly and has no sideways scrolling at phone width. The grade and trade
pages carry 0.4 to 0.9 MB of embedded data each, which is acceptable now and worth watching
as more is added.

---

## Worth adding

New ideas only. Items already on your list are noted where they connect.

- **A Track Record page** (finding 7). The best credibility-builder available.
- **A Buy / Sell page** from the year-2 and year-3 models (finding 4).
- **2028 rookie picks**, priced as generic early, mid and late picks from historical slot
  averages. Future-year picks are in most real dynasty trades.
- **A Contending / Rebuilding toggle** from the discount-rate alternatives already in code.
- **Value-over-time charts** per player, once weekly snapshots are archived and the scale
  is anchored.
- **An "About" page** on why an actuary's toolkit suits this problem. It is short to write
  and it is your differentiator.

Already on your list, and still good ideas: Sleeper import, the Bühlmann-Straub prior swap
(see finding 4 for a way to extend it), the three depth levels (presentation item 1),
handcuff values (see finding 2 for shared machinery) and the paywall plan. For the paywall,
keeping the default boards, Market Check and a future Track Record free is the right
instinct, because those pages are what earn trust.

---

## Suggested order of work

1. Role layer for QBs and the injured-reserve zero-out (finding 2). Most visible errors.
2. Player calibration table, then one standard for players and picks (finding 1).
3. Unpenalized-pick experiment (finding 3). An afternoon, and it may improve every
   post-draft number.
4. Refresh output checks and weekly archives (findings 10 and 7). Do this before more
   weeks are lost.
5. Wording and number fixes on the site (finding 6), then the Track Record page.
6. Usage models into the dynasty values and onto the site (finding 4).
7. The 2027 selection fix and the old-age tail (findings 5 and 8).
