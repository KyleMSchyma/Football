import pandas as pd, numpy as np
h=pd.read_pickle('./h.pkl')
h['rb']=pd.cut(h['round'],[0,1,2,3,7],labels=['R1','R2','R3','R4-7'])
for col in ['h1','h2','h3','ppg']:
    h['exp_'+col]=h.groupby(['position','rb'])[col].transform('mean')
rng=np.random.default_rng(1)
for g in ['Fell out of A','Stayed A','Rose into A','Below A- both']:
    s=h[h.grp==g]; diff=(s.h3-s.exp_h3).values
    bs=[rng.choice(diff,len(diff)).mean() for _ in range(4000)]
    print(g,len(s),'any',round(s.h3.mean(),3),'pickexp',round(s.exp_h3.mean(),3),'model p_any',round(s.p_any.mean(),3),'CI',np.percentile(bs,[2.5,97.5]).round(3),
      'top2',round(s.h2.mean(),3),round(s.exp_h2.mean(),3),round(s.p_top2.mean(),3),'top',round(s.h1.mean(),3),round(s.exp_h1.mean(),3),round(s.p_top.mean(),3),'ppg',round(s.ppg.mean(),2),round(s.exp_ppg.mean(),2))
# by position fallers model vs actual
s=h[h.grp=='Fell out of A']
print(s.groupby('position')[['h3','p_any','exp_h3','h2','p_top2']].mean().round(2))
# fallers by post grade band
s['pb']=s.post_grade.str[0]
print(s.groupby('pb').agg(n=('h3','size'),any=('h3','mean'),p_any=('p_any','mean'),ppg=('ppg','mean')).round(2))
d=pd.read_pickle('./d.pkl')
r=d[(d['class']>=2024)&(d.grp=='Fell out of A')].sort_values(['class','position'])
print(r[['position','class','name','pick','pre_grade','post_grade','nfl_outcome']].to_string())
print(d[d['class']>=2024].grp.value_counts())
