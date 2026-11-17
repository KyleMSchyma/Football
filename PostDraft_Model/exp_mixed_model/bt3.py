import pandas as pd, numpy as np, statsmodels.formula.api as smf, warnings
from scipy.stats import spearmanr, rankdata
warnings.filterwarnings('ignore')
S='./'
h,_=pd.read_pickle(S+'bt.pkl')
sc=pd.read_csv('PostDraft_Model/pd_post_grade_scale.csv')
G=['A+','A','A-','B+','B','B-','C+','C','C-','D','F']
preA=h.pre_i<=2; fell=preA&(h.post_i>2); d2=preA&(h.dropn>=2); early=h['round']<=3
specs={'V0':(None,None),
 'V1 flat bump, pre-A':(preA,'flat'),
 'V1 flat bump, pre-A fell':(fell,'flat'),
 'V2 flat bump, pre-A drop2+':(d2,'flat'),
 'V1 flat bump, pre-A fell, rounds 1-3':(fell&early,'flat'),
 'V2 flat bump, pre-A drop2+, rounds 1-3':(d2&early,'flat'),
 'V1 gap, pre-A':(preA,'gap'),
 'V2 gap, pre-A drop2+':(d2,'gap'),
}
classes=sorted(h['class'].unique()); base='C(position) + C(position):post_score'
def auc(y,p):
    r=rankdata(p); n1=y.sum(); n0=len(y)-n1; return (r[y==1].sum()-n1*(n1+1)/2)/(n1*n0)
def grade(pos,pct):
    s=sc[sc.position==pos].sort_values('pct_from',ascending=False)
    for _,r in s.iterrows():
        if pct>=r.pct_from: return r.grade
    return 'F'
rows=[]; Ps={}
for name,(mask,kind) in specs.items():
    h['x']=0.0 if mask is None else np.where(mask,1.0 if kind=='flat' else h.gap,0.0)
    P=pd.DataFrame(index=h.index,columns=['p1','p2','p3'],dtype=float); W=[]
    for c in classes:
        tr=h[h['class']!=c]; te=h[h['class']==c]
        for k in (1,2,3):
            m=smf.logit(f'h{k} ~ {base}'+('' if mask is None else ' + x'),tr).fit(disp=0,method='bfgs',maxiter=500)
            P.loc[te.index,f'p{k}']=m.predict(te)
            if k==3 and mask is not None: W.append(m.params['x'])
    P['p2']=np.maximum(P.p2,P.p1); P['p3']=np.maximum(P.p3,P.p2); Ps[name]=P
    ll=0
    for k in (1,2,3):
        y=h[f'h{k}']; p=P[f'p{k}'].clip(1e-4,1-1e-4); ll=ll-(y*np.log(p)+(1-y)*np.log(1-p))
    ex=P.p1+P.p2+P.p3; act=4-h.tier.clip(upper=4)
    rows.append(dict(spec=name,n=0 if mask is None else int(mask.sum()),ll=ll,auc3=auc(h.h3.values,P.p3.values),auc1=auc(h.h1.values,P.p1.values),
      rho=np.mean([spearmanr(ex[h['class']==c],act[h['class']==c]).correlation for c in classes]),
      odds_mult=np.exp(np.mean(W)) if W else np.nan,
      fell_pred=P.loc[fell,'p3'].mean(),fell_act=h.loc[fell,'h3'].mean(),
      fellDF_pred=P.loc[fell&~early,'p3'].mean(), fellDF_act=h.loc[fell&~early,'h3'].mean()))
b0=rows[0]['ll']; rng=np.random.default_rng(7); out=[]
for r in rows:
    dl=(r['ll']-b0).groupby(h['class']).sum().values
    bs=[rng.choice(dl,len(dl)).sum() for _ in range(4000)]
    out.append({**{k:v for k,v in r.items() if k!='ll'},'ll_change':dl.sum(),'ci_lo':np.percentile(bs,2.5),'ci_hi':np.percentile(bs,97.5),'cls_better':int((dl<-1e-9).sum())})
O=pd.DataFrame(out).set_index('spec'); pd.set_option('display.width',300)
print(O.round(3).to_string())
O.round(4).to_csv('./backtest_metrics.csv')
# grade view for best flat version
for name in ['V1 flat bump, pre-A fell','V2 flat bump, pre-A drop2+','V1 flat bump, pre-A fell, rounds 1-3']:
    P=Ps[name]; ex=P.p1+P.p2+P.p3; pct=ex.groupby(h.position).rank(pct=True)
    h['gn']=[grade(p,q) for p,q in zip(h.position,pct)]
    P0=Ps['V0']; ex0=P0.p1+P0.p2+P0.p3; pct0=ex0.groupby(h.position).rank(pct=True); h['g0']=[grade(p,q) for p,q in zip(h.position,pct0)]
    f=h[fell]; up=(f.g0.map(G.index)-f.gn.map(G.index))
    print(name,'avg steps up for fallers',round(up.mean(),2),'back to A range',int(f.gn.isin(G[:3]).sum()))
    f2=f.assign(b=f.gn.str[0]); print('  hit by new band',f2.groupby('b').h3.agg(['size','mean']).round(2).to_dict())
    h['b0']=h.g0.str[0]; h['bn']=h.gn.str[0]
    print('  all players any-hit by band V0', h.groupby('b0').h3.mean().round(3).to_dict(),' new',h.groupby('bn').h3.mean().round(3).to_dict())
    h[f'grade_{name[:2]}_{"r13" if "rounds" in name else "all"}']=h.gn
h['grade_V0']=h.g0
h[fell][['position','class','name','round','pick','pre_grade','post_grade','grade_V0']+[c for c in h.columns if c.startswith('grade_V') and c!='grade_V0']+['nfl_outcome','ppg']].sort_values(['position','class']).to_csv('./backtest_faller_regrades.csv',index=False)
P=Ps['V1 flat bump, pre-A fell']; P0=Ps['V0']
f=h[fell]
print(pd.DataFrame({'n':f.groupby('position').size(),'act':f.groupby('position').h3.mean(),'V0':P0.loc[fell,'p3'].groupby(h.position).mean(),'V1':P.loc[fell,'p3'].groupby(h.position).mean(),
 'act_top2':f.groupby('position').h2.mean(),'V0_top2':P0.loc[fell,'p2'].groupby(h.position).mean(),'V1_top2':P.loc[fell,'p2'].groupby(h.position).mean()}).round(2))
# stability by era
for era,m in [('2010-2016',h['class']<=2016),('2017-2023',h['class']>=2017)]:
    i=fell&m; print(era,int(i.sum()),round(h.loc[i,'h3'].mean(),2),round(P0.loc[i,'p3'].mean(),2),round(P.loc[i,'p3'].mean(),2))
