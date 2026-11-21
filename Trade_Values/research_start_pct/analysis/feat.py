import pandas as pd, numpy as np
D='./data/'
POS=['QB','RB','WR','TE']
REF={'QB':.9,'RB':.6,'WR':.8,'TE':.7}       # snap share of a full-time player
ROLE={'QB':.5,'RB':.45,'WR':.6,'TE':.5}     # snap share that counts as a "starter" game
w=pd.read_pickle(D+'weekly.pkl'); pl=pd.read_pickle(D+'players.pkl')
# position = modal over career
pos=w.groupby('player_id').position.agg(lambda s:s.value_counts().index[0]).rename('pos')
w=w.merge(pos,on='player_id')
pct=w.offense_pct
w['role']=np.where(w.pos=='QB',(w.attempts.fillna(0)>=15)|(pct.fillna(1)>=.5),pct.fillna(1)>=w.pos.map(ROLE)).astype(float)
w['sw']=np.minimum(1,pct.fillna(w.pos.map(REF))/w.pos.map(REF))
w['pts2']=w.pts**2
CUTN={'QB':12,'RB':24,'WR':36,'TE':12}
w['wrank']=w.groupby(['season','week','pos']).pts.rank(ascending=False,method='min')
w['st']=(w.wrank<=w.pos.map(CUTN)).astype(float)
cap=w.groupby('pos').pts.quantile(.99); w['ptsx']=np.minimum(w.pts,w.pos.map(cap))
pl=pl.drop_duplicates('gsis_id').set_index('gsis_id')
w['dpick']=w.player_id.map(pl.draft_pick); w['rk']=w.player_id.map(pl.rookie_season)
def agg(x):
    g=x.groupby('player_id')
    o=pd.DataFrame({'n':g.size(),'pts':g.pts.sum(),'pts2':g.pts2.sum(),'nr':g.role.sum(),
       'ptsr':(x.pts*x.role).groupby(x.player_id).sum(),'nw':g.sw.sum(),'ptsw':(x.pts*x.sw).groupby(x.player_id).sum(),
       'snap':g.offense_pct.mean(),'ns':g.st.sum(),'med':g.pts.median(),'ptsx':g.ptsx.sum()})
    return o
def snapshot(yr,cut):
    cur=w[(w.season==yr)&(w.week<=cut)]
    info=cur.groupby('player_id').agg(name=('player_display_name','last'),team=('team','last'),pos=('pos','first'))
    c=agg(cur).add_suffix('_c'); h=agg(w[(w.season>=yr-3)&(w.season<=yr-1)]).add_suffix('_h')
    d=info.join(c).join(h).fillna({k:0 for k in h.columns if k not in('snap_h','med_h')})
    d['dpick']=d.index.map(pl.draft_pick); d['rk']=d.index.map(pl.rookie_season)
    d['lpick']=np.log(d.dpick.fillna(262)); d['exp']=np.clip(yr-d.rk.fillna(yr),0,4); d['season']=yr
    return d.reset_index()
def target(yr,w0,w1):
    t=w[(w.season==yr)&(w.week>=w0)&(w.week<=w1)].groupby('player_id').agg(n_t=('pts','size'),pts_t=('pts','sum'))
    t['ppg_t']=t.pts_t/t.n_t; return t
# draft-capital prior, fit on seasons yr-10..yr-1 (season-level PPG weighted by games)
seas=w.groupby(['player_id','season']).agg(g=('pts','size'),pts=('pts','sum'),pos=('pos','first'),dpick=('dpick','first'),rk=('rk','first')).reset_index()
seas['lp']=np.log(seas.dpick.fillna(262)); seas['ex']=np.clip(seas.season-seas.rk.fillna(seas.season),0,4)
def X(lp,ex):
    return np.column_stack([np.ones(len(lp)),lp,lp**2,np.maximum(lp-np.log(32),0)**2]+[(ex==k).astype(float) for k in range(1,5)])
PRIOR={}
def prior(d,yr):
    out=np.full(len(d),np.nan)
    for p in POS:
        key=(yr,p)
        if key not in PRIOR:
            tr=seas[(seas.season<yr)&(seas.season>=yr-10)&(seas.pos==p)]
            Xm=X(tr.lp.values,tr.ex.values); W=tr.g.values
            PRIOR[key]=np.linalg.lstsq(Xm*np.sqrt(W)[:,None],(tr.pts/tr.g).values*np.sqrt(W),rcond=None)[0]
        i=(d.pos==p).values
        out[i]=X(d.lpick.values[i],d.exp.values[i])@PRIOR[key]
    return np.maximum(out,0)
rows=[]
for yr in range(2016,2026):
    # redraft: week-9 snapshot -> weeks 10-18
    d=snapshot(yr,9).join(target(yr,10,18),on='player_id'); d['h']='redraft'; d['prior']=prior(d,yr); rows.append(d)
    # next season: full-season snapshot -> next season
    if yr<=2025:
        d=snapshot(yr,18).join(target(yr+1,1,18),on='player_id'); d['h']='next'; d['prior']=prior(d,yr+1 if False else yr); rows.append(d)
# 2026 live snapshot (week 11), no target
d=snapshot(2026,11); d['h']='now'; d['prior']=prior(d,2026); rows.append(d)
A=pd.concat(rows,ignore_index=True); A.to_pickle(D+'snapshots.pkl')
print(A.groupby('h').size()); print(A[A.h=='redraft'].nr_c.div(A.n_c).describe())
