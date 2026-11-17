"""
Landing-spot offense study, step 1: build the player table.

Question (Kyle, 2026-11-17): do rookies who land on teams with a high-scoring fantasy
offense the year before produce more, by position and post-draft grade? And does team
offense add anything BEYOND the post-draft grade (which already uses draft pick and
landing-spot features: vacated share and incumbent production)?

Inputs
  ../PostDraft_Model/pd_post_player_grades.csv   post-draft grades 2010-2026 (LOCO scores 2010-23)
  nflverse draft_picks.csv                        drafting team + gsis id (joined on class + pick)
  nflverse weekly player stats 1999-2026          full PPR, 4-pt pass TD, regular season only
Set NFLVERSE_DIR to a folder holding draft_picks.csv, player_stats.csv.gz (1999-2024),
stats_player_week_2025.csv and stats_player_week_2026.csv (all from the nflverse-data releases).

Output
  lso_players.csv  one row per drafted QB/RB/WR/TE 2010-2026 with grade, team, prior-year
                   team offense, and NFL outcomes.
"""
import os
import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
NV = os.environ.get("NFLVERSE_DIR", os.path.join(HERE, "nflverse"))

PFR_TO_NV = {"GNB": "GB", "KAN": "KC", "LAR": "LA", "STL": "LA", "LVR": "LV", "OAK": "LV",
             "NOR": "NO", "NWE": "NE", "SDG": "LAC", "SFO": "SF", "TAM": "TB"}

# ---- weekly stats, regular season, 2009+ --------------------------------------------
old = pd.read_csv(os.path.join(NV, "player_stats.csv.gz"), low_memory=False)
old = old.rename(columns={"recent_team": "team"})
new = pd.concat([pd.read_csv(os.path.join(NV, f"stats_player_week_{y}.csv"), low_memory=False)
                 for y in (2025, 2026)])
cols = ["player_id", "position", "team", "season", "week", "season_type", "fantasy_points_ppr"]
w = pd.concat([old[cols], new[cols]])
w = w[(w.season_type == "REG") & (w.season >= 2009)].copy()
w["fantasy_points_ppr"] = w["fantasy_points_ppr"].fillna(0.0)

# ---- team offense per game, each season ------------------------------------------------
games = w.groupby(["season", "team"]).week.nunique().rename("team_games")
tot = w.groupby(["season", "team"]).fantasy_points_ppr.sum().rename("team_pts")
pos = (w[w.position.isin(["QB", "RB", "WR", "TE"])]
       .pivot_table(index=["season", "team"], columns="position",
                    values="fantasy_points_ppr", aggfunc="sum").fillna(0.0))
pos.columns = [f"team_pts_{c}" for c in pos.columns]
team = pd.concat([games, tot, pos], axis=1).reset_index()
for c in ["team_pts"] + list(pos.columns):
    team[c.replace("team_pts", "ppg")] = team[c] / team["team_games"]
# within-season standing, so eras compare fairly: z-score and percentile (0 worst, 1 best)
for c in [c for c in team.columns if c.startswith("ppg")]:
    g = team.groupby("season")[c]
    team[c + "_z"] = (team[c] - g.transform("mean")) / g.transform("std")
    team[c + "_pct"] = g.rank(pct=True)
team.to_csv(os.path.join(HERE, "lso_team_offense.csv"), index=False)

# ---- players --------------------------------------------------------------------------
gr = pd.read_csv(os.path.join(HERE, "..", "PostDraft_Model", "pd_post_player_grades.csv"))
dp = pd.read_csv(os.path.join(NV, "draft_picks.csv"))
dp = dp[dp.season >= 2010][["season", "pick", "team", "gsis_id", "pfr_player_name", "position"]]
dp = dp.rename(columns={"season": "class", "position": "dp_pos", "pfr_player_name": "dp_name"})
p = gr.merge(dp, on=["class", "pick"], how="left")
p["team"] = p["team"].replace(PFR_TO_NV)
print("players:", len(p), " matched to a drafting team:", p.team.notna().sum())
bad = p[p.team.notna() & (p.dp_pos != p.position)]
print("position mismatches (kept, same pick):", len(bad))

# prior-year offense of the drafting team
prev = team.copy()
prev["class"] = prev["season"] + 1
keep = ["class", "team", "ppg", "ppg_z", "ppg_pct"] + \
       [f"ppg_{x}{s}" for x in ["QB", "RB", "WR", "TE"] for s in ["", "_z", "_pct"]]
prev = prev[keep].rename(columns={c: "prev_" + c for c in keep if c.startswith("ppg")})
p = p.merge(prev, on=["class", "team"], how="left")
# same-season ("hindsight") offense, for contrast only: not knowable at draft time
same = team.rename(columns={"season": "class"})[["class", "team", "team_pts", "team_games"]]
p = p.merge(same, on=["class", "team"], how="left")

# ---- outcomes -------------------------------------------------------------------------
pts = w.groupby(["player_id", "season"]).fantasy_points_ppr.sum().rename("pts").reset_index()
gp = w.groupby(["player_id", "season"]).week.nunique().rename("gp").reset_index()
ps = pts.merge(gp, on=["player_id", "season"])


def yr(k):
    t = ps.copy()
    t["class"] = t["season"] - k
    return t.rename(columns={"player_id": "gsis_id", "pts": f"pts_y{k+1}", "gp": f"gp_y{k+1}"}).drop(columns="season")


for k in range(3):
    p = p.merge(yr(k), on=["gsis_id", "class"], how="left")
    p[[f"pts_y{k+1}", f"gp_y{k+1}"]] = p[[f"pts_y{k+1}", f"gp_y{k+1}"]].fillna(0)

# rookie points per team game (missed games count as zero: playing time is part of production)
p["rookie_ppg"] = p["pts_y1"] / p["team_games"]
# hindsight team offense that season, with the rookie's own points removed
p["same_ppg_excl"] = (p["team_pts"] - p["pts_y1"]) / p["team_games"]
p["y13_ppg"] = (p.pts_y1 + p.pts_y2 + p.pts_y3) / 17 / 3   # per 17-game season, approx
last_season = int(w.season.max())
p["rookie_complete"] = p["class"] < last_season
p["y13_complete"] = p["class"] <= last_season - 3
# nfl_tier: 1 = top tier (QB8/RB8/WR12/TE6), 2 = second, 3 = third, 4 = no tier
p["hit_any"] = np.where(p.outcome_complete, (p.nfl_tier <= 3).astype(float), np.nan)
p["hit_top2"] = np.where(p.outcome_complete, (p.nfl_tier <= 2).astype(float), np.nan)
band = {"A+": "A", "A": "A", "A-": "A", "B+": "B", "B": "B", "B-": "B", "C+": "C", "C": "C", "C-": "C"}
p["grade_band"] = p["post_grade"].map(band).fillna("D/F")
p.to_csv(os.path.join(HERE, "lso_players.csv"), index=False)
print(p.groupby("position")[["prev_ppg_z", "rookie_ppg"]].count())
