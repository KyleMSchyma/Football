"""pp_05_names.py: check every prospect the video names against our 2027 board: right name, on our board, mock range,
our pick slot (mixed model, site default league) and the video's bucket."""
import pandas as pd, numpy as np
F = '/home/user/Football/'
V = [('Jeremiah Smith', 'Jeremiah Smith', '1.01'), ('Charlie Becker', 'Charlie Becker', 'early 1st'), ('Nick Marsh', 'Nick Marsh', 'early 1st'),
     ('Jaden Ball', 'Jadan Baugh', 'early 1st'), ('Drew Mestemaker', 'Drew Mestemaker', 'early 1st'),
     ('Isaac Brown', 'Isaac Brown', 'mid 1st'), ('Trade Green', "Trey'Dez Green", 'mid 1st'), ('Jamari Johnson', 'Jamari Johnson', 'mid 1st'), ('Kanan Lacy', 'Kewan Lacy', 'mid 1st'),
     ('Ryan Williams', 'Ryan Williams', 'late 1st / 2nd'), ('KJ Duff', 'KJ Duff', 'late 1st / 2nd'), ('Cam Coleman', 'Cam Coleman', 'late 1st / 2nd'), ('Ryan Wingo', 'Ryan Wingo', 'late 1st / 2nd'),
     ('Bryant Wesco', 'Bryant Wesco', 'late 1st / 2nd'), ('Emmett Mosley', 'Emmett Mosley V', 'late 1st / 2nd'), ('Wyatt Young', 'Wyatt Young', 'late 1st / 2nd'),
     ('Amari Thomas', 'Amare Thomas', 'late 1st / 2nd'), ('Jackson Harris', 'Jackson Harris', 'late 1st / 2nd'), ('Amarian Miller', 'Omarion Miller', 'late 1st / 2nd'),
     ('Mario Craver', 'Mario Craver', 'late 1st / 2nd'), ('Nick Harbor', 'Nyck Harbor', 'late 1st / 2nd'), ('Deuce Robinson', 'Duce Robinson', 'late 1st / 2nd'),
     ('Deuce Alexander', 'Deuce Alexander', 'late 1st / 2nd'), ('Trinidad Chambliss', 'Trinidad Chambliss', 'deeper'), ('CJ Carr', 'CJ Carr', 'deeper'),
     ('Austin Simmons', 'Austin Simmons', 'deeper (may return)'), ('Dylan Riley', 'Dylan Riley', 'deeper'), ('Jamal Roberts', 'Jamal Roberts', 'deeper'),
     ('Hollywood Smothers', 'Daylan Smothers', 'deeper'), ('Arch Manning', 'Arch Manning', 'not ready / may return'), ('Ahmad Hardy', 'Ahmad Hardy', 'may not declare')]
norm = lambda s: pd.Series(s).str.lower().str.replace(r'[^a-z]', '', regex=True).str.replace(r'(jr|sr|ii|iii|iv|v)$', '', regex=True)
P = pd.read_csv('outputs/pp_prospects.csv').merge(pd.read_csv('outputs/pp_values.csv'), on='id')
m = P[(P.lens == 'mixed') & (P.cls == 2027)].sort_values('v_sf', ascending=False).reset_index(drop=True); m['slot'] = np.arange(1, len(m) + 1); m['k'] = norm(m.name).values
pre = P[(P.lens == 'pre') & (P.cls == 2027)].sort_values('v_sf', ascending=False).reset_index(drop=True); pre['slot'] = np.arange(1, len(pre) + 1); pre['k'] = norm(pre.name).values
mk = pd.read_csv(F + 'PostDraft_Model/pd_post_2027_mock_grades.csv'); mk['k'] = norm(mk.board_name).values
pg = pd.read_csv(F + 'PreDraft_Model/pd_player_grades.csv'); pg = pg[pg['class'] == 2027]; pg['k'] = norm(pg.name).values
dec = pd.read_csv(F + 'PreDraft_Model/pd_declare_2027.csv'); dec['k'] = norm(dec.name).values
lab = lambda s: f'{(s-1)//12+1}.{(s-1)%12+1:02d}' if s <= 48 else f'beyond 4.12 (#{s})'
rows = []
for said, ours, bucket in V:
    k = norm([ours])[0]; r = dict(video_name=said, our_name=ours, video_bucket=bucket)
    a = m[m.k == k]; b = mk[mk.k == k]; g = pg[pg.k == k]; d = dec[dec.k == k]
    r['on_our_board'] = 'yes' if len(a) else ('2027 pool only (not on 93-player board)' if len(d) else 'not found')
    if len(d): r.update(pos=d.position.iloc[0], college=d.college.iloc[0])
    if len(g): r.update(pos=g.position.iloc[0], college=g.college.iloc[0], pre_grade=g.grade.iloc[0])
    if len(b): r.update(mock_median_pick=int(b.pick.iloc[0]), mock_best_worst=f'{b.best_pick.iloc[0]:.0f}-{b.worst_pick.iloc[0]:.0f}', mixed_grade=b.post_grade.iloc[0], share_mocks=b.share_drafted.iloc[0])
    if len(a): r.update(our_slot=lab(int(a.slot.iloc[0])), value_sf=int(a.v_sf.iloc[0]), value_1qb=int(a.v_oneqb.iloc[0]))
    p = pre[pre.k == k]
    if len(p): r.update(pre_only_slot=lab(int(p.slot.iloc[0])))
    if len(d): r['p_declare_model'] = d.p_declare_refit.iloc[0]
    rows.append(r)
N = pd.DataFrame(rows); N.to_csv('outputs/video_names_check.csv', index=False)
pd.set_option('display.width', 260); print(N.to_string(index=False))
