import pandas as pd, numpy as np, statsmodels.formula.api as smf, warnings, json
warnings.filterwarnings("ignore")
G=pd.read_pickle("games.pkl"); T=["tot","pas","rus","rec","QB","RB","WR","TE"]
tr=G[G.season<=2022].copy()
tr["offid"]=tr.team+tr.season.astype(str); tr["defid"]=tr.opp+tr.season.astype(str)
out={}
for t in T:
    Ls=tr.groupby("season")[t].transform("mean")
    x=tr[t]/Ls
    res={}
    for side,gid in [("off","offid"),("def","defid")]:
        g=x.groupby(tr[gid]); n=g.size(); m=g.mean(); v=g.var()
        epv=v.mean(); nbar=n.mean()
        vhm=m.var()-epv/nbar
        res[side+"_k"]=epv/vhm
    # crossed random effects (additive, raw points minus season mean)
    tr["yc"]=tr[t]-Ls
    md=smf.mixedlm("yc~1",tr,groups=np.ones(len(tr)),vc_formula={"o":"0+C(offid)","d":"0+C(defid)"}).fit(reml=True)
    vo,vd=md.vcomp; ve=md.scale
    res.update(var_off=vo,var_def=vd,var_res=ve,signal_share=(vo+vd)/(vo+vd+ve),off_share=vo/(vo+vd+ve),def_share=vd/(vo+vd+ve))
    out[t]=res; print(t,{k:round(v,3) for k,v in res.items()},flush=True)
json.dump(out,open("varcomp.json","w"),indent=1)
