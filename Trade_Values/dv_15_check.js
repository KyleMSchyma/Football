// dv_15: run inside the trade-values page after window.DV15 is loaded. Returns max |browser - R| per league (100k scale).
(function(){ const out = [];
  DV15.forEach(L => { Object.assign(S, L.S); const c = compute(); let md = 0, mr = 0, mp = 0, nd = 0, nr = 0;
    const byD = {}, byR = {}; c.dyn.forEach(r => { if (!r.pick) byD[r.n + "|" + r.p] = r.v; }); c.red.forEach(r => byR[r.n + "|" + r.p] = r.v);
    L.players.forEach(pl => { const k = pl.n + "|" + pl.p;
      if (pl.d != null && pl.d >= 500 && byD[k] != null) { md = Math.max(md, Math.abs(byD[k] - pl.d)); nd++; }
      if (pl.r != null && byR[k] != null) { mr = Math.max(mr, Math.abs(byR[k] - pl.r)); nr++; } });
    const pv = c.dyn.filter(r => r.pick).map(r => r.v); L.picks.forEach((v, i) => { if (pv[i] != null) mp = Math.max(mp, Math.abs(pv[i] - v)); });
    out.push({league: L.name, dynasty_max_diff: +md.toFixed(4), n_dynasty: nd, redraft_max_diff: +mr.toFixed(4), n_redraft: nr, pick_max_diff: +mp.toFixed(4), n_picks: pv.length}); });
  Object.assign(S, DEF); return out; })()
