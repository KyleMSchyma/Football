# Football Prospect Models: Plain-English Guide

This guide explains what each model predicts, what the final model is, what drives it,
and how to explain it to someone who doesn't do statistics. The full math, every number
and every caveat are in [`MODELS_TECHNICAL_REFERENCE.md`](MODELS_TECHNICAL_REFERENCE.md).

## The one-paragraph version

These models try to answer one question at three moments in a young player's career:
"How likely is he to become a useful fantasy starter in his first three NFL seasons?"
Before the draft we only have college stats. On draft night we also know where he was
picked. After his rookie year and his second year we know how the NFL actually used him.
The big lesson: **each new piece of real information beats the clever stuff that came
before it.** Draft position beats college stats, and a player's actual NFL usage beats
draft position.

## Shared ideas (explain these once)

- **Tiers.** "Hitting" means at least one season in years 1-3 inside a tier. For QBs and RBs
  the tiers are top 8, top 16 and top 24 at the position. For TEs they are top 6, top 12
  and top 18 (since 2026-11-12: a 12-team league starts only 12 TEs, so a TE16 or TE24
  season is below replacement). For WRs they are top 12, top 24 and top 36 (more WRs start
  in fantasy lineups).
- **Fair testing.** Each draft class is predicted only with classes whose results were
  already known at the time, like a forecaster who is not allowed to peek at the future.
  This is called rolling-origin testing, and it's the honest score.
- **Always compare to a simple benchmark.** Every model is measured against "just use the
  draft pick." If a fancy model can't beat that, we say so.
- **Elastic net.** The workhorse model. Think of it as a regression that is told "use as
  few inputs as you can, and keep their effects modest." It keeps the model from
  over-reacting to quirks in a small sample, which matters when there are only about 14
  draft classes to learn from.
- **Probabilities that make sense together.** The models are built so a player's chance
  of a top-8 season can never be higher than his chance of a top-24 season.

## 1. Rookie draft-time models (WR, QB, RB, TE)

**What they predict.** For each drafted player: fantasy points over his first three
seasons, his chance of reaching each tier, and a "finish score" (his three yearly
position ranks added up, lower is better).

**Final model in plain words.** An elastic net that starts from draft position (the log of
the pick number, because the gap between picks 1 and 10 matters far more than between 150
and 160) and lets college production, age, athletic testing, recruiting and the team's
open opportunity nudge the projection up or down.

**Key drivers.**

- Draft pick, by a wide margin, at every position.
- WR: younger breakout age and younger draft age, career receiving yards, recruiting.
- QB: completion rate, low interception rate, touchdown rate.
- RB: vacated touches on the new team, early declaring.
- TE: recruiting rating, open targets on the new team, share of team catches, a fast 3-cone.

**The honest result.** Once you know the draft pick, college and combine data add
nothing you can measure. For QB total points and the RB top-24 model, adding them made
results slightly worse. NFL teams already bake the college film and stats into where they
pick a player.

**How to explain it.** "NFL front offices are the best scouts we have. Their draft pick
already contains almost everything the college numbers say, so the pick is the
projection. The college stats only help a little at the margins."

## 2. Tier ladder and finish score

**What they predict.** The chances of the player's best season landing in each tier
(for example WR1, WR2, WR3), with the chances nested so they always add up sensibly.

**Final model in plain words.** An ordered model: picture a ladder with rungs at top 8,
top 16 and top 24 (top 6, 12 and 18 for TEs; top 12, 24 and 36 for WRs). One score per player says how high up the ladder he's likely to
climb. The two-step finish score first asks "will he ever be a fantasy starter?" and then
"if so, how good?"

**How to explain it.** "Instead of one number, you get a ladder: a 30% shot at elite, a
50% shot at being a solid starter, a 70% shot at being at least a flex play."

## 3. Value score and Day-3 "hidden talent"

**What it measures.** How much more the college-only model likes a player than his draft
slot does. Used to build Day-3 stash lists.

**The honest result.** It's borderline at best. For WRs the most-liked third of Day-3
picks beat their slot by about 50 points over three years, but the uncertainty range
crosses zero. For RBs it went the wrong way. Simply taking the earliest Day-3 picks found
more future starters than the college "hidden" score did. Tyreek Hill, Puka Nacua and
Hunter Renfrow all ranked near the bottom of their Day-3 class on college data.

**How to explain it.** "Stash lists are lottery tickets. College stats can't reliably
find the late-round star."

## 4. Year-2 model (after the rookie season)

**What it predicts.** The chance of a tier season in years 2-3, using how the NFL actually
used him as a rookie: snaps, target or touch share, late-season role, efficiency.

**Final model in plain words.** An elastic net on rookie usage, compared against "draft
pick plus rookie fantasy points."

**Key drivers.** Target share and snap share (especially over the last six games), plus
rookie points. For QBs: low interception rate, late-season starts, accuracy over expected.
For RBs: receiving share, snap share, yards per carry.

**The result.** This is the strongest signal in the whole project. For QBs the usage
model clearly beats rookie points alone. For WRs and RBs it ties them. For TEs, rookie
points alone are slightly better. After one season, the rookie-year Day-3 stars (Hill,
Renfrow, Mooney, St. Brown, Nacua) all show up near the top of their class.

**How to explain it.** "One NFL season tells you more than three college seasons. A
rookie who played most snaps and drew a big target share is a buy, even if his fantasy
points were meh."

## 5. Year-3 model (after year 2)

**What it predicts.** The chance of a tier season in year 3.

**Final model in plain words.** The same usage approach with year-1 and year-2 data.

**The result.** Year-2 fantasy points dominate at every position (QB top-24 accuracy about
0.99 on the AUC scale). Usage ties points, but it's useful for reading the board: rising
target share and late-season snaps flag year-3 risers (for TEs the biggest drivers are
target share and WOPR, a blend of target and air-yards share).

**How to explain it.** "By year three, what he did last year is most of the story. Usage
trends tell you who's trending up or down inside that story."

## 6. Undrafted free agents

**What we found.** Undrafted hits are rare (RB and TE about 4% vs 11-12% for rounds 4-7;
no undrafted QB reached the top 24). The college model doesn't find them; the rookie-usage
model does once they play. Adding them to training changes no conclusions.

## 7. Buy / sell lists

**What they are.** Simple rules on top of the boards. A "buy" is a player the usage model
likes more than his fantasy points suggest (big snap or target share, late-season growth).
A "sell" is one whose points ran ahead of his usage (touchdown-heavy, falling late-season
snaps). "Sell" doesn't mean bad; it means the market may be paying for points the role
doesn't support.

## 8. Pre-draft (college-only) model and class grades

**What it predicts.** Before anyone is drafted, each college player's chance of a top,
top-two and any-tier season in his first three NFL years. It's trained on every
draft-eligible college player (about 900 to 2,800 per position), so "never made the NFL"
counts as a miss. Uses no draft pick and no combine.

**Final model in plain words.**

- QB, RB: an elastic net on college production, age, recruiting and conference level.
- TE: the average of an elastic net, a random forest and xgboost on the same inputs. The
  elastic net was the TE choice until the TE tiers moved to 6/12/18 (2026-11-12); with
  only 8 top-6 hits in the test years the average ranked them better, and the two tie on
  the any-tier (TE18) model.
- WR: a plain logistic regression on five inputs (receiving yards, dominator share, years
  out of high school, recruiting rating, Power 5). It tied the elastic net, and the
  simpler model wins ties.
- Random forests, gradient boosting (xgboost) and an average of models were all tested
  and lost everywhere except TE. With only a few dozen hits per position, simpler models are more reliable.

**Key drivers.** Youth (fewer years out of high school), recruiting rating, Power 5, and
the position's production: QB accuracy, TD rate and low INT rate; RB touchdown share and
receiving; WR receiving yards and dominator share; TE career receiving yards and
recruiting rating.

**FCS adjustment.** FCS stats are shrunk toward an FBS scale. Players who transferred from
FCS to FBS saw their production share drop more than FBS-to-FBS transfers, which gives a
factor of about 0.69 for receiving and rushing and 0.79 for passing. Conference labels
were tested as extra inputs (including a credibility-weighted conference effect) and did
not help.

**Class grades.** Add up the expected tier hits of each class's top prospects (QB 12, RB
20, WR 32, TE 15) and grade against 2010-2023 (A = top 10%, F = bottom 10%). Current:
2027 projected A− overall, 2026 F, 2025 A, 2024 C. Class grades track reality modestly
(correlation about 0.5 for the overall grade), so trust the overall grade more than any
single position's.

**How to explain it.** "It's a scouting report built only from the box score and recruiting
rankings. It finds real signal (it ranks future hits well above average) but the NFL draft
still knows more."

## 9. All-time pre-draft player grades

**What it is.** A letter grade (A+ to F) for every drafted QB, RB, WR and TE from 2010-2026,
plus the top 2027 prospects, from the college-only model. Historical grades are scored by
a model that never saw that class, so they're honest.

**The result.** A-range players hit about 59% of the time, B about 31%, C and below about
14%. The grade separates the top well but not the bottom (C, D and F hit at similar
rates). Draft slot is still more accurate, and the grade only adds to draft slot for QBs.
Famous misses: Johnny Manziel (A+), N'Keal Harry (A+); famous low grades that hit: Josh
Allen (F), Cooper Kupp (F), Tyreek Hill (D), George Kittle (D).

**How to explain it.** "An A means the college résumé looks like past hits. It's a
strong flag at the top, not a guarantee, and a low grade doesn't rule a player out."

## 10. All-time post-draft player grades

**What it is.** The same A+ to F board for every drafted player from 2010-2026, but built
from the post-draft version of each position model (college profile plus draft pick and
landing spot). It sits next to the pre-draft grade, so you can see how much draft capital
moved each player and each class. 2027 isn't on it because nobody has been drafted.
It lives in its own folder, `PostDraft_Model/`.

**The result.** Post-draft A-range players hit 69% of the time, B 35%, C 9% and D/F 4%.
Unlike the pre-draft grade, it separates the bottom too. It also ranks players within a
class better (average rank correlation 0.49-0.61 vs 0.31-0.45). Big risers include Carson
Wentz (F to A-), Doug Martin (D to A) and Travis Kelce (C to A-); big fallers are mostly
late picks with strong college numbers, such as Alex Collins (A- to D).

**How to explain it.** "The pre-draft grade is what the college stats say. The post-draft
grade adds what the NFL said with its pick. When they disagree, history sides with the
pick more often, which is why a pre-draft A who goes in round 6 usually fades."

## 11. Comparing rookies across positions: the Value column

**What it is.** Grades are ranks *within* a position (an A QB and an A TE are both near the
top of their own position, not worth the same). The pre-draft and post-draft boards now show
**Value**: each player's expected dynasty trade value on the trade-values page's 100,000-point
scale, in the default league (12 teams, superflex, PPR, 2 RB / 3 WR / 1 TE). The All tab is
sorted by Value.

**Final model in plain words.** Chance of each fantasy tier × what past drafted players in
that tier scored over their first four seasons above the replacement starter (discounted 15% a
year, adjusted for age), added up. It's the same math as the 2027 rookie-pick prices, so a 2027
prospect's Value equals his pick value.

**The fix it needed.** The college-only model's chances include the risk of going undrafted,
so among players who were drafted they ran about a third too low (16% expected any-tier vs 25%
actual). A small logistic recalibration per position and tier, fit on drafted players'
out-of-class predictions, fixes the level without changing anyone's order. It doesn't add
accuracy (Brier changes are within noise except WR36, which improves); it makes the chances
honest for a player we already know will be drafted. Drafted and mocked players use the
post-draft chances instead. The original grades don't change.

**What we found.** On the 2027 board, ranking by Value instead of percentile keeps 18 of the
top 30 but moves QBs up (13 of the top 30, because of superflex) and TEs down (one, Trey'Dez
Green), since a TE tier season is worth fewer points over replacement.

**How to explain it.** "The grade says how good he is for his position. Value says what he's
worth in a trade, so you can compare a running back with a quarterback."


## Course concepts to point to (ATPA / PA)

| If someone asks... | Point to |
|---|---|
| "How do you know it isn't overfit?" | Rolling-origin validation by draft class; fixed benchmark; bootstrap confidence intervals |
| "Why not a fancier model?" | Model comparison (ATPA 4.5): random forest and xgboost lost to a penalized GLM on small samples |
| "Why does the model say what it says?" | Permutation importance, PDP/ICE and SHAP (ATPA 4.3) |
| "What about missing college data?" | Leakage-safe imputation with missing flags (ATPA 3.7a) |
| "Does conference strength matter?" | Credibility / mixed-model test (ATPA 3.3), no gain |
| "Why are probabilities nested?" | Ordered (cumulative logit) models and forced monotone probabilities |
