// 语法检查 + 运行测试: node tests/check.js
const fs=require('fs'),path=require('path'),cp=require('child_process'),os=require('os');
const root=path.join(__dirname,'..');const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'cc-'));
let bad=0;
for(const f of fs.readdirSync(root).filter(f=>f.endsWith('.html'))){
  const t=fs.readFileSync(path.join(root,f),'utf8');const re=/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g;let m,i=0;
  while((m=re.exec(t))){i++;const p=path.join(tmp,f+'_'+i+'.js');fs.writeFileSync(p,m[1].replace(/<\?!?=[\s\S]*?\?>/g,''));
    const r=cp.spawnSync('node',['--check',p],{encoding:'utf8'});console.log(r.status?'FAIL':'OK  ',f,i,r.stderr||'');if(r.status)bad++;}
}
fs.copyFileSync(path.join(root,'Code.gs'),path.join(tmp,'Code.js'));
const r=cp.spawnSync('node',['--check',path.join(tmp,'Code.js')],{encoding:'utf8'});console.log(r.status?'FAIL':'OK  ','Code.gs',r.stderr||'');if(r.status)bad++;
for(const t of fs.readdirSync(__dirname).filter(f=>/\.test\.js$/.test(f))){
  const o=cp.spawnSync('node',[path.join(__dirname,t)],{encoding:'utf8'});const out=o.stdout+o.stderr;
  console.log('---',t);console.log(out.split('\n').filter(l=>/FAIL|Error/.test(l)).join('\n')||'all PASS ('+(out.match(/PASS/g)||[]).length+')');if(o.status||/FAIL/.test(out))bad++;
}
process.exit(bad?1:0);
