// pp_02_values.js: price every prospect in outputs/pp_prospects.csv with the site's own engine (shared/engine.js,
// prospectValue = tier odds x tier PPG with age adjustment, 100k dynasty scale) in four leagues, plus the site's
// 2027 pick values 1.01-4.12 and our dynasty player board (for rank-matching the trade-market pick prices).
// usage: node pp_02_values.js <prospect-actuary dir>
global.window = {}; const fs = require('fs'), vm = require('vm'), SITE = process.argv[2] || '/home/user/prospect-actuary/';
for (const f of ['trade-values/data/tv.js', 'trade-values/data/agetab.js', 'shared/engine.js', 'value-research/data/tm.js']) vm.runInThisContext(fs.readFileSync(SITE + f, 'utf8'));
const E = window.PAEngine(window.TV, window.TVAGE);
const base = {teams:12, ppr:1, tep:0, ptd:4, sf:1, rb:2, wr:3, te:1, flex:2, fdQB:0, fdRB:0, fdWR:0, fdTE:0};
const L = {sf: base, oneqb: {...base, sf:0}, tep: {...base, tep:1},
           market: {...base, ppr:0.5, flex:0}};   // the trade-market page's league (12 tm, 0.5 PPR, SF, no flex)
const lines = fs.readFileSync('outputs/pp_prospects.csv', 'utf8').trim().split('\n');
const parse = s => { const o = []; let cur = '', q = false; for (const ch of s) { if (ch === '"') q = !q; else if (ch === ',' && !q) { o.push(cur); cur = ''; } else cur += ch; } o.push(cur); return o; };
const H = parse(lines[0]); const ix = k => H.indexOf(k);
const out = ['id,' + Object.keys(L).map(k => 'v_' + k).join(',') + ',v_best,v_worst'];
for (const ln of lines.slice(1)) { const c = parse(ln), g = k => parseFloat(c[ix(k)]);
  const pos = c[ix('pos')], age = g('age');
  const vals = Object.values(L).map(S => Math.round(E.prospectValue(S, pos, [g('p1'), g('p2'), g('p3')], age) || 0));
  const bw = ['b', 'w'].map(p => isNaN(g(p + '1')) ? '' : Math.round(E.prospectValue(L.sf, pos, [g(p + '1'), g(p + '2'), g(p + '3')], age) || 0));
  out.push([c[ix('id')], ...vals, ...bw].join(',')); }
fs.writeFileSync('outputs/pp_values.csv', out.join('\n') + '\n');
// site pick values and our dynasty player board, per league
const pk = ['league,slot,s,value'], bd = ['league,rank,value,name,pos'];
for (const [k, S] of Object.entries(L)) { const C = E.compute(S);
  C.picks.forEach((r, s) => pk.push([k, r.slot, s + 1, Math.round(r.v)].join(',')));
  C.dynAll.filter(r => !r.pick).sort((a, b) => b.v - a.v).forEach((r, j) => bd.push([k, j + 1, Math.round(r.v), JSON.stringify(r.n), r.p].join(','))); }
fs.writeFileSync('outputs/pp_site_pick_values.csv', pk.join('\n') + '\n');
fs.writeFileSync('outputs/pp_our_board.csv', bd.join('\n') + '\n');
fs.writeFileSync('outputs/pp_market.json', JSON.stringify({asof: window.TM.asof, rows: window.TM.rows, picks: window.TM.picks}));
console.log('ok', out.length - 1, 'prospects');
