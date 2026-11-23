import json,statistics as st,sys
import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt, matplotlib.dates as md
from datetime import date
d=json.load(open('dd_history_sample_weekly.json'))
names={'ceedeelambwr':'CeeDee Lamb (WR)','bijanrobinsonrb':'Bijan Robinson (RB)','jaydendanielsqb':'Jayden Daniels (QB)','brockbowerste':'Brock Bowers (TE)'}
fig,axs=plt.subplots(2,2,figsize=(12,7.5),sharex=True)
cols=[(1,'Dynasty Daddy (dynasty SF)','#1f4e9e',2),(3,'FantasyCalc SF (via DD)','#e07b00',1.2),(4,'DynastyProcess SF (via DD)','#2a9d55',1.2),(2,'Dynasty Daddy v2 (since Aug 26 2026)','#7b2cbf',1.5)]
with open('dd_history_sample_weekly.csv','w') as f:
  f.write('player,'+','.join(d['columns'])+'\n')
  for k,v in d['players'].items():
    for r in v: f.write(k+','+','.join('' if x is None else str(x) for x in r)+'\n')
print('week-to-week median |% change|, Aug 2024 - Nov 2026')
for ax,(k,v) in zip(axs.flat,d['players'].items()):
  x=[date.fromisoformat(r[0]) for r in v]
  for i,lab,c,lw in cols:
    pts=[(a,r[i]) for a,r in zip(x,v) if r[i]]
    ax.plot([p[0] for p in pts],[p[1] for p in pts],label=lab,color=c,lw=lw)
  ax.set_title(names[k]); ax.grid(alpha=.3); ax.xaxis.set_major_formatter(md.DateFormatter('%b %y'))
  out=[]
  for i,lab,_,_ in cols[:3]:
    s=[r[i] for r in v if r[i]]
    ch=[abs(b/a-1)*100 for a,b in zip(s,s[1:])]
    out.append(f'{lab.split(" (")[0]} {st.median(ch):.1f}%')
  print(names[k],'|',' | '.join(out))
axs[0,0].legend(fontsize=8,loc='lower left')
fig.suptitle('Dynasty Daddy value history, every Tuesday since Aug 2024 (superflex; KeepTradeCut fields excluded)')
fig.text(0.01,0.01,'Source: api.dynasty-daddy.com /api/v1/player/{id}?isAllTime=true, pulled 2026-11-22. DD values top out at about 10,200.',fontsize=8)
plt.tight_layout(rect=(0,0.03,1,0.96)); plt.savefig('dd_history_sample_chart.png',dpi=130)
