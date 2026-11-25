"""pp_04_curve.py: the 2027 pick value curve. Our site pick values (1.01-4.12) vs the historical curve (mixed model,
2010-2026, same engine) vs the trade market (Dynasty Daddy Trade Database fit, Trade_Market tm.js: one generic "mid" price
per 2027 round). Market prices are put on our scale by rank: a pick the market ranks as its Nth asset gets the value of our
Nth player in the same league (12 teams, 0.5 PPR, superflex, no flex, the trade-market page's league).
Dynasty Daddy's public values API (checked 2026-11-25 in the built-in browser) lists no rookie picks, so there is no
separate DD pick price."""
import pandas as pd, numpy as np, json
import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
plt.rcParams.update({'figure.dpi': 130, 'axes.spines.top': False, 'axes.spines.right': False, 'axes.grid': True, 'grid.alpha': .3, 'font.size': 9.5})
P = pd.read_csv('outputs/pp_prospects.csv').merge(pd.read_csv('outputs/pp_values.csv'), on='id')
SP = pd.read_csv('outputs/pp_site_pick_values.csv'); B = pd.read_csv('outputs/pp_our_board.csv'); M = json.load(open('outputs/pp_market.json'))
lab = lambda s: f'{(s-1)//12+1}.{(s-1)%12+1:02d}'
def hist_curve(vcol):
    rows = []
    for c, d in P[(P.lens == 'mixed') & (P.cls <= 2026)].groupby('cls'):
        v = np.sort(d[vcol].values)[::-1][:48]; rows += [dict(cls=c, slot=k + 1, v=x) for k, x in enumerate(v)]
    H = pd.DataFrame(rows); return H, H.groupby('slot').v.agg(mean='mean', p10=lambda x: x.quantile(.1), p90=lambda x: x.quantile(.9))
# market: rank each pick among the market's players, then our value at that rank (market league)
mk = pd.DataFrame(M['rows'], columns=['name', 'pos', 'lv', 'n']).sort_values('lv', ascending=False).reset_index(drop=True)
bm = B[B.league == 'market'].sort_values('rank'); bs = B[B.league == 'sf'].sort_values('rank')
mp = []
for name, rd, lv, n in M['picks']:
    r = int((mk.lv > lv).sum()) + 1
    mp.append(dict(pick=name, round=rd, market_rank=r, trades=n, market_value_ours_scale=int(bm.value.iloc[r - 1]), market_value_sf_default=int(bs.value.iloc[r - 1])))
MP = pd.DataFrame(mp)
out = []
for lg, vcol in (('market', 'v_market'), ('sf', 'v_sf')):
    H, HC = hist_curve(vcol); o = SP[SP.league == lg].set_index('s').value
    for rd in range(1, 5):
        sl = range(12 * (rd - 1) + 1, 12 * rd + 1)
        mkt = MP.loc[MP['round'] == rd, 'market_value_ours_scale' if lg == 'market' else 'market_value_sf_default'].iloc[0]
        ours = o.loc[list(sl)].mean(); hist = HC.loc[list(sl), 'mean'].mean()
        # which 2027 slot does the market's generic pick buy?
        eq = int(np.argmin(np.abs(o.values - mkt))) + 1
        out.append(dict(league=lg, round=rd, ours_2027_round_avg=round(ours), ours_2027_mid_pick=round(o.loc[[12*(rd-1)+6, 12*(rd-1)+7]].mean()), hist_round_avg=round(hist),
                        market_mid_pick=mkt, model_minus_market_mid=round(o.loc[[12*(rd-1)+6, 12*(rd-1)+7]].mean() - mkt),
                        market_over_ours_mid=round(mkt / o.loc[[12*(rd-1)+6, 12*(rd-1)+7]].mean(), 2), market_price_equals_2027_slot=lab(eq)))
R = pd.DataFrame(out); R.to_csv('outputs/curve_vs_market.csv', index=False); MP.to_csv('outputs/market_picks.csv', index=False)
pd.set_option('display.width', 250); print(MP.to_string(index=False)); print(R.to_string(index=False))
# flatness: how much value is lost from 1.06 to 2.02, 1.09 to 2.06 etc. 2027 vs each past class
H, HC = hist_curve('v_sf'); o = SP[SP.league == 'sf'].set_index('s').value
fl = []
for a, b in ((6, 14), (5, 13), (9, 18), (13, 24), (19, 30), (25, 48)):
    hs = H.pivot(index='cls', columns='slot', values='v'); r = hs[b] / hs[a]
    fl.append(dict(from_pick=lab(a), to_pick=lab(b), keep_2027=round(o[b] / o[a], 2), keep_hist_median=round(r.median(), 2), keep_hist_min=round(r.min(), 2), keep_hist_max=round(r.max(), 2),
                   rank_2027_flattest_of_18=int((r > o[b] / o[a]).sum() + 1)))
FL = pd.DataFrame(fl); FL.to_csv('outputs/curve_flatness.csv', index=False); print(FL.to_string(index=False))
# chart 08: curve
fig, ax = plt.subplots(figsize=(11, 5.4)); x = np.arange(1, 49)
ax.fill_between(HC.index, HC.p10, HC.p90, color='#c9d3df', alpha=.6, label='Past classes 2010-26, 10th-90th pct')
ax.plot(HC.index, HC['mean'], color='#7f7f7f', lw=2, label='Past classes, average')
ax.plot(x, o.values, color='#1f4e79', lw=2.2, marker='o', ms=3, label='2027 picks, our values (site default league)')
for _, r in MP.iterrows():
    ax.scatter(12 * (r['round'] - 1) + 6.5, r.market_value_sf_default, marker='D', s=70, color='#e07b00', zorder=5, label='Trade market, generic 2027 "mid" pick' if r['round'] == 1 else None)
    ax.annotate(f"mid {['1st','2nd','3rd','4th'][r['round']-1]}\n{r.market_value_sf_default/1000:.1f}k", (12 * (r['round'] - 1) + 6.5, r.market_value_sf_default), xytext=(8, 6), textcoords='offset points', fontsize=8, color='#e07b00')
for v in (12.5, 24.5, 36.5): ax.axvline(v, color='#7f7f7f', lw=.8, ls=':')
ax.set_xticks([1, 4, 8, 12, 13, 18, 24, 25, 30, 36, 37, 42, 48]); ax.set_xticklabels([lab(s) for s in [1, 4, 8, 12, 13, 18, 24, 25, 30, 36, 37, 42, 48]], rotation=45)
ax.set_ylabel('Value (100k dynasty scale)'); ax.set_title('2027 pick value curve: our model vs past classes vs the trade market', loc='left', fontweight='bold'); ax.legend(frameon=False)
fig.tight_layout(); fig.savefig('charts/08_value_curve.png'); plt.close()
# chart 09: 2027 / history ratio by slot (where 2027 is above or below a normal class)
fig, ax = plt.subplots(figsize=(11, 3.8)); rr = o.values / HC['mean'].values
ax.bar(x, rr - 1, bottom=1, color=np.where(rr >= 1, '#2a9d8f', '#c44e52')); ax.axhline(1, color='#18212d', lw=.8)
for v in (12.5, 24.5, 36.5): ax.axvline(v, color='#7f7f7f', lw=.8, ls=':')
ax.set_xticks([1, 4, 8, 12, 13, 18, 24, 25, 30, 36, 37, 42, 48]); ax.set_xticklabels([lab(s) for s in [1, 4, 8, 12, 13, 18, 24, 25, 30, 36, 37, 42, 48]], rotation=45)
ax.set_ylabel('2027 value / past average'); ax.set_title('Each 2027 pick vs the same pick in an average class', loc='left', fontweight='bold')
fig.tight_layout(); fig.savefig('charts/09_ratio_by_slot.png'); plt.close()
