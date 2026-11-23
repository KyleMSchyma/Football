import json, pandas as pd, numpy as np
import sys
SITE=(sys.argv[1] if len(sys.argv)>1 else "../../prospect-actuary")+"/data/teams/"
REMAP={"OAK":"LV","SD":"LAC","STL":"LA"}
rows=[]
for s in range(2016,2027):
    d=json.load(open(f"{SITE}{s}.json"))
    pl=d["players"]
    for r in d["rows"]:
        c=r[4:]
        pas=0.04*c[0]+4*c[1]-2*c[2]+2*c[3]-2*c[4]
        rus=0.1*c[5]+6*c[6]+2*c[8]-2*c[9]
        rec=c[10]+0.1*c[11]+6*c[12]+2*c[14]-2*c[15]
        rows.append((s,r[2],REMAP.get(r[1],r[1]),REMAP.get(r[3],r[3]),pl[r[0]][1],pas,rus,rec))
df=pd.DataFrame(rows,columns="season week team opp pos pas rus rec".split())
df["tot"]=df.pas+df.rus+df.rec
g=df.groupby(["season","week","team","opp"])
out=g[["tot","pas","rus","rec"]].sum()
pos=df.pivot_table(index=["season","week","team","opp"],columns="pos",values="tot",aggfunc="sum",fill_value=0)
out=out.join(pos).reset_index()
print(out.shape, out.groupby("season").size().to_dict())
print(out.describe().round(2))
# check every game has a mirror
m=out.merge(out[["season","week","team","opp"]],left_on=["season","week","team","opp"],right_on=["season","week","opp","team"],how="left",indicator=True)
print(m._merge.value_counts())
print(sorted(out.team.unique()), len(out.team.unique()))
out.to_pickle("games.pkl")
