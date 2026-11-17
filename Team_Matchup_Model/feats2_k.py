# Bühlmann k for each efficiency metric: within team-season game variance / between team-season variance of true means
import pandas as pd, numpy as np, json, os
if not os.path.exists("eff_k.json"):
    DL="../dl"; REMAP={"OAK":"LV","SD":"LAC","STL":"LA"}
    pb=pd.concat([pd.read_parquet(f"{DL}/pbp_{s}.parquet",columns=["season","week","season_type","posteam","defteam","epa","success","play_type","pass"]) for s in range(2016,2023)])
    pb=pb[(pb.season_type=="REG")&pb.play_type.isin(["pass","run"])&pb.epa.notna()]
    g=pb.groupby(["season","week","posteam","defteam"]).agg(epa=("epa","mean"),succ=("success","mean"),plays=("epa","size"),passrate=("pass","mean")).reset_index()
    K={}
    for side,key in [("o","posteam"),("d","defteam")]:
        for m in ["epa","succ","plays","passrate"]:
            gr=g.groupby(["season",key])[m]; epv=gr.var().mean(); vhm=gr.mean().var()-epv/gr.size().mean(); K[f"{side}_{m}"]=float(epv/vhm)
    json.dump(K,open("eff_k.json","w"),indent=1); print(K)
