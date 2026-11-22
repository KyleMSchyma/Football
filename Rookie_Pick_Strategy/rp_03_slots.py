# Slot-level results, trade-down tests, position splits, charts.
import pandas as pd, numpy as np, sys, os, itertools
import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
import statsmodels.api as sm, statsmodels.formula.api as smf
OUT = sys.argv[1]; CH = OUT + '/charts/'; os.makedirs(CH, exist_ok=True)
rng = np.random.default_rng(2026)
b = pd.read_csv(OUT + '/players.csv')
plt.rcParams.update({'figure.dpi': 130, 'axes.spines.top': False, 'axes.spines.right': False, 'axes.grid': True, 'grid.alpha': .3, 'font.size': 10})
C1, C2, C3, C4 = '#1f4e79', '#e07b00', '#7f7f7f', '#2a9d8f'
P = b[(b['class'] <= 2021) & (b.slot <= 36)].copy()            # production lens: 12 classes, 5 full seasons
A = b[(b['class'].between(2016, 2023)) & (b.slot <= 36)].copy()  # asset lens: value held after season 3
Hh = b[(b['class'] <= 2023) & (b.slot <= 36)].copy()            # hit lens
# 100k scaling: across all 36 slots of 2010-2021, what was produced = what was paid
for col, lab in [('real_ref', 'prod'), ('real_flex', 'prodflex')]:
    c = P.value_100k.sum() / P[col].sum(); P[lab] = P[col] * c; b[lab] = b[col] * c
    print(f'{lab}: 100k per raw point-over-replacement unit = {c:.1f}')
GROUPS = [(1, 1, '1.01'), (2, 3, '1.02-1.03'), (4, 6, '1.04-1.06'), (7, 9, '1.07-1.09'), (10, 12, '1.10-1.12'),
          (13, 18, '2.01-2.06'), (19, 24, '2.07-2.12'), (25, 36, '3.01-3.12')]
def grp(s):
    for lo, hi, l in GROUPS:
        if lo <= s <= hi: return l
for d in (P, A, Hh, b): d['grp'] = d.slot.map(grp)
def boot(d, f, n=2000):
    cl = d['class'].unique(); bys = {k: v for k, v in d.groupby('class')}
    out = [f(pd.concat([bys[k] for k in rng.choice(cl, len(cl))])) for _ in range(n)]
    return np.percentile(out, [2.5, 97.5])
# ---------- 1. slot table ----------
rows = []
for lo, hi, l in GROUPS:
    p = P[P.grp == l]; a = A[A.grp == l]; h = Hh[Hh.grp == l]
    r = dict(group=l, slots=f'{lo}-{hi}', price=p.value_100k.mean(), produced=p['prod'].mean(), ratio=p['prod'].sum() / p.value_100k.sum())
    r['ratio_lo'], r['ratio_hi'] = boot(p, lambda z: z['prod'].sum() / z.value_100k.sum())
    r['produced_flex_ratio'] = p['prodflex'].sum() / p.value_100k.sum() * P.value_100k.sum() / P['prodflex'].sum() * 1
    r['median_produced'] = p['prod'].median(); r['bust_rate'] = (p['prod'] < 0.1 * p.value_100k).mean()
    r['price_a'] = a.value_100k.mean(); r['asset_y3'] = a.asset_y3.mean(); r['asset_ratio'] = a.asset_y3.sum() / a.value_100k.sum()
    r['asset_lo'], r['asset_hi'] = boot(a, lambda z: z.asset_y3.sum() / z.value_100k.sum())
    r['hit_top'] = (h.nfl_tier == 1).mean(); r['hit_any'] = (h.nfl_tier <= 3).mean(); r['n_prod'] = len(p); r['n_hit'] = len(h)
    rows.append(r)
T = pd.DataFrame(rows); T.to_csv(OUT + '/slot_groups.csv', index=False)
pd.set_option('display.width', 250); print(T.round(3).to_string(index=False))
# per-slot
ps = []
for s in range(1, 37):
    p = P[P.slot == s]; a = A[A.slot == s]; h = Hh[Hh.slot == s]
    ps.append(dict(slot=s, label=f'{(s-1)//12+1}.{(s-1)%12+1:02d}', price=p.value_100k.mean(), produced=p['prod'].mean(), produced_median=p['prod'].median(),
                   produced_flex=p['prodflex'].mean(), asset_y3=a.asset_y3.mean(), price_a=a.value_100k.mean(),
                   hit_top=(h.nfl_tier == 1).mean(), hit_any=(h.nfl_tier <= 3).mean(),
                   pos_mix='/'.join(f'{k}{v}' for k, v in h.position.value_counts().items())))
S = pd.DataFrame(ps); S.to_csv(OUT + '/per_slot.csv', index=False); print(S.round(2).to_string(index=False))
# ---------- charts 1-4 ----------
x = S.slot
def smooth(y, w=3): return pd.Series(y).rolling(w, center=True, min_periods=1).mean()
fig, ax = plt.subplots(figsize=(11, 5.5))
ax.plot(x, S.price, '-', color=C1, lw=2.2, label='Price at draft time (our pick value)')
ax.scatter(x, S.produced, color=C2, s=22, alpha=.6, label='Produced, each slot (mean of 12 classes)')
ax.plot(x, smooth(S.produced), color=C2, lw=2.2, label='Produced, 3-slot rolling mean')
ax.plot(x, smooth(S.produced_median), color=C2, lw=1.2, ls=':', label='Produced, median (typical outcome)')
for v in (12.5, 24.5): ax.axvline(v, color=C3, lw=.8, ls='--')
ax.set_xticks([1, 3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 33, 36]); ax.set_xticklabels([S.label[i - 1] for i in [1, 3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 33, 36]])
ax.set_ylabel('Value (100k scale)'); ax.set_title('What each rookie pick cost vs what it produced (2010-2021 classes, first 5 seasons)', loc='left', fontweight='bold')
ax.legend(frameon=False); fig.text(.01, .005, 'Produced = fantasy points over replacement, 12-team SF full PPR, scaled so all 36 picks together produced what they cost.', fontsize=8, color=C3)
fig.tight_layout(); fig.savefig(CH + '01_price_vs_produced_by_slot.png'); plt.close()
fig, ax = plt.subplots(figsize=(10, 5)); yy = np.arange(len(T))[::-1]
ax.errorbar(T.ratio, yy, xerr=[T.ratio - T.ratio_lo, T.ratio_hi - T.ratio], fmt='o', color=C1, capsize=3, label='Production, first 5 seasons (2010-21)')
ax.errorbar(T.asset_ratio, yy - .25, xerr=[T.asset_ratio - T.asset_lo, T.asset_hi - T.asset_ratio], fmt='s', color=C4, capsize=3, label='Trade value held after season 3 (2016-23)')
ax.axvline(1, color=C3, ls='--'); ax.set_yticks(yy - .12); ax.set_yticklabels(T.group)
ax.set_xlabel('Return per unit of price (1.0 = got what you paid for)'); ax.legend(frameon=False, loc='lower right')
ax.set_title('Return on price by pick range (bars: 95% bootstrap over draft classes)', loc='left', fontweight='bold')
fig.text(.01, .005, 'Trade-value lens is on its own scale (value held / price): compare ranges within one colour, not the two colours to each other.', fontsize=8, color=C3)
fig.tight_layout(); fig.savefig(CH + '02_return_on_price_by_range.png'); plt.close()
fig, ax = plt.subplots(figsize=(11, 5))
ax.bar(x - .2, S.hit_any, .4, color=C4, label='Any tier hit (QB24 / RB24 / WR36 / TE18 season)')
ax.bar(x + .2, S.hit_top, .4, color=C1, label='Top tier hit (QB8 / RB8 / WR12 / TE6 season)')
ax.plot(x, smooth(S.hit_any, 5), color=C4, lw=1.5); ax.plot(x, smooth(S.hit_top, 5), color=C1, lw=1.5)
for v in (12.5, 24.5): ax.axvline(v, color=C3, lw=.8, ls='--')
ax.set_xticks(range(1, 37, 3)); ax.set_xticklabels(S.label[::3]); ax.set_ylim(0, 1.02); ax.set_ylabel('Share of players (2010-2023, n = 14 per slot)')
ax.set_title('Hit rate by rookie draft slot (best finish in first 3 seasons); lines = 5-slot rolling mean', loc='left', fontweight='bold'); ax.legend(frameon=False)
fig.tight_layout(); fig.savefig(CH + '03_hit_rate_by_slot.png'); plt.close()
fig, ax = plt.subplots(figsize=(11, 5.5))
for s in range(1, 37):
    v = P[P.slot == s]['prod']; ax.scatter(np.full(len(v), s) + rng.uniform(-.25, .25, len(v)), v, s=14, color=C1 if s <= 12 else (C4 if s <= 24 else C3), alpha=.6)
ax.plot(x, S.price, color=C2, lw=2, label='Price'); ax.set_yscale('symlog', linthresh=5000)
ax.set_xticks(range(1, 37, 3)); ax.set_xticklabels(S.label[::3]); ax.set_ylabel('Produced value, 100k scale (log above 5k)')
ax.set_title('Every pick, every class: outcomes are boom or bust at every slot', loc='left', fontweight='bold'); ax.legend(frameon=False)
fig.tight_layout(); fig.savefig(CH + '04_every_pick_outcomes.png'); plt.close()
# concentration
srt = np.sort(P['prod'].values)[::-1]; print('share of all produced value from top 10% / 25% of the 432 picks:', srt[:43].sum() / srt.sum(), srt[:108].sum() / srt.sum())
# ---------- 5. trade-down ----------
SC = [('Two random 1sts (1.02-1.12)', (2, 12), (2, 12)), ('Early + mid 1st (1.02-1.06 and 1.07-1.12)', (2, 6), (7, 12)),
      ('Two mid 1sts (1.05-1.08)', (5, 8), (5, 8)), ('Two late 1sts (1.09-1.12)', (9, 12), (9, 12)),
      ('Late 1st + early 2nd (1.09-1.12 and 2.01-2.06)', (9, 12), (13, 18)), ('Two early 2nds (2.01-2.06)', (13, 18), (13, 18))]
def td(d, col, top=1):
    res = []
    for name, r1, r2 in SC:
        win = []; diff = []; pw = []
        for k, z in d.groupby('class'):
            v1 = z[z.slot == top][col].sum(); pr1 = z[z.slot == top].value_100k.sum()
            a = z[z.slot.between(*r1)]; c = z[z.slot.between(*r2)]
            for (_, i), (_, j) in itertools.product(a.iterrows(), c.iterrows()):
                if i.slot >= j.slot: continue
                s2 = i[col] + j[col]; win.append(v1 > s2); diff.append(v1 - s2); pw.append(pr1 - (i.value_100k + j.value_100k))
        res.append(dict(scenario=name, p_top_wins=np.mean(win), mean_gap_produced=np.mean(diff), mean_gap_price=np.mean(pw), n_pairs=len(win)))
    return pd.DataFrame(res)
out = []
for top, nm in [(1, '1.01'), (2, '1.02'), (3, '1.03')]:
    t = td(P, 'prod', top); t['keep'] = nm; t['lens'] = 'production 5 seasons'; out.append(t)
    t = td(A, 'asset_y3', top); t['keep'] = nm; t['lens'] = 'trade value after season 3'; out.append(t)
TD = pd.concat(out); TD.to_csv(OUT + '/trade_down.csv', index=False); print(TD.round(3).to_string(index=False))
# bootstrap: P(1.01 beats two random 1sts) with class resampling
def pw(d, col):
    w = []
    for k, z in d.groupby('class'):
        v1 = z[z.slot == 1][col].sum(); o = z[z.slot.between(2, 12)][col].values
        w += [v1 > o[i] + o[j] for i in range(len(o)) for j in range(i + 1, len(o))]
    return np.mean(w)
print('P(1.01 > two random 1sts) production', pw(P, 'prod'), boot(P, lambda z: pw(z.assign(**{'class': np.arange(len(z)) // 36}), 'prod'), 500))
# per-class table 1.01 vs best/avg pairs
pc = []
for k, z in P.groupby('class'):
    t = z[z.slot == 1].iloc[0]; o = z[z.slot.between(2, 12)].sort_values('slot')
    pc.append(dict(cls=k, pick_101=f'{t["name"]} ({t.position})', produced_101=t['prod'], price_101=t.value_100k,
                   avg_two_1sts=2 * o['prod'].mean(), mid_pair_105_108=o[o.slot.between(5, 8)]['prod'].mean() * 2,
                   best_later_1st=f'{o.loc[o["prod"].idxmax(), "name"]} {o.loc[o["prod"].idxmax(), "sl"]}', best_later_prod=o['prod'].max()))
PC = pd.DataFrame(pc); PC.to_csv(OUT + '/per_class_101.csv', index=False); print(PC.round(0).to_string(index=False))
t = TD[TD.keep == '1.01']
fig, axs = plt.subplots(1, 2, figsize=(13, 4.8), sharey=True)
for ax, l, c in zip(axs, ['production 5 seasons', 'trade value after season 3'], [C1, C4]):
    z = t[t.lens == l]; yy = np.arange(len(z))[::-1]
    ax.barh(yy, z.p_top_wins, color=c); ax.axvline(.5, color=C3, ls='--'); ax.set_xlim(0, 1)
    for yv, p_ in zip(yy, z.p_top_wins): ax.text(p_ + .01, yv, f'{p_:.0%}', va='center', fontsize=9)
    ax.set_yticks(yy); ax.set_yticklabels(z.scenario); ax.set_title(f'Keep 1.01 vs trade back: share of cases 1.01 won\n({l})', loc='left', fontweight='bold', fontsize=10)
fig.text(.01, .01, 'Every same-class pair of picks in each range, 2010-2021 (production) and 2016-2023 (trade value). Two players are added together (100k values are additive).', fontsize=8, color=C3)
fig.tight_layout(); fig.savefig(CH + '05_trade_down_win_rates.png'); plt.close()
fig, ax = plt.subplots(figsize=(11, 5)); xx = np.arange(len(PC))
ax.bar(xx - .2, PC.produced_101, .4, color=C1, label='1.01 produced'); ax.bar(xx + .2, PC.avg_two_1sts, .4, color=C2, label='Two average later 1sts produced (2 x mean of 1.02-1.12)')
ax.set_xticks(xx); ax.set_xticklabels([f'{c}\n{n.split(" (")[0]}' for c, n in zip(PC.cls, PC.pick_101)], fontsize=7.5)
ax.set_ylabel('Produced value, 100k scale'); ax.legend(frameon=False); ax.set_title('Each class: the 1.01 vs two average later firsts', loc='left', fontweight='bold')
fig.tight_layout(); fig.savefig(CH + '06_101_vs_two_firsts_by_class.png'); plt.close()
# ---------- 6. position ----------
pos = []
for rd in (1, 2, 3):
    for p_ in ['QB', 'RB', 'WR', 'TE']:
        z = P[(P.rd == rd) & (P.position == p_)]; h = Hh[(Hh.rd == rd) & (Hh.position == p_)]; a = A[(A.rd == rd) & (A.position == p_)]
        if len(z) < 3: continue
        r = dict(round=rd, pos=p_, n=len(z), price=z.value_100k.mean(), produced=z['prod'].mean(), ratio=z['prod'].sum() / z.value_100k.sum(),
                 ratio_flex=z['prodflex'].sum() / z.value_100k.sum() * P.value_100k.sum() / P['prodflex'].sum(),
                 asset_ratio=a.asset_y3.sum() / a.value_100k.sum() if len(a) else np.nan, hit_top=(h.nfl_tier == 1).mean(), hit_any=(h.nfl_tier <= 3).mean())
        r['lo'], r['hi'] = boot(z, lambda q: q['prod'].sum() / q.value_100k.sum(), 1000)
        pos.append(r)
PO = pd.DataFrame(pos); PO.to_csv(OUT + '/by_position.csv', index=False); print(PO.round(3).to_string(index=False))
fig, axs = plt.subplots(1, 2, figsize=(13, 4.8))
cols = {'QB': '#1f4e79', 'RB': '#e07b00', 'WR': '#2a9d8f', 'TE': '#9b5de5'}
for i, p_ in enumerate(['QB', 'RB', 'WR', 'TE']):
    z = PO[PO.pos == p_]; axs[0].errorbar(z['round'] + (i - 1.5) * .12, z.ratio, yerr=[z.ratio - z.lo, z.hi - z.ratio], fmt='o', color=cols[p_], capsize=3, label=f'{p_}')
    axs[1].plot(z['round'] + (i - 1.5) * .05, z.hit_any, 'o-', color=cols[p_], label=p_)
axs[0].axhline(1, color=C3, ls='--'); axs[0].set_xticks([1, 2, 3]); axs[0].set_xticklabels(['Round 1', 'Round 2', 'Round 3']); axs[0].set_ylabel('Production / price')
axs[0].set_title('Return on price by position and round (2010-21)', loc='left', fontweight='bold'); axs[0].legend(frameon=False)
axs[1].set_xticks([1, 2, 3]); axs[1].set_xticklabels(['Round 1', 'Round 2', 'Round 3']); axs[1].set_ylabel('Any tier hit rate'); axs[1].set_ylim(0, 1)
axs[1].set_title('Hit rate by position and round (2010-23)', loc='left', fontweight='bold'); axs[1].legend(frameon=False)
fig.tight_layout(); fig.savefig(CH + '07_position_by_round.png'); plt.close()
# position mix by slot
mix = Hh.groupby(['grp', 'position']).size().unstack(fill_value=0).reindex([g[2] for g in GROUPS]); mix = mix.div(mix.sum(1), axis=0)
fig, ax = plt.subplots(figsize=(10, 4)); left = np.zeros(len(mix))
for p_ in ['QB', 'RB', 'WR', 'TE']:
    ax.barh(mix.index[::-1], mix[p_][::-1], left=left[::-1], color=cols[p_], label=p_); left += mix[p_].values
ax.set_xlabel('Share of picks'); ax.legend(frameon=False, ncol=4, loc='lower right'); ax.set_title('Who goes in each range (12-team SF, by our draft-time value, 2010-23)', loc='left', fontweight='bold')
fig.tight_layout(); fig.savefig(CH + '08_position_mix_by_range.png'); plt.close()
# ---------- 7. GLM (ATPA): does slot or position explain production beyond price? ----------
P['lp'] = np.log(P.value_100k); P['early'] = (P.slot <= 6).astype(int)
m0 = smf.glm('prod ~ lp', data=P, family=sm.families.Poisson()).fit(scale='X2')
m1 = smf.glm('prod ~ lp + C(position, Treatment("WR"))', data=P, family=sm.families.Poisson()).fit(scale='X2')
m2 = smf.glm('prod ~ lp + C(grp, Treatment("1.07-1.09"))', data=P, family=sm.families.Poisson()).fit(scale='X2')
with open(OUT + '/glm_results.txt', 'w') as f:
    for nm, m in [('price only', m0), ('price + position', m1), ('price + slot range', m2)]:
        f.write(f'===== quasi-Poisson GLM: produced ~ {nm}  (deviance {m.deviance:.0f}, dispersion {m.scale:.0f})\n{m.summary().tables[1]}\n\n')
    f.write(f'Elasticity of production to price (price only): {m0.params["lp"]:.2f} (1.0 = production rises in step with price; >1 = expensive picks are worth even more than their price)\n')
print(open(OUT + '/glm_results.txt').read())
# flex sensitivity chart
fig, ax = plt.subplots(figsize=(10, 4.5)); yy = np.arange(len(T))[::-1]
ax.plot(T.ratio, yy, 'o', color=C1, ms=8, label='No flex (reference league)'); ax.plot(T.produced_flex_ratio, yy, 'D', color=C2, ms=7, label='Site default, 2 FLEX')
ax.axvline(1, color=C3, ls='--'); ax.set_yticks(yy); ax.set_yticklabels(T.group); ax.set_xlabel('Production / price'); ax.legend(frameon=False)
ax.set_title('Same answer with the site default league (2 FLEX)', loc='left', fontweight='bold')
fig.tight_layout(); fig.savefig(CH + '09_flex_sensitivity.png'); plt.close()
# NFL-draft-order robustness: rank picks by NFL pick instead of our value
Q = b[(b['class'] <= 2021)].copy(); Q = Q[Q.slot_nfl <= 36]; Q['grp2'] = Q.slot_nfl.map(grp)
Q['hit'] = (Q.nfl_tier <= 3).astype(float); Q['top'] = (Q.nfl_tier == 1).astype(float)
rob = Q.groupby('grp2').agg(price=('value_100k', 'mean'), produced=('prod', 'mean'), hit_any=('hit', 'mean'), hit_top=('top', 'mean')).reindex([g[2] for g in GROUPS])
rob['ratio'] = rob.produced / rob.price
rob['our_order_produced'] = T.set_index('group').produced; rob.to_csv(OUT + '/robust_nfl_order.csv'); print(rob.round(0))
