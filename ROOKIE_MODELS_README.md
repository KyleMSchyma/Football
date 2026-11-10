# Rookie Fantasy Football Models

These are rookie prospect models for fantasy football (PPR), built in R as an applied
predictive-analytics project.

| Folder | Position | Summary |
|---|---|---|
| [`WR_Model/`](WR_Model/README.md) | Wide receivers | Phases 1-10: data build, targets, PPR / hit / finish-score / hurdle / tier-ladder models, value score, year-2 and year-3 breakout models, undrafted WRs, college usage/PPA test, buy/sell lists |
| [`QB_Model/`](QB_Model/README.md) | Quarterbacks | Phases 1-7: same design adapted to QBs |
| [`RB_Model/`](RB_Model/README.md) | Running backs | Phases 1-7: same design adapted to RBs, with RB8 / RB16 / RB24 tiers; summary buy/sell lists |
| [`TE_Model/`](TE_Model/README.md) | Tight ends | Phases 1-7: same design adapted to TEs, with TE8 / TE16 / TE24 tiers; summary buy/sell lists |
| [`PreDraft_Model/`](PreDraft_Model/README.md) | All four positions | Pre-draft (college-only, no draft capital or combine) player scores, class grades, position depth and player deep dives for 2010-2027 |

Each folder has its own README covering how to run it, the validation design and the
results.

## Headline results

- **Draft-time models:** at the draft, draft slot carries nearly all the predictable
  signal. College and combine data don't beat a pick-only model after the draft. Before
  the draft, they carry real but modest signal.
- **After one NFL season:** actual NFL production is the strongest signal for WRs, QBs,
  RBs and TEs. For QBs, the usage model also significantly beats rookie points alone; for WRs, RBs and TEs it does not.
- **Hidden talent:** college data can't find Day-3 or undrafted stars (Hill, Nacua,
  Renfrow, Mooney). Rookie-season production finds them.

## Setup

- **R packages:** nflreadr, cfbfastR, dplyr, tidyr, stringr, ggplot2, glmnet, ranger,
  pROC, MASS, ordinalNet.
- **API key:** a College Football Data API key in `~/.Renviron` as `CFBD_API_KEY=...`.
  It is never committed.
- **Raw data:** `cache/` folders hold raw data pulls. They are excluded from git and are
  rebuilt when you run `WR_Model/wr_phase1_data_build.R`.
- **Running the QB, RB and TE scripts here:** they read `../Football2/cache`, so either create
  that folder or edit the path.
