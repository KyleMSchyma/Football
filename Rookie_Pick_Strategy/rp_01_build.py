# Build the player table for the rookie pick strategy research.
# Draft-time price: Trade_Values/dv_rookie_board_values.csv (post board, value_100k, out-of-class for 2010-2023).
# Realized production: nflverse season stats (full PPR), points over replacement of the draft season, discounted,
# seasons 1..min(5, 2025-class+1); same formula as dv_13 / pp_03 "players' definition", checked against pp_03's output.
import pandas as pd, numpy as np, glob, sys
S = sys.argv[1]; OUT = sys.argv[2]
ps = pd.concat([pd.read_csv(f, low_memory=False) for f in sorted(glob.glob(S + '/dl/ps_*.csv'))])
ps = ps[ps.season_type == 'REG'] if 'season_type' in ps else ps
ps = ps[ps.position.isin(['QB', 'RB', 'WR', 'TE'])][['player_id', 'player_display_name', 'position', 'season', 'games', 'fantasy_points_ppr']]
ps = ps.groupby(['player_id', 'season'], as_index=False).agg(name=('player_display_name', 'first'), pos=('position', 'first'), g=('games', 'sum'), pts=('fantasy_points_ppr', 'sum'))
ps['ppg'] = ps.pts / ps.g.clip(lower=1)
N = {'QB': 24, 'RB': 24, 'WR': 36, 'TE': 12}
rows = []
for y, d in ps[ps.g >= 6].groupby('season'):
    base = {}; rest = []
    for p, n in N.items():
        z = d[d.pos == p].sort_values('ppg', ascending=False)
        base[p] = z.ppg.iloc[n - 1]; rest.append(z.iloc[n:])
    fl = pd.concat([r for r, p in zip(rest, N) if p != 'QB']).sort_values('ppg', ascending=False)
    flex_line = fl.ppg.iloc[23]
    for p in N:
        rows.append(dict(season=y, pos=p, rep_ref=base[p], rep_flex=base[p] if p == 'QB' else min(base[p], flex_line)))
rep = pd.DataFrame(rows); rep.to_csv(OUT + '/replacement_lines.csv', index=False)
b = pd.read_csv(sys.argv[3]); b = b[(b.board == 'post') & (b['class'] <= 2023)].copy()
dp = pd.read_csv(S + '/dl/draft_picks.csv')[['season', 'pick', 'gsis_id']].rename(columns={'season': 'class'})
b = b.merge(dp, on=['class', 'pick'], how='left')
print('board rows', len(b), 'missing gsis', b.gsis_id.isna().sum())
def realized(r, v, col):
    K = min(5, 2025 - r['class'] + 1)
    h = ps[(ps.player_id == r.gsis_id) & (ps.season >= r['class']) & (ps.season < r['class'] + K)]
    ry = rep[(rep.season == r['class']) & (rep.pos == r.position)][col].iloc[0]
    k = h.season - r['class'] + 1
    return float((v ** k * h.g * (h.ppg - ry).clip(lower=0)).sum()), K
for v in [float(a) for a in sys.argv[4].split(',')]:
    b[f"real_ref_{v}"] = [realized(r, v, "rep_ref")[0] for _, r in b.iterrows()]
    b[f"real_flex_{v}"] = [realized(r, v, "rep_flex")[0] for _, r in b.iterrows()]
b['K'] = [min(5, 2025 - c + 1) for c in b['class']]
b.to_csv(OUT + '/players_raw.csv', index=False)
