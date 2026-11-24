"""Finer grid and combinations: k multiplier x EWMA weight, plus k fit on top players only; scored like vs_02."""
import pandas as pd, numpy as np, warnings, importlib.util, sys
warnings.filterwarnings('ignore')
sys.argv = ['x']
spec = importlib.util.spec_from_file_location('ev', 'vs_02_evaluate.py'); ev = importlib.util.module_from_spec(spec)
src = open('vs_02_evaluate.py').read().split('rows = []')[0]; exec(src, ev.__dict__)
P, V = ev.P, ev.V
# reuse helpers from vs_01 without recomputing slopes: rebuild light versions
from scipy.stats import norm
def cppg(k): Z = P.games / (P.games + k); return Z * P.ppg + (1 - Z) * P.hist_ppg
def rep_lines(c):
    mg = np.minimum(6, np.maximum(1, np.floor(0.6 * P.week))); el = (P.games >= mg) & P.rep_ppg.notna()
    above = el & (P.credible_ppg >= P.rep_ppg - 1e-9); key = [P.season, P.week, P.pos]
    N = above.groupby(key).transform('sum'); cr = pd.Series(np.where(el, c, -np.inf)).groupby(key).rank(ascending=False, method='first')
    return pd.Series(np.where(el & (cr == N), c, np.nan)).groupby(key).transform('max').fillna(P.rep_ppg)
def build(c):
    rep = rep_lines(c); dc = c - P.credible_ppg
    ros = P.dy_value_ros + P.exp_games_left * dc * norm.cdf((P.credible_ppg - P.rep_ppg.fillna(rep)) / 4.0)
    x = pd.DataFrame({'cppg': c, 'rep': rep, 'red': (c - rep) * P.exp_games_left, 'dyn': ros + P.fut + P.b_fut * dc, 'nxt': P.dy_ppg_next + P.b_next * dc})
    return x
def smooth(x, a):
    out = np.empty(len(P)); pk = None; s = 0.0
    for i, kk in enumerate(zip(P.player_id, P.season)):
        s = x[i] if kk != pk else a * x[i] + (1 - a) * s; out[i] = s; pk = kk
    return pd.Series(out)
def anchor(x):
    for col in ['red', 'dyn']:
        t10 = x.groupby([P.season, P.week])[col].transform(lambda s: s.nlargest(10).mean()); t1 = x.groupby([P.season, P.week])[col].transform('max')
        x[col + '100k'] = 1e5 * x[col] / t10 * (t10 / t1).groupby(P.season).transform('mean')
    return x
def plain(x):
    for col in ['red', 'dyn']: x[col + '100k'] = 1e5 * x[col] / x.groupby([P.season, P.week])[col].transform('max')
    return x
# ==== GRID ====
rows = []
for m in [1, 1.25, 1.5, 2]:
    c0 = cppg(m * P.k1).values
    for a in [1.0, 0.8, 0.7, 0.6, 0.5]:
        c = pd.Series(c0) if a == 1 else smooth(c0, a)
        for anc in [False, True]:
            x = build(c); x = anchor(x) if anc else plain(x)
            o = ev.acc(x); dv = ev.vol(x, 'dyn100k'); rv = ev.vol(x, 'red100k')
            rows.append(dict(k_mult=m, ewma_a=a, top10_anchor=anc, **o, dyn_mean_abs_chg=dv['mean_abs_chg'], dyn_drop10=dv['drop10'],
                             dyn_drop20=dv['drop20'], dyn_rank_move=dv['rank_move'], red_mean_abs_chg=rv['mean_abs_chg'], red_drop10=rv['drop10'], red_rank_move=rv['rank_move']))
            print(rows[-1]['k_mult'], a, anc, round(o['Next-season PPG RMSE (top 50)'], 3), round(o['ROS PPG RMSE'], 3), round(dv['drop10'], 3), flush=True)
pd.DataFrame(rows).to_csv('vs_grid.csv', index=False)
