"""
Landing-spot offense study, step 2: does the drafting team's prior-year fantasy offense
tell us anything about a rookie's production, and anything BEYOND the post-draft grade?

Team offense = drafting team's fantasy points per game the season before the draft (full PPR,
4-pt pass TD, all players), as a within-season z-score (0 = league average, +1 = one SD above).
"Same-position" version = only that team's points at the rookie's position.

Outcomes
  rookie_ppg    PPR points per TEAM game in the rookie season (missed games = 0), classes 2010-2025
  ppg_played    PPR points per game PLAYED, rookies with 6+ games (efficiency when on the field)
  y13_ppg       PPR points per 17 games over years 1-3, classes 2010-2023
  hit_any       ever reached a tier (QB/RB24, WR36, TE18), outcome-complete players
Methods (ATPA/PA): terciles and grade-band splits; OLS with robust SE and an interaction;
logistic regression; leave-one-class-out (LOCO) model comparison, linear and gradient boosting;
PDP/ICE from the boosted model.
"""
import os, json
import numpy as np
import pandas as pd
import statsmodels.formula.api as smf
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.inspection import partial_dependence
from sklearn.metrics import roc_auc_score, log_loss
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))
p = pd.read_csv(os.path.join(HERE, "lso_players.csv"))
p["ppg_played"] = np.where(p.gp_y1 >= 6, p.pts_y1 / p.gp_y1.clip(lower=1), np.nan)
p["off_z"] = p["prev_ppg_z"]
p["pos_off_z"] = [r[f"prev_ppg_{r.position}_z"] for _, r in p.iterrows()]
p["off_third"] = pd.cut(p["prev_ppg_pct"], [0, 1/3, 2/3, 1.0001], labels=["Bottom third", "Middle third", "Top third"])
POS = ["QB", "RB", "WR", "TE"]
out = {}
lines = []
def log(s=""):
    print(s); lines.append(s)

rk = p[p.rookie_complete].copy()      # 2010-2025 classes
log(f"Rookie-season sample: {len(rk)} players, classes {rk['class'].min()}-{rk['class'].max()}")

# ---- 1. raw splits by position -----------------------------------------------------------
t1 = (rk.groupby(["position", "off_third"], observed=True)
        .agg(n=("name", "size"), rookie_ppg=("rookie_ppg", "mean"), avg_pick=("pick", "mean"),
             post_pctile=("post_pctile", "mean"), hit_any=("hit_any", "mean")).round(3).reset_index())
t1.to_csv(os.path.join(HERE, "lso_raw_by_position.csv"), index=False)
log("\n1. Raw: rookie points per team game by prior-year team offense third\n" + t1.to_string(index=False))

# ---- 2. by grade band x offense third ------------------------------------------------------
t2 = (rk.groupby(["position", "grade_band", "off_third"], observed=True)
        .agg(n=("name", "size"), rookie_ppg=("rookie_ppg", "mean"), hit_any=("hit_any", "mean"))
        .round(2).reset_index())
t2.to_csv(os.path.join(HERE, "lso_by_grade_band.csv"), index=False)
t2b = (rk.groupby(["grade_band", "off_third"], observed=True)
         .agg(n=("name", "size"), rookie_ppg=("rookie_ppg", "mean"), hit_any=("hit_any", "mean")).round(2))
log("\n2. All positions, grade band x offense third\n" + t2b.to_string())
log("\n2b. By position, grade band x offense third (rookie PPG)\n" +
    t2.pivot_table(index=["position", "grade_band"], columns="off_third", values="rookie_ppg", observed=True).round(2).to_string())

# ---- 3. regression: offense beyond the post-draft score --------------------------------------
def ols(df, f):
    m = smf.ols(f, data=df).fit(cov_type="HC1")
    return m
reg = []
for outc, data in [("rookie_ppg", rk), ("ppg_played", rk.dropna(subset=["ppg_played"])),
                   ("y13_ppg", p[p.y13_complete])]:
    for pos in POS:
        d = data[data.position == pos]
        for var in ["off_z", "pos_off_z"]:
            raw = ols(d, f"{outc} ~ {var}")
            adj = ols(d, f"{outc} ~ post_score + I(post_score**2) + {var}")
            inter = ols(d, f"{outc} ~ post_score + I(post_score**2) + {var} + post_score:{var}")
            reg.append(dict(outcome=outc, position=pos, offense=var, n=len(d),
                            raw_coef=raw.params[var], raw_p=raw.pvalues[var],
                            adj_coef=adj.params[var], adj_lo=adj.conf_int().loc[var, 0], adj_hi=adj.conf_int().loc[var, 1],
                            adj_p=adj.pvalues[var], r2_grade_only=ols(d, f"{outc} ~ post_score + I(post_score**2)").rsquared,
                            r2_with_off=adj.rsquared, inter_coef=inter.params[f"post_score:{var}"],
                            inter_p=inter.pvalues[f"post_score:{var}"], outcome_mean=d[outc].mean()))
reg = pd.DataFrame(reg).round(4)
reg.to_csv(os.path.join(HERE, "lso_regressions.csv"), index=False)
log("\n3. OLS (robust SE): effect of +1 SD team offense, raw and holding post-draft score fixed\n" +
    reg[["outcome", "position", "offense", "n", "raw_coef", "raw_p", "adj_coef", "adj_lo", "adj_hi", "adj_p",
         "r2_grade_only", "r2_with_off", "inter_coef", "inter_p"]].to_string(index=False))

# logistic on hit_any (outcome-complete)
hc = p[p.hit_any.notna()].copy()
hc["lp"] = np.log(hc.p_any.clip(0.005, 0.995) / (1 - hc.p_any.clip(0.005, 0.995)))
lg = []
for pos in POS:
    d = hc[hc.position == pos]
    m = smf.logit("hit_any ~ lp + off_z", data=d).fit(disp=0)
    lg.append(dict(position=pos, n=len(d), hits=int(d.hit_any.sum()), odds_ratio_per_sd=np.exp(m.params["off_z"]),
                   or_lo=np.exp(m.conf_int().loc["off_z", 0]), or_hi=np.exp(m.conf_int().loc["off_z", 1]), p=m.pvalues["off_z"]))
lg = pd.DataFrame(lg).round(3)
lg.to_csv(os.path.join(HERE, "lso_logit_hit.csv"), index=False)
log("\n3b. Logistic: odds of ever hitting a tier per +1 SD team offense, holding the model's P(any tier)\n" + lg.to_string(index=False))

# ---- 4. LOCO model comparison ----------------------------------------------------------------
def loco(d, outc, feats, kind):
    pred = pd.Series(np.nan, index=d.index)
    for c in sorted(d["class"].unique()):
        tr, te = d[d["class"] != c], d[d["class"] == c]
        if kind == "lin":
            f = f"{outc} ~ post_score + I(post_score**2)" + "".join(f" + {x}" for x in feats if x != "post_score")
            m = smf.ols(f, data=tr).fit()
            pred[te.index] = m.predict(te)
        else:
            m = HistGradientBoostingRegressor(max_depth=2, learning_rate=0.05, max_iter=150,
                                              min_samples_leaf=20, random_state=1)
            m.fit(tr[feats], tr[outc]); pred[te.index] = m.predict(te[feats])
    return pred
cmp_rows = []
for pos in POS:
    d = rk[rk.position == pos]
    for kind in ["lin", "gbm"]:
        for label, feats in [("grade only", ["post_score"]), ("grade + team offense", ["post_score", "off_z"]),
                             ("grade + position offense", ["post_score", "pos_off_z"])]:
            pr = loco(d, "rookie_ppg", feats, kind)
            rmse = float(np.sqrt(np.mean((d.rookie_ppg - pr) ** 2)))
            cmp_rows.append(dict(position=pos, model=kind, features=label, loco_rmse=rmse))
    # logistic hit comparison
    h = hc[hc.position == pos]
    for label, f in [("grade only", "hit_any ~ lp"), ("grade + team offense", "hit_any ~ lp + off_z")]:
        pr = pd.Series(np.nan, index=h.index)
        for c in sorted(h["class"].unique()):
            m = smf.logit(f, data=h[h["class"] != c]).fit(disp=0); te = h[h["class"] == c]; pr[te.index] = m.predict(te)
        cmp_rows.append(dict(position=pos, model="logit hit_any", features=label,
                             loco_logloss=log_loss(h.hit_any, pr), loco_auc=roc_auc_score(h.hit_any, pr)))
cmp = pd.DataFrame(cmp_rows).round(4)
cmp.to_csv(os.path.join(HERE, "lso_model_comparison.csv"), index=False)
log("\n4. Leave-one-class-out comparison (lower RMSE / log-loss, higher AUC = better)\n" + cmp.to_string(index=False))

# ---- 5. PDP / ICE on the boosted model ------------------------------------------------------
fig, axes = plt.subplots(1, 4, figsize=(15, 3.8), sharey=False)
pdp_rows = []
for ax, pos in zip(axes, POS):
    d = rk[rk.position == pos]
    m = HistGradientBoostingRegressor(max_depth=2, learning_rate=0.05, max_iter=150, min_samples_leaf=20, random_state=1)
    X = d[["post_score", "off_z"]]
    m.fit(X, d.rookie_ppg)
    pdres = partial_dependence(m, X, ["off_z"], kind="both", grid_resolution=25, percentiles=(0.05, 0.95))
    grid = pdres["grid_values"][0]; avg = pdres["average"][0]; ice = pdres["individual"][0]
    rng = np.random.default_rng(1)
    for i in rng.choice(len(ice), min(40, len(ice)), replace=False):
        ax.plot(grid, ice[i], color="#9ab", lw=0.6, alpha=0.5)
    ax.plot(grid, avg, color="#e8590c", lw=2.5)
    ax.set_title(f"{pos}: PDP + ICE"); ax.set_xlabel("prior-year team offense (SD from avg)")
    if pos == "QB": ax.set_ylabel("predicted rookie PPR pts / game")
    for g, a in zip(grid, avg): pdp_rows.append(dict(position=pos, off_z=g, pdp_rookie_ppg=a))
plt.tight_layout(); plt.savefig(os.path.join(HERE, "plot_lso_pdp_ice.png"), dpi=110)
pd.DataFrame(pdp_rows).round(3).to_csv(os.path.join(HERE, "lso_pdp.csv"), index=False)

# raw scatter-style bar chart: rookie ppg by offense third, grade band panels
fig, axes = plt.subplots(1, 4, figsize=(15, 3.8))
for ax, pos in zip(axes, POS):
    t = t2[t2.position == pos].pivot_table(index="grade_band", columns="off_third", values="rookie_ppg", observed=True)
    t.plot.bar(ax=ax, color=["#adb5bd", "#748ffc", "#e8590c"], legend=(pos == "QB"), rot=0)
    ax.set_title(pos); ax.set_xlabel("post-draft grade")
    if pos == "QB": ax.legend(title="prior-year team offense"); ax.set_ylabel("rookie PPR pts / team game" if pos == "QB" else "")
plt.tight_layout(); plt.savefig(os.path.join(HERE, "plot_lso_grade_band.png"), dpi=110)

open(os.path.join(HERE, "lso_results_log.txt"), "w").write("\n".join(lines))
