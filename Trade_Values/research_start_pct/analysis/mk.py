import pandas as pd, numpy as np, json, re, unicodedata
R='/home/user/Football/Trade_Values/research_start_pct/'
def key(n,p):
    n=unicodedata.normalize('NFKD',str(n)).encode('ascii','ignore').decode().lower()
    n=re.sub(r'\b(jr|sr|ii|iii|iv|v)\b','',n); n=re.sub(r'[^a-z]','',n); return n+p.lower()
es=pd.read_csv(R+'espn_ownership_2026.csv'); es['k']=[key(a,b) for a,b in zip(es.name,es.position)]
es=es.sort_values('percent_owned',ascending=False).drop_duplicates('k')
dd=json.loads(open(R+'dd.js').read().split('=',1)[1].strip().rstrip(';'))
ddd=pd.DataFrame(dd['dynasty'],columns=['k','pos','team','dd_dyn']); ddr=pd.DataFrame(dd['redraft'],columns=['k','pos','team','dd_red'])
fix=lambda s: re.sub(r'(jr|sr|ii|iii|iv)(qb|rb|wr|te)$',r'\2',s)
ddd['k']=ddd.k.map(fix); ddr['k']=ddr.k.map(fix)
dy=pd.read_csv(R+'dv_v4_board.csv'); ro=pd.read_csv(R+'dv_ros_2026_board.csv')
for d in (dy,ro): d['k']=[key(a,b) for a,b in zip(d.name,d.pos)]
dy=dy.merge(es[['k','percent_owned','percent_started','pro_team_id']],on='k',how='left').merge(ddd[['k','dd_dyn']],on='k',how='left')
ro=ro.merge(es[['k','percent_owned','percent_started','pro_team_id']],on='k',how='left').merge(ddr[['k','dd_red']],on='k',how='left')
print('dynasty board espn match', dy.percent_owned.notna().mean(), 'top200', dy.head(200).percent_owned.notna().mean(), 'dd match top200', dy.head(200).dd_dyn.notna().mean())
print('redraft board espn match top200', ro.head(200).percent_owned.notna().mean(), 'dd', ro.head(200).dd_red.notna().mean())
print(dy.head(200)[dy.head(200).percent_owned.isna()][['name','pos','team']].to_string())
print(ro.status.value_counts(dropna=False))
dy.to_pickle(R+'../../../../dy.pkl') if False else None
dy.to_csv('./work/dy.csv',index=False); ro.to_csv('./work/ro.csv',index=False)
