import pandas as pd, numpy as np
D='./data/'
def terc(s):
    if len(s)<3: return pd.Series(['middle']*len(s),index=s.index)
    return pd.Series(pd.qcut(s.rank(method='first'),3,labels=['spiky','middle','steady']).astype(str),index=s.index)
for h in ['next','redraft']:
    T=pd.read_pickle(D+f'test3_{h}.pkl'); T['ppg_c']=T.pts_c/T.n_c; T['r']=T.ns_c/T.n_c
    T=T[T.n_c>=(8 if h=='next' else 5)].copy()
    T['band']=pd.cut(T.ppg_c,[8,12,16,40]).astype(str); T=T[T.band!='nan']
    T['rt']=T.groupby(['pos','band']).r.transform(terc)
    g=T.groupby(['band','rt']).apply(lambda x: pd.Series({'n':len(x),'startable':x.r.mean(),'ppg_now':x.ppg_c.mean(),'pred':np.average(x.p_base,weights=x.n_t),'actual':np.average(x.ppg_t,weights=x.n_t),'err':np.average(x.ppg_t-x.p_base,weights=x.n_t)}))
    print('\n',h); print(g.round(2).to_string())
T=pd.read_pickle(D+'test3_next.pkl'); T['ppg_c']=T.pts_c/T.n_c; T['r']=T.ns_c/T.n_c
x=T[(T.n_c>=10)&(T.ppg_c.between(13,17))&(T.pos.isin(['WR','RB']))]
c=['name','pos','season','n_c','ppg_c','r','p_base','ppg_t']
print('\nSpikiest 13-17 PPG RB/WR seasons:'); print(x.nsmallest(10,'r')[c].round(2).to_string(index=False))
print('\nSteadiest:'); print(x.nlargest(10,'r')[c].round(2).to_string(index=False))
