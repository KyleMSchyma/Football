"""pp_01_build.py: one table of every rookie prospect 2010-2027 under three model lenses (pre, post, mixed).
History (2010-2026): drafted players; 2027: the 93-player pre-draft board (Kyle's 4 mocks, median pick).
  pre   = pre-draft model, drafted-recalibrated odds (PreDraft_Model/pd_player_probs_drafted.csv, p_*_d). No draft capital.
  post  = plain post-draft model at the actual NFL pick (history) / mock median pick weighted by share drafted (2027): p_*_draft
  mixed = live mixed model (post-draft + pre-draft faller boost), same capital: p_* (history) / p_*_value (2027)
Ages from Trade_Values/dv_rookie_board_values.csv (22.0 when missing). Writes outputs/pp_prospects.csv for pp_02 (node values)."""
import pandas as pd, numpy as np
F = '/home/user/Football/'
pre = pd.read_csv(F + 'PreDraft_Model/pd_player_probs_drafted.csv')
post = pd.read_csv(F + 'PostDraft_Model/pd_post_player_grades.csv')
mk = pd.read_csv(F + 'PostDraft_Model/pd_post_2027_mock_grades.csv')
bv = pd.read_csv(F + 'Trade_Values/dv_rookie_board_values.csv')
norm = lambda s: s.str.lower().str.replace(r'[^a-z]', '', regex=True).str.replace(r'(jr|sr|ii|iii|iv|v)$', '', regex=True)
age = bv[bv.board.isin(['post', 'pre'])].assign(k=lambda d: norm(d.name)).groupby(['class', 'position', 'k']).age.first()
rows = []
for _, r in pre.iterrows():
    rows.append(dict(cls=r['class'], pos=r.position, name=r['name'], college=r.college, pick=r.pick, lens='pre', p1=r.p_top_d, p2=r.p_top2_d, p3=r.p_any_d))
for _, r in post[post['class'] <= 2026].iterrows():
    for lens, c in (('post', '_draft'), ('mixed', '')):
        rows.append(dict(cls=r['class'], pos=r.position, name=r['name'], college=r.college, pick=r.pick, lens=lens, p1=r['p_top' + c], p2=r['p_top2' + c], p3=r['p_any' + c],
                         nfl_tier=r.nfl_tier, complete=r.outcome_complete, src=r.score_source))
for _, r in mk.iterrows():
    for lens, c in (('post', '_value_draft'), ('mixed', '_value')):
        rows.append(dict(cls=2027, pos=r.position, name=r.board_name, college=r.board_school, pick=r.pick, lens=lens, p1=r['p_top' + c], p2=r['p_top2' + c], p3=r['p_any' + c],
                         share_drafted=r.share_drafted, best_pick=r.best_pick, worst_pick=r.worst_pick,
                         b1=r.best_p_top, b2=r.best_p_top2, b3=r.best_p_any, w1=r.worst_p_top, w2=r.worst_p_top2, w3=r.worst_p_any) if lens == 'mixed' else
                    dict(cls=2027, pos=r.position, name=r.board_name, college=r.board_school, pick=r.pick, lens=lens, p1=r['p_top' + c], p2=r['p_top2' + c], p3=r['p_any' + c]))
# 2027 board prospects missing from every mock: the site prices them with the pre-draft odds x P(declare) (dv_13);
# add them to the post and mixed lenses the same way. The pre lens weights mocked players by the share of mocks that
# draft them and unmocked players by P(declare), so every lens holds the same ~80 expected draftees as a real class.
dec = pd.read_csv(F + 'PreDraft_Model/pd_declare_2027.csv')
decm = pd.Series(dec.p_declare_refit.values, index=dec.position + '|' + norm(dec.name)).groupby(level=0).first()
mkk = set(mk.position + '|' + norm(mk.board_name)); shm = pd.Series(mk.share_drafted.values, index=mk.position + '|' + norm(mk.board_name))
for r in [r for r in rows if r['cls'] == 2027 and r['lens'] == 'pre']:
    key = r['pos'] + '|' + norm(pd.Series([r['name']]))[0]
    if key in mkk: w = float(shm[key])
    else:
        w = float(decm.get(key, 0.3)); r2 = dict(r); r2.update(p1=r['p1'] * w, p2=r['p2'] * w, p3=r['p3'] * w, share_drafted=0)
        rows.extend([dict(r2, lens='post'), dict(r2, lens='mixed')])
    r.update(p1=r['p1'] * w, p2=r['p2'] * w, p3=r['p3'] * w, w_pre=w)
D = pd.DataFrame(rows)
D['age'] = [age.get((c, p, k), np.nan) for c, p, k in zip(D.cls, D.pos, norm(D.name))]
D['age'] = D.age.fillna(22.0)
D['id'] = np.arange(len(D))
D.to_csv('outputs/pp_prospects.csv', index=False)
print(D.groupby(['lens', 'cls']).size().unstack(0).T.to_string()); print('age missing filled:', (D.age == 22.0).mean().round(3))
