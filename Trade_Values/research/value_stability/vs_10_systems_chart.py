"""Chart for vs_09: steadiness vs realized package fairness for each value system (live model)."""
import pandas as pd, numpy as np, matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
plt.rcParams.update({'font.size': 10, 'axes.spines.top': False, 'axes.spines.right': False, 'axes.edgecolor': '#c3c2b7', 'axes.grid': True,
                     'grid.color': '#e7e6e2', 'figure.facecolor': '#fcfcfb', 'axes.facecolor': '#fcfcfb'})
R = pd.read_csv('vs_value_systems.csv'); R = R[R.model == 'live'].iloc[::-1]
fig, axs = plt.subplots(1, 2, figsize=(9.5, 3.8), sharey=True); y = np.arange(len(R))
axs[0].barh(y, R.drop10 * 100, color='#2a78d6', height=.6); axs[0].set_xlabel('Top-24 weeks with a 10%+ drop (%)')
axs[1].barh(y, R.star_vs_2for1_realized, color='#eb6834', height=.6); axs[1].axvline(1, color='#52514e', lw=1, ls='--')
axs[1].set_xlabel('Top-3 star realized / equal-value pair realized (1 = fair)'); axs[1].set_xlim(0.5, 1.15)
axs[0].set_yticks(y, R.system); [a.grid(axis='y', visible=False) for a in axs]
for i, (a, b) in enumerate(zip(R.drop10, R.star_vs_2for1_realized)):
    axs[0].text(a * 100 + .4, i, f'{a*100:.1f}', va='center', fontsize=8); axs[1].text(b + .01, i, f'{b:.2f}', va='center', fontsize=8)
fig.suptitle('Value systems on the same projection (live model, 2018-2024)', x=.02, ha='left', fontsize=10.5)
fig.tight_layout(); fig.savefig('charts/08_value_systems.png', dpi=160); plt.close()
