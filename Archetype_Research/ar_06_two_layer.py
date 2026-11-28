"""Archetype research, step 6: two-layer alternative (ROLE x STYLE). Counts and next-season persistence per layer.
Output: tables/two_layer_counts_{POS}.csv, tables/two_layer_persistence.csv, plots/two_layer_persistence.png"""
import numpy as np, pandas as pd, matplotlib
matplotlib.use("Agg"); import matplotlib.pyplot as plt
rows = []
for pos in ["QB", "RB", "WR", "TE"]:
    h = pd.read_csv(f"ar_labels_{pos}.csv"); h = h[h.season < 2026]
    pd.crosstab(h.role_layer, h.style_layer, margins=True).to_csv(f"tables/two_layer_counts_{pos}.csv")
    for layer in ["archetype", "role_layer", "style_layer"]:
        z = h[["player_id", "season", layer]]
        nx = z.merge(z.assign(season=z.season - 1), on=["player_id", "season"], suffixes=("", "_n"))
        same = (nx[layer] == nx[layer + "_n"]).mean(); chance = (h[layer].value_counts(normalize=True) ** 2).sum()
        rows.append(dict(position=pos, layer={"archetype": "single label", "role_layer": "role layer", "style_layer": "style layer"}[layer],
                         n_groups=h[layer].nunique(), same_next_season=round(same, 3), chance=round(chance, 3), lift=round(same / chance, 2),
                         kappa=round((same - chance) / (1 - chance), 3)))
r = pd.DataFrame(rows); r.to_csv("tables/two_layer_persistence.csv", index=False); print(r.to_string())
fig, axs = plt.subplots(1, 4, figsize=(14, 3.4), sharey=True)
for ax, pos in zip(axs, ["QB", "RB", "WR", "TE"]):
    q = r[r.position == pos]
    ax.bar(np.arange(3), q.kappa, color=["#257de0", "#f47230", "#00b894"], width=0.6)
    for i, v in enumerate(q.kappa): ax.text(i, v + 0.01, f"{v:.2f}", ha="center", fontsize=8.5)
    ax.set_xticks(range(3)); ax.set_xticklabels(["single\nlabel", "role\nlayer", "style\nlayer"], fontsize=8.5); ax.set_title(pos, loc="left", fontweight="bold")
axs[0].set_ylabel("year-to-year stability\n(kappa: 0 = chance, 1 = always same)"); axs[0].set_ylim(0, 0.8)
fig.suptitle("Which labels are a stable trait? Same player, next season", x=0.01, ha="left", fontweight="bold", fontsize=10)
fig.tight_layout(); fig.savefig("plots/two_layer_persistence.png", dpi=130); plt.close(fig)
