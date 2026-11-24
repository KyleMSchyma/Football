# =============================================================================
# Backup QB research, step 2: P(backup becomes a starter within 1-2 years), model comparison (ATPA course workflow).
#
# Population: backup seasons (bq_01: fewer than half the team's starts, did not open the season as the starter, still on
#             a roster at season end), seasons 2012-2023 (2-year outcome observed through 2025).
# Target:     y_start12 = started half or more of his team's games in y+1 or y+2.
# Split:      train 2012-2019, test 2020-2023 (time split, no season in both). Also leave-one-season-out CV over 2012-2023
#             and a longer-history check (train 2006-2019).
# Models:     M0 base rate; M1 GLM (Kyle's five: age, spot-start PPG vs QB24, starts, draft capital, years in league);
#             M2 GLM + career/start history; M3 elastic net (M2 features); M4 random forest; M5 gradient boosting (xgboost).
# Outputs:    bq_02_log.txt, bq_02_metrics.csv, figs/*.png, bq_02_test_predictions.csv
# =============================================================================
import os, sys, warnings
import numpy as np, pandas as pd
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from sklearn.linear_model import LogisticRegression, LogisticRegressionCV
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import make_pipeline
from sklearn.metrics import log_loss, brier_score_loss, roc_auc_score, roc_curve
from sklearn.inspection import permutation_importance, partial_dependence
import statsmodels.api as sm
import xgboost as xgb
import shap
warnings.filterwarnings("ignore")
HERE = os.path.dirname(os.path.abspath(__file__)); os.chdir(HERE); os.makedirs("figs", exist_ok=True)
LOG = open("bq_02_log.txt", "w")
def say(*a):
    s = " ".join(str(x) for x in a); print(s); LOG.write(s + "\n")
K_SPOT = 3   # credibility for PPG in starts: (points over line) / (starts + 3), i.e. 3 phantom starts at the QB24 line

d = pd.read_csv("bq_qb_seasons.csv")
d = d.sort_values(["player_id", "season"])
d["pts_vs_rep_s"] = np.where(d.starts > 0, (d.ppg_s - d.rep) * d.starts, 0.0)
d["c_vs_rep"] = d.groupby("player_id").pts_vs_rep_s.cumsum()
d["spot_cred"] = d.pts_vs_rep_s / (d.starts + K_SPOT)                 # this season, credibility-weighted PPG in starts vs QB24
d["career_cred"] = d.c_vs_rep / (d.c_starts + K_SPOT)                 # career through y, same weighting
d["rookie_contract"] = (d.exp <= 3).astype(int)
FE1 = ["age", "spot_cred", "starts", "lpick", "undrafted", "exp"]                       # Kyle's five (draft capital = log pick + undrafted)
FE1B = [f for f in FE1 if f != "exp"]   # age and years in league correlate .97 in this population
FE2 = FE1 + ["career_cred", "c_starts_prev", "ever_starter_prev", "relief"]
LAB = {"age": "Age (next season)", "spot_cred": "Spot-start PPG vs QB24 (this season, credible)", "starts": "Starts this season",
       "lpick": "log(draft pick)", "undrafted": "Undrafted", "exp": "Years in league", "career_cred": "Career PPG in starts vs QB24 (credible)",
       "c_starts_prev": "Career starts before this season", "ever_starter_prev": "Was a full-time starter before", "relief": "Relief appearances"}

pop = d[(d.backup == 1) & d.y_start12.notna() & d.age.notna() & d.exp.notna()].copy()   # drops 3 rows with no birth date
dat = pop[pop.season.between(2012, 2023)].copy()
tr, te = dat[dat.season <= 2019], dat[dat.season >= 2020]
say(f"Backup QB seasons 2012-2023: {len(dat)} ({int(dat.y_start12.sum())} became starters within 2 years, {dat.y_start12.mean():.3f})")
say(f"train 2012-2019: {len(tr)} rows, {int(tr.y_start12.sum())} starters; test 2020-2023: {len(te)} rows, {int(te.y_start12.sum())} starters")
say(f"1-year rate (start in y+1): {dat.y_start1.mean():.3f}")

# ---------- EDA charts: base rates ----------
def rate_plot(col, bins, labels, fname, title):
    x = dat.copy(); x["b"] = pd.cut(x[col], bins=bins, labels=labels, right=False)
    r = x.groupby("b", observed=False).y_start12.agg(["mean", "size"])
    fig, ax = plt.subplots(figsize=(7, 4)); ax.bar(r.index.astype(str), r["mean"], color="#2b5d9b")
    for i, (m, n) in enumerate(zip(r["mean"], r["size"])): ax.text(i, m + 0.005, f"{m:.0%}\nn={n}", ha="center", fontsize=8)
    ax.set_ylabel("Share starting within 2 years"); ax.set_title(title); ax.set_ylim(0, max(r["mean"].max() * 1.3, 0.1))
    fig.tight_layout(); fig.savefig(f"figs/{fname}.png", dpi=130); plt.close(fig)
    say(f"\n{title}\n" + r.round(3).to_string())
rate_plot("age", [0, 24, 26, 28, 31, 50], ["<24", "24-25", "26-27", "28-30", "31+"], "eda_rate_by_age", "Backup -> starter within 2 years, by age")
rate_plot("pick", [0, 33, 65, 101, 300], ["Rd 1", "Rd 2", "Rd 3", "Rd 4+"], "eda_rate_by_pick", "Backup -> starter within 2 years, by draft pick (undrafted excluded)")
rate_plot("starts", [0, 1, 2, 4, 9], ["0", "1", "2-3", "4-8"], "eda_rate_by_starts", "Backup -> starter within 2 years, by starts this season")
rate_plot("exp", [0, 1, 2, 4, 7, 30], ["Rookie", "Year 2", "Years 3-4", "Years 5-7", "8+"], "eda_rate_by_exp", "Backup -> starter within 2 years, by years in league")
dat["spot_b"] = np.where(dat.starts == 0, 99, dat.spot_cred)
rate_plot("spot_b", [-20, -3, -1, 0, 1, 50, 100], ["< -3", "-3 to -1", "-1 to 0", "0 to 1", "> 1", "no starts"], "eda_rate_by_spot", "Backup -> starter within 2 years, by spot-start PPG vs QB24 (credible)")
u = dat.undrafted.astype(bool); say(f"undrafted rate {dat.y_start12[u].mean():.3f} (n={u.sum()}), drafted {dat.y_start12[~u].mean():.3f}")

# ---------- models ----------
def fit_models(trn, feats1, feats2, seed=1):
    X1, X2, y = trn[feats1].values, trn[feats2].values, trn.y_start12.values.astype(int)
    m = {}
    m["M1 GLM (Kyle's five)"] = make_pipeline(StandardScaler(), LogisticRegression(C=1e6, max_iter=5000)).fit(X1, y)
    m["M1b GLM, no years in league"] = make_pipeline(StandardScaler(), LogisticRegression(C=1e6, max_iter=5000)).fit(trn[FE1B].values, y)
    m["M2 GLM + history"] = make_pipeline(StandardScaler(), LogisticRegression(C=1e6, max_iter=5000)).fit(X2, y)
    m["M3 Elastic net"] = make_pipeline(StandardScaler(), LogisticRegressionCV(Cs=20, penalty="elasticnet", solver="saga", l1_ratios=[0.2, 0.5, 0.8, 1.0],
                                                                                 cv=5, scoring="neg_log_loss", max_iter=20000, random_state=seed)).fit(X2, y)
    m["M4 Random forest"] = RandomForestClassifier(n_estimators=1000, min_samples_leaf=10, max_features=0.5, random_state=seed).fit(X2, y)
    m["M5 Gradient boosting"] = xgb.XGBClassifier(n_estimators=300, learning_rate=0.03, max_depth=2, subsample=0.8, colsample_bytree=0.8,
                                                  min_child_weight=5, reg_lambda=5, random_state=seed, verbosity=0).fit(X2, y)
    return m
def predict(m, x, feats1, feats2):
    out = {"M0 Base rate": None}
    for k, mod in m.items():
        out[k] = mod.predict_proba(x[FE1B if k.startswith("M1b") else feats1 if k.startswith("M1") else feats2].values)[:, 1]
    return out
def metrics(y, p):
    p = np.clip(p, 1e-4, 1 - 1e-4)
    return dict(log_loss=log_loss(y, p, labels=[0, 1]), brier=brier_score_loss(y, p), auc=roc_auc_score(y, p) if len(set(y)) > 1 else np.nan,
                pred_mean=p.mean(), actual=y.mean())

M = fit_models(tr, FE1, FE2)
P = predict(M, te, FE1, FE2); P["M0 Base rate"] = np.full(len(te), tr.y_start12.mean())
rows = []
yte = te.y_start12.values.astype(int)
b0 = brier_score_loss(yte, P["M0 Base rate"])
for k, p in P.items():
    r = metrics(yte, p); r["model"] = k; r["split"] = "test 2020-2023"; r["BSS"] = 1 - r["brier"] / b0; rows.append(r)

# bootstrap (by player) the test log-loss gap of each model vs M1
rng = np.random.default_rng(7); ids = te.player_id.values; uid = np.unique(ids)
boot = {k: [] for k in P if k != "M1 GLM (Kyle's five)"}
for _ in range(2000):
    s = rng.choice(uid, len(uid)); idx = np.concatenate([np.where(ids == u_)[0] for u_ in s])
    if yte[idx].sum() == 0: continue
    l1 = log_loss(yte[idx], np.clip(P["M1 GLM (Kyle's five)"][idx], 1e-4, 1 - 1e-4), labels=[0, 1])
    for k in boot: boot[k].append(log_loss(yte[idx], np.clip(P[k][idx], 1e-4, 1 - 1e-4), labels=[0, 1]) - l1)
say("\nTest log-loss minus M1's (bootstrap by player, 95% interval; below 0 = better than M1):")
for k, v in boot.items(): say(f"  {k:24s} {np.mean(v):+.4f}  [{np.percentile(v, 2.5):+.4f}, {np.percentile(v, 97.5):+.4f}]")

# leave-one-season-out CV over 2012-2023
lo = {k: np.zeros(len(dat)) for k in list(P)}
for s in sorted(dat.season.unique()):
    i_tr, i_te = dat.season.values != s, dat.season.values == s
    mm = fit_models(dat[i_tr], FE1, FE2); pp = predict(mm, dat[i_te], FE1, FE2); pp["M0 Base rate"] = np.full(i_te.sum(), dat[i_tr].y_start12.mean())
    for k in lo: lo[k][i_te] = pp[k]
yall = dat.y_start12.values.astype(int); b0l = brier_score_loss(yall, lo["M0 Base rate"])
for k, p in lo.items():
    r = metrics(yall, p); r["model"] = k; r["split"] = "leave-one-season-out 2012-2023"; r["BSS"] = 1 - r["brier"] / b0l; rows.append(r)

# longer history: train 2006-2019, same test
tr6 = pop[pop.season.between(2006, 2019)]
M6 = fit_models(tr6, FE1, FE2); P6 = predict(M6, te, FE1, FE2); P6["M0 Base rate"] = np.full(len(te), tr6.y_start12.mean())
for k, p in P6.items():
    r = metrics(yte, p); r["model"] = k; r["split"] = "test 2020-2023, trained 2006-2019"; r["BSS"] = 1 - r["brier"] / brier_score_loss(yte, P6["M0 Base rate"]); rows.append(r)

met = pd.DataFrame(rows)[["split", "model", "log_loss", "brier", "BSS", "auc", "pred_mean", "actual"]]
met.to_csv("bq_02_metrics.csv", index=False)
say("\nModel comparison:\n" + met.round(4).to_string(index=False))

# ---------- charts: ROC + calibration (test) ----------
fig, ax = plt.subplots(1, 2, figsize=(12, 5))
for k, p in P.items():
    if k.startswith("M0"): continue
    f, t, _ = roc_curve(yte, p); ax[0].plot(f, t, label=f"{k} (AUC {roc_auc_score(yte, p):.3f})")
ax[0].plot([0, 1], [0, 1], "k:"); ax[0].set_xlabel("False positive rate"); ax[0].set_ylabel("True positive rate"); ax[0].set_title("ROC, test 2020-2023"); ax[0].legend(fontsize=8)
for k in ["M1 GLM (Kyle's five)", "M2 GLM + history", "M5 Gradient boosting"]:
    p = lo[k]; q = pd.qcut(p, 8, duplicates="drop"); c = pd.DataFrame({"p": p, "y": yall, "q": q}).groupby("q", observed=True).mean()
    ax[1].plot(c.p, c.y, "o-", label=k)
ax[1].plot([0, 0.7], [0, 0.7], "k:"); ax[1].set_xlabel("Predicted chance"); ax[1].set_ylabel("Actual share"); ax[1].set_title("Calibration, leave-one-season-out 2012-2023 (8 bins)"); ax[1].legend(fontsize=8)
fig.tight_layout(); fig.savefig("figs/model_roc_calibration.png", dpi=130); plt.close(fig)

# ---------- interpretation: GLM coefficients (statsmodels, all 2012-2023) ----------
for nm, fe in [("M1", FE1), ("M2", FE2)]:
    X = sm.add_constant(dat[fe]); g = sm.Logit(dat.y_start12, X).fit(disp=0)
    tab = pd.DataFrame({"coef": g.params, "se": g.bse, "z": g.tvalues, "p": g.pvalues, "odds_ratio": np.exp(g.params)})
    say(f"\n{nm} logistic regression on all 2012-2023 backup seasons (n={len(dat)}):\n" + tab.round(4).to_string())
    tab.to_csv(f"bq_02_{nm.lower()}_coefficients.csv")

# ---------- variable importance: permutation (test log loss) for M2 and M5; SHAP for M5; PDP ----------
Mall = fit_models(dat, FE1, FE2)
fig, ax = plt.subplots(1, 2, figsize=(12, 4.5))
for j, k in enumerate(["M2 GLM + history", "M5 Gradient boosting"]):
    pi = permutation_importance(Mall[k], dat[FE2].values, yall, scoring="neg_log_loss", n_repeats=30, random_state=1)
    s = pd.Series(pi.importances_mean, index=[LAB[f] for f in FE2]).sort_values()
    say(f"\nPermutation importance ({k}, increase in log loss when shuffled, fit on 2012-2023):\n" + s[::-1].round(4).to_string())
    ax[j].barh(s.index, s.values, color="#2b5d9b"); ax[j].set_title(f"Permutation importance: {k}"); ax[j].tick_params(labelsize=8)
fig.tight_layout(); fig.savefig("figs/varimp_permutation.png", dpi=130); plt.close(fig)

ex = shap.TreeExplainer(Mall["M5 Gradient boosting"]); sv = ex.shap_values(dat[FE2].values)
plt.figure(); shap.summary_plot(sv, dat[FE2].rename(columns=LAB), show=False, plot_size=(9, 5)); plt.title("SHAP, gradient boosting (log-odds)")
plt.tight_layout(); plt.savefig("figs/shap_summary_gbm.png", dpi=130); plt.close()
ms = pd.Series(np.abs(sv).mean(0), index=[LAB[f] for f in FE2]).sort_values(ascending=False)
say("\nMean |SHAP| (gradient boosting, log-odds):\n" + ms.round(4).to_string())

fig, ax = plt.subplots(2, 3, figsize=(14, 8)); ax = ax.ravel()
for j, f in enumerate(["age", "spot_cred", "starts", "lpick", "exp", "career_cred"]):
    ii = FE2.index(f)
    for k, c in [("M2 GLM + history", "#2b5d9b"), ("M5 Gradient boosting", "#d9822b"), ("M4 Random forest", "#4a9b5b")]:
        pdp = partial_dependence(Mall[k], dat[FE2].values, [ii], kind="both", grid_resolution=25, response_method="predict_proba")
        gx = pdp["grid_values"][0]; ax[j].plot(gx, pdp["average"][0], color=c, lw=2, label=k)
        if k.startswith("M5"):
            for line in pdp["individual"][0][::15]: ax[j].plot(gx, line, color=c, alpha=0.08, lw=0.7)   # ICE (every 15th row)
    xl = gx if f != "lpick" else gx
    ax[j].set_title(LAB[f], fontsize=9); ax[j].set_ylabel("P(starter within 2 yrs)")
    if f == "lpick": ax[j].set_xticks(np.log([1, 10, 32, 100, 250])); ax[j].set_xticklabels(["1", "10", "32", "100", "250"])
ax[0].legend(fontsize=7); fig.suptitle("Partial dependence (lines) with ICE for gradient boosting (faint)"); fig.tight_layout()
fig.savefig("figs/pdp_ice.png", dpi=130); plt.close(fig)

# test predictions table
te_out = te[["name", "season", "team", "age", "exp", "pick", "starts", "spot_cred", "career_cred", "y_start12", "dfv"]].copy()
for k in ["M1 GLM (Kyle's five)", "M2 GLM + history", "M5 Gradient boosting"]: te_out[k] = P[k]
te_out.sort_values("M2 GLM + history", ascending=False).to_csv("bq_02_test_predictions.csv", index=False)
say("\nTop 25 test-period backups by M2 chance:\n" + te_out.sort_values("M2 GLM + history", ascending=False).head(25).round(3).to_string(index=False))
LOG.close()
