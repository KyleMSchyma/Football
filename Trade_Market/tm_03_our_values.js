// Our model values (site engine) for a grid of leagues, for comparison with trade-implied values.
const fs = require('fs'), vm = require('vm');
const SITE = process.argv[2];
global.window = global;
vm.runInThisContext(fs.readFileSync(SITE + '/trade-values/data/tv.js', 'utf8'));
vm.runInThisContext(fs.readFileSync(SITE + '/shared/engine.js', 'utf8'));
const E = window.PAEngine(window.TV);
const rows = ['mode,teams,ppr,tep,sf,starters,name,pos,value,rank'];
for (const teams of [8,10,12,14]) for (const ppr of [0.5,1]) for (const tep of [0,0.5,1]) for (const sf of [0,1]) {
  const S = {teams, ppr, tep, ptd:4, sf, rb:2, wr:3, te:1, flex:2, fdQB:0, fdRB:0, fdWR:0, fdTE:0};
  const C = E.compute(S), st = 9 + sf;
  C.dynAll.forEach(r => rows.push(['d',teams,ppr,tep,sf,st,JSON.stringify(r.n),r.p,r.v.toFixed(1),r.r].join(',')));
  C.red.forEach(r => rows.push(['r',teams,ppr,tep,sf,st,JSON.stringify(r.n),r.p,r.v.toFixed(1),r.r].join(',')));
}
fs.writeFileSync('our_values.csv', rows.join('\n'));
console.log(rows.length, window.TV.asof);
