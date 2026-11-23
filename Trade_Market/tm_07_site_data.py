"""tm_07_site_data.py: write the Market Check page's "Trade market" source (prospect-actuary value-research/data/tm.js).

Market 1:1 values from the 4-shape dynasty run (out/dynasty_add4_*.csv; Kyle 2026-11-23 chose the 1:1 scale matched to
our curve and the Market Check page). The file holds each player's log 1:1 value at the page's league
(12 teams, 0.5 PPR, superflex, 1QB/2RB/3WR/1TE, no flex = 8 starters); the page fits one power so the market's curve
matches ours and shows values on our scale. Picks and pooled rare assets are left out (the page compares players only).
Usage: python3 tm_07_site_data.py <out_dir with dynasty_add4_*.csv> <sleeper_ids.json> <dest tm.js>
  e.g. python3 tm_07_site_data.py Football/Trade_Market/out prospect-actuary/data/sleeper_ids.json prospect-actuary/value-research/data/tm.js
Run weekly by tm_weekly.sh (Kyle 2026-11-23: trade data updated weekly).
"""
import sys, os, json
import numpy as np, pandas as pd
OUT, SLID, dst = sys.argv[1:4]
A = pd.read_csv(os.path.join(OUT, "dynasty_add4_assets.csv"), dtype={"asset": str})
B = pd.read_csv(os.path.join(OUT, "dynasty_add4_beta.csv"))
meta = pd.read_csv(os.path.join(OUT, "dynasty_add4_meta.csv")).iloc[0]
s = float(meta.stretch)
sl = json.load(open(SLID))["m"]
x = {"sf": 0.0, "ppr1": -0.5, "tep": 0.0, "teams": 0.0, "start": 8 - 10.0}
Bp = B.pivot(index="group", columns="covariate", values="beta")
A = A[A.grp.isin(["QB", "RB", "WR", "TE"])].copy()
A["lv"] = A.theta_unstretched + np.array([sum(Bp.loc[g, c] * x[c] for c in x) for g in A.grp]) / s   # 1:1 scale betas = stretched / s
A["nm"] = A.asset.map(lambda a: sl.get(a, "|").split("|")[0] or None)
A["nm"] = A["nm"].fillna(A["name"])
A = A[A["nm"].notna()].sort_values("lv", ascending=False)
rows = [[r.nm, r.grp, round(float(r.lv), 4), int(r.n_trades)] for r in A.itertuples()]
# 2:1 scale: power on the 1:1 values at which held-out 1-for-2 trades balance (log gap interpolated to 0)
h = pd.read_csv(os.path.join(OUT, "dynasty_add4_holdout_by_shape.csv")); h = h[h["shape"] == "1-for-2"].sort_values("stretch")
s_pkg = float(np.interp(0, h.mean_log_gap_few_minus_many.values, h.stretch.values))
data = {"asof": str(meta.get("last_trade", "2026-11-23")), "s_pkg": round(s_pkg, 3), "trades": int(meta.trades_used), "first": str(meta.get("first_trade", "2026-05-01")),
        "note": "Dynasty Daddy Trade Database, 1-for-1, 1-for-2, 2-for-2 and 2-for-3 dynasty trades", "rows": rows}
tmp = dst + ".tmp"
if len(rows) < 300: sys.exit(f"only {len(rows)} players; tm.js not written")
open(tmp, "w").write("window.TM = " + json.dumps(data, separators=(",", ":")) + ";\n"); os.replace(tmp, dst)
print(len(rows), "players ->", dst)
