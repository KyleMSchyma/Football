# Apply the recommended model (Poisson GLM: log implied total + log credibility projection + home/wind/cold)
# to an upcoming week. Fit on all completed regular-season games 2017 onward; inputs use only games already played.
import pandas as pd, numpy as np, json, statsmodels.api as sm, sys
NO_LINES="--no-lines" in sys.argv; args=[a for a in sys.argv[1:] if a!="--no-lines"]
SEASON, WEEK = int(args[0]), int(args[1]); SCHED=args[2] if len(args)>2 else "../dl/sched.csv"
T=["tot","pas","rus","rec","QB","RB","WR","TE"]; REMAP={"OAK":"LV","SD":"LAC","STL":"LA"}
G=pd.read_pickle("games.pkl"); D=pd.read_pickle("preds_v2.pkl"); tune=json.load(open("tune.json"))
# --- credibility projection for the upcoming week (same formula and settings as the backtest)
H=G[((G.season==SEASON)&(G.week<WEEK))|(G.season==SEASON-1)].copy()
s=pd.read_csv(SCHED); s=s[(s.season==SEASON)&(s.week==WEEK)&(s.game_type=="REG")]
rows=[]
RETRACTABLE_CLOSED={"HOU","DAL","ATL","ARI","IND"}   # roof missing before kickoff: these usually close in late season
for _,g in s.iterrows():
    h,a=REMAP.get(g.home_team,g.home_team),REMAP.get(g.away_team,g.away_team)
    roof=g.roof if isinstance(g.roof,str) else ("closed" if h in RETRACTABLE_CLOSED else "outdoors")
    dome=int(roof in("dome","closed"))
    wind=0 if dome else (g.wind if pd.notna(g.wind) else 8); temp=70 if dome else (g.temp if pd.notna(g.temp) else 55)
    for team,opp,home in [(h,a,1),(a,h,0)]:
        sp=g.spread_line if home else -g.spread_line
        rows.append(dict(team=team,opp=opp,home=home,dome=dome,wind_c=min(max(wind,0),25),cold=int(temp<35),
                         total_line=g.total_line,team_spread=sp,implied=g.total_line/2+sp/2,gameday=g.gameday))
U=pd.DataFrame(rows)
# fallback: credibility + home/wind/cold when lines are missing (forced with --no-lines)
no_lines=NO_LINES or U.total_line.isna().any() or U.team_spread.isna().any()
if no_lines: print("No lines: using credibility + home/wind/cold")
for t in T:
    c=tune[f"cred_{t}"]; d=c["decay"]; w=np.where(H.season==SEASON,1.0,d)
    L=(H[t]*w).sum()/w.sum()
    def side(key,k):
        out={}
        for team,x in H.assign(_w=w).groupby(key):
            n=x._w.sum(); r=(x[t]*x._w).sum()/n/L; Z=n/(n+k); out[team]=Z*r+1-Z
        return out
    ro=side("team",c["k_off"]); rd=side("opp",c["k_def"])
    U[f"cred_{t}"]=[L*ro.get(a,1)*rd.get(b,1) for a,b in zip(U.team,U.opp)]
# --- fit the GLM on every completed game with lines (2017 to last week) and predict
for t in T:
    def X(df):
        cols={"log_cred":np.log(df[f"cred_{t}"].clip(lower=1)),"home":df.home,"dome":df.dome,"wind_c":df.wind_c,"cold":df.cold}
        if not no_lines: cols.update(log_implied=np.log(df.implied.clip(lower=3)),team_spread=df.team_spread,total_line=df.total_line)
        return sm.add_constant(pd.DataFrame(cols),has_constant="add")
    m=sm.GLM(D["y_"+t].clip(lower=0),X(D),family=sm.families.Poisson()).fit()
    U[f"proj_{t}"]=m.predict(X(U))
U["sum_pos"]=U[[f"proj_{p}" for p in ["QB","RB","WR","TE"]]].sum(1); U["sum_cat"]=U[[f"proj_{p}" for p in ["pas","rus","rec"]]].sum(1)
print("max gap: positions vs total",(U.sum_pos/U.proj_tot-1).abs().max().round(3),"categories vs total",(U.sum_cat/U.proj_tot-1).abs().max().round(3))
# scale the splits so positions and categories each add up to the projected Total
for grp in (["QB","RB","WR","TE"],["pas","rus","rec"]):
    f=U.proj_tot/U[[f"proj_{p}" for p in grp]].sum(1)
    for p in grp: U[f"proj_{p}"]*=f
out=U[["team","opp","home","gameday","implied","proj_tot","cred_tot"]+[f"proj_{p}" for p in ["pas","rus","rec","QB","RB","WR","TE"]]].sort_values("proj_tot",ascending=False)
out.to_csv(f"projections_{SEASON}_wk{WEEK}{'_nolines' if no_lines else ''}.csv",index=False)
print(out.round(1).to_string(index=False))
