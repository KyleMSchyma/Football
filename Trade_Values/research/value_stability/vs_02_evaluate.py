"""Score every variant: volatility of the top values week to week vs accuracy (rolling origin, 2018+)."""
import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
P, V = pd.read_pickle('vs_variants.pkl')
# extra variants on the 100k scale only (values unchanged): anchor = mean of the top 10 raw values, not the #1 player
base = V['Live (k fit at week 9)'].copy()
for col in ['red', 'dyn']:
    t10 = base.groupby([P.season, P.week])[col].transform(lambda s: s.nlargest(10).mean())
    t1 = base.groupby([P.season, P.week])[col].transform('max')
    base[col + '100k'] = 1e5 * base[col] / t10 * (t10 / t1).groupby(P.season).transform('mean')
V['Live values, 100k anchored to top-10 average'] = base
ev = (P.season >= 2018)

def vol(x, col, rk_n=24):
    d = pd.DataFrame({'pid': P.player_id, 's': P.season, 'w': P.week, 'v': x[col]})
    d['rank'] = d.groupby(['s', 'w']).v.rank(ascending=False, method='first')
    g = d.groupby(['pid', 's']); d['pv'] = g.v.shift(); d['pr'] = g['rank'].shift(); d['pw'] = g.w.shift()
    t = d[ev & (d.pr <= rk_n) & (d.w == d.pw + 1) & (d.w >= 2)]
    ch = t.v / t.pv - 1
    return dict(mean_abs_chg=ch.abs().mean(), p90_abs_chg=ch.abs().quantile(.9), drop10=(ch < -.10).mean(),
                drop20=(ch < -.20).mean(), rank_move=(t['rank'] - t.pr).abs().mean(), n=len(t))

def acc(x):
    o = {}
    r = ev & (P.season <= 2025) & (P.n_ros >= 3)
    o['ROS PPG RMSE'] = np.sqrt(np.average((P.ppg_ros[r] - x.cppg[r]) ** 2, weights=P.n_ros[r]))
    top = r & (P['rank'] <= 50)
    o['ROS PPG RMSE (top 50)'] = np.sqrt(np.average((P.ppg_ros[top] - x.cppg[top]) ** 2, weights=P.n_ros[top]))
    n = ev & (P.season <= 2024) & (P.g_next >= 4) & P.dy_ppg_next.notna()
    o['Next-season PPG RMSE'] = np.sqrt(np.average((P.ppg_next_act[n] - x.nxt[n]) ** 2, weights=P.g_next[n]))
    nt = n & (P.dy_rank <= 50)
    o['Next-season PPG RMSE (top 50)'] = np.sqrt(np.average((P.ppg_next_act[nt] - x.nxt[nt]) ** 2, weights=P.g_next[nt]))
    # rank accuracy per snapshot: redraft value vs actual ROS points over replacement; dynasty value vs ROS + next season
    act_r = (P.ppg_ros.fillna(0) - x.rep) * P.n_ros
    act_d = np.maximum(P.ppg_ros.fillna(0) - x.rep, 0) * P.n_ros + np.maximum(P.ppg_next_act.fillna(0) - x.rep, 0) * P.g_next.fillna(0) / 1.15
    m = ev & (P.season <= 2025) & (P.games >= 3)
    o['Redraft Spearman'] = pd.DataFrame({'a': act_r[m], 'v': x.red[m], 's': P.season[m], 'w': P.week[m]}).groupby(['s', 'w']).apply(lambda g: g.v.corr(g.a, method='spearman')).mean()
    m2 = ev & (P.season <= 2024) & (P.games >= 3) & x.dyn.notna()
    o['Dynasty Spearman'] = pd.DataFrame({'a': act_d[m2], 'v': x.dyn[m2], 's': P.season[m2], 'w': P.week[m2]}).groupby(['s', 'w']).apply(lambda g: g.v.corr(g.a, method='spearman')).mean()
    return o

rows = []
for k, x in V.items():
    a = acc(x); dv = vol(x, 'dyn100k'); rv = vol(x, 'red100k'); draw = vol(x, 'dyn')
    rows.append(dict(variant=k, **a, dyn_mean_abs_chg=dv['mean_abs_chg'], dyn_drop10=dv['drop10'], dyn_drop20=dv['drop20'],
                     dyn_rank_move=dv['rank_move'], dyn_raw_mean_abs_chg=draw['mean_abs_chg'], red_mean_abs_chg=rv['mean_abs_chg'],
                     red_drop10=rv['drop10'], red_rank_move=rv['rank_move'], n_top24_weeks=dv['n']))
R = pd.DataFrame(rows); R.to_csv('vs_results.csv', index=False)
pd.set_option('display.width', 250); pd.set_option('display.max_columns', 30)
print(R.set_index('variant').round(3).T.to_string())
