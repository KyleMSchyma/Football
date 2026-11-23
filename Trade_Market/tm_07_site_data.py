"""tm_07_site_data.py: write the Market Check page's "Trade market" source (prospect-actuary value-research/data/tm.js).

Market 1:1 values from the 4-shape dynasty run (out/dynasty_add4_*.csv; Kyle 2026-11-23 chose the 1:1 scale matched to
our curve and the Market Check page). The file holds each player's log 1:1 value at the page's league
(12 teams, 0.5 PPR, superflex, 1QB/2RB/3WR/1TE, no flex = 8 starters); the page fits one power so the market's curve
matches ours and shows values on our scale. Picks and pooled rare assets are left out (the page compares players only).
Usage: python3 tm_07_site_data.py <Football> <prospect-actuary>
"""
import sys, os, json
import numpy as np, pandas as pd
FB, PA = sys.argv[1:3]
OUT = os.path.join(FB, "Trade_Market", "out")
A = pd.read_csv(os.path.join(OUT, "dynasty_add4_assets.csv"), dtype={"asset": str})
B = pd.read_csv(os.path.join(OUT, "dynasty_add4_beta.csv"))
meta = pd.read_csv(os.path.join(OUT, "dynasty_add4_meta.csv")).iloc[0]
s = float(meta.stretch)
sl = json.load(open(os.path.join(PA, "data", "sleeper_ids.json")))["m"]
x = {"sf": 0.0, "ppr1": -0.5, "tep": 0.0, "teams": 0.0, "start": 8 - 10.0}
Bp = B.pivot(index="group", columns="covariate", values="beta")
A = A[A.grp.isin(["QB", "RB", "WR", "TE"])].copy()
A["lv"] = A.theta_unstretched + np.array([sum(Bp.loc[g, c] * x[c] for c in x) for g in A.grp]) / s   # 1:1 scale betas = stretched / s
A["nm"] = A.asset.map(lambda a: sl.get(a, "|").split("|")[0] or None)
A["nm"] = A["nm"].fillna(A["name"])
A = A[A["nm"].notna()].sort_values("lv", ascending=False)
rows = [[r.nm, r.grp, round(float(r.lv), 4), int(r.n_trades)] for r in A.itertuples()]
data = {"asof": "2026-11-23", "trades": int(meta.trades_used), "first": "2026-05-01",
        "note": "Dynasty Daddy Trade Database, 1-for-1, 1-for-2, 2-for-2 and 2-for-3 dynasty trades", "rows": rows}
dst = os.path.join(PA, "value-research", "data", "tm.js")
open(dst, "w").write("window.TM = " + json.dumps(data, separators=(",", ":")) + ";\n")
print(len(rows), "players ->", dst)
