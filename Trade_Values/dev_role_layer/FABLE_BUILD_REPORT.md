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

---

# FABLE build, part 2 (2026-11-13, afternoon)

## Part 1: backup QBs — depth rank and starts in the QB still-playing and PPG models
These are added on top of status-based games, the horizon sd and the real season lengths. The dynasty backtest
uses week-9 snapshots from 2016-2020. Depth rank is used for the first future season; later seasons use an
"unknown" level.

| Option | Backup QBs (depth 2+), pred / actual, wider population | QBs with 0-2 games, pred / actual | QB Spearman, wider population | QB RMSE, 3+ test | Market rank corr. |
|---|---|---|---|---|---|
| Without (A2 + SH) | 1.43 | 2.72 | 0.716 | 111.3 | 0.872 |
| Depth rank only | 1.19 | 2.30 | 0.724 (+0.008, sig) | 110.1 | 0.868 |
| Depth + share of games started | 0.75 | 1.05 | 0.732 | 109.7 | 0.826 |
| **Average of the two (kept)** | **0.92** | 1.53 | 0.732 (+0.017, sig) | 109.7 | 0.849 |

None of the three is significantly worse than A2 + SH on the original 3+ game test; all-player dynasty RMSE is
69.85-69.90 vs 70.09. The average is the one whose backup-QB ratio is closest to 1, so it is the default
(`QB_SS = "avg"`).

Named QBs, default league, dynasty rank / redraft rank:

| Player | Live | New (final dev) |
|---|---|---|
| Justin Fields | 101 / 116 | 145 / 116 |
| Tua Tagovailoa | 107 / 121 | 148 / 118 |
| Marcus Mariota | 110 / 111 | 123 / 111 |
| Jameis Winston | 142 / 198 | 136 / 224 |
| Carson Wentz | 132 / 128 | 153 / 130 |
| Anthony Richardson | 67 / 115 | 103 / 115 |
| Deshaun Watson (Q, depth 1) | 72 / 80 | 62 / 73 |

## Part 2: wired into the full dev pipeline and the site worktree

**Defaults.** The dev defaults are now the kept setup. `dv_10` sets `ROLE_AVAIL`, `SIG_H`, `LENFIX` and
`QB_DEPTH` to TRUE and `QB_SS` to "avg" unless they are already set, so any of them can be switched off.

**Pick multiplier.** `dv_13` refits the pick multiplier on the players' definition of realized value: each season's
own week-9 default replacement line and the real season length. The result is **1.129, 95% bootstrap
0.80-1.47** (classes, then players; 2000 draws). The old definition gives 1.109. The per-position player
multipliers are not applied.

**League-setup backtest** (`rl_part2_league_backtest.csv`):

| Setting | Redraft Spearman live → new | Dynasty Spearman live → new | Dynasty pred / actual live → new |
|---|---|---|---|
| 12 teams superflex (default) | 0.669 → 0.685 | 0.698 → 0.699 | 1.201 → 0.986 |
| 12 teams 1 QB, 1 flex | 0.644 → 0.658 | 0.680 → 0.684 | 1.208 → 0.986 |
| 10 teams 1 QB, 2 flex | 0.630 → 0.647 | 0.661 → 0.664 | 1.226 → 0.972 |
| 14 teams superflex, 1 flex | 0.698 → 0.711 | 0.734 → 0.735 | 1.162 → 1.005 |
| 8 teams 1 QB, 1 flex | 0.612 → 0.636 | 0.610 → 0.614 | 1.279 → 0.954 |

**Scoring presets** (`rl_part2_scoring_backtest.csv`). Every preset improves or holds:
- Dynasty: QB +0.015 to +0.023; RB, WR and TE +0.000 to +0.005.
- Redraft: WR +0.029 to +0.030; TE +0.011 to +0.015; QB and RB +0.001 to +0.006.

**Anchor check** (`rl_part2_anchor_check.csv`). The dynasty two-player / one-player ratio averages 0.98, with
a range of 0.78-1.19 (live: 1.03, 0.89-1.24). Redraft is unchanged at 0.87.

**Page math.**
- R page math (`league_values`) vs dv_10 / dv_11: max difference 6e-14 (dynasty), 0 (redraft).
- Browser vs R: the built Trade Values page's own `compute()`, run in a browser for the five test leagues.
  `dv_15` writes `dv_15_expected.js`, and `dv_15_check.js` is the check. Max |page − R| on the 100k scale:

| League | Dynasty players | Redraft players | Pick slots |
|---|---|---|---|
| 12 teams superflex | 8.1 | 7.4 | 40.3 |
| 12 teams 1 QB, 1 flex | 5.6 | 9.8 | 37.8 |
| 10 teams 1 QB, 2 flex | 3.7 | 7.8 | 35.1 |
| 14 teams superflex, 1 flex | 6.2 | 10.1 | 38.9 |
| 8 teams 1 QB, 1 flex | 5.8 | 9.2 | 23.9 |

The differences are rounding: the page data stores projections to 3 decimals.

**Data format (additive).** Each scoring key's `sd` array was `[sd0, sig]` and is now `[sd0, sig, sd1..sd5]`.
- New page code uses `sd[1+t]` when it is present, otherwise `sig × sqrt(t)`.
- Older page code reads only `sd[0], sd[1]`.
- Checked in the browser that the new code runs on both formats.
- Players carry an optional `st` (status) field, and `picks.f_ci` is added.
- Files changed: trade-values template, trade-calculator, shared/league-value.js and value-research (same
  one-line change each).

**Status tags.** IR, Out, Doubtful, Q and Backup, with a one-line legend, on the Trade Values page and the
calculator. Backup means:
- QBs at depth 2+ or not on the chart.
- RB / WR / TE only when listed at depth 3+ and under half the offensive snaps. ESPN's slot charts list Puka
  Nacua 5th at his slot, so depth alone mislabels starters.

Currently: 59 IR, 20 Out, 2 Doubtful, 23 Q, 165 Backup.

**Guide text.** The site guide, GUIDE.md and the page's "How they're built" now describe status-based games,
the measured multi-year spread, QB depth and starts, the 1.13 pick multiplier with its interval, and the
0.95-1.01 predicted / actual. The 16-28% high claim is removed.

**Commits.** Site worktree commit 18b20d2 on prospect-actuary branch `claude/project-thread-huep4j` (PR #8).
The dev code and result CSVs are in Football `Trade_Values/dev_role_layer/`.

## Part 3: weekly refresh (Weekly_Refresh_dev), end to end with NO_PUSH — passed
The run: guarded pulls (stats, injury report, rosters, then depth charts / injuries / rosters / snaps / schedule
into the role cache; a failed pull prints REUSED and the run goes on), then `dv_13`, `dv_12`, `dv_15`, the grade
pages, the gates, the archive, a local site commit and a Football worktree commit. Nothing was pushed.

Gates on 2026-11-13 (week 10, one game played):
- latest week complete (2 of 2 teams)
- no missing values
- replacement lines QB 13.41 / RB 11.33 / WR 10.06 / TE 9.65, inside the 2016-2025 ranges ±2
- pick multiplier 1.129
- top-50 turnover: first archive
- R math = models (1e-13)
- built page vs R in headless Edge: players ≤ 10.1, picks ≤ 40.3 on the 100k scale

Turnover limit 15: 2021-2025 weeks 8-17, the redraft top 50 never lost more than 8 players in a week (median
3-4; weeks before 8 have no replacement pool yet). The movers file and the turnover gate were also exercised
against a planted previous week.

**Failure path, tested for real.** The first attempt stopped at the browser gate: Edge returns `--dump-dom`
output only when started through PowerShell with redirected stdout, which is now fixed. It wrote
`PROSPECT_ACTUARY_REFRESH_FAILED.txt` on the Desktop, raised the popup, and nothing was committed or pushed.

The archive (`Trade_Values/archive/2026-11-13_week10_*.csv`) is committed to the Football branch.

**Pre-draft regrade.** Skipped in dev (`SKIP_PREDRAFT=1`), because it edits the live `Football2_PreDraft`
folder; its code is unchanged. `pd_10` (live PostDraft folder) still reads `../Football2_Dynasty/dv_rookie_board_values.csv`,
so a dev run uses the live rookie Value file for the post-draft board. It reads the right file once the dynasty
folder is switched over.

## Part 4: switch-over — NOT DONE (waiting for Kyle)
- **Backup made:** `Documents\R Studio\_backup_pre_fable_2026-11-13\` (Football2_Dynasty, Weekly_Refresh; verified identical).
- **Blocked:** copying dev into the live folders was refused by this PC's Claude Code safety check, because those
  folders run Tuesday's scheduled task. Live folders verified unchanged.
- **To do on approval:**
  - copy `dv_*.R`, `rl_*.R`, `tv_page_template.html`, `dv_15_check.js` and `cache_role/` into `Football2_Dynasty`
  - copy `refresh.sh`, `rf_01`-`rf_04`, `rf_gate_limits.csv`, `README.md`, `run_dev.sh` and `archive/` into `Weekly_Refresh`
  - run `NO_PUSH=1 SKIP_PREDRAFT=1 bash Weekly_Refresh/refresh.sh`
  - `git reset --hard origin/main` in `ProspectActuary`
- **Before Tuesday:** merge site PR #8, so the calculator, market check and board Value columns use the new
  per-season sds too. The data change is additive, so they still work before the merge, with slightly different
  dynasty numbers.

## Part 5: finding 3 — penalizing the draft pick in the post-draft model
`Football2_PostDraft_exp/pd_20_pick_penalty_experiment.R` (new folder; position folders read only). Strict rolling
origin: test classes 2016-2023, train on classes up to Y−3, preprocessing in-fold. Pooled out-of-fold:

| Pos | Model | Points RMSE | Points Spearman | Top-tier Brier | Top-2 Brier | Any-tier Brier | Any-tier AUC | Ladder RPS |
|---|---|---|---|---|---|---|---|---|
| QB (95) | pick only | **205.2** | **0.667** | 0.104 | 0.112 | 0.140 | 0.848 | 0.116 |
| | current | 228.8 | 0.556 | **0.101** | 0.118 | **0.122** | **0.893** | 0.113 |
| | (i) pick unpenalized | 223.7 | 0.588 | 0.103 | **0.106** | 0.133 | 0.881 | **0.112** |
| | (ii) pick offset | 219.5 | 0.607 | 0.103 | 0.107 | 0.126 | 0.887 | – |
| | (iii) lambda.1se | 218.4 | 0.612 | 0.124 | 0.125 | 0.133 | 0.873 | 0.122 |
| | (iv) i + iii | 207.1 | 0.628 | 0.104 | 0.112 | 0.137 | 0.868 | 0.115 |
| WR (256) | pick only | 181.3 | 0.624 | **0.083** | 0.111 | **0.132** | **0.850** | **0.108** |
| | current | 183.8 | 0.613 | 0.089 | 0.117 | 0.140 | 0.798 | 0.114 |
| | (i) | 181.6 | 0.625 | 0.085 | 0.113 | 0.135 | 0.823 | 0.109 |
| | (ii) | **181.3** | 0.626 | 0.085 | 0.112 | 0.136 | 0.821 | – |
| | (iii) | 189.9 | **0.630** | 0.089 | 0.116 | 0.139 | 0.828 | 0.117 |
| | (iv) | 181.3 | 0.624 | 0.083 | **0.110** | 0.132 | 0.848 | 0.108 |
| RB (171) | pick only | 191.8 | **0.679** | **0.081** | 0.128 | **0.133** | **0.842** | **0.113** |
| | current | 196.8 | 0.640 | 0.085 | 0.135 | 0.147 | 0.795 | 0.121 |
| | (i) | 191.6 | 0.673 | 0.081 | **0.127** | 0.134 | 0.827 | 0.114 |
| | (ii) | **191.0** | 0.674 | 0.081 | 0.127 | 0.135 | 0.824 | – |
| | (iii) | 226.7 | 0.651 | 0.102 | 0.154 | 0.176 | 0.771 | 0.152 |
| | (iv) | 191.8 | 0.679 | 0.081 | 0.128 | 0.133 | 0.842 | 0.113 |
| TE (113) | pick only | **108.8** | **0.667** | **0.055** | 0.100 | **0.111** | **0.861** | **0.087** |
| | current | 114.2 | 0.558 | 0.064 | 0.115 | 0.120 | 0.822 | 0.096 |
| | (i) | 111.9 | 0.599 | 0.058 | 0.102 | 0.114 | 0.851 | 0.091 |
| | (ii) | 108.8 | 0.667 | 0.057 | **0.098** | 0.114 | 0.852 | – |
| | (iii) | 125.1 | 0.590 | 0.066 | 0.140 | 0.123 | 0.846 | 0.124 |
| | (iv) | 108.8 | 0.667 | 0.055 | 0.100 | 0.111 | 0.861 | 0.087 |

**Paired bootstrap results** (`pd20_bootstrap.csv`, 2000 draws).

(i) unpenalized pick vs current: never worse; significantly better for
- WR top-tier Brier (−0.0047) and ladder RPS (−0.0047)
- RB any-tier Brier (−0.013) and RPS (−0.007)
- TE top-2 Brier (−0.014)

(ii) behaves like (i). (iv) is better than current for QB points (−21.7 RMSE), RB any-tier and RPS, and TE
top-tier. Against pick-only, no variant is significantly better anywhere.

(iii) on its own is significantly worse than current:
- RB on every metric (points RMSE +29.9)
- TE points, top-2 Brier and RPS
- WR points
- QB top-tier

The 1-SE rule shrinks the pick too.

**Recommendation (no regrading done).**
1. Leaving `log_pick` unpenalized is a safe fix that only helps. Adopt it everywhere the post-draft elastic net or
   ladder is fit.
2. Even with that fix, college inputs add nothing measurable after the pick for RB, WR and TE: (iv) is the
   pick-only model. Price RB / WR / TE post-draft from pick-only (or pick + (i)), and say so on the site.
3. For QBs, keep a college adjustment with the pick unpenalized. Current any-tier (top-24) AUC is 0.893 vs 0.848
   for pick-only, the one place college data helps, matching the earlier likelihood-ratio result. Points are
   still best from pick-only.
4. Don't use `lambda.1se` alone.

## Parts 6-10 (2026-11-13, evening)

**Part 6, post-draft regrade with log_pick unpenalized (Kyle's choice) — IN PROGRESS, not finished.**
- `Football2_PostDraft_exp/pd_21_variant_ladders.R unpen` writes leave-one-class-out ladders (2010-2023) and
  2024-2026 boards into `Football2_PostDraft_dev_unpen/`. QB and RB are done (mean predicted any-tier 0.270 vs
  actual 0.276 for QB; 0.259 vs 0.262 for RB). WR and TE were still running when the usage limit hit.
- `pd_21_patch_dev.R` has already patched the dev copies of pd_07 (reads the new ladders) and pd_09 (2027 mock with
  the pick unpenalized).
- To finish:
  1. let pd_21 complete (or rerun `./run.sh pd_21_variant_ladders.R log.txt unpen ../Football2_PostDraft_dev_unpen`)
  2. in `Football2_PostDraft_dev_unpen`, run pd_07, then pd_09
  3. run `pd_25_regrade_compare.R ../Football2_PostDraft_dev_unpen` for the letter-grade changes, 25 biggest
     movers, 2027 mock before/after, and the validation files and band hit rates before/after
- The pick-only alternative was not needed (Kyle chose the unpenalized option).
- **Switch to live (after approval):**
  1. Re-run the position models' post ladders the same way, or copy the dev pd_07 / pd_09 together with the
     pd_21 outputs into `Football2_PostDraft`.
  2. Rerun pd_07, pd_09 and pd_10 (the post-draft page data line).
  3. Rerun dv_13, which rebuilds the 2027 pick values and the board Value column from `pd_post_player_grades.csv`
     and `pd_post_2027_mock_grades.csv`.
  4. Rebuild the pages (the weekly refresh does steps 3-4).

**Part 7, rolling-origin hit rates — done** (`PostDraft_Model/exp_rolling_hit_rates/`). Any-tier hit rate for the A
range, all positions:

| Board | Rolling 2016-2023 | LOCO 2016-2023 | LOCO 2010-2023 (published) |
|---|---|---|---|
| Pre-draft | 62% | 62% | 59% |
| Post-draft | 75% | 70% | 66% |

The published A-range numbers hold up. The post-draft low end separates less under rolling: D/F 9% vs C 9%.

**Part 8, Track Record — done** (`Track_Record/`, site `track-record/`).
- **Frozen 2026-11-13, with SHA-256:** 2024-2026 pre- and post-draft predictions plus a pick-only benchmark, and
  the Market Check log (169 players, 69 gaps of 25+ ranks). Stored byte for byte in git.
- **Results so far:**
  - A grades: 60-62% any-tier hit so far, vs 61-66% expected over three seasons.
  - Post-draft Brier beats pick-only for both the 2024 and 2025 classes.
  - Pre-draft beats it for 2024 only.
- `tr_02_score.R` reruns each January.

**Part 9, usage prior — tested and DROPPED.** For years 1-3 it made QB and RB redraft error significantly worse;
over all players, redraft Spearman −0.001 and error +0.05, both significant; dynasty was neutral. The Buy / Sell
page is built (site `buy-sell/`).

**Part 10, 2027 selection effect — done, dev only** (`PreDraft_Model/exp_selection_2027/`).
- Players who stayed in school carry 47-51% of the pre-draft model's predicted hit mass. Predicted hits are about
  2× actual on the eligible pool.
- A refit P(declare) multiplier brings the totals close to actual.
- Pick curve, default league:
  - 1.01-1.04 unchanged (mocked players)
  - 1.12: 20.3k → 16.8k
  - 2.12: 15.1k → 8.3k
  - 3.12: 12.6k → 6.5k

## Part 6 result: post-draft regrade with log_pick unpenalized (Kyle's choice) — done in dev
Built in `Football2_PostDraft_dev_unpen`:
- pd_21 ladders (leave-one-class-out 2010-2023; final model for 2024-2026)
- the patched pd_07 and pd_09
- the comparison: `pd_25_regrade_compare.R`

Files are in `PostDraft_Model/exp_pick_penalty/regrade_unpen/`.

**Calibration.** Mean predicted any-tier vs actual: QB 0.270 / 0.276, RB 0.259 / 0.262, WR 0.209 / 0.213, TE
0.219 / 0.228.

**Grade changes** (1,351 drafted players 2010-2026):

| Pos | Players | Grade changed | Letter changed | Up | Down | Moved 2+ steps |
|---|---|---|---|---|---|---|
| QB | 198 | 87 | 45 | 37 | 50 | 15 |
| RB | 354 | 177 | 95 | 86 | 91 | 30 |
| TE | 252 | 156 | 108 | 79 | 77 | 66 |
| WR | 547 | 212 | 108 | 114 | 98 | 30 |

TE moves most: the old model shrank the pick hardest there. The biggest movers are mostly late-pick TEs falling
from B to C/D, and mid-round players with good outcomes rising. Examples: Terry McLaurin D → B- (became a WR24
hit), Hunter Long C+ → B+, Brock Purdy B- → C- (pick 262). Full list: `pd25_biggest_movers.csv`.

**Validation** (LOCO 2010-2023, players with both grades; before → after):

| Pos | Points Spearman | Any-tier AUC (pick-only) | Mean within-class Spearman | Grade + pick vs pick alone, LRT p (any tier) |
|---|---|---|---|---|
| QB | 0.666 → 0.687 | 0.905 → 0.899 (0.876) | 0.605 → 0.590 | 0.0004 → 0.001 |
| RB | 0.635 → 0.655 | 0.790 → 0.809 (0.827) | 0.515 → 0.535 | 0.29 → 0.0005 |
| WR | 0.612 → 0.635 | 0.833 → 0.848 (0.842) | 0.495 → 0.511 | 0.76 → 0.47 |
| TE | 0.612 → 0.680 | 0.814 → 0.829 (0.850) | 0.477 → 0.517 | 0.46 → 0.00003 |

- **Hit rate by grade band** (any tier, before → after; full table `pd25_hit_rate_by_band_before_after.csv`):
  - QB A 0.79 → 0.83, C 0.06 → 0.12
  - RB A 0.73 → 0.71, D/F 0.10 → 0.04
  - TE A 0.57 → 0.63
  - WR about unchanged
- **2027 mock** (`pd25_mock_2027_before_after.csv`): probabilities rise for most mocked players and letters mostly
  hold. Jamari Johnson TE A- → A+, Terrance Carter TE C+ → B+, Deuce Alexander and Junior Sherrill WR B → B+,
  Luke Reynolds TE A- → B+, CJ Carr QB A → A-.
- **Read:** with the pick unpenalized, the post-draft grade now ranks NFL points better than before at every
  position. For RB and TE the grade adds to the pick in the likelihood-ratio test, where before it did not. Any-tier
  AUC for RB and TE is still a little below pick-only on its own; WR's is now above.

**Switch to live (waits for Kyle's approval; nothing has been copied):**
1. Put `pd_21_variant_ladders.R` (run with `unpen`) in `Football2_PostDraft` and run it there. It reads the
   position folders only and writes `pd21_oof_<POS>.csv` / `pd21_board_<POS>.csv`. The position folders
   themselves need no change; their own phase 4 / phase 6 files stay as the research record of the old fit.
2. Replace `Football2_PostDraft/pd_07_postdraft_grades.R` and `pd_09_mock_2027.R` with the dev versions (patched
   to read the pd_21 ladders; pd_09 fits its 2027 ladder with log_pick unpenalized). Run pd_07, then pd_09. This
   rewrites `pd_post_player_grades.csv`, the validation CSVs and `pd_post_2027_mock_grades.csv`.
3. Run `pd_10_site_page.R <site>/post-draft/index.html`, which swaps the post-draft page's data line.
4. Rerun `Football2_Dynasty/dv_13` (2027 pick values and the board Value column read both post-draft files), then
   dv_12 and `rf_02` for the pre-draft page. The weekly refresh runs steps 3-4 automatically.
5. Optional, for consistency: `pd_08` (predictor importance) refits its own ladder and would need the same
   `penaltyFactors` change.

## Switch-over to the live folders — DONE 2026-11-13 (Kyle's written approval)
**Backup** (verified identical before any change): `Documents\R Studio\_backup_pre_fable_2026-11-13\` with
Football2_Dynasty, Weekly_Refresh, Football2_PostDraft and Football2_PreDraft.

**What changed in each live folder:**
- `Football2_Dynasty`:
  - dev `dv_*.R` (defaults: status-based games, horizon sd, QB depth + starts "avg", real season length in
    the backtest)
  - `rl_*.R` and `cache_role/`
  - `dv_15` browser check data
  - the new page template (nearest-100 display, Expected PPG, why-this-value panel, known limits)
  - the `dv_13` P(declare) multiplier for pre-draft-priced 2027 prospects
  - fitted outputs regenerated by the test run
- `Weekly_Refresh`:
  - `refresh.sh` with live defaults (live folders, site main, Football main)
  - `rf_01`-`rf_04`, `rf_gate_limits.csv`, `run_dev.sh`, `README.md`
  - `archive/`
  - `run_weekly.cmd` and the Windows task are unchanged. The task still calls `run_weekly.cmd` → `refresh.sh`.
- `Football2_PostDraft`:
  - `pd_20` / `pd_21` (unpenalized ladders, run)
  - dev `pd_07` / `pd_09`, run; outputs identical to the dev regrade
- `Football2_PreDraft`:
  - new `pd_12_declare_2027.R` and `pd_declare_2027.csv`
  - `refresh.sh` runs pd_12 after pd_11 every week the pre-draft board is regraded
  - the regrade also ran once in the test

**Live test run** (`NO_PUSH=1 bash Weekly_Refresh/refresh.sh`, full path including the pre-draft regrade).

All six gates passed:
1. Week 10 complete (2/2 teams).
2. No missing values.
3. Replacement lines QB 13.41 / RB 11.33 / WR 10.06 / TE 9.65.
4. Pick multiplier 1.026, 95% 0.73-1.34. It moved from 1.13 because the post-draft regrade changed the pick
   probabilities it is calibrated against.
5. Top-50 turnover 0 / 0.
6. R = models (1e-13); page vs R ≤ 10.1 players and ≤ 50.3 picks.

- 73 pre-draft-priced 2027 prospects were multiplied by P(declare) (mean 0.41); all matched.
- The site main checkout was then reset to origin/main: clean, nothing committed or pushed. The Football commit was
  only in a temporary worktree (removed).
- Top 10 dynasty: JSN, Gibbs, Allen, Nacua, Bowers, Lamb, Burrow, Chase, Maye, St. Brown.
- Top 10 redraft: Gibbs, JSN, Allen, Lamb, Chase, St. Brown, Walker III, McCaffrey, Bijan, Burrow.
- 2027 picks 1.01-1.12 (default league): 56.5k, 39.5k, 31.9k, 31.6k, 23.4k, 23.1k, 22.8k, 21.0k, 20.3k, 19.3k,
  17.5k, 16.0k.

**Tuesday 10 AM.** The scheduled run will run the new code end to end and push to site main and Football main. It
does not depend on PR #8 to run, and there is no merge conflict:
- The refresh rewrites only `trade-values/` (page + data from the new template), `pre-draft/`, `post-draft/` and
  `value-research/data` on main.
- If PR #8 is not merged first, main gets the new Trade Values page (new math, tags, display) and the new data. The
  Trade Calculator, Market Check and grade-board Value columns keep main's old JavaScript; it reads the new data
  (additive format) with the old `sig × sqrt(t)` rule, so their dynasty numbers differ slightly from the Trade
  Values page.
- Track Record, Buy / Sell, the menu entries and the guide text appear only when PR #8 is merged.
- If PR #8 is merged after Tuesday, its `trade-values/index.html` and data files will conflict with the refresh's
  commit (both edited those generated files). Resolve by taking main's (the newer refresh), or simply rerun the
  refresh after merging.
- Merging PR #8 before Tuesday avoids all of this.
