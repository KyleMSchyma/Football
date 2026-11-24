# =============================================================================
# Backup QB research, step 3: dynasty FUTURE value of backup QBs = P(becomes a starter) x value of starting.
# Backtest against the live model (point-in-time snapshots in Trade_Values/history/snapshots, end of each season).
#
# Target:  DFV = realized discounted future value, h = 1..5 seasons after y (bq_01; same 1/1.15 discount and per-season
#          floor at 0 as dv_11; QB24 half-PPR line). Only seasons with all 5 future years observed (y <= 2020) are scored.
# Split:   new models fit on backup seasons 2006-2015; scored on 2016-2020 (the snapshots start in 2016).
# Live:    V0 = snapshot dynasty value minus rest-of-season value at the last regular-season week of y (points over
#          replacement, same units). A backup missing from the snapshot board counts as 0.
# New:     V1 hurdle, constant: P(start within 2 yrs, M1) x average DFV of backups who became starters (train)
#          V2 hurdle, fitted:   P(M1) x E[DFV | became starter] (gamma GLM, log link: age, spot-start PPG, log pick)
#          V3 hurdle with M2 probabilities (adds career history)
#          V4 direct Tweedie GLM on DFV (Kyle's five features)
#          V5 direct Tweedie gradient boosting (M2 features)
# Also:    the 2026 Backup-tagged QBs valued by V2 (as of week 11) next to the live future value.
# =============================================================================
import os, glob, warnings
import numpy as np, pandas as pd, rdata
import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
import statsmodels.api as sm
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import make_pipeline
from scipy.stats import spearmanr
import xgboost as xgb
warnings.filterwarnings("ignore")
HERE = os.path.dirname(os.path.abspath(__file__)); os.chdir(HERE)
SNAP = os.path.join(HERE, "..", "..", "history", "snapshots")
LOG = open("bq_03_log.txt", "w")
def say(*a):
    s = " ".join(str(x) for x in a); print(s); LOG.write(s + "\n")
K_SPOT = 3

d = pd.read_csv("bq_qb_seasons.csv").sort_values(["player_id", "season"])
d["pts_vs_rep_s"] = np.where(d.starts > 0, (d.ppg_s - d.rep) * d.starts, 0.0)
d["c_vs_rep"] = d.groupby("player_id").pts_vs_rep_s.cumsum()
d["spot_cred"] = d.pts_vs_rep_s / (d.starts + K_SPOT)
d["career_cred"] = d.c_vs_rep / (d.c_starts + K_SPOT)
FE1 = ["age", "spot_cred", "starts", "lpick", "undrafted", "exp"]
FE2 = FE1 + ["career_cred", "c_starts_prev", "ever_starter_prev", "relief"]
FEV = ["age", "spot_cred", "lpick"]
pop = d[(d.backup == 1) & d.age.notna() & d.exp.notna()].copy()
tr = pop[pop.season.between(2006, 2015)].copy(); te = pop[pop.season.between(2016, 2020)].copy()
say(f"train 2006-2015: {len(tr)} backup seasons ({int(tr.y_start12.sum())} starters within 2 yrs); test 2016-2020: {len(te)}")

# ---------- live model, point in time ----------
def last_snap(y):
    f = sorted(glob.glob(f"{SNAP}/hv_{y}_w*.rds"))[-1]
    x = rdata.read_rds(f)
    dy, rd = x["dynasty"], x["redraft"]
    dy = dy[dy.pos == "QB"][["player_id", "value", "value_ros", "value_100k", "status"]].copy()
    top = x["dynasty"].value.max()
    dy["fut_live"] = dy.value - dy.value_ros; dy["season"] = y; dy["top"] = top
    return dy[["player_id", "season", "fut_live", "status", "top"]]
live = pd.concat([last_snap(y) for y in range(2016, 2021)])
te = te.merge(live, on=["player_id", "season"], how="left")
say(f"test backups found on the live snapshot board: {te.fut_live.notna().sum()} of {len(te)}; tagged Backup there: {(te.status == 'Backup').sum()}")
te["V0 Live model"] = te.fut_live.fillna(0)

# ---------- new models ----------
def glm_p(feats, trn):
    return make_pipeline(StandardScaler(), LogisticRegression(C=1e6, max_iter=5000)).fit(trn[feats].values, trn.y_start12.values.astype(int))
p1 = glm_p(FE1, tr); p2 = glm_p(FE2, tr)
te["P1"] = p1.predict_proba(te[FE1].values)[:, 1]; te["P2"] = p2.predict_proba(te[FE2].values)[:, 1]
s1 = tr[tr.y_start12 == 1]; s0 = tr[tr.y_start12 == 0]
say(f"train: mean DFV if became a starter {s1.dfv.mean():.1f} (n={len(s1)}), if not {s0.dfv.mean():.1f} (n={len(s0)})")
gam = sm.GLM(s1.dfv + 1, sm.add_constant(s1[FEV]), family=sm.families.Gamma(sm.families.links.Log())).fit()
say("\nE[DFV | became starter] gamma GLM (log link), train 2006-2015:\n" + pd.DataFrame({"coef": gam.params, "p": gam.pvalues}).round(4).to_string())
cond1 = (gam.predict(sm.add_constant(te[FEV], has_constant="add")) - 1).clip(lower=0)
gam0 = sm.GLM(s0.dfv + 1, sm.add_constant(s0[FEV]), family=sm.families.Gamma(sm.families.links.Log())).fit()
cond0 = (gam0.predict(sm.add_constant(te[FEV], has_constant="add")) - 1).clip(lower=0)
te["V1 Hurdle, constant"] = te.P1 * s1.dfv.mean() + (1 - te.P1) * s0.dfv.mean()
te["V2 Hurdle, fitted"] = te.P1 * cond1 + (1 - te.P1) * cond0
te["V3 Hurdle, M2 chance"] = te.P2 * cond1 + (1 - te.P2) * cond0
tw = sm.GLM(tr.dfv, sm.add_constant(tr[FE1]), family=sm.families.Tweedie(var_power=1.5, link=sm.families.links.Log())).fit()
te["V4 Tweedie GLM"] = tw.predict(sm.add_constant(te[FE1], has_constant="add"))
gb = xgb.XGBRegressor(objective="reg:tweedie", tweedie_variance_power=1.5, n_estimators=300, learning_rate=0.03, max_depth=2,
                      subsample=0.8, colsample_bytree=0.8, min_child_weight=5, reg_lambda=5, random_state=1, verbosity=0).fit(tr[FE2].values, tr.dfv.values)
te["V5 Tweedie GBM"] = gb.predict(te[FE2].values)
VM = ["V0 Live model", "V1 Hurdle, constant", "V2 Hurdle, fitted", "V3 Hurdle, M2 chance", "V4 Tweedie GLM", "V5 Tweedie GBM"]

def score(x, label):
    rows = []
    for k in VM:
        p, a = x[k].values, x.dfv.values
        rows.append(dict(group=label, n=len(x), model=k, pred_total=p.sum(), actual_total=a.sum(), ratio=p.sum() / max(a.sum(), 1e-9),
                         rmse=np.sqrt(np.mean((p - a) ** 2)), mae=np.mean(np.abs(p - a)), spearman=spearmanr(p, a).statistic if len(x) > 5 else np.nan))
    return rows
grp = {"All backups 2016-2020": te,
       "Tagged Backup on the live board": te[te.status == "Backup"],
       "Young, high draft capital (age<=25, picks 1-64)": te[(te.age <= 25) & (te.pick <= 64)],
       "Spot starters (2+ starts)": te[te.starts >= 2],
       "Veterans 30+": te[te.age >= 30],
       "Undrafted": te[te.undrafted == 1]}
res = pd.DataFrame([r for k, x in grp.items() for r in score(x, k)])
res.to_csv("bq_03_value_backtest.csv", index=False)
say("\nFuture-value backtest, points over the QB24 line, discounted (pred vs realized DFV):\n" + res.round(3).to_string(index=False))

# bootstrap RMSE gap V2 - V0 by player
rng = np.random.default_rng(3); ids = te.player_id.values; uid = np.unique(ids); gaps = {k: [] for k in VM[1:]}
for _ in range(2000):
    s = rng.choice(uid, len(uid)); idx = np.concatenate([np.where(ids == u_)[0] for u_ in s])
    a = te.dfv.values[idx]; r0 = np.sqrt(np.mean((te["V0 Live model"].values[idx] - a) ** 2))
    for k in gaps: gaps[k].append(np.sqrt(np.mean((te[k].values[idx] - a) ** 2)) - r0)
say("\nRMSE minus the live model's (bootstrap by player, 95% interval; below 0 = better than live):")
for k, v in gaps.items(): say(f"  {k:22s} {np.mean(v):+.2f}  [{np.percentile(v, 2.5):+.2f}, {np.percentile(v, 97.5):+.2f}]")

# charts: predicted vs realized by decile of each model, and totals by group
fig, ax = plt.subplots(1, 2, figsize=(13, 5))
for k, c in [("V0 Live model", "#888888"), ("V2 Hurdle, fitted", "#2b5d9b"), ("V5 Tweedie GBM", "#d9822b")]:
    q = pd.qcut(te[k].rank(method="first"), 5, labels=False); t = te.groupby(q).agg(p=(k, "mean"), a=("dfv", "mean"))
    ax[0].plot(t.p, t.a, "o-", color=c, label=k)
m = max(te[["V0 Live model", "V2 Hurdle, fitted", "dfv"]].groupby(pd.qcut(te["V2 Hurdle, fitted"].rank(method="first"), 5, labels=False)).mean().max())
ax[0].plot([0, m], [0, m], "k:"); ax[0].set_xlabel("Average predicted future value (pts over QB24)"); ax[0].set_ylabel("Average realized"); ax[0].set_title("Calibration by fifths, backups 2016-2020"); ax[0].legend(fontsize=8)
pv = res[res.group != "Undrafted"].pivot(index="group", columns="model", values="ratio")[[m_ for m_ in VM if m_ != "V4 Tweedie GLM"]]   # undrafted: realized ~0; V4 off the scale
pv.plot.barh(ax=ax[1], width=0.8); ax[1].axvline(1, color="k", ls=":"); ax[1].set_xlabel("Predicted total / realized total"); ax[1].set_title("Total value ratio by group (undrafted and V4 left off: off the scale)"); ax[1].legend(fontsize=7); ax[1].tick_params(labelsize=8)
fig.tight_layout(); fig.savefig("figs/value_backtest.png", dpi=130); plt.close(fig)

cols = ["name", "season", "team", "age", "pick", "starts", "status", "y_start12", "dfv", "P1"] + VM
t = te[cols].sort_values("dfv", ascending=False)
t.to_csv("bq_03_test_rows.csv", index=False)
say("\nBiggest realized future values among 2016-2020 backups:\n" + t.head(20).round(2).to_string(index=False))
say("\nBiggest live-model values among 2016-2020 backups:\n" + t.sort_values("V0 Live model", ascending=False).head(15).round(2).to_string(index=False))

# ---------- 2026: Backup-tagged QBs now, new method vs live ----------
x26 = rdata.read_rds(sorted(glob.glob(f"{SNAP}/hv_2026_w*.rds"))[-1]); dy = x26["dynasty"]; top26 = dy.value.max()
q = dy[(dy.pos == "QB")][["player_id", "name", "team", "age", "status", "value", "value_ros", "value_100k"]].copy()
q["fut_live"] = q.value - q.value_ros
now = d[d.season == 2026][["player_id", "pick"] + FE2].loc[:, lambda z: ~z.columns.duplicated()]
q = q.merge(now, on="player_id", how="left", suffixes=("_snap", ""))
q = q[q.status == "Backup"].copy()
pall = glm_p(FE1, pop[pop.season.between(2006, 2023)])
s1a = pop[(pop.season.between(2006, 2020)) & (pop.y_start12 == 1)]; s0a = pop[(pop.season.between(2006, 2020)) & (pop.y_start12 == 0)]
g1 = sm.GLM(s1a.dfv + 1, sm.add_constant(s1a[FEV]), family=sm.families.Gamma(sm.families.links.Log())).fit()
g0 = sm.GLM(s0a.dfv + 1, sm.add_constant(s0a[FEV]), family=sm.families.Gamma(sm.families.links.Log())).fit()
ok = q[FE1].notna().all(axis=1)
q.loc[ok, "P_start_2027_28"] = pall.predict_proba(q.loc[ok, FE1].values)[:, 1]
q.loc[ok, "fut_new"] = q.P_start_2027_28 * (g1.predict(sm.add_constant(q.loc[ok, FEV], has_constant="add")) - 1) + (1 - q.P_start_2027_28) * (g0.predict(sm.add_constant(q.loc[ok, FEV], has_constant="add")) - 1)
q["fut_new"] = q.fut_new.clip(lower=0)
q["fut_live_100k"] = (q.fut_live / top26 * 100000).round(-1); q["fut_new_100k"] = (q.fut_new / top26 * 100000).round(-1)
q = q.sort_values("fut_new", ascending=False)
q[["name", "team", "age", "pick", "starts", "spot_cred", "P_start_2027_28", "fut_live", "fut_new", "fut_live_100k", "fut_new_100k"]].to_csv("bq_03_backups_2026.csv", index=False)
say("\n2026 Backup-tagged QBs (snapshot after week 11; reference league, no flex): future value, live vs new (V2 refit on all data):\n" +
    q[["name", "team", "age", "pick", "starts", "spot_cred", "P_start_2027_28", "fut_live", "fut_new", "fut_live_100k", "fut_new_100k"]].round(3).to_string(index=False))
LOG.close()
