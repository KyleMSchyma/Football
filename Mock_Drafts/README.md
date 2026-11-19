# Saved mock drafts

Kyle's own 2027 mock drafts, built in the NFL Mock Draft Database simulator under his account. They are his own user content and are kept here as a record only. Nothing in the models or the site reads this folder yet.

| File | Mock | Made | Kyle picked for | Picks |
|---|---|---|---|---|
| `2027_mock_2026-11-15_original_vikings.csv` | [#1 Mock Draft (user-mock-13881512)](https://www.nflmockdraftdatabase.com/user-mock-drafts/2027/user-mock-13881512) | 2026-11-15 | Minnesota Vikings (9 picks) | 257 |
| `2027_mock_2026-11-17_cowboys.csv` | [Mock 2 (user-mock-13882246)](https://www.nflmockdraftdatabase.com/user-mock-drafts/2027/user-mock-13882246) | 2026-11-17 | Dallas Cowboys (3 picks) | 257 |
| `2027_mock_2026-11-18_cowboys.csv` | [#3 (user-mock-13882672)](https://www.nflmockdraftdatabase.com/user-mock-drafts/2027/user-mock-13882672) | 2026-11-18 | Dallas Cowboys (3 picks) | 257 |
| `2027_mock_2026-11-19_cowboys.csv` | #4 (pasted in chat; no link saved) | 2026-11-19 | Dallas Cowboys (3 picks) | 257 |

The original mock is the one the site and the 2027 rookie pick values currently use (its 80 QB/RB/WR/TE picks).

## Columns

- `pick`: overall pick, 1 to 257
- `team_slug`, `team`: the drafting team
- `player`, `pos`, `school`: as listed on the mock
- `kyle_pick`: 1 for the picks Kyle made himself, 0 for picks the simulator made

Rounds are left out because compensatory picks make the round boundaries uneven after round 2.

Names are kept exactly as the mock shows them. A few differ from our board, for example Ryan Coleman-Williams (Ryan Williams), Hollywood Smothers (Daylan Smothers) and Quintrevion Wisner (Tre Wisner).

Mocks from other people or sites are not stored here, because their terms do not allow it.

## Pick range (built 2026-11-18, not live yet)

`combine_mocks.py` turns every `2027_mock_*.csv` here into one pick range per QB/RB/WR/TE prospect, written to `range/`:

- **Average pick**: the mean of his picks in the mocks that draft him, rounded to a whole pick (1.2 goes to 1, 1.6 goes to 2). This drives his post-draft grade.
- **Best case**: his earliest pick. **Worst case**: his latest pick, or undrafted if any mock leaves him out.
- **Value**: share of mocks that draft him x value at his average pick, plus the share that leave him out x the value of an undrafted player (based on how often past undrafted players hit a fantasy tier).

The files feed `PostDraft_Model/pd_09_mock_2027.R` (once per case), `pd_11_mixed_model.R` and `pd_12_mock_range.R`; see the top of `pd_12_mock_range.R` for the run order. To add a mock, save it here as `2027_mock_<date>_<team>.csv`, add it to the table above and rerun the pipeline.
