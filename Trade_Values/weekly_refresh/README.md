# Weekly refresh, 2026 NFL regular season

One script, `refresh.sh`, updates every model output that new weekly data changes and pushes the results.
Windows Task Scheduler runs it every **Tuesday at 10:00 AM** (task name *Prospect Actuary weekly refresh*)
from November 17, 2026 through **January 5, 2027**, the Tuesday after Week 18. After that the task stops on its own.

## What one run does

| Step | What | Where |
|---|---|---|
| 1 | Pull 2026 weekly player stats, the injury report and weekly rosters from nflverse (`rf_01_pull_nfl.R`) | `Football2_Dynasty/nfl_weekly_2026.rds`, `nfl_injuries_2026.rds`, `nfl_rosters_weekly_2026.rds` |
| 2 | Re-run redraft (rest-of-season) and dynasty trade values for every scoring preset and the 2027 rookie pick profiles (`dv_13`, which runs `dv_11` and `dv_10` four times, about 1 minute) | `dv_league_presets.rds` (all presets, read by the page), `dv_ros_2026_board.csv` and `dv_v4_board.csv` (default league), backtests |
| 3 | Rebuild the Trade Values page (`dv_12`) | `ProspectActuary/trade-values/` |
| 4 | Until Dec 16 (college regular season): re-pull CFBD 2026 stats, rebuild the 2027 pool (pro-rated and as-is), re-grade (`pd_01`, `pd_06`), refresh the pre-draft page data (`rf_02_predraft_page.R`) | `Football2_PreDraft/`, `ProspectActuary/pre-draft/` |
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
