"""Kyle 2026-11-24 proposal, part 1: do LOGGED values move less week to week than additive points?
Same projection as the steadiness study (vs_03 surrogate dynasty value, live and steadiness-candidate credible PPG).
Systems (no per-week #1 rescale unless stated; one constant per system puts the average #1 at 100k):
  Live: #1 = 100k each week | ADD fixed unit (points, no anchor) | LOGc: ln(1 + raw/c), c = 5, 20, 60 raw points.
Scored on top-24 weekly 10%+ / 20%+ drops (2018-2026) using the same ev.vol() as vs_09.
Run from this folder; it reads ../value_stability/ (vs_panel.pkl is local only, built by vs_00_prep.py)."""
import os, numpy as np, pandas as pd, warnings
warnings.filterwarnings('ignore')
here = os.getcwd(); os.chdir('../value_stability')
ns = {}; exec(open('vs_03_combos.py').read().split('# ==== GRID' + ' ====')[0], ns)
os.chdir(here)
P, ev, build, cppg, smooth = ns['P'], ns['ev'], ns['build'], ns['cppg'], ns['smooth']
models = {'live': build(P.credible_ppg.copy()), 'candidate': build(smooth(cppg(1.25 * P.k1).values, 0.7))}
key = [P.season, P.week]
def scale(v):
    C = 1e5 / v.groupby(key).transform('max')[P.season >= 2018].groupby(key).first().mean(); return C * v
rows = []
for mn, x in models.items():
    raw = x.dyn.clip(lower=0.01)
    S = {'Live: #1 = 100k each week': 1e5 * raw / raw.groupby(key).transform('max'), 'ADD fixed unit (no anchor)': scale(raw)}
    for c in [5, 20, 60]: S[f'LOG{c} fixed unit'] = scale(np.log1p(raw / c))
    S['LOG20, #1 = 100k each week'] = (lambda l: 1e5 * l / l.groupby(key).transform('max'))(np.log1p(raw / 20))
    for sn, v in S.items():
        ev.ev = P.season >= 2018; d = ev.vol(pd.DataFrame({'dyn100k': v}), 'dyn100k')
        rk = v.groupby(key).rank(ascending=False, method='first'); s18 = P.season >= 2018
        rows.append(dict(model=mn, system=sn, drop10=d['drop10'], drop20=d['drop20'], mean_abs_chg=d['mean_abs_chg'],
                         top1=v[s18].groupby(key).max().median(), rank12=v[(rk == 12) & s18].median(),
                         rank24=v[(rk == 24) & s18].median(), rank100=v[(rk == 100) & s18].median()))
        print(mn, sn, round(d['drop10'], 3), flush=True)
R = pd.DataFrame(rows); R.to_csv('ta_log_steadiness.csv', index=False)
pd.set_option('display.width', 250); print(R.round(3).to_string())
