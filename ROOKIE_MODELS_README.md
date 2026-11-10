# Rookie Fantasy Football Models

These are rookie prospect models for fantasy football (PPR), built in R as an applied
predictive-analytics project.

| Folder | Position | Summary |
|---|---|---|
| [`WR_Model/`](WR_Model/README.md) | Wide receivers | Phases 1-10: data build, targets, PPR / hit / finish-score / hurdle / tier-ladder models, value score, year-2 and year-3 breakout models, undrafted WRs, college usage/PPA test, buy/sell lists |
| [`QB_Model/`](QB_Model/README.md) | Quarterbacks | Phases 1-7: same design adapted to QBs |

Each folder has its own README covering how to run it, the validation design and the
results.

## Headline results

- **Draft-time models:** at the draft, draft slot carries nearly all the predictable
  signal. College and combine data don't beat a pick-only model after the draft. Before
  the draft, they carry real but modest signal.
- **After one NFL season:** actual NFL production is the strongest signal for both WRs and
  QBs. For QBs, the usage model also significantly beats rookie points alone.
- **Hidden talent:** college data can't find Day-3 or undrafted stars (Hill, Nacua,
  Renfrow, Mooney). Rookie-season production finds them.

## Setup

- **R packages:** nflreadr, cfbfastR, dplyr, tidyr, stringr, ggplot2, glmnet, ranger,
  pROC, MASS, ordinalNet.
- **API key:** a College Football Data API key in `~/.Renviron` as `CFBD_API_KEY=...`.
  It is never committed.
- **Raw data:** `cache/` folders hold raw data pulls. They are excluded from git and are
  rebuilt when you run `WR_Model/wr_phase1_data_build.R`.
- **Running the QB scripts here:** they read `../Football2/cache`, so either create that
  folder or edit the path.
