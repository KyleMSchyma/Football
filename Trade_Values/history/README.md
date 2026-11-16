# Point-in-time value history (2016 to now)

Kyle's ask (2026-11-16): value every player at every past Tuesday **as if the weekly refresh had run that morning**, using
only data that existed then, and track how those values did. This folder rebuilds that history and scores it.

Site page: [prospect-actuary /value-history/](https://kylemschyma.github.io/prospect-actuary/value-history/)

## What one snapshot is

Snapshot `(S, W)` = the redraft and dynasty values the refresh would have published on the Tuesday after week `W` of
season `S` (2016 week 1 through the latest 2026 week: 17 weeks a season before 2021, 18 from 2021).

| Piece | What it may use at `(S, W)` |
|---|---|
| NFL stats | every earlier season, plus weeks 1..W of season S |
| Injury report, roster status | weeks 1..W of season S (the last report before the Tuesday) |
| Depth chart | weeks 1..W of season S (the live refresh uses the newest ESPN chart; the history uses the chart of the week just played) |
| Draft information | players drafted in S or before |
| Credibility constants k1..k4 | fit on week-9 snapshots of seasons max(2009, S-10)..S-1 |
| Draft-capital prior | fit on the 10 seasons before each snapshot season |
| Role layer (injury / depth / starts) | fit on 2012..S-1 (injury and depth data start in 2012) |
| Aging, still-playing, availability models | season ends through S-2 with outcomes through S-1 (same lag as live: 2026 uses 2024) |
| Season length | 16 games before 2021, 17 from 2021; future seasons assumed the same length as season S |

No fitted model sees a single game of season S. Everything else is the live model, unchanged.

## How it works

* `hv_common.R`: copies the live scripts (`dv_common`, `dv_10`, `dv_11`, `rl_common`, `rl_dv10`, `rl_dv11_ext`) into a
  scratch folder with a fixed list of edits (`HV_EDITS`). Every edit must match the live text exactly once or the run
  stops, so a future change to the live scripts can't be skipped silently. It also wraps `readRDS()` so every data file
  is cut to the as-of date.
* `hv_01_snapshot.R S W OUT [asof|live]`: one snapshot, written to `OUT/hv_S_wWW.rds` (meta, redraft, dynasty).
  Run from the dynasty model folder (`Football2_Dynasty`). Takes about 15 seconds of model time.
* `hv_02_track_record.R SNAP OUT`: scores every snapshot against what happened next.
* `hv_03_site_data.R SNAP SCORED SITE`: writes the site files `data/history/index.json` and `values.json`.
* `run_backfill.sh`: the whole thing, in parallel.

### Proof it is the live model

`hv_01_snapshot.R 2026 10 OUT live` (no date cut, live depth-chart path) reproduces the live 2026 week-10 boards
(`dv_v4_board.csv`, `dv_ros_2026_board.csv`) exactly: 567 of 567 players, identical value and rank. In the default
as-of mode the 2026 week-10 board differs only through the depth chart / roster week timing above.

## Edits that are not about information

* Replacement pool: the live rule needs 6+ games played, and before week 10 nobody may have 6. The history uses
  min(6, max(1, floor(0.6 x W))) games, which is 6 from week 10 on, so the live board is unchanged.
* The weekly stats cache starts in 2006, so 2016-2018 snapshots were fit on fewer seasons than today's model.

## Known leaks and limits (documented, not fixable)

* **Model design hindsight**: which inputs the model uses was decided in 2026 after seeing these seasons.
* **Stat corrections**: nflverse stats include official corrections made after the games.
* **Team codes** are today's (LV for the 2016 Raiders, LA for the 2016 Rams).
* **Board population**: like the live board, a player is listed only once he has played a game that season, so a
  star who misses week 1 is missing from that week's board.
* **No rookie picks**: we have no mock drafts from those years, so pick values are not in the history.
* **League**: the reference league of the weekly archive (12 teams, superflex, 2 RB / 3 WR / 1 TE, no flex, full PPR).

## Outputs

* `history/snapshots/hv_S_wWW.rds`: the raw snapshots (not in git; rebuildable)
* `history/values/values_S.csv`: every snapshot's redraft and dynasty values, one file per season
* `history/track_record_by_snapshot.csv`, `history/track_record_summary.csv`: the scores
