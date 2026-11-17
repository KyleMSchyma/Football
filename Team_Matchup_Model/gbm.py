import pandas as pd, numpy as np, lightgbm as lgb, json, warnings
warnings.filterwarnings("ignore")
F=pd.read_pickle("feats.pkl"); T=["tot","pas","rus","rec","QB","RB","WR","TE"]
def feats(t):
    X=pd.DataFrame({
      "team_avg_this_season":F[f"o_{t}_0.0"],"team_avg_incl_last_season":F[f"o_{t}_0.5"],"team_last3":F[f"o3_{t}"],
      "opp_allowed_this_season":F[f"d_{t}_0.0"],"opp_allowed_incl_last_season":F[f"d_{t}_0.5"],"opp_allowed_last3":F[f"d3_{t}"],
      "league_avg":F[f"L_{t}_0.5"],"team_games":F["on_0.0"],"opp_games":F["dn_0.0"],"week":F.week})
    if t!="tot":
        X["team_total_avg"]=F["o_tot_0.5"]; X["opp_total_allowed"]=F["d_tot_0.5"]
    return X
params=dict(objective="regression",learning_rate=0.02,num_leaves=8,min_data_in_leaf=60,feature_fraction=0.8,bagging_fraction=0.8,bagging_freq=1,lambda_l2=5,verbose=-1,seed=1)
out=pd.DataFrame(index=F.index); info={}
for t in T:
    X=feats(t); y=F["y_"+t]
    # number of rounds: train 2017-2021, early stop on 2022
    tr=F.season<=2021; va=F.season==2022
    m=lgb.train(params,lgb.Dataset(X[tr],y[tr]),2000,valid_sets=[lgb.Dataset(X[va],y[va])],callbacks=[lgb.early_stopping(100,verbose=False)])
    nr=m.best_iteration; info[t]=nr
    pred=pd.Series(np.nan,index=F.index)
    # dev predictions (2018-2022) expanding window, test 2023-2026 expanding window
    for s in range(2018,2027):
        trn=F.season<s
        mm=lgb.train(params,lgb.Dataset(X[trn],y[trn]),nr)
        pred[F.season==s]=mm.predict(X[F.season==s])
    out[f"gbm_{t}"]=pred
    if t in ("tot","pas","rus","rec","QB","RB","WR","TE"):
        mm.save_model(f"gbm_{t}.txt")
print(info)
out.to_pickle("preds_gbm.pkl")
