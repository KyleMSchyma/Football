# v2 inputs from nflverse play-by-play: closing betting lines, home/away, roof, weather (known before kickoff)
# and per-game offense/defense efficiency (EPA/play, success rate, plays, pass rate), turned into point-in-time averages.
import pandas as pd, numpy as np, sys
DL=sys.argv[1] if len(sys.argv)>1 else "../dl"
REMAP={"OAK":"LV","SD":"LAC","STL":"LA"}
cols=['game_id','season','week','season_type','home_team','away_team','posteam','defteam','spread_line','total_line','roof','temp','wind','epa','success','play_type','pass']
pb=pd.concat([pd.read_parquet(f"{DL}/pbp_{s}.parquet",columns=cols) for s in range(2016,2027)])
pb=pb[pb.season_type=="REG"]
for c in ["home_team","away_team","posteam","defteam"]: pb[c]=pb[c].replace(REMAP)
g=pb.drop_duplicates("game_id")[["game_id","season","week","home_team","away_team","spread_line","total_line","roof","temp","wind"]]
rows=[]
for _,r in g.iterrows():
    for team,opp,home in [(r.home_team,r.away_team,1),(r.away_team,r.home_team,0)]:
        sp=r.spread_line if home else -r.spread_line   # nflverse spread_line: points the home team is favoured by
        rows.append(dict(season=r.season,week=r.week,team=team,opp=opp,home=home,total_line=r.total_line,team_spread=sp,
                         implied=r.total_line/2+sp/2,dome=int(r.roof in("dome","closed")),wind=0 if r.roof in("dome","closed") else (r.wind if pd.notna(r.wind) else 8),
                         temp=70 if r.roof in("dome","closed") else (r.temp if pd.notna(r.temp) else 55)))
C=pd.DataFrame(rows)
pl=pb[pb.play_type.isin(["pass","run"])&pb.epa.notna()]
eff=pl.groupby(["season","week","posteam","defteam"]).agg(epa=("epa","mean"),succ=("success","mean"),plays=("epa","size"),passrate=("pass","mean")).reset_index().rename(columns={"posteam":"team","defteam":"opp"})
E=["epa","succ","plays","passrate"]
eff=eff.sort_values(["season","week"])
# point-in-time: weighted average over prior games, current season weight 1, last season 0.25; with games count
out=[]
times=sorted(set(zip(eff.season,eff.week)))
for (s,w) in times:
    if s==2016: continue
    H=eff[((eff.season==s)&(eff.week<w))|(eff.season==s-1)].copy(); H["_w"]=np.where(H.season==s,1.0,0.25)
    L=(H[E].mul(H._w,axis=0).sum()/H._w.sum())
    def agg(key):
        a=H.groupby(key).apply(lambda x: pd.Series(np.r_[(x[E].mul(x._w,axis=0).sum()/x._w.sum()).values,x._w.sum()],index=E+["n"]),include_groups=False)
        return a
    o=agg("team"); d=agg("opp")
    cur=C[(C.season==s)&(C.week==w)]
    for _,r in cur.iterrows():
        rec=dict(season=s,week=w,team=r.team)
        for m in E:
            rec["L_"+m]=L[m]; rec["o_"+m]=o.loc[r.team,m] if r.team in o.index else L[m]; rec["d_"+m]=d.loc[r.opp,m] if r.opp in d.index else L[m]
        rec["o_n"]=o.loc[r.team,"n"] if r.team in o.index else 0; rec["d_n"]=d.loc[r.opp,"n"] if r.opp in d.index else 0
        out.append(rec)
X=pd.DataFrame(out).merge(C,on=["season","week","team"],how="left")
print(X.shape, X.isna().sum()[X.isna().sum()>0])
X.to_pickle("feats2.pkl")
