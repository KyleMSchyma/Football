"""Value stability backtest (Kyle 2026-11-24): can top values be steadier without losing accuracy?
Every variant changes only the IN-SEASON credibility blend (or smooths its output). History PPG (3-season blend
with the draft prior) is held at its live point-in-time value, backed out of each snapshot exactly.
Redraft value is recomputed exactly: (credible PPG - replacement line) x expected games left, replacement line
re-drawn at the same depth. Dynasty value uses a surrogate: within each player-season the live dynasty model's
next-season PPG is an exact linear function of credible PPG (R^2 = 1.00), and its future value is close to linear
(R^2 0.70-0.89), so the change in dynasty value = player-season slope x change in credible PPG.
Rolling origin: anything fitted for season S uses seasons before S only."""
import pandas as pd, numpy as np, warnings
from scipy.stats import spearmanr, norm
warnings.filterwarnings('ignore')
P = pd.read_pickle('vs_panel.pkl')
P = P[P.pos.isin(['QB', 'RB', 'WR', 'TE']) & P.hist_ppg.notna() & (P.games >= 1)].copy()
P['fut'] = P.dy_value - P.dy_value_ros
P['avail'] = (P.exp_games_left / P.team_games_left.replace(0, np.nan)).fillna(0)
P = P.sort_values(['player_id', 'season', 'week']).reset_index(drop=True)
POS = ['QB', 'RB', 'WR', 'TE']

# ---------- dynasty surrogate slopes (within player-season) ----------
def slopes(g):
    g = g.dropna(subset=['credible_ppg', 'fut', 'dy_ppg_next'])
    if len(g) < 5 or g.credible_ppg.std() < 0.2: return pd.Series({'b_next': np.nan, 'b_fut': np.nan})
    X = np.c_[np.ones(len(g)), g.credible_ppg, g.avail]
    bn = np.polyfit(g.credible_ppg, g.dy_ppg_next, 1)[0]
    bf = np.linalg.lstsq(X, g.fut.values, rcond=None)[0][1]
    return pd.Series({'b_next': bn, 'b_fut': bf})
S = P.groupby(['player_id', 'season']).apply(slopes).reset_index()
P = P.merge(S, on=['player_id', 'season'], how='left')
med = P.groupby('pos')[['b_next', 'b_fut']].median()
for c in ['b_next', 'b_fut']: P[c] = P[c].fillna(P.pos.map(med[c]))
P['b_fut'] = P.b_fut.clip(lower=0)
print('surrogate slopes (median by position):'); print(med.round(2))

# ---------- weekly scatter: classic Buhlmann-Straub k = EPV / VHM (exposure = games) ----------
wk = P[(P.g_wk == 1)][['player_id', 'season', 'pos', 'pts_wk']]
def bs_k(x):
    g = x.groupby(['player_id', 'season']).pts_wk.agg(['count', 'mean', 'var']); g = g[g['count'] >= 4]
    n, m, v = g['count'], g['mean'], g['var']
    EPV = ((n - 1) * v).sum() / (n - 1).sum(); N = n.sum(); xbar = (n * m).sum() / N; r = len(g)
    VHM = ((n * (m - xbar) ** 2).sum() - (r - 1) * EPV) / (N - (n ** 2).sum() / N)
    return pd.Series({'EPV': EPV, 'VHM': VHM, 'k': EPV / VHM, 'sd_game': np.sqrt(EPV)})
BSK = {(s, ps): bs_k(wk[(wk.season < s) & (wk.season >= s - 5) & (wk.pos == ps)]) for s in range(2017, 2027) for ps in POS}
bsk = pd.DataFrame(BSK).T; bsk.index.names = ['season', 'pos']; bsk = bsk.reset_index()
P = P.merge(bsk[['season', 'pos', 'k', 'sd_game']].rename(columns={'k': 'k_bs'}), on=['season', 'pos'], how='left')

# ---------- trimmed weekly points (limited-fluctuation idea) ----------
def ppg_trim(c):
    base = P.hist_ppg; lo = base - c * P.sd_game; hi = base + c * P.sd_game
    t = np.where(P.g_wk == 1, np.clip(P.pts_wk, lo, hi), 0.0)
    cum = pd.Series(t).groupby([P.player_id, P.season]).cumsum().values
    return cum / P.games

def cppg(k, ppg=None):
    ppg = P.ppg if ppg is None else ppg; Z = P.games / (P.games + k); return Z * ppg + (1 - Z) * P.hist_ppg

# ---------- rolling-origin fitted k (horizon matched) ----------
P['wb'] = pd.cut(P.week, [0, 4, 8, 12, 30], labels=['1-4', '5-8', '9-12', '13+'])
KG = np.exp(np.linspace(np.log(1), np.log(80), 60))
def fit_k(train, target, wcol):
    t = train.dropna(subset=[target]); best = None
    for k in KG:
        Z = t.games / (t.games + k); pr = Z * t.ppg + (1 - Z) * t.hist_ppg
        if target == 'ppg_next_act': pr = t.dy_ppg_next + t.b_next * (pr - t.credible_ppg)
        e = (t[wcol] * (t[target] - pr) ** 2).sum()
        if best is None or e < best[1]: best = (k, e)
    return best[0]
FK = []
ros_ok = (P.n_ros >= 3)
for s in range(2018, 2027):
    for ps in POS:
        for wb in P.wb.cat.categories:
            tr = P[(P.season < s) & (P.pos == ps) & (P.wb == wb)]
            kr = fit_k(tr[tr.n_ros >= 3], 'ppg_ros', 'n_ros')
            kd = fit_k(tr[(tr.g_next >= 4) & (tr.season <= s - 2)], 'ppg_next_act', 'g_next')   # next season of s-1 is not over at s's start
            FK.append(dict(season=s, pos=ps, wb=wb, k_ros=kr, k_dyn=kd))
FK = pd.DataFrame(FK); FK.to_csv('vs_fitted_k.csv', index=False)
P = P.merge(FK, on=['season', 'pos', 'wb'], how='left')

# ---------- value rebuild for one variant ----------
def rep_lines(c):
    """replacement line re-drawn at the live depth: N = eligible players at or above the live line"""
    mg = np.minimum(6, np.maximum(1, np.floor(0.6 * P.week)))
    el = (P.games >= mg) & P.rep_ppg.notna()
    above = el & (P.credible_ppg >= P.rep_ppg - 1e-9)
    key = [P.season, P.week, P.pos]
    N = above.groupby(key).transform('sum')
    cr = pd.Series(np.where(el, c, -np.inf)).groupby(key).rank(ascending=False, method='first')
    rep = pd.Series(np.where(el & (cr == N), c, np.nan)).groupby(key).transform('max')
    return rep.fillna(P.rep_ppg)

def build(c, ppg_next=None):
    rep = rep_lines(c)
    dc = c - P.credible_ppg
    red = (c - rep) * P.exp_games_left
    sd0 = 4.0
    ros = P.dy_value_ros + P.exp_games_left * dc * norm.cdf((P.credible_ppg - P.rep_ppg.fillna(rep)) / sd0)
    dyn = ros + P.fut + P.b_fut * dc
    nxt = P.dy_ppg_next + P.b_next * dc
    return pd.DataFrame({'cppg': c, 'rep': rep, 'red': red, 'dyn': dyn, 'nxt': nxt})

def to100k(x, col):
    top = x.groupby([P.season, P.week])[col].transform('max'); return 1e5 * x[col] / top

def smooth(series_new, a):
    """EWMA of credible PPG within a player-season: s_t = a x new_t + (1 - a) x s_(t-1)"""
    out = np.empty(len(P)); prev_key = None; s = 0.0
    keys = list(zip(P.player_id, P.season)); x = series_new.values
    for i, kk in enumerate(keys):
        s = x[i] if kk != prev_key else a * x[i] + (1 - a) * s; out[i] = s; prev_key = kk
    return pd.Series(out)

V = {}
V['Live (k fit at week 9)'] = build(P.credible_ppg)
for m in [1.5, 2, 3, 5]: V[f'k x {m}'] = build(cppg(m * P.k1))
V['Classic Buhlmann-Straub k (EPV/VHM)'] = build(cppg(P.k_bs))
V['Horizon k: redraft fit (ROS)'] = build(cppg(P.k_ros))
V['Horizon k: dynasty fit (next season)'] = build(cppg(P.k_dyn))
for c in [1.0, 1.5]: V[f'Trim games at +/-{c} sd'] = build(cppg(P.k1, ppg_trim(c)))
for a in [0.6, 0.4]: V[f'EWMA smooth a={a}'] = build(smooth(P.credible_ppg, a))
for kk, x in V.items():
    x['red100k'] = to100k(x, 'red'); x['dyn100k'] = to100k(x, 'dyn')
# split model: redraft on horizon-ROS k, dynasty on horizon-dynasty k (each value uses its own horizon)
sp = V['Horizon k: redraft fit (ROS)'].copy(); dd = V['Horizon k: dynasty fit (next season)']
for c in ['dyn', 'dyn100k', 'nxt']: sp[c] = dd[c]
V['Split: ROS k for redraft, dynasty k for dynasty'] = sp
pd.to_pickle((P, V), 'vs_variants.pkl')
chk = V['Live (k fit at week 9)']
print('rebuild check: redraft value vs live, mean abs diff', (chk.red - P.value).abs().mean().round(3),
      '| dynasty', (chk.dyn - P.dy_value).abs().mean().round(3))
