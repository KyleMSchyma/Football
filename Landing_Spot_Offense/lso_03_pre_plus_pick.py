"""
Landing-spot offense study, step 3: with the PRE-draft grade, QBs show a strong negative team-offense
effect. Is that the offense, or just draft capital (good offenses pick QBs later)? Hold pre-draft
score AND log(pick) fixed and re-estimate the team-offense effect. Writes lso_pre_plus_pick.csv.
"""
import os
import numpy as np
import pandas as pd
import statsmodels.formula.api as smf

HERE = os.path.dirname(os.path.abspath(__file__))
p = pd.read_csv(os.path.join(HERE, "lso_players.csv"))
p = p[p.pre_score.notna()].copy()
p["log_pick"] = np.log(p["pick"])
rows = []
for outc, d0 in [("rookie_ppg", p[p.rookie_complete]), ("y13_ppg", p[p.y13_complete])]:
    for pos in ["QB", "RB", "WR", "TE"]:
        d = d0[d0.position == pos]
        for label, f in [("pre score", "pre_score + I(pre_score**2)"),
                         ("pre score + log(pick)", "pre_score + I(pre_score**2) + log_pick")]:
            m = smf.ols(f"{outc} ~ {f} + prev_ppg_z", data=d).fit(cov_type="HC1")
            ci = m.conf_int().loc["prev_ppg_z"]
            rows.append(dict(outcome=outc, position=pos, held_fixed=label, n=len(d),
                             off_coef=m.params["prev_ppg_z"], lo=ci[0], hi=ci[1], p=m.pvalues["prev_ppg_z"]))
out = pd.DataFrame(rows).round(3)
out.to_csv(os.path.join(HERE, "lso_pre_plus_pick.csv"), index=False)
print(out.to_string(index=False))
