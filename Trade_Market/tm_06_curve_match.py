"""tm_06_curve_match.py: put the market's 1:1 (straight-up) dynasty values on the same curve shape as our values
(one power p fitted so the sorted top-150 player curves match in logs), then list per-player differences.
Kyle 2026-11-23. Usage: run from Trade_Market/ with our_values.csv at /tmp/claude-0/our_values.csv (from tm_03_our_values.js)."""
import pandas as pd, numpy as np, json
from scipy.optimize import minimize_scalar
from scipy.stats import spearmanr
sl=json.load(open('/home/user/prospect-actuary/data/sleeper_ids.json'))['m']
A=pd.read_csv('out/dynasty_add4_assets.csv',dtype={'asset':str}); s0=pd.read_csv('out/dynasty_add4_meta.csv').stretch[0]
A['th1']=A.theta_unstretched  # 1:1 scale, default league (SF, PPR, 12 tm, 10 starters -> covariates 0)
A['name2']=A.asset.map(lambda a: sl.get(a,'|').split('|')[0] or None)
o=pd.read_csv('/tmp/claude-0/our_values.csv'); o=o[(o['mode']=='d')&(o.teams==12)&(o.ppr==1)&(o.tep==0)&(o.sf==1)]
sk=A[A.grp.isin(['QB','RB','WR','TE'])].copy()
ours=np.sort(o[o.pos.isin(['QB','RB','WR','TE'])].value.values)[::-1][:150]
def curve(p):
    v=np.exp(p*sk.th1.values); v=1e5*v/v.max(); return np.sort(v)[::-1][:150]
f=lambda p: np.mean((np.log(curve(p))-np.log(ours))**2)
r=minimize_scalar(f,bounds=(0.5,5),method='bounded'); p=r.x
print('power on 1:1 scale',round(p,3),'rmse log',round(np.sqrt(r.fun),3), ' (package-fair =',round(s0,3),')')
for q in [1,s0,p]: print(q, np.round(curve(q)[[0,11,23,49,99,149]]/1000,1))
print('ours', np.round(ours[[0,11,23,49,99,149]]/1000,1))
v=np.exp(p*A.th1.values); A['mkt']=1e5*v/v[A.grp.isin(['QB','RB','WR','TE']).values].max()
P=A.merge(o[['name','value']],left_on='name2',right_on='name',how='left')
P['our_rank']=P.value.rank(ascending=False); P['mkt_rank']=P.mkt.where(P.grp.isin(['QB','RB','WR','TE'])).rank(ascending=False)
P['diff']=P.mkt-P.value
T=P[P.value.notna()&P.grp.isin(['QB','RB','WR','TE'])&((P.our_rank<=100)|(P.mkt_rank<=100))]
cols=['name2','grp','value','mkt','diff','our_rank','mkt_rank']
print(T.nlargest(15,'diff')[cols].round(0).to_string()); print(T.nsmallest(15,'diff')[cols].round(0).to_string())
print(P[P.grp=='PICK'].nlargest(8,'mkt')[['name_x','asset','mkt']].round(0))
pos=T[T.value>=5000].assign(lr=lambda q: np.log(q.mkt/q.value)).groupby('grp').lr.mean().apply(lambda m: round(np.exp(m)-1,3)); print(pos)
T[cols].sort_values('mkt',ascending=False).round(0).to_csv('compare_add4/dynasty_curve_matched.csv',index=False)
import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
COL={"QB":"#d1495b","RB":"#2e86ab","WR":"#3b9c5a","TE":"#e09f3e"}
top=T[T.our_rank<=150]
fig,ax=plt.subplots(figsize=(6.4,5.4))
for g,d in top.groupby('grp'): ax.scatter(d.value/1000,d.mkt/1000,s=12,color=COL[g],label=g,alpha=.85)
ax.plot([0,105],[0,105],ls='--',color='grey',lw=.8); ax.set_xlim(0,105); ax.set_ylim(0,105)
for _,r_ in pd.concat([top.nlargest(7,'diff'),top.nsmallest(7,'diff')]).iterrows(): ax.annotate(r_.name2,(r_.value/1000,r_.mkt/1000),fontsize=6.5,xytext=(3,2),textcoords='offset points')
ax.set_xlabel('our value (thousands)'); ax.set_ylabel(f'market value, curve matched to ours (thousands)'); ax.legend()
ax.set_title(f'Dynasty, site default: market 1:1 prices on our curve (power {p:.2f})\nSpearman {spearmanr(top.mkt,top.value).correlation:.3f}')
fig.tight_layout(); fig.savefig('compare_add4/dynasty_a8_curve_matched.png',dpi=130)
pk=P[P.grp=='PICK']; print(pk[pk.asset.isin(['2027early1stpi','2027mid1stpi','2027late1stpi','2027mid2ndpi','2027mid3rdpi'])][['asset','mkt']].round(0))
