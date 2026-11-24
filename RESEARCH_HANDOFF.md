# Research Handoff and Update Tracker

This file lets another analyst, or another AI, pick up the whole Football / Prospect Actuary project without missing
anything. It records what exists, how it was built, every decision and assumption (with the directions each one could
have taken), what was tried and rejected, and what to do next.

**It is a living file.** Every change to the models, the research, the site or the weekly refresh must add an entry to
the [Update log](#3-update-log), update the [Assumptions register](#6-assumptions-register) if an assumption was made
or changed, and update [Future recommendations](#9-future-recommendations). See [How to update this file](#1-how-to-update-this-file).

- Created: 2026-11-22 (covers the project from 2026-11-04 to 2026-11-22)
- Last updated: 2026-11-24 (Nov 28 batch done early: redesign Phase 1, picks to 4.12, Market Check ranks, trade-type read)
- Companion documents: [MODELS_TECHNICAL_REFERENCE.md](MODELS_TECHNICAL_REFERENCE.md) (formulas, features, coefficients and
  metrics for the rookie, pre-draft and post-draft models), [MODELS_GUIDE.md](MODELS_GUIDE.md) (plain English),
  [FABLE_REVIEW.md](FABLE_REVIEW.md) (end-to-end review, 2026-11-13), the README in each model folder.
  This file does not repeat their tables; it says where they are and what was decided.

---

## Contents

0. [The project in one page](#0-the-project-in-one-page)
1. [How to update this file](#1-how-to-update-this-file)
2. [System map: where everything lives and how it runs](#2-system-map)
3. [Update log](#3-update-log)
4. [Research and builds by area](#4-research-and-builds-by-area)
5. [Closed, rejected and parked ideas](#5-closed-rejected-and-parked-ideas)
6. [Assumptions register](#6-assumptions-register)
7. [Data sources, terms of use and privacy](#7-data-sources-terms-of-use-and-privacy)
8. [Known issues, documentation drift and open questions](#8-known-issues-documentation-drift-and-open-questions)
9. [Future recommendations](#9-future-recommendations)
10. [Working rules and Kyle's preferences](#10-working-rules-and-kyles-preferences)
11. [Index of reports, artifacts and branches](#11-index-of-reports-artifacts-and-branches)

---

## 0. The project in one page

**Goal.** Kyle (an actuarial student taking the SOA PA and ATPA courses) applies predictive-analytics methods from those
courses to fantasy football, and wants to understand the models well enough to explain them to non-technical people.
The work became a public site, **Prospect Actuary** ("Evaluate. Value. Decide."), at
https://kylemschyma.github.io/prospect-actuary/.

**Three model families.**

| Family | Question | Core method | Status |
|---|---|---|---|
| Rookie prospect models (WR, QB, RB, TE; pre-draft and post-draft) | How likely is a prospect to have a top-tier fantasy season in NFL years 1-3? | Elastic-net logistic / ordinal elastic net on college stats (+ draft pick and landing spot after the draft), rolling-origin validation by draft class | Live. Grades A+ to F for every drafted QB/RB/WR/TE 2010-2026 plus the 2027 class |
| Trade values (redraft and dynasty) | What is each NFL player and 2027 rookie pick worth, on one additive 100,000-point scale, in your league? | Credibility-weighted PPG over replacement x expected games; dynasty adds aging, survival, availability, stop-loss upside over 2027-2031 | Live, refreshed every Tuesday through 2027-01-05 |
| Research studies | One-off questions (landing spot, matchups, pick strategy, interactions, starter rate, priors, fallers...) | Backtests against the live method | Results recorded in section 4; most are research only |

**Headline findings to carry forward.**

1. At the draft, draft slot carries nearly all predictable signal; college stats add little after the pick (except QBs).
   Before the draft, college stats have real but modest signal (rolling Spearman about 0.2-0.4).
2. After one NFL season, NFL production dominates; usage models tie rookie points (QBs are the exception, usage wins).
3. College data cannot find Day-3 or undrafted stars; rookie-season usage can.
4. Pre-draft A-range players who fall in the draft beat both their slot and their post-draft grade, so the live
   "mixed draft model" boosts them.
5. Trade values backtest well against point-in-time history (dynasty Spearman 0.677 vs 0.610 naive; redraft 0.644 vs 0.563).
6. Almost every attempted "upgrade" since 2026-11-17 (team offense, priors, start rate, interactions, points targets,
   PPG-model values) failed to beat the live method out of sample. The live methods are the result of that testing.

---

## 1. How to update this file

Standing rule (Kyle, 2026-11-22): **every change that adds, removes or alters research, a model, a site feature, the
refresh, a data source or a decision must update this file in the same pull request.** Research that changes nothing
live still gets an entry. A rejected idea still gets an entry.

For each change:

1. **Update log (section 3).** Add a dated entry at the top of the log in this format:

   ```
   ### YYYY-MM-DD: short title
   - What: one or two sentences on what was asked and done.
   - Result: the key numbers (with the test used) or what is now live.
   - Status: LIVE / RESEARCH ONLY / REJECTED / PARKED / CLOSED, with PR numbers (Football #n, site #n).
   - Files: folders or scripts.
   - Assumptions: ids added or changed in section 6 (e.g. "A31 changed", "A62 new").
   - Recommendations: what this suggests doing next (also added to section 9).
   ```

2. **Section 4.** Update the area's write-up (what is live, how it works, where it lives).
3. **Section 6.** Add or edit assumptions. Never delete one; mark it `SUPERSEDED (date)` and add the new one, so the
   history of choices stays readable.
4. **Section 5.** Move ideas between parked / rejected / built as they change.
5. **Section 8.** Add any new known issue or doc drift found; strike through when fixed (with the date).
6. **Section 9.** Re-rank future recommendations; mark done ones with the date and the log entry.
7. Change "Last updated" at the top.

Keep private data out (section 7): this repository is public.

---

## 2. System map

### 2.1 Repositories

| Repo | Visibility | Role |
|---|---|---|
| [KyleMSchyma/Football](https://github.com/KyleMSchyma/Football) | Public | All model code, outputs, research, docs. Weekly refresh pushes outputs to `main`. Account was renamed from `kylejoe05-ai` (Kyle's GitHub login is still `kylejoe05-ai`). |
| [KyleMSchyma/prospect-actuary](https://github.com/KyleMSchyma/prospect-actuary) | Public | Static site on GitHub Pages. Displays model output; computes league-specific values in the browser. No backend. |

Kyle usually clicks Merge himself. When he says "merge and publish immediately", threads may merge.

### 2.2 Football repo folders

| Folder | What |
|---|---|
| `WR_Model/`, `QB_Model/`, `RB_Model/`, `TE_Model/` | Rookie position models, phases 1-10 (WR) / 1-7 (others): data build, targets, draft-time models, tier ladders, value score, year-2 and year-3 breakout models, UDFAs, buy/sell lists |
| `PreDraft_Model/` | College-only model (pd_01-pd_06, pd_11 drafted calibration, pd_12 2027 declare), PREDICTORS.md |
| `PostDraft_Model/` | Post-draft grades (pd_07), predictors (pd_08), 2027 mock grading (pd_09), site page data (pd_10), mixed model (pd_11), mock range (pd_12), pick-penalty experiments (pd_20/21), `exp_*` research |
| `Trade_Values/` | dv_01-dv_15 (dynasty and redraft values, presets, page), rl_* role layer, `weekly_refresh/`, `history/` (point-in-time backfill), `archive/` (weekly snapshots), `dev_role_layer/` (Fable build reports) |
| `Track_Record/` | Frozen 2024-2026 grades (SHA-256 hashed) and scoring scripts |
| `Mock_Drafts/` | Kyle's own four 2027 mocks (full 257 picks) + `combine_mocks.py` + `range/` |
| `Landing_Spot_Offense/` | Research: team offense vs rookie production (Python) |
| `Rookie_Pick_Strategy/` | Research: rookie pick slot value, trade-downs, picks vs veterans, 2027, league guidelines (Python) |
| Root docs | README, MODELS_TECHNICAL_REFERENCE, MODELS_GUIDE, ROOKIE_MODELS_README, FABLE_REVIEW, this file, CLAUDE.md |

Research that lives only on unmerged branches: see [section 11](#11-index-of-reports-artifacts-and-branches).

### 2.3 Kyle's PC (Windows, R 4.6.1) and where models run

R model runs happen on Kyle's PC through Remote Control sessions, because the cloud container cannot install some
CRAN packages (ordinalNet) and cannot reach some hosts. Some research ran in the cloud with R from apt or in Python.

| PC folder (Documents\R Studio\) | Role |
|---|---|
| `Football2` | Rookie WR model + shared `cache/` (cfbd and nflverse pulls) |
| `Football2_QB`, `_RB`, `_TE` | Position models (repo copies read `../Football2/cache`) |
| `Football2_PreDraft` | Pre-draft model (live) |
| `Football2_PostDraft` | Post-draft model (live, unpenalized pick regrade since 2026-11-14); `mock_2027/` holds the mock used (never committed if it is someone else's) |
| `Football2_Dynasty` | Trade values (live). `tv_page_template.html` here is what the refresh uses: template edits must reach the PC before Tuesday |
| `Weekly_Refresh` | `refresh.sh`, rf_* scripts, logs; Windows Task Scheduler "Prospect Actuary weekly refresh" |
| `ProspectActuary` | Local clone of the site repo |
| `Football_repo` | Local clone of the Football repo (refresh uses a worktree; Kyle's checkout was on `revert-dynasty-model`) |
| `_backup_*` folders | Backups before risky changes (TE tiers, Fable switch-over, mixed model) |
| Dev copies (`*_dev`) | Used for the Fable build; never edit live folders in place for experiments |

The cfbd API key lives only in `Documents\.Renviron` (`R_ENVIRON_USER`); never commit it.

### 2.4 Weekly refresh (Tuesdays 10:00 AM Central, 2026-11-17 to 2027-01-05)

Details: [Trade_Values/weekly_refresh/README.md](Trade_Values/weekly_refresh/README.md). In short: pull nflverse stats,
injuries, rosters, depth charts, snaps (guarded: a failed pull reuses last week's file) -> rerun dv_13 (all 20
scoring variants, runs dv_10 + dv_11) -> rebuild the Trade Values page from the template -> until Dec 16, re-pull
2026 college stats and re-grade 2027 pre-draft prospects (pd_01, pd_06, pd_11, pd_12 declare) -> swap the `window.PD=`
data line of the grade pages (page JS edits persist) -> output gates (any failure stops the run, writes a Desktop
FAILED file + popup) -> archive snapshot (one per day) -> append a value-history snapshot -> pull Dynasty Daddy values
for Market Check -> push site and Football `main` (Kyle approved direct pushes to main).

Not rerun weekly on purpose: post-draft grades, mock grading (pd_09/11/12; rerun when Kyle adds a mock), model training.

### 2.5 Site map (prospect-actuary)

Since 2026-11-24 (redesign Phase 1): logo = home (`index.html`), then five sections in `shared/nav.js` and the phone
bottom bar: **Values** (`trade-values/`, page title "Actuarial Trade Values", dynasty default), **Usage** (`buy-sell/` =
Breakout Watch, "2026 preseason list"; `team-analytics/`), **Prospects** (`pre-draft/`, `post-draft/` with a Before
Draft | After Draft | Adjusted switch, default Adjusted = the mixed model; 2027 class by default), **Tools**
(`trade-calculator/`, `value-research/` = Market Check, `moves/`, `league/` Sleeper, `compare/`), **Research**
(`research/`, `guide/`, `track-record/`, `value-history/`, `about/`). Earlier (11-14 to 11-24): Dashboard / Prospect
Lab / Player Values / Trade Center / Research. Profiles `player/?id=`,
`compare/?ids=`. Shared code: `theme.css`, `nav.js`, `mobile.js`, `search.js`, `league.js`, `engine.js` (the one
copy of value math), `league-value.js`, `data.js`, `sleeper.js`, `moves.js`, `teams.js`. Python builders in `scripts/`
run by the `player-ids` GitHub Action. GoatCounter analytics (code `kylemschyma`) on github.io only. Folder URLs never
change (the refresh hardcodes them).

---

## 3. Update log

Newest first. Football PRs are "F#", site PRs "S#". All dates 2026 unless noted.

### 2026-11-24: Nov 28 site batch done early: redesign Phase 1 and approved value changes (F#TBD, S#TBD)
- Kyle 11-24: "Lets do all the Nov 28 work right now including the Redesign, Phase 1". Source of truth:
  project files `site_redesign/redesign_handoff_2026-11-24.md` and `saturday_2026-11-28_plan.md`.
- **Redesign Phase 1 (site, presentation only):** navy + teal tokens in `shared/theme.css` (accent #107F80, darker than
  the handoff's #148A8A so white text passes 4.5:1, A87); grade badges by family (A/B/C/D/F tints); 16px body; nav
  Values / Usage / Prospects / Tools / Research with the logo as home (2.5); new homepage (hero, search, three core
  cards Values / Usage / Prospects, "What changed this week" tabs with value movers, evidence strip, supporting tools,
  methodology statement, quiet footer; quick calculator, pick grid and freshness table removed); short intros with
  methodology folded into details on boards, Values and Breakout Watch; "Adjusted" replaces "Mixed" as the consumer
  label (mixed model stays the methodology name); Buy / Sell renamed Breakout Watch under Usage with a "2026 preseason
  list" badge (no weekly usage score; handoff rule 12); share tags (Open Graph / Twitter card, favicon, 1200x630
  card image, `sitemap.xml`). URLs unchanged.
- **Prospect boards:** 2027 class by default (`?class=` overrides, `all` = every class); new Class Rank column = overall
  rank within the class across positions, in the board's current order (Value or percentile); column stays "Value"
  (Kyle) with a "Grade vs Value" explainer that links to Values.
- **2027 rookie picks through round 4 (4.12 in 12 teams)** in the engine, calculator, Sleeper page, moves, search and
  Market Check; R side: dv_15 checks 4 x teams picks, dv_13 prints 1.01-4.12, dv_14 pulls DD 2027 1st-4th picks,
  tm_07 writes 2027 mid 1st-4th market prices. Existing player and pick values unchanged (256-league check: 0 diffs;
  +2,816 new pick rows; 12-team 4.12 = 3,784).
- **Market Check:** labelled fixed league 12-team superflex half PPR (badge says so, cannot be changed there); all
  sources now rank-matched (our value at the market's rank) and the table shows ranks and positional ranks only (no
  curve fit, no package power, A88 supersedes A83 for display); moves list market and our ranks per player; new
  "2027 rookie picks, rounds 1-4" table (market: what player rank the pick trades like; ours: our slots' rank range).
  Trade market picks from tm.js now; Dynasty Daddy picks after the next dv_14 run; DynastyProcess picks live.
- **Trade Calculator:** verdict sentence fixed (percent = how much more the bigger side gets, "you get / you give"
  wording, no "the you" typo). New secondary line "Adjusted for trade type" for dynasty trades with 3+ assets and no
  picks (`shared/trade-adjust.js`, coefficients from F#43 `ta_01_fit_market.py`, system ADD, 68,903 DD trades; 1-for-1
  unadjusted; throw-in pieces under 25% of the best asset phased out). Our additive verdict and values unchanged (A89).
- **Not built (Kyle held 11-24):** sign-off box, player notes, review sheets; profiles leading with odds (Dec 12);
  table presets, league drawer, trade tray (Dec 5).
- **Steadiness candidate** (in-season k x1.25, EWMA a = 0.7, top-10 anchor): R point-in-time rerun with a 2023-2025
  holdout running on Kyle's PC; ships only if it passes (see the next entry when it lands).
- Template: `Trade_Values/tv_page_template.html` regenerated from the live page (only the data line differs); must be
  copied to the PC's Football2_Dynasty with dv_13 / dv_14 / dv_15 before Tuesday, and tm_07 to the trade-market folder.
- Status: LIVE when the two PRs merge. Assumptions A87-A90. Issues 20-22. Recommendations R29-R31.

### 2026-11-23: Contending / Rebuild toggle for Market Check moves (site S#36)
- Kyle: add a contending/rebuild toggle to Best market moves; trades stay equal in value and follow the same rules, but
  prioritize (> 50%) the team's need: contend = redraft/now value, rebuild = future value; a contender gives a future
  piece for a contending piece and vice versa. "If the market check page doesn't have that data, then use the ratios
  from our own values to give them 'pseudo' values."
- Built (page only, `value-research/index.html`): toggle Best value (default, unchanged) | Contending | Rebuild,
  remembered per browser (`pa-vr-goal`). Dynasty only. Each player's market value is split with OUR ratio: future share
  = (our dynasty value minus its rest-of-2026 part) / our dynasty value (same split as /moves/); now share = 1 minus it.
  Contending (Rebuild) move: market-fair as before (1:1 prices for pivots, 2:1 prices for uptier/downtier), same shape
  rules (same-position lead piece > 50%), our dynasty values within 10% of each other, the side you get carries over
  half of the trade's pseudo now (future) value and more than 10% and >= 1,000 more than you give, and you give up more
  pseudo future (now) value. Ranked by pseudo need value gained. Works for all three sources (DD/DP on rank-matched values).
- Examples (trade market, 11-23 data): contending pivot Jeremiyah Love -> Christian McCaffrey; rebuild the reverse;
  rebuild downtier Gibbs -> Kenneth Walker + Brock Bowers.
- Assumption A86. Status: site PR S#36.

### 2026-11-23: Uptier / downtier shape rule (site S#35)
- Kyle (example he likes: A.J. Brown + Tucker Kraft -> Carnell Tate): the two-piece side must be led by a player at the
  single player's position, a tier or so lower (below the single player on market value), holding more than half of
  that side's market value; the other piece makes up the difference (any position). Applies to uptiers and downtiers.
- Status: site PR S#35. Assumption A85 updated.

### 2026-11-23: Market moves for every source; weekly trade-market update
- Kyle: "I want the trade data updated weekly. If our values aren't directly comparable (dynasty daddy/process) we will
  have to base it off of similar positional/overall ranking values. When it comes to a downtier, we need the same
  position back and then any position after that. Pivot can be any position. Actuarial values are included in ours."
- Page (S#34): Best market moves now show for all three sources. Dynasty Daddy / DynastyProcess use rank-matched values
  (each player gets our value at the same overall rank in that source's list; packages add on that scale). Downtier
  requires one returned piece at the same position as the player given; uptiers the same (one of the two given matches
  the received player's position; Kyle 11-23). Roster-spot caveats removed (our values
  already carry the actuarial parts).
- Weekly: `Trade_Market/tm_weekly.sh` (+ `tm_weekly.cmd`, Task Scheduler Tuesday 5:00 AM on the PC, from
  `Football2/research/dd_trades`): tm_01 dynasty pull of new weeks (TM_TYPES=Dynasty), tm_04 4-shape refit (~1.5 h),
  tm_07 -> `out/tm.js` (`tm_07_site_data.R`, an R port, because the PC has no Python; the .py stays for the cloud). refresh.sh step 4c copies tm.js to the site and the aggregate CSVs + scripts to
  `Trade_Market/` when it changed; a failed 5 AM run keeps last week's file. tm_04 meta now carries first/last trade dates.
- Status: S#34 OPEN; PC scheduling via Remote Control. Assumption A85; R28 DONE (weekly), R27 open (redraft).

### 2026-11-23: Trade market source on Market Check (S#34)
- What: Kyle chose to show the curve-matched trade-market values on the Market Check page as a third source (dynasty
  only), with the situations where the market doesn't add up listed beside them.
- How: `Trade_Market/tm_07_site_data.py` writes `value-research/data/tm.js` (log 1:1 value per player at the page's
  league: 12 teams, 0.5 PPR, SF, 8 starters; from the 4-shape run). The page fits one power in the browser so the
  market's top-150 curve matches ours (2.03 at this league), shows Our value / Market value next to the ranks, and a
  note box: 1-for-2 ~+20% for the single player, 2-for-3 ~+5%, bigger packages not used, close swaps, settings the
  market barely prices, recency, rare players. Rank correlation top 150: .86.
- Best market moves (Kyle: "publish the 1:1, 2:1 versions. 1:1 is pivot section, 2:1 is uptier/downtier"): with the
  Trade market source selected the page lists Pivots (1-for-1: market 1:1 prices within 10%, our dynasty value gain
  > 10% and >= 1,000; best target per player given) and Uptier / Downtier (2-for-1: market 2:1 package prices, i.e. the
  1:1 values to the power 2.546 at which held-out 1-for-2 trades balance, two pieces within 10% of the single player;
  same gain rule), top 200 players, plus a "moves for one player" search. Our values don't credit the roster spot an
  uptier frees.
- Status: site PR S#34 OPEN (awaiting Kyle's merge). tm.js is a static snapshot (not in the weekly refresh).
- Assumptions: A83 now LIVE once S#34 merges. Recommendation R28 added.

### 2026-11-23: Trade market values on our additive scale (research)
- What: Kyle asked to translate the market values to be additive so they compare directly with ours. Kyle's framing
  (11-23): the point is to show where the market (people's preferences) sits relative to our methodology, measured on
  our method's terms; neither is "right", only the differences are reported.
- Synthetic tests (made-up trades with known values): tm_02's settings compress values even when the true market is
  perfectly additive (fitted log-value spread 1/1.24 of the truth; a fake 1-for-2 "premium" of ~19%). Two causes:
  shrinkage toward position means (LAMBDA0 = 2) and the fact that every observed trade is roughly fair, so squeezing
  values together always looks "fairer". Rejected along the way: a per-asset roster cost (package = sum of (v - c)) is
  the same additive model, so c cannot be estimated (fit gave c .80 vs true .15 with a lower loss); a depth discount
  (k-th asset counts lambda^(k-1)) cannot be fitted because lambda = 0 with equal values makes every trade fair.
- Method (`tm_04_additive_calibrated.R`): tm_02 with light shrinkage (LAMBDA0 = 0.05), then one stretch s on the
  fitted log values (v' = v^s), s chosen so the 14-day holdout shows no consolidation gap. Synthetic: recovers the true
  spread (slope .97). `tm_05_compare_additive.py` charts the result against our values (site default league).
- Result, dynasty all trades (1.56M): s = 1.71. Kyle then asked to use only 1-for-1, 1-for-2, 2-for-2 and 2-for-3 trades
  (bigger trades are large steps): 1.18M trades, s = 2.44. Measured with straight-up prices (s = 1), the single player
  in a 1-for-2 fetches +48% over the two pieces, the smaller side of a 2-for-3 +24% (all-trade run: +34% 1-for-2).
  Making those trades fair on one additive scale needs a curve much steeper than ours (rank 24: market 25k, ours 39k;
  rank 50: 14k vs 27k), while straight-up prices give a flatter one (47k, 34k); 1-for-1 holdout error .19 at s = 1 vs
  .47 at s = 2.44, so no single additive scale fits both. Player-level differences are the same in every view: market
  above our method on J. Allen, Bijan, C. Williams, Jefferson, L. Jackson, Mendoza; below on Jeanty, McCaffrey, Stroud,
  Nacua, 2026 rookies (Tate, O. Cooper Jr., J. Love) and 2027 picks (mid 1st ~40% of ours). Spearman top 150 .889.
- Curve match (Kyle: "match an exponential function like our values so it is 1:1 with our site values";
  `tm_06_curve_match.py`): market 1:1 values raised to one power p = 1.81 so the top-150 value-by-rank curve matches
  ours (log RMSE .06; rank 24: 36k vs our 39k). Kyle chose to KEEP this curve-matched scale. Position level: QB +2%,
  RB -2%, WR -8%, TE +22%. Market above our method: C. Williams 56k vs 33k, Jefferson 48k vs 25k, Allen 88k vs 66k,
  Bijan 78k vs 56k, L. Jackson, Mendoza, Achane, McBride; below: Jeanty 32k vs 54k, O. Cooper Jr., Stroud, McCaffrey,
  Nacua, Gibbs, Tate, Goff, J. Love; 2027 mid 1st 18k vs 24k. On held-out trades at this scale: 1-for-2 lone player
  still +20% over the sum, 2-for-3 +6%, 1-for-1 typical miss 34% (19% at raw 1:1). Kyle asked for these exceptions to
  be listed on the site; where it goes on the site is pending his choice (Market Check source recommended).
- Redraft: run paused by Kyle at the final fit (holdout chose s = 2.12; reference fell back to a player because
  redraft has almost no 2027 1st trades). Kyle: focus on dynasty.
- Status: RESEARCH ONLY. Files: `Trade_Market/tm_04_additive_calibrated.R` (TM_SHAPES, TM_TAG options),
  `tm_05_compare_additive.py`, `out/dynasty_add_*.csv`, `out/dynasty_add4_*.csv`, `compare_additive/`, `compare_add4/`.
- Assumptions: A80-A82 added; A75 kept and annotated. Issue 18 updated, 19 added. R23 done; R26-R27 added.

### 2026-11-23: "Trade" value method from real trades (research)
- What: Kyle asked for a separate value method built from real trades, recent trades more credible, only leagues our
  settings can describe, comparable to any scoring setting, NOT built into the current values. Sleeper's Terms of Use
  ban crawling other leagues without approval, so the data comes from the Dynasty Daddy Trade Database instead (DD's
  owner told Kyle he may use it, 11-22). Pulled 1.80M dynasty trades (since 05-01) and 710k redraft trades (since 09-01)
  on Kyle's PC; fit on 1,562,946 / 686,944 usable trades from 180k / 190k leagues.
- Method: each trade treated as fair; log value of each asset = theta + position-specific setting terms (SF, full PPR,
  TE premium, team count, starters); robust (Huber) fit of log(sum side A) - log(sum side B) = 0. Long-run fit plus a
  credibility fit: weight 0.5^(age/H), shrink to long-run with k, Z = I/(I+k). H, k chosen on a 14-day time holdout.
- Result: best H = 7 days, k = 2 in both formats (edge of grid). Holdout mean |log gap| dynasty .296 vs .341 all trades
  equal and .305 last 30 days; redraft .285 vs .301 / .293. Rank agreement with our values, top 150 at the site default:
  dynasty Spearman .897, redraft .837 (48 settings: dynasty .82-.90, redraft .71-.89). The market is NOT additive: the
  fewer-asset side fetched +35% (1-for-2), +54% (1-for-3), +67% (1-for-4) over the additive fit, so trade values are
  much flatter than ours. The market barely prices settings: SF off cuts top QBs 35% (ours 66%); TE premium +1 lifts top
  TEs 16% (ours 116%); PPR and team count move prices 2% or less. Market pays more for Jefferson, C. Williams, L. Jackson,
  J. Allen, Bijan; less for Jeanty, Nacua, CMC, Stroud, Tate. 2027 mid 1st 27.7k (ours 24.0k), mid 2nd 15.6k (9.8k).
- Status: RESEARCH ONLY (nothing on the site). Files: `Trade_Market/` (tm_01 pull, tm_02 fit, tm_03 charts,
  `out/` aggregates without league ids, `compare/` charts). Report: https://claude.ai/artifact/D57WtFX8mNemAZ647ujpz5
- Assumptions: A75-A79 added. Recommendations: R23-R25.

### 2026-11-23: Mock range capped at the median
- What: 8 of 94 mocked prospects had a worst case worth more than the median, or a best case worth less. Cause: the
  mixed model's faller bump, not landing spot (landing spot barely matters: WR zero, RB vacated touches x1.08/SD, TE
  vacated targets x1.17/SD). A later pick drops the plain grade below A-, he becomes a "faller", and the bump (odds about
  x2) lifts him above his median (CJ Carr, Mensah, KJ Duff, Leavitt, Hoover); Luke Reynolds is the reverse (boosted at
  the median, not at his best pick); Chambliss and Dante Moore are small landing-spot differences.
- Fix (Kyle: "fix it where it gets the boost, but it maxed out at the median"): `pd_12_mock_range.R` keeps each case's
  boost but caps worst-case odds and grade at the median's and floors the best case at the median's, tier by tier, for
  both the mixed and plain post-draft ranges. Rejected: faller status fixed at the median pick; best/worst from the plain
  model only.
- Status: built; goes LIVE with the next PC rerun of pd_12, dv_13, pd_10. A74.

### 2026-11-23: Proj. PPG column on the draft boards (F#33, S#33)
- What: Kyle approved both PRs and asked for projected 3-YEAR PPG (not total points) next to the grade, on the pre-draft,
  post-draft and mixed boards, wired so the weekly refresh keeps it.
- Result: new `PreDraft_Model/pd_14_proj_ppg.R` and `PostDraft_Model/pd_13_proj_ppg.R` (elastic net on the grade's own
  inputs, target = PPR points per game over seasons 1-3 for players who played, weighted by games; past classes
  out-of-class, 2024+ and the 2027 mock from a final 2010-2023 fit). Out-of-class Spearman with actual 3-yr PPG:
  post-draft QB .61, RB .59, WR .59, TE .59; pre-draft QB .25, RB .43, WR .35, TE .31. Mixed view adds a faller bump in
  PPG (QB +3.9, RB +1.5, TE +1.7, WR +0.9; 11-27 fallers each, noisy). `rf_02_predraft_page.R` and `pd_10_site_page.R`
  write `pp` (mixed / pre) and `ppd` (plain post-draft) into the data lines; `refresh.sh` runs pd_14 (with the pre-draft
  regrade) and pd_13 (before pd_10), both guarded (a failure keeps last week's CSV). Site: "Proj. PPG" column after Grade,
  note above each board; the Post-draft switch shows `ppd`.
- Status: LIVE once F#33 and S#33 are merged AND the four scripts are copied to the PC (pd_13 + pd_10 to
  Football2_PostDraft, pd_14 to Football2_PreDraft, rf_02 + refresh.sh to Weekly_Refresh). Until the PC has them, the
  refresh rewrites the data lines without `pp` and the column shows blank (no error).
- Display only: grades, Value and pick prices do not use it (A73).
- Assumptions: A72, A73 added. Recommendations: R22.

### 2026-11-22: Dynasty Daddy historical values (research)
- What: Kyle asked whether Dynasty Daddy has time-stamped historical values. Checked the documented API, DD's front-end
  code and the history endpoints it calls, from Kyle's PC (cloud is blocked).
- Result: yes, via UNDOCUMENTED endpoints: `/api/v1/player/{name_id}?isAllTime=true` (one row per day per player) and
  `/api/v1/player/all/prev/{days}` (top-500 board N days ago). DD's own values (`daddy_*`, = public API today) start
  2024-08-01 (~2.3 seasons); DD v2 from 2026-08-26; FantasyCalc and DynastyProcess from 2023-05; the 2021+ unprefixed
  fields are KeepTradeCut (never use). 1QB and SF for every market; redraft 0 in the offseason. DD weekly noise
  ~2% median with one-day spikes. No ToS page found; the docs only ask to cache and keep load low.
- Status: RESEARCH ONLY (nothing pulled by the refresh, nothing on site). Files: `Trade_Values/research/dd_history/`
  (README, weekly sample for 4 players, chart). PR: this one.
- Assumptions: A71 added; A51 unchanged.
- Recommendations: R21 (ask DD permission, then one paced history pull and a market backtest).

### 2026-11-22: Research handoff and update tracker (this file)
- What: Kyle asked for one exhaustive, always-updated handoff of all research, with an update log, an assumptions
  register (with alternative directions) and future recommendations at each update.
- Result: this file, a root `CLAUDE.md` with the standing update rule, README link, project memory rule.
- Status: Football PR #35, open for Kyle's merge.
- Assumptions: register A1-A70 created from the full history.
- Recommendations: see section 9; first priorities are the offseason plan (R1-R5).

### 2026-11-22: Rookie pick strategy research merged (F#34)
- What: which rookie slots pay off vs price (2010-2023), trade-downs, picks vs veterans, 2027 class, Kyle's two leagues.
- Result: keep 1.01 (1.15x price; 14/14 any-tier, 10/14 top tier); 1.02-1.03 0.70x (QB busts); 1.04-1.06 1.2x; cliff after
  1.06 (top-tier 49% vs 20%, Fisher p = .0002); top 10% of picks = 59% of value; position not significant beyond price
  (elasticity 0.86). 2027: same shape, cliff after 1.07; late 2nds/3rds priced above history (sell). Cheap (<10k) picks
  beat cheap veterans (1.24-1.34x vs .44-.60x); at 20-35k prime vets 25-27 beat picks (1.19x vs .88x). League versions in
  the README.
- Status: RESEARCH ONLY (nothing on site), merged to main. Files: `Rookie_Pick_Strategy/`.
- Recommendations: R20 (surface pick-slot history on the Picks tab, only if Kyle asks).

### 2026-11-21: Kyle's league advice (League of Lampoons)
- What: trade and roster advice for Kyle's 10-team league using the site values and the pick research.
- Result: advice only. Personal trade details are kept in project memory, not in this public repo.

### 2026-11-21: PPG-model values, top-24 split, hybrid (research)
- What: price rookies from PPG models (rookie or years 1-3 PPG over replacement) instead of the tier method; split the
  test at the consensus top 24; hybrid (PPG for top 24, tiers outside).
- Result: PPG values Spearman .519/.516 vs live .540 (gap CI overlaps 0); top-12 rookie-draft realized 1231/1236 vs 1300.
  Hybrid .491/.488 vs .494. None beat live. Live over-values top 24 slightly (pred/actual 1.09); PPG models under-value
  outside top 24 (.78-.81).
- Status: REJECTED for values. Files: branch of F#33 `Interaction_Research/points_projection/` (pp_06, pp_09), project
  files `research/points_projection/`.

### 2026-11-21: Projected 3-year points column (preview)
- What: show projected 3-yr points next to grades (pre, post and mixed versions).
- Result: mixed points fix fallers' level but do not rank better. Rookie value backtest 2016-22: live tier method best
  at every position (cross-position Spearman .540 vs year-1 points .501, 3-yr points .495, mixed .502).
- Status: site S#33 DRAFT preview, do not merge (refresh would overwrite it; needs an R generator to go live).

### 2026-11-20: Squared and interaction terms (research)
- What: test x^2 and pairwise products (inspired by ATPA `pairs(auto)`), H-statistics, GAM curvature, collinearity.
- Result: pre-draft up to 10-15% worse log loss; post-draft no reliable gain; 2 of 133 GAM checks curved; huge VIF (QB
  171k) but elastic net handles it. Points vs hits: log(1+3yr pts) ranks pre-draft WR/TE better (CIs > 0); year-1 hit
  model weakest. Trade values: still-playing model + cppg^2 + cppg:age + lpick:exp improves log loss 0.4-2.4%, but the
  value-level backtest moved Spearman only .699 -> .700 and QB A/E got worse (.917 -> .877).
- Status: Kyle DECIDED leave it out. Research on F#33 (open). Assumption A13, A40.

### 2026-11-20: Starter rate and "Market adjusted" toggle
- What: should players started less in fantasy lineups (or spiky scorers) rate below steady starters at the same PPG?
  Then: apply it to trade value via ESPN % rostered.
- Result: 9 PPG variants, none beat live (rolling 2019-2025); NFL-starter-only and snap-weighted games clearly worse.
  ESPN rostered %: lightly rostered QBs sell ~0.68x our value on Dynasty Daddy and DynastyProcess (WR/TE no gap). A
  toggle (multiplier 0.85 at rel <= 0.5 to 1.0 at rel >= 0.9) was built (F#32 + S#32).
- Status: CLOSED unmerged the same day. Kyle: "I don't want anything published yet. Just research." Code kept on branch
  `claude/project-thread-m614pm`. Rostered/start % is only ever for trade value, never for predicting production.
- Follow-up (11-20, research): % started with week-11 byes (ATL, CLE, GB, LA, NE, SEA) and injured players removed
  (n=108). At equal value and rostered %, the start/rostered ratio predicted a higher Dynasty Daddy price (+0.77 log,
  95% +0.43 to +1.18) but nothing on DynastyProcess (-0.01, -0.50 to +0.53). One week is too thin. The model already
  has a season-level "theoretical start %" (redraft: hard cut at the replacement line; dynasty: E[(PPG - rep)+]), but
  not weekly start/sit. Kyle (11-20): start % is a crowd-trust signal to compare with our model ("who should be
  trusted"). Proposed test: when our model's start chance and the crowd's start % disagree, who is right over the next
  4 weeks (redraft) and next season (dynasty value)? If we win, the gap is a buy-low / sell-high signal. Needs 4-6
  weeks of archived ESPN start % first (not set up; nothing published).

### 2026-11-20: CJ Stroud QB3 explanation
- What: why Stroud ranked QB3 on the dynasty board.
- Result: credible PPG 18.5 (2026 20.5 over 9 games with ~60% weight vs 15.3 in 2023-25), age 24.9 keeps ~19 PPG through
  2031, 90% still starting 2030. Market has him QB11-13. Not a bug; it shows the small-sample weight on the current
  season (A31) and that IR players (Lamar, Hurts) drop.

### 2026-11-19: Fourth mock; mock range rebuilt (F#29 closed, F#30, F#31, S#31)
- Result: 94 prospects, 93 graded (Sorsby ungraded: board lists him in the 2026 class). All 7 gates passed.
- Quirk: worst case can beat median when the landing team differs or the mixed boost applies only at one pick.

### 2026-11-18: Mock pick range (F#28, S#29, S#30)
- What: grade each 2027 prospect at his MEDIAN pick across Kyle's mocks (Kyle changed from mean), show best/worst, value
  = share drafted x value at median + share undrafted x undrafted value.
- Result: LIVE 2026-11-19. Undrafted base rates (2010-23 UDFAs): RB any-tier 2.5%, WR 1.7%, TE 1.6%, QB 0%.
- Assumptions A26-A29.

### 2026-11-18: Saved mock list (F#26, F#27)
- Kyle's own mocks only, full 257 picks, in `Mock_Drafts/`. Not used by models beyond the range pipeline.

### 2026-11-18: Model parity rule
- Kyle: anything that feeds the mixed model must also feed post and pre models where applicable. A25.

### 2026-11-18: Rookie-model prior for player values (F#25 open, research)
- What: the parked "Bühlmann-Straub prior swap": replace the draft-pick credibility prior with prospect-model priors.
- Result: no version beats the pick prior (<1% PPG error change; rolling version worst). Not adopted. A31.

### 2026-11-18: 2027 rookie class total value
- Result: 2027 top 24 = 426k, 8th of 18 classes (avg 399k; best 2015 502k; worst 2013 282k). Jeremiah Smith 51.7k is the
  highest #1 rookie of any class. 8 QBs in the top 24 (normal about 4). Research only; project files
  `research/rookie_class_value/`.

### 2026-11-18: Site analytics (S#27, S#28)
- GoatCounter, injected by `shared/nav.js` on github.io only; `#no-count` opts out.

### 2026-11-18: Rookie grade model switch (S#26, F#24)
- Pre-draft | Post-draft (`?model=post`) | Mixed (default). pd_10 writes `dr` (plain post-draft values) for boosted rows.

### 2026-11-17: Mixed draft model (F#22, F#23, S#24, S#25)
- What: players with a pre-draft A-range grade who fell below A- after the draft.
- Result: fallers (n 75) hit any-tier 40% vs ~25% predicted. Flat odds bump best in LOCO backtest (log loss -13, CI -28.6
  to +0.1, 9/14 classes). LIVE: `pd_11_mixed_model.R` offset-logistic bump (odds about x3.2 / 2.0 / 2.3 by tier), only
  fallers' grades change (89 changes). Must rerun after every pd_07/pd_09, before dv_13 and pd_10. A24.

### 2026-11-17: Landing-spot offense (F#20)
- Result: holding the post-draft score fixed, prior-year team offense adds ~0 for RB/WR/TE; QB rookie year -0.9 pts/game
  per SD (sitting behind a starter), fades by years 1-3. Pre-draft QB effect is mostly draft capital. REJECTED as a model
  input. A11.

### 2026-11-17: Team matchup projections (F#19 open, research)
- Result: multiplicative Bühlmann credibility (offense x opponent defense) R² 9.1%; v2 with closing lines + weather/home
  Poisson GLM R² 17.6%; ceiling ~15-24%. Head-to-head, the higher projection wins 65%. Not on site.

### 2026-11-17: NFL Team Analytics (S#22), profile NFL sections (S#21), phone layout (S#20)
- Team offense PPG split passing/rushing/receiving and points allowed by position, 2016 on, scored in the browser.
- Profiles: NFL production and usage; 5 nearest past seasons as comparables (outcomes, not forecasts; not in values).
- Phones keep the light theme (Kyle's choice over the dark spec). `shared/mobile.js` + CSS block at end of theme.css.

### 2026-11-17: 2 FLEX footer restore (F#21, S#23)
- The Nov 17 refresh used the old PC template and reverted footer text. Lesson: template edits must reach the PC.

### 2026-11-16: Contending / Rebuild moves (S#19)
- One-for-one swaps within 10% dynasty value; Contending = >10% more redraft value; Rebuild = >10% more future value.

### 2026-11-16: Point-in-time value history 2016-2026 (F#18, S#18)
- What: rebuild weekly values as the refresh would have produced them each Tuesday using only data known then.
- Result: 185 snapshots; live mode reproduces live 2026 week 10 exactly. Dynasty Spearman .677 vs naive .610 (pred/actual
  .936); redraft .644 vs .563 (1.091). Tuesday refresh appends each week. No historical rookie pick values (Kyle).
- Leak found and fixed for the history: dv_10 k1-k4 were fit on all 2016-2025 seasons. A48.

### 2026-11-15: Kyle's 7-round mock replaces Renner (F#16, S#16)
- 80 QB/RB/WR/TE picks from Kyle's own MDDB simulator mock (his user content). LIVE same day.

### 2026-11-15: Site default league = 2 FLEX (F#17, S#17)
- 12 teams, SF, full PPR, 4-pt pass TD, 1QB/2RB/3WR/1TE/2FLEX (code `12_1_0_4_1_2_3_1_2_0_0_0_0`). R models keep the no-flex
  reference league. A32.

### 2026-11-15: Weekly X post drafts set up
- Tuesday values, Wednesday 2027 rookies; drafts only (Kyle posts himself). Tools in project files `x_posts/weekly/`.

### 2026-11-14: Sleeper integration (S#14, S#15)
- `/league/`: settings auto-fill, priced rosters, team ranks, needs map, trade partners, calculator gap-fill.

### 2026-11-14: Releases 1-2 of the unified platform (S#9-S#13, F#11-F#15)
- Five sections, navy/orange, player ids, profiles, compare, saved leagues, data status, snapshots with ids/versions,
  table layout rules (header always visible, only Rank frozen, one trade button). Release 3 (snapshots charts,
  risers/fallers, exports) was not approved; parts later arrived via Value History.

### 2026-11-13 to 11-14: Fable Review and full build (F#10, S#8)
- Review: 10 priority findings (FABLE_REVIEW.md). Kyle: "Do it all", test each change before it replaces anything.
- KEPT: status-based expected games (redraft Spearman .669 -> .686), horizon-specific stop-loss sd (dynasty pred/actual
  1.20 -> 0.99), QB depth rank + share of starts (backup QBs 1.43 -> 0.92 of actual), guarded refresh with 6+ gates,
  archive, failure alert, post-draft regrade with log_pick unpenalized (Spearman up every position; 356 of 1,351 letter
  changes), 2027 P(declare) adjustment, Track Record and Buy/Sell pages, nearest-100 display, "Too close to call" within
  10%, Known limits notes.
- DROPPED (worse out of sample): QB P(start) x starter value, snap share/depth in PPG, direct horizon models, still
  playing = 4+ games, old-age fixes, lambda.1se, usage-model prior for years 1-3.
- Pick multiplier now 1.03 (95% 0.73-1.34). LIVE on PC 2026-11-14.

### 2026-11-13: Navigation redesign (S#7)
- Rookies / Trade / Guide menu, board first, Market check renamed from Value research. All URLs kept.

### 2026-11-13: Dynasty window extended to 2031 for all players and picks; pick calibration
- Kyle: everyone valued over the same period. Pick tier values calibrated so 2016-22 round-1 backtest lands ~1.0 (was 20% low).

### 2026-11-12: Many site and model builds
- Trade Calculator (S#2), All-positions tab + 2027 on both boards (S#3), Value Research vs DynastyProcess and Dynasty
  Daddy (S#4, S#5), 2027 post-draft grades from a mock (F#8, S#1; Renner mock, fantasy picks only, credited).
- TE tiers changed to 6/12/18 (F#9, S#6); pre-draft TE switched to ensemble. A2.
- Pre-draft drafted-player recalibration + cross-position Value column (pd_11 drafted calibration, dv_13). A15.
- First-down bonus and customizable scoring LIVE. A42.
- 2027 picks priced with the post-draft model at Kyle's mock slot; non-mocked prospects with pre-draft. A39.
- KTC compared and rejected on terms (A51). X rookie guide (QB set drafted; branch `claude/project-thread-e3qnnu`).

### 2026-11-11: Trade values v1, league customization, weekly refresh, predictors pages
- Kyle's value rule: points over replacement per game, credible PPG, injury factor, 100k scale, additive. Redraft = rest
  of 2026; dynasty = plus future seasons. Survival-based "Dynasty Value Score" with an anchor-trade exponential curve
  (dv_08) was merged (F#3) then reverted (F#4) as not ready; replaced by the additive per-game method. A30.
- Customizable leagues LIVE: 8/10/12/14 teams, 0.5/1 PPR, TE premium, pass TD 4/5/6, SF, starters, flex.
- Weekly refresh set up (F#7 closed; refresh pushes to main). PREDICTORS pages (F#5, F#6).

### 2026-11-10: Rookie models complete, pre-draft and post-draft grades, docs, public site
- WR phases 1-10, QB/RB/TE phases 1-7 run on the PC. Pre-draft model (pd_01-06), post-draft grades, FCS translation,
  conference test (rejected). Docs: technical reference + guide. Main brought up to date (F#1, F#2). Public site repo launched.

### 2026-11-04: WR model roadmap
- Plan: WR-only first, years 1-3 PPR + top-24 hit, elastic net + credibility, rolling origin by class, pick-only
  benchmark. Phase 1 scripts written. Built on Kyle's ATPA coursework (`ATPA/Module/Rookie_Model`), which found XGB RMSE
  3.19 vs null 4.27 for rookie PPG and the draft_picks career-yardage leak.

---

## 4. Research and builds by area

### 4.1 Rookie position models (WR, QB, RB, TE)

- **Live use:** source of the post-draft tier ladders (ordinal elastic net) that become post-draft grades; tier
  calibration for rookie pick values; year-2/3 models feed buy/sell lists only.
- **Design:** one row per drafted player, classes 2010-2026; targets = best finish in years 1-3 as nested tier hits,
  3-yr points, finish score; pick-only benchmark; leakage-safe in-fold preprocessing; strict rolling origin (train <=
  Y-3) as the headline test, LOCO as an optimistic check; 2,000-draw paired bootstrap for every comparison.
- **Results:** post-draft elastic net never significantly beats pick-only (sometimes worse: QB points, RB top-24, RB
  ladder). Year-2 usage beats pick and ties rookie points except QB (usage significantly better). Day-3 WR hits (Hill,
  Renfrow, Mooney, Davis, St. Brown, Doubs, Nacua) found by rookie usage, not by college data.
- **Details:** MODELS_TECHNICAL_REFERENCE.md section 2 and each folder README.
- **Not used anywhere live:** year-2/year-3 usage models in dynasty values (tested as a prior 2026-11-13, dropped).

### 4.2 Pre-draft (college-only) model

- **Spec (Kyle):** no draft pick, no landing spot, no combine; college production, usage shares, age proxy, recruiting,
  Power 5 flag, FCS translation. Use model comparison, PDP/ICE, SHAP.
- **Pool:** every draft-eligible college player (not just drafted), so P(tier) includes the chance of never being drafted.
- **Chosen models** (rolling BSS rule): QB enet, RB enet, WR 5-input logistic, TE ensemble (enet + RF + xgb) since TE6/12/18.
- **Grades:** score = P(top) + P(top two) + P(any); A+ top 5% ... F bottom 10% among drafted players 2010-2023 at the
  position (fixed cut points, within position). 2010-2023 use LOCO predictions.
- **Validation:** any-tier hit ~59% A range, 31% B, 14% C and below (C/D/F similar, so grades separate the top). Grade adds
  to pick significantly only for QBs. Rolling hit rates (Fable build): A 62% pre-draft.
- **Drafted recalibration** (pd_11_drafted_calibration.R): two-parameter logit map on drafted rows fixes the ~30% low level
  for pricing; grades unchanged.
- **2027:** in-progress college season pro-rated to 12 games (and an as-is version); re-pulled weekly until Dec 16;
  P(declare) adjustment (pd_12_declare_2027.R) multiplies non-declared underclassmen by a refit P(declare) (picks 1.01-1.04
  unchanged, rest of R1 -10-20%, R2 -30-50%).
- **Details:** technical reference section 3, PreDraft_Model/README.md, PREDICTORS.md.

### 4.3 Post-draft grades and the mixed draft model

- **Post-draft:** ordinal elastic net on the pre-draft features + log_pick (unpenalized since 2026-11-14) + vacated
  share + incumbent production. Hit rates by grade band (pre -> post): A 59 -> 66%, B 28 -> 34%, C 14 -> 10%, D/F 13 -> 4%
  (rolling version: A 75% post, D/F 9%).
- **Mixed (default on site):** pd_11_mixed_model.R boosts pre-draft A-range players who fell out of A after the draft.
  Rewrites post-draft and 2027 mock CSVs in place, keeps `*_draft` columns (plain post-draft) for the model switch.
- **Run order:** pd_07 -> pd_09 (x3: median, best, worst) -> pd_11 -> pd_12 -> pd_13 (Proj. PPG) -> dv_13 -> pd_10.
- **Proj. PPG (2026-11-23):** pd_13_proj_ppg.R writes projected 3-year PPG (plain and mixed) for the board and the 2027
  mock; pd_14_proj_ppg.R does the same for the pre-draft board. Display column only (A72, A73).

### 4.4 The 2027 class: mocks and pick range

- **Draft-capital placeholder:** Kyle's own MDDB simulator mocks (four, 2026-11-15 to 11-19). Grade and value at the
  median pick across mocks that draft the player; best/worst case shown; undrafted share priced at UDFA base rates.
- **History of the placeholder:** StickToTheModel 100-pick mock (2026-11-11, private, never used in values) -> Renner mock
  (2026-11-12 to 11-15, 30 fantasy picks credited on site) -> Kyle's 7-round mock (11-15) -> median of four mocks (11-19).
- **Prospects not in any mock:** pre-draft model, drafted-recalibrated, x P(declare).
- **To add a mock:** save the CSV in `Mock_Drafts/`, run `combine_mocks.py --aliases <alias file>`, merge, then on the PC
  pd_09 x3, pd_11, pd_12, copy mock grades to the site, refresh.sh. MDDB pastes drop picks at page breaks; check 257 rows.

### 4.5 Trade values (redraft and dynasty)

- **Rule (Kyle, 2026-11-11):** value = fantasy points over replacement per game x expected games; 100k scale where the
  top player = 100,000; values add. Redraft = rest of 2026. Dynasty = rest of 2026 + 2027-2031 for every player and pick.
- **Credible PPG (dv_10):** last-3-season games-weighted PPG blended with a draft-pick regression prior
  (Z = g/(g+k2)), then 2026 PPG blended with Z = n/(n+k1). Current k (default scoring): QB k1 5.9 / k2 15.4, RB 3.8 /
  25.3, WR 3.8 / 9.0, TE 4.4 / 6.9; availability k3/k4 QB 6.7/51.9, RB 5.4/91.1, WR 5.8/185.7, TE 7.6/54.0.
- **Expected games:** status-based (IR / Out / Doubtful / Questionable / starter / backup) role x health with credibility
  (Fable A2).
- **Dynasty (dv_11):** value = sum over t of v^t x S(t) x G(t) x E[(PPG_t - rep)+], v = 1/1.15; PPG_t from a fitted
  aging model; S(t) logistic still-playing model (QB adds depth rank + share of starts); stop-loss upside with
  horizon-specific sd.
- **Leagues (dv_13):** 20 per-position scoring runs (pass TD x first-down bonus for QB; PPR x FD for RB/WR; TE catch value
  x FD) precomputed weekly; lineup settings (teams, SF, starters, flex) computed in the browser (replacement lines by
  filling every lineup; flex greedily by projected PPG).
- **Rookie picks:** tier probabilities x tier calibration (games, PPG, spread by tier and season from 2010-2022 classes,
  season 5 from 2010-2021) with age adjustment, x a calibration multiplier (1.03, 95% 0.73-1.34) so 2016-22 slots
  1.01-1.12 match realized. 2027 rounds 1-4 valued since 2026-11-24 (rounds 1-3 before); picks shown as slots, not names (Kyle).
- **Backtests:** dynasty pred/actual ~0.99 after Fable; point-in-time history in 4.7.
- **Known weak spots:** backup QBs still somewhat above market; old QB survival high (Fable 8, fixes failed);
  small-sample current-season weight (Stroud).
- **No technical-reference section yet** for trade values (see R9); code headers in dv_10, dv_11, dv_13 and the Fable
  build report are the best documentation.

### 4.6 Market comparison and track record

- **Market Check** (`/value-research/`): ranks vs Dynasty Daddy (default; dynasty + redraft, cached weekly by dv_14),
  DynastyProcess (dynasty, live with fallback) and the Trade market. Fixed 12-team SF half PPR (labelled on the page and
  badge since 11-24). Overall + positional rank differences only; every source rank-matched for moves (A88). 2027 pick
  table rounds 1-4 (11-24). Never KTC.
- **Dynasty Daddy history** (research 11-22, `Trade_Values/research/dd_history/`): daily DD values exist from
  2024-08-01 via undocumented endpoints (player history, whole-board `prev/{days}`); also FantasyCalc/DynastyProcess
  from 2023-05. Not pulled; permission to be asked first (R21). Use: backtest our values vs the market over time.
- **Trade Market values** (research 11-23, `Trade_Market/`): a separate "trade" method from 1.56M dynasty and 687k
  redraft real trades (Dynasty Daddy Trade Database, with permission). Values solved so trades balance, with setting
  terms by position and recency credibility (H = 7 days, k = 2 by holdout). Ranks agree with ours (dynasty .90,
  redraft .84 Spearman); the market pays a large consolidation premium and barely adjusts for PPR, TE premium or team
  count. Not on the site. See the 11-23 log entry. Market Check moves have a Best value | Contending | Rebuild toggle
  (S#36, A86): contending/rebuild moves split market values with our now/future ratio. On our additive scale (tm_04, 11-23): the market pays a large
  consolidation premium (+48% for the single player in 1-for-2 trades at straight-up prices), so one additive market
  scale is either flatter (straight-up prices) or much steeper (package-fair) than ours; player-level differences
  (Allen, Bijan, young QBs above ours; Jeanty, CMC, Stroud, rookies, picks below) hold in both views.
- **Track Record** (`Track_Record/`, `/track-record/`): 2024-2026 grades frozen 2026-11-13 with hashes; scored as
  outcomes arrive.
- **Value History** (`Trade_Values/history/`, `/value-history/`): weekly point-in-time values 2016+, scored against what
  happened.

### 4.7 Point-in-time value history

See [Trade_Values/history/README.md](Trade_Values/history/README.md). As-of rules: games before that Tuesday only;
draft known from May; credibility k's, priors, role layer, aging/survival refit each season on earlier seasons only;
early-week replacement pool min games = min(6, max(1, floor(0.6W))). Remaining leaks: nflverse stat corrections,
hindsight model design.

### 4.8 Site features (beyond the boards)

Trade Calculator (gap-fill suggestions, "Too close to call" inside 10%), Sleeper league page (needs, partners), Contending /
Rebuild moves, Buy/Sell page, Team Analytics, profiles with NFL comparables, compare, saved leagues, data status, phone
layout, homepage movers ("What changed this week"). Calculator "Adjusted for trade type" line (11-24, A89). Share tags,
favicon, sitemap (11-24). Details in the site README and memory notes listed in section 11.

### 4.9 Research studies (one-offs)

| Date | Study | Answer | Status |
|---|---|---|---|
| 11-12 | QB grade drop pre -> post | 11 of 27 pre-A QBs fell out of A, mostly later picks; several still hit (Wilson, Lamar, Watson, Nix) | Led to the mixed model |
| 11-12 | Tier system review | Keep best season yrs 1-3, season totals; 3/2/1 weights don't change ranks; TE to 6/12/18 | TE change LIVE |
| 11-17 | Landing-spot offense | No effect beyond post-draft grade | Rejected |
| 11-17 | Team matchup model | R² 9-18%, credible tilt, not a point forecast | Research (F#19 open) |
| 11-17 | Grade fallers | Fallers beat slot and post grade | LIVE as mixed model |
| 11-18 | Class total value | 2027 = 8th of 18 | Research |
| 11-18 | Prospect-model prior | No gain over pick prior | Rejected (F#25 open) |
| 11-20 | Starter rate / market adjusted | No PPG gain; market discount is a QB effect | Closed, research only |
| 11-20 | Interactions / squared terms | No gain for rookies; tiny gain for still-playing model left out | Rejected (F#33 open) |
| 11-20/21 | Points / PPG targets | Better pre-draft WR/TE ranking by points, but values worse | Display-only preview (S#33 draft) |
| 11-21 | Rookie pick strategy | Keep 1.01, cliff after 1.06, sell late 2nds/3rds | Research (F#34 merged) |

Earlier one-offs inside model work: conference as predictor (rejected), college usage/PPA (not adopted; only 2014+), WR
value score (Day-3 tiebreaker only), WR finish/hurdle/tier ladder (no gain vs pick), UDFAs (no conclusion changes).

### 4.10 Social posts (X)

Drafts only; Kyle posts. Weekly tools in project files `x_posts/weekly/` (extract.js runs the site's engine on committed
data; render.js makes a 2400x3000 navy/orange top-24 image with an OVR column; gated on a weekly refresh commit).
2027 rookie guide (pre-draft model only, QB first, one position per approval) on branch `claude/project-thread-e3qnnu`.

---

## 5. Closed, rejected and parked ideas

| Idea | Date | Outcome and reason | Revisit if |
|---|---|---|---|
| KeepTradeCut values | 11-12 | Never use: terms ban scraping and reuse on another site | KTC grants written permission |
| Crawl Sleeper leagues for trades | 11-22 | Sleeper Terms of Use 11.1/11.3 ban crawling and automated collection without written approval; used the Dynasty Daddy Trade Database (permission given) instead | Sleeper approves in writing |
| MDDB published mocks / consensus | 11-15 | Not usable: only R1 free, ToS bans using content to train/evaluate ML | Written permission or paid API |
| StickToTheModel mock in values | 11-11 | Personal non-commercial terms; kept private, not used | Never on the public site |
| Anchor-trade exponential trade curve (dv_08) | 11-10/11 | Reverted; replaced by additive per-game values (no consolidation premium) | Kyle wants a 2-for-1 premium (see R14) |
| Trade market: per-asset roster cost (package = sum of (v - c)) | 11-23 | Mathematically the same additive model; c not identifiable (synthetic fit c .80 vs true .15) | Never |
| Trade market: depth discount (k-th asset counts lambda^(k-1)) fitted jointly | 11-23 | lambda = 0 with equal values makes every trade fair, so the fit collapses | lambda fixed from outside data |
| Old `/dynasty/` page | 11-11 | Kept down; refresh stops if the folder reappears | Never |
| Conference indicators / random conference intercept | 11-10 | No variant improved Brier | New level data |
| College usage / PPA features | 11-10 | Hurt WR hit Brier; data only 2014+ | Longer history |
| Trees (RF, xgb) as main learner | 11-10 | Lost on rolling BSS (more variance) | Much larger samples |
| Stacking meta-learner, neural nets | 11-10 | 8 rolling classes can't support it | - |
| lambda.1se | 11-13 | Worse out of sample | - |
| QB P(start) x starter value (A3) | 11-13 | Overcorrected backup QBs once the sd fix was in | - |
| Snap share / depth in PPG (A4) | 11-13 | Dynasty RMSE worse | - |
| Direct horizon models, still-playing 4+ games, old-age fixes | 11-13 | Worse out of sample | Old QB survival still high (R8) |
| Usage-model prior for years 1-3 in dynasty | 11-13 | Hurt redraft out of sample | - |
| Bühlmann-Straub prospect-model prior | 11-18 | No gain | - |
| Prior-year team offense in rookie models | 11-17 | No gain beyond grade | - |
| Fantasy start rate in PPG | 11-20 | No gain | Archived real start % exists |
| Market adjusted toggle (ESPN % rostered) | 11-20 | Built then closed: Kyle wants research only | Kyle asks again |
| Crowd start % vs model start chance ("who was right", buy/sell signal) | 11-20 | Idea; one-week test mixed | 4-6 weeks of archived ESPN start % |
| Squared / interaction terms | 11-20 | No gain (rookies); trade-value gain too small, QB worse | - |
| Points or PPG models for rookie values | 11-21 | Tier method better | - |
| Rushing per-carry bonus | 11-12 | Kyle passed | Kyle asks |
| Historical rookie pick values in Value History | 11-16 | Kyle chose players only (no mocks back then) | - |
| Release 3 of the redesign | 11-14 | Not approved (parts arrived via Value History) | Kyle asks |
| 3-level site split | 11-14 | Superseded by the unified platform spec | - |
| Handcuffs section (backup RB/QB starter potential) | 11-12 | IDEA ONLY, do not build until Kyle says. Spec: raw small-sample spot-start PPG over replacement, discounted by expected starts; backups on the main board stay; separate Handcuffs section | Kyle says build |
| Dynasty Daddy value history (bulk pull, market backtest) | 11-22 | PARKED: exists from 2024-08 via undocumented endpoints; ask DD first, Kyle decides (R21) | DD says OK and Kyle asks |
| Paywall (custom leagues, handcuffs, deep dives, exports) | 11-12 | Advice only; keep default boards and Market Check free | Kyle asks |
| 2-for-1 consolidation moves; check incoming player starts | 11-16 | Not built | Kyle asks |
| Fable optional items: 2028 picks, contend/rebuild toggle, live home lead, renv | 11-14 | Not built | Kyle asks |
| Weekly usage score / route participation / air-yard share on Usage | 11-24 | PARKED: no researched model yet (handoff rule 12); Usage launches with Breakout Watch | A usage model is built, tested and Kyle approves |
| Sign-off box, per-player notes, review sheets | 11-24 | HELD by Kyle | Kyle says build |
| Market Check curve fit / package power for DD and DP | 11-24 | Dropped for rank-matching (Kyle 11-24) | Never unless Kyle asks |

---

## 6. Assumptions register

Each row: the assumption, where it lives, the directions it could have gone, why this one was chosen, and how it was
tested. Status: ACTIVE, CHANGED (with date), or SUPERSEDED.

### 6.1 Outcomes and targets

| Id | Assumption | Where | Alternatives | Why chosen / evidence | Status |
|---|---|---|---|---|---|
| A1 | Rookie success = best finish tier in NFL years 1-3 (nested hits) | all rookie models, pre/post grades | Career value; years 1-4/5; total or per-game points; first-year only | Three complete seasons exist for 2010-2023; tier review 11-12: year 4 adds few hitters; points targets (11-20/21) rank pre-draft WR/TE better but price rookies worse | ACTIVE |
| A2 | Tier cutoffs QB/RB 8/16/24, WR 12/24/36, TE 6/12/18 | `te_common.R TE_CUT`, `pd_common.R TIERS`, site TIER | Same cutoffs for all; cutoffs from league starters; PPG thresholds | Kyle's choice matching 12-team starters; TE was 8/16/24 until 2026-11-12 (TE16/24 below replacement). TE6 is thin (14 hits) | CHANGED 2026-11-12 (TE) |
| A3 | Targets scored with nflverse full PPR (QB 4-pt pass TD), regular season | rookie models, tier calibration | Half PPR; 6-pt TD; league-specific | Standard, available; league scoring handled later in values. Pick research rescored for Kyle's leagues | ACTIVE |
| A4 | A season with no games counts 0 points (a bust), not missing | rookie models | Drop or impute | Missing seasons are real outcomes for drafted players | ACTIVE |
| A5 | Season totals (not PPG) define finishes | rookie targets | PPG with games minimum | Tier review: PPG gives about the same hitters | ACTIVE |
| A6 | Training classes start 2010 | all rookie/pre models | Extend to 2006 (roadmap plan) | cfbd has almost no player data before 2008 | ACTIVE |

### 6.2 Rookie and pre-draft modeling

| Id | Assumption | Where | Alternatives | Why chosen / evidence | Status |
|---|---|---|---|---|---|
| A7 | Elastic net, alpha 0.5, lambda.min, CV folds = draft classes | everywhere | Tuned alpha; lambda.1se; random folds | Keeps correlated stats together; class folds avoid leakage; lambda.1se tested 11-13, worse | ACTIVE |
| A8 | Draft capital enters as log(pick), unpenalized in post-draft | post-draft ladders | Raw pick; pick value chart; offset; pick-only for RB/WR/TE; penalized | Value falls steeply early; Fable finding 3: unpenalized never worse, better in 5 places; Kyle chose unpenalized for all positions | CHANGED 2026-11-14 (was penalized) |
| A9 | Strict rolling origin (train <= Y-3) is the honest test; historical grades use LOCO predictions | validation, grades | Rolling grades everywhere; untouched holdout | LOCO gives a prediction for every class; rolling check (11-13) confirmed published hit rates | ACTIVE (see R6 holdout) |
| A10 | Missing values: in-fold median + missing flag (pre-draft flag only if >1% missing) | preprocessing | Model-based imputation; drop rows | Leak-safe (ATPA 3.7a); flags carry signal (skipped drills, missing team totals) | ACTIVE |
| A11 | Landing spot = vacated share + incumbent production; no team offense quality | post-draft | Prior-year team fantasy offense; coaching; scheme | Team offense tested 11-17: no gain | ACTIVE |
| A12 | Linear penalized models beat trees; no stacking or neural nets | model choice | RF/xgb main; stacking; NN | Rolling BSS; 8 test classes too few for meta-learner | ACTIVE |
| A13 | No squared or interaction terms | all rookie models | x^2, pairwise products, GAM splines | Tested 11-20: worse or no gain | ACTIVE |
| A14 | Pre-draft model: no combine, no pick, no landing spot | pre-draft | Add combine as a post-combine stage | Kyle's spec: grade before the draft process | ACTIVE |
| A15 | Pre-draft pool = all eligible productive college players; drafted recalibration used only for pricing | pd_01, pd_11 | Train on drafted only | Learns P(tier) including not being drafted; level fixed for drafted players by a 2-parameter logit map | ACTIVE |
| A16 | Age proxy = years since high school; value age = 18.6 + years out of HS (or real birth date / mock age) | pre-draft, dv_13 | Birth dates (unavailable for college); class year | College data has no birth dates. Fable 5: yrs_since_hs effect partly selection | ACTIVE |
| A17 | FCS production deflated by transfer-based factors (receiving 0.685, rushing 0.685, passing 0.789), capped at 1 | pd_01 | Conference effects; no adjustment; drop FCS | Minor-league-translation style; FBS->FBS control group | ACTIVE |
| A18 | In-progress 2026 college season pro-rated to 12 games | pd_01 (2027 pool) | As-is (also computed, PD_NO_SCALE=1) | Mid-season comparability | ACTIVE until season ends (R2) |
| A19 | Model selection rule: highest rolling Brier skill averaged over 3 thresholds (simplest model wins ties) | pd_02 | AUC; log loss; LOCO | Probability quality matters for pricing | ACTIVE |
| A20 | Grades are within-position percentiles among drafted 2010-2023 players, fixed cut points | pd_06, pd_07 | Cross-position grade; class-relative | Comparable across classes; cross-position handled by the Value column | ACTIVE |
| A21 | Score = P(top) + P(top two) + P(any) (3/2/1 weighting) | grades | Other weights; expected points | Tier review: weights don't change rankings | ACTIVE |
| A22 | Class grades use the top K prospects (QB 12, RB 20, WR 32, TE 15) | pd_04 | Whole-class sums | Growing cfbd coverage would inflate later classes | ACTIVE |
| A23 | 2027 prospects: P(declare) adjustment for non-declared underclassmen (rookie picks); originally "assume everyone declares" | pd_12_declare_2027, dv_13 | Assume all declare; use declare flag only | Fable 5/10: selection effect ~2x overstatement; refit P(declare) | CHANGED 2026-11-14 |
| A24 | Mixed model: flat odds bump only for pre-draft A-range players who fell below A- | pd_11_mixed_model | 2+ step drop; gap-scaled; all pre-A players; stacked pre+post | LOCO backtest: flat bump best (log loss -13, 9/14 classes); gap-scaled lifted late D/F fallers who all missed | ACTIVE (2026-11-17) |
| A25 | Model parity: anything feeding the mixed model also feeds post and pre (where applicable) | all 2027 outputs | Mixed-only features | Kyle's rule 11-18: the model switch must compare models, not inputs | ACTIVE |

### 6.3 2027 draft capital

| Id | Assumption | Where | Alternatives | Why chosen / evidence | Status |
|---|---|---|---|---|---|
| A26 | Draft capital for 2027 = Kyle's own mocks | pd_09, combine_mocks.py | Analyst mocks (Renner, STM); MDDB consensus; ADP/rankings; no capital (pre-draft only) | Kyle owns his mocks; others restricted by terms. Renner used 11-12 to 11-15 | CHANGED 2026-11-15 |
| A27 | Grade at the MEDIAN pick across mocks that draft him; value = share drafted x value at median + share undrafted x UDFA value | pd_12_mock_range | Mean pick (Kyle's first choice); probability-weighted over every pick; best/worst | Kyle changed mean to median 11-18; best/worst shown as range | ACTIVE |
| A28 | Landing team = team in the mock nearest the median | pd_12 | Average of teams; no landing features | Needs one team for vacated/incumbent features; causes worst-case-above-median quirks | ACTIVE |
| A29 | Undrafted base rates from 2010-23 UDFAs (RB 2.5%, WR 1.7%, TE 1.6%, QB 0%) | pd_12 | Zero value; pre-draft model | Empirical | ACTIVE |

### 6.4 Trade values

| Id | Assumption | Where | Alternatives | Why chosen / evidence | Status |
|---|---|---|---|---|---|
| A30 | Value = PPG over replacement x expected games, additive, 100k scale (top = 100,000) | dv_10, dv_11, engine.js | Rank-based convex curve fit to anchor trades (dv_08, #1 = #8 + #20); per-setting consolidation curve from simulated lineups; total points | Kyle's rule 11-11: additive and explainable. Anchor checks still printed (dv_anchor_check.csv: ratios 0.93-1.08) | ACTIVE |
| A31 | Credible PPG: Bühlmann blends, 3-season games-weighted history with draft-pick prior (k2), then current season (k1), k fit per position on week-9 backtests | dv_10 | Classic EPV/VHM k; prospect-model prior; 5 seasons; start-rate weighting | Fit empirically; priors (11-18) and start rate (11-20) tested, no gain. Side effect: 9 hot games get ~60% weight (Stroud) | ACTIVE |
| A32 | Replacement = credible PPG of the Nth player (6+ games); reference league QB24/RB24/WR36/TE12 (12 teams, SF, no flex); site default adds 2 FLEX filled greedily by projected PPG | dv_10 LG_DEFAULT, engine.js | VOLS/VORP variants; waiver-wire average; dynamic by week | Simple, league-aware; R reference league kept for calibration, backtests, downloads, snapshots | CHANGED 2026-11-15 (site default) |
| A33 | Dynasty horizon = rest of 2026 + 2027-2031 for everyone (players and picks); discount v = 1/1.15 per season | dv_11, dv_13 | Age-based horizons; perpetuity; other discount | Kyle 11-13: same window for all | CHANGED 2026-11-13 (was to 2030) |
| A34 | Future upside via stop-loss E[(X - rep)+] with horizon-specific sd from h-year residuals | dv_11 | sd x sqrt(t) (old); no upside (floor at 0) | Old version made values 20% high; fix gives pred/actual 0.99 | CHANGED 2026-11-13 |
| A35 | Still-playing S(t): logistic by position (QB adds depth rank + share of starts) | dv_03, dv_11 | Kaplan-Meier; Cox; survival forest; 4+ games definition | Compared in dv_03; 4+ games and old-age fixes worse | ACTIVE (old QB survival high, R8) |
| A36 | PPG aging: next-season PPG ~ current credible PPG + age curve + experience + draft slot (young) | dv_11 | Direct horizon models; usage priors | Direct horizons worse (11-13) | ACTIVE |
| A37 | Expected games from status: IR/Out/Doubtful/Q ratios, role x health credibility; own history counts injury misses only | rl_common, rl_dv10 | Games-played rate only; snap/depth in PPG | +.016 redraft Spearman (sig) | ACTIVE (2026-11-13) |
| A38 | Future seasons are 17 games | dv_11 | 18-game season | Current NFL schedule | ACTIVE |
| A39 | 2027 pick value = tier probabilities x historical tier outcomes (2010-22, season 5 from 2010-21) x age adjustment x calibration multiplier (1.03); slot = rank of value in the chosen league; only rounds 1-3 of 2027 | dv_13 | PPG models (rejected 11-21); market pick values; include 2028 | Backtest-calibrated; picks named by slot only (Kyle) | ACTIVE |
| A40 | Still-playing model without interaction terms | dv_11 | + cppg^2, cppg:age, lpick:exp | Kyle decided leave out 11-20 | ACTIVE |
| A41 | Scoring presets: each knob touches one position; QB catches full PPR and RB/WR pass TDs 4 pts in every preset | dv_13 | Full grid | Rounding error; 20 runs instead of hundreds | ACTIVE |
| A42 | First-down bonus 0-1 per rushing/receiving first down by position, never passing | dv_10/13 | Include passing FDs; per-carry bonus | Kyle's spec 11-12 | ACTIVE |
| A43 | Values are purely production-based; no market adjustment | engine.js | Market-adjusted toggle (ESPN rostered) | Kyle wants research only (11-20) | ACTIVE |
| A44 | No consolidation premium: 2-for-1 equals the sum | engine.js, moves.js | Convex curve | Additivity rule; moves are one-for-one | ACTIVE |
| A45 | A trade is "Too close to call" inside 10% | calculator, moves | 5% "About even" (old) | Values carry noise; Kyle's redesign spec keeps 10% | CHANGED 2026-11-14 |
| A46 | Values shown to the nearest 100, no interval | site | Ranges / tiers | Fable 9: avoid false precision; ranges not built | ACTIVE |

### 6.5 History, research and site

| Id | Assumption | Where | Alternatives | Why chosen / evidence | Status |
|---|---|---|---|---|---|
| A47 | Value history: data before each Tuesday only; models refit on earlier seasons; future seasons same length as season S | Trade_Values/history | Use final models (leaky) | Kyle asked point-in-time; leak list documented | ACTIVE |
| A48 | Value history excludes rookie picks | history | Price picks from past mocks | No mocks existed back then; Kyle's choice | ACTIVE |
| A49 | Team matchup projection = multiplicative credibility (+ closing lines when available) | Team_Matchup_Model (branch) | GBM; additive off+def | GBM 1-2 R² points worse; naive additive worse than league average | RESEARCH |
| A50 | Pick strategy: price = dv_13 value at draft; realized on the same scale (v = 0.93 as recorded in project memory) | Rookie_Pick_Strategy | Market prices (not available historically) | Only consistent price history we own | RESEARCH |
| A51 | Market references = Dynasty Daddy + DynastyProcess, never KTC | value-research | KTC, FantasyCalc, others | Terms of use | ACTIVE |
| A52 | Site is static (GitHub Pages), all league math in the browser, one engine.js | site | Backend/API | Free hosting, no keys, Kyle's spec | ACTIVE |
| A53 | Phones keep the light theme | theme.css | Dark charcoal theme (Kyle's original spec) | Kyle chose matching desktop | ACTIVE |
| A54 | Table rules: header always visible; only Rank frozen; one "Start a trade" button | site tables | Frozen name column | Kyle 11-14 | ACTIVE |
| A55 | Default league on site: 12 teams, SF, full PPR, 4-pt TD, 1/2/3/1 + 2 FLEX | shared/league.js DEF | No-flex (old default) | Kyle 11-15, matches X images | CHANGED 2026-11-15 |
| A56 | Player ids are permanent slugs `name-class` | data/players.json | gsis/pfr ids | Covers college prospects who have no NFL id | ACTIVE |
| A57 | Sleeper picks: 2027 rounds 1-3 valued (exact slot if order set, else round average); 2028+ and round 4+ listed, not valued | shared/sleeper.js | Value future picks at a discount | No model for 2028 classes yet | ACTIVE |
| A58 | Team needs: bottom third = Need, top third = Strength; spare = next player >= half an average starter | league page | Absolute thresholds | Relative to the league | ACTIVE |
| A59 | Contending/Rebuild: fair = within 10% dynasty; contend = +10% redraft; rebuild = +10% future; gains < 1,000 dropped | moves.js | Consolidation moves | Kyle 11-16 | ACTIVE |
| A60 | Profile comparables = 5 closest past seasons by age, PPG, prior PPG; shown as outcomes, not used in values | build_production.py | Use in projections | Display only | ACTIVE |
| A61 | Team analytics: passing and receiving double count by design | teams.js | Split credit | Stated on page | ACTIVE |
| A62 | Weekly gates: replacement lines within 2016-2025 week-9 range +-2 PPG; pick multiplier 0.7-1.6; <= 15 players leave either top 50 (from week 8); browser within 100 points of R | rf_03_gates.R, rf_gate_limits.csv | Looser/stricter limits | Historical maxima (never more than 8 top-50 exits) | ACTIVE |
| A63 | Redraft "now" = latest week; credibility constants still fit on week-9 backtests | dv_10 CUT26 | Refit k by week | Simplicity; history uses early-week min-games rule | ACTIVE |
| A64 | Post-draft grades are not rerun weekly | refresh | Rerun weekly | They use draft capital and college data only | ACTIVE |
| A65 | Snap features before 2013 imputed | year-2 models | Drop 2010-12 rookies | Snap counts start 2013 | ACTIVE |
| A66 | The 2026 season is the "current" season; replacement and values use 2026 week-by-week data | everything live | - | Calendar | ACTIVE until season ends (R1) |
| A67 | Kyle's leagues (half PPR, 6-pt TD, TE premium, FD bonuses) are evaluated by rescoring production with generic prices | Rookie_Pick_Strategy rp_07 | League-specific price model | Only generic price history exists | RESEARCH |
| A68 | Research uses Python in the cloud when R is unavailable, matching R outputs (e.g. realized value r = .99 with pp_03) | research folders | Always R on PC | Container lacks some packages; checked against R | ACTIVE |
| A69 | Year-2/3 usage models are research and buy/sell only, not in values | position models | Feed dynasty values | Tested as prior 11-13, hurt redraft | ACTIVE |
| A70 | 2027 board names: alias list maps mock names to board names (Ryan Coleman-Williams = Ryan Williams, Hollywood Smothers = Daylan Smothers, Quintrevion Wisner = Tre Wisner) | combine_mocks.py aliases | Fuzzy matching | Exact and auditable | ACTIVE |
| A72 | Board "Proj. PPG" = projected PPR points per game over NFL seasons 1-3 in games played, elastic net on the grade's own inputs, trained on players with 1+ game weighted by games; past classes out-of-class; mixed = post + faller bump in PPG | pd_13, pd_14 | Projected total 3-yr points (S#33 first preview); rookie-year PPG; expected PPG including zero-game risk | Kyle chose 3-yr PPG 11-23; per-game separates "how good when he plays" from the grade's "will he make it"; 3-yr PPG beat rookie-year PPG in the value tests | ACTIVE |
| A73 | Rookie values and pick prices stay on the tier odds; Proj. PPG is display only | dv_13 | PPG-model values; hybrid (PPG top 24, tiers outside) | Tier method best in every 11-21 backtest (.540 vs .516-.519; hybrid .491) | ACTIVE |
| A74 | Mock range: best/worst cases keep their own faller boost, but worst <= median <= best on each tier's odds and the grade (capped / floored at the median-pick case) | pd_12_mock_range | Per-case boost with no cap (worst > median for 5 players); faller status fixed at the median; best/worst from the plain post-draft model only | Kyle's call 2026-11-23: keep the boost, max it at the median | ACTIVE 2026-11-23 |
| A75 | "Trade" values: every trade is roughly fair and package values add (sum of asset values per side) | Trade_Market tm_02 | Consolidation exponent (sum of v^alpha); per-shape term; pairwise 1-for-1 only | Additive matches our 100k scale; holdout shows a large stud premium, so this is the first thing to revisit (R23) | RESEARCH 11-23; 11-23 tm_04 keeps additivity but recalibrates the spread (A80); the gap is partly a fit artifact and partly a real market premium |
| A76 | Trade recency: weight 0.5^(age/H), credibility shrink to the long-run fit with k; H = 7 days, k = 2 | tm_02 | All trades equal; last 30 days only; H 14-120; k 10/50 | Best on a 14-day time holdout in dynasty and redraft; both at the edge of the grid (3 days added for the next run) | RESEARCH 11-23 |
| A77 | Trade leagues kept only if our settings describe them: 8-14 teams, 0.5/1 PPR, TE premium <= 1, no best ball; settings enter as SF, full PPR, TEP, (teams-12)/2, starters-10 per position group | tm_01, tm_02 | Exact-setting subsets (too thin); all leagues pooled with no terms | Lets one model give values for any of our settings; pass TD and first-down bonus are not in the data, so trade values ignore them | RESEARCH 11-23 |
| A78 | Trade source = Dynasty Daddy Trade Database (`api.dynasty-daddy.com/api/v1/trade/search`), pulled once from Kyle's PC at ~2.5 s per call; raw trades and league ids stay private on the PC | tm_01 | Crawl Sleeper ourselves | DD owner gave Kyle permission 11-22; Sleeper ToS bans crawling | ACTIVE 11-23 |
| A80 | Market values on our additive scale: light shrinkage (LAMBDA0 0.05) and one stretch v' = v^s chosen so holdout trades show no consolidation gap | tm_04 | tm_02 as is (flat); roster cost; depth discount; stretch by MAE (always s = 1) | Only option that recovers known values in synthetic tests and puts package prices on an additive scale; the s = 1 (straight-up) view is reported next to it | RESEARCH 11-23 |
| A81 | Dynasty market comparison uses only 1-for-1, 1-for-2, 2-for-2, 2-for-3 trades (75% of trades) | tm_04 TM_SHAPES | All shapes | Kyle 11-23: bigger trades are large steps | RESEARCH 11-23 |
| A82 | Market comparison is descriptive: differences are "market above / below our method", never errors on either side | Trade_Market write-ups | Treat the market as truth or as noise | Kyle 11-23 | ACTIVE 11-23 |
| A83 | Market values shown on our curve: 1:1 market values raised to one power fitted so the top-150 curve matches ours; package exceptions listed beside them | tm_06 | Package-fair scale (s 2.44); raw 1:1 (flatter) | Kyle 11-23: "keep the 1:1" with our site values; differences become pure player placement | SUPERSEDED 2026-11-24 for the site by A88 (rank differences) |
| A84 | Market moves: fair = market prices within 10% (1:1 prices for pivots, 2:1 package prices for uptier/downtier); listed when our dynasty value gains > 10% and >= 1,000 | value-research page (S#34) | Fair on our values (as /moves/); fair on the curve-matched scale; 2-for-3 calibration (power 2.09) | Kyle 11-23; matches the site's 10% too-close-to-call rule; 2:1 power from 1-for-2 holdout trades only | RESEARCH 11-23, LIVE when S#34 merges |
| A86 | Market moves Contending / Rebuild: market values split into now / future with our own per-player ratio (pseudo values); need side > 50% of the trade's need value and > 10% / >= 1,000 above the other side; give up more of the other kind; our dynasty values within 10%; ranked by pseudo need gain | value-research page (S#36) | Our redraft / future values directly (no market side); need share threshold on the whole package; our dynasty gain still required | Kyle 11-23 ("use the ratios from our own values to give them pseudo values"); keeps both sides "value equal" and judges the need on market terms | LIVE when S#36 merges |
| A85 | DD / DynastyProcess moves use rank-matched values (our value at the same overall rank); downtier and uptier: the two-piece side is led by a same-position player below the single player with > 50% of that side's market value (11-23, S#35), the other piece any position; pivots any position | value-research page (S#34) | Positional-rank matching; no moves for DD/DP | Kyle 11-23 | LIVE when S#34 merges |
| A79 | Assets with fewer than 25 trades pooled per position; reference asset 2027 mid 1st (redraft: most-traded player) | tm_02 | Separate tiny-sample values; another reference | Stable fit; values are rescaled to 100k per league anyway | RESEARCH 11-23 |
| A87 | Site accent teal #107F80 (handoff asked #148A8A) | shared/theme.css | #148A8A as given; navy-only buttons | #148A8A with white text is 4.2:1, under WCAG AA 4.5:1; #107F80 is 4.8:1 and reads the same | ACTIVE 11-24 |
| A88 | Market Check: every source rank-matched (each player gets our value at his market overall rank) and shown as overall + positional rank differences; 2-for-1 moves use rank-matched values for all sources | value-research page | Curve fit with package power for the trade market (A83); positional-rank matching | Kyle 11-24 approved rank differences for all sources | ACTIVE 11-24; A83 SUPERSEDED for display 11-24 |
| A89 | Calculator trade-type adjustment is a secondary "market-style read": adj = a + b g + c g^2 by type (n1 v n2), g = ln(best1/best2) clipped to the training range; 1-for-1 and trades with picks get none; pieces under 25% of the best asset phase out linearly from 25% to 5% | shared/trade-adjust.js | Make it the headline verdict; no adjustment; refit live | Kyle 11-24 "keep values additive and add the adjustment as tested"; F#43 found the gap term mostly encodes market-vs-our pricing, so it stays beside, not instead of, our verdict | ACTIVE 11-24 |
| A90 | 2027 rookie picks valued through round 4 (4 x teams slots) | engine.js, dv_15, dv_13, dv_14, tm_07 | Rounds 1-3 | Kyle 11-24 | ACTIVE 11-24 |
| A71 | Market history, if used, = Dynasty Daddy's own `daddy_*` fields from DD's history endpoints, only after DD permission; never the unprefixed/KTC fields | research/dd_history | Use documented current API only and build our own weekly archive of it; use FantasyCalc history | DD history is the only dated market source found that we may use; own archive starts from zero | ACTIVE |

---

## 7. Data sources, terms of use and privacy

| Source | Use | Terms / limits |
|---|---|---|
| nflverse via nflreadr (draft picks, combine, players, weekly stats, snaps, injuries, rosters, depth charts, pbp) | Everything NFL | CC BY 4.0; credit on site. Stat corrections can change history |
| CollegeFootballData.com via cfbfastR | College stats, team stats, recruiting, usage/PPA | API key private (`.Renviron`); credit on site. FCS only vs FBS before 2022 |
| Pro Football Reference | Credited on site | - |
| Dynasty Daddy public API | Market Check snapshot | Allowed (Kyle confirmed); cache, low request rate; blocked from cloud (fetch via Kyle's PC) |
| Dynasty Daddy history endpoints (`/player/{id}?isAllTime=true`, `/player/all/prev/{days}`) | Research sample only (11-22) | Undocumented; no ToS page; ask DD before bulk use; rows also carry KTC fields, which stay unused |
| DynastyProcess open data | Market Check, Sleeper id map | Open data on GitHub |
| Dynasty Daddy Trade Database (`/api/v1/trade/search`) | Trade Market research (11-23) | DD's owner gave Kyle permission 11-22; one paced pull from the PC; raw trades contain league ids and stay private, only aggregates in the repo |
| Sleeper public API | League import in the visitor's browser | Read-only; blocked from the cloud container. API docs: non-commercial use; Terms of Use ban crawling other leagues without written approval (checked 11-22) |
| ESPN `kona_player_info` | Research only (rostered %) | Works from Kyle's PC only; current week only |
| KeepTradeCut | NOT USED | Terms ban scraping and reuse |
| NFL Mock Draft Database | Only Kyle's own simulator mocks | Their mocks: ToS bans ML use; R2-7 paywalled; never bypass |
| StickToTheModel mock | Private project file only | Personal non-commercial use; never in public repos or the site |
| Renner 2027 mock (analyst) | 30 fantasy picks graded and credited 11-12 to 11-15; private copy in project files | Not committed to public repos |

**Privacy.** Both repos are public. Never commit: the cfbd key, Kyle's email, private mocks (StickToTheModel, Renner),
Kyle's personal league ids and trade history. Those stay in project memory or project files. League *settings* are
fine (already in Rookie_Pick_Strategy/README.md).

---

## 8. Known issues, documentation drift and open questions

1. `Mock_Drafts/README.md` still says "Average pick" and "not live yet"; live uses the MEDIAN pick and has been live since
   2026-11-19 (pd_12). Fix wording.
2. MODELS_TECHNICAL_REFERENCE.md has no trade-values section (Fable suggestion, not built).
3. Root README.md does not list the research folders or the pick-strategy study (partly fixed by linking this file).
4. Sorsby is ungraded (board lists him in the 2026 class).
5. Dante Moore's 2027 QB row shows only 132 primary-season attempts (likely partial or mismatched data).
6. Players missing from trade values though the market ranks them: Jayden Higgins, Travis Hunter, Brandon Aiyuk, Carson Beck.
7. Backup QBs still rate above market (lightly rostered QBs sell ~0.68x our value); old QB survival too high (Stafford
   example in FABLE_REVIEW finding 8).
8. Current-season small samples get large credibility weight (Stroud QB3 vs market QB11-13); IR players drop sharply.
9. Mock range quirk: worst case can beat the median (landing team or mixed boost at one pick only), e.g. CJ Carr, Luke
   Reynolds, KJ Duff, Mensah.
10. Template trap: `refresh.sh` rebuilds the Trade Values page from the PC's `tv_page_template.html` and copies it back
    to the repo. Any template edit must be copied to the PC before Tuesday (it broke the footer once, 2026-11-17).
11. Wednesday rookie X posts barely change week to week because mock grades are not rerun weekly.
12. Open research PRs never merged: F#19 (team matchup), F#25 (prospect prior). Their findings are recorded here; code
    lives only on the branches. (F#33 now carries the Proj. PPG build as well as the interaction/points research.)
16. Proj. PPG needs pd_13, pd_14, pd_10, rf_02 and refresh.sh on the PC; otherwise the column is blank after a refresh.
    The pre-draft PPG model is weak for QBs (Spearman .25) and the mixed QB faller bump (+3.9 PPG) rests on 11 players.
13. Sleeper settings the site cannot model (e.g. Lampoons' TE +0.25 and yardage bonuses).
14. The refresh only runs if the PC is on (Task Scheduler runs it at the next start-up otherwise).
15. Market Check is a single snapshot; dd.js keeps no history (each refresh overwrites it). DD history would fix this (R21).
17. Trade Market run 11-23: already-drafted 2026 picks (`2026.1.1.pi`) were labelled OTH and the final long-run fit hit its
    iteration cap (the credibility fit converged). Both fixed in tm_02 for the next run; outputs not yet rerun.
18. Trade Market values are additive but the market is not. 11-23 (tm_04): part of tm_02's premium was a fit artifact
    (shrinkage + compression), but a real premium remains (+48% 1-for-2 at straight-up prices), so any single additive
    market scale misprices either straight-up or package trades. Compare levels with both views side by side.
19. tm_04's long-run fit stops at its 800-iteration cap (the credibility fit converges); redraft run paused 11-23.
20. 11-24: Dynasty Daddy 2027 pick prices are blank on Market Check until dv_14 runs on the PC (the cloud cannot reach
    the DD API). Trade market gives one generic (mid) price per round, so early/late picks compare to a round average.
21. 11-24: the calculator's trade-type coefficients are a frozen 11-24 fit; they are not refit weekly yet (tm_weekly does
    not write them). Round-4 picks sit near the replacement line, so small values in deep leagues.
22. 11-24: robots.txt cannot live under a GitHub project subpath; submit `sitemap.xml` in Search Console instead.

---

## 9. Future recommendations

Ranked. Each says why, and which log entry or assumption it comes from. Mark done items with the date. Nothing here is
approved to build unless Kyle says so (see section 10).

### As of 2026-11-22

**Offseason plan (time-sensitive)**

- **R1. Plan the end of the 2026 season (refresh ends 2027-01-05).** After week 18: freeze final redraft values, decide
  whether the dynasty window rolls to 2027-2032 and when, retire the Tuesday task, and run one archive snapshot. (A33, A66)
- **R2. Re-pull the full 2026 college season after Dec 16** and regrade 2027 prospects without pro-rating; compare to
  the pro-rated grades. (A18)
- **R3. Retrain rookie models with the 2024 class** once its third season (2026) is complete, so training becomes
  2010-2024; refit tier calibration (2010-2023) and the pick multiplier. Record changes against the frozen Track Record. (A1, A39)
- **R4. After the April 2027 NFL draft:** grade the real 2027 class with actual picks, retire the mocks, score the mock
  approach against the real draft, and price 2028 picks (needs a 2028 pre-draft board). (A26-A29, A57)
- **R5. Score the frozen 2024-2026 Track Record** after the 2026 season and publish the result.

**Model quality**

- **R6. Keep an untouched holdout** (Fable 7): freeze one season of value predictions and one class of grades before any
  new modeling, so future tests have a clean check.
- **R7. Backup QB discount research** using archived ESPN rostered % (archive 4-6 weeks first, no publishing), test a
  QB-only adjustment. (A43, issue 7)
  The same archive enables the crowd-vs-model start % test (section 3, 2026-11-20 follow-up).
- **R8. Old QB survival:** a new angle is needed (the 11-13 fixes failed), e.g. contract or depth-chart-based exits.
- **R9. Write the trade-values section of MODELS_TECHNICAL_REFERENCE.md** (formulas, k table, backtests). Documentation only.
- **R10. Current-season credibility weight check:** test whether k1 should vary by week or by prior sample size, since
  9 hot games carry ~60% weight. (A31, A63)
- **R11. Investigate the missing players** (Higgins, Hunter, Aiyuk, Beck), Sorsby and Dante Moore. (issues 4-6)

- **R22. Copy the Proj. PPG scripts to the PC** (pd_13 + pd_10 -> Football2_PostDraft, pd_14 -> Football2_PreDraft,
  rf_02 + refresh.sh -> Weekly_Refresh) before the next Tuesday refresh after F#33/S#33 merge. (A72, issue 16)

**Product (only when Kyle asks)**

- **R12. Handcuffs section** per the parked spec. **R13. Value ranges / uncertainty bands** (Fable 9).
- **R14. 2-for-1 consolidation** (simulation-based premium per league) if Kyle wants it on the calculator. (A44)
- **R15. Points column on boards** needs an R generator in pd_10 before S#33 can go live. (11-21)
- **R16. Team matchup projections** on the site as a weekly tilt (not a point forecast). (A49)

**Housekeeping**

- **R17. Merge or archive the open research PRs** (F#19, F#25, F#33) so the code sits on main next to these findings.
- **R18. Fix doc drift** in Mock_Drafts/README.md and the root README. (issues 1, 3)
- **R19. renv lockfile** for the R environment (Fable, not built).
- **R20. Pick-slot history on the Picks tab** (from Rookie_Pick_Strategy) only if Kyle asks.

**Market data**

- **R21. Dynasty Daddy history:** ask DD (Discord/X) whether pulling history from its undocumented endpoints is OK; if
  yes, one paced pull from Kyle's PC (~120 weekly `prev/{days}` calls, cached, never re-pulled) and a backtest of our
  point-in-time values vs DD against next-season PPG, by position. Meanwhile, cheap fallback: keep each week's dd.js
  in the archive so our own market history starts now. (11-22, A71)

**Nov 28 batch follow-ups (11-24)**

- **R29. Copy the regenerated `tv_page_template.html`, dv_13, dv_14, dv_15 to Football2_Dynasty and tm_07 to the trade
  market folder before Tuesday 12-01.** (issue 10, A90)
- **R30. Have tm_weekly write the trade-type coefficients** into `shared/trade-adjust.js` so the calculator line refits
  weekly. (A89, issue 21)
- **R31. Dec 5 / Dec 12 phases** per the redesign handoff (tables, league drawer, trade tray; profiles). Weekly usage
  score only after research.

**Trade Market (research 11-23)**

- **R28. DONE 11-23 (weekly tm_weekly.sh + refresh step 4c).** Refresh the Trade market source: tm.js is a one-off snapshot of trades to 11-23; add a periodic re-pull and
  refit (paced, from the PC, DD permission) if Kyle wants it kept current. (A83, S#34)
- **R26. Two-number market summary:** report the market as straight-up values (s = 1) plus a measured consolidation
  premium by trade shape, rather than one stretched scale; optionally compare with our own 2-for-1 premium idea (R14).
  Only if Kyle asks. (A80-A82)
- **R27. Finish or drop the paused redraft tm_04 run** when Kyle says; raise the long-fit iteration cap. (issue 19)
- **R23. DONE 11-23 (see log; tm_04).** Consolidation-aware trade values: fit an exponent (package value = (sum v^alpha)^(1/alpha)) or a per-shape term,
  compare on the same 14-day holdout (1-for-3 trades now miss by 57%), and re-express values on the 100k additive scale.
  Needed before comparing value levels with ours. (A75, issue 18)
- **R24. Rerun tm_02 with the fixes** (pick labels, 3-day half-life, smaller k such as 0.5) and pull the two unfinished
  weeks after 11-27. (A76, issue 17)
- **R25. Use the trade market as a check on our setting effects:** traders price TE premium and SF far less than our
  model does; test which one predicts realised points better before changing anything. Only if Kyle asks. (A77)

---

## 10. Working rules and Kyle's preferences

- **Approval:** build only what Kyle asked for. Research requests are research only unless he says publish
  ("I don't want anything published yet. Just research", 2026-11-20). Ideas marked IDEA ONLY wait for him.
- **Merging:** open PRs for Kyle to merge; he usually clicks Merge. Weekly refresh pushes straight to main (approved).
- **Live folders on the PC:** never edit in place for experiments; work in a `_dev` copy, back up before switch-over,
  get Kyle's written approval naming the live folders.
- **Show everything:** in research, show Kyle the charts and outputs of everything examined, not just conclusions
  (2026-11-20).
- **Methods:** always apply ATPA/PA techniques (rolling splits, model comparison, varimp / PDP / ICE / SHAP, bootstrap CIs).
- **Explainability:** Kyle wants to explain the models to non-technical people; plain-English write-ups, insurance
  analogies work well.
- **Model parity rule** (A25). **Additive value rule** (A30). **10% too-close-to-call** (A45). **Never fabricate data.**
- **X posts:** drafts only, short casual single posts, content first, site link on the side; never post for him.
- **Kyle's leagues:** findings should also be tailored to League of Lampoons (10 teams, 1QB/2RB/3WR/1TE/2FLEX, SF, half
  PPR, 6-pt pass TD) and Dynasty Confederates (12 teams, same lineup, SF, half PPR, TE +0.5, 6-pt pass TD, first-down
  bonus RB +0.25 / WR +0.5 / TE +1), not only the site default.
- **Update this file** with every change (section 1).

---

## 11. Index of reports, artifacts and branches

**Write-ups (claude.ai artifacts, private to Kyle unless shared)**

| Topic | Link |
|---|---|
| Model write-up | https://claude.ai/artifact/LpjqTZULpQXjUzYEnTzFYr |
| Pre-draft player grades | https://claude.ai/artifact/XAVUw32K3yMb7atWgpov3i |
| Post-draft player grades | https://claude.ai/artifact/CXjjafaBwrK84knShtR4n6 |
| WR roadmap / WR summary | https://claude.ai/artifact/2DrQ7HFQgH6Lb41PQs72J5 , https://claude.ai/artifact/2TuvoX47nj6zuNzyiNrbbT |
| Site organization plan | https://claude.ai/artifact/2HpfnuUN1hAMh4Dssc9L2Y |
| Platform audit (redesign) | https://claude.ai/artifact/RCecJm9ZCDhhdhxgYYDjFx |
| Team matchup model | https://claude.ai/artifact/7qkYEDDyJsjw25gQfRksnA |
| Prospect-model prior backtest | https://claude.ai/artifact/7SuXy2ubvAKdJFAKRGZDrj |
| Starter rate research | https://claude.ai/artifact/MC4T33mjaH2Uu5oV3onTyN |
| Interactions / squared terms | https://claude.ai/artifact/NsvDr1nxQ78NeP47kMdmcw |
| Top-24 boards (points vs tiers) | https://claude.ai/artifact/6UXRNYjU8YddKV9ajiXGej |
| Rookie pick strategy | https://claude.ai/artifact/WKN1QzTfvdzKTgKzg6rR6T |
| Trade Market values (Trade_Market; includes the 11-23 additive-scale section) | https://claude.ai/artifact/D57WtFX8mNemAZ647ujpz5 |

**Reports in this repo:** FABLE_REVIEW.md; `Trade_Values/dev_role_layer/FABLE_BUILD_REPORT.md` and
`ROLE_AND_CALIBRATION_REPORT.md`; `Trade_Values/history/README.md`; `Landing_Spot_Offense/README.md`;
`Rookie_Pick_Strategy/README.md`; `PostDraft_Model/exp_mixed_model/README.md`; each model folder README and PREDICTORS.md.

**Branches with work not on main**

| Branch | What | PR |
|---|---|---|
| `claude/project-thread-9maezz` | Team_Matchup_Model research | F#19 open |
| `claude/project-thread-hdosin` | Trade_Values/prospect_prior research | F#25 open |
| `claude/project-thread-81ioqt` | Interaction_Research (squared/interaction, points, PPG values, hybrid) | F#33 open; site preview S#33 draft |
| `claude/project-thread-m614pm` | Market adjusted toggle, rf_05 ESPN pull, research_start_pct | F#32 / S#32 closed |
| `claude/project-thread-e3qnnu` | X_Posts/2027_Rookie_Guide (QB) | none |
| `dynasty-model`, `revert-dynasty-model` | First dynasty model (anchor curve) and its revert | F#3 / F#4 |
| Older feature branches (`wr-model`, `rb-model`, `te-model`, `pre-draft-model`, `player-grades`, ...) | Merged history | F#1-F#6 |

**Project files (private, not in repos):** `mock_drafts/` (STM, Renner, Kyle's mock fantasy positions + alias file),
`research/` (grade_fallers, interactions_squared, points_projection, rookie_class_value, rookie_pick_strategy,
starter_rate), `reviews/FABLE_REVIEW.md`, `x_posts/`, `team_matchup/`, `value_history_install/`, `ATPA/` and `PA/`
coursework (the course prototypes in `ATPA/Module/Rookie_Model` and `Fantasy_Football` are the project's origin).
