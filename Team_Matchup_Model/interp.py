import pandas as pd, numpy as np, lightgbm as lgb, shap, json, matplotlib
matplotlib.use("Agg"); import matplotlib.pyplot as plt
exec(open("gbm.py").read().split("params=")[0])  # reuse F, feats()
out={}
for t in ["tot","pas","rus","rec","QB","RB","WR","TE"]:
    m=lgb.Booster(model_file=f"gbm_{t}.txt"); X=feats(t)[F.season>=2023]
    sv=shap.TreeExplainer(m).shap_values(X)
    imp=pd.Series(np.abs(sv).mean(0),index=X.columns).sort_values(ascending=False)
    out[t]=imp.round(2).to_dict()
    if t=="tot":
        shap.summary_plot(sv,X,show=False,plot_size=(8,5)); plt.tight_layout(); plt.savefig("shap_tot.png",dpi=110); plt.close()
        fig,ax=plt.subplots(1,2,figsize=(10,4))
        for a,c in zip(ax,["team_avg_incl_last_season","opp_allowed_incl_last_season"]):
            grid=np.linspace(X[c].quantile(.05),X[c].quantile(.95),25)
            pd_=[m.predict(X.assign(**{c:g})).mean() for g in grid]
            for i in X.sample(60,random_state=1).index:  # ICE
                a.plot(grid,[m.predict(X.loc[[i]].assign(**{c:g}))[0] for g in grid],color="0.8",lw=.5)
            a.plot(grid,pd_,color="C1",lw=3); a.plot(grid,grid,"k--",lw=.8); a.set_xlabel(c); a.set_ylabel("predicted team points")
        plt.tight_layout(); plt.savefig("pdp_tot.png",dpi=110); plt.close()
json.dump(out,open("shap_importance.json","w"),indent=1)
for t,v in out.items(): print(t,list(v.items())[:5])
