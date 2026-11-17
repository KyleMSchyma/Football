import pandas as pd, numpy as np
S='./'
h,res=pd.read_pickle(S+'bt.pkl')
sc=pd.read_csv('PostDraft_Model/pd_post_grade_scale.csv')
G=['A+','A','A-','B+','B','B-','C+','C','C-','D','F']
def grade(pos,pct):
    s=sc[sc.position==pos].sort_values('pct_from',ascending=False)
    for _,r in s.iterrows():
        if pct>=r.pct_from: return r.grade
    return 'F'
out={}
for key in ['V0 current post grade','V1 pre-A players (all)','V2 pre-A who dropped 2+ steps']:
    P=res[key][0]; ex=P.p1+P.p2+P.p3
    pct=ex.groupby(h.position).rank(pct=True)
    out[key]=[grade(p,q) for p,q in zip(h.position,pct)]
h['g0']=out['V0 current post grade']; h['g1']=out['V1 pre-A players (all)']; h['g2']=out['V2 pre-A who dropped 2+ steps']
print('V0 regrade matches stored post grade:', (h.g0==h.post_grade).mean().round(2))
f=h[(h.pre_i<=2)&(h.post_i>2)].copy()
for g in ['post_grade','g1','g2']:
    f['b']=f[g].str[0]; print(g, f.groupby('b').agg(n=('h3','size'),any=('h3','mean'),ppg=('ppg','mean')).round(2).T.to_dict())
print('fallers back in A range: V1', f.g1.isin(G[:3]).sum(), 'V2', f.g2.isin(G[:3]).sum())
# all players hit rate by grade band under V1 vs current
for g in ['post_grade','g1']:
    h['b']=h[g].str[0]; print(g, h.groupby('b').agg(n=('h3','size'),any=('h3','mean')).round(2).T.to_dict())
f['step_up']=f.post_grade.map(G.index)-f.g1.map(G.index)
print(f.sort_values('step_up',ascending=False)[['position','class','name','pick','pre_grade','post_grade','g1','g2','nfl_outcome']].head(25).to_string())
f[['position','class','name','pick','pre_grade','post_grade','g1','g2','nfl_outcome','ppg']].rename(columns={'g1':'blend_grade_v1_preA','g2':'blend_grade_v2_drop2'}).to_csv('./backtest_faller_regrades.csv',index=False)
