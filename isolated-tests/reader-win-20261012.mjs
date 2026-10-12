// Synthetic Windows read-stream close probe. No private OPS data or live machine access.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createReadStream, mkdtempSync, openSync, closeSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createInterface} from 'node:readline';
import {fileURLToPath} from 'node:url';

const PWSH = [
  "$ErrorActionPreference='Stop'",
  "try {",
  " $handle=[System.IO.File]::Open($env:OPS_READER_FIXTURE,[System.IO.FileMode]::Open,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None)",
  " $handle.Dispose()",
  " Write-Output 'EXCLUSIVE_OPEN_OK'",
  " exit 0",
  "} catch { Write-Output ('EXCLUSIVE_OPEN_REJECTED:'+$_.Exception.GetType().Name); exit 24 }",
].join('\n');
function probe(file) {
  const r=spawnSync('powershell.exe',['-NoLogo','-NoProfile','-NonInteractive','-Command',PWSH],{
    encoding:'utf8',env:{...process.env,OPS_READER_FIXTURE:file},timeout:9000
  });
  if(r.error) throw r.error;
  if(![0,24].includes(r.status)) throw Error('unexpected PowerShell status '+r.status+': '+r.stderr);
  return {exclusive:r.status===0, probe:r.stdout.trim()};
}
async function legacy(file) {
  const rl=createInterface({input:createReadStream(file),crlfDelay:Infinity});
  const lines=[];
  for await(const line of rl){lines.push(line);if(lines.length===12)break;}
  rl.close();return lines;
}
async function fixed(file) {
  const stream=createReadStream(file),rl=createInterface({input:stream,crlfDelay:Infinity});
  const lines=[];
  try {for await(const line of rl){lines.push(line);if(lines.length===12)break;}}
  finally {
    const closed=stream.closed?Promise.resolve():new Promise(resolve=>stream.once('close',resolve));
    rl.close();stream.destroy();await closed;
  }
  return lines;
}
if(process.env.READER_CASE) {
  const which=process.env.READER_CASE;
  assert.ok(['none','held','legacy','fixed'].includes(which));
  const dir=mkdtempSync(join(tmpdir(),'reader-win-synthetic-'));
  const file=join(dir,'fixture.txt');
  const contents=Array.from({length:24000},(_,i)=>
    'line_'+String(i).padStart(6,'0')+':'+'x'.repeat(90)).join('\n');
  writeFileSync(file,contents);
  let held;
  try {
    if(which==='held') held=openSync(file,'r');
    const lines=which==='legacy'?await legacy(file):which==='fixed'?await fixed(file):[];
    if(which==='legacy'||which==='fixed')
      assert.deepEqual(lines,contents.split('\n').slice(0,12));
    console.log(JSON.stringify({case:which,platform:process.platform,
      node:process.version,lines:lines.length,...probe(file)}));
  } finally {
    if(held!==undefined) closeSync(held);
    try{rmSync(dir,{force:true,recursive:true});}
    catch(e){console.warn('cleanup deferred: '+e.code);}
  }
} else {
  const summary=[];
  for(const which of ['none','held','legacy','fixed']) {
    const r=spawnSync(process.execPath,[fileURLToPath(import.meta.url)],{
      encoding:'utf8',timeout:30000,env:{...process.env,READER_CASE:which}
    });
    if(r.status!==0)throw Error(which+' exit='+r.status+
      '\n'+r.stderr+'\n'+r.stdout);
    summary.push(JSON.parse(r.stdout.trim().split('\n').at(-1)));
  }
  const lookup=Object.fromEntries(summary.map(x=>[x.case,x]));
  assert.equal(lookup.none.exclusive,true,'unlocked control must allow exclusive open');
  assert.equal(lookup.held.exclusive,false,'known-open control must reject exclusive open');
  assert.equal(lookup.fixed.exclusive,true,'fixed reader must release handle on return');
  assert.equal(lookup.fixed.lines,12);
  assert.equal(lookup.legacy.lines,12);
  console.log(JSON.stringify({status:'PASS',platform:process.platform,
    node:process.version,legacy_observation:lookup.legacy.exclusive,
    corrected_observation:lookup.fixed.exclusive,cases:summary},null,2));
}
