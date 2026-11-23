import pandas as pd, numpy as np, json
D=pd.read_pickle("preds_v2.pkl"); T=["tot","pas","rus","rec","QB","RB","WR","TE"]
M=["league","v1_cred","cred+ctx","cred+ctx+eff","lines_only","lines+ctx","lines+cred+ctx","all_glm","gbm_all"]
def st(df,t,m):
    y=df["y_"+t]; e=y-df[f"{m}_{t}"]; return dict(rmse=np.sqrt((e**2).mean()),mae=e.abs().mean(),r2=1-(e**2).sum()/((y-y.mean())**2).sum())
rows=[]
for sp,mask in [("test",D.season>=2023),("test_wk1_4",(D.season>=2023)&(D.week<=4)),("test_wk5plus",(D.season>=2023)&(D.week>=5)),("dev",(D.season>=2018)&(D.season<=2022))]:
    for t in T:
        for m in M: rows.append(dict(split=sp,target=t,model=m,**st(D[mask],t,m)))
R=pd.DataFrame(rows); R.to_csv("results_v2.csv",index=False)
pd.set_option("display.width",200)
for sp in ["test","test_wk1_4","test_wk5plus"]:
    print("==",sp); print((R[R.split==sp].pivot(index="model",columns="target",values="r2").loc[M,T]*100).round(1))
print((R[R.split=="test"].pivot(index="model",columns="target",values="rmse").loc[M,T]).round(2))
print((R[R.split=="test"].pivot(index="model",columns="target",values="mae").loc[M,T]).round(2))
for s in [2023,2024,2025,2026]: print(s,{m:round(st(D[D.season==s],"tot",m)["r2"]*100,1) for m in ["v1_cred","cred+ctx+eff","lines_only","all_glm","gbm_all"]})
