import pandas as pd, numpy as np, statsmodels.formula.api as smf, warnings
warnings.filterwarnings('ignore')
S='./'
h,_=pd.read_pickle(S+'bt.pkl'); d=pd.read_pickle(S+'d.pkl')
sc=pd.read_csv('PostDraft_Model/pd_post_grade_scale.csv')
G=['A+','A','A-','B+','B','B-','C+','C','C-','D','F']
for x in (h,d):
    x['pre_i']=x.pre_grade.map(G.index); x['post_i']=x.post_grade.map(G.index); x['x']=((x.pre_i<=2)&(x.post_i>2)).astype(float)
base='C(position) + C(position):post_score'
ms={k:smf.logit(f'h{k} ~ {base} + x',h).fit(disp=0,method='bfgs',maxiter=500) for k in (1,2,3)}
m0={k:smf.logit(f'h{k} ~ {base}',h).fit(disp=0,method='bfgs',maxiter=500) for k in (1,2,3)}
print('odds mult', {k:round(np.exp(ms[k].params['x']),2) for k in ms})
def ex(models,df): return sum(models[k].predict(df) for k in (1,2,3))
ref=h.assign(e0=ex(m0,h))
def grade(pos,val):
    pct=(ref[ref.position==pos].e0<=val).mean()
    s=sc[sc.position==pos].sort_values('pct_from',ascending=False)
    for _,r in s.iterrows():
        if pct>=r.pct_from: return r.grade
    return 'F'
r=d[(d['class']>=2024)&(d.x==1)].copy()
r['p_any_now']=m0[3].predict(r); r['p_any_blend']=ms[3].predict(r)
r['blend_grade']=[grade(p,v) for p,v in zip(r.position,ex(ms,r))]
print(r[['class','position','name','pick','pre_grade','post_grade','blend_grade','p_any_now','p_any_blend']].round(2).to_string())
r[['class','position','name','pick','pre_grade','post_grade','blend_grade','p_any_now','p_any_blend','nfl_outcome']].round(3).to_csv('./fallers_2024_2026_blend.csv',index=False)
