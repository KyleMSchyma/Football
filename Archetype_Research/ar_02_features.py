"""Archetype research, step 2: per-position features and qualifying samples.
Run: python3 ar_02_features.py <nflverse_parquet_dir>  -> ar_features_{QB,RB,WR,TE}.csv"""
import sys, numpy as np, pandas as pd
D = sys.argv[1] if len(sys.argv) > 1 else "nfl"
ps = pd.read_csv("ar_player_seasons.csv")
z = lambda s: s.replace(0, np.nan)
g = ps.games.fillna(ps.games_active_usage)
ps["g"] = g
# team RB opportunity totals (carries + targets by RBs on the main team)
rb = ps[ps.position == "RB"].copy()
rb["opp"] = rb.carries.fillna(0) + rb.targets.fillna(0)
team_rb = rb.groupby(["team", "season"]).opp.sum().rename("team_rb_opp")
ps = ps.merge(team_rb, on=["team", "season"], how="left")

# ---------- QB
ngs = pd.read_parquet(f"{D}/ngs_passing.parquet")
ngs = ngs[(ngs.week == 0) & (ngs.season_type == "REG")][["player_gsis_id", "season", "aggressiveness", "avg_time_to_throw", "avg_intended_air_yards"]]
qb = ps[ps.position == "QB"].merge(ngs.rename(columns={"player_gsis_id": "player_id"}), on=["player_id", "season"], how="left")
qb["qual"] = qb.dropbacks >= np.where(qb.season == 2026, 150, 250)
qb["rush_ypg"] = qb.rush_yds.fillna(0) / qb.g                # all QB rushing incl. scrambles
qb["designed_runs_pg"] = qb.designed_runs.fillna(0) / qb.g
qb["scramble_rate"] = qb.scr_n.fillna(0) / z(qb.dropbacks)
qb["rush_fp_share"] = (0.1 * qb.rush_yds.fillna(0) + 6 * qb.rush_td.fillna(0)) / z(qb.fantasy_points_ppr)
qb["deep_rate"] = qb.deep_att / z(qb.aired)
qb["int_rate"] = qb.ints / z(qb.pass_att)
qb["sack_rate"] = qb.sacks / z(qb.dropbacks)
qb["epa_db"] = qb.pass_epa / z(qb.dropbacks)
qb["dropbacks_pg"] = qb.dropbacks / qb.g
# ---------- RB
r = ps[ps.position == "RB"].copy()
r["opp"] = r.carries.fillna(0) + r.targets.fillna(0)
r["qual"] = r.opp >= np.where(r.season == 2026, 70, 100)
r["touches_pg"] = (r.carries.fillna(0) + r.receptions.fillna(0)) / r.g
r["opp_share"] = r.opp / z(r.team_rb_opp)
r["targets_pg"] = r.targets.fillna(0) / r.g
r["tgt_mix"] = r.targets.fillna(0) / z(r.opp)               # share of his opportunities that are targets
r["gl_share"] = r.gl_carries.fillna(0) / z(r.team_gl_rush)
r["explosive_rate"] = r.runs_15p / z(r.carries)
r["ypc"] = r.rush_yds / z(r.carries)
r["stuff_rate"] = r.runs_le0 / z(r.carries)
r["yprr_proxy"] = r.rec_yds.fillna(0) / z(r.targets)
# ---------- WR
w = ps[ps.position == "WR"].copy()
w["qual"] = w.targets >= np.where(w.season == 2026, 30, 40)
w["target_share"] = w.targets / z(w.team_targets)
w["air_share"] = w.air_tgt / z(w.team_air)
w["deep_rate"] = w.deep_tgt / z(w.targets)
w["behind_rate"] = w.behind_tgt / z(w.targets)
w["yac_per_rec"] = w.yac / z(w.receptions)
w["rz_share"] = w.rz_tgt / z(w.team_rz_targets)
w["rz_mix"] = w.rz_tgt / z(w.targets)
w["catch_rate"] = w.receptions / z(w.targets)
w["carries_pg"] = w.carries.fillna(0) / w.g
w["route_known"] = w.rt_known.fillna(0)
for c in ["rt_vert", "rt_short_in", "rt_screen", "rt_out_hitch"]:
    w[c + "_pct"] = w[c] / z(w.rt_known)
# ---------- TE
t = ps[ps.position == "TE"].copy()
t["qual"] = (t.pfr_snaps >= np.where(t.season == 2026, 200, 300))
t["targets_per_snap"] = t.targets.fillna(0) / z(t.pfr_snaps)
t["target_share"] = t.targets.fillna(0) / z(t.team_targets)
t["run_snap_mix"] = t.run_snaps / z(t.snaps)               # share of his snaps that were run plays (participation, <=2025)
t["team_run_mix"] = 1 - t.team_cov_pass / z(t.team_cov_plays)
t["run_tilt"] = t.run_snap_mix - t.team_run_mix             # >0 = on the field more for runs than the team average
t["rz_mix"] = t.rz_tgt / z(t.targets)
t["rz_share"] = t.rz_tgt / z(t.team_rz_targets)
t["td_per_tgt"] = t.rec_td / z(t.targets)
t["yac_per_rec"] = t.yac / z(t.receptions)
for name, d in [("QB", qb), ("RB", r), ("WR", w), ("TE", t)]:
    d.to_csv(f"ar_features_{name}.csv", index=False)
    print(name, "qualifying player-seasons:", int(d.qual.sum()), "of", len(d))
