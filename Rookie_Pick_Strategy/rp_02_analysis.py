# Rookie pick strategy: which rookie-draft slots return the most value for their price, and does trading down pay.
import pandas as pd, numpy as np, json, sys
OUT = sys.argv[1]; HIST = sys.argv[2]; GR = sys.argv[3]; V = '0.93'
b = pd.read_csv(OUT + '/players_raw.csv')
b['real_ref'] = b[f'real_ref_{V}'].fillna(0); b['real_flex'] = b[f'real_flex_{V}'].fillna(0)
# rookie-draft slot = order of draft-time value within the class (all drafted QB/RB/WR/TE)
b = b.sort_values(['class', 'value_100k'], ascending=[True, False])
b['slot'] = b.groupby('class').cumcount() + 1
# NFL-draft-order slot (alternative ADP proxy)
b['slot_nfl'] = b.groupby('class')['pick'].rank(method='first').astype(int)
b['rd'] = (b.slot - 1) // 12 + 1; b['sl'] = b.rd.astype(str) + '.' + ((b.slot - 1) % 12 + 1).map('{:02d}'.format)
# hits (pd_post_player_grades: nfl_tier 1 = top tier, <=3 = any tier, first 3 seasons; QB8/16/24, RB8/16/24, WR12/24/36, TE6/12/18)
g = pd.read_csv(GR)[['position', 'class', 'pick', 'nfl_tier', 'nfl_best_finish', 'outcome_complete']]
b = b.merge(g, on=['position', 'class', 'pick'], how='left')
# asset lens: dynasty trade value (100k) held at the end of season 1, 2 and 3 (point-in-time history, reference league)
ix = pd.DataFrame(json.load(open(HIST + '/index.json'))['snapshots'])
last = ix.groupby('season').i.max().to_dict()
H = {}
for p in json.load(open(HIST + '/values.json'))['players']:
    H[p['g']] = {s[0]: (s[1] or 0) for s in p['s']}
for y in (1, 2, 3):
    b[f'asset_y{y}'] = [(H.get(gid, {}).get(last.get(c + y - 1), 0) if (c + y - 1) in last and c >= 2016 else np.nan) for gid, c in zip(b.gsis_id, b['class'])]
b.to_csv(OUT + '/players.csv', index=False)
