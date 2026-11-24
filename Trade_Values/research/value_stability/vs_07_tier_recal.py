"""Second try at Kyle's point: re-calibrate next-season PPG only inside the top tier, keeping its level.
For snapshot season S, fit act = a + b x pred on dynasty top-50 rows (weeks 1-18) of seasons <= S-2, per position
group (QB vs non-QB, pooled for sample size). Apply to dynasty rank <= 40 in full, fading to none at rank 60."""
import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
ns = {}; exec(open('vs_03_combos.py').read().split('# ==== GRID' + ' ====')[0], ns)
P, ev, build, cppg, smooth, anchor, plain = ns['P'], ns['ev'], ns['build'], ns['cppg'], ns['smooth'], ns['anchor'], ns['plain']
P['grp'] = np.where(P.pos == 'QB', 'QB', 'FLEX')
fits = []
for s in range(2018, 2027):
    for g in ['QB', 'FLEX']:
        t = P[(P.season <= s - 2) & (P.grp == g) & (P.dy_rank <= 50) & (P.g_next >= 4) & P.dy_ppg_next.notna()]
        b, a = np.polyfit(t.dy_ppg_next, t.ppg_next_act, 1, w=t.g_next); fits.append(dict(season=s, grp=g, a=a, b=b))
F = pd.DataFrame(fits); F.to_csv('vs_tier_recal_fit.csv', index=False); print(F.round(2).to_string())
Q = P[['season', 'grp']].merge(F, on=['season', 'grp'], how='left')
wt = np.clip((60 - P.dy_rank) / 20, 0, 1).fillna(0).values
adj = (wt * ((Q.a + Q.b * P.dy_ppg_next) - P.dy_ppg_next)).fillna(0).values
ratio = (P.b_fut / P.b_next.replace(0, np.nan)).fillna(0).clip(0, 40)
def rec(x, anc):
    x = x.copy(); x['nxt'] = x.nxt + adj; x['dyn'] = x.dyn + ratio * adj; return anchor(x) if anc else plain(x)
live = plain(build(P.credible_ppg.copy())); cc = build(smooth(cppg(1.25 * P.k1).values, 0.7))
V = {'Live': live, 'Tier recalibration only': rec(build(P.credible_ppg.copy()), False),
     'Steadiness candidate': anchor(cc.copy()), 'Candidate + tier recalibration': rec(cc, True)}
m24 = (P.season >= 2018) & (P.season <= 2024) & (P.g_next >= 4) & (P.dy_rank <= 24) & P.dy_ppg_next.notna()
rows = []
for k, x in V.items():
    ev.ev = P.season >= 2018; a = ev.acc(x); d = ev.vol(x, 'dyn100k')
    rows.append(dict(variant=k, next_rmse=a['Next-season PPG RMSE'], next_rmse_top50=a['Next-season PPG RMSE (top 50)'],
                     next_rmse_top24=np.sqrt(np.average((P.ppg_next_act[m24] - x.nxt[m24]) ** 2, weights=P.g_next[m24])),
                     dynasty_spearman=a['Dynasty Spearman'], drop10=d['drop10'], drop20=d['drop20'], rank_move=d['rank_move']))
R = pd.DataFrame(rows).round(3); R.to_csv('vs_tier_recal_results.csv', index=False); print(R.T.to_string())
w = (P.season == 2026) & (P.week == 11)
B = pd.DataFrame({'name': P.name[w], 'proj_live': P.dy_ppg_next[w].round(1), 'proj_recal': (P.dy_ppg_next + adj)[w].round(1),
                  'live': live.dyn100k[w].round(-2), 'recal': V['Tier recalibration only'].dyn100k[w].round(-2), 'cand_recal': V['Candidate + tier recalibration'].dyn100k[w].round(-2)}).sort_values('live', ascending=False).head(16)
print(B.to_string(index=False)); B.to_csv('vs_tier_recal_2026.csv', index=False)
