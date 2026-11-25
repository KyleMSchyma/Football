"""
Same tests as gt_01_tier_tests.py, for the B band (B+/B/B-) and the C band (C+/C/C-). (Kyle 2026-11-25, research only.)
Data, outcomes and tests as in gt_01 (drafted QB/RB/WR/TE 2010-2023, LOCO grades; pre / post / mixed systems).
Adjacent comparisons include the band edges (A- vs B+, B- vs C+, C- vs D). Alternative cut points for each band are
scored by leave-one-class-out Brier of grade x position hit rates, with the rest of the scale held fixed, and
class-bootstrap CIs on the gap to the current scale.
Writes gt_bc_*.csv and plot_bc_*.png into this folder.
"""
import numpy as np, pandas as pd, matplotlib, os
matplotlib.use("Agg"); import matplotlib.pyplot as plt
from scipy import stats
from statsmodels.stats.contingency_tables import StratifiedTable
from statsmodels.stats.proportion import proportion_confint
from statsmodels.stats.power import NormalIndPower
import statsmodels.formula.api as smf
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
rng = np.random.default_rng(2026)

d = pd.read_csv(f"{ROOT}/PostDraft_Model/pd_post_player_grades.csv")
d = d[(d["class"] <= 2023) & d.outcome_complete].copy()
pp = pd.read_csv(f"{ROOT}/PostDraft_Model/pd_post_proj_ppg.csv")[["position", "class", "pick", "name", "actual_ppg3"]]
d = d.merge(pp, on=["position", "class", "pick", "name"], how="left")
d["ppg"] = d.actual_ppg3.fillna(0.0)
d["ppg_z"] = d.groupby("position").ppg.transform(lambda s: (s - s.mean()) / s.std())
d["hit_top"] = (d.nfl_tier == 1).astype(int); d["hit_top2"] = (d.nfl_tier <= 2).astype(int); d["hit_any"] = (d.nfl_tier <= 3).astype(int)
SYS = {"pre": ("pre_grade", "pre_pctile"), "post": ("post_grade_draft", "post_pctile_draft"), "mixed": ("post_grade", "post_pctile")}
SYSN = {"pre": "Pre-draft", "post": "Post-draft", "mixed": "Adjusted (mixed)"}
OUTS = ["hit_top", "hit_top2", "hit_any"]; POS = ["QB", "RB", "WR", "TE"]
SCALE = [(.95, "A+"), (.90, "A"), (.85, "A-"), (.75, "B+"), (.65, "B"), (.55, "B-"), (.45, "C+"), (.35, "C"), (.25, "C-"), (.10, "D"), (0, "F")]
TIERS = ["A-", "B+", "B", "B-", "C+", "C", "C-", "D", "F"]
PAIRS = [("A-", "B+"), ("B+", "B"), ("B", "B-"), ("B+", "B-"), ("B-", "C+"), ("C+", "C"), ("C", "C-"), ("C+", "C-"), ("C-", "D"), ("D", "F")]
print("players:", len(d))

def wilson(k, n): return proportion_confint(k, n, method="wilson")

# 1. outcomes by grade (pooled + by position)
rows = []
for s, (g, pc) in SYS.items():
    for pos in ["All"] + POS:
        x = d if pos == "All" else d[d.position == pos]
        for t in TIERS:
            y = x[x[g] == t]; n = len(y)
            r = dict(system=s, position=pos, grade=t, n=n, mean_pick=round(y.pick.mean(), 1), median_round=y["round"].median())
            for o in OUTS:
                lo, hi = wilson(y[o].sum(), n); r[o] = round(y[o].mean(), 3); r[o + "_lo"] = round(lo, 3); r[o + "_hi"] = round(hi, 3)
            se = y.ppg.std() / np.sqrt(n); r["ppg"] = round(y.ppg.mean(), 2)
            r["ppg_lo"] = round(r["ppg"] - 1.96 * se, 2); r["ppg_hi"] = round(r["ppg"] + 1.96 * se, 2); r["ppg_z"] = round(y.ppg_z.mean(), 2)
            rows.append(r)
tab = pd.DataFrame(rows); tab.to_csv(f"{HERE}/gt_bc_tier_outcomes.csv", index=False)

# 2. adjacent tests
def perm_ppg(a, b, n=5000):
    obs = a.ppg_z.mean() - b.ppg_z.mean(); both = pd.concat([a.assign(_g=1), b.assign(_g=0)])
    grs = [(grp.ppg_z.values, grp._g.values) for _, grp in both.groupby("position")]; diffs = np.empty(n)
    for i in range(n):
        sa = sb = 0.0
        for v, l in grs:
            pl = rng.permutation(l); sa += v[pl == 1].sum(); sb += v[pl == 0].sum()
        diffs[i] = sa / len(a) - sb / len(b)
    return obs, (np.abs(diffs) >= abs(obs) - 1e-12).mean()

trows = []
for s, (g, pc) in SYS.items():
    for hi_t, lo_t in PAIRS:
        a = d[d[g] == hi_t]; b = d[d[g] == lo_t]
        r = dict(system=s, compare=f"{hi_t} vs {lo_t}", n_hi=len(a), n_lo=len(b))
        for o in OUTS:
            tb = [np.array([[a[a.position == p][o].sum(), (a.position == p).sum() - a[a.position == p][o].sum()],
                            [b[b.position == p][o].sum(), (b.position == p).sum() - b[b.position == p][o].sum()]]) for p in POS
                  if (a.position == p).any() and (b.position == p).any()]
            r[o + "_hi"] = round(a[o].mean(), 3); r[o + "_lo"] = round(b[o].mean(), 3); r[o + "_diff"] = round(a[o].mean() - b[o].mean(), 3)
            try:
                st = StratifiedTable(tb); r[o + "_OR_mh"] = round(st.oddsratio_pooled, 2); r[o + "_p_cmh"] = round(st.test_null_odds(correction=True).pvalue, 3)
            except Exception:
                r[o + "_OR_mh"] = np.nan; r[o + "_p_cmh"] = np.nan
        obs, p = perm_ppg(a, b)
        r["ppg_hi"] = round(a.ppg.mean(), 2); r["ppg_lo"] = round(b.ppg.mean(), 2); r["ppg_z_diff"] = round(obs, 2); r["ppg_p_perm"] = round(p, 3)
        p0 = b.hit_any.mean()
        if 0 < p0 < 1:
            h = NormalIndPower().solve_power(nobs1=len(a), ratio=len(b) / len(a), alpha=.05, power=.8)
            r["hit_any_min_detectable_gap"] = round(np.sin((2 * np.arcsin(np.sqrt(p0)) + h) / 2) ** 2 - p0, 3)
        trows.append(r)
tests = pd.DataFrame(trows); tests.to_csv(f"{HERE}/gt_bc_adjacent_tests.csv", index=False)

prow = []
for s, (g, pc) in SYS.items():
    for pos in POS:
        x = d[d.position == pos]
        for hi_t, lo_t in [("B+", "B"), ("B", "B-"), ("C+", "C"), ("C", "C-")]:
            a, b = x[x[g] == hi_t], x[x[g] == lo_t]
            r = dict(system=s, position=pos, compare=f"{hi_t} vs {lo_t}", n_hi=len(a), n_lo=len(b))
            for o in ["hit_top", "hit_any"]:
                ka, kb = a[o].sum(), b[o].sum(); r[o + "_hi"] = f"{ka}/{len(a)}"; r[o + "_lo"] = f"{kb}/{len(b)}"
                r[o + "_p_fisher"] = round(stats.fisher_exact([[ka, len(a) - ka], [kb, len(b) - kb]])[1], 3)
            r["ppg_hi"] = round(a.ppg.mean(), 1); r["ppg_lo"] = round(b.ppg.mean(), 1); r["ppg_p_mwu"] = round(stats.mannwhitneyu(a.ppg, b.ppg).pvalue, 3)
            prow.append(r)
pd.DataFrame(prow).to_csv(f"{HERE}/gt_bc_adjacent_tests_by_position.csv", index=False)

# 3. trend inside each band: does the percentile still matter?
trend = []
for s, (g, pc) in SYS.items():
    for lab, lo, hi in [("B band (55-85)", .55, .85), ("C band (25-55)", .25, .55), ("D/F (below 25)", 0, .25)]:
        x = d[(d[pc] >= lo) & (d[pc] < hi)].copy(); x["pct10"] = x[pc] * 10; r = dict(system=s, subset=lab, n=len(x))
        for o in ["hit_top", "hit_any"]:
            try:
                m = smf.logit(f"{o} ~ pct10 + C(position)", x).fit(disp=0)
                r[o + "_rate"] = round(x[o].mean(), 3); r[o + "_OR_per10pct"] = round(np.exp(m.params["pct10"]), 2); r[o + "_p"] = round(m.pvalues["pct10"], 4)
            except Exception:
                r[o + "_OR_per10pct"] = np.nan; r[o + "_p"] = np.nan
        m = smf.ols("ppg_z ~ pct10 + C(position)", x).fit(); r["ppg_z_per10pct"] = round(m.params["pct10"], 2); r["ppg_p"] = round(m.pvalues["pct10"], 4)
        trend.append(r)
trend = pd.DataFrame(trend); trend.to_csv(f"{HERE}/gt_bc_trend_within_band.csv", index=False)

# 4. alternative splits (rest of the scale fixed)
def labels(p, scale):
    out = np.empty(len(p), dtype=object)
    for c, nme in sorted(scale):
        out[p >= c] = nme
    return out
def replace_band(lo, hi, new):  # keep cuts outside [lo, hi), insert new cuts
    return [(c, n) for c, n in SCALE if not (lo <= c < hi)] + new
ALT = {
    "current scale": SCALE,
    "B: one band (55-85)": replace_band(.55, .85, [(.55, "B")]),
    "B: two bands B+ 75 / B 55": replace_band(.55, .85, [(.75, "B+"), (.55, "B")]),
    "B: two bands B+ 70 / B 55": replace_band(.55, .85, [(.70, "B+"), (.55, "B")]),
    "C: one band (25-55)": replace_band(.25, .55, [(.25, "C")]),
    "C: two bands C+ 40 / C 25": replace_band(.25, .55, [(.40, "C+"), (.25, "C")]),
    "C+D: C-/D merged (10-35)": replace_band(.10, .35, [(.10, "C-")]),
    "C and below: one band (<55)": replace_band(0, .55, [(0, "C")]),
    "B and C one band each": replace_band(.25, .85, [(.55, "B"), (.25, "C")]),
    "B+/B merged (65-85), B- kept": replace_band(.65, .85, [(.65, "B")]),
    "data-led: B 65-85 / C 25-65 (B- joins C)": replace_band(.25, .85, [(.65, "B"), (.25, "C")]),
}
def loco_err(lab, o):
    pred = np.empty(len(d)); y = d[o].values; cls = d["class"].values; pos = d.position.values
    for c in np.unique(cls):
        tr = cls != c
        for i in np.where(~tr)[0]:
            m = tr & (lab == lab[i]) & (pos == pos[i]); pred[i] = (y[m].sum() + 1) / (m.sum() + 2)
    return (pred - y) ** 2
alt = []
for s, (g, pc) in SYS.items():
    p = d[pc].values
    for o in ["hit_top2", "hit_any"]:
        e0 = loco_err(labels(p, SCALE), o)
        for nm, sc in ALT.items():
            e = loco_err(labels(p, sc), o); gap = pd.Series(e - e0).groupby(d["class"].values).agg(["sum", "count"])
            draws = []
            for _ in range(3000):
                k = rng.choice(len(gap), len(gap)); draws.append(gap["sum"].values[k].sum() / gap["count"].values[k].sum())
            alt.append(dict(system=s, outcome=o, split=nm, brier=round(e.mean(), 5), gap_vs_current=round(e.mean() - e0.mean(), 5),
                            gap_lo=round(np.percentile(draws, 2.5), 5), gap_hi=round(np.percentile(draws, 97.5), 5)))
alt = pd.DataFrame(alt); alt.to_csv(f"{HERE}/gt_bc_alternative_splits.csv", index=False)

# charts
COL = {"A-": "#a5d6a7", "B+": "#1565c0", "B": "#42a5f5", "B-": "#90caf9", "C+": "#ef6c00", "C": "#ffa726", "C-": "#ffcc80", "D": "#bdbdbd", "F": "#757575"}
fig, axes = plt.subplots(3, 4, figsize=(18, 11))
for i, s in enumerate(SYS):
    t = tab[(tab.system == s) & (tab.position == "All")].set_index("grade").loc[TIERS]
    for j, (o, lab) in enumerate([("hit_top", "Top-tier hit (QB8/RB8/WR12/TE6)"), ("hit_top2", "Top-2 tiers (QB16/RB16/WR24/TE12)"),
                                  ("hit_any", "Any tier (QB24/RB24/WR36/TE18)"), ("ppg", "PPR PPG, NFL yrs 1-3")]):
        ax = axes[i, j]; v = t[o].values; lo = t[o + "_lo"].values; hi = t[o + "_hi"].values
        ax.bar(TIERS, v, color=[COL[k] for k in TIERS]); ax.errorbar(TIERS, v, yerr=[v - lo, hi - v], fmt="none", ecolor="k", capsize=3, lw=.8)
        for k, vv in enumerate(v):
            ax.text(k, hi[k] + (0.015 if o != "ppg" else 0.25), f"{vv:.0%}" if o != "ppg" else f"{vv:.1f}", ha="center", fontsize=8)
        ax.set_ylim(0, (0.75 if o != "ppg" else max(hi) * 1.18)); ax.tick_params(axis="x", labelsize=9)
        if i == 0: ax.set_title(lab, fontsize=10)
        if j == 0: ax.set_ylabel(SYSN[s])
        if j == 3: ax.set_xticks(range(len(TIERS))); ax.set_xticklabels([f"{g}\n{n}" for g, n in zip(TIERS, t.n)], fontsize=8)
fig.suptitle("Real outcomes by grade, B and C bands (drafted rookies 2010-2023, positions pooled, 95% CIs; n under PPG bars)", fontsize=12)
fig.tight_layout(); fig.savefig(f"{HERE}/plot_bc_tier_outcomes.png", dpi=130); plt.close(fig)

BT = ["B+", "B", "B-", "C+", "C", "C-"]
fig, axes = plt.subplots(3, 4, figsize=(17, 10))
for i, s in enumerate(SYS):
    for j, pos in enumerate(POS):
        ax = axes[i, j]; t = tab[(tab.system == s) & (tab.position == pos)].set_index("grade").loc[BT]; xs = np.arange(len(BT)); w = .38
        for k, (o, col) in enumerate([("hit_any", "#1565c0"), ("hit_top2", "#ef6c00")]):
            v = t[o].values; ax.bar(xs + (k - .5) * w, v, w, color=col, alpha=.85, label={"hit_any": "Any tier", "hit_top2": "Top-2 tiers"}[o])
            ax.errorbar(xs + (k - .5) * w, v, yerr=[v - t[o + "_lo"].values, t[o + "_hi"].values - v], fmt="none", ecolor="k", capsize=2, lw=.7)
        ax.set_xticks(xs); ax.set_xticklabels([f"{g}\nn={n}" for g, n in zip(BT, t.n)], fontsize=8); ax.set_ylim(0, 1)
        if i == 0: ax.set_title(pos)
        if j == 0: ax.set_ylabel(SYSN[s])
axes[0, 0].legend(fontsize=8); fig.suptitle("B and C band hit rates by position (95% CIs)", fontsize=12); fig.tight_layout()
fig.savefig(f"{HERE}/plot_bc_tier_by_position.png", dpi=130); plt.close(fig)

pd.set_option("display.width", 260); pd.set_option("display.max_columns", 50)
print(tab[tab.position == "All"][["system", "grade", "n", "mean_pick", "hit_top", "hit_top2", "hit_any", "hit_any_lo", "hit_any_hi", "ppg"]].to_string(index=False))
print(tests[["system", "compare", "n_hi", "n_lo", "hit_top_diff", "hit_top_p_cmh", "hit_top2_diff", "hit_top2_p_cmh", "hit_any_hi", "hit_any_lo", "hit_any_p_cmh", "ppg_hi", "ppg_lo", "ppg_p_perm", "hit_any_min_detectable_gap"]].to_string(index=False))
print(trend.to_string(index=False)); print(alt.to_string(index=False))
