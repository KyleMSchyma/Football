import pandas as pd, numpy as np
h=pd.read_pickle('./h.pkl')
h['rb']=pd.cut(h['round'],[0,1,2,3,7],labels=['R1','R2','R3','R4-7'])
# pick-matched: for each player, expected any-tier from same position x round band among ALL players
for col in ['h1','h2','h3','ppg','pts3']:
    h['exp_'+col]=h.groupby(['position','rb'])[col].transform('mean')
g=h.groupby('grp')[['h1','exp_h1','h2','exp_h2','h3','exp_h3','ppg','exp_ppg','pts3','exp_pts3']].mean().round(3)
print(g)
print(h.groupby(['position','grp'])[['h3','exp_h3','ppg','exp_ppg']].mean().round(2))
# fallers vs below-both within round band
f=h[h.grp.isin(['Fell out of A','Below A- both'])]
print(f.groupby(['rb','grp']).agg(n=('h3','size'),any=('h3','mean'),top2=('h2','mean'),ppg=('ppg','mean')).round(2))
fl=h[h.grp=='Fell out of A'].sort_values(['position','class'])
fl[['position','class','name','round','pick','pre_grade','post_grade','tier','nfl_outcome','ppg','pts3']].to_csv('./fallers.csv',index=False)
print(fl[['position','class','name','pick','pre_grade','post_grade','nfl_outcome','ppg']].round(1).to_string())
