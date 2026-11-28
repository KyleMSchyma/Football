"""Archetype research, step 2: do archetypes double count production? (Kyle's hypothesis, 2026-11-28)

Approved labels: two layers (role = how much, style = how), explosive RB and red-zone TE dropped.
Baseline = what the live values already use: this season's PPG and games, last season's PPG and games (credible-PPG
inputs), age, draft pick. Target = NEXT season PPR points per game (next season >= 4 games; 2026 = weeks 1-12).
Part A: how much of each archetype the baseline already explains (5-fold CV, one-vs-rest AUC per label).
Part B: rolling-origin holdout (test seasons 2020-2025, train on all earlier seasons): RMSE / R2 / Spearman for
        baseline vs + role, + style, + role + style, + raw usage inputs, and archetypes alone. Paired bootstrap by player.
Part C: are the baseline's out-of-sample errors different by archetype (residual means, 95% CI, ANOVA)?
Outputs: tables/dc_*.csv, plots/dc_*.png"""
import numpy as np, pandas as pd, matplotlib
matplotlib.use("Agg"); import matplotlib.pyplot as plt
from scipy import stats
from sklearn.linear_model import LogisticRegression, RidgeCV
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import make_pipeline
from sklearn.model_selection import cross_val_predict, StratifiedKFold
from sklearn.metrics import roc_auc_score
PAL = ["#257de0", "#f47230", "#00b894", "#f2a600", "#ee7fac", "#008a17", "#6a4ce2"]
plt.rcParams.update({"font.size": 10, "axes.spines.top": False, "axes.spines.right": False, "axes.edgecolor": "#999999",
                     "xtick.color": "#666666", "ytick.color": "#666666", "axes.grid": True, "grid.color": "#e6e6e6", "grid.linewidth": 0.6})
rng = np.random.default_rng(7)
ps = pd.read_csv("ar_player_seasons.csv")
ps["ppg"] = ps.fantasy_points_ppr / ps.games.replace(0, np.nan)
nxt = ps[["player_id", "season", "ppg", "games"]].rename(columns={"ppg": "ppg_next", "games": "games_next"}); nxt["season"] -= 1
prv = ps[["player_id", "season", "ppg", "games"]].rename(columns={"ppg": "ppg_prev", "games": "games_prev"}); prv["season"] += 1
BASE = ["ppg", "games", "ppg_prev", "games_prev", "no_prev", "age", "log_pick", "undrafted"]
USAGE = {"QB": ["rush_ypg", "scramble_rate", "adot_pass", "deep_rate", "int_rate", "aggressiveness", "epa_db", "dropbacks_pg"],
         "RB": ["touches_pg", "snap_share", "opp_share", "targets_pg", "tgt_mix", "gl_share", "explosive_rate", "weight"],
         "WR": ["target_share", "air_share", "adot", "deep_rate", "behind_rate", "yac_per_rec", "rz_mix", "height", "weight"],
         "TE": ["snap_share", "targets_per_snap", "target_share", "rz_mix", "adot", "yac_per_rec", "weight"]}
POS = ["QB", "RB", "WR", "TE"]
partA, partB, partC, boot_rows = [], [], [], []
def prep(pos):
    d = pd.read_csv(f"ar_labels_{pos}.csv")
    d = d.drop(columns=[c for c in ["ppg"] if c in d]).merge(ps[["player_id", "season", "ppg"]], on=["player_id", "season"], how="left")
    d = d.merge(prv, on=["player_id", "season"], how="left").merge(nxt, on=["player_id", "season"], how="left")
    d["no_prev"] = d.ppg_prev.isna().astype(int); d["ppg_prev"] = d.ppg_prev.fillna(0); d["games_prev"] = d.games_prev.fillna(0)
    d["age"] = d.season + 0.67 - (pd.to_datetime(d.birth_date).dt.year + pd.to_datetime(d.birth_date).dt.dayofyear / 365.25)
    d["age"] = d.age.fillna(d.age.median())
    d["undrafted"] = d.draft_pick.isna().astype(int); d["log_pick"] = np.log(d.draft_pick.fillna(262))
    for c in USAGE[pos]: d[c] = d[c].astype(float).fillna(d[c].median())
    return d
def dummies(d, col, pref): return pd.get_dummies(d[col], prefix=pref, drop_first=True, dtype=float)
for pos in POS:
    d = prep(pos)
    # ---------- Part A: does production already know the archetype?
    h = d[d.season < 2026]
    for layer in ["role_layer", "style_layer"]:
        y = h[layer].astype(str).values
        clf = make_pipeline(StandardScaler(), LogisticRegression(max_iter=2000))
        pr = cross_val_predict(clf, h[BASE], y, cv=StratifiedKFold(5, shuffle=True, random_state=1), method="predict_proba")
        classes = np.unique(y)
        for j, c in enumerate(classes):
            partA.append(dict(position=pos, layer=layer.replace("_layer", ""), label=c, n=int((y == c).sum()),
                              auc_from_production=round(roc_auc_score(y == c, pr[:, j]), 3)))
    # ---------- Part B: rolling-origin holdout on next-season PPG
    m = d[(d.games_next >= 4) & d.ppg_next.notna()].copy()
    R = dummies(m, "role_layer", "role"); S = dummies(m, "style_layer", "style")
    sets = {"Baseline (production, age, pick)": m[BASE],
            "+ role layer": pd.concat([m[BASE], R], axis=1),
            "+ style layer": pd.concat([m[BASE], S], axis=1),
            "+ role + style": pd.concat([m[BASE], R, S], axis=1),
            "+ raw usage inputs": pd.concat([m[BASE], m[USAGE[pos]]], axis=1),
            "Archetypes only (no production)": pd.concat([R, S], axis=1)}
    preds = {k: np.full(len(m), np.nan) for k in sets}
    for t in range(2020, 2026):
        tr = (m.season < t).values; te = (m.season == t).values
        for k, X in sets.items():
            mod = make_pipeline(StandardScaler(), RidgeCV(alphas=np.logspace(-2, 3, 20))).fit(X[tr], m.ppg_next[tr])
            preds[k][te] = mod.predict(X[te])
    ev = ~np.isnan(preds["Baseline (production, age, pick)"]); y = m.ppg_next.values[ev]
    base_err = (preds["Baseline (production, age, pick)"][ev] - y) ** 2
    pid = m.player_id.values[ev]; up = np.unique(pid); idx = {p: np.where(pid == p)[0] for p in up}
    for k in sets:
        p = preds[k][ev]; e = (p - y) ** 2
        rmse = np.sqrt(e.mean()); r2 = 1 - e.sum() / ((y - y.mean()) ** 2).sum()
        # paired bootstrap by player of RMSE difference vs baseline
        diffs = []
        for _ in range(1000):
            s = np.concatenate([idx[q] for q in rng.choice(up, len(up))])
            diffs.append(np.sqrt(e[s].mean()) - np.sqrt(base_err[s].mean()))
        lo, hi = np.percentile(diffs, [2.5, 97.5])
        partB.append(dict(position=pos, model=k, n_test=int(ev.sum()), rmse=round(rmse, 3), r2=round(r2, 3),
                          spearman=round(stats.spearmanr(p, y)[0], 3), d_rmse_vs_base=round(rmse - np.sqrt(base_err.mean()), 4),
                          ci_lo=round(lo, 4), ci_hi=round(hi, 4)))
    # ---------- Part C: baseline holdout residual by archetype
    res = y - preds["Baseline (production, age, pick)"][ev]
    mm = m[ev].assign(resid=res)
    for layer in ["role_layer", "style_layer"]:
        groups = [g.resid.values for _, g in mm.groupby(layer)]
        F, pv = stats.f_oneway(*groups)
        for lab, g in mm.groupby(layer):
            se = g.resid.std(ddof=1) / np.sqrt(len(g))
            partC.append(dict(position=pos, layer=layer.replace("_layer", ""), label=lab, n=len(g), mean_resid_ppg=round(g.resid.mean(), 3),
                              ci95=round(1.96 * se, 3), anova_p_layer=round(pv, 4)))
A = pd.DataFrame(partA); B = pd.DataFrame(partB); C = pd.DataFrame(partC)
A.to_csv("tables/dc_A_archetype_explained_by_production.csv", index=False)
B.to_csv("tables/dc_B_holdout_next_season_ppg.csv", index=False)
C.to_csv("tables/dc_C_baseline_residual_by_archetype.csv", index=False)
print(A.to_string()); print(B.to_string()); print(C.to_string())
# ---------- charts
fig, axs = plt.subplots(1, 4, figsize=(16, 4.6), sharex=True)
for ax, pos in zip(axs, POS):
    a = A[A.position == pos].reset_index(drop=True)
    cols = [PAL[0] if l == "role" else PAL[1] for l in a.layer]
    ax.barh(range(len(a)), a.auc_from_production, color=cols, height=0.65)
    for i, v in enumerate(a.auc_from_production): ax.text(v + 0.01, i, f"{v:.2f}", va="center", fontsize=8)
    ax.set_yticks(range(len(a))); ax.set_yticklabels([f"{l}: {b}" for l, b in zip(a.layer, a.label)], fontsize=8); ax.invert_yaxis()
    ax.axvline(0.5, color="#999999", lw=1, ls="--"); ax.set_xlim(0.4, 1.05); ax.set_title(pos, loc="left", fontweight="bold")
axs[0].set_xlabel(""); fig.supxlabel("AUC: how well production + age + pick already identify the label (0.5 = not at all, 1.0 = perfectly)", fontsize=9)
fig.suptitle("Part A. Does production already 'know' the archetype? Blue = role layer, orange = style layer", x=0.01, ha="left", fontweight="bold")
fig.tight_layout(); fig.savefig("plots/dc_A_explained_by_production.png", dpi=130); plt.close(fig)
models = ["+ role layer", "+ style layer", "+ role + style", "+ raw usage inputs"]
fig, axs = plt.subplots(1, 4, figsize=(16, 3.8), sharey=True)
for ax, pos in zip(axs, POS):
    b = B[(B.position == pos) & B.model.isin(models)].set_index("model").reindex(models)
    yv = np.arange(len(models))
    ax.errorbar(b.d_rmse_vs_base, yv, xerr=[b.d_rmse_vs_base - b.ci_lo, b.ci_hi - b.d_rmse_vs_base], fmt="o", color=PAL[0], ms=7, capsize=3, lw=1.5)
    ax.axvline(0, color="#191919", lw=1); ax.set_yticks(yv); ax.set_yticklabels(models); ax.invert_yaxis()
    base = B[(B.position == pos) & (B.model.str.startswith("Baseline"))].iloc[0]
    ax.set_title(f"{pos} (baseline RMSE {base.rmse:.2f} PPG, R2 {base.r2:.2f})", loc="left", fontweight="bold", fontsize=9.5)
fig.supxlabel("change in next-season holdout RMSE vs baseline (PPG; left of 0 = better), 95% bootstrap CI", fontsize=9)
fig.suptitle("Part B. Do archetypes add anything once production is in the model? (test seasons 2020-2025)", x=0.01, ha="left", fontweight="bold")
fig.tight_layout(); fig.savefig("plots/dc_B_holdout_gain.png", dpi=130); plt.close(fig)
fig, axs = plt.subplots(1, 4, figsize=(16, 4.4), sharex=True)
for ax, pos in zip(axs, POS):
    c = C[C.position == pos].reset_index(drop=True)
    cols = [PAL[0] if l == "role" else PAL[1] for l in c.layer]
    for i, r in c.iterrows():
        ax.errorbar(r.mean_resid_ppg, i, xerr=r.ci95, fmt="o", color=cols[i], ms=6, capsize=3)
    ax.axvline(0, color="#191919", lw=1); ax.set_yticks(range(len(c))); ax.set_yticklabels([f"{l}: {b} ({n})" for l, b, n in zip(c.layer, c.label, c.n)], fontsize=8); ax.invert_yaxis()
    pr = c.groupby("layer").anova_p_layer.first()
    ax.set_title(f"{pos}  p(role)={pr.get('role', np.nan):.2f}  p(style)={pr.get('style', np.nan):.2f}", loc="left", fontweight="bold", fontsize=9)
fig.supxlabel("average miss of the production baseline next season (actual - predicted PPG), 95% CI; 0 = baseline already right", fontsize=9)
fig.suptitle("Part C. Does the baseline miss systematically for any archetype?", x=0.01, ha="left", fontweight="bold")
fig.tight_layout(); fig.savefig("plots/dc_C_residual_by_archetype.png", dpi=130); plt.close(fig)

# ---------- Robustness: (1) nonlinear model (gradient boosting), (2) WR role residual centred within test season,
#            excluding the partial 2026 target
from sklearn.ensemble import HistGradientBoostingRegressor
rob = []
for pos in POS:
    d = prep(pos); m = d[(d.games_next >= 4) & d.ppg_next.notna()].copy()
    R = dummies(m, "role_layer", "role"); S = dummies(m, "style_layer", "style")
    sets = {"Baseline": m[BASE], "+ role + style": pd.concat([m[BASE], R, S], axis=1), "+ raw usage inputs": pd.concat([m[BASE], m[USAGE[pos]]], axis=1)}
    out = {}
    for k, X in sets.items():
        p = np.full(len(m), np.nan)
        for t in range(2020, 2026):
            tr = (m.season < t).values; te = (m.season == t).values
            p[te] = HistGradientBoostingRegressor(max_depth=3, learning_rate=0.05, max_iter=300, min_samples_leaf=20, random_state=1).fit(X[tr], m.ppg_next[tr]).predict(X[te])
        ev = ~np.isnan(p); out[k] = np.sqrt(((p[ev] - m.ppg_next.values[ev]) ** 2).mean())
    for k in sets: rob.append(dict(position=pos, model="gradient boosting: " + k, rmse=round(out[k], 3), d_rmse_vs_base=round(out[k] - out["Baseline"], 3)))
rob = pd.DataFrame(rob); rob.to_csv("tables/dc_robust_gradient_boosting.csv", index=False); print(rob.to_string())
c2 = []
for pos in POS:
    d = prep(pos); m = d[(d.games_next >= 4) & d.ppg_next.notna()].copy()
    p = np.full(len(m), np.nan)
    for t in range(2020, 2025):
        tr = (m.season < t).values; te = (m.season == t).values
        p[te] = make_pipeline(StandardScaler(), RidgeCV(alphas=np.logspace(-2, 3, 20))).fit(m[BASE][tr], m.ppg_next[tr]).predict(m[BASE][te])
    ev = ~np.isnan(p); mm = m[ev].assign(resid=m.ppg_next.values[ev] - p[ev])
    mm["resid_c"] = mm.resid - mm.groupby("season").resid.transform("mean")
    for layer in ["role_layer", "style_layer"]:
        F, pv = stats.f_oneway(*[g.resid_c.values for _, g in mm.groupby(layer)])
        for lab, g in mm.groupby(layer):
            c2.append(dict(position=pos, layer=layer.replace("_layer", ""), label=lab, n=len(g), mean_resid_centred=round(g.resid_c.mean(), 3),
                           ci95=round(1.96 * g.resid_c.std(ddof=1) / np.sqrt(len(g)), 3), anova_p=round(pv, 4)))
c2 = pd.DataFrame(c2); c2.to_csv("tables/dc_C2_residual_centred_2020_2024.csv", index=False); print(c2.to_string())
