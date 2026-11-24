"""Charts for the log + trade adjustment research (charts/09-11; 01-08 are in ../value_stability/charts)."""
import pandas as pd, numpy as np, matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
plt.rcParams.update({'font.size': 10, 'axes.spines.top': False, 'axes.spines.right': False, 'axes.edgecolor': '#c3c2b7', 'axes.grid': True,
                     'grid.color': '#e7e6e2', 'figure.facecolor': '#fcfcfb', 'axes.facecolor': '#fcfcfb'})
BLUE, ORANGE, GREY, INK = '#2a78d6', '#eb6834', '#a3a29b', '#29282a'
# 09 steadiness of logged values
S = pd.read_csv('ta_log_steadiness.csv'); L = S[S.model == 'live']
names = ['Live: #1 = 100k each week', 'ADD fixed unit (no anchor)', 'LOG60 fixed unit', 'LOG20 fixed unit', 'LOG5 fixed unit']
lab = ['Live (additive, #1 = 100k)', 'Additive, fixed unit', 'Log, c = 60', 'Log, c = 20', 'Log, c = 5']
L = L.set_index('system').loc[names]
fig, ax = plt.subplots(1, 2, figsize=(11, 3.8)); y = np.arange(len(names))[::-1]
ax[0].barh(y, L.drop10 * 100, color=BLUE, height=.6); ax[0].set_yticks(y, lab); ax[0].set_xlabel('Top-24 weeks with a 10%+ drop (%)')
for yi, v in zip(y, L.drop10 * 100): ax[0].text(v + .4, yi, f'{v:.1f}%', va='center', fontsize=9)
ax[0].set_title('Logging makes the numbers move less...', loc='left', fontsize=11)
for i, (c, col) in enumerate([('rank12', BLUE), ('rank24', ORANGE), ('rank100', GREY)]):
    ax[1].barh(y + (1 - i) * .25, L[c] / L.top1 * 100, height=.25, color=col, label={'rank12': '#12', 'rank24': '#24', 'rank100': '#100'}[c])
ax[1].set_yticks(y, [''] * len(y)); ax[1].set_xlabel('Value as % of #1 (median week)'); ax[1].legend(frameon=False, loc='upper left', bbox_to_anchor=(1.0, 1.0), title='Player ranked'); ax[1].set_xlim(0, 100)
ax[1].set_title('...because it squeezes everyone toward the top', loc='left', fontsize=11)
fig.text(0.01, 0.01, 'Same projections in every row (live dynasty, 2018-2026 weeks). Rank order and rank moves are identical in all five.', fontsize=8.5, color='#6f6e69')
fig.tight_layout(rect=(0, .04, 1, 1)); fig.savefig('charts/09_log_steadiness.png', dpi=160); plt.close()
# 10 market holdout error by type
H = pd.read_csv('ta_market_holdout.csv'); types = ['ALL', '1v2', '2v1', '2v2', '2v3', '3v3']
sysn = ['ADD', 'LOG60', 'LOG20', 'LOG5']; sl = {'ADD': 'Additive', 'LOG60': 'Log c=60', 'LOG20': 'Log c=20', 'LOG5': 'Log c=5'}
cols = {'ADD': BLUE, 'LOG60': '#7aa7e0', 'LOG20': '#f0a27c', 'LOG5': ORANGE}
fig, ax = plt.subplots(figsize=(11, 4.6)); x = np.arange(len(types)); w = .2
for i, s in enumerate(sysn):
    h = H[H.system == s].set_index('type').loc[types]
    ax.bar(x + (i - 1.5) * w, h.norm_type_gap, w * .9, color=cols[s], label=sl[s] + ' + adjustment')
    ax.scatter(x + (i - 1.5) * w, h.norm_no_adj, marker='_', s=120, color=INK, zorder=3, label='Same system, no adjustment' if i == 0 else None)
ax.set_xticks(x, ['All types\n(1-for-1 unadjusted)'] + types[1:]); ax.set_ylabel('Holdout error vs. real trades\n(1 = typical 1-for-1 miss)')
ax.legend(frameon=False, ncol=5, fontsize=8.5, loc='upper center', bbox_to_anchor=(.5, -.18)); ax.set_ylim(0, 2.0)
ax.set_title('Additive + adjustment reproduces accepted multi-player trades best (last 14 days held out, 16,770 trades)', loc='left', fontsize=11)
fig.tight_layout(); fig.savefig('charts/10_market_holdout.png', dpi=160); plt.close()
# 11 fitted adjustment curves, market vs realized
M = pd.read_csv('ta_market_curves.csv'); R = pd.read_csv('ta_realized_curves.csv')
fig, ax = plt.subplots(2, 3, figsize=(11, 6), sharey=True)
for i, s in enumerate(['ADD', 'LOG20']):
    for j, t in enumerate(['1v2', '2v1', '2v2']):
        a = ax[i, j]
        for D, col, nm in [(M, BLUE, 'Market (Dynasty Daddy trades)'), (R, ORANGE, 'Realized points (2018-21)')]:
            d = D[(D.system == s) & (D.type == t)]; a.plot(np.exp(d.g), (np.exp(d.adj) - 1) * 100, color=col, lw=2, label=nm)
        a.axhline(0, color=INK, lw=.8); a.set_ylim(-80, 80)
        a.set_title(f'{sl[s]}, {t}', loc='left', fontsize=10)
        if i == 1: a.set_xlabel("Best-asset ratio (side 1's best / side 2's best)")
        if j == 0: a.set_ylabel('Adjustment to side 1 (%)')
ax[0, 0].legend(frameon=False, fontsize=8.5)
fig.suptitle('Fitted adjustment: + means the side with the best player gets credit beyond its summed value', x=.01, ha='left', fontsize=11)
fig.text(0.01, 0.005, 'Curves drawn only up to the 95th percentile of the gaps seen in training. Realized sample is our own simulated trades, so its gaps are narrower.', fontsize=8.5, color='#6f6e69')
fig.tight_layout(rect=(0, .03, 1, .96)); fig.savefig('charts/11_adjust_curves.png', dpi=160); plt.close()
# 12 type premium relative to 1-for-1 (market) + Kyle's design scored (1-for-1 untouched)
Pm = pd.read_csv('ta_market_relative_premium.csv'); Sm = pd.read_csv('ta_market_relative_summary.csv')
fig, ax = plt.subplots(1, 2, figsize=(11, 4.8), gridspec_kw={'width_ratios': [1.5, 1]})
tys = ['1v2', '1v3', '2v1', '3v1', '2v2', '2v3', '3v2', '3v3']; x = np.arange(len(tys))
for i, (s, ratio, col) in enumerate([('ADD', 1, '#7aa7e0'), ('ADD', 2, BLUE), ('LOG20', 1, '#f0a27c'), ('LOG20', 2, ORANGE)]):
    d = Pm[(Pm.system == s) & (Pm.best_ratio == ratio)].set_index('type').loc[tys]
    ax[0].bar(x + (i - 1.5) * .2, d.rel_pct, .18, color=col, label=f"{sl[s]}, best player {ratio}x theirs")
ax[0].axhline(0, color=INK, lw=.8); ax[0].set_xticks(x, tys); ax[0].set_ylabel('Extra credit to side with the best player\nvs. a 1-for-1 at the same gap (%)')
ax[0].legend(frameon=False, fontsize=8, loc='upper right'); ax[0].set_title('What the market adds by trade type', loc='left', fontsize=11)
y = np.arange(4)[::-1]; S2 = Sm.set_index('system').loc[['ADD', 'LOG60', 'LOG20', 'LOG5']]
ax[1].barh(y + .2, S2.multi_none, .38, color=GREY, label='No adjustment')
ax[1].barh(y - .2, S2.multi_rel_only, .38, color=BLUE, label='+ type adjustment (1-for-1 untouched)')
ax[1].set_yticks(y, [sl[s] for s in S2.index]); ax[1].set_xlabel('Multi-player holdout error (1 = typical 1-for-1 miss)')
ax[1].legend(frameon=False, fontsize=8, loc='upper center', bbox_to_anchor=(.45, -.2), ncol=1); ax[1].set_xlim(0, 1.7)
ax[1].set_title("Kyle's design: adjustment on top of our values", loc='left', fontsize=11)
for yi, a_, b_ in zip(y, S2.multi_none, S2.multi_rel_only): ax[1].text(a_ + .02, yi + .2, f'{a_:.2f}', va='center', fontsize=8.5); ax[1].text(b_ + .02, yi - .2, f'{b_:.2f}', va='center', fontsize=8.5)
fig.text(0.01, 0.01, 'Side 1 holds the single best asset. Negative = the market credits the OTHER (fewer-player) side. Fitted before the last 14 days; error on the last 14 days.', fontsize=8.5, color='#6f6e69')
fig.tight_layout(rect=(0, .04, 1, 1)); fig.savefig('charts/12_type_premium.png', dpi=160); plt.close()
