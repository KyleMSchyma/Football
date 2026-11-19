"""Combine Kyle's saved 2027 mocks into one pick range per QB/RB/WR/TE prospect.

Kyle's rule (2026-11-18):
  * best case  = his earliest pick across the mocks
  * worst case = his latest pick, or UNDRAFTED if any mock leaves him out
  * value      = share of mocks that draft him x value at his MEDIAN pick
                 + share that leave him undrafted x undrafted value
  * median pick = median over the mocks that draft him (Kyle 2026-11-18, was the average), rounded to the nearest
                  whole pick (.5 rounds up; only happens with an even number of mocks drafting him)

Inputs : every Mock_Drafts/2027_mock_*.csv (Kyle's own mocks only; listed in Mock_Drafts/README.md)
         a previous pd_09 mock file for board-name aliases and height/weight (optional, --aliases)
Outputs (Mock_Drafts/range/):
  mock_2027_range_players.csv   one row per prospect: picks in each mock, share drafted, best / worst / average pick
  mock_2027_avg.csv             pd_09 MOCK_FILE format, pick = rounded MEDIAN pick (file name kept for the pipeline)
  mock_2027_best.csv            pd_09 MOCK_FILE format, pick = best pick
  mock_2027_worst.csv           pd_09 MOCK_FILE format, pick = worst pick (players drafted in every mock only)
The landing team for the median pick is the team from the mock whose pick is closest to the median
(the earlier pick on a tie). Rounds are approximate (comp picks move the round boundaries); only the pick feeds the model.

Run: python3 Mock_Drafts/combine_mocks.py [--aliases <pd_09 mock csv with mddb_name column>]
"""
import argparse, csv, glob, math, os, re
from collections import OrderedDict

HERE = os.path.dirname(os.path.abspath(__file__))
FANTASY = {"QB", "RB", "WR", "TE"}
ABBR = {"arizona-cardinals": "ARI", "atlanta-falcons": "ATL", "baltimore-ravens": "BAL", "buffalo-bills": "BUF",
        "carolina-panthers": "CAR", "chicago-bears": "CHI", "cincinnati-bengals": "CIN", "cleveland-browns": "CLE",
        "dallas-cowboys": "DAL", "denver-broncos": "DEN", "detroit-lions": "DET", "green-bay-packers": "GB",
        "houston-texans": "HOU", "indianapolis-colts": "IND", "jacksonville-jaguars": "JAX", "kansas-city-chiefs": "KC",
        "las-vegas-raiders": "LV", "los-angeles-chargers": "LAC", "los-angeles-rams": "LA", "miami-dolphins": "MIA",
        "minnesota-vikings": "MIN", "new-england-patriots": "NE", "new-orleans-saints": "NO", "new-york-giants": "NYG",
        "new-york-jets": "NYJ", "philadelphia-eagles": "PHI", "pittsburgh-steelers": "PIT", "san-francisco-49ers": "SF",
        "seattle-seahawks": "SEA", "tampa-bay-buccaneers": "TB", "tennessee-titans": "TEN", "washington-commanders": "WAS"}
# MDDB names that differ from our 2027 board (also read from --aliases when given)
ALIASES = {"Ryan Coleman-Williams": "Ryan Williams", "Hollywood Smothers": "Daylan Smothers", "Quintrevion Wisner": "Tre Wisner"}
ROUND_END = [32, 64, 100, 139, 176, 217, 999]   # approximate, from the 2026-11-15 mock


def rnd(p):
    return next(i + 1 for i, e in enumerate(ROUND_END) if p <= e)


def round_half_up(x):
    return int(math.floor(x + 0.5))


def key(name):
    return re.sub(r"[^a-z]", "", re.sub(r"\b(jr|sr|ii|iii|iv)\.?$", "", name.lower().strip()))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--aliases", help="previous pd_09 mock file (columns player, mddb_name, height_in, weight_lb)")
    ap.add_argument("--out", default=os.path.join(HERE, "range"))
    a = ap.parse_args()
    hw = {}
    if a.aliases and os.path.exists(a.aliases):
        for r in csv.DictReader(open(a.aliases, encoding="utf-8")):
            if r.get("mddb_name") and r["mddb_name"] != r["player"]:
                ALIASES[r["mddb_name"]] = r["player"]
            hw[key(r["player"])] = (r.get("height_in", ""), r.get("weight_lb", ""))

    files = sorted(glob.glob(os.path.join(HERE, "2027_mock_*.csv")))
    mocks = [os.path.basename(f)[:-4] for f in files]
    players = OrderedDict()
    for m, f in zip(mocks, files):
        for r in csv.DictReader(open(f, encoding="utf-8")):
            if r["pos"] not in FANTASY:
                continue
            name = ALIASES.get(r["player"], r["player"])
            k = (key(name), r["pos"])
            p = players.setdefault(k, {"player": name, "mddb_name": r["player"], "pos": r["pos"], "school": r["school"], "picks": {}})
            p["picks"][m] = (int(r["pick"]), r["team_slug"], r["team"])

    os.makedirs(a.out, exist_ok=True)
    n = len(mocks)
    rows, avg, best, worst = [], [], [], []
    for k, p in players.items():
        pk = p["picks"]
        vals = sorted(v[0] for v in pk.values())
        mid = len(vals) // 2
        mean = vals[mid] if len(vals) % 2 else (vals[mid - 1] + vals[mid]) / 2   # the MEDIAN (name kept below)
        apick = round_half_up(mean)
        near = min(pk.values(), key=lambda v: (abs(v[0] - mean), v[0]))
        b = min(pk.values(), key=lambda v: v[0])
        w = max(pk.values(), key=lambda v: v[0])
        all_in = len(pk) == n
        h, wt = hw.get(k[0], ("", ""))
        row = OrderedDict(player=p["player"], mddb_name=p["mddb_name"], pos=p["pos"], school=p["school"],
                          n_mocks=n, n_drafted=len(pk), share_drafted=round(len(pk) / n, 4),
                          avg_pick_exact=round(mean, 2), avg_pick=apick, mean_pick=round(sum(vals) / len(vals), 2), avg_team_abbr=ABBR[near[1]],
                          best_pick=b[0], best_team_abbr=ABBR[b[1]],
                          worst_pick=w[0] if all_in else "", worst_team_abbr=ABBR[w[1]] if all_in else "",
                          worst_case="pick" if all_in else "undrafted")
        for m in mocks:
            row["pick_" + m] = pk[m][0] if m in pk else ""
        rows.append(row)
        base = dict(player=p["player"], pos=p["pos"], school=p["school"], height_in=h, weight_lb=wt, mddb_name=p["mddb_name"])
        team = lambda v: dict(team=v[2], team_abbr=ABBR[v[1]])
        avg.append(dict(round=rnd(apick), pick=apick, **team(near), **base))
        best.append(dict(round=rnd(b[0]), pick=b[0], **team(b), **base))
        if all_in:
            worst.append(dict(round=rnd(w[0]), pick=w[0], **team(w), **base))

    cols = ["round", "pick", "team", "team_abbr", "player", "pos", "school", "height_in", "weight_lb", "mddb_name"]
    for name, data in [("mock_2027_avg.csv", avg), ("mock_2027_best.csv", best), ("mock_2027_worst.csv", worst)]:
        data.sort(key=lambda r: (r["pick"], r["player"]))
        with open(os.path.join(a.out, name), "w", newline="", encoding="utf-8") as fh:
            wr = csv.DictWriter(fh, cols, lineterminator="\n"); wr.writeheader(); wr.writerows(data)
    rows.sort(key=lambda r: (r["avg_pick_exact"], r["player"]))
    with open(os.path.join(a.out, "mock_2027_range_players.csv"), "w", newline="", encoding="utf-8") as fh:
        wr = csv.DictWriter(fh, list(rows[0].keys()), lineterminator="\n"); wr.writeheader(); wr.writerows(rows)
    print(f"{n} mocks: {', '.join(mocks)}")
    print(f"{len(rows)} QB/RB/WR/TE prospects; drafted in every mock {sum(r['n_drafted'] == n for r in rows)}, "
          f"in some {sum(0 < r['n_drafted'] < n for r in rows)}; avg/best/worst files: {len(avg)}/{len(best)}/{len(worst)} rows")


if __name__ == "__main__":
    main()
