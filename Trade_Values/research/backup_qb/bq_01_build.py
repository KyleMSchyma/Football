# =============================================================================
# Backup QB research, step 1: one row per QB-season (2002-2026) with backup status, features and outcomes.
#
# Sources (nflverse, open data): weekly player stats, games.csv starting QB ids (home_qb_id / away_qb_id),
# seasonal rosters, draft picks, players (birth dates). Usage: python bq_01_build.py RAW_DIR
#   RAW_DIR holds ps_all_old.parquet (1999-2024), ps_2025.parquet, ps_2026.parquet, games.csv, ros_YYYY.parquet,
#   draft_picks.parquet, players.parquet (download URLs in README.md).
#
# Scoring: half PPR, 4-pt pass TD, no first-down bonus (the site's QB_p4f0 reference scoring; nflverse fantasy_points
#          already uses 4-pt pass TD, -2 INT, -2 fumbles lost).
# Replacement line: QB24 = 24th-best season PPG among QBs with 5+ games that season (same 5-game rule as dv_10).
# Backup season: on a season roster or in the box scores at QB, and started fewer than half of his team's games.
# Start = listed starting QB in games.csv (home_qb_id / away_qb_id), regular season only.
# Outcomes: starter (half or more of team games) in y+1, and within y+1..y+2; realized dynasty future value
#   DFV = sum over h=1..5 of (1/1.15)^h x max(games x (PPG - QB24 line), 0), seasons after y (same floor-at-0 per season
#   and 1.15 discount as dv_11). Only complete seasons (<= 2025) count; nh = how many of the 5 seasons are observed.
# =============================================================================
import sys, os
import numpy as np, pandas as pd

RAW = sys.argv[1] if len(sys.argv) > 1 else "raw"
OUT = os.path.dirname(os.path.abspath(__file__))
LAST_DONE = 2025        # last complete season
V = 1 / 1.15

# ---------- weekly QB stats ----------
old = pd.read_parquet(f"{RAW}/ps_all_old.parquet")
old = old.rename(columns={"recent_team": "team"})
new = pd.concat([pd.read_parquet(f"{RAW}/ps_{y}.parquet") for y in (2025, 2026)])
cols = ["player_id", "player_display_name", "position", "season", "week", "season_type", "team",
        "attempts", "carries", "receptions", "fantasy_points"]
wk = pd.concat([old[cols], new[cols]])
wk = wk[(wk.season_type == "REG") & (wk.season >= 2002)]
wk["fp"] = wk.fantasy_points + 0.5 * wk.receptions.fillna(0)
wk["played"] = ((wk.attempts.fillna(0) > 0) | (wk.carries.fillna(0) > 0)).astype(int)

# ---------- starts from games.csv ----------
g = pd.read_csv(f"{RAW}/games.csv")
g = g[(g.game_type == "REG") & (g.season >= 2002)]
st = pd.concat([g[["season", "week", "home_team", "home_qb_id", "home_score"]].set_axis(["season", "week", "team", "player_id", "sc"], axis=1),
                g[["season", "week", "away_team", "away_qb_id", "away_score"]].set_axis(["season", "week", "team", "player_id", "sc"], axis=1)])
done_games = st[st.sc.notna()]
team_games = done_games.groupby(["season", "team"]).size().rename("tg").reset_index()
st = done_games.dropna(subset=["player_id"])[["season", "week", "team", "player_id"]].assign(start=1)
# opened the season as his team's starter (started the team's first game): injured / benched starters, not backups
wk1 = st.sort_values("week").groupby(["season", "team"]).head(1)[["season", "player_id"]].drop_duplicates().assign(opened=1)

wk = wk.merge(st[["season", "week", "player_id", "start"]], on=["season", "week", "player_id"], how="left")
wk["start"] = wk.start.fillna(0).astype(int)
qbw = wk[wk.position == "QB"].copy()

# season totals
qbw["fp_s"] = qbw.fp * qbw.start
ps = qbw.groupby(["player_id", "season"]).agg(name=("player_display_name", "last"), g=("played", "sum"), starts=("start", "sum"),
                                              pts=("fp", "sum"), pts_s=("fp_s", "sum"), att=("attempts", "sum"),
                                              team_stats=("team", lambda s: s.mode().iat[0])).reset_index()
# starts can exist for a player-week with no stat row (rare); take max with the games.csv count
st_cnt = st.groupby(["player_id", "season"]).size().rename("starts_gc").reset_index()
ps = ps.merge(st_cnt, on=["player_id", "season"], how="outer")
ps["starts"] = np.maximum(ps.starts.fillna(0), ps.starts_gc.fillna(0)).astype(int)
for c in ["g", "pts", "pts_s", "att"]:
    ps[c] = ps[c].fillna(0)
ps["ppg"] = np.where(ps.g > 0, ps.pts / ps.g.clip(lower=1), np.nan)
ps["ppg_s"] = np.where(ps.starts > 0, ps.pts_s / ps.starts.clip(lower=1), np.nan)

# replacement line: QB24 PPG among QBs with 5+ games
def qb24(x):
    v = np.sort(x.loc[x.g >= 5, "ppg"].values)[::-1]
    return v[23] if len(v) >= 24 else np.nan
rep = ps.groupby("season").apply(qb24, include_groups=False).rename("rep").reset_index()
ps = ps.merge(rep, on="season")

# ---------- roster membership (zero-snap backups too) ----------
ros = pd.concat([pd.read_parquet(f"{RAW}/ros_{y}.parquet", columns=["season", "team", "position", "gsis_id", "full_name", "status", "birth_date", "rookie_year", "entry_year", "draft_number"])
                 for y in range(2002, 2027)])
ros = ros[(ros.position == "QB") & ros.gsis_id.notna()].rename(columns={"gsis_id": "player_id"})
ros_s = ros.groupby(["player_id", "season"]).agg(team_ros=("team", "last"), name_ros=("full_name", "last"), ros_status=("status", "last")).reset_index()

base = ps.merge(ros_s, on=["player_id", "season"], how="outer")
base["team"] = base.team_ros.fillna(base.team_stats)
base["name"] = base.name.fillna(base.name_ros)
for c in ["g", "starts", "pts", "pts_s", "att"]:
    base[c] = base[c].fillna(0)
base = base.drop(columns=["rep"]).merge(rep, on="season", how="left")
base = base.merge(team_games.rename(columns={"team": "team"}), on=["season", "team"], how="left")
base["tg"] = base.tg.fillna(base.season.map(lambda y: 17 if y >= 2021 else 16))
base["ss"] = (base.starts / base.tg).clip(upper=1)
base["starter"] = (base.ss >= 0.5).astype(int)
base = base.merge(wk1, on=["season", "player_id"], how="left"); base["opened"] = base.opened.fillna(0).astype(int)
# backup season (the population of the model): fewer than half the team's starts, did not open the season as the starter,
# and still on a roster at season end (not cut, practice squad, retired or a free agent)
base["backup"] = ((base.starter == 0) & (base.opened == 0) & ~base.ros_status.isin(["CUT", "DEV", "UFA", "RET", "NWT", "RSN", "RSR"])).astype(int)

# ---------- player info ----------
pl = pd.read_parquet(f"{RAW}/players.parquet", columns=["gsis_id", "birth_date", "rookie_season", "draft_year", "draft_pick", "display_name"]).rename(columns={"gsis_id": "player_id"})
dp = pd.read_parquet(f"{RAW}/draft_picks.parquet", columns=["gsis_id", "season", "pick"]).dropna(subset=["gsis_id"]).rename(columns={"gsis_id": "player_id", "season": "dyear", "pick": "dpick"}).drop_duplicates("player_id")
info = pl.merge(dp, on="player_id", how="left")
rinfo = ros.sort_values("season").groupby("player_id").agg(bd2=("birth_date", "last"), ry2=("rookie_year", "min"), ey2=("entry_year", "min"), dn2=("draft_number", "last")).reset_index()
info = info.merge(rinfo, on="player_id", how="outer")
info["bd"] = pd.to_datetime(info.birth_date.fillna(info.bd2), errors="coerce")
first_stat = ps.groupby("player_id").season.min().rename("first_stat")
info = info.merge(first_stat, on="player_id", how="left")
info["rookie"] = pd.to_numeric(info.draft_year, errors="coerce").fillna(info.dyear).fillna(info.ey2).fillna(info.ry2).fillna(info.rookie_season).fillna(info.first_stat)
info["pick"] = pd.to_numeric(info.dpick, errors="coerce").fillna(pd.to_numeric(info.draft_pick, errors="coerce")).fillna(pd.to_numeric(info.dn2, errors="coerce"))
for c_ in ["rookie"]: pass
info = info[["player_id", "bd", "rookie", "pick"]].drop_duplicates("player_id")
base = base.merge(info, on="player_id", how="left")
base["age"] = (pd.to_datetime(base.season.astype(int).astype(str) + "-09-01") - base.bd).dt.days / 365.25 + 1   # age at the start of season y+1
base["exp"] = (base.season - base.rookie).clip(lower=0)
base["undrafted"] = base.pick.isna().astype(int)
base["lpick"] = np.log(base.pick.fillna(300).clip(upper=300))

# ---------- career features through y ----------
base = base.sort_values(["player_id", "season"]).reset_index(drop=True)
base["pts_s_vs_rep"] = base.pts_s - base.starts * base.rep          # points over the QB24 line in starts
gb = base.groupby("player_id")
base["c_starts"] = gb.starts.cumsum()
base["c_starts_prev"] = base.c_starts - base.starts
base["c_vs_rep"] = gb.pts_s_vs_rep.cumsum()
base["c_ppg_s_vs_rep"] = np.where(base.c_starts > 0, base.c_vs_rep / base.c_starts.clip(lower=1), np.nan)   # career PPG in starts - QB24 line
base["spot_vs_rep"] = np.where(base.starts > 0, base.ppg_s - base.rep, np.nan)                         # this season, PPG in starts - line
base["ever_starter_prev"] = gb.starter.transform(lambda s: s.shift(1, fill_value=0).cummax())
base["relief"] = (base.g - base.starts).clip(lower=0)
base["seasons_on_roster"] = gb.cumcount() + 1

# ---------- outcomes ----------
nxt = base[["player_id", "season", "starts", "ss", "starter", "g", "ppg", "rep", "pts"]].copy()
def shift(h):
    x = nxt.copy(); x["season"] = x.season - h
    return x.rename(columns={c: f"{c}_{h}" for c in nxt.columns if c not in ("player_id", "season")})
for h in range(1, 6):
    base = base.merge(shift(h), on=["player_id", "season"], how="left")
rep_by = rep.set_index("season").rep
dfv = np.zeros(len(base)); nh = np.zeros(len(base), int)
for h in range(1, 6):
    yo = base.season + h
    ok = yo <= LAST_DONE
    rep_h = yo.map(rep_by)
    val = np.maximum(base[f"g_{h}"].fillna(0) * (base[f"ppg_{h}"].fillna(0) - rep_h), 0)
    dfv += np.where(ok, V ** h * val, 0); nh += ok.astype(int)
    base[f"st_{h}"] = np.where(ok, base[f"starter_{h}"].fillna(0), np.nan)
    base[f"val_{h}"] = np.where(ok, val, np.nan)
base["dfv"] = dfv; base["nh"] = nh
base["y_start1"] = base.st_1
base["y_start12"] = np.where(base.season + 2 <= LAST_DONE, np.maximum(base.st_1.fillna(0), base.st_2.fillna(0)), np.nan)

keep = ["player_id", "name", "season", "team", "age", "exp", "pick", "lpick", "undrafted", "g", "starts", "tg", "ss", "starter",
        "relief", "att", "opened", "backup", "ppg", "ppg_s", "rep", "spot_vs_rep", "c_starts", "c_starts_prev", "c_ppg_s_vs_rep", "ever_starter_prev",
        "seasons_on_roster", "ros_status", "starts_1", "starts_2", "st_1", "st_2", "y_start1", "y_start12",
        "val_1", "val_2", "val_3", "val_4", "val_5", "dfv", "nh", "ppg_1", "g_1"]
out = base[keep]
out.to_csv(f"{OUT}/bq_qb_seasons.csv", index=False)
rep.to_csv(f"{OUT}/bq_rep_line.csv", index=False)
bk = out[(out.backup == 1)]
print("QB-seasons:", len(out), " backup seasons:", len(bk), " with 2-year outcome:", bk.y_start12.notna().sum())
print("rep line (QB24 half-PPR):", rep.set_index("season").rep.round(2).to_dict())
print("backup -> starter within 2 years, by season:", bk.groupby("season").y_start12.mean().round(3).to_dict())
