"""Why top values drop (decomposition), robustness of the candidate by season, 2026 examples, and charts."""
import pandas as pd, numpy as np, warnings, matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
warnings.filterwarnings('ignore')
ns = {}; exec(open('vs_03_combos.py').read().split('# ==== GRID' + ' ====')[0], ns)
P, build, cppg, smooth, anchor, plain, ev = ns['P'], ns['build'], ns['cppg'], ns['smooth'], ns['anchor'], ns['plain'], ns['ev']
BLUE, ORANGE, AQUA, GRAY, INK = '#2a78d6', '#eb6834', '#1baf7a', '#9a9893', '#0b0b0b'
plt.rcParams.update({'font.size': 10, 'axes.spines.top': False, 'axes.spines.right': False, 'axes.edgecolor': '#c3c2b7',
                     'axes.grid': True, 'grid.color': '#e7e6e2', 'grid.linewidth': .6, 'figure.facecolor': '#fcfcfb', 'axes.facecolor': '#fcfcfb'})
live = plain(build(P.credible_ppg.copy()))
cand = anchor(build(smooth(cppg(1.25 * P.k1).values, 0.7)))
out = []
# ---------- 1. what moves a top-24 dynasty value in a week (live) ----------
d = pd.DataFrame({'pid': P.player_id, 's': P.season, 'w': P.week, 'name': P.name, 'v100': P.dy_value_100k, 'raw': P.dy_value,
                  'ros': P.dy_value_ros, 'fut': P.fut, 'cp': P.credible_ppg, 'av': P.avail, 'st': P.status.fillna(''), 'rk': P.dy_rank, 'gw': P.g_wk})
d['top'] = d.groupby(['s', 'w']).raw.transform('max')
g = d.groupby(['pid', 's'])
for c in ['v100', 'raw', 'ros', 'fut', 'cp', 'av', 'top', 'rk', 'w']: d['p_' + c] = g[c].shift()
t = d[(d.p_rk <= 24) & (d.w == d.p_w + 1) & (d.s >= 2016)].copy()
t['chg'] = t.v100 / t.p_v100 - 1
dr = t[t.chg < -0.10].copy()
dr['scale_part'] = np.log(dr.top / dr.p_top); dr['raw_part'] = np.log(dr.raw / dr.p_raw)
def why(r):
    if r.raw_part > -0.05: return 'Mostly the #1 player rising (100k rescale)'
    if r.st != '' or r.av < r.p_av - 0.1: return 'Injury / status (games expected fell)'
    if r.gw == 0: return 'Did not play (bye or missing)'
    if r.cp < r.p_cp - 0.2: return 'Bad game lowered credible PPG'
    return 'Other (games-left clock, replacement line)'
dr['why'] = dr.apply(why, axis=1)
W = dr.why.value_counts(normalize=True).round(3); print('top-24 dynasty drops of 10%+ (live), 2016-2026:', len(dr), 'of', len(t)); print(W)
W.to_csv('vs_drop_reasons.csv')
# leverage: % change in dynasty value per 1% change in credible PPG (top 24)
tt = t[(t.cp != t.p_cp) & (t.av.round(2) == t.p_av.round(2))]
lev = (np.log(tt.raw / tt.p_raw) / np.log(tt.cp / tt.p_cp)).clip(-20, 20)
print('leverage (median elasticity of dynasty value to credible PPG, top 24):', round(lev.median(), 2))
# ---------- 2. robustness by season (top-50 next-season RMSE, ROS RMSE, big-drop share) ----------
rows = []
for s in range(2018, 2026):
    m = P.season == s; r = m & (P.n_ros >= 3); n = m & (P.g_next >= 4) & (P['dy_rank'] <= 50) & P.dy_ppg_next.notna()
    f = lambda x, mk, y, wt, col: np.sqrt(np.average((P[y][mk] - x[col][mk]) ** 2, weights=P[wt][mk])) if mk.sum() else np.nan
    rows.append(dict(season=s, ros_rmse_live=f(live, r, 'ppg_ros', 'n_ros', 'cppg'), ros_rmse_cand=f(cand, r, 'ppg_ros', 'n_ros', 'cppg'),
                     next_rmse_top50_live=f(live, n, 'ppg_next_act', 'g_next', 'nxt'), next_rmse_top50_cand=f(cand, n, 'ppg_next_act', 'g_next', 'nxt')))
SR = pd.DataFrame(rows)
ev.ev = P.season >= 0
def vol_season(x, s):
    ev.ev = (P.season == s); return ev.vol(x, 'dyn100k')['drop10']
for nm, x in [('live', live), ('cand', cand)]: SR['drop10_' + nm] = [vol_season(x, s) for s in SR.season]
SR = SR.round(3); SR.to_csv('vs_by_season.csv', index=False); print(SR.to_string())
# ---------- 3. 2026 current board: live vs candidate (week 11) ----------
m = (P.season == 2026) & (P.week == P[P.season == 2026].week.max())
B = pd.DataFrame({'name': P.name[m], 'pos': P.pos[m], 'live_100k': live.dyn100k[m].round(), 'steady_100k': cand.dyn100k[m].round(),
                  'live_rank': live.dyn100k[m].rank(ascending=False), 'steady_rank': cand.dyn100k[m].rank(ascending=False)}).sort_values('live_rank').head(30)
B.to_csv('vs_2026_board_compare.csv', index=False); print(B.to_string())
# volatility of 2026 so far
ev.ev = P.season == 2026
print('2026 so far drop10 live', round(ev.vol(live, 'dyn100k')['drop10'], 3), 'steady', round(ev.vol(cand, 'dyn100k')['drop10'], 3))
pd.to_pickle((live, cand), 'vs_live_cand.pkl')

# ================= charts =================
G = pd.read_csv('vs_grid.csv'); R = pd.read_csv('vs_results.csv')
# A. frontier
fig, ax = plt.subplots(figsize=(7.5, 4.6))
for anc, col, lab in [(False, ORANGE, '#1 player = 100k (live scale)'), (True, BLUE, 'Top-10 average anchor')]:
    x = G[G.top10_anchor == anc]
    ax.scatter(x.dyn_drop10 * 100, x['Next-season PPG RMSE (top 50)'], s=40 + 60 * (1 - x.ewma_a), color=col, alpha=.85, edgecolor='white', lw=1.5, label=lab, zorder=3)
ax.scatter([25.6], [3.620], s=140, facecolor='none', edgecolor=INK, lw=1.5, zorder=4); ax.annotate('Live today', (25.6, 3.620), xytext=(18, 3.629), fontsize=9, arrowprops=dict(arrowstyle='-', color=GRAY))
ax.scatter([15.4], [3.600], s=140, facecolor='none', edgecolor=INK, lw=1.5, zorder=4); ax.annotate('Candidate: k x1.25, smooth 0.7, top-10 anchor', (15.4, 3.600), xytext=(18.6, 3.6045), fontsize=9, arrowprops=dict(arrowstyle='-', color=GRAY))
ax.set_xlabel('Top-24 dynasty values: share of weeks with a 10%+ drop (%)'); ax.set_ylabel('Next-season PPG error, top 50 (RMSE)')
ax.set_title('Steadier and no less accurate: every grid variant (bigger dot = more smoothing)', fontsize=10.5, loc='left'); ax.legend(frameon=False, fontsize=9, loc='upper right')
fig.tight_layout(); fig.savefig('charts/01_frontier.png', dpi=160); plt.close()
# B. weekly change distribution
def chgs(x):
    q = pd.DataFrame({'pid': P.player_id, 's': P.season, 'w': P.week, 'v': x.dyn100k}); q['rk'] = q.groupby(['s', 'w']).v.rank(ascending=False)
    gg = q.groupby(['pid', 's']); q['pv'] = gg.v.shift(); q['pr'] = gg.rk.shift(); q['pw'] = gg.w.shift()
    q = q[(q.pr <= 24) & (q.w == q.pw + 1) & (q.s >= 2018)]; return (q.v / q.pv - 1) * 100
fig, ax = plt.subplots(figsize=(7.5, 4)); bins = np.arange(-40, 41, 2.5)
ax.hist(chgs(live).clip(-40, 40), bins=bins, color=ORANGE, alpha=.55, label='Live', edgecolor='white')
ax.hist(chgs(cand).clip(-40, 40), bins=bins, color=BLUE, alpha=.55, label='Candidate', edgecolor='white')
ax.axvline(-10, color=GRAY, ls='--', lw=1); ax.text(-10.5, ax.get_ylim()[1] * .9, '-10%', ha='right', fontsize=9, color='#52514e')
ax.set_xlabel('Week-to-week change in a top-24 dynasty value (%, 100k scale, 2018-2026)'); ax.set_ylabel('Player-weeks')
ax.set_title('The candidate pulls in both tails: fewer big drops and fewer big jumps', fontsize=10.5, loc='left'); ax.legend(frameon=False)
fig.tight_layout(); fig.savefig('charts/02_change_distribution.png', dpi=160); plt.close()
# C. drop reasons
fig, ax = plt.subplots(figsize=(7.5, 3.2)); W2 = W.sort_values()
ax.barh(W2.index, W2.values * 100, color=BLUE, height=.6); ax.grid(axis='y', visible=False)
for i, v in enumerate(W2.values): ax.text(v * 100 + .8, i, f'{v*100:.0f}%', va='center', fontsize=9)
ax.set_xlabel(f'Share of live top-24 dynasty drops of 10%+ (n = {len(dr)}, 2016-2026)'); ax.set_title('Why a top dynasty value drops 10%+ in a week (live model)', fontsize=10.5, loc='left')
fig.tight_layout(); fig.savefig('charts/03_drop_reasons.png', dpi=160); plt.close()
# D. examples: 4 players 2026
ex = P[(P.season == 2026)].groupby('player_id').dy_rank.min().sort_values().index[:40]
pick = [p for p in ['Ja\'Marr Chase', 'Josh Allen', 'Bijan Robinson', 'Puka Nacua', 'Jahmyr Gibbs', 'Lamar Jackson'] if (P[(P.season == 2026)].name == p).any()][:4]
fig, axs = plt.subplots(2, 2, figsize=(8, 5.2), sharex=True)
for ax, nm in zip(axs.flat, pick):
    m = (P.season == 2026) & (P.name == nm)
    ax.plot(P.week[m], live.dyn100k[m] / 1000, color=ORANGE, lw=2, marker='o', ms=4, label='Live')
    ax.plot(P.week[m], cand.dyn100k[m] / 1000, color=BLUE, lw=2, marker='o', ms=4, label='Candidate')
    ax.set_title(nm, fontsize=10, loc='left'); ax.set_ylabel('Value (k)')
axs[0, 0].legend(frameon=False, fontsize=8); [a.set_xlabel('2026 week') for a in axs[1]]
fig.suptitle('2026 dynasty value paths, live vs candidate (100k scale)', x=.02, ha='left', fontsize=10.5); fig.tight_layout(); fig.savefig('charts/04_examples_2026.png', dpi=160); plt.close()
# E. fitted k
FK = pd.read_csv('vs_fitted_k.csv'); FK = FK[FK.season == 2026]
k1 = P[P.season == 2026].groupby('pos').k1.first(); kb = P[P.season == 2026].groupby('pos').k_bs.first()
fig, ax = plt.subplots(figsize=(7.5, 3.6)); pos = ['QB', 'RB', 'WR', 'TE']; xx = np.arange(4); wdt = .2
ax.bar(xx - 1.5 * wdt, [kb[p] for p in pos], wdt, color=GRAY, label='Textbook B-S (EPV/VHM, vs position mean)')
ax.bar(xx - .5 * wdt, [k1[p] for p in pos], wdt, color=ORANGE, label='Live k1 (fit at week 9)')
ax.bar(xx + .5 * wdt, [FK[FK.pos == p].k_ros.mean() for p in pos], wdt, color=AQUA, label='Fitted for rest of season (avg of week groups)')
ax.bar(xx + 1.5 * wdt, [FK[FK.pos == p].k_dyn.mean() for p in pos], wdt, color=BLUE, label='Fitted for next season')
ax.set_xticks(xx, pos); ax.set_ylabel('k (games)'); ax.grid(axis='x', visible=False)
ax.set_title('Credibility constant k: Z = games / (games + k)', fontsize=10.5, loc='left'); ax.legend(frameon=False, fontsize=8)
fig.tight_layout(); fig.savefig('charts/05_fitted_k.png', dpi=160); plt.close()
# F. single-lever bars
lev_rows = R[R.variant.isin(['Live (k fit at week 9)', 'k x 1.5', 'k x 2', 'Classic Buhlmann-Straub k (EPV/VHM)', 'Horizon k: dynasty fit (next season)',
                             'Trim games at +/-1.0 sd', 'EWMA smooth a=0.6', 'Live values, 100k anchored to top-10 average'])]
fig, axs = plt.subplots(1, 2, figsize=(9, 3.8), sharey=True)
yy = np.arange(len(lev_rows))
axs[0].barh(yy, lev_rows.dyn_drop10 * 100, color=BLUE, height=.6); axs[0].set_xlabel('10%+ weekly drops, top-24 dynasty (%)')
axs[1].barh(yy, lev_rows['ROS PPG RMSE'], color=ORANGE, height=.6); axs[1].set_xlim(3.4, 3.62); axs[1].set_xlabel('Rest-of-season PPG RMSE (lower = better)')
axs[0].set_yticks(yy, lev_rows.variant); [a.grid(axis='y', visible=False) for a in axs]
for i, (a, b) in enumerate(zip(lev_rows.dyn_drop10, lev_rows['ROS PPG RMSE'])): axs[0].text(a * 100 + .4, i, f'{a*100:.1f}', va='center', fontsize=8); axs[1].text(b + .003, i, f'{b:.3f}', va='center', fontsize=8)
fig.suptitle('Each lever on its own: steadiness (left) vs accuracy (right)', x=.02, ha='left', fontsize=10.5); fig.tight_layout(); fig.savefig('charts/06_single_levers.png', dpi=160); plt.close()
print('charts done')
