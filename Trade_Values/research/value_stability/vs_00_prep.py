"""Value stability research (2026-11-24): build one panel from the point-in-time history.
Reads Trade_Values/history/values/*.csv and the snapshot meta (credibility k per season).
Writes vs_panel.pkl: one row per player x snapshot with redraft + dynasty columns,
the backed-out history PPG (fixed within a season) and weekly points."""
import pandas as pd, numpy as np, glob, os, warnings, rdata
warnings.filterwarnings('ignore')
H = '/home/user/Football/Trade_Values/history'
v = pd.concat([pd.read_csv(f) for f in sorted(glob.glob(f'{H}/values/values_*.csv'))])
# credibility k1 per season and position, from the week-1 snapshot meta (k is fixed within a season)
K = []
for f in sorted(glob.glob(f'{H}/snapshots/hv_*_w01.rds')):
    m = rdata.read_rds(f)['meta']; k = m['credibility_k']
    for i, ps in enumerate(k.coords['dim_0'].values):
        K.append(dict(season=int(m['season'][0]), pos=str(ps), k1=float(k.values[i, 0]), k2=float(k.values[i, 1])))
K = pd.DataFrame(K)
r = v[v.format == 'redraft'][['season', 'week', 'player_id', 'name', 'pos', 'team', 'age', 'status', 'games', 'ppg',
                              'credible_ppg', 'rep_ppg', 'team_games_left', 'exp_games_left', 'value', 'value_100k', 'rank', 'rank_pos']]
d = v[v.format == 'dynasty'][['season', 'week', 'player_id', 'name', 'pos', 'games', 'ppg', 'ppg_next', 'S_y4', 'value_ros', 'value', 'value_100k', 'rank', 'rank_pos', 'credible_ppg']]
d = d.rename(columns={c: 'dy_' + c for c in d.columns if c not in ('season', 'week', 'player_id')})
for c in ['name', 'pos', 'games', 'ppg']: d[c] = d.pop('dy_' + c)
P = r.merge(d, on=['season', 'week', 'player_id'], how='outer', indicator=True, suffixes=('', '_d'))
for c in ['name', 'pos', 'games', 'ppg']: P[c] = P[c].fillna(P.pop(c + '_d'))
P['credible_ppg'] = P.credible_ppg.fillna(P.dy_credible_ppg)
print(P._merge.value_counts()); P = P.drop(columns='_merge')
P = P.merge(K, on=['season', 'pos'], how='left')
P = P.sort_values(['player_id', 'season', 'week']).reset_index(drop=True)
# history PPG implied by the live blend: cppg = Z ppg + (1 - Z) hist, Z = n / (n + k1)
Z = P.games / (P.games + P.k1)
P['hist_ppg'] = (P.credible_ppg - Z * P.ppg) / (1 - Z)
# weekly points this week (cumulative points difference; 0 games added = did not play)
P['cum_pts'] = P.games * P.ppg
g = P.groupby(['player_id', 'season'])
P['pts_wk'] = P.cum_pts - g.cum_pts.shift().fillna(0)
P['g_wk'] = P.games - g.games.shift().fillna(0)
# season end: final games / points for rest-of-season targets
last = P.groupby(['player_id', 'season']).agg(g_end=('games', 'last'), pts_end=('cum_pts', 'last'), wk_last=('week', 'last')).reset_index()
P = P.merge(last, on=['player_id', 'season'])
P['n_ros'] = P.g_end - P.games; P['ppg_ros'] = np.where(P.n_ros > 0, (P.pts_end - P.cum_pts) / P.n_ros.clip(lower=1), np.nan)
# next season actual PPG (dynasty target)
nx = last.assign(season=last.season - 1).rename(columns={'g_end': 'g_next', 'pts_end': 'pts_next'})[['player_id', 'season', 'g_next', 'pts_next']]
P = P.merge(nx, on=['player_id', 'season'], how='left')
P['ppg_next_act'] = np.where(P.g_next >= 4, P.pts_next / P.g_next, np.nan)
P.to_pickle('vs_panel.pkl')
print(P.shape)
# sanity: hist_ppg should be constant within player-season
s = P[P.games >= 1].groupby(['player_id', 'season']).hist_ppg.agg(['std', 'count'])
print('within player-season sd of backed-out history PPG:', s['std'].describe().round(3).to_dict())
