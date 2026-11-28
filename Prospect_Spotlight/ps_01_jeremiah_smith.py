"""
Prospect Spotlight: the #1 2027 prospect (Jeremiah Smith, WR, Ohio State).

Builds the facts table and the 1920x1080 video scenes from the repo's own model outputs.
Nothing is typed in by hand except text labels; every number is read from a file below.

Inputs (all in this repo unless noted)
  PreDraft_Model/pd_player_grades.csv, pd_player_deep_dive.csv, pd_player_probs_drafted.csv,
  pd_WR_shap_prospects.csv, pd_pool.rds, pd_pool_asis.rds, pd_proj_ppg.csv
  PostDraft_Model/pd_post_2027_mock_grades.csv, pd_post_2027_mock_proj_ppg.csv, pd_post_player_grades.csv,
  pd_post_grade_vs_pick.csv
  Mock_Drafts/range/mock_2027_range_players.csv (Kyle's own mocks)
  Trade_Values/dv_rookie_board_values.csv
  Rookie class value research (project files research/rookie_class_value/top24_by_class_players.csv),
  copied to outputs/top24_by_class_players.csv
  CFBD season stats 2004-2025 (PC cache cfbd_stats_2004_2025.rds, via cfbfastR): Smith's rows saved to
  outputs/smith_college_seasons.csv
  Site value (default site league) from the weekly X tools facts.json (2026-11-25 run), saved in outputs/

Run: python3 ps_01_jeremiah_smith.py  (needs pandas, matplotlib, pyreadr)
"""
import json, os, sys
import pandas as pd, numpy as np, pyreadr
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager as fm

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(HERE, "outputs"); os.makedirs(OUT, exist_ok=True)
FR = os.environ.get("FRAMES", os.path.join(OUT, "frames")); os.makedirs(FR, exist_ok=True)
NAME, AID = "Jeremiah Smith", "5079720"

for f in fm.findSystemFonts():
    if "Inter" in f: fm.fontManager.addfont(f)
plt.rcParams.update({"font.family": "Inter", "font.size": 22, "text.color": "#eef2f8",
                     "axes.labelcolor": "#93a3bd", "xtick.color": "#93a3bd", "ytick.color": "#93a3bd",
                     "axes.edgecolor": "#2a3b5c", "figure.facecolor": "#0d1525", "axes.facecolor": "#0d1525"})
BG, INK, MUTED, OR, BLUE, GRN, RED, GRID, PANEL = ("#0d1525", "#eef2f8", "#93a3bd", "#f28c28", "#66aef5",
                                                    "#47cf98", "#f07373", "#1f2c45", "#121c30")
pdr = lambda *p: os.path.join(ROOT, *p)

# ----------------------------------------------------------------------------- facts
g = pd.read_csv(pdr("PreDraft_Model", "pd_player_grades.csv"))
pre = g[(g.name == NAME) & (g["class"] == 2027)].iloc[0]
wr27 = g[(g.position == "WR") & (g["class"] == 2027)].sort_values("score", ascending=False)
wr_hist = g[(g.position == "WR") & (g["class"] <= 2026)].sort_values("score", ascending=False)
dd = pd.read_csv(pdr("PreDraft_Model", "pd_player_deep_dive.csv")).query("name == @NAME").iloc[0]
drc = pd.read_csv(pdr("PreDraft_Model", "pd_player_probs_drafted.csv")).query("name == @NAME").iloc[0]
shap = pd.read_csv(pdr("PreDraft_Model", "pd_WR_shap_prospects.csv"), dtype={"athlete_id": str})
shap_s = shap[(shap.athlete_id == AID) & (shap["class"] == 2027)].sort_values("shap", ascending=False)
post = pd.read_csv(pdr("PostDraft_Model", "pd_post_2027_mock_grades.csv")).query("name == @NAME").iloc[0]
ppg_pre = pd.read_csv(pdr("PreDraft_Model", "pd_proj_ppg.csv")).query("name == @NAME").iloc[0].proj_ppg3
ppg_post = pd.read_csv(pdr("PostDraft_Model", "pd_post_2027_mock_proj_ppg.csv")).query("name == @NAME").iloc[0]
mocks = pd.read_csv(pdr("Mock_Drafts", "range", "mock_2027_range_players.csv")).query("player == @NAME").iloc[0]
dv = pd.read_csv(pdr("Trade_Values", "dv_rookie_board_values.csv")).query("name == @NAME and board == 'mock'").iloc[0]
pg = pd.read_csv(pdr("PostDraft_Model", "pd_post_player_grades.csv"))
vp = pd.read_csv(pdr("PostDraft_Model", "pd_post_grade_vs_pick.csv")).query("position == 'WR'")
site = json.load(open(os.path.join(OUT, "site_facts_2026-11-25.json")))
site_r1 = [r for r in site["rookies"]["top24"] if r["n"] == NAME][0]
cls = pd.read_csv(os.path.join(OUT, "top24_by_class_players.csv"))

pool = list(pyreadr.read_r(pdr("PreDraft_Model", "pd_pool.rds")).values())[0]
asis = list(pyreadr.read_r(pdr("PreDraft_Model", "pd_pool_asis.rds")).values())[0]
me = pool[pool.athlete_id.astype(str) == AID].iloc[0]; me_asis = asis[asis.athlete_id.astype(str) == AID].iloc[0]
seasons = pd.read_csv(os.path.join(OUT, "smith_college_seasons.csv"))
games26 = round(12 * me_asis.p_rec / me.p_rec)

hist_wr = pool[(pool.position == "WR") & (pool.eligible == True) & (pool["class"] <= 2023)].copy()
top_picks = pg[(pg.position == "WR") & (pg.outcome_complete == True)].copy()
def band(lo, hi):
    s = top_picks[(top_picks.pick >= lo) & (top_picks.pick <= hi)]
    return dict(n=len(s), pred_wr12=s.p_top.mean(), real_wr12=(s.nfl_tier == 1).mean(),
                pred_wr24=s.p_top2.mean(), real_wr24=(s.nfl_tier <= 2).mean(),
                pred_wr36=s.p_any.mean(), real_wr36=(s.nfl_tier <= 3).mean())
bands = {"Picks 1-5": band(1, 5), "Picks 1-10": band(1, 10), "Picks 11-32": band(11, 32)}

facts = dict(
    name=NAME, school="Ohio State", position="WR", recruit_stars=int(pre.recruit_stars), yrs_out_of_hs=int(pre.yrs_out_of_hs),
    pre_score=pre.score, pre_grade=pre.grade, pre_pctile=pre.pctile, pre_score_asis=pre.score_asis, pre_grade_asis=pre.grade_asis,
    pre_p_wr12=pre.p_top, pre_p_wr24=pre.p_top2, pre_p_wr36=pre.p_any,
    pre_drafted_p_wr12=drc.p_top_d, pre_drafted_p_wr24=drc.p_top2_d, pre_drafted_p_wr36=drc.p_any_d,
    p_declare_flag=pre.p_declare, class_wr2_name=wr27.iloc[1]["name"], class_wr2_score=wr27.iloc[1].score,
    hist_best_wr_name=wr_hist.iloc[0]["name"], hist_best_wr_class=int(wr_hist.iloc[0]["class"]), hist_best_wr_score=wr_hist.iloc[0].score,
    comps=dd.comps, shap=dict(zip(shap_s.variable, shap_s.shap.round(2))),
    primary_2026_scaled=dict(rec=me.p_rec, yds=me.p_rec_yds, td=round(me.p_rec_td, 1), rec_share=round(me.p_rec_share, 3), dominator=round(me.p_dominator, 3)),
    primary_2026_asis=dict(rec=me_asis.p_rec, yds=me_asis.p_rec_yds, td=me_asis.p_rec_td, games_est=games26),
    hist_wr_1600_plus=int((hist_wr.p_rec_yds >= 1600).sum()), hist_wr_pool=len(hist_wr),
    mocks_picks=mocks.picks_in_mocks if "picks_in_mocks" in mocks else None,
    mock_picks=[int(mocks[c]) for c in mocks.index if c.startswith("pick_2027_mock")], median_pick=int(post.pick), team=post.team,
    post_grade=post.post_grade, post_p_wr12=post.p_top, post_p_wr24=post.p_top2, post_p_wr36=post.p_any,
    best_pick=int(post.best_pick), best_p_wr12=post.best_p_top, age_est=post.age_est,
    proj_ppg_pre=ppg_pre, proj_ppg_post=ppg_post.proj_ppg3_post, proj_ppg_mixed=ppg_post.proj_ppg3_mixed,
    value_lg_default=int(dv.value_100k), value_site_default=site_r1["v"], ovr_site_default=site_r1["ovr"], rookie_rank=site_r1["r"],
    site_league=site["league_label"], site_asof=site["status"]["asof"],
    wr_post_grade_vs_pick_LRT_p_wr12=float(vp.query("target == 'WR12'").LRT_p.iloc[0]),
    history_top_pick_wrs=bands)
json.dump(facts, open(os.path.join(OUT, "smith_facts.json"), "w"), indent=1, default=float)

# ----------------------------------------------------------------------------- scene helpers
def fig(title, kicker, sub=None):
    f = plt.figure(figsize=(19.2, 10.8), dpi=100)
    f.text(0.055, 0.915, kicker.upper(), color=OR, fontsize=22, weight="bold")
    f.text(0.055, 0.845, title, color=INK, fontsize=46, weight="heavy", family="Inter Display")
    if sub: f.text(0.055, 0.795, sub, color=MUTED, fontsize=24)
    f.text(0.055, 0.035, "PROSPECT ACTUARY  ·  kylemschyma.github.io/prospect-actuary", color=MUTED, fontsize=16, weight="bold")
    f.text(0.945, 0.035, "Data: CollegeFootballData.com (cfbfastR), nflverse, Pro Football Reference", color="#5d6b84", fontsize=15, ha="right")
    return f
def style(ax, grid="x"):
    for s in ["top", "right", "left"]: ax.spines[s].set_visible(False)
    ax.spines["bottom"].set_color("#2a3b5c")
    ax.grid(axis=grid, color=GRID, lw=1); ax.set_axisbelow(True); ax.tick_params(length=0, labelsize=19)
def save(f, n): f.savefig(os.path.join(FR, f"scene_{n:02d}.png"), facecolor=BG); plt.close(f)
pct = lambda x: f"{x*100:.0f}%"

# 01 title -------------------------------------------------------------------
f = plt.figure(figsize=(19.2, 10.8), dpi=100)
f.text(0.055, 0.80, "2027 PROSPECT SPOTLIGHT  ·  THE MODEL'S #1", color=OR, fontsize=26, weight="bold")
f.text(0.055, 0.62, NAME, color=INK, fontsize=110, weight="heavy", family="Inter Display")
f.text(0.057, 0.53, f"WR  ·  Ohio State  ·  {facts['recruit_stars']}-star recruit  ·  true junior", color=MUTED, fontsize=34)
tiles = [(facts["pre_grade"], "pre-draft grade", f"#1 of {len(wr27)} 2027 WRs"),
         (f"{facts['value_site_default']:,}", "dynasty value", f"#{facts['rookie_rank']} rookie · #{facts['ovr_site_default']} overall"),
         (pct(facts["post_p_wr12"]), "P(top-12 WR year)", f"NFL yrs 1-3, mock pick {facts['median_pick']}"),
         (f"{facts['proj_ppg_mixed']:.1f}", "projected PPR PPG", "NFL years 1-3")]
for i, (big, lab, sm) in enumerate(tiles):
    x = 0.055 + i * 0.228
    f.patches.append(plt.Rectangle((x, 0.13), 0.21, 0.30, transform=f.transFigure, fc=PANEL, ec="#1f2c45", lw=2))
    f.text(x + 0.018, 0.30, big, color=GRN if i == 0 else INK, fontsize=64, weight="heavy", family="Inter Display")
    f.text(x + 0.018, 0.225, lab.upper(), color=OR, fontsize=19, weight="bold")
    f.text(x + 0.018, 0.17, sm, color=MUTED, fontsize=20)
f.text(0.055, 0.035, "PROSPECT ACTUARY  ·  kylemschyma.github.io/prospect-actuary", color=MUTED, fontsize=16, weight="bold")
f.text(0.945, 0.035, f"Values: {facts['site_league']}", color="#5d6b84", fontsize=15, ha="right")
save(f, 1)

# 02 production --------------------------------------------------------------
f = fig("Three years, three 900+ yard seasons", "College production",
        f"Regular-season receiving yards (CFBD). 2026 is through about {games26} games.")
ax = f.add_axes([0.08, 0.14, 0.86, 0.6]); style(ax, "y")
yrs = ["2024\nfreshman", "2025\nsophomore", "2026\njunior (so far)"]
ys = [seasons.query("year==2024").receiving_yds.iloc[0], seasons.query("year==2025").receiving_yds.iloc[0], me_asis.p_rec_yds]
x = np.arange(3)
ax.bar(x, ys, width=0.5, color=[BLUE, BLUE, OR], zorder=3)
ax.bar(2, me.p_rec_yds - me_asis.p_rec_yds, bottom=me_asis.p_rec_yds, width=0.5, fc="none", ec=OR, ls="--", lw=2.5, zorder=3)
recs = [seasons.query("year==2024").receiving_rec.iloc[0], seasons.query("year==2025").receiving_rec.iloc[0], me_asis.p_rec]
tds = [seasons.query("year==2024").receiving_td.iloc[0], seasons.query("year==2025").receiving_td.iloc[0], me_asis.p_rec_td]
for i in range(3):
    ax.text(i, ys[i] - 60, f"{ys[i]:,.0f}", ha="center", va="top", fontsize=34, weight="heavy", color=BG)
    ax.text(i, ys[i] / 2 - 40, f"{recs[i]:.0f} rec\n{tds[i]:.0f} TD", ha="center", va="center", fontsize=21, color=BG, weight="bold")
ax.text(2.3, me.p_rec_yds, f"{me.p_rec_yds:,.0f} pace over 12 games\n(what the model uses)", va="center", fontsize=21, color=OR)
ax.set_xticks(x, yrs, fontsize=22, color=INK); ax.set_ylim(0, 1800); ax.set_xlim(-0.5, 3.2)
ax.yaxis.set_major_formatter(matplotlib.ticker.FuncFormatter(lambda v, _: f"{v:,.0f}"))
save(f, 2)

# 03 class gap ---------------------------------------------------------------
f = fig("Nobody in the 2027 class is close", "Pre-draft model score, 2027 WRs",
        "Score = P(WR12) + P(WR24) + P(WR36) in NFL years 1-3, college data only")
ax = f.add_axes([0.25, 0.12, 0.69, 0.64]); style(ax)
t = wr27.head(12).iloc[::-1]
ax.barh(range(len(t)), t.score, height=0.68, color=[OR if n == NAME else "#3a6fa5" for n in t.name], zorder=3)
ax.set_yticks(range(len(t)), [f"{n}  ({c})" for n, c in zip(t.name, t.college)], fontsize=19, color=INK)
for i, (s, gr) in enumerate(zip(t.score, t.grade)): ax.text(s + 0.03, i, f"{s:.2f}  {gr}", va="center", fontsize=19, color=INK)
ax.set_xlim(0, 2.95)
ax.annotate(f"{facts['pre_score']/facts['class_wr2_score']:.1f}x the next WR", xy=(facts["pre_score"], len(t) - 1), xytext=(1.75, len(t) - 4.3),
            color=OR, fontsize=26, weight="bold", arrowprops=dict(arrowstyle="->", color=OR, lw=2))
save(f, 3)

# 04 all-time ----------------------------------------------------------------
f = fig("The highest pre-draft WR score we have", "Every WR class, 2010-2027",
        "Top 14 pre-draft scores and what happened (best finish in NFL years 1-3)")
ax = f.add_axes([0.25, 0.12, 0.69, 0.64]); style(ax)
allw = g[(g.position == "WR")].sort_values("score", ascending=False).head(14).iloc[::-1]
def outc(r):
    if r["class"] == 2027: return "not drafted yet"
    if r["class"] == 2026: return "rookie, in progress"
    if pd.isna(r.nfl_best_finish) or r.nfl_best_finish >= 100: return "no top-100 season"
    s = f"best WR{int(r.nfl_best_finish)}"
    return s + ("" if r.outcome_complete else " (so far)")
cols = []
for _, r in allw.iterrows():
    if r["name"] == NAME: cols.append(OR)
    elif r["class"] >= 2026: cols.append("#3a4a66")
    elif r.nfl_tier == 1: cols.append(GRN)
    elif r.nfl_tier in (2, 3): cols.append(BLUE)
    else: cols.append(RED)
ax.barh(range(len(allw)), allw.score, height=0.68, color=cols, zorder=3)
ax.set_yticks(range(len(allw)), [f"{n} ({c})" for n, c in zip(allw.name, allw["class"])], fontsize=18, color=INK)
for i, (_, r) in enumerate(allw.iterrows()): ax.text(r.score + 0.03, i, f"{r.score:.2f}  ·  {outc(r)}", va="center", fontsize=17, color=INK)
ax.set_xlim(0, 3.6)
for k, (c, l) in enumerate([(GRN, "WR12 season"), (BLUE, "WR24/36 season"), (RED, "no tier season")]):
    ax.add_patch(plt.Rectangle((2.45 + k * 0.0, 1.0 + k * 0.9), 0.08, 0.5, color=c, transform=ax.transData, clip_on=False))
    ax.text(2.58, 1.25 + k * 0.9, l, va="center", fontsize=17, color=MUTED)
save(f, 4)

# 05 SHAP --------------------------------------------------------------------
lab = {"p_rec_yds": f"Receiving yards ({me.p_rec_yds:,.0f} pace)", "recruit_rating": "Recruit rating (5-star, 0.9997)",
       "yrs_since_hs": "Years out of high school (3)", "p_dominator": f"Dominator rating ({me.p_dominator:.0%})",
       "power5": "Power 5 program"}
s5 = shap_s[shap_s.shap != 0].head(5)
f = fig("Why the model loves him", "What drives the grade (SHAP, pre-draft WR model)",
        "Each bar = how much that input raises his log-odds of a WR36 season vs an average prospect")
ax = f.add_axes([0.33, 0.2, 0.6, 0.55]); style(ax)
s5r = s5.iloc[::-1]
ax.barh(range(len(s5r)), s5r.shap, height=0.62, color=OR, zorder=3)
ax.set_yticks(range(len(s5r)), [lab.get(v, v) for v in s5r.variable], fontsize=21, color=INK)
for i, v in enumerate(s5r.shap): ax.text(v + 0.05, i, f"+{v:.2f}", va="center", fontsize=22, weight="bold", color=INK)
ax.set_xlim(0, 4.2); ax.set_xlabel("SHAP value (log-odds)", fontsize=19)
f.text(0.33, 0.075, "No combine data in the pre-draft model. Age and draft-pick inputs come later, in the post-draft model.", color=MUTED, fontsize=18)
save(f, 5)

# 06 off the chart -----------------------------------------------------------
f = fig("Rare air, even among true juniors", "Every eligible WR prospect, 2010-2023",
        f"Final-season receiving yards vs years out of high school. Only {facts['hist_wr_1600_plus']} of {facts['hist_wr_pool']:,} topped 1,600.")
ax = f.add_axes([0.08, 0.13, 0.55, 0.62]); style(ax, "both")
h = hist_wr[hist_wr.p_rec_yds > 300]
rng = np.random.default_rng(7); jit = rng.uniform(-0.18, 0.18, len(h))
miss = h.tier.isna() | (h.tier == 4)
ax.scatter(h.yrs_since_hs[miss] + jit[miss.values], h.p_rec_yds[miss], s=14, color="#3a4a66", alpha=0.6, lw=0, label="no WR36 season")
ax.scatter(h.yrs_since_hs[~miss] + jit[~miss.values], h.p_rec_yds[~miss], s=60, color=GRN, ec=BG, lw=1.5, label="had a WR36 season", zorder=3)
ax.scatter([3], [me.p_rec_yds], s=900, marker="*", color=OR, ec=BG, lw=2, zorder=5)
ax.text(3.15, me.p_rec_yds + 40, NAME, color=OR, fontsize=24, weight="bold")
ax.set_xlim(2.4, 6.6); ax.set_ylim(250, 1850); ax.set_xticks([3, 4, 5, 6], ["3", "4", "5", "6"]); ax.set_xlabel("Years out of high school", fontsize=20)
ax.yaxis.set_major_formatter(matplotlib.ticker.FuncFormatter(lambda v, _: f"{v:,.0f}"))
lg = ax.legend(loc="lower right", fontsize=17, frameon=False, labelcolor=MUTED)
club = hist_wr[(hist_wr.yrs_since_hs <= 3) & (hist_wr.p_rec_yds >= 1450) & hist_wr.recruit_stars.notna()].sort_values("p_rec_yds", ascending=False)
f.text(0.68, 0.70, "TRUE JUNIORS WITH 1,450+ YARDS", color=OR, fontsize=19, weight="bold")
for i, (_, r) in enumerate(club.iterrows()):
    res = "no tier season" if (pd.isna(r.tier) or r.tier == 4) else f"best WR{int(r.best)}"
    f.text(0.68, 0.645 - i * 0.075, f"{r['name']} ({int(r['class'])})", color=INK, fontsize=21, weight="bold")
    f.text(0.68, 0.615 - i * 0.075, f"{r.p_rec_yds:,.0f} yds  ·  {res}", color=MUTED, fontsize=18)
f.text(0.68, 0.645 - len(club) * 0.075 - 0.01, f"None was a 5-star recruit.\nSmith: {me.p_rec_yds:,.0f} pace, 5-star.", color=OR, fontsize=20, weight="bold", va="top")
save(f, 6)

# 07 draft capital -----------------------------------------------------------
f = fig("Add draft capital and the odds jump", "Tier odds, NFL years 1-3",
        f"Kyle's own 2027 mocks: picks {', '.join(map(str, facts['mock_picks']))}  ->  median pick {facts['median_pick']} ({post.team})")
ax = f.add_axes([0.08, 0.14, 0.86, 0.58]); style(ax, "y")
groups = ["WR12 season", "WR24 season", "WR36 season"]
series = [("Pre-draft, all prospects", [pre.p_top, pre.p_top2, pre.p_any], "#3a6fa5"),
          ("Pre-draft, if drafted (recalibrated)", [drc.p_top_d, drc.p_top2_d, drc.p_any_d], "#7d8aa0"),
          (f"Post-draft at pick {facts['median_pick']}", [post.p_top, post.p_top2, post.p_any], OR)]
w = 0.26
for k, (nm, vals, c) in enumerate(series):
    xs = np.arange(3) + (k - 1) * (w + 0.02)
    ax.bar(xs, vals, width=w, color=c, zorder=3, label=nm)
    for xx, v in zip(xs, vals): ax.text(xx, v + 0.015, pct(v), ha="center", fontsize=21, weight="bold", color=INK)
ax.set_xticks(range(3), groups, fontsize=22, color=INK); ax.set_ylim(0, 1.1); ax.set_yticks([0, .25, .5, .75, 1], ["0%", "25%", "50%", "75%", "100%"])
ax.legend(loc="upper left", ncol=3, fontsize=18, frameon=False, labelcolor=INK, bbox_to_anchor=(0, 1.08))
save(f, 7)

# 08 reality check -----------------------------------------------------------
f = fig("Reality check: top-10 WRs miss too", "Model odds vs what happened, WRs drafted 2010-2023",
        "Share with a WR12 season in NFL years 1-3. Small samples; no WR went in picks 1-3 in this span.")
ax = f.add_axes([0.07, 0.15, 0.44, 0.57]); style(ax, "y")
bn = list(bands)
xs = np.arange(len(bn))
ax.bar(xs - 0.2, [bands[b]["pred_wr12"] for b in bn], width=0.38, color="#7d8aa0", zorder=3, label="Model said")
ax.bar(xs + 0.2, [bands[b]["real_wr12"] for b in bn], width=0.38, color=OR, zorder=3, label="Actually hit WR12")
for i, b in enumerate(bn):
    ax.text(i - 0.2, bands[b]["pred_wr12"] + 0.02, pct(bands[b]["pred_wr12"]), ha="center", fontsize=20, color=INK, weight="bold")
    ax.text(i + 0.2, bands[b]["real_wr12"] + 0.02, pct(bands[b]["real_wr12"]), ha="center", fontsize=20, color=INK, weight="bold")
ax.set_xticks(xs, [f"{b}\n(n={bands[b]['n']})" for b in bn], fontsize=20, color=INK); ax.set_ylim(0, 1)
ax.set_yticks([0, .25, .5, .75, 1], ["0%", "25%", "50%", "75%", "100%"])
ax.legend(loc="upper right", fontsize=18, frameon=False, labelcolor=INK)
t5 = top_picks[top_picks.pick <= 5].sort_values("class")
f.text(0.56, 0.70, "EVERY TOP-5 WR, 2010-2023 (MODEL'S FITTED ODDS)", color=OR, fontsize=19, weight="bold")
for i, (_, r) in enumerate(t5.iterrows()):
    res = f"best WR{int(r.nfl_best_finish)}"
    f.text(0.56, 0.635 - i * 0.06, f"{r['name']} (#{int(r.pick)}, {int(r['class'])})", color=INK, fontsize=21, weight="bold")
    f.text(0.79, 0.635 - i * 0.06, f"said {pct(r.p_top)}  ·  {res}", color=GRN if r.nfl_tier == 1 else MUTED, fontsize=19)
f.text(0.56, 0.635 - len(t5) * 0.06 - 0.01, f"Smith at pick {facts['median_pick']}: model says {pct(post.p_top)}.", color=OR, fontsize=21, weight="bold")
save(f, 8)

# 09 value -------------------------------------------------------------------
f = fig("A top-15 dynasty asset before his first snap", "Rookie value at the draft, #1 rookie of each class",
        "100k scale, reference league (no flex). Past classes: Nov 18 class-value study. Smith: current board.")
ax = f.add_axes([0.08, 0.15, 0.86, 0.57]); style(ax, "y")
c1 = cls[cls["class"] < 2027].sort_values("value_100k", ascending=False).groupby("class").head(1).sort_values("class")
xs = list(c1["class"]) + [2027]; vs = list(c1.value_100k) + [facts["value_lg_default"]]; nm = list(c1.name) + [NAME]
ax.bar(range(len(xs)), vs, width=0.66, color=["#3a6fa5"] * (len(xs) - 1) + [OR], zorder=3)
for i, (v, n) in enumerate(zip(vs, nm)):
    last = n.split()[-1] if n != "Robert Griffin III" else "Griffin"
    ax.text(i, v + 700, f"{v/1000:.1f}k", ha="center", fontsize=15, color=INK, weight="bold")
    ax.text(i, 1500, last, ha="center", va="bottom", rotation=90, fontsize=15, color=BG, weight="bold")
ax.set_xticks(range(len(xs)), [str(x)[2:] if x != 2027 else "'27" for x in xs], fontsize=17)
ax.set_ylim(0, 58000); ax.yaxis.set_major_formatter(matplotlib.ticker.FuncFormatter(lambda v, _: f"{v/1000:.0f}k"))
rank = sorted(vs, reverse=True).index(facts["value_lg_default"]) + 1
ax.text(0.5, 1.04, f"#{rank} of {len(vs)} #1 rookies since 2010.   In the site's default league: {facts['value_site_default']:,} = #{facts['ovr_site_default']} among ALL dynasty players.",
        color=OR, fontsize=20, weight="bold", ha="center", transform=ax.transAxes)
save(f, 9)

# 10 risks -------------------------------------------------------------------
f = fig("What could make the model wrong", "Risks and data caveats")
items = [("No combine yet", "Pre-draft uses college data only. The post-draft model's athletic inputs are filled at average until the 2027 combine."),
         (f"2026 is about {games26} games in", f"Counting stats are pro-rated to 12 games ({me_asis.p_rec_yds:,.0f} -> {me.p_rec_yds:,.0f} yds). Unscaled, he is still {facts['pre_grade_asis']} ({facts['pre_score_asis']:.2f})."),
         ("Few true precedents", f"Only {facts['hist_wr_1600_plus']} WRs since 2010 topped 1,600 yards, and none was a 5-star true junior. The model is reaching past most of its data."),
         ("Top picks run hot", f"WRs drafted top 5 hit WR12 {pct(bands['Picks 1-5']['real_wr12'])} of the time vs {pct(bands['Picks 1-5']['pred_wr12'])} predicted (n={bands['Picks 1-5']['n']})."),
         ("Draft capital is a placeholder", "Pick 2 comes from Kyle's own mocks, not a real draft. We assume he declares (our declare model says 14%, but it badly understates elite juniors)."),
         ("Regular season only", "CFBD season stats exclude bowls and playoffs, the same for every prospect in the model.")]
for i, (h1, body) in enumerate(items):
    col, row = i % 2, i // 2
    x, y = 0.055 + col * 0.45, 0.62 - row * 0.21
    f.patches.append(plt.Rectangle((x, y - 0.06), 0.43, 0.195, transform=f.transFigure, fc=PANEL, ec="#1f2c45", lw=2))
    f.text(x + 0.015, y + 0.09, h1, color=OR, fontsize=25, weight="bold")
    import textwrap
    f.text(x + 0.015, y + 0.055, "\n".join(textwrap.wrap(body, 58)), color=INK, fontsize=19, va="top", linespacing=1.35)
save(f, 10)

# 11 bottom line -------------------------------------------------------------
f = plt.figure(figsize=(19.2, 10.8), dpi=100)
f.text(0.055, 0.80, "THE BOTTOM LINE", color=OR, fontsize=26, weight="bold")
f.text(0.055, 0.60, "The best WR profile in our data.", color=INK, fontsize=70, weight="heavy", family="Inter Display")
f.text(0.055, 0.49, "Still not a lock.", color=OR, fontsize=70, weight="heavy", family="Inter Display")
f.text(0.057, 0.37, f"Model: {pct(post.p_top)} WR12 odds at pick {facts['median_pick']}.  History: about half of top-10 WRs get there.", color=INK, fontsize=30)
f.text(0.057, 0.31, f"Our price: {facts['value_site_default']:,}, the clear 1.01 on our board.", color=MUTED, fontsize=30)
f.text(0.057, 0.15, "Full 2027 rookie rankings  ·  kylemschyma.github.io/prospect-actuary/rookie-rankings/", color=INK, fontsize=24, weight="bold")
f.text(0.057, 0.10, "Data: CollegeFootballData.com via cfbfastR · nflverse via nflreadr · Pro Football Reference.  Values as of the Nov 24 refresh.", color=MUTED, fontsize=17)
f.text(0.057, 0.035, "PROSPECT ACTUARY  ·  CC BY 4.0", color=MUTED, fontsize=16, weight="bold")
save(f, 11)
print(json.dumps(facts, indent=1, default=float))
