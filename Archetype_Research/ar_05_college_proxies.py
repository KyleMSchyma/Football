"""Archetype research, step 5: can the NFL archetype be read from college stats? (label check, not a value test)
For drafted players with a qualifying NFL season in years 1-3, take their most common NFL archetype and compare it with
final-college-season proxies from the repo's college tables (cfbfastR / CollegeFootballData). Reports AUC of each proxy
for separating one archetype from the rest of the position. Output: tables/college_proxy_auc.csv, plots/college_proxies.png"""
import numpy as np, pandas as pd, pyreadr, matplotlib
matplotlib.use("Agg"); import matplotlib.pyplot as plt
from sklearn.metrics import roc_auc_score
PAL = ["#257de0", "#f47230"]
REPO = ".."
col = {p: list(pyreadr.read_r(f"{REPO}/{m}/{p.lower()}_college_seasons.rds").values())[0] for p, m in
       [("QB", "QB_Model"), ("RB", "RB_Model"), ("WR", "WR_Model"), ("TE", "TE_Model")]}
TESTS = [  # (pos, nfl archetype(s) treated as positive, college proxy, plain name)
 ("QB", ["Dual-threat", "Hybrid"], "rush_yds", "final-season rushing yards"),
 ("QB", ["Dual-threat", "Hybrid"], "rush_yds_share", "share of team rushing yards"),
 ("QB", ["Gunslinger"], "ypa", "yards per attempt"),
 ("QB", ["Game manager"], "ypa", "yards per attempt (low = manager?)"),
 ("RB", ["Receiving back"], "rec_yds_share", "share of team receiving yards"),
 ("RB", ["Receiving back"], "rec", "receptions"),
 ("RB", ["Workhorse"], "car_share", "share of team carries"),
 ("RB", ["Power / goal-line"], "weight", "NFL listed weight"),
 ("RB", ["Explosive"], "ypc", "yards per carry"),
 ("WR", ["Deep threat"], "ypr", "yards per reception"),
 ("WR", ["Slot / possession", "YAC / gadget"], "ypr", "yards per reception (low = slot?)"),
 ("WR", ["X / alpha"], "dominator", "dominator (yards+TD share)"),
 ("WR", ["Big-bodied red zone"], "td_share", "share of team receiving TDs"),
 ("WR", ["YAC / gadget"], "rush_car", "carries"),
 ("TE", ["Receiving / move", "Hybrid"], "rec_yds_share", "share of team receiving yards"),
 ("TE", ["Inline / blocking"], "weight", "NFL listed weight"),
 ("TE", ["Red-zone specialist"], "rec_td_share", "share of team receiving TDs"),
]
rows, plotd = [], []
for pos in ["QB", "RB", "WR", "TE"]:
    lab = pd.read_csv(f"ar_labels_{pos}.csv")
    lab = lab[(lab.season < 2026) & (lab.season - lab.draft_year).between(0, 2)]
    mode = lab.groupby("player_id").agg(nfl_arch=("archetype", lambda s: s.value_counts().index[0]), weight=("weight", "first"), name=("display_name", "first"))
    c = col[pos].sort_values("college_year").groupby("gsis_id").tail(1).set_index("gsis_id")
    if pos == "WR": c["ypr"] = c.rec_yds / c.rec.replace(0, np.nan)
    m = mode.join(c, how="inner", rsuffix="_c")
    for p, pos_lab, x, nm in [t for t in TESTS if t[0] == pos]:
        dd = m[[x, "nfl_arch"]].dropna(); y = dd.nfl_arch.isin(pos_lab)
        if y.sum() < 5: continue
        auc = roc_auc_score(y, dd[x])
        rows.append(dict(position=pos, nfl_archetype=" or ".join(pos_lab), college_proxy=x, plain=nm, n=len(dd), n_positive=int(y.sum()),
                         auc=round(auc, 3), median_positive=round(dd[x][y].median(), 3), median_rest=round(dd[x][~y].median(), 3)))
        plotd.append((pos, " or ".join(pos_lab), nm, dd[x][y].values, dd[x][~y].values, auc))
r = pd.DataFrame(rows); r.to_csv("tables/college_proxy_auc.csv", index=False); print(r.to_string())
n = len(plotd); cols = 4; rws = int(np.ceil(n / cols))
fig, axs = plt.subplots(rws, cols, figsize=(15, 3.1 * rws))
for ax, (pos, a, nm, pv, rv, auc) in zip(axs.flat, plotd):
    bp = ax.boxplot([rv, pv], vert=False, widths=0.55, patch_artist=True, showfliers=False)
    for patch, cc in zip(bp["boxes"], ["#bbbbbb", PAL[0]]): patch.set_facecolor(cc); patch.set_edgecolor("#666666")
    for med in bp["medians"]: med.set_color("#191919")
    ax.set_yticks([1, 2]); ax.set_yticklabels([f"rest of {pos} ({len(rv)})", f"{a[:22]} ({len(pv)})"], fontsize=7.5)
    ax.set_title(f"{pos}: {nm}\nAUC {auc:.2f}", loc="left", fontsize=8.5, fontweight="bold")
for ax in list(axs.flat)[n:]: ax.axis("off")
fig.suptitle("Final college season vs NFL archetype in years 1-3 (AUC 0.5 = no signal, 0.7 = useful, 0.8+ = strong)", x=0.01, ha="left", fontsize=10, fontweight="bold")
fig.tight_layout(); fig.savefig("plots/college_proxies.png", dpi=120); plt.close(fig)
