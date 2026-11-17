import pandas as pd, numpy as np, statsmodels.formula.api as smf, warnings
from scipy.stats import spearmanr
warnings.filterwarnings('ignore')
S='./'
h=pd.read_pickle(S+'h.pkl').copy()
G=['A+','A','A-','B+','B','B-','C+','C','C-','D','F']
h['pre_i']=h.pre_grade.map(G.index); h['post_i']=h.post_grade.map(G.index)
h['dropn']=h.post_i-h.pre_i
h['gap']=(h.pre_pctile-h.post_pctile).clip(lower=0)
preA=h.pre_i<=2
sets={'V0 current post grade':None,
 'V1 pre-A players (all)':preA,
 'V1b pre-A who fell out of A':preA&(h.post_i>2),
 'V2 pre-A who dropped 2+ steps':preA&(h.dropn>=2),
 'V2b anyone who dropped 2+ steps':(h.dropn>=2)}
print({k:(int(v.sum()) if v is not None else len(h)) for k,v in sets.items()})
base='C(position) + C(position):post_score'
classes=sorted(h['class'].unique())
res={}
for name,mask in sets.items():
    h['x']=0.0 if mask is None else np.where(mask,h.gap,0.0)
    P=pd.DataFrame(index=h.index,columns=['p1','p2','p3'],dtype=float); W=[]
    for c in classes:
        tr=h[h['class']!=c]; te=h[h['class']==c]
        for k in (1,2,3):
            f=f'h{k} ~ {base}' + ('' if mask is None else ' + x')
            m=smf.logit(f,tr).fit(disp=0,method='bfgs',maxiter=500)
            P.loc[te.index,f'p{k}']=m.predict(te)
            if k==3 and mask is not None: W.append(m.params['x'])
    # enforce monotone
    P['p2']=np.maximum(P.p2,P.p1); P['p3']=np.maximum(P.p3,P.p2)
    res[name]=(P,W)
def metrics(P,idx):
    out={}
    for k in (1,2,3):
        y=h.loc[idx,f'h{k}'].values; p=P.loc[idx,f'p{k}'].clip(1e-4,1-1e-4).values
        out[f'll{k}']=-np.mean(y*np.log(p)+(1-y)*np.log(1-p)); out[f'br{k}']=np.mean((p-y)**2)
        out[f'pred{k}']=p.mean(); out[f'act{k}']=y.mean()
    return out
def auc(y,p):
    from scipy.stats import rankdata
    r=rankdata(p); n1=y.sum(); n0=len(y)-n1; return (r[y==1].sum()-n1*(n1+1)/2)/(n1*n0)
rows=[]
for name,(P,W) in res.items():
    m=metrics(P,h.index)
    m['auc3']=auc(h.h3.values,P.p3.values); m['auc2']=auc(h.h2.values,P.p2.values)
    ex=P.p1+P.p2+P.p3; act=4-h.tier.clip(upper=4)
    m['rho_in_class']=np.mean([spearmanr(ex[h['class']==c],act[h['class']==c]).correlation for c in classes])
    m['w_mean']=np.mean(W) if W else np.nan; m['w_min']=np.min(W) if W else np.nan; m['w_max']=np.max(W) if W else np.nan
    rows.append(pd.Series(m,name=name))
R=pd.DataFrame(rows); pd.set_option('display.width',250)
print(R[["ll3","br3","auc2","auc3","rho_in_class","w_mean"]].round(4).to_string())
# paired class-level bootstrap of logloss diff (sum of 3 tiers) vs V0
def ll_vec(P):
    t=0
    for k in (1,2,3):
        y=h[f'h{k}']; p=P[f'p{k}'].clip(1e-4,1-1e-4); t=t-(y*np.log(p)+(1-y)*np.log(1-p))
    return t
b0=ll_vec(res['V0 current post grade'][0]); rng=np.random.default_rng(5)
for name in list(res)[1:]:
    dl=(ll_vec(res[name][0])-b0); bycls=dl.groupby(h['class']).sum().values
    bs=[rng.choice(bycls,len(bycls)).sum() for _ in range(4000)]
    print(name,'total logloss change',round(dl.sum(),2),'CI',np.percentile(bs,[2.5,97.5]).round(2),'classes improved',int((bycls<0).sum()),'/14')
# calibration on affected groups
grp={'pre-A fell out':preA&(h.post_i>2),'pre-A dropped 2+':preA&(h.dropn>=2),'all dropped 2+':h.dropn>=2,'everyone else (not pre-A fallers)':~(preA&(h.post_i>2))}
for gname,gm in grp.items():
    idx=h.index[gm]; line=[gname,len(idx),'actual any %.2f top2 %.2f top %.2f'%(h.loc[idx,'h3'].mean(),h.loc[idx,'h2'].mean(),h.loc[idx,'h1'].mean())]
    for name,(P,W) in res.items():
        line.append(name.split()[0]+' %.2f/%.2f/%.2f'%(P.loc[idx,'p3'].mean(),P.loc[idx,'p2'].mean(),P.loc[idx,'p1'].mean()))
    print(*line,sep=' | ')
pd.to_pickle((h,res),S+'bt.pkl')
