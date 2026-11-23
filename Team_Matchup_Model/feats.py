# Point-in-time features: for each game (season s, week w) use only games before week w of season s (plus earlier seasons).
import pandas as pd, numpy as np, time
G=pd.read_pickle("games.pkl")
T=["tot","pas","rus","rec","QB","RB","WR","TE"]
G=G.sort_values(["season","week"]).reset_index(drop=True)
times=sorted(set(zip(G.season,G.week)))
DECAYS=[0.0,0.25,0.5,0.75]
recs=[]
t0=time.time()
for (s,w) in times:
    if s==2016: continue
    H=G[((G.season<s)|((G.season==s)&(G.week<w)))&(G.season>=s-2)]
    cur=G[(G.season==s)&(G.week==w)]
    Hc=H[H.season==s]
    feat={}
    for d in DECAYS:
        wt=np.where(H.season==s,1.0,np.where(H.season==s-1,d,d*d*0.0))  # use 1 prior season only
        Hw=H.assign(_w=wt)
        Hw=Hw[Hw._w>0]
        L=(Hw[T].mul(Hw._w,axis=0).sum()/Hw._w.sum()/1)  # weighted league mean per team-game
        # offense
        o=Hw.groupby("team").apply(lambda x: pd.Series(np.r_[ (x[T].mul(x._w,axis=0).sum()/x._w.sum()).values, x._w.sum()], index=T+["n"]),include_groups=False)
        dd=Hw.groupby("opp").apply(lambda x: pd.Series(np.r_[ (x[T].mul(x._w,axis=0).sum()/x._w.sum()).values, x._w.sum()], index=T+["n"]),include_groups=False)
        feat[d]=(L,o,dd)
    # last-3 offense / defense in current season (fallback NaN)
    l3o=Hc.sort_values("week").groupby("team").tail(3).groupby("team")[T].mean()
    l3d=Hc.sort_values("week").groupby("opp").tail(3).groupby("opp")[T].mean()
    for _,r in cur.iterrows():
        rec={"season":s,"week":w,"team":r.team,"opp":r.opp}
        for t in T: rec["y_"+t]=r[t]
        for d,(L,o,dd) in feat.items():
            for t in T:
                rec[f"L_{t}_{d}"]=L[t]
                rec[f"o_{t}_{d}"]=o.loc[r.team,t] if r.team in o.index else np.nan
                rec[f"d_{t}_{d}"]=dd.loc[r.opp,t] if r.opp in dd.index else np.nan
            rec[f"on_{d}"]=o.loc[r.team,"n"] if r.team in o.index else 0
            rec[f"dn_{d}"]=dd.loc[r.opp,"n"] if r.opp in dd.index else 0
        for t in T:
            rec[f"o3_{t}"]=l3o.loc[r.team,t] if r.team in l3o.index else np.nan
            rec[f"d3_{t}"]=l3d.loc[r.opp,t] if r.opp in l3d.index else np.nan
        recs.append(rec)
F=pd.DataFrame(recs)
F.to_pickle("feats.pkl")
print(F.shape, time.time()-t0)
