import pandas as pd, numpy as np
d=pd.read_pickle('./d.pkl')
h=d[d['class']<=2023].copy()
print('ppg NA by games', h[h.ppg_3yr.isna()].games_3yr.describe())
h['pts3']=h.pts3.fillna(h.nfl_ppr_pts)
h['games_3yr']=pd.to_numeric(h.games_3yr)
h['ppg']=np.where(h.games_3yr>0,h.pts3/h.games_3yr,np.nan)
for k in (1,2,3): h[f'h{k}']=(h.tier<=k).astype(int)
def wil(x,n,z=1.96):
    if n==0: return (np.nan,np.nan)
    p=x/n; den=1+z*z/n; c=(p+z*z/(2*n))/den; w=z*np.sqrt(p*(1-p)/n+z*z/(4*n*n))/den; return c-w,c+w
order=['Stayed A','Fell out of A','Rose into A','Below A- both']
def summ(g):
    n=len(g); lo,hi=wil(g.h3.sum(),n)
    return pd.Series({'n':n,'med_pick':g.pick.median(),'top':g.h1.mean(),'top2':g.h2.mean(),'any':g.h3.mean(),'any_lo':lo,'any_hi':hi,'ppg':g.ppg.mean(),'med_ppg':g.ppg.median(),'pts3':g.pts3.mean(),'zero_games':(g.games_3yr.fillna(0)==0).mean()})
pd.set_option('display.width',250)
print(h.groupby('grp').apply(summ).loc[order].round(3))
print(h.groupby(['position','grp']).apply(summ).round(2).to_string())
h.to_pickle('./h.pkl')
