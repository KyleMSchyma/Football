"""Kyle 2026-11-24: anchor the Nth player (2nd, 3rd, ...) at 100k and let the very top go above it.
Compare with #1 = 100k (live) and the top-10 average anchor. Values unchanged; display scale only.
Reports steadiness of top-24 values and how high the #1 player goes."""
import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
ns = {}; exec(open('vs_03_combos.py').read().split('# ==== GRID' + ' ====')[0], ns)
P, ev, build, cppg, smooth = ns['P'], ns['ev'], ns['build'], ns['cppg'], ns['smooth']
live = build(P.credible_ppg.copy()); cand = build(smooth(cppg(1.25 * P.k1).values, 0.7))
key = [P.season, P.week]
def scale(x, how):
    x = x.copy()
    for col in ['red', 'dyn']:
        g = x.groupby(key)[col]
        if how == 'top10': ref = g.transform(lambda s: s.nlargest(10).mean())
        else: ref = g.transform(lambda s, n=how: s.nlargest(n).iloc[-1])
        x[col + '100k'] = 1e5 * x[col] / ref
    return x
rows = []
for base_nm, base in [('Live model', live), ('Steadiness candidate model', cand)]:
    for how, lab in [(1, '#1 = 100k (live)'), (2, '#2 = 100k'), (3, '#3 = 100k'), (5, '#5 = 100k'), (10, '#10 = 100k'), ('top10', 'Top-10 average = 100k')]:
        x = scale(base, how); ev.ev = P.season >= 2018
        d = ev.vol(x, 'dyn100k'); r = ev.vol(x, 'red100k')
        top = x[P.season >= 2018].groupby([P.season, P.week]).dyn100k.max()
        rows.append(dict(model=base_nm, anchor=lab, dyn_drop10=d['drop10'], dyn_drop20=d['drop20'], dyn_mean_abs_chg=d['mean_abs_chg'],
                         red_drop10=r['drop10'], top_median=top.median(), top_p90=top.quantile(.9), top_max=top.max()))
R = pd.DataFrame(rows); R.to_csv('vs_anchor_rank.csv', index=False); print(R.round(3).to_string())
w = (P.season == 2026) & (P.week == 11)
for how in [1, 2, 3, 5]:
    x = scale(cand, how)
    print(how, x[w].assign(name=P.name[w]).nlargest(5, 'dyn100k')[['name', 'dyn100k']].round(-2).values.tolist())
