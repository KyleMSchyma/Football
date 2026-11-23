import pandas as pd, numpy as np, json, time, warnings
from sklearn.linear_model import PoissonRegressor, Ridge
warnings.filterwarnings("ignore")
G=pd.read_pickle("games.pkl"); F=pd.read_pickle("feats.pkl"); VC=json.load(open("varcomp.json"))
T=["tot","pas","rus","rec","QB","RB","WR","TE"]
TEAMS=sorted(G.team.unique()); ix={t:i for i,t in enumerate(TEAMS)}
def X_of(df):
    X=np.zeros((len(df),64)); r=np.arange(len(df))
    X[r,df.team.map(ix).values]=1; X[r,32+df.opp.map(ix).values]=1; return X
P=F[["season","week","team","opp"]+["y_"+t for t in T]].copy()
DEV=P.season<=2022
def rmse(y,p): return float(np.sqrt(np.mean((y-p)**2)))
tune={}
# --- baselines
for t in T:
    P[f"league_{t}"]=F[f"L_{t}_0.0"]                           # league average this season to date (wk1 -> last season)
    P[f"league_{t}"]=P[f"league_{t}"].fillna(F[f"L_{t}_0.5"])
    P[f"std_{t}"]=F[f"o_{t}_0.0"].fillna(P[f"league_{t}"])     # team season-to-date average
    P[f"naive_{t}"]=(F[f"o_{t}_0.0"].fillna(P[f"league_{t}"])+F[f"d_{t}_0.0"].fillna(P[f"league_{t}"])-P[f"league_{t}"])  # off + def - league
# --- Bühlmann credibility, multiplicative (offense relativity x defense relativity)
for t in T:
    ko0,kd0=VC[t]["off_k"],VC[t]["def_k"]
    best=None
    for d in [0.25,0.5,0.75]:
        for mo in [0.5,1,2]:
            for md in [0.5,1,2]:
                ko,kd=ko0*mo,kd0*md
                L=F[f"L_{t}_{d}"]; on=F[f"on_{d}"]; dn=F[f"dn_{d}"]
                ro=(F[f"o_{t}_{d}"]/L).fillna(1); rd=(F[f"d_{t}_{d}"]/L).fillna(1)
                Zo=on/(on+ko); Zd=dn/(dn+kd)
                p=L*(Zo*ro+1-Zo)*(Zd*rd+1-Zd)
                e=rmse(P.loc[DEV,"y_"+t],p[DEV])
                if best is None or e<best[0]: best=(e,d,mo,md,p)
    tune[f"cred_{t}"]=dict(decay=best[1],k_off=ko0*best[2],k_def=kd0*best[3],k_off_buhlmann=ko0,k_def_buhlmann=kd0)
    P[f"cred_{t}"]=best[4]
    # pure Bühlmann k (no tuning of k), same decay: shows theory vs tuned
    d=best[1]; L=F[f"L_{t}_{d}"]; on=F[f"on_{d}"]; dn=F[f"dn_{d}"]
    ro=(F[f"o_{t}_{d}"]/L).fillna(1); rd=(F[f"d_{t}_{d}"]/L).fillna(1)
    Zo=on/(on+ko0); Zd=dn/(dn+kd0); P[f"credB_{t}"]=L*(Zo*ro+1-Zo)*(Zd*rd+1-Zd)
print("cred done",flush=True)
# --- weekly refits: penalised Poisson GLM (log link, offense x defense rating factors) and Gaussian mixed model (BLUP)
times=sorted(set(zip(P.season,P.week)))
def weekly(kind,t,d,pen):
    out=pd.Series(np.nan,index=P.index)
    for (s,w) in times:
        H=G[((G.season==s)&(G.week<w))|((G.season==s-1)&(d>0))]
        cur=P[(P.season==s)&(P.week==w)]
        sw=np.where(H.season==s,1.0,d)
        X=X_of(H); y=H[t].values
        if kind=="glm":
            m=PoissonRegressor(alpha=pen,max_iter=300).fit(X,np.clip(y,0,None),sample_weight=sw)
        else:
            lo,ld=pen  # BLUP: ridge with penalty sigma_e^2/sigma_u^2 per side, via column scaling
            sc=np.r_[np.full(32,1/np.sqrt(lo)),np.full(32,1/np.sqrt(ld))]
            m=Ridge(alpha=1.0).fit(X*sc,y,sample_weight=sw); m.coef_=m.coef_*1  # predictions use same scaling
            out[cur.index]=m.predict(X_of(cur)*sc); continue
        out[cur.index]=m.predict(X_of(cur))
    return out
t0=time.time()
import sys
for t in sys.argv[1:]:
    best=None
    for d in [0.1,0.25,0.5]:
        for a in [0.1,0.2,0.4,0.8,1.6,3.2,6.4]:
            p=weekly("glm",t,d,a); e=rmse(P.loc[DEV,"y_"+t],p[DEV])
            if best is None or e<best[0]: best=(e,d,a,p)
    tune[f"glm_{t}"]=dict(decay=best[1],alpha=best[2]); P[f"glm_{t}"]=best[3]
    vr,vo,vd=VC[t]["var_res"],VC[t]["var_off"],VC[t]["var_def"]
    best=None
    for d in [0.1,0.25,0.5]:
        p=weekly("mm",t,d,(vr/vo,vr/vd)); e=rmse(P.loc[DEV,"y_"+t],p[DEV])
        if best is None or e<best[0]: best=(e,d,p)
    tune[f"mixed_{t}"]=dict(decay=best[1],lambda_off=vr/vo,lambda_def=vr/vd); P[f"mixed_{t}"]=best[2]
    print(t,"glm/mixed",tune[f"glm_{t}"],round(time.time()-t0),flush=True)
tag="_".join(sys.argv[1:])
P.to_pickle(f"preds_stat_{tag}.pkl"); json.dump(tune,open(f"tune_{tag}.json","w"),indent=1)
