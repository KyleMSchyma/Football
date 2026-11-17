import pandas as pd, numpy as np, statsmodels.api as sm
S='./'
h,_=pd.read_pickle(S+'bt.pkl')
h['flag']=((h.pre_i<=2)&(h.post_i>2)).astype(float)
lg=lambda p: np.log(np.clip(p,1e-4,1-1e-4)/(1-np.clip(p,1e-4,1-1e-4)))
pcols={1:'p_top',2:'p_top2',3:'p_any'}
def fit(df,k):
    X=sm.add_constant(df[['flag']]); m=sm.GLM(df[f'h{k}'],X,family=sm.families.Binomial(),offset=lg(df[pcols[k]])).fit(); return m.params['flag']
print('full-data odds mult', {k:round(np.exp(fit(h,k)),2) for k in (1,2,3)})
# LOCO
P=pd.DataFrame(index=h.index,columns=[1,2,3],dtype=float)
for c in sorted(h['class'].unique()):
    tr=h[h['class']!=c]; te=h['class']==c
    for k in (1,2,3):
        b=fit(tr,k); z=lg(h.loc[te,pcols[k]])+b*h.loc[te,'flag']; P.loc[te,k]=1/(1+np.exp(-z))
P[2]=np.maximum(P[2],P[1]); P[3]=np.maximum(P[3],P[2])
def ll(y,p): p=np.clip(p,1e-4,1-1e-4); return -(y*np.log(p)+(1-y)*np.log(1-p))
d=sum(ll(h[f'h{k}'],P[k])-ll(h[f'h{k}'],h[pcols[k]].clip(1e-4,1-1e-4)) for k in (1,2,3))
bc=d.groupby(h['class']).sum().values; rng=np.random.default_rng(3)
print('LOCO logloss change',round(d.sum(),2),np.percentile([rng.choice(bc,14).sum() for _ in range(4000)],[2.5,97.5]).round(2),'classes better',(bc<0).sum())
f=h.flag==1; print('fallers actual',h.loc[f,'h3'].mean().round(3),'model',h.loc[f,'p_any'].mean().round(3),'mixed',P.loc[f,3].mean().round(3))
