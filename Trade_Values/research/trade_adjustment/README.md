# Logged values + trade-type adjustment (research only, 2026-11-24)

Kyle's proposal: log the values to make them steadier, and drop additivity only if a trade value adjustment is added
that depends on (a) the gap between each side's best asset and (b) the trade type (1:1, 2:1, 2:2, 2:3, 1:3, 3:3...).
**Nothing here is live.** Additive values (A30, A44) are unchanged.

## Data
- **Market:** 68,903 dynasty trades (Dynasty Daddy Trade Database, owner permission; Sep 8 - Nov 20 2026; SF, 10-14
  teams, 0.5/1 PPR, players only, 1-3 per side). Raw trades stay private (not in this repo). Each player gets our dynasty
  raw value from the latest snapshot on or before the trade date (`Trade_Values/history`). Last 14 days held out.
- **Realized:** simulated trades from our point-in-time history (2018-2024, weeks 3-14, dynasty top 200, the market's
  type mix, sides within 20% by our values). Realized side value = rest-of-season + next-season points over
  replacement (next season / 1.15). Fit 2018-2021, test 2022-2024.

## Systems
- `ADD`: our raw dynasty value (points over replacement), summed. The live rule.
- `LOGc`: ln(1 + raw / c), c = 5, 20, 60 raw points, summed (smaller c = more compressed).
- Adjustment: adj(type, g) = a + b g + c g^2 per type (Huber), g = ln(best asset side 1 / best asset side 2), side 1
  holds the single best asset. Verdict = ln(S1/S2) + adj.

## Scripts (run in order from this folder)
| Script | What |
|---|---|
| ta_00_trades.py | Map DD trades to our player values (needs the private raw files; writes ta_trades.pkl, not committed) |
| ta_01_fit_market.py [--fit11] | Fit the type + gap adjustment on market trades; 14-day holdout. Default leaves 1-for-1 unadjusted |
| ta_02_realized.py | Same adjustment fitted on realized points |
| ta_03_log_steadiness.py | Week-to-week steadiness of logged values (reads ../value_stability) |
| ta_04_charts.py | charts/09-12 |
| ta_05_relative.py | Splits the adjustment into "our price vs market price" and the pure trade-type premium |

## Results
1. **Logging steadies the numbers, but only by squeezing them** (chart 09, `ta_log_steadiness.csv`). Top-24 weeks with
   a 10%+ drop: live 25.6%, additive fixed unit 26.3%, log c=60 9.2%, c=20 3.9%, c=5 1.3%. Ranks and rank moves are
   identical (same projections). The #24 player goes from 40% of #1 (live) to 73% (c=20); #100 from 11% to 39%.
2. **Fitted adjustment, market holdout** (chart 10, `ta_market_holdout.csv`). Error normalized by each system's
   typical 1-for-1 miss. With type + gap adjustment: additive 0.23 (1v2), 0.23 (2v1), 0.29 (2v2); log 0.35-0.62.
   Additive + adjustment beats log + adjustment in every type. Unadjusted, log c=5 and c=20 miss 2v1 and 3v1 trades by 1.8-3.3 (additive 1.3-1.4).
3. **Most of that gain is not a trade-type effect** (`ta_05_relative.py`). In accepted 1-for-1s our values differ from
   the market by ~2x (median |ln ratio| 0.68), and the market's ln(S1/S2) rises ~1:1 with the gap in every type. A
   gap term per type mostly learns "market price vs our price". The pure type premium (vs a 1-for-1 at the same gap,
   chart 12 left, `ta_market_relative_premium.csv`): the side with fewer players gets +35-49% (1v2), +60-88% (1v3),
   about +35% (2v1, lone side), +15-59% (2v3, the 2 side); 2v2 and 3v3 grow with the gap (0-41%). Logs need more.
4. **Kyle's design (1-for-1 untouched, type adjustment on top) moves us AWAY from accepted trades** (chart 12 right,
   `ta_market_relative_summary.csv`): multi-player holdout error additive 0.80 -> 0.98, log c=60 0.84 -> 1.08,
   c=20 1.03 -> 1.18, c=5 1.50 -> 1.27. Our additive scale is already steeper than market straight-up prices by
   about the size of the market's package premium, so additive values already line up with package trades better
   than with 1-for-1s (0.80 vs 1.27 for 1-for-1s). Adding the premium double counts.
5. **Realized points: the adjustment adds nothing** (`ta_realized_holdout.csv`). Error 1.095 -> 1.091 additive,
   1.106 -> 1.091 log c=5; all systems ~1.09 after adjustment. Unadjusted logs are biased toward the 2-player side
   (log c=5 1v2 mean -0.38 vs realized -0.01); additive is already about fair (+0.00). Realized type premium for
   additive is ~0-10% within the sampled gaps (market: 35%+). Caveat: realized points ignore lineup slots.
6. **Throw-in cliff.** With the fitted additive 1v2 curve, 100 vs 50 is "+100% for the star side" as a 1-for-1, but
   100 vs 50 + a 5-point bench player becomes "+31%": a near-worthless add swings the verdict. Any adjustment that
   switches on by trade type needs a smooth weight for small assets.

## Reading
Keep additive values unlogged. Logging is a display choice that hides movement by compressing the scale, and it makes
multi-player trades need a large, gap-dependent correction just to get back to where additive already sits. If the goal
is steadier numbers, the steadiness candidate (k x 1.25 + EWMA 0.7 + top-10 anchor, R29/R30) cuts drops without
changing the scale. A market-style package premium is a separate "market view" question (R14, R26), not a fix for
additivity. Frame all market numbers as differences (where the market sits vs our method), not as right or wrong.

## Limits
- Market window is ~10 weeks of 2026; our values per trade are the latest weekly snapshot (up to 6 days stale).
- Realized trades are simulated, so they cover a narrower gap range than real trades (curves drawn only to the 95th
  percentile of training gaps). Realized value counts points over replacement, not roster or lineup slots.
- Picks are excluded (players only).
