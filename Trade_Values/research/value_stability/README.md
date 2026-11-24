# Value stability backtest (research only, 2026-11-24)

Write-up with charts: https://claude.ai/artifact/EAM6b8NqqNa1SB9XuimdQ3

Kyle: "One problem that I have with the top values is how often they drop. I want to set up a back test that adds a
little bit of consistency. Maybe using a BS-method (Bühlmann-Straub)?"

**Nothing live changed.** This folder tests ways to make the top redraft and dynasty values steadier week to week and
measures what each one costs in accuracy, on the point-in-time history (`Trade_Values/history`, 186 weekly snapshots,
2016 week 1 to 2026 week 11).

## How often do top values drop today?

Top-24 dynasty players (by last week's rank), weekly change on the 100k scale, 2018-2026:

| | Live |
|---|---|
| Average weekly move (up or down) | 11.6% |
| Weeks with a drop of 10% or more | 25.6% (one week in four) |
| Weeks with a drop of 20% or more | 9.5% |
| Average rank move | 3.7 places |
| 2026 so far: weeks with a 10%+ drop | 33% |

Why a top-24 dynasty value drops 10%+ in a week (live, 1,148 drops 2016-2026, `vs_drop_reasons.csv`):

| Cause | Share |
|---|---|
| One bad game lowered credible PPG | 59% |
| Mostly the #1 player rising (everyone is rescaled to #1 = 100,000) | 15% |
| Injury / status (expected games fell) | 15% |
| Games-left clock, replacement line | 10% |
| Did not play (bye or missing) | 2% |

The amplifier is leverage: dynasty value is points **over replacement** for six seasons, so a 1% change in credible PPG
moves a top-24 dynasty value about **2.7%** (median elasticity). Example: a WR averaging 20 PPG over 9 games scores 8 in
week 10. His credible PPG falls about 0.9 (4%) and his dynasty value about 11%.

## What was tested

Every variant changes only the in-season credibility blend (or smooths it). The history part (3-season PPG blended with
the draft prior) stays at its live point-in-time value, backed out of each snapshot exactly (within-season sd 0.007).
Rolling origin: anything fitted for season S uses seasons before S only. Accuracy is scored 2018-2025 (redraft) and
2018-2024 (dynasty, next season complete).

| Variant | Idea |
|---|---|
| k x 1.25 / 1.5 / 2 / 3 / 5 | Larger in-season credibility constant: Z = n / (n + m x k1) |
| Textbook Bühlmann-Straub k | k = EPV / VHM from weekly points (exposure = games), previous 5 seasons |
| Horizon k (ROS) | k fitted per position and week group (1-4, 5-8, 9-12, 13+) to the rest of the season |
| Horizon k (dynasty) | k fitted per position and week group to NEXT season's PPG |
| Trim games | Each game's points clipped to history PPG +/- 1.0 or 1.5 x per-game sd (limited fluctuation) |
| EWMA smoothing | credible PPG_t = a x new_t + (1 - a) x published_(t-1), a = 0.8 ... 0.4 |
| Top-10 anchor | 100k scale anchored on the average of the top 10 raw values, not the #1 player |
| Star recalibration | Pull the top tier's next-season projections together (Kyle's follow-up, below) |
| Grid | k x {1, 1.25, 1.5, 2} x a {1, .8, .7, .6, .5} x anchor {no, yes} (`vs_grid.csv`) |

## Results (`vs_results.csv`, `vs_grid.csv`)

Lower RMSE is better; higher Spearman is better; lower drop share is steadier.

| Variant | ROS PPG RMSE | ROS RMSE top 50 | Next-season RMSE | Next RMSE top 50 | Redraft Spearman | Dynasty Spearman | Dyn 10%+ drops | Dyn 20%+ drops |
|---|---|---|---|---|---|---|---|---|
| **Live** | **3.462** | 4.003 | 3.495 | 3.620 | **0.645** | **0.655** | 25.6% | 9.5% |
| k x 1.5 | 3.475 | **3.973** | **3.487** | **3.583** | 0.644 | 0.655 | 22.9% | 7.4% |
| k x 2 | 3.507 | 4.000 | 3.498 | 3.589 | 0.641 | 0.653 | 20.9% | 5.5% |
| Textbook B-S k (EPV/VHM) | 3.590 | 4.341 | 3.596 | 3.843 | 0.641 | 0.635 | 27.4% | 11.2% |
| Horizon k (ROS) | 3.463 | 3.990 | 3.496 | 3.623 | 0.645 | 0.654 | 25.4% | 9.2% |
| Horizon k (dynasty) | 3.469 | 3.994 | 3.496 | 3.610 | 0.646 | 0.655 | 24.7% | 8.4% |
| Trim games +/- 1 sd | 3.564 | 4.218 | 3.557 | 3.821 | 0.635 | 0.640 | 19.1% | 5.1% |
| EWMA a = 0.6 | 3.479 | 4.003 | 3.499 | 3.626 | 0.643 | 0.653 | 17.3% | 3.8% |
| Top-10 anchor only | 3.462 | 4.003 | 3.495 | 3.620 | 0.645 | 0.655 | 21.6% | 6.7% |
| Candidate, #1 = 100k kept: k x 1.25 + EWMA 0.7 | 3.478 | 3.982 | 3.491 | 3.600 | 0.643 | 0.654 | 18.4% | 4.3% |
| **Candidate: k x 1.25 + EWMA 0.7 + top-10 anchor** | 3.478 | 3.982 | 3.491 | 3.600 | 0.643 | 0.654 | **15.4%** | **3.3%** |

Candidate by season (`vs_by_season.csv`): fewer big drops in every season 2018-2025 (e.g. 2024 27.9% to 18.6%);
next-season top-50 error better in 5 of 8 seasons; rest-of-season error within +/- 0.04 PPG each season.

### What it means

1. **The textbook Bühlmann-Straub k makes values jumpier, not steadier** (k 1.2-2.0 games vs live 3.8-5.9). EPV/VHM
   measures credibility against the *position average*. Our complement is the player's *own* history, which is much
   closer to the truth, so the right VHM is smaller and k larger. The live k1 already is the empirical B-S answer for
   that complement, and fitting it by week or by horizon lands at almost the same k (QB the only exception, 6-9 for
   the dynasty horizon). So "B-S done right" mostly confirms the live weights.
2. **Slightly more weight on history helps the top players.** k x 1.25-1.5 is better for the top 50 on both horizons
   and costs 0.002-0.013 PPG overall. The fitted k is dominated by the hundreds of fringe players.
3. **Smoothing (EWMA on credible PPG) is the cheapest steadiness.** a = 0.7 removes a third of the big drops for
   +0.010 ROS RMSE and no dynasty cost. It only smooths PPG: injuries and status still hit the value the same week.
4. **Trimming big or bad games is rejected:** steadier, but clearly less accurate. Big games are real signal.
5. **The 100k scale itself causes 15% of big drops.** Anchoring on the top-10 average removes them at zero accuracy
   cost because values do not change, only the display scale. It breaks "#1 = exactly 100,000" (the #1 player shows
   about 95k-110k), which is Kyle's rule (A30), so it is a separate decision.

## Kyle's follow-up: dynasty values are predictions (Bijan vs Gibbs)

Kyle (2026-11-24): "dynasty values are PREDICTIVE VALUES ... One bad game is not going to throw a top tier player like
Bijan Robinson so low that Gibbs is worth more than a first."

* Week 11 2026: Gibbs 85,800 vs Bijan 42,700. Not one game: 2026 PPG 28.1 vs 19.8 over 10 games. Projected 2027 PPG
  23.0 vs 17.7 (both already regressed); over the RB replacement line (~11.5) that is 11.5 vs 6.2, so ~2:1.
  From week 4 to 11 Bijan's projected 2027 PPG fell 12% (20.2 to 17.7) while his value fell 44% (leverage + Gibbs
  becoming the #1 the scale is set by). Chart `07_bijan_gibbs.png`.
* In hindsight the top tier IS over-separated (`vs_05`, `vs_star_calibration.csv`): slope of actual on projected
  next-season PPG, weeks 6-14, 2016-2024: top 12 overall 0.52 (90% bootstrap 0.23-0.77, 156 player-seasons), top 24
  0.73, top 50 0.81, all players 0.98. Top-24 RBs 0.27 (-0.17 to 0.83, only 61 player-seasons).
* But it does not fix out of sample. Two rolling fixes (fitted on seasons <= S-2):
  - knot shrink above a per-position knot (`vs_05`, `vs_06`): next-season RMSE top 50 3.620 -> 3.670, top 24 3.760 -> 3.834;
  - top-tier recalibration act = a + b x pred on dynasty top 50, faded from rank 40 to 60 (`vs_07`): top 50 3.620 -> 3.689,
    top 24 3.760 -> 3.833. The early-season fits (b 0.28-0.62) were far stronger than later seasons needed (0.80-0.88).
  With the recalibration Gibbs 82,800 vs Bijan 43,900: the gap barely moves. REJECTED for now.
* The steadiness candidate lifts Bijan to 49,000 vs Gibbs 88,100 (top-10 anchored scale).

## Method notes and limits

* **Dynasty is a surrogate, not a rerun.** Within each player-season the live dynasty model's next-season PPG is an exact
  linear function of credible PPG (R^2 1.00, slope 0.76-0.88) and its future value is close to linear (R^2 0.70-0.89),
  so dynasty value change = player-season slope x change in credible PPG. The slope is estimated from the whole season's
  snapshots (a model-structure property, no outcome data). Redraft values are rebuilt exactly (live check: 0.02 mean
  absolute difference). A faithful R rerun on the PC (hv_01 with the variant) is needed before anything goes live.
* The dynasty ppg_next model was fitted on season-end credible PPG with the live k1; a live k change should refit it.
* The candidate's settings (1.25, 0.7) were picked on the same 2018-2025 period they are scored on. The gains are small
  and steady across seasons, but a holdout check (choose on 2018-2022, score 2023-2025) should come first.
* Replacement lines are re-drawn at the live depth; the site's flex greedy fill is not reproduced.
* Rookie picks are not in the history, so their stability is not measured.

## Files

| File | What |
|---|---|
| `vs_00_prep.py` | Panel from `history/values/*.csv` + snapshot meta (k per season); backs out history PPG; weekly points; targets |
| `vs_01_backtest.py` | Fitted k (`vs_fitted_k.csv`), dynasty surrogate slopes, single-lever variants |
| `vs_02_evaluate.py` | Volatility and accuracy scores (`vs_results.csv`) |
| `vs_03_combos.py` | k x EWMA x anchor grid (`vs_grid.csv`) |
| `vs_04_report.py` | Drop causes, by-season robustness, 2026 board compare (`vs_2026_board_compare.csv`), charts |
| `vs_05_star_calibration.py`, `vs_06_star_eval.py`, `vs_07_tier_recal.py` | Kyle's follow-up: top-tier calibration, knot shrink, tier recalibration (`vs_star_*.csv`, `vs_tier_recal_*.csv`) |
| `charts/` | 01 frontier, 02 change distribution, 03 drop reasons, 04 2026 examples, 05 fitted k, 06 single levers, 07 Bijan vs Gibbs |

Run in order with Python 3 (pandas, numpy, scipy, matplotlib, rdata). Intermediate `*.pkl` files are not committed.
