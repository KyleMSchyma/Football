import pandas as pd, numpy as np, rdata, warnings
warnings.filterwarnings('ignore')
d=pd.read_csv('PostDraft_Model/pd_post_player_grades.csv')
mt=[]
for p in ['qb','rb','wr','te']:
    t=rdata.read_rds(f'{p.upper()}_Model/{p}_model_table.rds')
    pts='total_ppr_3yr' if p=='wr' else 'total_pts_3yr'
    t=t.assign(position=p.upper(),pts3=t[pts])[['position','draft_season','pick','ppg_3yr','games_3yr','pts3','n_years_obs']]
    mt.append(t)
mt=pd.concat(mt); mt['draft_season']=mt.draft_season.astype(int); mt['pick']=mt.pick.astype(int)
d=d.merge(mt,left_on=['position','class','pick'],right_on=['position','draft_season','pick'],how='left')
print('ppg match', d.ppg_3yr.notna().mean())
print((d.pts3-d.nfl_ppr_pts).abs().describe())
print((d.pts3/d.games_3yr - d.ppg_3yr).abs().describe())
cut={'QB':(8,16,24),'RB':(8,16,24),'WR':(12,24,36),'TE':(6,12,18)}
def tier(r):
    b=r.nfl_best_finish
    if pd.isna(b): return np.nan if not r.outcome_complete else 4
    c=cut[r.position]; return 1 if b<=c[0] else 2 if b<=c[1] else 3 if b<=c[2] else 4
d['tier']=d.apply(tier,axis=1)
print(pd.crosstab(d.tier,d.nfl_tier))
A=['A+','A','A-']
d=d[d.pre_grade.notna()]
d['grp']=np.select([d.pre_grade.isin(A)&~d.post_grade.isin(A), d.pre_grade.isin(A)&d.post_grade.isin(A), ~d.pre_grade.isin(A)&d.post_grade.isin(A)],['Fell out of A','Stayed A','Rose into A'],'Below A- both')
d.to_pickle('./d.pkl')
