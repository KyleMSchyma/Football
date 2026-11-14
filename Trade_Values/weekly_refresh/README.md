# Weekly refresh, 2026 NFL regular season

One script, `refresh.sh`, updates every model output that new weekly data changes and pushes the results.
Windows Task Scheduler runs it every **Tuesday at 10:00 AM** (task name *Prospect Actuary weekly refresh*)
from November 17, 2026 through **January 5, 2027**, the Tuesday after Week 18. After that the task stops on its own.

## What one run does

| Step | What | Where |
|---|---|---|
| 1 | Pull 2026 weekly player stats, the injury report and weekly rosters from nflverse (`rf_01_pull_nfl.R`) | `Football2_Dynasty/nfl_weekly_2026.rds`, `nfl_injuries_2026.rds`, `nfl_rosters_weekly_2026.rds` |
| 2 | Re-run redraft (rest-of-season) and dynasty trade values for every scoring preset and the 2027 rookie pick profiles (`dv_13`, which runs `dv_11` and `dv_10` 20 times to cover every scoring and first-down bonus, about 3 minutes) | `dv_league_presets.rds` (all presets, read by the page), `dv_ros_2026_board.csv` and `dv_v4_board.csv` (default league), backtests |
| 3 | Rebuild the Trade Values page (`dv_12`) | `ProspectActuary/trade-values/` |
| 4 | Until Dec 16 (college regular season): re-pull CFBD 2026 stats, rebuild the 2027 pool (pro-rated and as-is), re-grade (`pd_01`, `pd_06`), drafted recalibration (`pd_11`) | `Football2_PreDraft/` |
| 4b | Every week, after the trade values: swap the data lines of the pre-draft and post-draft grade pages (`rf_02_predraft_page.R`, `Football2_PostDraft/pd_10_site_page.R`). They carry the cross-position Value column (`Football2_Dynasty/dv_rookie_board_values.csv`, written by `dv_13`) | `ProspectActuary/pre-draft/`, `ProspectActuary/post-draft/` |
| 5 | Push the site to `prospect-actuary` main; push code + outputs to Football main | `Trade_Values/`, `PreDraft_Model/` |

Not re-run, on purpose: post-draft grades (they use draft capital and college data only), the position
research models, and model training (pre-draft models are trained on 2010-2023 classes and do not change).
The old `/dynasty/` page is never published; the script stops before pushing if a `dynasty/` folder appears on the site.

Redraft values use the latest week as "now" (`CUT26` in `dv_10`); the credibility constants are still fit
on week-9 backtests. After Week 18 there are no games left, so the redraft sheet keeps its last in-season values.

## Running it by hand

```
bash refresh.sh              # full run with pushes
NO_PUSH=1 bash refresh.sh    # everything except git push
FOOTBALL_BRANCH=weekly-refresh bash refresh.sh   # Football repo to a branch + PR instead of main
```

Logs: `logs/<date_time>/refresh.txt` (plus one log per R step); `logs/last_status.txt` says OK or FAILED.
The site repo must be on `main` with no uncommitted changes, or the run stops before changing anything.
A run takes about 10 minutes; the PC has to be on (if it was off, Task Scheduler runs it at the next start-up).

## FABLE build additions (2026-11-13)

| Step | What |
|---|---|
| 1b | Role data for the trade values (`rl_00_pull_role_data.R`, `rl_01_role_build.R` in the dynasty folder): depth charts, injury report, weekly rosters, snap counts, schedule. A failed pull keeps last week's cached file and prints `REUSED` in the log; the run goes on. |
| 3c | `dv_15_board_value_check.R` writes the R values the browser check compares against. |
| G | **Output gates** (`rf_03_gates.R`), before anything is committed or pushed. They check: every team that finished a game in the latest week is in the stats; no missing values in the boards, page inputs or pick inputs; default replacement lines within the 2016-2025 week-9 range ±2 PPG (`rf_gate_limits.csv`); pick multiplier 0.7-1.6; at most 15 players leaving either top 50 since last week (2021-2025 weeks 8-17: never more than 8; skipped before week 8); R page math equal to the models; and the built Trade Values page, run in headless Edge, within 100 points of R on the 100,000 scale for five test leagues. Any failure stops the run. |
| A | **Archive** (`rf_04_archive.R`): `archive/YYYY-MM-DD_weekNN_redraft.csv`, `_dynasty.csv`, `_picks.csv` and `_movers.csv` (biggest value changes since the previous archive), copied to `Trade_Values/archive/` in the Football repo. |
| ! | **On any failure:** `PROSPECT_ACTUARY_REFRESH_FAILED.txt` on the Desktop, a Windows popup, and `logs/last_status.txt`. |

Settings (environment): `DYN_DIR`, `SITE_DIR`, `SITE_BRANCH`, `FOOTBALL_BRANCH`, `SKIP_PREDRAFT=1`, `ARCHIVE_DIR`, `NO_PUSH=1`, `NO_NOTIFY=1`, and `FORCE_GATE_FAIL=1` to test the failure path. The defaults are the live folders, site `main` and Football `main`. `run_dev.sh` runs against `Football2_Dynasty_dev` and the site worktree on the review branch, with pushes off.
