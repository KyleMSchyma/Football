"""pp_03_pockets.py: pocket strength of the 2027 class vs 2010-2026 under five views, the realized check,
the declaration / draft-capital Monte Carlo, the position mix and the named-prospect check.
Inputs: outputs/pp_prospects.csv (pp_01), outputs/pp_values.csv (pp_02). Writes outputs/*.csv and charts/0*.png."""
import pandas as pd, numpy as np, json
from scipy import stats
import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
plt.rcParams.update({'figure.dpi': 130, 'axes.spines.top': False, 'axes.spines.right': False, 'font.size': 9.5})
P = pd.read_csv('outputs/pp_prospects.csv').merge(pd.read_csv('outputs/pp_values.csv'), on='id')
# sensitivity view: 2027 board without the prospects no mock drafts (they are priced on pre-draft odds x P(declare), no capital)
P = pd.concat([P, P[(P.lens == 'mixed') & ((P.cls < 2027) | (P.share_drafted > 0))].assign(lens='mixed_mocked')], ignore_index=True)
POCK = [('1.01', 1, 1), ('1.02-04', 2, 4), ('1.05-08', 5, 8), ('1.09-12', 9, 12), ('2.01-06', 13, 18), ('2.07-12', 19, 24), ('Round 3', 25, 36), ('Round 4', 37, 48)]
VIDEO = {'1.01': 'S-tier', '1.02-04': '5th of 13', '1.05-08': '7th of 13', '1.09-12': '3rd of 13', '2.01-06': '2nd of 13', '2.07-12': '1st of 13', 'Round 3': '~1st', 'Round 4': '~1st (early R4)'}
VIEWS = {'pre (no capital), SF': ('pre', 'v_sf'), 'post, SF': ('post', 'v_sf'), 'mixed (live), SF': ('mixed', 'v_sf'), 'mixed, SF, mocked prospects only': ('mixed_mocked', 'v_sf'),
         'mixed, 1QB': ('mixed', 'v_oneqb'), 'mixed, SF + TE prem 1.0': ('mixed', 'v_tep')}
COMP = list(range(2014, 2027))      # the 13 classes before 2027, like the video
def slots(d, vcol):
    d = d.sort_values(vcol, ascending=False).head(48).copy(); d['slot'] = np.arange(1, len(d) + 1); d['v'] = d[vcol]; return d
def pockets(d):
    o = {}
    for lab, lo, hi in POCK:
        q = d[d.slot.between(lo, hi)]
        o[lab] = dict(value=q.v.mean(), e_top=q.p1.sum(), e_any=q.p3.sum(), n=len(q),
                      act_top=(q.nfl_tier == 1).sum() if 'nfl_tier' in q else np.nan, act_any=(q.nfl_tier <= 3).sum() if 'nfl_tier' in q else np.nan,
                      pos='/'.join(f'{k}{v}' for k, v in q.pos.value_counts().items()))
    return o
rows, SL = [], {}
for vn, (lens, vcol) in VIEWS.items():
    for c, d in P[P.lens == lens].groupby('cls'):
        s = slots(d, vcol); SL[(vn, c)] = s
        for lab, m in pockets(s).items(): rows.append(dict(view=vn, cls=c, pocket=lab, **m))
T = pd.DataFrame(rows); T.to_csv('outputs/pocket_by_class.csv', index=False)
# 2027 rank among the 13 comparison classes, and percentile among 2010-2026
rk = []
for vn in VIEWS:
    for lab, *_ in POCK:
        t = T[(T.view == vn) & (T.pocket == lab)]; x27 = t[t.cls == 2027].iloc[0]
        h13 = t[t.cls.isin(COMP)]; h17 = t[t.cls <= 2026]
        rk.append(dict(view=vn, pocket=lab, value_2027=round(x27.value), hist_mean=round(h17.value.mean()), ratio=round(x27.value / h17.value.mean(), 2),
                       rank_of_14=int((h13.value > x27.value).sum() + 1), rank_of_18=int((h17.value > x27.value).sum() + 1),
                       e_any_2027=round(x27.e_any, 2), e_any_hist=round(h17.e_any.mean(), 2), e_top_2027=round(x27.e_top, 2), e_top_hist=round(h17.e_top.mean(), 2),
                       pos_2027=x27.pos, video=VIDEO[lab]))
R = pd.DataFrame(rk); R.to_csv('outputs/pocket_rank_2027.csv', index=False)
pd.set_option('display.width', 250); print(R.to_string(index=False))
# chart 01: heat map, mixed SF, value per pocket by class (colour = percentile within column, number = value in k)
def heat(vn, fn, title):
    t = T[T.view == vn].pivot(index='cls', columns='pocket', values='value')[[p[0] for p in POCK]]
    pct = t.rank(pct=True)
    fig, ax = plt.subplots(figsize=(9.5, 7.4))
    ax.imshow(pct.values, cmap='Blues', aspect='auto', vmin=0, vmax=1.15)
    for i, c in enumerate(t.index):
        for j, p in enumerate(t.columns):
            r = int(t[p].rank(ascending=False)[c]); ax.text(j, i, f'{t.loc[c, p]/1000:.1f}k\n#{r}', ha='center', va='center', fontsize=7.5,
                    color='white' if pct.loc[c, p] > .6 else '#18212d', fontweight='bold' if c == 2027 else 'normal')
    ax.set_xticks(range(len(t.columns))); ax.set_xticklabels(t.columns); ax.set_yticks(range(len(t.index))); ax.set_yticklabels(t.index)
    ax.add_patch(plt.Rectangle((-.5, len(t.index) - 1.5), len(t.columns), 1, fill=False, ec='#e07b00', lw=2.2))
    ax.set_title(title, loc='left', fontweight='bold'); ax.tick_params(length=0)
    for s in ax.spines.values(): s.set_visible(False)
    fig.text(.01, .01, 'Number = average value of the picks in that pocket (100k dynasty scale, site default league). #N = rank among 18 classes. Darker = stronger.', fontsize=7.5, color='#555')
    fig.tight_layout(rect=(0, .02, 1, 1)); fig.savefig(fn); plt.close()
heat('mixed (live), SF', 'charts/01_heatmap_mixed_sf.png', 'Pocket strength by class, mixed model (live), superflex')
heat('pre (no capital), SF', 'charts/02_heatmap_pre_sf.png', 'Pocket strength by class, pre-draft model only (no draft capital)')
heat('mixed, 1QB', 'charts/03_heatmap_mixed_1qb.png', 'Pocket strength by class, mixed model, 1QB')
# chart 04: 2027 ratio to history by pocket, all views
fig, ax = plt.subplots(figsize=(10.5, 4.6)); W = .135; cols = ['#9aa5b1', '#2a9d8f', '#1f4e79', '#6b8fb5', '#e07b00', '#9b5de5']
for k, (vn, c) in enumerate(zip(VIEWS, cols)):
    r = R[R.view == vn]; ax.bar(np.arange(8) + (k - 2.5) * W, r.ratio, W, color=c, label=vn)
ax.axhline(1, color='#18212d', lw=.8); ax.set_xticks(range(8)); ax.set_xticklabels([p[0] for p in POCK]); ax.set_ylabel('2027 value / 2010-26 average')
ax.set_title('2027 pocket value vs the average class (1.0 = average)', loc='left', fontweight='bold'); ax.legend(frameon=False, ncol=3, fontsize=8)
fig.tight_layout(); fig.savefig('charts/04_ratio_by_view.png'); plt.close()

# ---- realized check (2010-2021: 3+ seasons, LOCO): does ex-ante pocket strength predict realized hits? ----
V = 'mixed (live), SF'; H = T[(T.view == V) & (T.cls <= 2021)]
val = []
for lab, *_ in POCK:
    h = H[H.pocket == lab]
    rs = stats.spearmanr(h.e_any, h.act_any).statistic; rp = stats.pearsonr(h.e_any, h.act_any).statistic if h.act_any.std() > 0 else np.nan
    val.append(dict(pocket=lab, classes=len(h), e_any_mean=round(h.e_any.mean(), 2), act_any_mean=round(h.act_any.mean(), 2), e_top_mean=round(h.e_top.mean(), 2), act_top_mean=round(h.act_top.mean(), 2),
                    spearman_exante_vs_actual=round(rs, 2), pearson=round(rp, 2), actual_any_range=f'{int(h.act_any.min())}-{int(h.act_any.max())}'))
VAL = pd.DataFrame(val)
# whole-class version: picks 9-36 (the video's "depth") expected vs actual hits
dep = H[H.pocket.isin(['1.09-12', '2.01-06', '2.07-12', 'Round 3'])].groupby('cls')[['e_any', 'act_any', 'value']].sum()
r_dep = stats.spearmanr(dep.e_any, dep.act_any).statistic
VAL.loc[len(VAL)] = dict(pocket='1.09-3.12 combined', classes=len(dep), e_any_mean=round(dep.e_any.mean(), 2), act_any_mean=round(dep.act_any.mean(), 2), e_top_mean=np.nan, act_top_mean=np.nan,
                         spearman_exante_vs_actual=round(r_dep, 2), pearson=round(stats.pearsonr(dep.e_any, dep.act_any).statistic, 2), actual_any_range=f'{int(dep.act_any.min())}-{int(dep.act_any.max())}')
VAL.to_csv('outputs/realized_check.csv', index=False); print(VAL.to_string(index=False))
# bootstrap: SD of a pocket's hit count from luck alone (Poisson-binomial with the model's odds), vs spread across classes
luck = []
rng = np.random.default_rng(7)
for lab, *_ in POCK:
    sims = []
    for c in range(2010, 2022):
        s = SL[(V, c)]; q = s[s.slot.between(*[p[1:] for p in POCK if p[0] == lab][0])]
        sims.append((rng.random((4000, len(q))) < q.p3.values).sum(1))
    sims = np.array(sims); h = H[H.pocket == lab]
    luck.append(dict(pocket=lab, sd_luck_within_class=round(sims.std(1).mean(), 2), sd_expected_between_classes=round(h.e_any.std(), 2), sd_actual_between_classes=round(h.act_any.std(), 2)))
LK = pd.DataFrame(luck); LK.to_csv('outputs/luck_vs_signal.csv', index=False); print(LK.to_string(index=False))
fig, axs = plt.subplots(1, 2, figsize=(11, 4.4))
ax = axs[0]; ax.scatter(dep.e_any, dep.act_any, color='#1f4e79')
for c, r in dep.iterrows(): ax.annotate(str(c), (r.e_any, r.act_any), xytext=(4, 3), textcoords='offset points', fontsize=8)
lim = [min(dep.e_any.min(), dep.act_any.min()) - 1, max(dep.e_any.max(), dep.act_any.max()) + 1]; ax.plot(lim, lim, color='#9aa5b1', ls='--', lw=.8)
x27 = T[(T.view == V) & (T.cls == 2027) & T.pocket.isin(['1.09-12', '2.01-06', '2.07-12', 'Round 3'])].e_any.sum()
ax.axvline(x27, color='#e07b00', lw=1.5); ax.text(x27, lim[1] - .5, ' 2027 expected', color='#e07b00', fontsize=8)
ax.set_xlabel('Expected hits, picks 1.09-3.12 (model at draft time)'); ax.set_ylabel('Actual hits (any tier)'); ax.set_title(f'Depth: expected vs actual, 2010-21 (Spearman {r_dep:.2f})', loc='left', fontweight='bold')
ax = axs[1]; x = np.arange(len(LK)); ax.bar(x - .2, LK.sd_luck_within_class, .4, color='#c9d3df', label='Luck: SD of hits a class gets by chance')
ax.bar(x + .2, LK.sd_expected_between_classes, .4, color='#1f4e79', label='Signal: SD of expected hits between classes')
ax.set_xticks(x); ax.set_xticklabels(LK.pocket, rotation=30); ax.set_ylabel('Hits (SD)'); ax.legend(frameon=False, fontsize=8); ax.set_title('Luck swamps class-to-class differences', loc='left', fontweight='bold')
fig.tight_layout(); fig.savefig('charts/05_realized_check.png'); plt.close()

# ---- Monte Carlo for 2027: draft-capital range (best / median / worst mock pick) and declarations ----
m27 = P[(P.lens == 'mixed') & (P.cls == 2027)].copy()
m27['v_best'] = m27.v_best.fillna(m27.v_sf); m27['v_worst'] = m27.v_worst.fillna(m27.v_sf)
doubt = {'Arch Manning': .5, 'Ahmad Hardy': .5, 'Austin Simmons': .5}     # the video doubts these declare
hist = T[(T.view == V) & T.cls.isin(COMP)]
def run(p_declare=.85, n=4000, seed=11):
    rng = np.random.default_rng(seed); out = {p[0]: [] for p in POCK}
    vb, vm, vw = m27.v_best.values, m27.v_sf.values, m27.v_worst.values
    pdcl = np.array([doubt.get(nm, 1.0 if i == 0 else p_declare) for i, nm in enumerate(m27.name)])   # Smith always in
    order = np.argsort(-vm); vb, vm, vw, pdcl = vb[order], vm[order], vw[order], pdcl[order]
    for _ in range(n):
        u = rng.random(len(vm)); v = np.where(u < .25, vb, np.where(u < .75, vm, vw))
        v = v[rng.random(len(v)) < pdcl]; v = np.sort(v)[::-1][:48]
        for lab, lo, hi in POCK:
            pv = v[lo - 1:hi].mean(); out[lab].append(int((hist[hist.pocket == lab].value > pv).sum() + 1))
    return out
mc = []
for pdl, tag in ((1.0, 'capital range only, all declare'), (.85, 'worst case: 15% of prospects stay in school, nobody replaces them'), (.7, 'worst case: 30% stay in school, nobody replaces them')):
    o = run(pdl)
    for lab, *_ in POCK:
        a = np.array(o[lab]); mc.append(dict(scenario=tag, pocket=lab, median_rank_of_14=int(np.median(a)), p10=int(np.percentile(a, 10)), p90=int(np.percentile(a, 90)), share_top3=round((a <= 3).mean(), 2)))
MC = pd.DataFrame(mc); MC.to_csv('outputs/mc_2027_ranks.csv', index=False); print(MC.to_string(index=False))
fig, ax = plt.subplots(figsize=(10, 4.4))
for k, (tag, c) in enumerate(zip(MC.scenario.unique(), ['#1f4e79', '#2a9d8f', '#9aa5b1'])):
    q = MC[MC.scenario == tag]; x = np.arange(8) + (k - 1) * .22
    ax.errorbar(x, q.median_rank_of_14, yerr=[q.median_rank_of_14 - q.p10, q.p90 - q.median_rank_of_14], fmt='o', color=c, capsize=3, label=tag)
vr = {'1.01': 1, '1.02-04': 5, '1.05-08': 7, '1.09-12': 3, '2.01-06': 2, '2.07-12': 1, 'Round 3': 1, 'Round 4': 1}
ax.scatter(np.arange(8), [vr[p[0]] for p in POCK], marker='*', s=140, color='#e07b00', zorder=4, label="Video's rank")
ax.invert_yaxis(); ax.set_yticks([1, 3, 5, 7, 9, 11, 14]); ax.set_ylabel('2027 rank among 14 classes (1 = best)'); ax.set_xticks(range(8)); ax.set_xticklabels([p[0] for p in POCK])
ax.set_title('Where 2027 ranks, with draft-capital and declaration uncertainty (10th-90th percentile)', loc='left', fontweight='bold'); ax.legend(frameon=False, fontsize=8, ncol=2)
fig.tight_layout(); fig.savefig('charts/06_mc_rank.png'); plt.close()

# ---- position mix by pocket ----
pm = []
for c in range(2010, 2028):
    s = SL[(V, c)]
    for lab, lo, hi in POCK:
        q = s[s.slot.between(lo, hi)]
        for p in ['QB', 'RB', 'WR', 'TE']: pm.append(dict(cls=c, pocket=lab, pos=p, n=(q.pos == p).sum(), value=q[q.pos == p].v.sum()))
PM = pd.DataFrame(pm); PM.to_csv('outputs/position_mix.csv', index=False)
mix = PM.assign(grp=np.where(PM.cls == 2027, '2027', np.where(PM.cls == 2025, '2025', 'avg 2010-26 (excl 2025)'))).groupby(['grp', 'cls', 'pocket', 'pos']).n.sum().groupby(['grp', 'pocket', 'pos']).mean().unstack('pos')
mix = mix.reindex([(g, p[0]) for g in ['2027', '2025', 'avg 2010-26 (excl 2025)'] for p in POCK]).round(1); mix.to_csv('outputs/position_mix_summary.csv'); print(mix.to_string())
# WR / RB share of slots 9-36 by class
dz = PM[PM.pocket.isin(['1.09-12', '2.01-06', '2.07-12', 'Round 3'])].groupby(['cls', 'pos']).n.sum().unstack()
dz = dz.div(dz.sum(axis=1), axis=0); dz.to_csv('outputs/depth_position_share.csv')
fig, axs = plt.subplots(1, 2, figsize=(11.5, 4.4))
ax = axs[0]; bottom = np.zeros(len(dz)); cc = {'QB': '#1f4e79', 'RB': '#e07b00', 'WR': '#2a9d8f', 'TE': '#9b5de5'}
for p in ['WR', 'RB', 'QB', 'TE']:
    ax.bar(dz.index.astype(str), dz[p], bottom=bottom, color=cc[p], label=p); bottom += dz[p].values
ax.set_ylabel('Share of picks 1.09-3.12'); ax.tick_params(axis='x', rotation=60); ax.legend(frameon=False, ncol=4, fontsize=8, loc='upper left', bbox_to_anchor=(0, 1.12))
ax.set_title('Who fills the depth picks (1.09-3.12)', loc='left', fontweight='bold', pad=22)
ax = axs[1]; s27 = SL[(V, 2027)]; hm = pd.concat([SL[(V, c)] for c in range(2010, 2027)]).groupby(['slot', 'pos']).size().unstack().fillna(0) / 17
for p in ['WR', 'RB', 'QB', 'TE']:
    ax.plot(hm.index, hm[p].rolling(5, center=True, min_periods=1).mean(), color=cc[p], lw=1.5, label=f'{p} history (share at slot)')
    q = s27[s27.pos == p]; ax.scatter(q.slot, np.full(len(q), {'WR': 1.04, 'RB': 1.09, 'QB': 1.14, 'TE': 1.19}[p]), color=cc[p], s=18)
ax.set_xlabel('Pick (1-48)'); ax.set_ylabel('Share of classes with that position at the slot'); ax.set_ylim(0, 1.25)
ax.text(1, 1.21, 'dots = 2027 picks by position', fontsize=7.5, color='#555'); ax.set_title('Position by slot: 2027 dots vs history lines', loc='left', fontweight='bold'); ax.legend(frameon=False, fontsize=7, loc='center right')
fig.tight_layout(); fig.savefig('charts/07_position_mix.png'); plt.close()

# ---- 2027 slot list under each view ----
lst = []
for vn in VIEWS:
    s = SL[(vn, 2027)]
    for _, r in s.iterrows(): lst.append(dict(view=vn, slot=int(r.slot), sl=f'{(int(r.slot)-1)//12+1}.{(int(r.slot)-1)%12+1:02d}', name=r['name'], pos=r.pos, college=r.college, mock_pick=r.pick, value=int(r.v), p_top=round(r.p1, 3), p_any=round(r.p3, 3)))
pd.DataFrame(lst).to_csv('outputs/slots_2027_by_view.csv', index=False)
