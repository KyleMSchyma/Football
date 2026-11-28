"""Archetype research, step 1: build NFL player-season usage/style table (2016-2026 regular season).

Sources (all nflverse, open data): play_by_play, pbp_participation (2016-2025; on-field ids), stats_player,
players (height/weight/draft). Run: python3 ar_01_build.py <nflverse_parquet_dir>
Output: ar_player_seasons.csv (one row per player-season, QB/RB/WR/TE).
"""
import sys, numpy as np, pandas as pd
D = sys.argv[1] if len(sys.argv) > 1 else "nfl"
YEARS = range(2016, 2027)
PBP_COLS = ["game_id","play_id","season","season_type","week","posteam","play_type","pass_attempt","rush_attempt",
            "qb_dropback","qb_scramble","qb_kneel","qb_spike","sack","interception","air_yards","yards_after_catch",
            "yards_gained","yardline_100","passer_player_id","rusher_player_id","receiver_player_id","complete_pass",
            "touchdown","pass_touchdown","rush_touchdown","epa","two_point_attempt"]
out = []
for y in YEARS:
    p = pd.read_parquet(f"{D}/play_by_play_{y}.parquet", columns=PBP_COLS)
    p = p[(p.season_type == "REG") & (p.two_point_attempt != 1) & p.play_type.isin(["pass", "run", "qb_kneel", "qb_spike"])]
    p = p[(p.qb_kneel != 1) & (p.qb_spike != 1)]
    p["dropback"] = (p.qb_dropback == 1)
    p["designed_run"] = (p.rush_attempt == 1) & (p.qb_scramble != 1)
    # ---- participation: on-field snaps by play type
    try:
        part = pd.read_parquet(f"{D}/pbp_participation_{y}.parquet", columns=["nflverse_game_id","play_id","offense_players","route"])
        part = part.rename(columns={"nflverse_game_id": "game_id"})
    except FileNotFoundError:
        part = None
    if part is not None:
        pp = p.merge(part, on=["game_id", "play_id"], how="left")
        has = pp.offense_players.fillna("").str.len() > 0
        pp["team_cov"] = has
        on = pp.loc[has, ["game_id", "play_id", "posteam", "dropback", "offense_players"]].copy()
        on["pid"] = on.offense_players.str.split(";")
        on = on.explode("pid")
        snaps = on.groupby(["pid", "posteam"]).agg(snaps=("play_id", "size"), pass_snaps=("dropback", "sum")).reset_index()
        snaps["run_snaps"] = snaps.snaps - snaps.pass_snaps
        team_cov = pp[has].groupby("posteam").agg(team_cov_plays=("play_id", "size"), team_cov_pass=("dropback", "sum")).reset_index()
        snaps = snaps.merge(team_cov, on="posteam")
        snaps = snaps.rename(columns={"pid": "player_id", "posteam": "team"})
        p = pp
    else:
        p["route"] = np.nan; snaps = None
    team = p.groupby("posteam").agg(team_plays=("play_id", "size"), team_dropbacks=("dropback", "sum"),
                                    team_targets=("receiver_player_id", lambda s: s.notna().sum()),
                                    team_air=("air_yards", lambda s: s[p.loc[s.index, "receiver_player_id"].notna()].clip(lower=0).sum()),
                                    team_rush=("rush_attempt", "sum")).reset_index().rename(columns={"posteam": "team"})
    rz = p[p.yardline_100 <= 20]; gl = p[p.yardline_100 <= 5]
    team["team_rz_targets"] = team.team.map(rz[rz.receiver_player_id.notna()].groupby("posteam").size()).fillna(0)
    team["team_gl_rush"] = team.team.map(gl[gl.rush_attempt == 1].groupby("posteam").size()).fillna(0)
    rbpos = None
    # ---- passing
    pa = p[p.dropback & p.passer_player_id.notna()]
    tgt = pa[pa.pass_attempt == 1]
    qb = pa.groupby(["passer_player_id", "posteam"]).agg(
        dropbacks=("play_id", "size"), pass_att=("pass_attempt", "sum"), sacks=("sack", "sum"),
        ints=("interception", "sum"), pass_epa=("epa", "sum"),
        scrambles=("qb_scramble", "sum")).reset_index().rename(columns={"passer_player_id": "player_id", "posteam": "team"})
    t2 = tgt[tgt.air_yards.notna()].groupby(["passer_player_id", "posteam"]).agg(
        adot_pass=("air_yards", "mean"), deep_att=("air_yards", lambda s: (s >= 20).sum()),
        short_att=("air_yards", lambda s: (s <= 0).sum()), aired=("air_yards", "size")).reset_index().rename(
        columns={"passer_player_id": "player_id", "posteam": "team"})
    qb = qb.merge(t2, on=["player_id", "team"], how="left")
    # scrambles credited to rusher on scramble plays (rusher id == QB)
    sc = p[(p.qb_scramble == 1) & p.rusher_player_id.notna()].groupby(["rusher_player_id", "posteam"]).agg(
        scr_n=("play_id", "size"), scr_yds=("yards_gained", "sum")).reset_index().rename(columns={"rusher_player_id": "player_id", "posteam": "team"})
    # ---- rushing
    ru = p[(p.rush_attempt == 1) & p.rusher_player_id.notna()]
    rush = ru.groupby(["rusher_player_id", "posteam"]).agg(
        carries=("play_id", "size"), rush_yds=("yards_gained", "sum"), rush_td=("rush_touchdown", "sum"),
        designed_runs=("designed_run", "sum"),
        designed_yds=("yards_gained", lambda s: s[ru.loc[s.index, "designed_run"]].sum()),
        runs_10p=("yards_gained", lambda s: (s >= 10).sum()), runs_15p=("yards_gained", lambda s: (s >= 15).sum()),
        runs_le0=("yards_gained", lambda s: (s <= 0).sum()),
        gl_carries=("yardline_100", lambda s: (s <= 5).sum()), rz_carries=("yardline_100", lambda s: (s <= 20).sum()),
        short_yd=("yards_gained", "size")).reset_index().rename(columns={"rusher_player_id": "player_id", "posteam": "team"})
    # ---- receiving
    rc = p[p.receiver_player_id.notna() & (p.pass_attempt == 1)].copy()
    rc["deep"] = rc.air_yards >= 20
    rc["behind"] = rc.air_yards <= 0
    rc["rz"] = rc.yardline_100 <= 20
    rc["ez"] = rc.yardline_100 <= 10
    r = rc.route.fillna("").str.upper()
    rc["rt_known"] = r != ""
    rc["rt_vert"] = r.isin(["GO", "POST", "CORNER", "WHEEL"])
    rc["rt_short_in"] = r.isin(["SLANT", "SHALLOW CROSS/DRAG", "IN/DIG", "TEXAS/ANGLE"])
    rc["rt_screen"] = r.isin(["SCREEN", "SWING"])
    rc["rt_out_hitch"] = r.isin(["QUICK OUT", "HITCH/CURL", "DEEP OUT", "FLAT"])
    rec = rc.groupby(["receiver_player_id", "posteam"]).agg(
        targets=("play_id", "size"), receptions=("complete_pass", "sum"),
        rec_yds=("yards_gained", lambda s: s[rc.loc[s.index, "complete_pass"] == 1].sum()),
        yac=("yards_after_catch", "sum"), air_tgt=("air_yards", lambda s: s.clip(lower=0).sum()),
        adot=("air_yards", "mean"), deep_tgt=("deep", "sum"), behind_tgt=("behind", "sum"),
        rz_tgt=("rz", "sum"), ez_tgt=("ez", "sum"), rec_td=("pass_touchdown", "sum"),
        rt_known=("rt_known", "sum"), rt_vert=("rt_vert", "sum"), rt_short_in=("rt_short_in", "sum"),
        rt_screen=("rt_screen", "sum"), rt_out_hitch=("rt_out_hitch", "sum")).reset_index().rename(
        columns={"receiver_player_id": "player_id", "posteam": "team"})
    games = pd.concat([pa[["passer_player_id", "game_id", "posteam"]].set_axis(["player_id", "game_id", "team"], axis=1),
                       ru[["rusher_player_id", "game_id", "posteam"]].set_axis(["player_id", "game_id", "team"], axis=1),
                       rc[["receiver_player_id", "game_id", "posteam"]].set_axis(["player_id", "game_id", "team"], axis=1)])
    g = games.drop_duplicates().groupby(["player_id", "team"]).size().rename("games_active_usage").reset_index()
    df = g.merge(qb, on=["player_id", "team"], how="left").merge(sc, on=["player_id", "team"], how="left") \
          .merge(rush, on=["player_id", "team"], how="left").merge(rec, on=["player_id", "team"], how="left")
    if snaps is not None:
        df = df.merge(snaps, on=["player_id", "team"], how="left")
    df = df.merge(team, on="team", how="left")
    df["season"] = y
    out.append(df); print(y, len(df))
df = pd.concat(out, ignore_index=True)
# player-season: keep the team with most usage as 'team', sum numerics across teams
num = [c for c in df.columns if c not in ("player_id", "team", "season") and not c.startswith("team_") and c not in ("adot", "adot_pass")]
df["usage_n"] = df[["dropbacks", "carries", "targets"]].fillna(0).sum(axis=1)
# weighted means for adot fields
df["adot_x_t"] = df.adot * df.targets; df["adotp_x_a"] = df.adot_pass * df.aired
tcols = [c for c in df.columns if c.startswith("team_")]
for c in tcols: df[c + "_w"] = df[c] * df.usage_n
agg = {c: "sum" for c in num + ["usage_n", "adot_x_t", "adotp_x_a"] + [c + "_w" for c in tcols]}
main_team = df.sort_values("usage_n").groupby(["player_id", "season"]).team.last()
ps = df.groupby(["player_id", "season"]).agg(agg).reset_index()
ps["team"] = ps.set_index(["player_id", "season"]).index.map(main_team)
ps["n_teams"] = df.groupby(["player_id", "season"]).size().values
for c in tcols: ps[c] = ps[c + "_w"] / ps.usage_n.replace(0, np.nan); ps.drop(columns=c + "_w", inplace=True)
ps["adot"] = ps.adot_x_t / ps.targets.replace(0, np.nan)
ps["adot_pass"] = ps.adotp_x_a / ps.aired.replace(0, np.nan)
# player info
pl = pd.read_parquet(f"{D}/players.parquet", columns=["gsis_id", "display_name", "position", "height", "weight",
                                                       "draft_year", "draft_round", "draft_pick", "birth_date", "college_name"])
ps = ps.merge(pl.rename(columns={"gsis_id": "player_id"}), on="player_id", how="left")
# official stats (games, fantasy points)
st = pd.concat([pd.read_parquet(f"{D}/stats_player_reg_{y}.parquet", columns=["player_id", "season", "games", "fantasy_points_ppr", "position"]) for y in YEARS])
st = st.rename(columns={"position": "pos_stats"})
ps = ps.merge(st, on=["player_id", "season"], how="left")
ps["position"] = ps.position.fillna(ps.pos_stats)
ps = ps[ps.position.isin(["QB", "RB", "FB", "WR", "TE"])].copy()
ps.loc[ps.position == "FB", "position"] = "RB"
ps.to_csv("ar_player_seasons.csv", index=False)
print(ps.shape, ps.position.value_counts().to_dict())

# ---- PFR snap counts (all years incl. 2026): season snap share over games the player appeared in
sn = pd.concat([pd.read_parquet(f"{D}/snap_counts_{y}.parquet") for y in YEARS])
sn = sn[(sn.game_type == "REG")]
tg = sn.groupby(["game_id", "team"]).offense_snaps.max().rename("team_game_snaps").reset_index()
sn = sn.merge(tg, on=["game_id", "team"])
sn = sn[sn.offense_snaps > 0]
pfr = sn.groupby(["pfr_player_id", "season"]).agg(pfr_snaps=("offense_snaps", "sum"), pfr_team_snaps=("team_game_snaps", "sum"),
                                                  pfr_games=("game_id", "nunique")).reset_index()
pfr["snap_share"] = pfr.pfr_snaps / pfr.pfr_team_snaps
idmap = pd.read_parquet(f"{D}/players.parquet", columns=["gsis_id", "pfr_id"]).dropna().drop_duplicates("pfr_id")
pfr = pfr.merge(idmap, left_on="pfr_player_id", right_on="pfr_id").rename(columns={"gsis_id": "player_id"})
ps = ps.merge(pfr[["player_id", "season", "pfr_snaps", "pfr_team_snaps", "pfr_games", "snap_share"]], on=["player_id", "season"], how="left")
ps.to_csv("ar_player_seasons.csv", index=False)
print("snap coverage", ps.groupby("season").snap_share.apply(lambda s: s.notna().mean()).round(2).to_dict())
