# Trade_Market: the "Trade" value method (research only)

A value method built only from real trades, kept fully separate from the model-based trade values in `Trade_Values/`.

- Data: Dynasty Daddy Trade Database (used with permission from Dynasty Daddy's owner, 2026-11-22). Pulled on Kyle's PC by `tm_01_pull_dd_trades.R`; raw trades (which contain league ids) stay private on the PC and are never committed.
- Formats kept: 8-14 teams, half or full PPR, TE premium 0-1, no best ball (the settings our site can express).
- Fit: `tm_02_fit_trade_values.R`. Each trade is treated as roughly fair; asset values (players and picks) are solved so both sides balance, with position-specific adjustments for superflex, PPR, TE premium, team count and starter count. Recent trades count more (half-life H) and each asset's recent price is blended with its long-run price by credibility Z = I/(I+k). H and k are chosen on a 14-day time holdout.
- Outputs in `out/` are aggregates only (no league ids, no raw trades).

Status: RESEARCH ONLY. Nothing here feeds the site.

## Results (2026-11-23 run)

- Trades used: 1,562,946 dynasty (May 1 to Nov 23) and 686,944 redraft (Sep 1 to Nov 23).
- Holdout (last 14 days): best weighting H = 7 days, k = 2 in both formats. Dynasty mean |log gap| .296 vs .341 with all
  trades equal; redraft .285 vs .301.
- Rank agreement with our model values, top 150 at the site default league: dynasty Spearman .897, redraft .837.
- The market pays a consolidation premium (fewer-asset side +35% in 1-for-2, +67% in 1-for-4), so these additive trade
  values are flatter than ours: compare ranks, not levels, until a consolidation-aware fit exists.
- Traders barely adjust for PPR, TE premium or team count; superflex is the one setting priced strongly.
- Charts and tables: `compare/`. Full report: https://claude.ai/artifact/KxjqETAkoyxDSxtq8uhaaM

Rerun: `Rscript tm_01_pull_dd_trades.R` (PC), `Rscript tm_02_fit_trade_values.R dynasty|redraft` (PC), then
`node tm_03_our_values.js <prospect-actuary>` and `python3 tm_03_compare.py <Football> our_values.csv <prospect-actuary>/data/sleeper_ids.json`.
