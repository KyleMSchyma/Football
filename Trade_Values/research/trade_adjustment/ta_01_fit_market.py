"""Step 1 (python3 ta_01_fit_market.py [--fit11]): fit Kyle's trade adjustment on real trades and score it on a 14-day holdout.
Systems (side value = sum of asset values):
  ADD   additive points: v = our dynasty raw value (points over replacement), the live rule
  LOGc  logged values:   v = ln(1 + raw / c), c in {5, 20, 60} raw points (smaller c = more compressed)
For each trade, side 1 = the side holding the single best asset. Trade type = n1 v n2 (e.g. 1v2 = the best player
alone for two). Best-asset gap g = ln(best1 / best2) on raw values (>= 0).
Unadjusted gap r = ln(S1 / S2). Real trades are taken as fair, so the adjustment is adj(type, g) = -E[r | type, g],
fitted per type as a + b g + c g^2 (Huber loss), on trades before the holdout. Adjusted verdict = r + adj.
Score: holdout mean |r + adj| (lower = the system plus adjustment reproduces what managers accept), by type."""
import pandas as pd, numpy as np, warnings
from scipy.optimize import minimize
warnings.filterwarnings('ignore')
T = pd.read_pickle('ta_trades.pkl')
EPS = 0.5
def prep(T):
    s1 = T.apply(lambda r: max(r.va) >= max(r.vb), axis=1)
    a = np.where(s1, T.va, T.vb); b = np.where(s1, T.vb, T.va)
    X = pd.DataFrame({'when': T.when, 'A': a, 'B': b})
    X['type'] = X.A.map(len).astype(str) + 'v' + X.B.map(len).astype(str)
    X['g'] = np.log(np.maximum(X.A.map(max), EPS) / np.maximum(X.B.map(max), EPS))
    return X
X = prep(T)
SYS = {'ADD': lambda v: np.maximum(np.asarray(v), EPS)}
for c in [5, 20, 60]: SYS[f'LOG{c}'] = (lambda c: lambda v: np.log1p(np.maximum(np.asarray(v), 0) / c) + 1e-3)(c)
import sys
NO11 = True
# 1-for-1: r = f(g) exactly, so a gap-based adjustment would simply turn our values into market prices (every 1-for-1
# becomes 'fair' by construction). Run once with NO11 = False to show that, then leave 1-for-1 unadjusted.
NO11 = '--fit11' not in sys.argv
cut = X.when.max() - pd.Timedelta(days=14); tr = X.when < cut
def huber(x, d=0.5): ax = np.abs(x); return np.where(ax <= d, x * x / 2, d * (ax - d / 2))
rows, curves = [], []
for sn, f in SYS.items():
    r = np.log(X.A.map(lambda v: f(v).sum()) / X.B.map(lambda v: f(v).sum()))
    X['r_' + sn] = r
    adj = np.zeros(len(X)); adj0 = np.zeros(len(X))
    for ty in X.type.unique():
        m = (X.type == ty).values; mt = m & tr.values
        if ty == '1v1' and NO11: continue   # 1-for-1 left unadjusted (see note in the header)
        y = r[mt].values; g = X.g[mt].values
        p = minimize(lambda q: huber(y + q[0] + q[1] * g + q[2] * g * g).sum(), [0, 0, 0], method='Nelder-Mead', options={'maxiter': 4000}).x
        p0 = minimize(lambda q: huber(y + q[0]).sum(), [0], method='Nelder-Mead').x   # type-only adjustment (no gap)
        gg = X.g[m].values; adj[m] = p[0] + p[1] * gg + p[2] * gg * gg; adj0[m] = p0[0]
        for gx in np.linspace(0, np.quantile(g, .95), 26):   # curve only where training data exist
            curves.append(dict(system=sn, type=ty, g=gx, adj=p[0] + p[1] * gx + p[2] * gx * gx))
        rows.append(dict(system=sn, type=ty, n_train=int(mt.sum()), n_hold=int((m & ~tr.values).sum()), a=p[0], b=p[1], c=p[2], type_only=p0[0]))
    X['adj_' + sn] = adj; X['adj0_' + sn] = adj0
P = pd.DataFrame(rows); P.to_csv('ta_market_fit.csv', index=False); pd.DataFrame(curves).to_csv('ta_market_curves.csv', index=False)
H = X[~tr]; S = []
scale = {sn: np.abs(X.loc[X.type == '1v1', 'r_' + sn]).median() for sn in SYS}
for sn in SYS:
    for ty in ['ALL'] + sorted(X.type.unique()):
        h = H if ty == 'ALL' else H[H.type == ty]
        S.append(dict(system=sn, type=ty, n=len(h), no_adjustment=np.abs(h['r_' + sn]).mean(), type_only=np.abs(h['r_' + sn] + h['adj0_' + sn]).mean(),
                      type_and_gap=np.abs(h['r_' + sn] + h['adj_' + sn]).mean(), median_unadj=h['r_' + sn].median(),
                      scale=scale[sn], norm_no_adj=np.abs(h['r_' + sn]).mean() / scale[sn], norm_type_gap=np.abs(h['r_' + sn] + h['adj_' + sn]).mean() / scale[sn]))
S = pd.DataFrame(S).round(3); S.to_csv('ta_market_holdout%s.csv' % ('' if NO11 else '_fit11'), index=False)
pd.set_option('display.width', 200); print(S.to_string())
X.drop(columns=['A', 'B']).to_pickle('ta_scored.pkl')
