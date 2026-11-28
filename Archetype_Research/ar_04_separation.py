"""Archetype research, step 4: are the rule labels well separated in the data?
For each position (2016-2025 qualifying seasons): standardise the defining features, then
 (a) silhouette of the rule labels, (b) k-means k=2..8 silhouette, (c) k-means with k = #labels vs rules (ARI + crosstab),
 (d) shallow decision tree that re-learns the rule labels (are they simple?), (e) year-to-year label persistence,
 (f) charts: PCA scatter, feature profiles, persistence. Output: tables/*.csv, plots/*.png, ar_separation_summary.csv"""
import os, numpy as np, pandas as pd, matplotlib
matplotlib.use("Agg"); import matplotlib.pyplot as plt
from sklearn.preprocessing import StandardScaler
from sklearn.decomposition import PCA
from sklearn.cluster import KMeans
from sklearn.mixture import GaussianMixture
from sklearn.metrics import silhouette_score, adjusted_rand_score
from sklearn.tree import DecisionTreeClassifier, export_text
from sklearn.model_selection import cross_val_score
os.makedirs("plots", exist_ok=True); os.makedirs("tables", exist_ok=True)
PAL = ["#257de0", "#f47230", "#00b894", "#f2a600", "#ee7fac", "#008a17", "#6a4ce2"]
plt.rcParams.update({"font.size": 10, "axes.spines.top": False, "axes.spines.right": False, "axes.edgecolor": "#999999",
                     "axes.labelcolor": "#191919", "xtick.color": "#666666", "ytick.color": "#666666", "axes.grid": True,
                     "grid.color": "#e6e6e6", "grid.linewidth": 0.6})
FEATS = {
 "QB": ["rush_ypg", "designed_runs_pg", "scramble_rate", "adot_pass", "deep_rate", "int_rate", "aggressiveness", "avg_time_to_throw", "sack_rate", "epa_db"],
 "RB": ["touches_pg", "snap_share", "opp_share", "targets_pg", "tgt_mix", "gl_share", "explosive_rate", "ypc", "stuff_rate", "weight"],
 "WR": ["target_share", "air_share", "adot", "deep_rate", "behind_rate", "yac_per_rec", "rz_mix", "catch_rate", "carries_pg", "height", "weight"],
 "TE": ["snap_share", "targets_per_snap", "target_share", "run_tilt", "rz_mix", "td_per_tgt", "adot", "yac_per_rec", "weight"],
}
ORDER = {
 "QB": ["Dual-threat", "Hybrid", "Pocket passer", "Gunslinger", "Game manager"],
 "RB": ["Workhorse", "Receiving back", "Power / goal-line", "Explosive", "Committee", "Lead back (balanced)"],
 "WR": ["X / alpha", "Deep threat", "YAC / gadget", "Big-bodied red zone", "Slot / possession", "Outside #2 (intermediate)"],
 "TE": ["Hybrid", "Receiving / move", "Red-zone specialist", "Inline / blocking", "Rotational (no clear role)"],
}
summary = []
for pos, feats in FEATS.items():
    d = pd.read_csv(f"ar_labels_{pos}.csv")
    h = d[d.season < 2026].copy()
    X = h[feats].astype(float); X = X.fillna(X.median())
    Z = StandardScaler().fit_transform(X)
    lab = np.asarray(h.archetype.astype(str).tolist()); labs = ORDER[pos]; k = len(labs)
    sil_rules = silhouette_score(Z, lab)
    ks = range(2, 9)
    sil_k = [silhouette_score(Z, KMeans(kk, n_init=20, random_state=1).fit_predict(Z)) for kk in ks]
    bic = [GaussianMixture(kk, covariance_type="diag", n_init=3, random_state=1).fit(Z).bic(Z) for kk in ks]
    km = KMeans(k, n_init=20, random_state=1).fit(Z); cl = km.labels_
    ari = adjusted_rand_score(lab, cl)
    # name each cluster by its majority rule label
    ct = pd.crosstab(pd.Series(lab, name="rule label"), pd.Series(cl, name="k-means cluster"))
    ct = ct.reindex(labs)
    ct.to_csv(f"tables/{pos}_rules_vs_kmeans.csv")
    centers = pd.DataFrame(km.cluster_centers_, columns=feats).round(2); centers["n"] = np.bincount(cl)
    centers["majority_rule_label"] = [ct[c].idxmax() for c in range(k)]
    centers.to_csv(f"tables/{pos}_kmeans_centers_z.csv", index_label="cluster")
    tree = DecisionTreeClassifier(max_depth=3, min_samples_leaf=10, random_state=1)
    acc_tree = cross_val_score(tree, X, lab, cv=5).mean()
    tree_km = DecisionTreeClassifier(max_depth=3, min_samples_leaf=10, random_state=1)
    acc_tree_km = cross_val_score(tree_km, X, cl, cv=5).mean()
    tree_km.fit(X, cl)
    with open(f"tables/{pos}_kmeans_tree_rules.txt", "w") as f:
        f.write(f"Depth-3 tree that describes the {k} k-means clusters in plain thresholds (5-fold accuracy {acc_tree_km:.2f})\n")
        f.write("Cluster -> majority rule label: " + "; ".join(f"{c}={centers.majority_rule_label[c]}" for c in range(k)) + "\n\n")
        f.write(export_text(tree_km, feature_names=feats, decimals=3))
    # persistence: same player, consecutive qualifying seasons
    pz = h.sort_values("season")[["player_id", "season", "archetype"]]
    nx = pz.merge(pz.assign(season=pz.season - 1), on=["player_id", "season"], suffixes=("", "_next"))
    stay = (nx.archetype == nx.archetype_next).groupby(nx.archetype).mean()
    base = h.archetype.value_counts(normalize=True)
    pers = pd.DataFrame({"n_pairs": nx.groupby("archetype").size(), "same_next_year": stay, "chance_if_random": base}).reindex(labs).round(3)
    pers.to_csv(f"tables/{pos}_persistence.csv")
    overall_stay = (nx.archetype == nx.archetype_next).mean(); overall_chance = (base ** 2).sum()
    tr = pd.crosstab(nx.archetype, nx.archetype_next, normalize="index").reindex(index=labs, columns=labs).round(2)
    tr.to_csv(f"tables/{pos}_transition_next_season.csv")
    summary.append(dict(position=pos, n=len(h), n_labels=k, silhouette_rule_labels=round(sil_rules, 3),
                        best_k_silhouette=list(ks)[int(np.argmax(sil_k))], best_silhouette=round(max(sil_k), 3),
                        best_k_bic=list(ks)[int(np.argmin(bic))], ari_rules_vs_kmeans=round(ari, 3),
                        tree_depth3_recovers_rules=round(acc_tree, 3), tree_depth3_recovers_kmeans=round(acc_tree_km, 3),
                        same_label_next_season=round(overall_stay, 3), chance_same=round(overall_chance, 3)))
    # ---- plots
    pca = PCA(2).fit(Z); P = pca.transform(Z)
    load = pd.DataFrame(pca.components_.T, index=feats, columns=["PC1", "PC2"])
    def axname(i):
        top = load.iloc[:, i].abs().sort_values(ascending=False).index[:2]
        return f"PC{i+1} ({pca.explained_variance_ratio_[i]:.0%} of variation): mostly " + " & ".join(f"{'+' if load.loc[t].iloc[i] > 0 else '-'}{t}" for t in top)
    fig, axs = plt.subplots(1, 2, figsize=(13, 5.6), sharex=True, sharey=True)
    for j, a in enumerate(labs):
        m = lab == a
        axs[0].scatter(P[m, 0], P[m, 1], s=14, color=PAL[j], alpha=0.75, label=f"{a} ({m.sum()})", edgecolor="white", linewidth=0.4)
    axs[0].set_title(f"{pos}: rule-based archetypes", loc="left", fontweight="bold")
    for c in range(k):
        m = cl == c
        axs[1].scatter(P[m, 0], P[m, 1], s=14, color=PAL[c], alpha=0.75, label=f"cluster {c}: mostly {centers.majority_rule_label[c]} ({m.sum()})", edgecolor="white", linewidth=0.4)
    axs[1].set_title(f"{pos}: k-means with k={k} (no labels given)", loc="left", fontweight="bold")
    for ax in axs:
        ax.set_xlabel(axname(0), fontsize=8.5); ax.legend(fontsize=7.5, frameon=False, loc="best")
    axs[0].set_ylabel(axname(1), fontsize=8.5)
    fig.text(0.01, 0.005, f"Each dot = one qualifying player-season, 2016-2025. Silhouette of rule labels {sil_rules:.2f}; agreement with k-means (ARI) {ari:.2f}. "
             "Silhouette near 0 = overlapping groups, >0.25 = some structure, >0.5 = clearly separate.", fontsize=8, color="#666666")
    fig.tight_layout(rect=(0, 0.03, 1, 1)); fig.savefig(f"plots/{pos}_pca_rules_vs_kmeans.png", dpi=130); plt.close(fig)
    # feature profiles (median by label, as within-position percentile so all features share one 0-100 axis)
    pct = X.rank(pct=True) * 100; pct["archetype"] = lab
    med = pct.groupby("archetype").median().reindex(labs)
    fig, ax = plt.subplots(figsize=(1.0 * len(feats) + 3, 0.55 * k + 1.6))
    im = ax.imshow(med.values, cmap="Blues", vmin=0, vmax=100, aspect="auto")
    ax.set_xticks(range(len(feats))); ax.set_xticklabels(feats, rotation=35, ha="right", fontsize=8.5)
    ax.set_yticks(range(k)); ax.set_yticklabels([f"{a} (n={int((lab == a).sum())})" for a in labs], fontsize=9)
    for i in range(k):
        for j in range(len(feats)):
            v = med.values[i, j]; ax.text(j, i, f"{v:.0f}", ha="center", va="center", fontsize=8, color="white" if v > 60 else "#191919")
    ax.grid(False); ax.set_title(f"{pos}: median percentile of each feature by archetype (50 = typical {pos})", loc="left", fontweight="bold", fontsize=10)
    fig.colorbar(im, ax=ax, fraction=0.025, pad=0.01); fig.tight_layout(); fig.savefig(f"plots/{pos}_feature_profile.png", dpi=130); plt.close(fig)
    # silhouette by k
    fig, ax = plt.subplots(figsize=(6, 3.4))
    ax.plot(list(ks), sil_k, color=PAL[0], lw=2, marker="o", ms=6)
    ax.axhline(sil_rules, color=PAL[1], lw=2, ls="--"); ax.text(8, sil_rules, " rule labels", color="#191919", va="bottom", ha="right", fontsize=8.5)
    ax.set_xlabel("number of k-means clusters"); ax.set_ylabel("silhouette (higher = cleaner)"); ax.set_ylim(0, max(0.35, max(sil_k) + 0.05))
    ax.set_title(f"{pos}: do natural clusters exist?", loc="left", fontweight="bold")
    fig.tight_layout(); fig.savefig(f"plots/{pos}_silhouette_by_k.png", dpi=130); plt.close(fig)
    # persistence
    fig, ax = plt.subplots(figsize=(7, 0.45 * k + 1.4))
    y = np.arange(k)
    ax.barh(y + 0.2, pers.same_next_year, height=0.38, color=PAL[0], label="same label next season")
    ax.barh(y - 0.2, pers.chance_if_random, height=0.38, color="#bbbbbb", label="chance if labels were random")
    ax.set_yticks(y); ax.set_yticklabels([f"{a} ({int(n)} pairs)" for a, n in zip(labs, pers.n_pairs.fillna(0))]); ax.invert_yaxis()
    ax.set_xlim(0, 1); ax.set_xlabel("share of player-seasons"); ax.legend(frameon=False, fontsize=8, loc="lower right")
    ax.set_title(f"{pos}: does a player keep his archetype the next year?", loc="left", fontweight="bold")
    fig.tight_layout(); fig.savefig(f"plots/{pos}_persistence.png", dpi=130); plt.close(fig)
s = pd.DataFrame(summary); s.to_csv("ar_separation_summary.csv", index=False); print(s.T.to_string())

# ---------- extra 1: what is the k=2 split (the "best" natural split)?
for pos, feats in FEATS.items():
    h = pd.read_csv(f"ar_labels_{pos}.csv"); h = h[h.season < 2026]
    X = h[feats].astype(float); X = X.fillna(X.median()); Z = StandardScaler().fit_transform(X)
    km = KMeans(2, n_init=20, random_state=1).fit(Z)
    c = pd.DataFrame(km.cluster_centers_, columns=feats).round(2).T; c.columns = [f"cluster{i} (n={n})" for i, n in enumerate(np.bincount(km.labels_))]
    c.to_csv(f"tables/{pos}_k2_centers_z.csv"); print(pos, "k=2 split (z-scores)\n", c.to_string())
# ---------- extra 2: style-only features (volume removed) -- do style groups separate better on their own?
STYLE = {"QB": ["rush_ypg", "scramble_rate", "adot_pass", "deep_rate", "int_rate", "aggressiveness", "avg_time_to_throw"],
         "RB": ["tgt_mix", "gl_share", "explosive_rate", "ypc", "stuff_rate", "weight"],
         "WR": ["adot", "deep_rate", "behind_rate", "yac_per_rec", "rz_mix", "catch_rate", "height", "weight"],
         "TE": ["targets_per_snap", "run_tilt", "rz_mix", "adot", "yac_per_rec", "weight"]}
rows = []
for pos, feats in STYLE.items():
    h = pd.read_csv(f"ar_labels_{pos}.csv"); h = h[h.season < 2026]
    X = h[feats].astype(float); X = X.fillna(X.median()); Z = StandardScaler().fit_transform(X)
    for kk in range(2, 7):
        rows.append(dict(position=pos, k=kk, silhouette=round(silhouette_score(Z, KMeans(kk, n_init=20, random_state=1).fit_predict(Z)), 3)))
st = pd.DataFrame(rows).pivot(index="position", columns="k", values="silhouette"); st.to_csv("tables/style_only_silhouette.csv"); print("style-only silhouettes\n", st)
# ---------- extra 3: plain two-axis maps (the charts to explain archetypes to non-technical readers)
MAPS = {"QB": ("adot_pass", "rush_ypg", "average throw depth (air yards per attempt)", "rushing yards per game"),
        "RB": ("touches_pg", "tgt_mix", "touches per game", "share of his opportunities that are targets"),
        "WR": ("adot", "target_share", "average depth of target (yards)", "share of team targets"),
        "TE": ("snap_share", "targets_per_snap", "share of offensive snaps played", "targets per snap")}
for pos, (xv, yv, xl, yl) in MAPS.items():
    d = pd.read_csv(f"ar_labels_{pos}.csv"); h = d[d.season < 2026]; labs = ORDER[pos]
    fig, ax = plt.subplots(figsize=(8.5, 6))
    for j, a in enumerate(labs):
        m = h.archetype == a
        ax.scatter(h.loc[m, xv], h.loc[m, yv], s=14, color=PAL[j], alpha=0.7, edgecolor="white", linewidth=0.4, label=f"{a} ({m.sum()})")
    cur = d[d.season == 2026].sort_values("fantasy_points_ppr", ascending=False).groupby("archetype").head(2)
    for _, r in cur.iterrows():
        ax.scatter(r[xv], r[yv], s=60, facecolor="none", edgecolor="#191919", linewidth=1.2)
        ax.annotate(f"{r.display_name} '26", (r[xv], r[yv]), xytext=(5, 4), textcoords="offset points", fontsize=7.5, color="#191919")
    ax.set_xlabel(xl); ax.set_ylabel(yl); ax.legend(frameon=False, fontsize=8, loc="best")
    ax.set_title(f"{pos} archetypes on two plain axes (2016-2025 seasons; circled = 2026 examples)", loc="left", fontweight="bold", fontsize=10)
    fig.tight_layout(); fig.savefig(f"plots/{pos}_two_axis_map.png", dpi=130); plt.close(fig)
