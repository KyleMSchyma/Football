# Apply the historical slot findings to the 2027 class (pre board: Kyle's mock median picks priced by the post-draft model, others pre-draft x P(declare)).
import pandas as pd, numpy as np
import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
plt.rcParams.update({'figure.dpi': 130, 'axes.spines.top': False, 'axes.spines.right': False, 'axes.grid': True, 'grid.alpha': .3, 'font.size': 10})
b = pd.read_csv('/home/user/Football/Trade_Values/dv_rookie_board_values.csv')
z = b[(b.board == 'pre') & (b['class'] == 2027)].sort_values('value_100k', ascending=False).head(36).reset_index(drop=True)
z['slot'] = np.arange(1, 37); z['sl'] = [f'{(s-1)//12+1}.{(s-1)%12+1:02d}' for s in z.slot]
S = pd.read_csv('per_slot.csv'); P = pd.read_csv('players.csv')
H = P[(P['class'] <= 2023) & (P.slot <= 36)]
# historical model-predicted vs actual top-tier rate by slot (are post-draft probabilities honest by slot?)
cal = H.groupby('slot').agg(pred_top=('p_top', 'mean'), act_top=('nfl_tier', lambda s: (s == 1).mean())).reset_index()
z = z.merge(S[['slot', 'price', 'hit_top', 'hit_any']].rename(columns={'price': 'hist_price', 'hit_top': 'hist_top', 'hit_any': 'hist_any'}), on='slot').merge(cal[['slot', 'pred_top']].rename(columns={'pred_top': 'hist_pred_top'}), on='slot')
z[['sl', 'name', 'position', 'college', 'source', 'p_top', 'p_any', 'value_100k', 'hist_price', 'hist_pred_top', 'hist_top', 'hist_any']].to_csv('class_2027_slots.csv', index=False)
pd.set_option('display.width', 250); print(z[['sl', 'name', 'position', 'p_top', 'p_any', 'value_100k', 'hist_price', 'hist_pred_top', 'hist_top']].round(3).to_string(index=False))
G = [(1, 1), (2, 3), (4, 6), (7, 9), (10, 12), (13, 18), (19, 24), (25, 36)]
rows = []
for lo, hi in G:
    q = z[z.slot.between(lo, hi)]; h = H[H.slot.between(lo, hi)]
    rows.append(dict(range=f'{q.sl.iloc[0]}-{q.sl.iloc[-1]}', price_2027=q.value_100k.mean(), price_hist=h.value_100k.mean(),
                     ptop_2027=q.p_top.mean(), ptop_model_hist=h.p_top.mean(), top_actual_hist=(h.nfl_tier == 1).mean(),
                     pany_2027=q.p_any.mean(), any_actual_hist=(h.nfl_tier <= 3).mean(), pos_2027='/'.join(f'{k}{v}' for k, v in q.position.value_counts().items())))
R = pd.DataFrame(rows); R.to_csv('class_2027_ranges.csv', index=False); print(R.round(3).to_string(index=False))
print('expected top-tier players 1-6 / 7-12:', z.p_top[:6].sum(), z.p_top[6:12].sum(), ' hist actual per class:', (H[H.slot <= 6].nfl_tier == 1).sum() / 14, (H[H.slot.between(7, 12)].nfl_tier == 1).sum() / 14)
print('class top-36 total 2027', z.value_100k.sum(), 'hist mean', H.groupby('class').value_100k.sum().mean())
# chart 10: 2027 price curve vs history; chart 11: expected top-tier odds vs history
fig, ax = plt.subplots(figsize=(11, 5.2))
ax.plot(S.slot, S.price, color='#7f7f7f', lw=2, label='Average price, 2010-2021 classes')
ax.plot(S.slot, S.produced.rolling(3, center=True, min_periods=1).mean(), color='#e07b00', lw=1.5, ls='--', label='Average produced, 2010-2021 (3-slot rolling)')
cols = {'QB': '#1f4e79', 'RB': '#e07b00', 'WR': '#2a9d8f', 'TE': '#9b5de5'}
ax.plot(z.slot, z.value_100k, color='#18212d', lw=1.2)
for p_, c in cols.items():
    q = z[z.position == p_]; ax.scatter(q.slot, q.value_100k, color=c, s=40, zorder=3, label=f'2027 {p_}')
for _, r in z.head(9).iterrows(): ax.annotate(r['name'].split(' ')[-1], (r.slot, r.value_100k), xytext=(5, 4), textcoords='offset points', fontsize=8)
for v in (12.5, 24.5): ax.axvline(v, color='#7f7f7f', lw=.8, ls=':')
ax.set_xticks(range(1, 37, 3)); ax.set_xticklabels(z.sl[::3]); ax.set_ylabel('Value (100k scale)')
ax.set_title('2027 class: our pick prices vs the historical price curve', loc='left', fontweight='bold'); ax.legend(frameon=False, ncol=2)
fig.tight_layout(); fig.savefig('charts/10_2027_price_curve.png'); plt.close()
fig, ax = plt.subplots(figsize=(11, 4.8))
ax.bar(z.slot - .2, z.p_top, .4, color='#1f4e79', label='2027: model odds of a top-tier season')
ax.bar(z.slot + .2, z.hist_top, .4, color='#c9d3df', label='History: actual top-tier rate at that slot (2010-23)')
ax.plot(z.slot, z.hist_pred_top, color='#e07b00', lw=1.5, label='History: what the model predicted at that slot')
ax.set_xticks(range(1, 37, 3)); ax.set_xticklabels(z.sl[::3]); ax.set_ylim(0, 1); ax.set_ylabel('Probability / rate')
ax.set_title('2027 top-tier odds by slot vs what history delivered', loc='left', fontweight='bold'); ax.legend(frameon=False)
fig.tight_layout(); fig.savefig('charts/11_2027_hit_odds.png'); plt.close()
