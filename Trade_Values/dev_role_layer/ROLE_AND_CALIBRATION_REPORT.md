# Role layer and calibration (FABLE_REVIEW findings 1, 2, 8) — dev report, 2026-11-13

All work is in `Football2_Dynasty_dev` (a copy of `Football2_Dynasty`). Nothing live was changed. With every switch
off, the dev scripts reproduce the live board and backtests exactly (checked: identical top-40 and backtest tables).
Every test is a paired comparison on the same players and the same target. Intervals come from a 2000-draw player
bootstrap (seed 2026). Replacement lines and backtest targets are held on the live definition in every variant.

## Recommendation

**Adopt A2 + the stop-loss sd fix (SH) + the season-length fix in the backtest (LF).** Drop A3, A4, HD, S4 and the
age variants. Per-position multipliers are optional: after SH the players are already calibrated in total (0.99).

| Setup (default league, 3+ game sample) | Dynasty Spearman | Dynasty pred / actual | Dynasty RMSE | Redraft Spearman | Redraft RMSE |
|---|---|---|---|---|---|
| Live model | 0.698 | 1.201 (1.172 with real season lengths) | 71.2 | 0.669 | 24.27 |
| A2 + LF + SH (recommended) | 0.700 | 0.995 | 70.1 | 0.686 (+0.016, sig) | 24.07 (sig) |

## Data (nflverse via nflreadr, cached in `cache_role/`)
- Depth charts: weekly 2012-2024. ESPN snapshots for 2025-2026 (latest 2026-11-13): for each week, the last
  snapshot before that week's first kickoff.
- Injury report: 2012-2026. Weekly rosters: 2012-2026, but the INA status only exists from 2019. CUT and practice-squad
  rows are sparse in 2016. Snap counts: 2013+, 99.9% mapped to gsis ids.
- Depth-rank coverage for players who played is 85-93% every season (`rl_coverage_by_season.csv`).

## A1: player-week classes (2016-2026, regular season, `rl_a1_class_counts_by_pos.csv`)
| Pos | played | missed, injured | missed, healthy | missed, other | off roster |
|---|---|---|---|---|---|
| QB | 6,737 | 1,867 | 6,708 | 54 | 4,045 |
| RB | 18,415 | 5,538 | 3,306 | 211 | 8,913 |
| TE | 16,524 | 4,685 | 1,713 | 130 | 8,152 |
| WR | 27,590 | 8,296 | 2,925 | 390 | 18,740 |

Among misses by depth-1 players, 9-11% are healthy misses for RB, WR and TE, and 35% for QBs.

## A2 (expected games from status) — KEEP
Rate = role × health:
- **Role:** credibility blend of this season's share of healthy games played and the position × depth-rank average.
- **Health:** injury-only availability (depth-chart misses are not counted), with credibility.
- **Injured statuses:** reserve / Out / Doubtful / Questionable use the fitted actual-to-role ratio for that status.
- **Fit:** only on snapshot seasons before the test season (2012 onward).

Results:
- **Redraft, all players:** Spearman 0.669 → 0.686 (+0.016, 95% +0.010 to +0.024), RMSE −0.20 (sig).
- **Redraft by position:** WR +0.030 (sig); RB +0.006 and TE +0.012 (both not significant).
- **Availability RMSE:** QB 0.293 → 0.281, RB 0.286 → 0.268, TE 0.278 → 0.270.
- **Dynasty:** neutral.
- **League setups:** redraft Spearman improves significantly in all five.
- **Wider population:** redraft Spearman +0.024 (sig).
- **Market check:** rank correlation 0.868 → 0.872.

## A3 (QB P(start) × value as a starter) — DROP
Start = a game with 15+ attempts. Pieces built: PPG in starts with credibility (k1 = 9.1, k2 = 45), P(start) for
each remaining game, pooled-horizon start-share and relief models, and a relief-appearance charge.
- PPG in starts predicts later PPG in starts better (RMSE 3.42 vs 3.97).
- On the redraft target, QB Spearman falls (3+ sample −0.019, not significant; wider sample −0.072, significant).
- **A3F (future seasons only):**
  - Before SH: it fixed backup-QB calibration on the wider sample (depth 2+: 2.07 → 0.72 × actual) with no
    significant harm on the 3+ test.
  - With SH on: QB dynasty RMSE is worse on both samples (3+: 111 → 122, sig; wider: +6.7, sig), and so is
    all-player RMSE (sig). SH alone takes backup QBs from 2.07 to 1.43 × actual; A3F overcorrects to 0.70.
- The QB layer works as code (`rl_dv11_qb.R`) but does not beat SH. Kept as a switch only.

## A4 (snap share and depth rank in PPG and availability) — DROP
On top of A2, only RB redraft ranking improves (+0.010, sig). Fed into the dynasty projection, it makes dynasty
RMSE worse (+1.4, sig) and totals worse (1.21 → 1.26).

## Backtest population
The live backtests score only players with 3+ games by week 9, so 0-1 game backups such as Fields and Tua are never
tested. Every variant was also run on a wider population (`WIDE`): rostered at week 9 with a draft pick or
prior-season games, about 720 extra player-seasons. Dynasty, QBs with 0-2 games, predicted / actual:

| Setup | Pred / actual |
|---|---|
| Live | 4.27 |
| A2 | 4.11 |
| A2 + SH | 2.72 |
| A2 + A3F + SH | 0.68 |

These are still overstated under the recommendation (see "Not done").

## Named QBs, default league, 2026 (dynasty rank / redraft rank)

Full table, including A2 + A3: `rl_named_qbs.csv`.

| Player | Live | A2 only | A2 + A3F |
|---|---|---|---|
| Fields | 101 / 116 | 107 / 116 | 112 / 116 |
| Tagovailoa | 107 / 121 | 112 / 118 | 246 / 118 |
| Mariota | 110 / 111 | 111 / 111 | 120 / 111 |
| Winston | 142 / 198 | 147 / 224 | 127 / 224 |
| Wentz | 132 / 128 | 132 / 130 | 270 / 130 |
| Richardson | 67 / 115 | 69 / 115 | 135 / 115 |
| Watson | 72 / 80 | 70 / 73 | 73 / 73 |

## B1: where the ~20% sits (`rl_calib_tables.csv`)
- **Season length:** valuing 2017-2020 seasons at 17 games instead of 16 accounts for about 3 points of it
  (1.201 → 1.172).
- **By value decile:** the top two deciles hold about 65% of the excess.
- **By experience:** rookies 0.97-0.99; years 4-6 1.22; years 7+ 1.33.
- **By age:** 26-28 1.29, 29-31 1.48. QBs aged 23-31 run 1.45-1.74.

## B2 (on A2 + LF; for QBs, the A2-only base)
- **(i) Direct horizon models (HD):** worse (RB RMSE +2.4 sig, totals up). Drop.
- **(ii) sd from h-ahead residuals (SH):**
  - All players: totals 1.18 → 0.99, Spearman +0.001.
  - QBs: RMSE 116 → 111 (sig), totals 1.30 → 1.12.
  - RB/WR/TE: totals 1.11-1.20 → 0.90-0.98.
  - SH is the main cause, and it is the fix: errors revert to the mean, so `sig × sqrt(t)` inflates upside.
- **(iii) Survival = 4+ games (S4):** totals −0.06, Spearman flat. SH + S4 overcorrects (0.96). Drop.

## B3: old age (`rl_calib_age.csv`)
- **Monotone survival after 30:** no effect at all, because the fitted curve is already non-increasing.
- **Pooling ages 37+:** neutral (QB Spearman +0.016, not significant).
- **Stafford and Cousins:** neither variant changes them materially. Their 2030 values come from the PPG and sd
  path, which SH shrinks. Not a separate fix.

## B4: picks
- **Live multiplier:** 1.114, 95% bootstrap 0.80-1.44 (classes, then players). Class ratios range 0.76-1.51.
- **Refit on the players' definition** (season's own replacement line, real season length): 1.134, 0.81-1.49.
- **Player multipliers after SH:** QB 0.89, RB 1.11, TE 1.03, WR 1.02. A leave-one-snapshot-out check does not
  improve held-out RMSE (70.09 → 70.43), so the multipliers are optional.
- **Default-league top 60** (`rl_board60_before_after.csv`): picks in the top 60 go from 6 to 9, QBs from 17 to 14.
  The 1.01 pick moves from 12th to 11th.

## Not done
- **SH on the live page math:** the browser formula uses `sig × sqrt(t)` (presets `sdk`). It needs per-horizon sd
  in `dv_13` and the page JS.
- **Backup QBs are still about 1.4× too high under SH.** A depth-rank term only in the survival model is the next
  thing to try.
- **Market Check:** gaps barely move. The backup QBs are still the biggest "higher than market" gaps under the
  recommended setup.

## Files (dev)
- New: `rl_00_pull_role_data.R`, `rl_01_role_build.R`, `rl_common.R`, `rl_dv10.R`, `rl_dv11_ext.R`,
  `rl_dv11_qb.R`, `rl_run.R`, `rl_eval.R`, `rl_wide_report.R`, `rl_calib.R`, `rl_b4_picks.R`, `rl_board60.R`.
- Changed: `dv_10_ros_value.R` (switch hooks, `att` column, replacement-line pin, `relief_v`, `WIDE_POP`,
  `BT_MIN`), `dv_11_dynasty_v4.R` (switches, `GLEN_`, export).
- Disabled in dev: `dv_09`, `dv_12`, `dv_14` (they write to the live site).

## To switch over (not done)
1. Copy the new `rl_*` scripts and the changed `dv_10` / `dv_11` into `Football2_Dynasty`. Set
   `ROLE_AVAIL <- TRUE; SIG_H <- TRUE; LENFIX <- TRUE` at the top of `dv_11` (or in `dv_13`).
2. Port SH to `dv_13` presets and the page JS: per-horizon sd in place of `sig × sqrt(t)`. Rerun `dv_15`.
3. In `Weekly_Refresh/rf_01`, add tryCatch pulls of `load_depth_charts(2026)`, `load_injuries`, and
   `load_rosters_weekly` into `Football2_Dynasty/cache_role/`, then run `rl_01`. On failure, keep last week's cache
   and run with `ROLE_AVAIL <- FALSE`.
4. On the trade-values page template, add a status tag per player (IR / Out / Doubtful / Q / Backup) from
   `cat` in `dv_ros_2026_board.csv`.
