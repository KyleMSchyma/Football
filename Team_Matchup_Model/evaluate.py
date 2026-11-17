import pandas as pd, numpy as np, json
P=pd.read_pickle("preds_stat.pkl").join(pd.read_pickle("preds_gbm.pkl"))
T=["tot","pas","rus","rec","QB","RB","WR","TE"]
M=["league","std","naive","credB","cred","mixed","glm","gbm"]
for t in T: P[f"blend_{t}"]=(P[f"glm_{t}"]+P[f"gbm_{t}"])/2
M+=["blend"]
def stats(df,t,m):
    y=df["y_"+t]; p=df[f"{m}_{t}"]; e=y-p
    return dict(rmse=np.sqrt((e**2).mean()),mae=e.abs().mean(),r2=1-(e**2).sum()/((y-y.mean())**2).sum(),bias=e.mean())
rows=[]
for split,mask in [("dev",(P.season>=2018)&(P.season<=2022)),("test",P.season>=2023),("test_wk1_4",(P.season>=2023)&(P.week<=4)),("test_wk5plus",(P.season>=2023)&(P.week>=5))]:
    for t in T:
        for m in M:
            rows.append(dict(split=split,target=t,model=m,**stats(P[mask],t,m)))
R=pd.DataFrame(rows)
assert P[[c for c in P.columns if "_" in c and P.season.min()]].loc[P.season>=2018].filter(regex="^(league|std|naive|credB|cred|mixed|glm|gbm|blend)_").isna().sum().sum()==0, "NaN predictions"
R.to_csv("results.csv",index=False)
pd.set_option("display.width",200)
for split in ["test","test_wk1_4","test_wk5plus"]:
    print("==",split)
    print(R[R.split==split].pivot(index="model",columns="target",values="r2").loc[M,T].round(3))
print(R[R.split=="test"].pivot(index="model",columns="target",values="rmse").loc[M,T].round(2))
print(R[R.split=="test"].pivot(index="model",columns="target",values="mae").loc[M,T].round(2))
print(R[R.split=="dev"].pivot(index="model",columns="target",values="r2").loc[M,T].round(3))
# per-season stability of the R2 for total
for s in [2023,2024,2025,2026]:
    print(s,{m:round(stats(P[P.season==s],"tot",m)["r2"],3) for m in M})
P.to_pickle("preds_all.pkl")
