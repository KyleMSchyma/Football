# Rerun the pick-strategy results with each of Kyle's leagues' scoring and lineups.
# Price stays the draft-time / history value of the reference league (what generic market values look like);
# production is rescored per league and scaled so all rookie picks 1.01-3.12 (2010-21) produced what they cost, per league.
# A ratio therefore says how a slot / position / age paid off in THAT league, against generic prices.
import pandas as pd, numpy as np, json, sys, glob, itertools
import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
OUT = '/mnt/project-files/research/rookie_pick_strategy'; S = sys.argv[1]; HIST = '/home/user/prospect-actuary/data/history'
V = .93; rng = np.random.default_rng(2026)
LEAGUES = {
 'Reference (12, SF, PPR, no flex)': dict(n=12, flex=0, rec=dict(QB=1, RB=1, WR=1, TE=1), ptd=4, fd=dict(QB=0, RB=0, WR=0, TE=0)),
 'Site default (12, SF, PPR, 2 flex)': dict(n=12, flex=2, rec=dict(QB=1, RB=1, WR=1, TE=1), ptd=4, fd=dict(QB=0, RB=0, WR=0, TE=0)),
 'League of Lampoons': dict(n=10, flex=2, rec=dict(QB=.5, RB=.5, WR=.5, TE=.5), ptd=6, fd=dict(QB=0, RB=0, WR=0, TE=0)),
 'Dynasty Confederates': dict(n=12, flex=2, rec=dict(QB=.5, RB=.5, WR=.5, TE=1.0), ptd=6, fd=dict(QB=0, RB=.25, WR=.5, TE=1.0)),
}
raw = pd.concat([pd.read_csv(f, low_memory=False) for f in sorted(glob.glob(S + '/dl/ps_*.csv'))])
raw = raw[raw.position.isin(['QB', 'RB', 'WR', 'TE'])].fillna({c: 0 for c in ['receptions', 'passing_tds', 'rushing_first_downs', 'receiving_first_downs']})
raw = raw.groupby(['player_id', 'season'], as_index=False).agg(pos=('position', 'first'), g=('games', 'sum'), ppr=('fantasy_points_ppr', 'sum'), rec=('receptions', 'sum'),
      ptd=('passing_tds', 'sum'), fd=('rushing_first_downs', 'sum'), fd2=('receiving_first_downs', 'sum'))
P = pd.read_csv(OUT + '/players.csv'); P = P[(P['class'] <= 2021) & (P.slot <= 36)].copy()
SP = pd.read_csv(OUT + '/spend_players.csv'); VT = SP[SP.kind == 'Veteran'][['name', 'gid', 'pos', 'Y', 'price', 'age', 'agegrp', 'band']].copy()
GROUPS = [(1, 1, '1.01'), (2, 3, '1.02-1.03'), (4, 6, '1.04-1.06'), (7, 9, '1.07-1.09'), (10, 12, '1.10-1.12'), (13, 18, '2.01-2.06'), (19, 24, '2.07-2.12'), (25, 36, '3.01-3.12')]
P['grp'] = P.slot.map(lambda s: next(l for lo, hi, l in GROUPS if lo <= s <= hi))
def boot(d, f, key='class', n=1000):
    ys = d[key].unique(); g = {k: v for k, v in d.groupby(key)}
    return np.percentile([f(pd.concat([g[k] for k in rng.choice(ys, len(ys))])) for _ in range(n)], [2.5, 97.5])
res = {}
for L, cfg in LEAGUES.items():
    ps = raw.copy(); r = ps.pos.map(cfg['rec']); f = ps.pos.map(cfg['fd'])
    ps['pts'] = ps.ppr - (1 - r) * ps.rec + (cfg['ptd'] - 4) * ps.ptd + f * (ps.fd + ps.fd2)
    ps['ppg'] = ps.pts / ps.g.clip(lower=1)
    n = cfg['n']; N = dict(QB=2 * n, RB=2 * n, WR=3 * n, TE=n); rep = {}
    for y, d in ps[ps.g >= 6].groupby('season'):
        base = {}; rest = []
        for p_, k in N.items():
            z = d[d.pos == p_].sort_values('ppg', ascending=False); base[p_] = z.ppg.iloc[k - 1]; rest.append(z.iloc[k:])
        fl = pd.concat(rest[1:]).sort_values('ppg', ascending=False).ppg.iloc[cfg['flex'] * n - 1] if cfg['flex'] else 99
        for p_ in N: rep[(y, p_)] = base[p_] if p_ == 'QB' else min(base[p_], fl)
    PS = {k: v for k, v in ps.groupby('player_id')}
    def prod(gid, pos, Y):
        out = np.zeros(5); h = PS.get(gid)
        if h is None or not isinstance(gid, str): return out
        for _, x in h[(h.season >= Y) & (h.season < Y + 5)].iterrows():
            k = int(x.season - Y + 1); out[k - 1] = V ** k * x.g * max(x.ppg - rep[(Y, pos)], 0)
        return out
    rk = P.copy(); a = np.array([prod(g_, p_, y) for g_, p_, y in zip(rk.gsis_id, rk.position, rk['class'])])
    C = rk.value_100k.sum() / a.sum(); rk['now'] = a[:, :2].sum(1) * C; rk['later'] = a[:, 2:].sum(1) * C; rk['prod'] = rk.now + rk.later
    vt = VT.copy(); b = np.array([prod(g_, p_, y) for g_, p_, y in zip(vt.gid, vt.pos, vt.Y)]) * C
    vt['now'] = b[:, :2].sum(1); vt['later'] = b[:, 2:].sum(1); vt['prod'] = vt.now + vt.later
    rk.to_csv(f"{OUT}/league_{L.split(' (')[0].replace(' ', '_').lower()}_rookies.csv", index=False)
    R = dict(C=C, rep=pd.Series(rep).unstack().loc[2016:2025].mean().round(1).to_dict())
    # slot groups
    R['slots'] = pd.DataFrame([dict(group=l, ratio=d['prod'].sum() / d.value_100k.sum(), median=d['prod'].median(), bust=(d['prod'] < .1 * d.value_100k).mean(),
                                    share=d['prod'].sum() / rk['prod'].sum()) for l, d in rk.groupby('grp', sort=False)]).set_index('group').reindex([g[2] for g in GROUPS])
    # trade-down
    td = {}
    for top in (1, 2, 3):
        for nm, r1, r2 in [('two random 1sts', (2, 12), (2, 12)), ('two mid 1sts (1.05-1.08)', (5, 8), (5, 8)), ('two late 1sts', (9, 12), (9, 12)), ('late 1st + early 2nd', (9, 12), (13, 18))]:
            w = []
            for _, z in rk.groupby('class'):
                v1 = z[z.slot == top]['prod'].sum(); A_ = z[z.slot.between(*r1) & (z.slot != top)]; B_ = z[z.slot.between(*r2) & (z.slot != top)]
                w += [v1 > i + j for (si, i), (sj, j) in itertools.product(zip(A_.slot, A_['prod']), zip(B_.slot, B_['prod'])) if si < sj]
            td[(f'1.0{top}', nm)] = np.mean(w)
    R['td'] = pd.Series(td).unstack(0)
    # position x round (rookies) and age/price (veterans)
    rk['rd'] = (rk.slot - 1) // 12 + 1
    R['pos'] = pd.DataFrame([dict(rd=k[0], pos=k[1], n=len(d), ratio=d['prod'].sum() / d.value_100k.sum(), lo_hi=boot(d, lambda q: q['prod'].sum() / q.value_100k.sum(), n=500))
                             for k, d in rk.groupby(['rd', 'position']) if len(d) >= 5])
    R['rpos'] = rk.groupby('position').apply(lambda d: d['prod'].sum() / d.value_100k.sum(), include_groups=False)
    allv = pd.concat([rk.assign(agegrp='Rookie pick', Y=rk['class'], price=rk.value_100k, pos=rk.position,
                                band=pd.cut(rk.value_100k, [2000, 5000, 10000, 20000, 35000, 60000], labels=['2-5k', '5-10k', '10-20k', '20-35k', '35-60k'], right=False).astype(str)), vt])
    allv = allv[allv.band.isin(['2-5k', '5-10k', '10-20k', '20-35k', '35-60k'])]
    R['ageband'] = allv.groupby(['agegrp', 'band']).apply(lambda d: d['prod'].sum() / d.price.sum(), include_groups=False).unstack().reindex(columns=['2-5k', '5-10k', '10-20k', '20-35k', '35-60k'])
    R['agepos'] = allv.groupby(['agegrp', 'pos']).apply(lambda d: d['prod'].sum() / d.price.sum(), include_groups=False).unstack()
    R['nowlater'] = allv.groupby('agegrp').apply(lambda d: pd.Series(dict(now=d.now.sum() / d.price.sum(), later=d.later.sum() / d.price.sum())), include_groups=False)
    R['vet_overall'] = vt['prod'].sum() / vt.price.sum()
    res[L] = R
    print('=' * 20, L, 'C', round(C, 1), 'avg replacement PPG 2016-25', R['rep'], 'veterans overall', round(R['vet_overall'], 2))
    print(R['slots'].round(2).to_string()); print(R['td'].round(2).to_string()); print(R['rpos'].round(2).to_string())
    print(R['pos'].assign(lo=lambda d: d.lo_hi.str[0], hi=lambda d: d.lo_hi.str[1]).drop(columns='lo_hi').round(2).to_string(index=False))
    print(R['ageband'].round(2).to_string()); print(R['agepos'].round(2).to_string()); print(R['nowlater'].round(2).to_string())
pd.to_pickle(res, OUT + '/league_results.pkl')
# comparison tables
names = list(LEAGUES)
cmp_slots = pd.concat({n.split(' (')[0]: res[n]['slots'].ratio for n in names}, axis=1); cmp_slots.to_csv(OUT + '/league_cmp_slots.csv')
cmp_td = pd.concat({n.split(' (')[0]: res[n]['td'].stack() for n in names}, axis=1); cmp_td.to_csv(OUT + '/league_cmp_tradedown.csv')
cmp_ab = pd.concat({n.split(' (')[0]: res[n]['ageband'].stack() for n in names}, axis=1); cmp_ab.to_csv(OUT + '/league_cmp_ageband.csv')
cmp_ap = pd.concat({n.split(' (')[0]: res[n]['agepos'].stack() for n in names}, axis=1); cmp_ap.to_csv(OUT + '/league_cmp_agepos.csv')
cmp_pr = pd.concat({n.split(' (')[0]: res[n]['pos'].set_index(['rd', 'pos']).ratio for n in names}, axis=1); cmp_pr.to_csv(OUT + '/league_cmp_posround.csv')
# charts
cl = ['#9aa6b5', '#7f7f7f', '#e07b00', '#1f4e79']; sh = [n.split(' (')[0] for n in names]
def bars(df, title, fn, xl):
    fig, ax = plt.subplots(figsize=(12, 5)); x = np.arange(len(df)); w = .2
    for i, (c, col) in enumerate(zip(df.columns, cl)): ax.bar(x + (i - 1.5) * w, df[c], w, color=col, label=c)
    ax.axhline(1 if 'win' not in fn else .5, color='#555', ls='--', lw=.8); ax.set_xticks(x); ax.set_xticklabels(xl, fontsize=8.5)
    ax.set_title(title, loc='left', fontweight='bold'); ax.legend(frameon=False, ncol=4, fontsize=8.5); fig.tight_layout(); fig.savefig(OUT + '/charts/' + fn); plt.close()
plt.rcParams.update({'figure.dpi': 130, 'axes.spines.top': False, 'axes.spines.right': False, 'axes.grid': True, 'grid.alpha': .3, 'font.size': 10})
bars(cmp_slots, 'Return on price by pick range, by league (production / generic price)', '15_league_slots.png', cmp_slots.index)
bars(cmp_td, 'Share of cases the kept pick beat the two-pick package, by league', '16_league_tradedown_win.png', [f'Keep {b}\nvs {a}' for a, b in cmp_td.index])
q = cmp_pr; bars(q, 'Rookie picks: return on price by position and round, by league', '17_league_position_round.png', [f'Rd {a} {b}' for a, b in q.index])
q = cmp_ab.loc[['Rookie pick', 'Vet 24 or younger', 'Vet 25-27', 'Vet 28+']]; bars(q, 'Rookie picks vs veterans at the same price, by league', '18_league_age_price.png', [f'{a.replace("Rookie pick", "Pick").replace("Vet 24 or younger", "Vet<=24")}\n{b}' for a, b in q.index])
q = cmp_ap.loc[['Rookie pick', 'Vet 24 or younger', 'Vet 25-27', 'Vet 28+']]; bars(q, 'Return on price by buy type and position, by league', '19_league_age_position.png', [f'{a.replace("Rookie pick", "Pick").replace("Vet 24 or younger", "Vet<=24")}\n{b}' for a, b in q.index])
