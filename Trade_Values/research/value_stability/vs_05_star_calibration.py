"""Kyle 2026-11-24: dynasty values are predictions of FUTURE production; one hot or cold stretch should not split two
elite players 2:1. Test: are next-season PPG projections for the top players too spread out (calibration slope < 1)?
Then a fix: shrink projected next-season PPG above a knot, x_adj = K + b (x - K), K and b fitted per position on
seasons up to S-2 (rolling), and carry the change into dynasty value with the player-season surrogate slope."""
import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
P, V = pd.read_pickle('vs_variants.pkl')
rng = np.random.default_rng(1)
# ---------- 1. calibration slope by tier with player-season bootstrap ----------
x = P[(P.season <= 2024) & (P.week.between(6, 14)) & (P.g_next >= 4) & P.dy_ppg_next.notna()].copy()
def slope(y): return np.polyfit(y.dy_ppg_next, y.ppg_next_act, 1, w=y.g_next)[0]
rows = []
for tier, n in [('top 12', 12), ('top 24', 24), ('top 50', 50), ('top 100', 100), ('all', 9999)]:
    for pos in ['ALL', 'QB', 'RB', 'WR', 'TE']:
        y = x[(x.dy_rank <= n) & ((x.pos == pos) | (pos == 'ALL'))]
        if y[['player_id', 'season']].drop_duplicates().shape[0] < 15: continue
        keys = y[['player_id', 'season']].drop_duplicates().values; bs = []
        for _ in range(300):
            k = pd.DataFrame(keys[rng.integers(0, len(keys), len(keys))], columns=['player_id', 'season'])
            bs.append(slope(k.merge(y, on=['player_id', 'season'])))
        rows.append(dict(tier=tier, pos=pos, player_seasons=len(keys), slope=slope(y), lo=np.percentile(bs, 5), hi=np.percentile(bs, 95)))
C = pd.DataFrame(rows).round(2); C.to_csv('vs_star_calibration.csv', index=False); print(C.to_string())
# ---------- 2. rolling knot shrink ----------
KN = np.arange(10, 24.5, 0.5); BG = np.arange(0.2, 1.01, 0.05)
def fit(tr):
    best = (None, None, np.inf)
    for K in KN:
        hi = tr.dy_ppg_next > K
        if hi.sum() < 30: continue
        for b in BG:
            p = np.where(hi, K + b * (tr.dy_ppg_next - K), tr.dy_ppg_next)
            e = np.sum(tr.g_next * (tr.ppg_next_act - p) ** 2)
            if e < best[2]: best = (K, b, e)
    return best[:2]
F = []
base = P[(P.g_next >= 4) & P.dy_ppg_next.notna()]
for s in range(2018, 2027):
    for ps in ['QB', 'RB', 'WR', 'TE']:
        K, b = fit(base[(base.season <= s - 2) & (base.pos == ps)])
        F.append(dict(season=s, pos=ps, knot=K, b=b))
F = pd.DataFrame(F); F.to_csv('vs_star_shrink_fit.csv', index=False); print(F[F.season.isin([2020, 2024, 2026])].to_string())
Q = P.merge(F, on=['season', 'pos'], how='left')
adj = np.where(Q.dy_ppg_next > Q.knot, Q.knot + Q.b * (Q.dy_ppg_next - Q.knot), Q.dy_ppg_next) - Q.dy_ppg_next
adj = pd.Series(adj).fillna(0)
pd.to_pickle(adj, 'vs_star_adj.pkl')
print('mean shift for top-24 dynasty, 2026 wk11:', adj[(P.season == 2026) & (P.week == 11) & (P.dy_rank <= 24)].mean().round(2))
