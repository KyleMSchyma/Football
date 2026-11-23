"""tm_05_compare_additive.py: compare the calibrated ADDITIVE market values (tm_04) directly with our values.

Inputs
  Trade_Market/out/{dynasty,redraft}_add_*.csv  (tm_04 aggregates; no league ids)
  Trade_Market/out/{dynasty,redraft}_assets.csv / _beta.csv (tm_02, for the before/after view)
  our values for a league grid: CSV from tm_03_our_values.js (site engine)
  prospect-actuary data/sleeper_ids.json   (Sleeper id -> our player name)
Outputs
  Trade_Market/compare_additive/*.png, *.csv, summary.json

Usage: python3 tm_05_compare_additive.py <football_repo> <our_values.csv> <sleeper_ids.json>
"""
import json, sys, os
import numpy as np, pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from scipy.stats import spearmanr

REPO, OURS, SLID = sys.argv[1:4]
TAG = sys.argv[4] if len(sys.argv) > 4 else "add"   # tm_04 output tag (add, add4 ...)
OUT = os.path.join(REPO, "Trade_Market", "out")
CMP = os.path.join(REPO, "Trade_Market", "compare_additive" if TAG == "add" else f"compare_{TAG}"); os.makedirs(CMP, exist_ok=True)
COL = {"QB": "#d1495b", "RB": "#2e86ab", "WR": "#3b9c5a", "TE": "#e09f3e", "PICK": "#7b5ea7", "OTH": "#888888"}
plt.rcParams.update({"figure.dpi": 130, "font.size": 9, "axes.spines.top": False, "axes.spines.right": False})
COVS = ["sf", "ppr1", "tep", "teams", "start"]
DEFAULT = dict(teams=12, ppr=1, tep=0, sf=1, starters=10)
SKILL = ["QB", "RB", "WR", "TE"]

sl = json.load(open(SLID))["m"]
ours = pd.read_csv(OURS)
summary = {}


def values(assets, beta, lg):
    B = beta.pivot(index="group", columns="covariate", values="beta")[COVS]
    x = np.array([lg["sf"] - 1, lg["ppr"] - 1, lg["tep"], (lg["teams"] - 12) / 2, lg["starters"] - 10], float)
    v = np.exp(assets["theta"].values + np.array([B.loc[g].values @ x for g in assets["grp"]]))
    return 1e5 * v / v[assets["grp"].isin(SKILL).values].max()


def our_slice(mode, lg):
    return ours[(ours["mode"] == mode) & (ours.teams == lg["teams"]) & (ours.ppr == lg["ppr"]) & (ours.tep == lg["tep"]) & (ours.sf == lg["sf"])]


def save(fig, name):
    fig.tight_layout(); fig.savefig(os.path.join(CMP, name)); plt.close(fig)


for TYPE, MODE in [("dynasty", "d"), ("redraft", "r")]:
    f = os.path.join(OUT, f"{TYPE}_{TAG}_assets.csv")
    if not os.path.exists(f):
        continue
    A = pd.read_csv(f, dtype={"asset": str}); beta = pd.read_csv(os.path.join(OUT, f"{TYPE}_{TAG}_beta.csv"))
    hold = pd.read_csv(os.path.join(OUT, f"{TYPE}_{TAG}_holdout.csv"))
    shp = pd.read_csv(os.path.join(OUT, f"{TYPE}_{TAG}_holdout_by_shape.csv"))
    meta = pd.read_csv(os.path.join(OUT, f"{TYPE}_{TAG}_meta.csv")).iloc[0]
    A0 = pd.read_csv(os.path.join(OUT, f"{TYPE}_assets.csv"), dtype={"asset": str}); beta0 = pd.read_csv(os.path.join(OUT, f"{TYPE}_beta.csv"))
    for X in (A, A0):
        X["our_name"] = X["asset"].map(lambda s: sl.get(s, "|").split("|")[0] or None)
    S = {"trades": int(meta.trades_used), "stretch": round(float(meta.stretch), 3), "lambda0": float(meta.lambda0),
         "converged": [int(meta.converged_long), int(meta.converged)]}

    o = our_slice(MODE, DEFAULT)
    A["market_add"] = values(A, beta, DEFAULT)
    A0["market_old"] = values(A0, beta0, DEFAULT)
    P = (A[A.grp.isin(SKILL)][["asset", "our_name", "grp", "n_trades", "market_add"]]
         .merge(A0[["asset", "market_old"]], on="asset", how="left")
         .merge(o[["name", "value", "rank"]], left_on="our_name", right_on="name", how="left")
         .drop(columns="name").rename(columns={"value": "our_value", "rank": "our_rank"})
         .sort_values("market_add", ascending=False))
    P["market_rank"] = np.arange(1, len(P) + 1)
    P["gap"] = P.market_add - P.our_value
    P.round(1).to_csv(os.path.join(CMP, f"{TYPE}_default_league_additive.csv"), index=False)
    top = P[P.our_value.notna()].head(150)

    # 1. holdout: consolidation gap and accuracy vs stretch
    fig, ax = plt.subplots(1, 2, figsize=(8.4, 3))
    ax[0].plot(hold.stretch, np.exp(-hold.consolidation_gap) - 1, color="#e09f3e")
    ax[0].axhline(0, color="black", lw=.6); ax[0].axvline(S["stretch"], color="grey", ls="--", lw=.8)
    ax[0].yaxis.set_major_formatter(matplotlib.ticker.PercentFormatter(1.0))
    ax[0].set_xlabel("stretch s (v' = v^s)"); ax[0].set_title("premium the fewer-asset side fetched\nover the model (holdout)")
    ax[1].plot(hold.stretch, hold.holdout_mae, color="#2e86ab"); ax[1].axvline(S["stretch"], color="grey", ls="--", lw=.8)
    ax[1].set_xlabel("stretch s"); ax[1].set_title("holdout mean |log gap| (all trades)")
    fig.suptitle(f"{TYPE.title()}: choosing the stretch (chosen s = {S['stretch']:.2f})")
    save(fig, f"{TYPE}_a1_stretch.png")
    hs = hold.iloc[(hold.stretch - S["stretch"]).abs().argsort()[:1]].iloc[0]
    S["holdout"] = {"gap_s1": round(float(hold.consolidation_gap.iloc[0]), 4), "mae_s1": round(float(hold.holdout_mae.iloc[0]), 4),
                    "gap_chosen": round(float(hs.consolidation_gap), 4), "mae_chosen": round(float(hs.holdout_mae), 4)}

    # 2. by trade shape: before vs after the stretch
    s_near = hold.stretch.iloc[(hold.stretch - S["stretch"]).abs().argmin()]
    b = shp[(shp.stretch == 1) & shp.mean_log_gap_few_minus_many.notna()].head(6)
    a = shp[(shp.stretch == s_near)].set_index("shape").reindex(b["shape"])
    fig, ax = plt.subplots(figsize=(6, 2.8)); xx = np.arange(len(b))
    ax.bar(xx - .2, np.exp(-b.mean_log_gap_few_minus_many.values) - 1, .4, label="before (s = 1)", color="#e09f3e")
    ax.bar(xx + .2, np.exp(-a.mean_log_gap_few_minus_many.values) - 1, .4, label=f"after (s = {s_near:.2f})", color="#3b9c5a")
    ax.set_xticks(xx); ax.set_xticklabels(b["shape"]); ax.axhline(0, color="black", lw=.6); ax.legend(fontsize=7)
    ax.yaxis.set_major_formatter(matplotlib.ticker.PercentFormatter(1.0))
    ax.set_title(f"{TYPE.title()} holdout: fewer-asset side premium by trade shape")
    save(fig, f"{TYPE}_a2_shape.png")
    S["shape"] = [dict(shape=r["shape"], trades=int(r.trades), before=round(float(np.exp(-r.mean_log_gap_few_minus_many) - 1), 3),
                       after=round(float(np.exp(-a.loc[r["shape"]].mean_log_gap_few_minus_many) - 1), 3)) for _, r in b.iterrows()]

    # 2b. accuracy by trade shape across stretches: does one additive scale fit straight-up AND package trades?
    fig, ax = plt.subplots(figsize=(6.4, 3.2))
    for sh_, c in [("1-for-1", "#555555"), ("2-for-2", "#999999"), ("1-for-2", "#e09f3e"), ("1-for-3", "#d1495b"), ("2-for-3", "#2e86ab"), ("2-for-4", "#3b9c5a")]:
        q = shp[shp["shape"] == sh_].sort_values("stretch")
        if len(q): ax.plot(q.stretch, q.mae, label=sh_, color=c)
    ax.axvline(S["stretch"], color="grey", ls="--", lw=.8); ax.set_xlabel("stretch s"); ax.set_ylabel("holdout mean |log gap|")
    ax.set_title(f"{TYPE.title()}: holdout error by trade shape"); ax.legend(fontsize=7, ncol=2)
    save(fig, f"{TYPE}_a7_mae_by_shape.png")
    S["mae_by_shape"] = shp[shp.stretch.isin([1.0, s_near])][["stretch", "shape", "trades", "mae"]].round(3).to_dict("records")

    # 3. direct comparison: additive market vs ours (and the old fit for reference)
    rho = spearmanr(top.market_add, top.our_value).correlation
    fig, axs = plt.subplots(1, 2, figsize=(10, 4.8), sharey=False)
    for ax, col, lab in [(axs[0], "market_old", "before (tm_02 additive fit)"), (axs[1], "market_add", f"calibrated additive (s = {S['stretch']:.2f})")]:
        for g, d in top.groupby("grp"):
            ax.scatter(d.our_value / 1000, d[col] / 1000, s=12, color=COL[g], label=g, alpha=.85)
        lim = 105; ax.plot([0, lim], [0, lim], color="grey", lw=.8, ls="--"); ax.set_xlim(0, lim); ax.set_ylim(0, lim)
        ax.set_xlabel("our value (thousands)"); ax.set_ylabel("market value (thousands)"); ax.set_title(lab)
    t = top.assign(d=top.market_add - top.our_value)
    for _, r in pd.concat([t.nlargest(6, "d"), t.nsmallest(6, "d")]).iterrows():
        axs[1].annotate(r.our_name, (r.our_value / 1000, r.market_add / 1000), fontsize=6.5, xytext=(3, 2), textcoords="offset points")
    axs[0].legend(fontsize=7)
    fig.suptitle(f"{TYPE.title()} at site default (12 tm, SF, PPR, 2 FLEX), top 150, both on 100k scale. Spearman {rho:.3f}")
    save(fig, f"{TYPE}_a3_market_vs_ours.png")
    S["spearman_top150"] = round(rho, 3)
    S["mean_abs_gap_top50_k"] = round(float(top.head(50).gap.abs().mean() / 1000), 1)

    # 4. value curve by rank: is the market now as steep as ours?
    fig, ax = plt.subplots(figsize=(6.4, 3.2))
    rk = np.arange(1, 151)
    for col, lab, c in [("our_value", "our model", "#555555"), ("market_old", "market, before", "#e09f3e"), ("market_add", "market, calibrated additive", "#7b5ea7")]:
        v = np.sort(P[col].dropna().values)[::-1][:150]
        ax.plot(rk[:len(v)], v / 1000, label=lab, color=c)
    ax.set_xlabel("rank (players only)"); ax.set_ylabel("value (thousands)"); ax.legend(fontsize=7)
    ax.set_title(f"{TYPE.title()}: value curve, site default league")
    save(fig, f"{TYPE}_a4_value_curve.png")
    curve = {}
    for col in ["our_value", "market_old", "market_add"]:
        v = np.sort(P[col].dropna().values)[::-1]
        curve[col] = {f"rank{r}": round(float(v[r - 1] / 1000), 1) for r in [1, 12, 24, 50, 100, 150] if len(v) >= r}
    S["curve"] = curve

    # 5. position gap, calibrated additive vs ours
    t2 = top[top.our_value >= 5000].assign(lr=lambda q: np.log(q.market_add.clip(lower=200) / q.our_value))   # skip near-replacement players
    pg = t2.groupby("grp").lr.mean()
    fig, ax = plt.subplots(figsize=(5, 2.6))
    ax.bar(pg.index, np.exp(pg.values) - 1, color=[COL[g] for g in pg.index]); ax.axhline(0, color="black", lw=.6)
    ax.yaxis.set_major_formatter(matplotlib.ticker.PercentFormatter(1.0))
    ax.set_title(f"{TYPE.title()}: calibrated market vs our values by position\n(top 150, our value 5k+, geometric mean)")
    save(fig, f"{TYPE}_a5_position_gap.png")
    S["position_gap"] = {g: round(float(np.exp(m) - 1), 3) for g, m in pg.items()}

    S["market_higher"] = t.nlargest(12, "d")[["our_name", "grp", "market_add", "our_value"]].round(0).to_dict("records")
    S["market_lower"] = t.nsmallest(12, "d")[["our_name", "grp", "market_add", "our_value"]].round(0).to_dict("records")

    # 6. dynasty picks
    if TYPE == "dynasty":
        pk = A[(A.grp == "PICK") & (A.pick_year == 2027) & (A.pick_round <= 3)].copy()
        op = o[o.pos == "PICK"].copy()
        op["slot"] = op.name.str.extract(r"(\d)\.(\d\d)").apply(lambda r: (int(r[0]) - 1) * 12 + int(r[1]), axis=1)
        def our_tier(rnd, tier):
            s = np.arange(1, 13) + (rnd - 1) * 12
            s = {"early": s[:4], "mid": s[4:8], "late": s[8:]}.get(tier, s)
            return op[op.slot.isin(s)].value.mean()
        pk["our_value"] = [our_tier(r, t_) for r, t_ in zip(pk.pick_round, pk.pick_tier)]
        pk = pk.sort_values(["pick_round", "market_add"], ascending=[True, False])
        fig, ax = plt.subplots(figsize=(6.4, 3)); xx = np.arange(len(pk))
        ax.bar(xx - .2, pk.market_add / 1000, .4, label="market, calibrated additive", color="#7b5ea7")
        ax.bar(xx + .2, pk.our_value / 1000, .4, label="our model (2027 slots)", color="#aaaaaa")
        ax.set_xticks(xx); ax.set_xticklabels(pk.name.str.replace("2027 ", ""), rotation=45, ha="right", fontsize=7)
        ax.set_ylabel("value (thousands)"); ax.legend(fontsize=7); ax.set_title("2027 rookie picks at site default")
        save(fig, "dynasty_a6_picks.png")
        S["picks"] = pk[["name", "n_trades", "market_add", "our_value"]].round(0).to_dict("records")
    summary[TYPE] = S

json.dump(summary, open(os.path.join(CMP, "summary.json"), "w"), indent=1, default=str)
print(json.dumps({k: {kk: v.get(kk) for kk in ["stretch", "holdout", "spearman_top150", "curve", "position_gap", "shape"]} for k, v in summary.items()}, indent=1, default=str))
