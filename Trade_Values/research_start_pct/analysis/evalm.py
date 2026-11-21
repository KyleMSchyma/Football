import pandas as pd, numpy as np
from scipy.optimize import minimize
from scipy.stats import spearmanr
D='./data/'
POS=['QB','RB','WR','TE']
A=pd.read_pickle(D+'snapshots.pkl')
def safe(a,b): return np.where(b>0,a/np.where(b>0,b,1),0.0)
def parts(d,m):
    if m in('base','RS','VAR','RSVAR'): return d.n_c,safe(d.pts_c,d.n_c),d.n_h,safe(d.pts_h,d.n_h)
    if m=='SW1': return d.nw_c,safe(d.pts_c,d.n_c),d.nw_h,safe(d.pts_h,d.n_h)
    if m=='SW2': return d.nw_c,safe(d.ptsw_c,d.nw_c),d.nw_h,safe(d.ptsw_h,d.nw_h)
    if m=='ST':  return d.nr_c,safe(d.ptsr_c,d.nr_c),d.nr_h,safe(d.ptsr_h,d.nr_h)
NP={'base':2,'SW1':2,'SW2':2,'ST':2,'RS':3,'VAR':3,'RSVAR':4}
def svar(n,pts,pts2,pos_s2,m=4):
    v=safe(pts2-safe(pts**2,n),np.maximum(n-1,0))
    return (np.maximum(n-1,0)*v+m*pos_s2)/(np.maximum(n-1,0)+m)
def predict(d,m,q):
    nc,pc,nh,ph=[np.asarray(x,float) for x in parts(d,m)]
    k1,k2=np.exp(q[0]),np.exp(q[1]); f1=f2=1.0
    if m in('RS','RSVAR'):
        b=q[2]; r_c=(d.nr_c.values+.5)/(d.n_c.values+1); r_h=(d.nr_h.values+.5)/(d.n_h.values+1)
        f1=r_c**-b; f2=r_h**-b
    if m in('VAR','RSVAR'):
        c=q[-1]; s2p=d['_s2p'].values
        f1=f1*(svar(d.n_c.values,d.pts_c.values,d.pts2_c.values,s2p)/s2p)**c
        f2=f2*(svar(d.n_h.values,d.pts_h.values,d.pts2_h.values,s2p)/s2p)**c
    K1,K2=k1*f1,k2*f2
    hist=nh/(nh+K2)*ph+K2/(nh+K2)*d.prior.values
    return nc/(nc+K1)*pc+K1/(nc+K1)*hist
def fit(d,m):
    def f(q): p=predict(d,m,q); return np.sum(d.n_t*(d.ppg_t-p)**2)
    q0=[np.log(4),np.log(10)]+[0.0]*(NP[m]-2)
    return minimize(f,q0,method='Nelder-Mead',options={'maxiter':4000,'xatol':1e-4,'fatol':1e-6}).x
def run(h,mmin_t):
    d=A[(A.h==h)&(A.n_c>=3)&(A.n_t>=mmin_t)].copy()
    # position weekly variance (pooled), for VAR
    s2=d.groupby('pos').apply(lambda x: np.sum(x.pts2_c-x.pts_c**2/x.n_c)/np.sum(x.n_c-1)); d['_s2p']=d.pos.map(s2)
    test_years=range(2019,2026) if h=='redraft' else range(2018,2025)
    out=[];K={}
    for p in POS:
        for y in test_years:
            tr=d[(d.pos==p)&(d.season<y)]; te=d[(d.pos==p)&(d.season==y)].copy()
            for m in NP:
                q=fit(tr,m); te['p_'+m]=predict(te,m,q); K[(p,y,m)]=q
            out.append(te)
    return pd.concat(out),K
if __name__=='__main__':
    res={}
    for h,mt in [('redraft',3),('next',4)]:
        T,K=run(h,mt); T.to_pickle(D+f'test_{h}.pkl'); pd.to_pickle(K,D+f'K_{h}.pkl')
        print('\n=====',h,len(T))
        rng=np.random.default_rng(2026); pids=T.player_id.unique()
        idx={pid:np.where(T.player_id.values==pid)[0] for pid in pids}
        for grp,G in [('ALL',T)]+[(p,T[T.pos==p]) for p in POS]:
            line=[]
            e0=(G.ppg_t-G.p_base)**2*G.n_t
            for m in NP:
                e=(G.ppg_t-G['p_'+m])**2*G.n_t
                rm=np.sqrt(e.sum()/G.n_t.sum()); sp=spearmanr(G['p_'+m],G.ppg_t)[0]
                # cluster bootstrap of RMSE difference vs base
                gp=G.player_id.values; up=np.unique(gp); gi={u:np.where(gp==u)[0] for u in up}
                diffs=[]
                for b in range(300):
                    s=np.concatenate([gi[u] for u in rng.choice(up,len(up))])
                    diffs.append(np.sqrt(e.values[s].sum()/G.n_t.values[s].sum())-np.sqrt(e0.values[s].sum()/G.n_t.values[s].sum()))
                lo,hi=np.percentile(diffs,[2.5,97.5])
                line.append(f'{m}: rmse {rm:.3f} ({rm-np.sqrt(e0.sum()/G.n_t.sum()):+.3f} [{lo:+.3f},{hi:+.3f}]) rho {sp:.3f}')
            print(grp,len(G)); print('  '+'\n  '.join(line))
