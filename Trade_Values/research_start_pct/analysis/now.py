import pandas as pd, numpy as np, eval2 as E, evalm as M
from scipy.optimize import minimize
D=E.D; A=E.A
# SR with b fixed at 1 (strong version of the idea): fit k1,k2 only
def pred_b1(d,q): return E.predict(d,'SR',[q[0],q[1],np.log(2/1-1)*-1 if False else 0.0]) # placeholder
B1=np.log((1-(-1))/(2-1)) # sig(x,-1,2)=1 -> x = log((1+1)/(2-1)) = log 2
def fitb1(d):
    f=lambda q: np.sum(d.n_t*(d.ppg_t-E.predict(d,'SR',[q[0],q[1],B1]))**2)
    return minimize(f,[np.log(4),np.log(10)],method='Nelder-Mead').x
res=[]
for h,mt,ys in [('redraft',3,range(2019,2026)),('next',4,range(2018,2025))]:
    d=A[(A.h==h)&(A.n_c>=3)&(A.n_t>=mt)].copy()
    for p in E.POS:
        for y in ys:
            tr=E.add_r(d[(d.pos==p)&(d.season<y)],d[(d.pos==p)&(d.season<y)]); te=E.add_r(d[(d.pos==p)&(d.season==y)],d[(d.pos==p)&(d.season<y)])
            q=fitb1(tr); te['p_b1']=E.predict(te,'SR',[q[0],q[1],B1]); te['p_base']=E.predict(te,'base',E.fit(tr,'base')); te['h']=h; res.append(te)
R=pd.concat(res)
for h in ['redraft','next']:
    G=R[R.h==h]; f=lambda c: np.sqrt(np.average((G.ppg_t-G[c])**2,weights=G.n_t))
    print(h,'base',round(f('p_base'),3),'steady-weighted b=1',round(f('p_b1'),3))
# 2026 now: fit on all redraft-horizon rows (week-9 style) for each method
d=A[(A.h=='redraft')&(A.n_c>=3)&(A.n_t>=3)]
now=A[(A.h=='now')&(A.n_c>=3)].copy()
out=[]
for p in E.POS:
    tr=E.add_r(d[d.pos==p],d[d.pos==p]); te=E.add_r(now[now.pos==p],d[d.pos==p])
    te['base']=E.predict(te,'base',E.fit(tr,'base'))
    q=fitb1(tr); te['steady']=E.predict(te,'SR',[q[0],q[1],B1])
    te['nfl_start_only']=M.predict(te.assign(_s2p=1.0),'ST',M.fit(tr.assign(_s2p=1.0),'ST'))
    out.append(te)
N=pd.concat(out); N['ppg26']=N.pts_c/N.n_c; N['startable26']=N.ns_c/N.n_c; N['nfl_start26']=N.nr_c/N.n_c
N['d_steady']=N.steady-N.base; N['d_start']=N.nfl_start_only-N.base
c=['name','pos','team','n_c','ppg26','startable26','nfl_start26','base','steady','nfl_start_only']
top=N[N.base>=11]
print('\nbiggest drops under steady weighting'); print(top.nsmallest(10,'d_steady')[c].round(2).to_string(index=False))
print('\nbiggest gains under steady weighting'); print(top.nlargest(6,'d_steady')[c].round(2).to_string(index=False))
print('\nbiggest drops under NFL-starter-games-only'); print(top.nsmallest(8,'d_start')[c].round(2).to_string(index=False))
print(N[N.name.str.contains('Stroud')][c].round(2).to_string(index=False))
N.to_csv(D+'now_2026.csv',index=False)
