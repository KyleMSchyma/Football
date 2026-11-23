# What to spend picks on: at the same 100k price, how did rookies by position compare with veterans by position and age?
# Veterans: dynasty value at the end of season Y-1 (point-in-time history, week 17), Y = 2017..2021, so 5 later seasons are known.
# Rookies: classes 2010-2021, slots 1-36, draft-time price. Production for both: seasons Y..Y+4, v=0.93, points over the
# season-Y replacement line (reference league), times the same 100k scale (216.2) as the slot study.
import pandas as pd, numpy as np, json, sys, glob
import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
OUT = '/mnt/project-files/research/rookie_pick_strategy'; S = sys.argv[1]; HIST = '/home/user/prospect-actuary/data/history'
C = 216.2; V = .93; rng = np.random.default_rng(2026)
plt.rcParams.update({'figure.dpi': 130, 'axes.spines.top': False, 'axes.spines.right': False, 'axes.grid': True, 'grid.alpha': .3, 'font.size': 10})
ps = pd.concat([pd.read_csv(f, low_memory=False) for f in sorted(glob.glob(S + '/dl/ps_*.csv'))])
ps = ps[ps.position.isin(['QB', 'RB', 'WR', 'TE'])].groupby(['player_id', 'season'], as_index=False).agg(g=('games', 'sum'), pts=('fantasy_points_ppr', 'sum'))
ps['ppg'] = ps.pts / ps.g.clip(lower=1)
rep = pd.read_csv(OUT + '/replacement_lines.csv').set_index(['season', 'pos']).rep_ref
PS = {k: v for k, v in ps.groupby('player_id')}
def prod(gid, pos, Y):
    h = PS.get(gid); out = np.zeros(5)
    if h is None: return out
    ry = rep[(Y, pos)]
    for _, r in h[(h.season >= Y) & (h.season < Y + 5)].iterrows():
        k = int(r.season - Y + 1); out[k - 1] = V ** k * r.g * max(r.ppg - ry, 0) * C
    return out
pl = pd.read_csv(S + '/dl/players.csv', low_memory=False)[['gsis_id', 'birth_date']].dropna(); bd = dict(zip(pl.gsis_id, pd.to_datetime(pl.birth_date, errors='coerce')))
# veterans
ix = pd.DataFrame(json.load(open(HIST + '/index.json'))['snapshots']); last = ix.groupby('season').i.max().to_dict()
rows = []
for p in json.load(open(HIST + '/values.json'))['players']:
    s = {a[0]: a[1] for a in p['s'] if a[1]}
    for Y in range(2017, 2022):
        v = s.get(last[Y - 1])
        if not v: continue
        b = bd.get(p['g']); age = (pd.Timestamp(f'{Y}-09-01') - b).days / 365.25 if b is not None and not pd.isna(b) else np.nan
        pr = prod(p['g'], p['p'], Y)
        rows.append(dict(kind='Veteran', name=p['n'], gid=p['g'], pos=p['p'], Y=Y, price=v, age=age, **{f'y{k+1}': pr[k] for k in range(5)}))
VT = pd.DataFrame(rows)
# rookies
P = pd.read_csv(OUT + '/players.csv'); P = P[(P['class'] <= 2021) & (P.slot <= 36)]
rows = []
for _, r in P.iterrows():
    pr = prod(r.gsis_id, r.position, r['class']) if isinstance(r.gsis_id, str) else np.zeros(5)
    rows.append(dict(kind='Rookie', name=r['name'], gid=r.gsis_id, pos=r.position, Y=r['class'], price=r.value_100k, age=r.age, slot=r.slot, **{f'y{k+1}': pr[k] for k in range(5)}))
RK = pd.DataFrame(rows)
D = pd.concat([RK, VT], ignore_index=True)
D['total'] = D[[f'y{k}' for k in range(1, 6)]].sum(1); D['now'] = D.y1 + D.y2; D['later'] = D.y3 + D.y4 + D.y5
D['agegrp'] = np.where(D.kind == 'Rookie', 'Rookie pick', pd.cut(D.age, [0, 24.99, 27.99, 99], labels=['Vet 24 or younger', 'Vet 25-27', 'Vet 28+']).astype(str))
BANDS = [2000, 5000, 10000, 20000, 35000, 60000]; LB = ['2-5k', '5-10k', '10-20k', '20-35k', '35-60k']
D['band'] = pd.cut(D.price, BANDS, labels=LB, right=False)
D = D[D.band.notna()]; D.to_csv(OUT + '/spend_players.csv', index=False)
# check: veteran 100k scale vs production overall (all vets, all prices) so the two prices are on comparable footing
print('overall produced/price: rookies %.2f, veterans %.2f' % (RK.pipe(lambda d: (d[[f"y{k}" for k in range(1,6)]].sum(1)).sum() / d.price.sum()),
      VT.pipe(lambda d: (d[[f"y{k}" for k in range(1,6)]].sum(1)).sum() / d.price.sum())))
def ratio(d, col='total'): return d[col].sum() / d.price.sum()
def ci(d, col='total', n=1000):
    ys = d.Y.unique(); g = {k: v for k, v in d.groupby('Y')}
    b = [ratio(pd.concat([g[k] for k in rng.choice(ys, len(ys))]), col) for _ in range(n)]
    return np.percentile(b, [2.5, 97.5])
def table(by):
    out = []
    for key, d in D.groupby(by, observed=True):
        if len(d) < 8: continue
        lo, hi = ci(d)
        out.append(dict(zip(by, key if isinstance(key, tuple) else (key,)), n=len(d), price=d.price.mean(), ratio=ratio(d), lo=lo, hi=hi,
                        now=ratio(d, 'now'), later=ratio(d, 'later'), bust=(d.total < .1 * d.price).mean()))
    return pd.DataFrame(out)
pd.set_option('display.width', 250)
T1 = table(['kind', 'pos']); T2 = table(['agegrp']); T3 = table(['agegrp', 'band']); T4 = table(['kind', 'pos', 'band']); T5 = table(['agegrp', 'pos'])
for n, t in [('kind_pos', T1), ('age', T2), ('age_band', T3), ('kind_pos_band', T4), ('age_pos', T5)]:
    t.to_csv(f'{OUT}/spend_{n}.csv', index=False); print('=====', n); print(t.round(2).to_string(index=False))
# charts
cols = {'QB': '#1f4e79', 'RB': '#e07b00', 'WR': '#2a9d8f', 'TE': '#9b5de5'}
fig, axs = plt.subplots(1, 2, figsize=(13, 5), sharey=True)
for ax, kd in zip(axs, ['Rookie', 'Veteran']):
    t = T1[T1.kind == kd]; x = np.arange(len(t))
    ax.bar(x, t.ratio, color=[cols[p] for p in t.pos]); ax.errorbar(x, t.ratio, yerr=[t.ratio - t.lo, t.hi - t.ratio], fmt='none', color='k', capsize=3)
    ax.axhline(1, color='#7f7f7f', ls='--'); ax.set_xticks(x); ax.set_xticklabels([f'{p}\n(n={n})' for p, n in zip(t.pos, t.n)])
    ax.set_title(f'{kd}s: production / price by position', loc='left', fontweight='bold')
axs[0].set_ylabel('Produced over next 5 seasons / price (1.0 = paid back)')
fig.text(.01, .01, 'Rookies: rookie-draft slots 1.01-3.12, classes 2010-2021. Veterans: value at the end of 2016-2020, production 2017-2025. Prices 2k-60k on the 100k scale.', fontsize=8, color='#7f7f7f')
fig.tight_layout(); fig.savefig(OUT + '/charts/12_spend_by_position.png'); plt.close()
order = ['Rookie pick', 'Vet 24 or younger', 'Vet 25-27', 'Vet 28+']; cc = ['#18212d', '#2a9d8f', '#1f4e79', '#e07b00']
fig, ax = plt.subplots(figsize=(11, 5)); w = .2
for i, (g_, c) in enumerate(zip(order, cc)):
    t = T3[T3.agegrp == g_].set_index('band').reindex(LB)
    x = np.arange(len(LB)) + (i - 1.5) * w
    ax.bar(x, t.ratio, w, color=c, label=g_); ax.errorbar(x, t.ratio, yerr=[t.ratio - t.lo, t.hi - t.ratio], fmt='none', color='#555', capsize=2, lw=.8)
ax.axhline(1, color='#7f7f7f', ls='--'); ax.set_xticks(range(len(LB))); ax.set_xticklabels(LB); ax.set_xlabel('Price (100k scale)'); ax.set_ylabel('Produced (5 seasons) / price')
ax.set_title('Same price, different buys: rookie picks vs veterans by age', loc='left', fontweight='bold'); ax.legend(frameon=False)
fig.tight_layout(); fig.savefig(OUT + '/charts/13_spend_by_age_and_price.png'); plt.close()
fig, ax = plt.subplots(figsize=(10, 4.6)); t = T2.set_index('agegrp').reindex(order); x = np.arange(len(order))
ax.bar(x - .18, t.now, .36, color='#e07b00', label='Seasons 1-2 (production now)'); ax.bar(x + .18, t.later, .36, color='#1f4e79', label='Seasons 3-5 (future value)')
ax.set_xticks(x); ax.set_xticklabels(order); ax.set_ylabel('Produced / price'); ax.legend(frameon=False)
ax.set_title('When the value arrives: now vs later, per unit of price', loc='left', fontweight='bold')
fig.tight_layout(); fig.savefig(OUT + '/charts/14_now_vs_later.png'); plt.close()
