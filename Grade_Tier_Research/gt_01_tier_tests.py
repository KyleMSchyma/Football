"""
Do A+, A and A- rookie grades separate real outcomes? (Kyle 2026-11-25, research only.)

Data: PostDraft_Model/pd_post_player_grades.csv, drafted QB/RB/WR/TE, classes 2010-2023 (outcomes complete,
grades out-of-class / LOCO, so no class grades itself). Three grade systems on the same players:
  pre   = pre-draft grade (pre_grade / pre_pctile)
  post  = pure post-draft grade (post_grade_draft / post_pctile_draft)
  mixed = mixed "Adjusted" grade shown on the site (post_grade / post_pctile)
Outcomes (NFL years 1-3): top tier (QB8/RB8/WR12/TE6), top-2 tiers (QB16/RB16/WR24/TE12), any tier
(QB24/RB24/WR36/TE18), and PPR points per game (PostDraft_Model/pd_post_proj_ppg.csv actual_ppg3; 0 if no games).
Tests: Wilson 95% CIs; adjacent tiers compared with Cochran-Mantel-Haenszel (stratified by position) for hit rates,
Fisher exact per position, and a within-position permutation test for PPG (z-scored within position).
Alternative splits scored by leave-one-class-out Brier score of tier hit rates.
Writes CSVs + PNGs into this folder.
"""
import numpy as np, pandas as pd, matplotlib
matplotlib.use("Agg"); import matplotlib.pyplot as plt
from scipy import stats
from statsmodels.stats.contingency_tables import StratifiedTable
from statsmodels.stats.proportion import proportion_confint
import statsmodels.formula.api as smf
import os
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
rng = np.random.default_rng(2026)

d = pd.read_csv(f"{ROOT}/PostDraft_Model/pd_post_player_grades.csv")
d = d[(d["class"] <= 2023) & d.outcome_complete].copy()
pp = pd.read_csv(f"{ROOT}/PostDraft_Model/pd_post_proj_ppg.csv")[["position", "class", "pick", "name", "actual_ppg3", "games_3yr"]]
d = d.merge(pp, on=["position", "class", "pick", "name"], how="left")
d["ppg"] = d.actual_ppg3.fillna(0.0)
d["ppg_z"] = d.groupby("position").ppg.transform(lambda s: (s - s.mean()) / s.std())
d["hit_top"] = (d.nfl_tier == 1).astype(int); d["hit_top2"] = (d.nfl_tier <= 2).astype(int); d["hit_any"] = (d.nfl_tier <= 3).astype(int)
SYS = {"pre": ("pre_grade", "pre_pctile", None), "post": ("post_grade_draft", "post_pctile_draft", "p_any_draft"),
       "mixed": ("post_grade", "post_pctile", "p_any")}
TIERS = ["A+", "A", "A-", "B+"]; OUTS = ["hit_top", "hit_top2", "hit_any"]; POS = ["QB", "RB", "WR", "TE"]
print("players:", len(d), d.position.value_counts().to_dict())

def wilson(k, n):
    lo, hi = proportion_confint(k, n, method="wilson"); return lo, hi

# ---------- 1. tier table (pooled + by position) ----------
rows = []
for s, (g, pc, _) in SYS.items():
    for pos in ["All"] + POS:
        x = d if pos == "All" else d[d.position == pos]
        for t in TIERS:
            y = x[x[g] == t]; n = len(y)
            r = dict(system=s, position=pos, grade=t, n=n, mean_pick=round(y.pick.mean(), 1))
            for o in OUTS:
                k = y[o].sum(); lo, hi = wilson(k, n); r[o] = round(k / n, 3); r[o + "_lo"] = round(lo, 3); r[o + "_hi"] = round(hi, 3)
            r["ppg"] = round(y.ppg.mean(), 2); se = y.ppg.std() / np.sqrt(n)
            r["ppg_lo"] = round(r["ppg"] - 1.96 * se, 2); r["ppg_hi"] = round(r["ppg"] + 1.96 * se, 2)
            r["ppg_z"] = round(y.ppg_z.mean(), 2)
            rows.append(r)
tab = pd.DataFrame(rows); tab.to_csv(f"{HERE}/gt_tier_outcomes.csv", index=False)

# ---------- 2. adjacent-tier tests ----------
def perm_ppg(a, b, n=20000):
    """within-position permutation test of mean ppg_z difference a - b"""
    obs = a.ppg_z.mean() - b.ppg_z.mean(); both = pd.concat([a.assign(_g=1), b.assign(_g=0)])
    groups = [grp for _, grp in both.groupby("position")]; cnt = 0
    vals = [grp.ppg_z.values for grp in groups]; labs = [grp._g.values for grp in groups]
    na = len(a); diffs = np.empty(n)
    for i in range(n):
        sa = sb = 0.0
        for v, l in zip(vals, labs):
            pl = rng.permutation(l); sa += v[pl == 1].sum(); sb += v[pl == 0].sum()
        diffs[i] = sa / na - sb / len(b)
    return obs, (np.abs(diffs) >= abs(obs) - 1e-12).mean()

trows = []
for s, (g, pc, _) in SYS.items():
    for hi_t, lo_t in [("A+", "A"), ("A", "A-"), ("A-", "B+"), ("A+", "A-")]:
        a = d[d[g] == hi_t]; b = d[d[g] == lo_t]
        r = dict(system=s, compare=f"{hi_t} vs {lo_t}", n_hi=len(a), n_lo=len(b))
        for o in OUTS:
            tbls = []
            for pos in POS:
                aa, bb = a[a.position == pos], b[b.position == pos]
                if len(aa) and len(bb):
                    tbls.append(np.array([[aa[o].sum(), len(aa) - aa[o].sum()], [bb[o].sum(), len(bb) - bb[o].sum()]]))
            st = StratifiedTable(tbls)
            r[o + "_diff"] = round(a[o].mean() - b[o].mean(), 3)
            r[o + "_OR_mh"] = round(st.oddsratio_pooled, 2); r[o + "_p_cmh"] = round(st.test_null_odds(correction=True).pvalue, 3)
        obs, p = perm_ppg(a, b, 5000)
        r["ppg_diff"] = round(a.ppg.mean() - b.ppg.mean(), 2); r["ppg_z_diff"] = round(obs, 2); r["ppg_p_perm"] = round(p, 3)
        trows.append(r)
tests = pd.DataFrame(trows); tests.to_csv(f"{HERE}/gt_adjacent_tests.csv", index=False)

prow = []
for s, (g, pc, _) in SYS.items():
    for pos in POS:
        x = d[d.position == pos]
        for hi_t, lo_t in [("A+", "A"), ("A", "A-")]:
            a, b = x[x[g] == hi_t], x[x[g] == lo_t]
            r = dict(system=s, position=pos, compare=f"{hi_t} vs {lo_t}", n_hi=len(a), n_lo=len(b))
            for o in ["hit_top", "hit_any"]:
                ka, kb = a[o].sum(), b[o].sum()
                r[o + "_hi"] = f"{ka}/{len(a)}"; r[o + "_lo"] = f"{kb}/{len(b)}"
                r[o + "_p_fisher"] = round(stats.fisher_exact([[ka, len(a) - ka], [kb, len(b) - kb]])[1], 3)
            r["ppg_hi"] = round(a.ppg.mean(), 1); r["ppg_lo"] = round(b.ppg.mean(), 1)
            r["ppg_p_mwu"] = round(stats.mannwhitneyu(a.ppg, b.ppg).pvalue, 3)
            prow.append(r)
pd.DataFrame(prow).to_csv(f"{HERE}/gt_adjacent_tests_by_position.csv", index=False)

# ---------- 3. trend inside the A range (top 15%): does percentile still matter? ----------
trend = []
for s, (g, pc, _) in SYS.items():
    for lab, cut in [("A range (top 15%)", 0.85), ("B+ and up (top 25%)", 0.75), ("all drafted", 0.0)]:
        x = d[d[pc] >= cut].copy(); x["pct10"] = x[pc] * 10   # per 10 percentile points
        r = dict(system=s, subset=lab, n=len(x))
        for o in ["hit_top", "hit_any"]:
            try:
                m = smf.logit(f"{o} ~ pct10 + C(position)", x).fit(disp=0)
                r[o + "_OR_per10pct"] = round(np.exp(m.params["pct10"]), 2); r[o + "_p"] = round(m.pvalues["pct10"], 4)
            except Exception as e:
                r[o + "_OR_per10pct"] = np.nan; r[o + "_p"] = np.nan
        m = smf.ols("ppg_z ~ pct10 + C(position)", x).fit()
        r["ppg_z_per10pct"] = round(m.params["pct10"], 2); r["ppg_p"] = round(m.pvalues["pct10"], 4)
        trend.append(r)
pd.DataFrame(trend).to_csv(f"{HERE}/gt_trend_within_A.csv", index=False)

# ---------- 4. power: smallest gap these sample sizes can detect ----------
def mde(n1, n2, p0, alpha=0.05, power=0.8):
    from statsmodels.stats.power import NormalIndPower
    h = NormalIndPower().solve_power(nobs1=n1, ratio=n2 / n1, alpha=alpha, power=power)
    # Cohen's h -> proportion above p0
    phi = 2 * np.arcsin(np.sqrt(p0)) + h; return np.sin(phi / 2) ** 2 - p0
pw = []
for s, (g, pc, _) in SYS.items():
    n = d[g].value_counts()
    for hi_t, lo_t in [("A+", "A"), ("A", "A-")]:
        for o in ["hit_top", "hit_any"]:
            p0 = d[d[g] == lo_t][o].mean()
            pw.append(dict(system=s, compare=f"{hi_t} vs {lo_t}", outcome=o, n_hi=n[hi_t], n_lo=n[lo_t], base_rate=round(p0, 3),
                           min_detectable_gap=round(mde(n[hi_t], n[lo_t], p0), 3)))
pd.DataFrame(pw).to_csv(f"{HERE}/gt_power.csv", index=False)

# ---------- 5. fine percentile curve ----------
BINS = [0, .25, .45, .65, .75, .85, .90, .95, 1.0001]
BL = ["<25", "25-45", "45-65", "65-75", "75-85 (B+)", "85-90 (A-)", "90-95 (A)", "95+ (A+)"]
fc = []
for s, (g, pc, _) in SYS.items():
    x = d.copy(); x["bin"] = pd.cut(x[pc], BINS, labels=BL, right=False)
    for b, y in x.groupby("bin", observed=True):
        r = dict(system=s, bin=b, n=len(y), ppg=round(y.ppg.mean(), 2), ppg_z=round(y.ppg_z.mean(), 2))
        for o in OUTS:
            lo, hi = wilson(y[o].sum(), len(y)); r[o] = round(y[o].mean(), 3); r[o + "_lo"] = round(lo, 3); r[o + "_hi"] = round(hi, 3)
        fc.append(r)
fc = pd.DataFrame(fc); fc.to_csv(f"{HERE}/gt_percentile_curve.csv", index=False)

# ---------- 6. alternative splits: leave-one-class-out Brier of tier hit rates ----------
def loco_brier(x, labels, o, per_player=False):
    """predict each player's hit with the hit rate of his tier+position in the OTHER classes (Laplace smoothed)"""
    pred = np.empty(len(x)); y = x[o].values; cls = x["class"].values; pos = x.position.values
    for c in np.unique(cls):
        tr = cls != c
        for i in np.where(~tr)[0]:
            m = tr & (labels == labels[i]) & (pos == pos[i]); pred[i] = (y[m].sum() + 1) / (m.sum() + 2)
    return (pred - y) ** 2 if per_player else np.mean((pred - y) ** 2)

def split_labels(p, cuts, names):
    out = np.array(["below"] * len(p), dtype=object)
    for c, nme in sorted(zip(cuts, names)):
        out[p >= c] = nme
    return out

ALT = {
    "current: A+ 95 / A 90 / A- 85": ([.95, .90, .85], ["A+", "A", "A-"]),
    "one A band (85+)": ([.85], ["A"]),
    "two bands: A+ 95 / A 85": ([.95, .85], ["A+", "A"]),
    "two bands: A+ 90 / A 85": ([.90, .85], ["A+", "A"]),
    "narrow top: A+ 97 / A 90 / A- 85": ([.97, .90, .85], ["A+", "A", "A-"]),
    "wider: A+ 92 / A 85 / A- 75": ([.92, .85, .75], ["A+", "A", "A-"]),
}
alt = []
for s, (g, pc, pa) in SYS.items():
    for o in ["hit_top", "hit_any"]:
        # baseline: B+ and below share one 'rest' bucket logic -> keep the full current scale below A- (B+, B, ...) fixed
        base_low = d[pc].values
        below = split_labels(base_low, [.75, .65, .55, .45, .35, .25, .10], ["B+", "B", "B-", "C+", "C", "C-", "D"])
        for nm, (cuts, names) in ALT.items():
            lab = split_labels(d[pc].values, cuts, names)
            lab = np.where(lab == "below", below, lab)
            # for 'wider' the A- band reaches into B+, so re-label consistently
            alt.append(dict(system=s, outcome=o, split=nm, brier=round(loco_brier(d, lab, o), 5)))
alt = pd.DataFrame(alt)
alt["brier_vs_current"] = alt.groupby(["system", "outcome"]).brier.transform(lambda b: (b - b.iloc[0]).round(5))
alt.to_csv(f"{HERE}/gt_alternative_splits.csv", index=False)

# class-bootstrap CI on the Brier gap (each alternative minus current); negative = alternative better
bs = []
for s, (g, pc, pa) in SYS.items():
    below = split_labels(d[pc].values, [.75, .65, .55, .45, .35, .25, .10], ["B+", "B", "B-", "C+", "C", "C-", "D"])
    lab_c = np.where((l := split_labels(d[pc].values, *ALT["current: A+ 95 / A 90 / A- 85"])) == "below", below, l)
    for o in ["hit_top", "hit_any"]:
        e_c = loco_brier(d, lab_c, o, True)
        for nm, (cuts, names) in list(ALT.items())[1:]:
            l2 = split_labels(d[pc].values, cuts, names); l2 = np.where(l2 == "below", below, l2)
            gap = pd.Series(loco_brier(d, l2, o, True) - e_c).groupby(d["class"].values).agg(["sum", "count"])
            cls = gap.index.values; draws = []
            for _ in range(4000):
                k = rng.choice(len(cls), len(cls)); draws.append(gap["sum"].values[k].sum() / gap["count"].values[k].sum())
            bs.append(dict(system=s, outcome=o, split=nm, gap=round(gap["sum"].sum() / gap["count"].sum(), 5),
                           lo=round(np.percentile(draws, 2.5), 5), hi=round(np.percentile(draws, 97.5), 5)))
bs = pd.DataFrame(bs); bs.to_csv(f"{HERE}/gt_alternative_splits_bootstrap.csv", index=False)

# ---------- charts ----------
C = {"A+": "#1b5e20", "A": "#43a047", "A-": "#a5d6a7", "B+": "#90a4ae"}
fig, axes = plt.subplots(3, 4, figsize=(16, 11))
for i, s in enumerate(SYS):
    for j, (o, lab) in enumerate([("hit_top", "Top-tier hit (QB8/RB8/WR12/TE6)"), ("hit_top2", "Top-2 tiers (QB16/RB16/WR24/TE12)"),
                                  ("hit_any", "Any tier (QB24/RB24/WR36/TE18)"), ("ppg", "PPR PPG, NFL yrs 1-3")]):
        ax = axes[i, j]; t = tab[(tab.system == s) & (tab.position == "All")].set_index("grade").loc[TIERS]
        v = t[o].values; lo = t[o + "_lo"].values; hi = t[o + "_hi"].values
        ax.bar(TIERS, v, color=[C[k] for k in TIERS]); ax.errorbar(TIERS, v, yerr=[v - lo, hi - v], fmt="none", ecolor="k", capsize=4)
        for k, (vv, nn) in enumerate(zip(v, t.n.values)):
            ax.text(k, 0.01 if o != "ppg" else 0.2, f"n={nn}", ha="center", color="white", fontsize=8)
            ax.text(k, hi[k] + (0.02 if o != "ppg" else 0.3), f"{vv:.0%}" if o != "ppg" else f"{vv:.1f}", ha="center", fontsize=9)
        ax.set_ylim(0, 1.1 if o != "ppg" else max(hi) * 1.2)
        if i == 0: ax.set_title(lab, fontsize=10)
        if j == 0: ax.set_ylabel({"pre": "Pre-draft grade", "post": "Post-draft grade", "mixed": "Adjusted (mixed) grade"}[s])
fig.suptitle("Real outcomes by grade, drafted rookies 2010-2023 (all positions pooled, 95% CIs)", fontsize=13)
fig.tight_layout(); fig.savefig(f"{HERE}/plot_tier_outcomes.png", dpi=130); plt.close(fig)

fig, axes = plt.subplots(1, 3, figsize=(16, 4.8), sharey=True)
for ax, s in zip(axes, SYS):
    t = fc[fc.system == s]; xs = np.arange(len(t))
    for o, col in [("hit_any", "#1565c0"), ("hit_top", "#c62828")]:
        ax.plot(xs, t[o], "o-", color=col, label={"hit_any": "Any tier", "hit_top": "Top tier"}[o])
        ax.fill_between(xs, t[o + "_lo"], t[o + "_hi"], color=col, alpha=.15)
    ax.set_xticks(xs); ax.set_xticklabels(t.bin, rotation=40, ha="right", fontsize=8)
    for xx, nn in zip(xs, t.n): ax.text(xx, -0.08, f"n={nn}", ha="center", fontsize=7)
    ax.axvspan(4.5, 7.5, color="#e8f5e9", zorder=0)
    ax.set_title({"pre": "Pre-draft", "post": "Post-draft", "mixed": "Adjusted (mixed)"}[s]); ax.set_ylim(-0.12, 1.05)
axes[0].set_ylabel("Hit rate (NFL yrs 1-3)"); axes[0].legend(loc="upper left")
fig.suptitle("Hit rate by grade percentile (shaded = A range)", fontsize=12); fig.tight_layout()
fig.savefig(f"{HERE}/plot_percentile_curve.png", dpi=130); plt.close(fig)

fig, axes = plt.subplots(3, 4, figsize=(16, 10))
for i, s in enumerate(SYS):
    for j, pos in enumerate(POS):
        ax = axes[i, j]; t = tab[(tab.system == s) & (tab.position == pos)].set_index("grade").loc[TIERS]
        w = 0.38; xs = np.arange(4)
        for k, (o, col) in enumerate([("hit_any", "#1565c0"), ("hit_top", "#c62828")]):
            v = t[o].values; ax.bar(xs + (k - .5) * w, v, w, color=col, alpha=.85, label={"hit_any": "Any tier", "hit_top": "Top tier"}[o])
            ax.errorbar(xs + (k - .5) * w, v, yerr=[v - t[o + "_lo"].values, t[o + "_hi"].values - v], fmt="none", ecolor="k", capsize=2, lw=.8)
        ax.set_xticks(xs); ax.set_xticklabels([f"{g}\nn={n}" for g, n in zip(TIERS, t.n)], fontsize=8); ax.set_ylim(0, 1.05)
        if i == 0: ax.set_title(pos)
        if j == 0: ax.set_ylabel({"pre": "Pre-draft", "post": "Post-draft", "mixed": "Adjusted (mixed)"}[s])
axes[0, 0].legend(fontsize=8)
fig.suptitle("Hit rates by grade and position (95% CIs)", fontsize=12); fig.tight_layout()
fig.savefig(f"{HERE}/plot_tier_by_position.png", dpi=130); plt.close(fig)

pd.set_option("display.width", 250); pd.set_option("display.max_columns", 40)
print(tab[tab.position == "All"].drop(columns=["position"]).to_string(index=False))
print(tests.to_string(index=False)); print(pd.DataFrame(trend).to_string(index=False)); print(pd.DataFrame(pw).to_string(index=False))
print(fc.to_string(index=False)); print(alt.to_string(index=False)); print(bs.to_string(index=False))
