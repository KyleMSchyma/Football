import pandas as pd
T=pd.read_csv('slot_groups.csv'); TD=pd.read_csv('trade_down.csv',dtype={'keep':str}); PC=pd.read_csv('per_class_101.csv'); PO=pd.read_csv('by_position.csv').rename(columns={'round':'rnd'}); R=pd.read_csv('robust_nfl_order.csv')
k=lambda v: f'{v/1000:.1f}k'; pc=lambda v: f'{v:.0%}'
rows=''.join(f"<tr><td>{r.group}</td><td>{k(r.price)}</td><td>{k(r.produced)}</td><td>{k(r.median_produced)}</td><td><b>{r.ratio:.2f}</b> <span class=ci>({r.ratio_lo:.2f}–{r.ratio_hi:.2f})</span></td><td>{r.asset_ratio:.2f} <span class=ci>({r.asset_lo:.2f}–{r.asset_hi:.2f})</span></td><td>{pc(r.hit_top)}</td><td>{pc(r.hit_any)}</td><td>{pc(r.bust_rate)}</td></tr>" for r in T.itertuples())
td=''
for sc in TD.scenario.unique():
    z=TD[TD.scenario==sc]; g=lambda kk,l: z[(z.keep==kk)&(z.lens==l)].p_top_wins.iloc[0]
    td+=f"<tr><td>{sc}</td>"+''.join(f"<td>{pc(g(kk,'production 5 seasons'))} / {pc(g(kk,'trade value after season 3'))}</td>" for kk in ['1.01','1.02','1.03'])+"</tr>"
pcr=''.join(f"<tr><td>{r.cls}</td><td>{r.pick_101}</td><td>{k(r.produced_101)}</td><td>{k(r.avg_two_1sts)}</td><td class={'win' if r.produced_101>r.avg_two_1sts else 'loss'}>{'1.01' if r.produced_101>r.avg_two_1sts else 'Two 1sts'}</td><td>{r.best_later_1st} ({k(r.best_later_prod)})</td></tr>" for r in PC.itertuples())
por=''.join(f"<tr><td>Round {r.rnd}</td><td>{r.pos}</td><td>{r.n}</td><td>{k(r.price)}</td><td>{k(r.produced)}</td><td><b>{r.ratio:.2f}</b> <span class=ci>({r.lo:.2f}–{r.hi:.2f})</span></td><td>{r.ratio_flex:.2f}</td><td>{pc(r.hit_top)}</td><td>{pc(r.hit_any)}</td></tr>" for r in PO.itertuples())
rob=''.join(f"<tr><td>{r.grp2}</td><td>{k(r.price)}</td><td>{k(r.produced)}</td><td>{r.ratio:.2f}</td><td>{pc(r.hit_top)}</td><td>{pc(r.hit_any)}</td></tr>" for r in R.itertuples())
open('tables.html','w').write(f'<!--slot-->{rows}\n<!--td-->{td}\n<!--pc-->{pcr}\n<!--po-->{por}\n<!--rob-->{rob}')
print(sum(PC.produced_101>PC.avg_two_1sts))
