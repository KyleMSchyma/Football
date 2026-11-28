# Prospect Spotlight

One-player deep dives built only from this repo's model outputs, for video and X posts (drafts for Kyle; nothing posts
automatically). Research only: nothing here changes a grade, a value or the site.

## 1. Jeremiah Smith (WR, Ohio State), the #1 2027 prospect (2026-11-28)

`ps_01_jeremiah_smith.py` reads the model files, writes `outputs/smith_facts.json` and draws eleven 1920x1080 scenes
(`outputs/frames/`, not committed; the finished video and script live in Kyle's project files
`x_posts/top_prospect_2027/`). Run: `python3 ps_01_jeremiah_smith.py` (pandas, matplotlib, pyreadr).

Inputs: `PreDraft_Model/` (grades, deep dive, drafted recalibration, WR SHAP, pool .rds, proj PPG),
`PostDraft_Model/` (2027 mock grades and proj PPG, historical post grades, grade-vs-pick test),
`Mock_Drafts/range/` (Kyle's four own mocks), `Trade_Values/dv_rookie_board_values.csv`, plus three saved extracts in
`outputs/`: Smith's CFBD season rows (from the PC cache `cfbd_stats_2004_2025.rds`, cfbfastR), the site facts from the
2026-11-25 weekly X run (site default league values), and the Nov 18 class-value study (`top24_by_class_players.csv`).

### Findings (as of the 2026-11-24 refresh)
- Pre-draft score 2.52 (A+, 100th pctile): the highest WR score in the model, 2010-2027 (next: Amari Cooper 2015, 2.44),
  and 2.3x the #2 2027 WR (Charlie Becker 1.08). Still A+ without pro-rating 2026 (2.38).
- Drivers (SHAP, log-odds): receiving yards +3.53 (1,600 on a 12-game pace; 1,200 in about 9 games), recruit rating
  +1.22, 3 years out of HS +1.13, dominator 49% +0.86, Power 5 +0.56.
- Only 9 of 2,765 eligible WR prospects (2010-2023) topped 1,600 yards; true juniors with 1,450+ (Cooks, Cooper, Adams,
  Chase, Tate) were all 2-4 star recruits; four of five had a WR12 or WR24 season.
- Tier odds (WR12/24/36, NFL years 1-3): pre-draft 72/87/93%; pre-draft recalibrated to drafted players 32/62/75%;
  post-draft at median mock pick 2 (mocks 1,1,2,2; LAC) 89/95/97%; projected PPR PPG 13.9 pre, 17.2 post/mixed.
- Value: 56,038 in the site default league (#1 rookie, #14 overall); 49,133 in the reference league, #2 of the 18 #1
  rookies since 2010 (Cooper 51,756).
- Caution: WRs drafted in picks 1-5 (2010-2023, n=6) had a fitted 73% WR12 chance and 2 hit (33%); picks 1-10 62% vs
  50% (n=16); picks 11-32 28% vs 26% (n=39). For WRs the post-draft grade adds nothing over the pick (LRT p 0.71), so
  his 89% is mostly "pick 2", and no WR in 2010-2023 went in picks 1-3 (extrapolation).
