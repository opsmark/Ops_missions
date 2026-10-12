// Official published desktop-commander@0.2.52 Windows reader probe.
// Runs only on disposable GitHub-hosted Windows fixtures; no OPS machine paths or data.
// The npm package must have been fetched via "npm pack --ignore-scripts" into ./package.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL, fileURLToPath} from 'node:url';

const root=process.cwd();
const packageJson=join(root,'package','package.json');
const modulePath=join(root,'package','dist','utils','files','text.js');
assert.ok(existsSync(packageJson)&&existsSync(modulePath),'expected exact official npm package and dist reader');
const pkg=JSON.parse(readFileSync(packageJson,'utf8'));
assert.equal(pkg.name,'@wonderwhy-er/desktop-commander');
assert.equal(pkg.version,'0.2.52');
const raw=readFileSync(modulePath);
const sourceSha256=createHash('sha256').update(raw).digest('hex');
const moduleText=raw.toString('utf8');
assert.match(moduleText,/readFromStartWithReadline/);
const {TextFileHandler}=await import(pathToFileURL(modulePath).href);

function exclusiveOpen(file){
 const script=[
  "$ErrorActionPreference='Stop'",
  "try {",
  " $h=[System.IO.File]::Open($env:OPS_READER_FIXTURE,[System.IO.FileMode]::Open,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None)",
  " $h.Dispose(); Write-Output 'EXCLUSIVE_OPEN_OK'; exit 0",
  "} catch { Write-Output 'EXCLUSIVE_OPEN_REJECTED'; exit 24 }"
 ].join('\n');
 const r=spawnSync('powershell.exe',['-NoLogo','-NoProfile','-NonInteractive','-Command',script],
   {encoding:'utf8',env:{...process.env,OPS_READER_FIXTURE:file},timeout:12000});
 if(r.error)throw r.error;
 if(![0,24].includes(r.status))throw Error('PowerShell probe failed '+r.status+': '+r.stderr);
 return {allowed:r.status===0,observation:r.stdout.trim()};
}
async function one(which){
 const tmp=mkdtempSync(join(tmpdir(),'ops-released-read-'));
 const file=join(tmp,'test.txt');
 const deep=which==='deep';
 const count=deep?145000:25000;
 const size=deep?100:80;
 const lines=Array.from({length:count},(_,i)=>'ROW'+String(i).padStart(6,'0')+':'+'x'.repeat(size));
 writeFileSync(file,lines.join('\n'));
 try{
  const baseline=exclusiveOpen(file);
  assert.equal(baseline.allowed,true,'new fixture must not start locked');
  let content='',offset=0,length=null;
  const handler=new TextFileHandler();
  if(which==='explicit'){
   length=12;
   const r=await handler.read(file,{offset,length,includeStatusMessage:false});
   content=r.content;
   assert.deepEqual(content.split('\n'),lines.slice(0,length));
  }else if(which==='default'){
   const r=await handler.read(file);
   content=r.content;
   assert.match(content,/Reading 1000 lines from start/);
  }else if(which==='eof'){
   length=count+1;
   const r=await handler.read(file,{offset,length,includeStatusMessage:false});
   content=r.content;
   assert.equal(content.split('\n').length,count);
  }else if(which==='deep'){
   offset=1500;length=9;
   const r=await handler.read(file,{offset,length,includeStatusMessage:false});
   content=r.content;
   assert.ok(content.length>0);
  }else if(which!=='none')throw Error('unrecognized case');
  const p=exclusiveOpen(file);
  // The original OPS failure was a staged replacement, not just an exclusive open.
  // Test the equivalent cross-process rename-over-existing-file using disposable fixtures.
  const replacement=join(tmp,'next.tmp');
  writeFileSync(replacement,'NEW_FILE_GENERATION\n');
  const atomic=spawnSync(process.execPath,[
    '-e',
    "const fs=require('node:fs'); try{fs.renameSync(process.argv[1],process.argv[2]);console.log('REPLACE_OK')}catch(e){console.log('REPLACE_REJECTED:'+e.code);process.exit(24)}",
    replacement,file
  ],{encoding:'utf8',timeout:9000});
  if(atomic.error)throw atomic.error;
  if(![0,24].includes(atomic.status))throw Error('replace child error '+atomic.status+': '+atomic.stderr);
  return {case:which,baseline:baseline.observation,postRead:p.observation,
   exclusiveAllowed:p.allowed,atomicReplaceAllowed:atomic.status===0,atomicObservation:atomic.stdout.trim(),
   reportedLines:which==='default'?1000:content.split('\n').length,
   moduleSha256:sourceSha256,node:process.version,platform:process.platform};
 }finally{
  try{rmSync(tmp,{recursive:true,force:true,maxRetries:3,retryDelay:150})}
  catch(e){console.error('CLEANUP_BLOCKED '+which+' '+e.code);}
 }
}

const which=process.env.OFFICIAL_READER_CASE;
if(which){
 console.log(JSON.stringify(await one(which)));
}else{
 const cases=[];
 for(const mode of ['none','explicit','default','eof','deep']){
  const r=spawnSync(process.execPath,[fileURLToPath(import.meta.url)],{
    encoding:'utf8',timeout:45000,env:{...process.env,OFFICIAL_READER_CASE:mode},
  });
  assert.equal(r.status,0,mode+' child failed: '+r.stderr+'\n'+r.stdout);
  cases.push(JSON.parse(r.stdout.trim().split(/\r?\n/).at(-1)));
 }
 const by=Object.fromEntries(cases.map(x=>[x.case,x]));
 assert.equal(by.none.exclusiveAllowed,true);
 assert.equal(by.eof.exclusiveAllowed,true);
 // These expectations qualify the observed shipped defect, not a production fix.
 assert.equal(by.explicit.exclusiveAllowed,false,'official small prefix unexpectedly released file');
 assert.equal(by.default.exclusiveAllowed,false,'official default prefix unexpectedly released file');
 assert.equal(by.deep.exclusiveAllowed,false,'official large deep offset unexpectedly released file');
 // A separate writer must be able to atomically replace a clean target and a fully drained target.
 assert.equal(by.none.atomicReplaceAllowed,true,'control atomic replacement failed');
 assert.equal(by.eof.atomicReplaceAllowed,true,'drained reader blocked atomic replacement');
 assert.equal(by.explicit.atomicReplaceAllowed,false,'explicit-budget read failed to block atomic replacement');
 assert.equal(by.default.atomicReplaceAllowed,false,'default-budget read failed to block atomic replacement');
 assert.equal(by.deep.atomicReplaceAllowed,false,'deep-offset read failed to block atomic replacement');
 assert.ok(cases.every(c=>c.moduleSha256===sourceSha256&&c.platform==='win32'));
 console.log(JSON.stringify({status:'PASS',classification:'OFFICIAL_NPM_0.2.52_WINDOWS_REPRO',
   packageName:pkg.name,packageVersion:pkg.version,sourceSha256,cases},null,2));
}
