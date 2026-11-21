import pandas as pd, numpy as np, glob, os
D='./data/'
POS=['QB','RB','WR','TE']
w=pd.concat([pd.read_csv(f'{D}spw{y}.csv.gz',low_memory=False,usecols=['player_id','player_display_name','position','season','week','season_type','team','attempts','carries','targets','receptions','fantasy_points_ppr']) for y in range(2012,2027)])
w=w[(w.season_type=='REG')&w.position.isin(POS)].copy()
w['pts']=w.fantasy_points_ppr.fillna(0)
pl=pd.read_csv(D+'players.csv.gz',low_memory=False,usecols=['gsis_id','pfr_id','display_name','draft_pick','draft_round','rookie_season','birth_date','position'])
sn=pd.concat([pd.read_csv(f'{D}snap{y}.csv.gz') for y in range(2013,2027)])
sn=sn[sn.game_type=='REG']
# team-week schedule from snaps (all players)
tw=sn[['season','week','team']].drop_duplicates()
sn=sn.merge(pl[['pfr_id','gsis_id']].dropna().drop_duplicates('pfr_id'),left_on='pfr_player_id',right_on='pfr_id',how='left')
print('snap map rate (skill pos):', sn[sn.position.isin(POS)].gsis_id.notna().mean())
sn=sn[sn.gsis_id.notna()][['gsis_id','season','week','team','offense_snaps','offense_pct']].drop_duplicates(['gsis_id','season','week'])
w=w.merge(sn.rename(columns={'gsis_id':'player_id'})[['player_id','season','week','offense_snaps','offense_pct']],on=['player_id','season','week'],how='left')
print('stat rows with snap pct', w[w.season>=2013].offense_pct.notna().mean())
# snap rows with offense snaps but no stat row = played but no stats -> add as 0-pt games? live uses stat rows only. keep a flag table
w.to_pickle(D+'weekly.pkl'); tw.to_pickle(D+'teamweeks.pkl'); pl.to_pickle(D+'players.pkl')
sn.to_pickle(D+'snaps.pkl')
print(w.groupby('season').size().tail(4)); print(w[w.season==2026].week.max())
