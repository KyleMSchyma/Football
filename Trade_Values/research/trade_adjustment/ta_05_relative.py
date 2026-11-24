"""Step 5: separate the consolidation premium from level disagreement.
In accepted 1-for-1 trades our dynasty values typically differ by ~2x (median |ln ratio| 0.68) and r rises ~1:1 with
the gap, so a gap term fitted per type mostly re-learns 'market price vs our price', not package behaviour.
Relative adjustment: rel(type, g) = adj_type(g) - adj_1v1(g) = how much MORE (or less) the market credits the side with
the best asset in this trade type than in a 1-for-1 with the same best-asset gap. This is the part that depends on the
trade type only; it is what a 'trade value adjustment' on top of our values would add.
Scored on the 14-day holdout: error of r + adj_1v1(g) + rel(type, g) is by construction the full fit, so we report the
premium table and how much of the full adjustment's gain the type-specific part carries (r + adj_1v1 alone vs full)."""
import pandas as pd, numpy as np, warnings
from scipy.optimize import minimize
warnings.filterwarnings('ignore')
src = open('ta_01_fit_market.py').read().split('import sys')[0]; exec(src)
cut = X.when.max() - pd.Timedelta(days=14); tr = X.when < cut
def huber(x, d=0.5): ax = np.abs(x); return np.where(ax <= d, x * x / 2, d * (ax - d / 2))
def fit(y, g): return minimize(lambda q: huber(y + q[0] + q[1] * g + q[2] * g * g).sum(), [0, 0, 0], method='Nelder-Mead', options={'maxiter': 4000}).x
Q = lambda p, g: p[0] + p[1] * g + p[2] * g * g
prem, hold = [], []
types = ['1v2', '1v3', '2v1', '2v2', '2v3', '3v1', '3v2', '3v3']
for sn, f in SYS.items():
    r = np.log(X.A.map(lambda v: f(v).sum()) / X.B.map(lambda v: f(v).sum()))
    p11 = fit(r[tr & (X.type == '1v1')].values, X.g[tr & (X.type == '1v1')].values)
    for ty in types:
        mt = tr & (X.type == ty); p = fit(r[mt].values, X.g[mt].values); g95 = np.quantile(X.g[mt], .95)
        for ratio in [1, 1.25, 1.5, 2, 3]:
            gx = np.log(ratio)
            prem.append(dict(system=sn, type=ty, best_ratio=ratio, in_range=gx <= g95, rel_pct=100 * (np.exp(Q(p, gx) - Q(p11, gx)) - 1)))
        h = (~tr) & (X.type == ty); gh = X.g[h].values; rh = r[h].values
        hold.append(dict(system=sn, type=ty, n_hold=int(h.sum()), err_none=np.abs(rh).mean(), err_1v1_curve_only=np.abs(rh + Q(p11, gh)).mean(),
                         err_full=np.abs(rh + Q(p, gh)).mean(), err_rel_only=np.abs(rh + Q(p, gh) - Q(p11, gh)).mean(), err_rel_flat=np.abs(rh + Q(p11, gh) + np.median(-(r[mt] + Q(p11, X.g[mt])))).mean()))
Pm = pd.DataFrame(prem).round(3); Pm.to_csv('ta_market_relative_premium.csv', index=False)
H = pd.DataFrame(hold).round(3); H.to_csv('ta_market_relative_holdout.csv', index=False)
pd.set_option('display.width', 220)
print(Pm[Pm.system == 'ADD'].pivot(index='type', columns='best_ratio', values='rel_pct').round(0))
print(Pm[Pm.system == 'LOG20'].pivot(index='type', columns='best_ratio', values='rel_pct').round(0))
print(H.to_string())
# Kyle's design: 1-for-1 untouched, only the type part added. Normalized by that system's 1-for-1 holdout median |r|.
h11 = (~tr) & (X.type == '1v1'); rows = []
for sn, f in SYS.items():
    r = np.log(X.A.map(lambda v: f(v).sum()) / X.B.map(lambda v: f(v).sum())); sc = np.median(np.abs(r[h11]))
    h = H[H.system == sn]; w = h.n_hold
    rows.append(dict(system=sn, scale=sc, multi_none=(h.err_none * w).sum() / w.sum() / sc, multi_rel_only=(h.err_rel_only * w).sum() / w.sum() / sc,
                     multi_full=(h.err_full * w).sum() / w.sum() / sc))
S = pd.DataFrame(rows).round(3); S.to_csv('ta_market_relative_summary.csv', index=False); print(S.to_string())
