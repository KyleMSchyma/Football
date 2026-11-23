# Preview only: add projected 3-year PPR points ("pp") to the pre-draft and post-draft boards' data and a "Proj. pts" column.
# The weekly refresh rewrites the window.PD line, so going live would need the R page generators to write the field instead.
import csv, json, re, sys
SITE = sys.argv[1]; R = "/mnt/project-files/research/points_projection/"
def rd(f): return list(csv.DictReader(open(R + f)))
def num(x): return None if x in ("", "NA", None) else int(float(x))
pre = {(r["position"], r["class"], r["name"]): num(r["proj_pts_3yr"]) for r in rd("proj_points_predraft.csv")}
post = {(r["position"], r["class"], r["pick"]): (num(r["proj_pts_3yr_mixed"]), num(r["proj_pts_3yr_post"])) for r in rd("proj_points_postdraft.csv")}
mock = {(r["position"], r["pick"], r["board_name"]): (num(r["proj_pts_3yr_mixed"]), num(r["proj_pts_3yr_post"])) for r in rd("proj_points_2027_mock.csv")}
mock2 = {(r["position"], r["pick"]): (num(r["proj_pts_3yr_mixed"]), num(r["proj_pts_3yr_post"])) for r in rd("proj_points_2027_mock.csv")}
def pk(x): return "" if x is None else str(int(x))
TH = '<th title="Grade = rank within position">Grade</th>'
TH_NEW = TH + '<th class="r" title="Projected PPR points over the first 3 NFL seasons (research preview). Expected points, so busts pull it down; see the note above the board.">Proj. pts</th>'
TD = '<td>${chip(p.g)}</td>'
TD_NEW = TD + '<td class="r num">${p.pp==null?"":p.pp.toLocaleString("en-US")}</td>'
NOTE_PRE = '<p class="small"><b>Proj. pts (research preview):</b> projected PPR points over a player\'s first three NFL seasons, from a points model on the same college inputs as the grade. Past classes show the out-of-class projection (what the model would have said before the draft). It includes the chance of going undrafted, so it runs low for players who were drafted. It ranks college prospects by actual 3-year points a bit better than the grade (WR and TE most), but rookie Value stays on the tier odds, which tracked real dynasty value better in testing.</p>'
NOTE_POST = '<p class="small"><b>Proj. pts (research preview):</b> projected PPR points over a player\'s first three NFL seasons, from a points model on the same inputs as the post-draft grade (draft slot, landing spot, college profile). Past classes show the out-of-class projection. The mixed view adds the faller boost on the points scale. After the draft it ranks players about the same as the grade; rookie Value stays on the tier odds.</p>'
def patch(path, kind):
    s = open(path).read()
    m = re.search(r'window\.PD=(\{.*?\});\n', s); D = json.loads(m.group(1)); hit = 0
    for p in D["players"]:
        if kind == "pre": v = pre.get((p["pos"], str(p["cls"]), p["name"]))
        else:
            v = post.get((p["pos"], str(p["cls"]), pk(p.get("pk"))))
            if v: p["ppd"] = v[1]; v = v[0]
        p["pp"] = v; hit += v is not None
    print(path, "board rows", len(D["players"]), "with projection", hit)
    s = s[:m.start(1)] + json.dumps(D, separators=(",", ":"), ensure_ascii=False) + s[m.end(1):]
    if kind == "post":
        m = re.search(r'window\.MOCK27=(\[.*?\]);\n', s); M = json.loads(m.group(1)); h = 0
        for d in M:
            v = mock.get((d["pos"], str(d["pick"]), d["name"])) or mock2.get((d["pos"], str(d["pick"])))
            if v: d["pp"], d["ppd"] = v; h += 1
        print("mock rows", len(M), "with projection", h)
        s = s[:m.start(1)] + json.dumps(M, separators=(",", ":"), ensure_ascii=False) + s[m.end(1):]
        old = 'p.sc = d.sc; p.pct = d.pct; p.vq = d.qv || d.q; p.mx = 0; p.v = null; });'
        assert s.count(old) == 1; s = s.replace(old, old[:-4] + ' }); rows.forEach(p => { if (p.ppd !== undefined) p.pp = p.ppd; });')
        old = 'team:d.team,mx:d.mx,gd:d.gd,'; assert s.count(old) == 1; s = s.replace(old, 'team:d.team,mx:d.mx,gd:d.gd,pp:d.pp,')
    assert s.count(TH) >= 1 and s.count(TD) >= 1
    # only the main board gets the column
    i = s.index('document.getElementById("board").innerHTML'); j = s.index("</tr></thead><tbody>", i)
    head = s[i:j]; assert TH in head; s = s[:i] + head.replace(TH, TH_NEW) + s[j:]
    k = s.index("rows.slice(0,shown).map(", i); l = s.index(TD, k); s = s[:l] + TD_NEW + s[l + len(TD):]
    anchor = '<label for="fSort">'; a = s.index(anchor); b = s.rfind("<div", 0, a)
    s = s[:b] + (NOTE_PRE if kind == "pre" else NOTE_POST) + "\n  " + s[b:]
    open(path, "w").write(s)
patch(SITE + "/pre-draft/index.html", "pre"); patch(SITE + "/post-draft/index.html", "post")
