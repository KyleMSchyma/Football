"""Score the star shrink (vs_05) alone and on top of the steadiness candidate; Bijan vs Gibbs today."""
import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
ns = {}; exec(open('vs_03_combos.py').read().split('# ==== GRID' + ' ====')[0], ns)
P, ev, build, cppg, smooth, anchor, plain = ns['P'], ns['ev'], ns['build'], ns['cppg'], ns['smooth'], ns['anchor'], ns['plain']
adj = pd.read_pickle('vs_star_adj.pkl').values
ratio = (P.b_fut / P.b_next.replace(0, np.nan)).fillna(0).clip(0, 40)
def star(x, scale=True):
    x = x.copy(); x['nxt'] = x.nxt + adj; x['dyn'] = x.dyn + ratio * adj
    return anchor(x) if scale else plain(x)
live = plain(build(P.credible_ppg.copy())); cand_c = build(smooth(cppg(1.25 * P.k1).values, 0.7))
V = {'Live': live, 'Star shrink only (#1 = 100k)': star(build(P.credible_ppg.copy()), False),
     'Steadiness candidate (k x1.25, EWMA .7, top-10 anchor)': anchor(cand_c.copy()),
     'Candidate + star shrink': star(cand_c)}
rows = []
for k, x in V.items():
    ev.ev = P.season >= 2018
    a = ev.acc(x); d = ev.vol(x, 'dyn100k')
    rows.append(dict(variant=k, **{c: a[c] for c in ['Next-season PPG RMSE', 'Next-season PPG RMSE (top 50)', 'Dynasty Spearman']},
                     dyn_mean_abs_chg=d['mean_abs_chg'], dyn_drop10=d['drop10'], dyn_drop20=d['drop20'], dyn_rank_move=d['rank_move']))
R = pd.DataFrame(rows).round(3); R.to_csv('vs_star_results.csv', index=False); print(R.T.to_string())
# top-24 next-season RMSE specifically
m = (P.season >= 2018) & (P.season <= 2024) & (P.g_next >= 4) & (P.dy_rank <= 24) & P.dy_ppg_next.notna()
for k, x in V.items(): print(k, 'top-24 next RMSE', round(np.sqrt(np.average((P.ppg_next_act[m] - x.nxt[m]) ** 2, weights=P.g_next[m])), 3))
# 2026 week 11 board
w = (P.season == 2026) & (P.week == 11)
B = pd.DataFrame({'name': P.name[w], 'pos': P.pos[w], 'ppg_2026': P.ppg[w], 'proj_next_live': P.dy_ppg_next[w].round(1),
                  'proj_next_star': (P.dy_ppg_next + adj)[w].round(1), 'live_100k': live.dyn100k[w].round(-2),
                  'star_100k': V['Star shrink only (#1 = 100k)'].dyn100k[w].round(-2), 'cand_star_100k': V['Candidate + star shrink'].dyn100k[w].round(-2)})
B['live_rank'] = B.live_100k.rank(ascending=False, method='first').astype(int); B['star_rank'] = B.star_100k.rank(ascending=False, method='first').astype(int)
B = B.sort_values('live_rank').head(30); B.to_csv('vs_star_2026_board.csv', index=False); print(B.to_string(index=False))
pd.to_pickle(V, 'vs_star_variants.pkl')
# chart 07: Bijan vs Gibbs, 2026 (live), dynasty value and projected 2027 PPG
import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
plt.rcParams.update({'font.size': 10, 'axes.spines.top': False, 'axes.spines.right': False, 'axes.edgecolor': '#c3c2b7', 'axes.grid': True,
                     'grid.color': '#e7e6e2', 'figure.facecolor': '#fcfcfb', 'axes.facecolor': '#fcfcfb'})
fig, axs = plt.subplots(1, 2, figsize=(9, 3.6))
for nm, col in [('Jahmyr Gibbs', '#2a78d6'), ('Bijan Robinson', '#eb6834')]:
    m = (P.season == 2026) & (P.name == nm)
    axs[0].plot(P.week[m], P.dy_value_100k[m] / 1000, color=col, lw=2, marker='o', ms=4, label=nm)
    axs[1].plot(P.week[m], P.ppg[m], color=col, lw=2, ls=':', label=f'{nm}: 2026 PPG')
    axs[1].plot(P.week[m], P.dy_ppg_next[m], color=col, lw=2, marker='o', ms=4, label=f'{nm}: projected 2027 PPG')
axs[0].set_title('Live dynasty value (k, 100k scale)', fontsize=10, loc='left'); axs[0].legend(frameon=False, fontsize=8)
axs[1].set_title('2026 PPG (dotted) vs projected 2027 PPG (solid)', fontsize=10, loc='left'); axs[1].axhline(11.5, color='#9a9893', lw=1, ls='--')
axs[1].text(1, 12, 'RB replacement ~11.5', fontsize=8, color='#52514e')
for a in axs: a.set_xlabel('2026 week')
fig.tight_layout(); fig.savefig('charts/07_bijan_gibbs.png', dpi=160); plt.close()
