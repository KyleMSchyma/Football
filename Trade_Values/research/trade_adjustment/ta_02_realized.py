"""Step 2: the same adjustment fitted on REALIZED points instead of the market.
Synthetic trades from the point-in-time history: for each 2018-2024 snapshot (weeks 3-14), draw trades of every type
(1v1 ... 3v3, in the market's mix) from the dynasty top 200, keeping those our additive values call fair (sides
within 20%). Realized side value R = rest-of-season + next-season points over replacement actually scored
(next season / 1.15), the same window as vs_02. Target y = ln((R1 + 5) / (R2 + 5)); side 1 holds the best asset.
For each system (ADD, LOG5, LOG20, LOG60) the adjustment adj(type, g) = a + b g + c g^2 is fitted to y - r_sys on
2018-2021 and scored on 2022-2024: mean |y - (r_sys + adj)| in realized units, comparable across systems."""
import pandas as pd, numpy as np, warnings
from scipy.optimize import minimize
warnings.filterwarnings('ignore')
P = pd.read_pickle('../value_stability/vs_panel.pkl')
P = P[(P.season.between(2018, 2024)) & P.week.between(3, 14) & P.dy_value.notna()].copy()
P['act'] = np.maximum(P.ppg_ros.fillna(0) - P.rep_ppg.fillna(0), 0) * P.n_ros + np.maximum(P.ppg_next_act.fillna(0) - P.rep_ppg.fillna(0), 0) * P.g_next.fillna(0) / 1.15
P = P[P.dy_rank <= 200]
MIX = {'1v1': .52, '1v2': .13, '2v1': .11, '2v2': .12, '2v3': .03, '3v2': .03, '3v3': .03, '1v3': .02, '3v1': .01}
rng = np.random.default_rng(7); rows = []
for (s, w), g in P.groupby(['season', 'week']):
    v = np.maximum(g.dy_value.values, 0.5); a = g.act.values; n = len(v)
    for ty, share in MIX.items():
        na, nb = int(ty[0]), int(ty[2]); want = int(400 * share); got = 0; tries = 0
        while got < want and tries < want * 60:
            tries += 1; ia = rng.choice(n, na, replace=False); ib = rng.choice(n, nb, replace=False)
            if set(ia) & set(ib): continue
            if abs(np.log(v[ia].sum() / v[ib].sum())) > np.log(1.2): continue
            if v[ia].max() < v[ib].max(): ia, ib = ib, ia
            rows.append(dict(season=s, type=f'{len(ia)}v{len(ib)}', A=v[ia], B=v[ib], y=np.log((a[ia].sum() + 5) / (a[ib].sum() + 5)))); got += 1
X = pd.DataFrame(rows); print(len(X), 'synthetic trades'); print(X.type.value_counts().to_dict())
X['g'] = np.log(X.A.map(max) / X.B.map(max))
SYS = {'ADD': lambda v: v}
for c in [5, 20, 60]: SYS[f'LOG{c}'] = (lambda c: lambda v: np.log1p(v / c) + 1e-3)(c)
tr = X.season <= 2021
def huber(x, d=0.5): ax = np.abs(x); return np.where(ax <= d, x * x / 2, d * (ax - d / 2))
out, curves = [], []
for sn, f in SYS.items():
    r = np.log(X.A.map(lambda v: f(v).sum()) / X.B.map(lambda v: f(v).sum())); adj = np.zeros(len(X))
    for ty in X.type.unique():
        m = (X.type == ty).values; mt = m & tr.values; y = (X.y - r)[mt].values; gg = X.g[mt].values
        p = minimize(lambda q: huber(y - q[0] - q[1] * gg - q[2] * gg * gg).sum(), [0, 0, 0], method='Nelder-Mead', options={'maxiter': 4000}).x
        G = X.g[m].values; adj[m] = p[0] + p[1] * G + p[2] * G * G
        for gx in np.linspace(0, np.quantile(gg, .95), 26):   # curve only where training data exist
            curves.append(dict(system=sn, type=ty, g=gx, adj=p[0] + p[1] * gx + p[2] * gx * gx))
    for ty in ['ALL'] + sorted(X.type.unique()):
        h = (~tr) & ((X.type == ty) | (ty == 'ALL'))
        out.append(dict(system=sn, type=ty, n_test=int(h.sum()), err_no_adj=np.abs(X.y - r)[h].mean(), err_adj=np.abs(X.y - r - adj)[h].mean(),
                        mean_y=X.y[h].mean(), mean_r=r[h].mean()))
O = pd.DataFrame(out).round(3); O.to_csv('ta_realized_holdout.csv', index=False); pd.DataFrame(curves).to_csv('ta_realized_curves.csv', index=False)
pd.set_option('display.width', 200); print(O.to_string())
