# Trade_Market: the "Trade" value method (research only)

A value method built only from real trades, kept fully separate from the model-based trade values in `Trade_Values/`.

- Data: Dynasty Daddy Trade Database (used with permission from Dynasty Daddy's owner, 2026-11-22). Pulled on Kyle's PC by `tm_01_pull_dd_trades.R`; raw trades (which contain league ids) stay private on the PC and are never committed.
- Formats kept: 8-14 teams, half or full PPR, TE premium 0-1, no best ball (the settings our site can express).
- Fit: `tm_02_fit_trade_values.R`. Each trade is treated as roughly fair; asset values (players and picks) are solved so both sides balance, with position-specific adjustments for superflex, PPR, TE premium, team count and starter count. Recent trades count more (half-life H) and each asset's recent price is blended with its long-run price by credibility Z = I/(I+k). H and k are chosen on a 14-day time holdout.
- Outputs in `out/` are aggregates only (no league ids, no raw trades).

Status: RESEARCH ONLY. Nothing here feeds the site.
