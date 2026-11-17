import pandas as pd, numpy as np, statsmodels.formula.api as smf
h=pd.read_pickle('./h.pkl')
s=h[h.grp=='Fell out of A']; rng=np.random.default_rng(2); dd=(s.h3-s.p_any).values
print('actual-p_any', dd.mean(), np.percentile([rng.choice(dd,len(dd)).mean() for _ in range(4000)],[2.5,97.5]))
h['lp']=np.log(h.pick)
for f in ['h3 ~ C(position)*post_score','h3 ~ C(position)*post_score + pre_pctile','h3 ~ C(position)*post_score + C(position):pre_pctile']:
    m=smf.logit(f,h).fit(disp=0); print(f, round(m.llf,1), m.params.filter(like='pre').round(2).to_dict(), m.pvalues.filter(like='pre').round(4).to_dict())
m=smf.logit('h3 ~ C(position)*post_score + pre_pctile',h).fit(disp=0)
print('OR per 0.1 pctile', np.exp(0.1*m.params['pre_pctile']))
