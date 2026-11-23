"""tm_03_compare.py: charts and comparison tables for the research-only "Trade" value method.

Inputs
  Trade_Market/out/{dynasty,redraft}_*.csv  (tm_02 aggregates; no league ids)
  our values for a league grid: CSV from tm_03_our_values.js (site engine, same math as the live pages)
  prospect-actuary data/sleeper_ids.json   (Sleeper id -> our player name)
Outputs
  Trade_Market/compare/*.png and *.csv

Usage: python3 tm_03_compare.py <football_repo> <our_values.csv> <sleeper_ids.json>
"""
import json, sys, os
import numpy as np, pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from scipy.stats import spearmanr

REPO, OURS, SLID = sys.argv[1:4]
OUT = os.path.join(REPO, "Trade_Market", "out")
CMP = os.path.join(REPO, "Trade_Market", "compare"); os.makedirs(CMP, exist_ok=True)
COL = {"QB": "#d1495b", "RB": "#2e86ab", "WR": "#3b9c5a", "TE": "#e09f3e", "PICK": "#7b5ea7", "OTH": "#888888"}
plt.rcParams.update({"figure.dpi": 130, "font.size": 9, "axes.spines.top": False, "axes.spines.right": False})
COVS = ["sf", "ppr1", "tep", "teams", "start"]
DEFAULT = dict(teams=12, ppr=1, tep=0, sf=1, starters=10)

sl = json.load(open(SLID))["m"]
ours = pd.read_csv(OURS)
summary = {}

def xvec(teams, ppr, tep, sf, starters):
    return np.array([sf - 1, ppr - 1, tep, (teams - 12) / 2, starters - 10], float)

def trade_values(assets, beta, lg, col="theta", bcol="beta"):
    B = beta.pivot(index="group", columns="covariate", values=bcol)[COVS]
    x = xvec(**lg)
    eta = assets[col].values + np.array([B.loc[g].values @ x for g in assets["grp"]])
    v = np.exp(eta)
    top = v[assets["grp"].isin(["QB", "RB", "WR", "TE"]).values].max()
    return 1e5 * v / top

def save(fig, name):
    fig.tight_layout(); fig.savefig(os.path.join(CMP, name)); plt.close(fig)

for TYPE, MODE in [("dynasty", "d"), ("redraft", "r")]:
    if not os.path.exists(os.path.join(OUT, f"{TYPE}_assets.csv")):
        continue
    A = pd.read_csv(os.path.join(OUT, f"{TYPE}_assets.csv"), dtype={"asset": str})
    beta = pd.read_csv(os.path.join(OUT, f"{TYPE}_beta.csv"))
    grid = pd.read_csv(os.path.join(OUT, f"{TYPE}_holdout_grid.csv"))
    meta = pd.read_csv(os.path.join(OUT, f"{TYPE}_meta.csv")).iloc[0]
    vol = pd.read_csv(os.path.join(OUT, f"{TYPE}_weekly_volume.csv"))
    mix = pd.read_csv(os.path.join(OUT, f"{TYPE}_format_mix.csv"))
    shape = pd.read_csv(os.path.join(OUT, f"{TYPE}_holdout_by_shape.csv"))
    A["our_name"] = A["asset"].map(lambda s: sl.get(s, "|").split("|")[0] or None)
    S = {"trades": int(meta.trades_used), "first": str(meta["first"])[:10], "last": str(meta["last"])[:10], "H": meta.H, "k": meta.k}

    # 1. volume
    fig, ax = plt.subplots(figsize=(7, 2.6))
    ax.bar(pd.to_datetime(vol.week), vol.N, width=5, color="#2e86ab")
    ax.set_title(f"{TYPE.title()} trades per week used ({S['trades']:,} total)"); ax.set_ylabel("trades")
    save(fig, f"{TYPE}_01_volume.png")

    # 2. format mix
    fig, axs = plt.subplots(1, 4, figsize=(9, 2.4))
    for ax, c, lab in zip(axs, ["teams", "sf", "ppr", "tep"], ["Teams", "Superflex", "PPR", "TE premium"]):
        t = mix.groupby(c).N.sum(); t = t / t.sum()
        ax.bar([str(i) for i in t.index], t.values, color="#7b5ea7"); ax.set_title(lab); ax.set_ylim(0, 1)
    axs[0].set_ylabel("share of trades")
    save(fig, f"{TYPE}_02_format_mix.png")
    mix.groupby(["teams", "sf", "ppr", "tep"]).N.sum().reset_index().sort_values("N", ascending=False).to_csv(os.path.join(CMP, f"{TYPE}_format_mix_summary.csv"), index=False)

    # 3. holdout grid
    fig, ax = plt.subplots(figsize=(6, 3.2))
    cg = grid[grid.k.notna()]
    for k, g in cg.groupby("k"):
        ax.plot(g.H, g.holdout_mae, marker="o", label=f"credibility k={k:g}")
    for _, r in grid[grid.k.isna()].iterrows():
        ax.axhline(r.holdout_mae, ls="--", color="grey" if "long" in r.model else "black", lw=1, label=r.model)
    ax.set_xscale("log"); ax.set_xticks(sorted(cg.H.unique())); ax.set_xticklabels([f"{h:g}" for h in sorted(cg.H.unique())])
    ax.set_xlabel("half-life H (days)"); ax.set_ylabel("holdout mean |log gap|")
    ax.set_title(f"{TYPE.title()}: which weighting predicts the last 14 days of trades best"); ax.legend(fontsize=7)
    save(fig, f"{TYPE}_03_holdout_grid.png")
    grid.to_csv(os.path.join(CMP, f"{TYPE}_holdout_grid.csv"), index=False)
    S["holdout"] = grid.round(4).to_dict("records")

    # 4. trade vs our values at the site default league
    lg = DEFAULT.copy()
    A["trade_value"] = trade_values(A, beta, lg)
    o = ours[(ours["mode"] == MODE) & (ours.teams == lg["teams"]) & (ours.ppr == lg["ppr"]) & (ours.tep == lg["tep"]) & (ours.sf == lg["sf"])]
    P = A[A.grp.isin(["QB", "RB", "WR", "TE"])].merge(o[["name", "value", "rank"]], left_on="our_name", right_on="name", how="left")
    P = P.sort_values("trade_value", ascending=False)
    top = P[P.value.notna()].head(150)
    rho = spearmanr(top.trade_value, top.value).correlation
    fig, ax = plt.subplots(figsize=(6.4, 5.4))
    for g, d in top.groupby("grp"):
        ax.scatter(d.value / 1000, d.trade_value / 1000, s=14, color=COL[g], label=g, alpha=.85)
    lim = max(top.value.max(), top.trade_value.max()) / 1000 * 1.05
    ax.plot([0, lim], [0, lim], color="grey", lw=.8, ls="--"); ax.set_xlim(0, lim); ax.set_ylim(0, lim)
    for _, r in pd.concat([top.assign(d=top.trade_value - top.value).nlargest(6, "d"), top.assign(d=top.trade_value - top.value).nsmallest(6, "d")]).iterrows():
        ax.annotate(r["name_x"] if "name_x" in r else r["our_name"], (r.value / 1000, r.trade_value / 1000), fontsize=6.5, xytext=(3, 2), textcoords="offset points")
    ax.set_xlabel("our model value (thousands, 100k scale)"); ax.set_ylabel("trade-implied value (thousands)")
    ax.set_title(f"{TYPE.title()} at site default (12 tm, SF, PPR, 2 FLEX): top 150 by trades\nSpearman {rho:.3f}"); ax.legend()
    save(fig, f"{TYPE}_04_trade_vs_ours.png")
    keep = ["asset", "our_name", "grp", "n_trades", "trades_last30", "Z", "trade_value", "value", "rank"]
    P2 = P[keep].rename(columns={"value": "our_value", "rank": "our_rank"})
    P2["trade_rank"] = np.arange(1, len(P2) + 1)
    P2["gap"] = P2.trade_value - P2.our_value
    P2.round(1).to_csv(os.path.join(CMP, f"{TYPE}_default_league_values.csv"), index=False)
    t2 = P2[P2.our_value.notna()].head(150)
    S["default_spearman_top150"] = round(rho, 3)
    S["missing_from_ours_top100"] = P2.head(100)[P2.head(100).our_value.isna()].our_name.fillna(P2.asset).tolist()
    S["trade_higher"] = t2.nlargest(12, "gap")[["our_name", "grp", "trade_value", "our_value"]].round(0).to_dict("records")
    S["trade_lower"] = t2.nsmallest(12, "gap")[["our_name", "grp", "trade_value", "our_value"]].round(0).to_dict("records")

    # 5. position-level gaps: mean log ratio trade/our by position (top 150)
    t2 = t2.assign(lr=np.log(t2.trade_value.clip(lower=200) / t2.our_value.clip(lower=200)))
    pg = t2.groupby("grp").lr.agg(["mean", "count"]).reset_index()
    fig, ax = plt.subplots(figsize=(5, 2.6))
    ax.bar(pg.grp, np.exp(pg["mean"]) - 1, color=[COL[g] for g in pg.grp]); ax.axhline(0, color="black", lw=.6)
    ax.yaxis.set_major_formatter(matplotlib.ticker.PercentFormatter(1.0))
    ax.set_title(f"{TYPE.title()}: trade market vs our values by position (geo. mean, top 150)")
    save(fig, f"{TYPE}_05_position_gap.png")
    S["position_gap"] = {r.grp: round(float(np.exp(r["mean"]) - 1), 3) for _, r in pg.iterrows()}

    # 6. setting effects: how much each position's value moves when a setting changes, trades vs ours
    rows = []
    changes = [("Superflex off", dict(sf=0, starters=9)), ("Half PPR", dict(ppr=0.5)), ("TE premium +0.5", dict(tep=0.5)),
               ("TE premium +1.0", dict(tep=1)), ("10 teams", dict(teams=10)), ("14 teams", dict(teams=14))]
    base_t = trade_values(A, beta, DEFAULT)
    for lab, ch in changes:
        lg2 = {**DEFAULT, **ch}
        tv2 = trade_values(A, beta, lg2)
        o2 = ours[(ours["mode"] == MODE) & (ours.teams == lg2["teams"]) & (ours.ppr == lg2["ppr"]) & (ours.tep == lg2["tep"]) & (ours.sf == lg2["sf"])]
        for g in ["QB", "RB", "WR", "TE"]:
            m = (A.grp == g).values
            idx = np.argsort(-base_t * m)[:24 if g != "TE" else 12]
            names = A.our_name.values[idx]
            tr = np.exp(np.mean(np.log(tv2[idx] / base_t[idx])))
            ob = o.set_index("name").value.reindex(names); oc = o2.set_index("name").value.reindex(names)
            ok = (ob > 0) & (oc > 0)
            orr = np.exp(np.mean(np.log(oc[ok] / ob[ok]))) if ok.sum() else np.nan
            rows.append(dict(change=lab, pos=g, trade_ratio=tr, our_ratio=orr))
    se = pd.DataFrame(rows); se.round(3).to_csv(os.path.join(CMP, f"{TYPE}_setting_effects.csv"), index=False)
    fig, axs = plt.subplots(2, 3, figsize=(9, 4.8), sharey=True)
    for ax, (lab, d) in zip(axs.flat, se.groupby("change", sort=False)):
        xx = np.arange(4)
        ax.bar(xx - .2, d.trade_ratio - 1, .4, label="trade market", color="#7b5ea7")
        ax.bar(xx + .2, d.our_ratio - 1, .4, label="our model", color="#aaaaaa")
        ax.set_xticks(xx); ax.set_xticklabels(d.pos); ax.axhline(0, color="black", lw=.6); ax.set_title(lab)
        ax.yaxis.set_major_formatter(matplotlib.ticker.PercentFormatter(1.0))
    axs[0, 0].legend(fontsize=7)
    fig.suptitle(f"{TYPE.title()}: change in value of top starters vs site default, by setting (100k scale re-normalised)")
    save(fig, f"{TYPE}_06_setting_effects.png")
    S["setting_effects"] = se.round(3).to_dict("records")

    # 7. agreement across the league grid
    agr = []
    for teams in [8, 10, 12, 14]:
        for sf in [0, 1]:
            for ppr in [0.5, 1]:
                for tep in [0, 0.5, 1]:
                    lg2 = dict(teams=teams, ppr=ppr, tep=tep, sf=sf, starters=9 + sf)
                    tv2 = trade_values(A, beta, lg2)
                    o2 = ours[(ours["mode"] == MODE) & (ours.teams == teams) & (ours.ppr == ppr) & (ours.tep == tep) & (ours.sf == sf)]
                    q = pd.DataFrame({"n": A.our_name, "t": tv2, "g": A.grp})
                    q = q[q.g.isin(["QB", "RB", "WR", "TE"])].merge(o2[["name", "value"]], left_on="n", right_on="name").nlargest(150, "t")
                    agr.append(dict(teams=teams, sf=sf, ppr=ppr, tep=tep, spearman_top150=spearmanr(q.t, q.value).correlation))
    agr = pd.DataFrame(agr); agr.round(3).to_csv(os.path.join(CMP, f"{TYPE}_agreement_grid.csv"), index=False)
    fig, ax = plt.subplots(figsize=(7, 2.8))
    lab = agr.apply(lambda r: f"{r.teams:.0f}{'SF' if r.sf else '1QB'}\n{r.ppr:g}/{r.tep:g}", axis=1)
    ax.bar(range(len(agr)), agr.spearman_top150, color=["#d1495b" if s else "#2e86ab" for s in agr.sf])
    ax.set_xticks(range(len(agr))); ax.set_xticklabels(lab, fontsize=5)
    ax.set_ylim(max(0, agr.spearman_top150.min() - .1), 1); ax.set_ylabel("Spearman, top 150")
    ax.set_title(f"{TYPE.title()}: agreement with our values in every league (teams, SF, PPR/TE premium)")
    save(fig, f"{TYPE}_07_agreement_grid.png")
    S["agreement_range"] = [round(agr.spearman_top150.min(), 3), round(agr.spearman_top150.max(), 3)]

    # 8. credibility
    fig, ax = plt.subplots(figsize=(5.4, 3))
    pl = A[A.grp.isin(["QB", "RB", "WR", "TE"])]
    ax.scatter(pl.weighted_info, pl.Z, s=6, c=[COL[g] for g in pl.grp], alpha=.6); ax.set_xscale("log")
    ax.set_xlabel("recency-weighted trade appearances (I)"); ax.set_ylabel("credibility Z = I/(I+k)")
    ax.set_title(f"{TYPE.title()}: credibility given to each player's recent price (k={S['k']:g})")
    save(fig, f"{TYPE}_08_credibility.png")

    # 9. consolidation check
    fig, ax = plt.subplots(figsize=(5.4, 2.8))
    sh = shape[shape.mean_log_gap_few_minus_many.notna()].head(6)
    ax.bar(sh["shape"], np.exp(sh.mean_log_gap_few_minus_many) - 1, color="#e09f3e"); ax.axhline(0, color="black", lw=.6)
    ax.yaxis.set_major_formatter(matplotlib.ticker.PercentFormatter(1.0))
    ax.set_title(f"{TYPE.title()}: holdout, side with fewer assets priced vs additive model\n(+ = consolidation premium)")
    save(fig, f"{TYPE}_09_consolidation.png")
    S["shape"] = shape.round(4).to_dict("records")

    # 10. value over time
    vt = os.path.join(OUT, f"{TYPE}_value_over_time.csv")
    if os.path.exists(vt):
        T = pd.read_csv(vt, dtype={"asset": str})
        last = T[T["asof"] == T["asof"].max()]
        pick = last[last.grp != "PICK"].nlargest(10, "theta").asset.tolist()
        if TYPE == "dynasty":
            pick += last[last.grp == "PICK"].nlargest(3, "theta").asset.tolist()
        fig, ax = plt.subplots(figsize=(7, 3.6))
        for a in pick:
            d = T[T["asset"] == a].sort_values("asof")
            nm = sl.get(a, "|").split("|")[0] or d.name.iloc[0]
            ax.plot(pd.to_datetime(d["asof"]), np.exp(d["theta"]), marker=".", label=nm, color=COL.get(d.grp.iloc[0]))
        ax.set_yscale("log"); ax.set_ylabel(f"value relative to a 2027 mid 1st (log)")
        ax.set_title(f"{TYPE.title()}: trade-implied value over time (default league)"); ax.legend(fontsize=6, ncol=2)
        save(fig, f"{TYPE}_10_value_over_time.png")

    # 11. dynasty only: picks vs our 2027 pick slots (12 teams)
    if TYPE == "dynasty":
        pk = A[(A.grp == "PICK") & (A.pick_year == 2027)].copy()
        op = o[o.pos == "PICK"].copy()
        op["slot"] = op.name.str.extract(r"(\d)\.(\d\d)").apply(lambda r: (int(r[0]) - 1) * 12 + int(r[1]), axis=1)
        def our_tier(rnd, tier):
            s = np.arange(1, 13) + (rnd - 1) * 12
            if tier == "early": s = s[:4]
            elif tier == "mid": s = s[4:8]
            elif tier == "late": s = s[8:]
            return op[op.slot.isin(s)].value.mean()
        pk["our_value"] = [our_tier(r, t) for r, t in zip(pk.pick_round, pk.pick_tier)]
        pk = pk[pk.pick_round <= 3].sort_values(["pick_round", "trade_value"], ascending=[True, False])
        fig, ax = plt.subplots(figsize=(6.4, 3))
        xx = np.arange(len(pk))
        ax.bar(xx - .2, pk.trade_value / 1000, .4, label="trade market", color="#7b5ea7")
        ax.bar(xx + .2, pk.our_value / 1000, .4, label="our model (2027 slots)", color="#aaaaaa")
        ax.set_xticks(xx); ax.set_xticklabels(pk.name.str.replace("2027 ", ""), rotation=45, ha="right", fontsize=7)
        ax.set_ylabel("value (thousands)"); ax.legend(); ax.set_title("2027 rookie picks at site default: trades vs our model")
        save(fig, "dynasty_11_picks.png")
        pk[["name", "n_trades", "trade_value", "our_value"]].round(0).to_csv(os.path.join(CMP, "dynasty_picks.csv"), index=False)
        S["picks"] = pk[["name", "n_trades", "trade_value", "our_value"]].round(0).to_dict("records")
    summary[TYPE] = S

json.dump(summary, open(os.path.join(CMP, "summary.json"), "w"), indent=1, default=str)
print(json.dumps({k: {kk: v[kk] for kk in ["trades", "H", "k", "default_spearman_top150", "agreement_range", "position_gap"]} for k, v in summary.items()}, indent=1, default=str))
