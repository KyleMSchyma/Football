"""Kyle 2026-11-24: with no anchor at all, which value system is best? He wants it to stay exponential (convex).
Every system is a 'currency' on the SAME projection (live dynasty value = expected points over replacement, 2026-2031):
  A  Points, fixed unit: value = C x VOR (C one constant for all weeks and seasons; no per-week rescale)
  Pa Power: value = C x VOR^a, a in {0.75, 1.25, 1.5, 2} (a > 1 = more exponential, stars worth more than their points)
  R  Rank-exponential: value = C x exp(-b x (rank - 1)), b fitted so the curve matches ours on average (old dv_08 style)
Scored on: (1) steadiness of top-24 values week to week; (2) realized fairness: realized value ~ c x value^beta,
beta = 1 means a package worth X really scores X (additive trades come out fair); fitted per system on top-150,
2018-2024 snapshots, realized = rest-of-season + next-season points over replacement (next season discounted 1/1.15).
Rank accuracy (Spearman) is identical for all systems: they are all monotone in the same projection."""
import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
ns = {}; exec(open('vs_03_combos.py').read().split('# ==== GRID' + ' ====')[0], ns)
P, ev, build, cppg, smooth = ns['P'], ns['ev'], ns['build'], ns['cppg'], ns['smooth']
models = {'live': build(P.credible_ppg.copy()), 'candidate': build(smooth(cppg(1.25 * P.k1).values, 0.7))}
key = [P.season, P.week]
def systems(x):
    vor = x.dyn.clip(lower=0.01); out = {}
    top = vor.groupby(key).transform('max'); C1 = 1e5 / top[P.season >= 2018].groupby(key).first().mean()
    out['Live: #1 = 100k each week'] = 1e5 * vor / top
    for a in [0.75, 1.0, 1.25, 1.5, 2.0]:
        v = vor ** a; C = 1e5 / (v.groupby(key).transform('max')[P.season >= 2018].groupby(key).first().mean())
        out[f'Points^{a} fixed unit' if a != 1 else 'Points, fixed unit (no anchor)'] = C * v
    rk = vor.groupby(key).rank(ascending=False, method='first')
    # b so that log value-by-rank slope over ranks 1-50 matches ours on average
    sub = (rk <= 50) & (P.season >= 2018)
    b = -np.polyfit(rk[sub] - 1, np.log(out['Live: #1 = 100k each week'][sub]), 1)[0]
    out[f'Rank-exponential (b = {b:.3f})'] = 1e5 * np.exp(-b * (rk - 1))
    return out
act = np.maximum(P.ppg_ros.fillna(0) - P.rep_ppg.fillna(0), 0) * P.n_ros + np.maximum(P.ppg_next_act.fillna(0) - P.rep_ppg.fillna(0), 0) * P.g_next.fillna(0) / 1.15
rows = []
for mn, x in models.items():
    for sn, v in systems(x).items():
        y = pd.DataFrame({'dyn100k': v}); ev.ev = P.season >= 2018; d = ev.vol(y, 'dyn100k')
        rk = v.groupby(key).rank(ascending=False, method='first')
        m = (P.season >= 2018) & (P.season <= 2024) & (rk <= 150) & (P.games >= 3)
        beta = np.polyfit(np.log(v[m]), np.log(act[m] + 1), 1)[0]          # realized ~ value^beta
        # package test: realized of the #1 player vs realized of the 2 players whose values sum closest to his (each snapshot)
        g = pd.DataFrame({'s': P.season, 'w': P.week, 'v': v, 'a': act, 'rk': rk})[m]
        ratios = []
        for (s, w), q in g.groupby(['s', 'w']):
            q = q.sort_values('rk'); top3 = q.head(3)
            for _, t in top3.iterrows():
                rest = q[q.rk > 6]; target = t.v
                # pairs: player i + the player whose value makes the pair closest to target
                vv = rest.v.values; aa = rest.a.values; best = None
                for i in range(len(vv)):
                    j = np.argmin(np.abs(vv - (target - vv[i]))); 
                    if j == i: continue
                    e = abs(vv[i] + vv[j] - target)
                    if best is None or e < best[0]: best = (e, aa[i] + aa[j])
                if best and best[1] > 0: ratios.append(t.a / best[1])
        rows.append(dict(model=mn, system=sn, drop10=d['drop10'], drop20=d['drop20'], mean_abs_chg=d['mean_abs_chg'], rank_move=d['rank_move'],
                         realized_beta=beta, star_vs_2for1_realized=np.median(ratios), n_pkg=len(ratios),
                         top1_median=v[P.season >= 2018].groupby(key).max().median(), rank24_median=v[(rk == 24) & (P.season >= 2018)].median(),
                         rank50_median=v[(rk == 50) & (P.season >= 2018)].median()))
        print(rows[-1]['model'], sn, round(d['drop10'], 3), round(beta, 2), round(rows[-1]['star_vs_2for1_realized'], 2), flush=True)
R = pd.DataFrame(rows); R.to_csv('vs_value_systems.csv', index=False)
pd.set_option('display.width', 250); print(R.round(3).to_string())
