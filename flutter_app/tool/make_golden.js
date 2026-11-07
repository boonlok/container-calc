// 用 JavaScript.html 里的装箱算法 (网页版) 产生基准数据, Flutter 版测试逐项比对:  node tool/make_golden.js
const fs = require('fs'), vm = require('vm'), path = require('path');
const html = fs.readFileSync(path.join(__dirname, '..', '..', 'JavaScript.html'), 'utf8');
const a = html.indexOf('function calcBoxesNeeded'), b = html.indexOf('// ============================================================\n//  物品清单管理');
const ctx = {}; vm.createContext(ctx); vm.runInContext(html.slice(a, b), ctx);
const C = [{ name: '20GP', L: 589, W: 235, H: 239, maxPayload: 28180 }, { name: '40GP', L: 1203, W: 235, H: 239, maxPayload: 26580 },
  { name: '40HC', L: 1203, W: 235, H: 269, maxPayload: 28600 }, { name: '45HC', L: 1355, W: 235, H: 269, maxPayload: 27600 }];
const mk = (id, name, n, l, w, h, wt = 0, ppb = 1) => ({ id, name, totalPcs: n, pcsPerBox: ppb, boxL: l, boxW: w, boxH: h, boxWeight: wt, color: '#888888' });
const scen = [
  ['S1', [mk(1, 'A', 1000, 50, 40, 30)]],
  ['S2', [mk(1, 'A', 300, 60, 40, 40), mk(2, 'B', 800, 30, 30, 25), mk(3, 'C', 60, 100, 50, 50)]],
  ['S3', [mk(1, 'A', 1500, 45, 35, 20)]],
  ['S4', [mk(1, 'A', 500, 40, 40, 40, 40)]],
  ['S5', Array.from({ length: 12 }, (_, i) => mk(i + 1, 'I' + i, 100 + i * 37, 20 + i * 3, 15 + i * 2, 10 + i * 4))],
  ['S6 oversize', [mk(1, 'Huge', 5, 300, 300, 300), mk(2, 'Ok', 100, 40, 30, 20)]],
  ['S7 pcs per box', [mk(1, 'P', 1234, 33, 22, 11, 2.5, 12), mk(2, 'Q', 777, 41, 29, 19, 0, 7)]],
];
let seed = 7; const rnd = () => (seed = (seed * 1664525 + 1013904223) % 4294967296) / 4294967296;
for (let k = 0; k < 40; k++) {
  const n = 1 + Math.floor(rnd() * 6);
  scen.push(['R' + k, Array.from({ length: n }, (_, i) => mk(i + 1, 'R' + i, 20 + Math.floor(rnd() * 900), 15 + Math.floor(rnd() * 80), 15 + Math.floor(rnd() * 60), 10 + Math.floor(rnd() * 60), rnd() < 0.3 ? 5 + Math.floor(rnd() * 30) : 0, 1 + Math.floor(rnd() * 5)))]);
}
const out = scen.map(([name, items]) => {
  const r = ctx.packContainers(items, C);
  return { name, items, presets: C, result: JSON.parse(JSON.stringify({ containers: r.containers, unfulfilled: r.unfulfilled.map(u => ({ name: u.name, boxesRemaining: u.boxesRemaining })) })) };
});
fs.writeFileSync(path.join(__dirname, '..', 'test', 'golden', 'algo_golden.json'), JSON.stringify(out));
console.log('scenarios', out.length, 'bytes', fs.statSync(path.join(__dirname, '..', 'test', 'golden', 'algo_golden.json')).size);
