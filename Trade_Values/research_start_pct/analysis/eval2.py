import pandas as pd, numpy as np, sys
from scipy.optimize import minimize
from scipy.stats import spearmanr
D='./data/'
POS=['QB','RB','WR','TE']
A=pd.read_pickle(D+'snapshots.pkl')
def safe(a,b): a=np.asarray(a,float); b=np.asarray(b,float); return np.where(b>0,a/np.where(b>0,b,1),0.0)
sig=lambda x,lo,hi: lo+(hi-lo)/(1+np.exp(-x))
NP={'base':2,'SR':3,'WIN':2,'MED':3,'CON':3}
def predict(d,m,q,aux=None):
    nc,nh=d.n_c.values.astype(float),d.n_h.values.astype(float)
    pc,ph=safe(d.pts_c,d.n_c),safe(d.pts_h,d.n_h)
    if m=='WIN': pc,ph=safe(d.ptsx_c,d.n_c),safe(d.ptsx_h,d.n_h)
    if m=='MED':
        l=sig(q[2],0,1); pc=(1-l)*pc+l*d.med_c.fillna(0).values; ph=np.where(nh>0,(1-l)*ph+l*d.med_h.fillna(0).values,0)
    K1,K2=np.exp(np.clip(q[0],-4,7))*np.ones(len(d)),np.exp(np.clip(q[1],-4,7))*np.ones(len(d))
    if m=='SR':
        b=sig(q[2],-1,2); rc=(d.ns_c.values+.5)/(nc+1); rh=(d.ns_h.values+.5)/(nh+1)
        rc0=d['_rbar'].values
        K1=K1*(rc/rc0)**-b; K2=K2*(rh/rc0)**-b
    hist=nh/(nh+K2)*ph+K2/(nh+K2)*d.prior.values
    p=nc/(nc+K1)*pc+K1/(nc+K1)*hist
    if m=='CON':
        # startable rate above/below what his PPG implies, times current-season credibility
        p=p+np.clip(q[2],-3,3)*d['_rres'].values*nc/(nc+K1)*10
    return p
def fit(d,m):
    f=lambda q: np.sum(d.n_t*(d.ppg_t-predict(d,m,q))**2)
    q0=[np.log(4),np.log(10)]+[0.0]*(NP[m]-2)
    return minimize(f,q0,method='Nelder-Mead',options={'maxiter':4000,'xatol':1e-4,'fatol':1e-6}).x
def add_r(d,tr):
    # expected startable rate given current PPG (fit on training rows only)
    r=lambda x:(x.ns_c+.5)/(x.n_c+1); pp=lambda x:safe(x.pts_c,x.n_c)
    Xf=lambda x: np.column_stack([np.ones(len(x)),pp(x),pp(x)**2,pp(x)**3])
    b=np.linalg.lstsq(Xf(tr),r(tr),rcond=None)[0]
    out=d.copy(); out['_rres']=r(d)-Xf(d)@b; out['_rbar']=np.average(r(tr),weights=tr.n_c); return out
def run(h,mt):
    d=A[(A.h==h)&(A.n_c>=3)&(A.n_t>=mt)].copy()
    ys=range(2019,2026) if h=='redraft' else range(2018,2025)
    out=[];K={}
    for p in POS:
        for y in ys:
            tr0=d[(d.pos==p)&(d.season<y)]; tr=add_r(tr0,tr0); te=add_r(d[(d.pos==p)&(d.season==y)],tr0)
            for m in NP:
                q=fit(tr,m); te['p_'+m]=predict(te,m,q); K[(p,y,m)]=q
            out.append(te)
    return pd.concat(out),K
if __name__=='__main__':
    for h,mt in [(a,{'redraft':3,'next':4}[a]) for a in sys.argv[1:]]:
        T,K=run(h,mt); T.to_pickle(D+f'test3_{h}.pkl'); pd.to_pickle(K,D+f'K3_{h}.pkl')
        print('\n=====',h,len(T))
        for m,(i,lo,hi) in {'SR':(2,-1,2),'MED':(2,0,1),'CON':(2,None,None)}.items():
            v=[K[k][i] for k in K if k[2]==m]
            v=[sig(x,lo,hi) for x in v] if lo is not None else v
            print(f'  fitted {m} param by pos:',{p:round(float(np.mean([ (sig(K[k][i],lo,hi) if lo is not None else K[k][i]) for k in K if k[2]==m and k[0]==p])),3) for p in POS})
        rng=np.random.default_rng(2026)
        for grp,G in [('ALL',T)]+[(p,T[T.pos==p]) for p in POS]:
            e0=((G.ppg_t-G.p_base)**2*G.n_t).values; W=G.n_t.values
            gp=G.player_id.values; up=np.unique(gp); gi={u:np.where(gp==u)[0] for u in up}
            S=[np.concatenate([gi[u] for u in rng.choice(up,len(up))]) for b in range(300)]
            line=[]
            for m in NP:
                e=((G.ppg_t-G['p_'+m])**2*G.n_t).values; rm=np.sqrt(e.sum()/W.sum())
                dd=[np.sqrt(e[s].sum()/W[s].sum())-np.sqrt(e0[s].sum()/W[s].sum()) for s in S]
                lo,hi=np.percentile(dd,[2.5,97.5])
                line.append(f'{m:5s} rmse {rm:.3f} ({rm-np.sqrt(e0.sum()/W.sum()):+.3f} [{lo:+.3f},{hi:+.3f}]) rho {spearmanr(G["p_"+m],G.ppg_t)[0]:.3f}')
            print(grp,len(G)); print('  '+'\n  '.join(line))
