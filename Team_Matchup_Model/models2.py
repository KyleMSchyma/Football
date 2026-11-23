import pandas as pd, numpy as np, json, warnings, statsmodels.api as sm, lightgbm as lgb
warnings.filterwarnings("ignore")
T=["tot","pas","rus","rec","QB","RB","WR","TE"]
P=pd.read_pickle("preds_all.pkl"); F=pd.read_pickle("feats.pkl"); X2=pd.read_pickle("feats2.pkl")
D=P.merge(X2,on=["season","week","team"],how="inner",suffixes=("","_x"))
F=F.merge(D[["season","week","team"]],on=["season","week","team"]); assert len(F)==len(D)
print("rows",len(D),"of",len(P))
# credibility-shrink the efficiency averages (Bühlmann k per metric, estimated on 2016-2022 games)

E=["epa","succ","plays","passrate"]
import feats2_k  # writes/reads k values
K=json.load(open("eff_k.json"))
for m in E:
    for side,n in [("o","o_n"),("d","d_n")]:
        Z=D[n]/(D[n]+K[f"{side}_{m}"]); D[f"{side}_{m}_c"]=Z*D[f"{side}_{m}"]+(1-Z)*D["L_"+m]
ctx=["home","dome","wind_c","cold"]
D["wind_c"]=D.wind.clip(0,25); D["cold"]=(D.temp<35).astype(int)
effc=[f"{s}_{m}_c" for s in "od" for m in E]
def design(t,set_):
    cols={}
    if "cred" in set_: cols["log_cred"]=np.log(D[f"cred_{t}"].clip(lower=1))
    if "ctx" in set_:
        for c in ctx: cols[c]=D[c]
    if "eff" in set_:
        for c in effc: cols[c]=D[c]
    if "lines" in set_:
        cols["log_implied"]=np.log(D.implied.clip(lower=3)); cols["team_spread"]=D.team_spread; cols["total_line"]=D.total_line
    return pd.DataFrame(cols)
SETS={"v1_cred":None,"cred+ctx":["cred","ctx"],"cred+ctx+eff":["cred","ctx","eff"],"lines_only":["lines"],"lines+ctx":["lines","ctx"],"lines+cred+ctx":["lines","cred","ctx"],"all_glm":["lines","cred","ctx","eff"]}
res={}
for t in T:
    y=D["y_"+t].clip(lower=0)
    D[f"v1_cred_{t}"]=D[f"cred_{t}"]
    for name,st in SETS.items():
        if st is None: continue
        Xd=sm.add_constant(design(t,st))
        pred=pd.Series(np.nan,index=D.index)
        for s in range(2018,2027):
            tr=(D.season<s)&(D.season>=2017); te=D.season==s
            m=sm.GLM(y[tr],Xd[tr],family=sm.families.Poisson()).fit()
            pred[te]=m.predict(Xd[te])
            if s==2026 and t in("tot","rus","WR"): res[f"coef_{name}_{t}"]=m.params.round(4).to_dict()
        D[f"{name}_{t}"]=pred
    # GBM with everything
    Xg=pd.concat([design(t,["lines","ctx","eff"]),pd.DataFrame({"off_avg":F[f"o_{t}_0.25"],"def_avg":F[f"d_{t}_0.25"],"off3":F[f"o3_{t}"],"def3":F[f"d3_{t}"],"L":F[f"L_{t}_0.25"],"on":F["on_0.25"],"dn":F["dn_0.25"],"cred":D[f"cred_{t}"],"week":D.week})],axis=1)
    params=dict(objective="regression",learning_rate=0.02,num_leaves=8,min_data_in_leaf=60,feature_fraction=0.8,bagging_fraction=0.8,bagging_freq=1,lambda_l2=5,verbose=-1,seed=1,num_threads=4)
    yv=D["y_"+t]; tr=D.season<=2021; va=D.season==2022
    mm=lgb.train(params,lgb.Dataset(Xg[tr],yv[tr]),2000,valid_sets=[lgb.Dataset(Xg[va],yv[va])],callbacks=[lgb.early_stopping(100,verbose=False)])
    nr=mm.best_iteration; pred=pd.Series(np.nan,index=D.index)
    for s in range(2018,2027):
        m2=lgb.train(params,lgb.Dataset(Xg[D.season<s],yv[D.season<s]),nr); pred[D.season==s]=m2.predict(Xg[D.season==s])
    D[f"gbm_all_{t}"]=pred
    if t=="tot":
        import shap
        sv=shap.TreeExplainer(m2).shap_values(Xg[D.season>=2023]); res["shap_gbm_all_tot"]=pd.Series(np.abs(sv).mean(0),index=Xg.columns).sort_values(ascending=False).round(2).to_dict()
    print(t,flush=True)
D.to_pickle("preds_v2.pkl"); json.dump(res,open("v2_extra.json","w"),indent=1)
