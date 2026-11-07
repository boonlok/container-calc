// 装箱算法测试: 从 JavaScript.html 取出算法函数, 在 node 里执行
const fs=require('fs'),vm=require('vm'),path=require('path');
const html=fs.readFileSync(path.join(__dirname,'..','JavaScript.html'),'utf8');
const a=html.indexOf('function calcBoxesNeeded'),b=html.indexOf('// ============================================================\n//  物品清单管理');
const ctx={};vm.createContext(ctx);vm.runInContext(html.slice(a,b),ctx);Object.assign(ctx,vm.runInContext('({PACK_ORDERINGS,PACK_POLICIES})',ctx));
const t=(n,ok,extra)=>console.log(ok?'PASS':'FAIL',n,extra||'');
const C=[{name:'20GP',L:589,W:235,H:239,maxPayload:28180},{name:'40GP',L:1203,W:235,H:239,maxPayload:26580},{name:'40HC',L:1203,W:235,H:269,maxPayload:28600},{name:'45HC',L:1355,W:235,H:269,maxPayload:27600}];
const mk=(id,name,n,l,w,h,wt=0)=>({id,name,totalPcs:n,pcsPerBox:1,boxL:l,boxW:w,boxH:h,boxWeight:wt,color:'#888888'});
// 旧算法 = 体积排序 + 利用率优先 (新实现的第一个组合)
const old=(items)=>ctx.packWithStrategy(items,C,ctx.PACK_ORDERINGS.volume,ctx.PACK_POLICIES.util);
const score=r=>ctx.packScore(r);
const scen={
 'S1 1000x(50x40x30)':[mk(1,'A',1000,50,40,30)],
 'S2 mixed':[mk(1,'A',300,60,40,40),mk(2,'B',800,30,30,25),mk(3,'C',60,100,50,50)],
 'S3 awkward':[mk(1,'A',1500,45,35,20)],
 'S4 heavy':[mk(1,'A',500,40,40,40,40)],
 'S5 12 kinds':Array.from({length:12},(_,i)=>mk(i+1,'I'+i,100+i*37,20+i*3,15+i*2,10+i*4)),
};
let strictlyBetter=0;
for(const [k,items] of Object.entries(scen)){
  const o=old(items),n=ctx.packContainers(items,C);
  const so=score(o),sn=score(n);
  const notWorse=!ctx.packScoreLess(so,sn);
  if(ctx.packScoreLess(sn,so))strictlyBetter++;
  t(k+' not worse than old',notWorse,`old ${o.containers.map(c=>c.containerType).join('+')} -> new ${n.containers.map(c=>c.containerType).join('+')}`);
  // 完整性: 每个物品全部装完
  const placed={};n.containers.forEach(c=>c.allocations.forEach(al=>placed[al.itemId]=(placed[al.itemId]||0)+al.boxesPlaced));
  t(k+' every box placed',items.every(i=>(placed[i.id]||0)===ctx.calcBoxesNeeded(i))&&n.unfulfilled.length===0);
  // 物理约束: 区块不超出柜长, 不重叠, 重量不超
  const ok=n.containers.every(c=>{let end=0;return c.allocations.every(al=>{const good=al.startLength>=end-0.01&&al.startLength+al.lengthUsed<=c.L+0.01&&al.horizontal*(al.rotated?al.boxL:al.boxW)<=c.W&&al.vertical*al.boxH<=c.H;end=al.startLength+al.lengthUsed;return good})&&c.totalWeightUsed<=c.maxPayload});
  t(k+' physical constraints',ok);
}
t('S1 uses a single 45HC (was 40HC+20GP)',ctx.packContainers(scen['S1 1000x(50x40x30)'],C).containers.length===1);
t('at least one scenario strictly improved',strictlyBetter>=1,strictlyBetter);
// 随机回归: 新算法永远不比旧的差
let seed=7;const rnd=()=>(seed=(seed*1664525+1013904223)%4294967296)/4294967296;
let worse=0,better=0,N=60;
for(let k=0;k<N;k++){const items=Array.from({length:1+Math.floor(rnd()*6)},(_,i)=>mk(i+1,'R'+i,20+Math.floor(rnd()*900),15+Math.floor(rnd()*80),15+Math.floor(rnd()*60),10+Math.floor(rnd()*60),rnd()<0.3?5+Math.floor(rnd()*30):0));
  const o=old(items),n=ctx.packContainers(items,C);if(ctx.packScoreLess(score(o),score(n)))worse++;else if(ctx.packScoreLess(score(n),score(o)))better++;}
t('random: never worse than old ('+N+' cases)',worse===0,`better in ${better}`);
const big=Array.from({length:40},(_,i)=>mk(i+1,'B'+i,500+i*13,20+(i%7)*9,15+(i%5)*8,10+(i%6)*7));
const t0=Date.now();ctx.packContainers(big,C);const ms=Date.now()-t0;t('40 items runs fast (<3s)',ms<3000,ms+'ms');
