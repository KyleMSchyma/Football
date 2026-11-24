"""Trade adjustment research (Kyle 2026-11-24), step 0: Dynasty Daddy trades (Kyle has DD's permission) joined to OUR
point-in-time dynasty values. Raw trades stay on Kyle's PC / in the private staging area; this writes only an
anonymised trade table (no league ids, no transaction ids) to a local pickle that is NOT committed.
Scope: dynasty, superflex, 10-14 teams, 0.5 / 1 PPR, TE premium <= 1, no best ball, 6-14 starters, trades since
2026-09-08 (first 2026 value snapshot), players only (trades with any pick or unmapped asset dropped: our history
has no pick values), 1-3 assets a side. Our value = dynasty raw value (expected points over replacement 2026-2031,
reference league 12 teams SF full PPR no flex) from the latest snapshot on or before the trade date."""
import pandas as pd, numpy as np, json, glob, pyreadr, re, unicodedata
RAW = '/mnt/user-data/uploads/Football2/research/dd_trades/raw'
d = pd.concat([list(pyreadr.read_r(f).values())[0] for f in sorted(glob.glob(f'{RAW}/dynasty_2026-*.rds'))]).drop_duplicates('transaction_id')
d['when'] = pd.to_datetime(d.date.str[:19])
d = d[d.sf & d.teams.isin([10, 12, 14]) & d.ppr.isin([0.5, 1]) & (d.tep <= 1) & ~d.bestball & d.starters.between(6, 14) & (d.when >= '2026-09-08')]
print('compatible SF trades since 09-08:', len(d))
m = json.load(open('/home/user/prospect-actuary/data/sleeper_ids.json'))['m']
def norm(s): s = unicodedata.normalize('NFKD', s).encode('ascii', 'ignore').decode().lower(); return re.sub(r'[^a-z]', '', re.sub(r'\b(jr|sr|ii|iii|iv|v)\b\.?', '', s))
v = pd.read_csv('/home/user/Football/Trade_Values/history/values/values_2026.csv'); v = v[v.format == 'dynasty']
v['key'] = v.name.map(norm) + '|' + v.pos
sl = {k: norm(x.split('|')[0]) + '|' + x.split('|')[1] for k, x in m.items()}
dates = sorted(v.date.unique())
V = {dt: g.set_index('key').value for dt, g in v.groupby('date')}
rows = []
for t in d.itertuples():
    A = t.sidea.split('|'); B = t.sideb.split('|')
    if not (1 <= len(A) <= 3 and 1 <= len(B) <= 3): continue
    if any(x not in sl for x in A + B): continue
    snap = [x for x in dates if x <= str(t.when.date())]
    if not snap: continue
    vv = V[snap[-1]]
    ka = [sl[x] for x in A]; kb = [sl[x] for x in B]
    if any(k not in vv.index for k in ka + kb): continue
    rows.append(dict(when=t.when, snap=snap[-1], teams=t.teams, ppr=t.ppr, va=[float(vv[k]) for k in ka], vb=[float(vv[k]) for k in kb], ka=ka, kb=kb))
T = pd.DataFrame(rows); T.to_pickle('ta_trades.pkl')
T['shape'] = T.va.str.len().astype(str) + 'v' + T.vb.str.len().astype(str)
print(len(T), 'trades usable'); print(T['shape'].value_counts())
