# =============================================================================
# Backup QB research, step 4: the two redraft rules Kyle proposed (2026-11-24), backtested on the point-in-time snapshots.
#   Rule A: QBs tagged Backup get 0 redraft (rest-of-season) value.
#   Rule B: injured starters on IR keep redraft value, with expected games = team games left - 4 (start at 4, adjust later).
# Snapshots: Trade_Values/history/snapshots/hv_S_wWW.rds, seasons 2016-2025, weeks 3 to (last week - 3).
# Realized rest-of-season value = max(sum over the remaining weeks he played of (points - snapshot QB24 line), 0), half PPR,
# 4-pt pass TD (the snapshot reference scoring), regular season only. Usage: python bq_04_redraft_rules.py RAW_DIR
# "Starter before IR" = started at least half of his team's games so far that season (games.csv starting QB).
# The IR minimum changed: 2016-2019 IR was season-ending except 1-2 designated returns (8 weeks); 2020-2021 3 games;
# 2022 on 4 games. Results are shown for all seasons and 2022-2025 separately.
# =============================================================================
import os, sys, glob, warnings
import numpy as np, pandas as pd, rdata
import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
warnings.filterwarnings("ignore")
RAW = sys.argv[1] if len(sys.argv) > 1 else "raw"
HERE = os.path.dirname(os.path.abspath(__file__)); os.chdir(HERE)
SNAP = os.path.join(HERE, "..", "..", "history", "snapshots")
LOG = open("bq_04_log.txt", "w")
def say(*a):
    s = " ".join(str(x) for x in a); print(s); LOG.write(s + "\n")

old = pd.read_parquet(f"{RAW}/ps_all_old.parquet").rename(columns={"recent_team": "team"})
new = pd.concat([pd.read_parquet(f"{RAW}/ps_{y}.parquet") for y in (2025, 2026)])
cols = ["player_id", "position", "season", "week", "season_type", "attempts", "carries", "receptions", "fantasy_points"]
wk = pd.concat([old[cols], new[cols]]); wk = wk[(wk.season_type == "REG") & (wk.season >= 2016) & (wk.position == "QB")]
wk["fp"] = wk.fantasy_points + 0.5 * wk.receptions.fillna(0)
wk["played"] = ((wk.attempts.fillna(0) > 0) | (wk.carries.fillna(0) > 0)).astype(int)
g = pd.read_csv(f"{RAW}/games.csv"); g = g[(g.game_type == "REG") & (g.season >= 2016)]
st = pd.concat([g[["season", "week", "home_qb_id", "home_team"]].set_axis(["season", "week", "player_id", "team"], axis=1),
                g[["season", "week", "away_qb_id", "away_team"]].set_axis(["season", "week", "player_id", "team"], axis=1)])
tgw = st.groupby(["season", "team"]).week.apply(sorted)

rows = []
for f in sorted(glob.glob(f"{SNAP}/hv_20*_w*.rds")):
    b_ = os.path.basename(f); S, W = int(b_[3:7]), int(b_[9:11])
    last = 17 if S <= 2020 else 18
    if S > 2025 or W < 3 or W > last - 3: continue
    x = rdata.read_rds(f)["redraft"]; q = x[x.pos == "QB"].copy()
    q["season"], q["week"] = S, W
    rows.append(q[["player_id", "name", "team", "season", "week", "status", "games", "credible_ppg", "rep_ppg", "team_games_left", "exp_games_left", "value"]])
sn = pd.concat(rows)
sn["value_raw"] = sn.value; sn["value"] = sn.value.clip(lower=0)   # the board floors rest-of-season value at 0
w = wk[["player_id", "season", "week", "fp", "played"]]
fut = sn[["player_id", "season", "week", "rep_ppg"]].merge(w, on=["player_id", "season"], suffixes=("", "_g"))
fut = fut[fut.week_g > fut.week]
agg = fut.assign(v=lambda z: z.played * (z.fp - z.rep_ppg)).groupby(["player_id", "season", "week"]).agg(g_ros=("played", "sum"), pts_vs_rep=("v", "sum")).reset_index()
sn = sn.merge(agg, on=["player_id", "season", "week"], how="left"); sn[["g_ros", "pts_vs_rep"]] = sn[["g_ros", "pts_vs_rep"]].fillna(0)
sn["real"] = sn.pts_vs_rep.clip(lower=0)
# starts so far
ss = st.merge(sn[["player_id", "season", "week"]].drop_duplicates(), on=["player_id", "season"], suffixes=("_g", ""))
ss = ss[ss.week_g <= ss.week].groupby(["player_id", "season", "week"]).size().rename("starts_so_far").reset_index()
sn = sn.merge(ss, on=["player_id", "season", "week"], how="left"); sn["starts_so_far"] = sn.starts_so_far.fillna(0)
sn["team_games_so_far"] = (sn.week - 1).clip(lower=1)   # approx. (one bye in weeks 4-14)
sn["starter_before"] = sn.starts_so_far >= 0.5 * sn.team_games_so_far
say(f"QB snapshot rows 2016-2025 (weeks 3 to last-3): {len(sn)}; statuses: {sn.status.value_counts().to_dict()}")

# ---------- Rule A: Backup = 0 ----------
b = sn[sn.status == "Backup"]
def summ(x, lab):
    return dict(group=lab, rows=len(x), pred_total=x.value.sum(), real_total=x.real.sum(), ratio=x.value.sum() / max(x.real.sum(), 1e-9),
                rmse_live=np.sqrt(np.mean((x.value - x.real) ** 2)), rmse_zero=np.sqrt(np.mean(x.real ** 2)),
                share_real_pos=(x.real > 0).mean(), real_p95=x.real.quantile(0.95), real_max=x.real.max())
ra = pd.DataFrame([summ(b, "Backup, all"), summ(b[b.season >= 2022], "Backup, 2022-2025"), summ(b[b.starts_so_far >= 2], "Backup with 2+ starts so far"),
                   summ(b[b.starts_so_far == 0], "Backup with 0 starts so far")])
say("\nRule A, Backup-tagged QBs: live rest-of-season value vs realized (points over the QB24 line):\n" + ra.round(3).to_string(index=False))
ra.to_csv("bq_04_rule_a_backup_zero.csv", index=False)
say("\nBackup-tagged snapshot rows with the largest realized rest-of-season value:\n" +
    b.sort_values("real", ascending=False).head(15)[["name", "season", "week", "team", "games", "starts_so_far", "value", "real", "g_ros"]].round(2).to_string(index=False))
# how often do backups end up starting a fantasy-useful stretch? by week
by_w = b.assign(wb=pd.cut(b.week, [2, 6, 10, 14, 18], labels=["wk 3-6", "wk 7-10", "wk 11-14", "wk 15"])).groupby("wb", observed=True).agg(rows=("real", "size"), live=("value", "mean"), real=("real", "mean"), share_pos=("real", lambda s: (s > 0).mean()))
say("\nBackup rows by snapshot week (mean points over line):\n" + by_w.round(3).to_string())

# ---------- Rule B: IR starters keep value with team games left - 4 ----------
ir = sn[(sn.status == "IR") & sn.starter_before].copy()
ir["g_rule"] = (ir.team_games_left - 4).clip(lower=0)
avail = sn[(sn.status == "") & sn.starter_before]
ratio_h = avail.g_ros.sum() / avail.team_games_left.sum()            # healthy starters play this share of the games left
ir["g_rule_h"] = ir.g_rule * ratio_h
pp = (ir.credible_ppg - ir.rep_ppg).clip(lower=0)
ir["v_rule"] = ir.g_rule * pp; ir["v_rule_h"] = ir.g_rule_h * pp
# calibrated variant: scale the rule so total games match on 2020-2025 (in-sample, small sample)
c_cal = ir[ir.season >= 2020].g_ros.sum() / ir[ir.season >= 2020].g_rule.sum()
ir["g_rule_c"] = ir.g_rule * c_cal; ir["v_rule_c"] = ir.g_rule_c * pp
say(f"calibration factor for the rule (2020-2025 actual games / rule games): {c_cal:.3f}")
rr = ir[ir.season >= 2020].assign(gl=pd.cut(ir.team_games_left, [0, 4, 7, 10, 17], labels=["1-4", "5-7", "8-10", "11+"]))
say("\nIR starters 2020-2025 by team games left: share who played again, games played, rule games:\n" +
    rr.groupby("gl", observed=True).agg(rows=("g_ros", "size"), players=("player_id", "nunique"), returned=("g_ros", lambda s: (s > 0).mean()),
                                         g_actual=("g_ros", "mean"), g_rule=("g_rule", "mean"), g_live=("exp_games_left", "mean")).round(3).to_string())
say(f"\nhealthy starters (no tag) play {ratio_h:.3f} of their team's remaining games")
def summ_b(x, lab):
    return dict(group=lab, rows=len(x), players=x.player_id.nunique(), team_games_left=x.team_games_left.mean(), g_live=x.exp_games_left.mean(),
                g_rule=x.g_rule.mean(), g_rule_h=x.g_rule_h.mean(), g_actual=x.g_ros.mean(), share_returned=(x.g_ros > 0).mean(),
                mae_g_live=np.mean(np.abs(x.exp_games_left - x.g_ros)), mae_g_rule=np.mean(np.abs(x.g_rule - x.g_ros)), mae_g_rule_h=np.mean(np.abs(x.g_rule_h - x.g_ros)), g_rule_c=x.g_rule_c.mean(), mae_g_rule_c=np.mean(np.abs(x.g_rule_c - x.g_ros)), v_rule_c=x.v_rule_c.sum(),
                rmse_v_rule_c=np.sqrt(np.mean((x.v_rule_c - x.real) ** 2)),
                v_live=x.value.sum(), v_rule=x.v_rule.sum(), v_rule_h=x.v_rule_h.sum(), v_real=x.real.sum(),
                rmse_v_live=np.sqrt(np.mean((x.value - x.real) ** 2)), rmse_v_rule=np.sqrt(np.mean((x.v_rule - x.real) ** 2)), rmse_v_rule_h=np.sqrt(np.mean((x.v_rule_h - x.real) ** 2)))
rb = pd.DataFrame([summ_b(ir, "IR starters, 2016-2025"), summ_b(ir[ir.season <= 2019], "2016-2019 (IR mostly season-ending)"),
                   summ_b(ir[ir.season.between(2020, 2021)], "2020-2021 (3-game IR)"), summ_b(ir[ir.season >= 2022], "2022-2025 (4-game IR)"),
                   summ_b(ir[(ir.season >= 2022) & (ir.team_games_left >= 8)], "2022-2025, 8+ team games left")])
say("\nRule B, starters on IR: expected games and rest-of-season value, live vs 'team games left - 4' (rule) vs actual:\n" + rb.round(3).T.to_string())
rb.to_csv("bq_04_rule_b_ir_starters.csv", index=False)
# distribution of games missed after an IR snapshot (2022-2025), first IR snapshot per player-season
fi = ir[ir.season >= 2022].sort_values("week").groupby(["player_id", "season"]).head(1)
fi = fi.assign(missed=fi.team_games_left - fi.g_ros)
say("\nFirst IR snapshot per player-season, 2022-2025 starters:\n" + fi[["name", "season", "week", "team_games_left", "exp_games_left", "g_rule", "g_ros", "missed", "value", "v_rule", "real"]].round(2).to_string(index=False))
fig, ax = plt.subplots(1, 2, figsize=(12, 4.5))
ax[0].hist(fi.missed, bins=range(0, 16), color="#2b5d9b", edgecolor="white"); ax[0].axvline(4, color="#d9822b", lw=2, label="rule: 4 games")
ax[0].set_xlabel("Team games missed after the first IR snapshot (rest of season)"); ax[0].set_ylabel("Players"); ax[0].set_title("Starters placed on IR, 2022-2025"); ax[0].legend()
ax[1].scatter(fi.exp_games_left, fi.g_ros, label="live expected games", color="#888888"); ax[1].scatter(fi.g_rule, fi.g_ros, label="rule: team games left - 4", color="#d9822b")
m = max(fi.team_games_left.max(), 1); ax[1].plot([0, m], [0, m], "k:"); ax[1].set_xlabel("Predicted games"); ax[1].set_ylabel("Actual games played"); ax[1].legend(); ax[1].set_title("Predicted vs actual games, IR starters")
fig.tight_layout(); fig.savefig("figs/ir_starters_games.png", dpi=130); plt.close(fig)
fig, ax = plt.subplots(figsize=(7, 4.5))
ax.hist(b.real, bins=40, color="#2b5d9b"); ax.set_yscale("log"); ax.set_xlabel("Realized rest-of-season points over QB24 line"); ax.set_ylabel("Snapshot rows (log)"); ax.set_title("Backup-tagged QBs, 2016-2025: what they actually produced")
fig.tight_layout(); fig.savefig("figs/backup_ros_realized.png", dpi=130); plt.close(fig)
LOG.close()
