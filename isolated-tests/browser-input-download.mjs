import {spawn} from 'node:child_process';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync,existsSync,readdirSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
const sha=b=>createHash('sha256').update(b).digest('hex');
const report={schema:'ops099.browser-input-download/1',started_utc:new Date().toISOString(),status:'NOT_COMPLETED',scope:'Synthetic offline browser fixture only; no live website, native OPS computer, account, network submission or model call.',steps:[],errors:[]};
const expected={schema:'ops.browser-receipt-fixture/1',title:'Public test: source handoff',notes:'Synthetic only: café, "quoted text" & <literal>.\nSecond line: preserve exactly.'};
const html=`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>OPS browser return test — synthetic only</title><style>body{font:16px system-ui;max-width:620px;margin:20px auto;padding:0 20px;color:#16202a;background:white}h1{font-size:24px}label{display:block;margin-top:14px;font-weight:600}input,textarea{box-sizing:border-box;width:100%;font:16px system-ui;padding:9px;margin:5px 0;border:1px solid #687787;border-radius:4px}textarea{height:100px}button{font:15px system-ui;padding:9px 15px;margin:10px 8px 0 0}#status{margin:14px 0;font-weight:600}.note{font-size:13px;color:#384859}</style><h1>Browser file round trip</h1><p class="note">Isolated test fixture · Synthetic data · No website submission</p><form id="fixture"><label for="title">Receipt title</label><input id="title" required maxlength="120"><label for="notes">Notes</label><textarea id="notes" maxlength="1000"></textarea><button type="button" id="download" disabled>Download JSON</button><button type="button" id="clear">Clear fields</button><label for="import">Read back the downloaded file</label><input id="import" type="file" accept=".json,application/json"><p id="status" role="status">Enter a title to enable the local download.</p></form><script>
const t=document.getElementById('title'),n=document.getElementById('notes'),d=document.getElementById('download'),f=document.getElementById('import'),s=document.getElementById('status');
t.addEventListener('input',()=>d.disabled=!t.value.trim());
d.addEventListener('click',()=>{if(!t.value.trim())return;const data={schema:'ops.browser-receipt-fixture/1',title:t.value,notes:n.value};const url=URL.createObjectURL(new Blob([JSON.stringify(data,null,2)+'\\n'],{type:'application/json'}));const a=document.createElement('a');a.href=url;a.download='ops-browser-fixture.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);s.textContent='Download requested — synthetic data only.'});
document.getElementById('clear').addEventListener('click',()=>{t.value='';n.value='';f.value='';d.disabled=true;s.textContent='Fields cleared.'});
f.addEventListener('change',async()=>{try{if(f.files.length!==1||f.files[0].size>4096)throw Error('File bound');const data=JSON.parse(await f.files[0].text());if(data.schema!=='ops.browser-receipt-fixture/1'||typeof data.title!=='string'||typeof data.notes!=='string'||data.title.length>120||data.notes.length>1000)throw Error('Schema');t.value=data.title;n.value=data.notes;d.disabled=!t.value.trim();s.textContent='Downloaded JSON reloaded locally.'}catch{s.textContent='Import refused.'}});
</script></html>`;
report.fixture_sha256=sha(Buffer.from(html));
const root=mkdtempSync(join(tmpdir(),'ops-browser-input-'));const home=join(root,'home'),downloads=join(root,'downloads');mkdirSync(home);mkdirSync(downloads);
const args=['--headless=new','--remote-debugging-pipe','--no-first-run','--no-default-browser-check','--disable-background-networking','--disable-default-apps','--disable-sync','--disable-extensions','--window-size=720,650',`--user-data-dir=${join(root,'profile')}`,'about:blank'];
if(process.getuid()===0)throw Error('Refusing root');
const browser=spawn('/opt/google/chrome/chrome',args,{detached:true,stdio:['ignore','ignore','pipe','pipe','pipe'],env:{PATH:'/usr/bin:/bin',HOME:home,TMPDIR:root,LANG:'C.UTF-8'}});
let stderr='',buffer=Buffer.alloc(0),sequence=0,closed=false,fatal=null,session;const pending=new Map(),events=[];const returned=[];
browser.stderr.on('data',b=>{stderr=(stderr+b.toString()).slice(-1500)});browser.on('error',e=>{fatal=e});
browser.on('exit',()=>{closed=true;for(const p of pending.values()){clearTimeout(p.timer);p.reject(Error('Browser exited'))}pending.clear()});
function send(method,params={},sessionId){if(fatal)return Promise.reject(fatal);if(closed)return Promise.reject(Error('Closed browser'));const id=++sequence;return new Promise((resolve,reject)=>{const timer=setTimeout(()=>{pending.delete(id);reject(Error('CDP timeout '+method))},10000);pending.set(id,{resolve,reject,timer});browser.stdio[3].write(JSON.stringify({id,method,params,...(sessionId?{sessionId}:{})})+'\0',e=>{if(e){clearTimeout(timer);pending.delete(id);reject(e)}})})}
browser.stdio[4].on('data',chunk=>{buffer=Buffer.concat([buffer,chunk]);if(buffer.length>1024*1024){fatal=Error('Protocol bound');browser.kill('SIGTERM');return}let end;while((end=buffer.indexOf(0))>=0){const b=buffer.subarray(0,end);buffer=buffer.subarray(end+1);if(!b.length)continue;let e;try{e=JSON.parse(b.toString())}catch{fatal=Error('Protocol parse');continue}if(e.id&&pending.has(e.id)){const p=pending.get(e.id);pending.delete(e.id);clearTimeout(p.timer);e.error?p.reject(Error(e.error.message)):p.resolve(e.result)}else if(['Browser.downloadWillBegin','Browser.downloadProgress','Network.requestWillBeSent'].includes(e.method)&&events.length<100)events.push(e)}});
async function value(expression){const r=await send('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true},session);if(r.exceptionDetails)throw Error('Page evaluation exception');return r.result.value}
async function ready(){for(let i=0;i<40;i++){if(fatal)throw fatal;if(await value('document.readyState === "complete" && !!document.body'))return;await delay(100)}throw Error('Readiness timeout')}
function check(name,ok,detail){report.steps.push({name,passed:!!ok,detail});if(!ok)throw Error(name)}
async function click(id){const p=await value(`(()=>{const e=document.getElementById(${JSON.stringify(id)});if(!e||e.disabled)return null;e.scrollIntoView({block:'center'});const r=e.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()`);if(!p)throw Error('Unavailable control '+id);await send('Input.dispatchMouseEvent',{type:'mousePressed',button:'left',clickCount:1,...p},session);await send('Input.dispatchMouseEvent',{type:'mouseReleased',button:'left',clickCount:1,...p},session)}
async function type(id,text){await click(id);await send('Input.insertText',{text},session)}
function returnFile(name,b){if(b.length>45000)throw Error('Return file bound');returned.push({name,bytes:b.length,sha256:sha(b),base64:b.toString('base64')})}
try{
 report.browser=await send('Browser.getVersion');const t=await send('Target.createTarget',{url:'about:blank'});session=(await send('Target.attachToTarget',{targetId:t.targetId,flatten:true})).sessionId;await send('Page.enable',{},session);await send('Runtime.enable',{},session);
 await send('Page.navigate',{url:'chrome://sandbox'},session);await ready();report.sandbox_text=await value('document.body.innerText');check('sandbox_enabled',/adequately sandboxed/i.test(report.sandbox_text)&&/Seccomp-BPF sandbox\s+Yes/i.test(report.sandbox_text),'Browser native sandbox report; no sandbox-disabling flags');
 await send('Network.enable',{},session);await send('Network.setBlockedURLs',{urls:['http://*','https://*','ws://*','wss://*']},session);
 await send('Browser.setDownloadBehavior',{behavior:'allowAndName',downloadPath:downloads,eventsEnabled:true});
 await send('Page.navigate',{url:'data:text/html;charset=utf-8,'+encodeURIComponent(html)},session);await ready();
 check('empty_title_disables_download',await value('document.getElementById("download").disabled'),'Isolated fixture only');
 await type('title',expected.title);await type('notes',expected.notes);
 const fields=await value('({title:document.getElementById("title").value,notes:document.getElementById("notes").value})');check('actual_browser_text_entry',fields.title===expected.title&&fields.notes===expected.notes,'Input.insertText and independent DOM readback preserve Unicode, quotes and newline');
 await click('download');let done;
 for(let i=0;i<70;i++){done=events.find(e=>e.method==='Browser.downloadProgress'&&e.params.state==='completed');if(done)break;await delay(100)}
 check('browser_download_completed',!!done,'Browser downloadProgress completion event');const guid=done.params.guid;if(!/^[0-9a-f-]{36}$/i.test(guid))throw Error('Unexpected download identifier');const file=join(downloads,guid);const bytes=readFileSync(file);if(bytes.length>4096)throw Error('Downloaded size bound');const got=JSON.parse(bytes.toString('utf8'));
 check('downloaded_file_matches_input',JSON.stringify(got)===JSON.stringify(expected),'Actual downloaded file bytes, not a separately regenerated expected file');returnFile('browser-generated-fixture.json',bytes);
 await click('clear');check('first_clear',await value('!document.getElementById("title").value&&!document.getElementById("notes").value&&document.getElementById("download").disabled'),'Existing fixture Clear control');
 const doc=await send('DOM.getDocument',{},session);const q=await send('DOM.querySelector',{nodeId:doc.root.nodeId,selector:'#import'},session);await send('DOM.setFileInputFiles',{nodeId:q.nodeId,files:[file]},session);
 for(let i=0;i<40;i++){if(await value('document.getElementById("status").textContent === "Downloaded JSON reloaded locally."'))break;await delay(100)}
 check('download_reimport_matches',await value(`document.getElementById('title').value===${JSON.stringify(expected.title)}&&document.getElementById('notes').value===${JSON.stringify(expected.notes)}`),'File input reads only the just-downloaded synthetic JSON; no network upload');
 await value('window.scrollTo(0,0)');await delay(100);const shot=await send('Page.captureScreenshot',{format:'jpeg',quality:35,captureBeyondViewport:false},session);returnFile('browser-roundtrip.jpg',Buffer.from(shot.data,'base64'));
 await click('clear');check('final_clear',await value('!document.getElementById("title").value&&!document.getElementById("notes").value&&!document.getElementById("import").value&&document.getElementById("download").disabled'),'Both text inputs and selected file cleared');
 report.http_requests_observed=events.filter(e=>e.method==='Network.requestWillBeSent'&&/^https?:/.test(e.params.request.url)).map(e=>({method:e.params.request.method,url:e.params.request.url}));check('no_fixture_http_requests',report.http_requests_observed.length===0,'Page CDP observation; not a process-wide packet capture');
 report.downloaded_files=readdirSync(downloads).length;report.status='INPUT_DOWNLOAD_REIMPORT_CLEAR_PASS';
}catch(e){report.errors.push(e.message);report.status='FAILED_OR_BLOCKED';process.exitCode=1}
finally{
 try{if(!closed)await send('Browser.close')}catch{}
 for(let i=0;i<30&&!closed;i++)await delay(100);
 const alive=()=>{try{process.kill(-browser.pid,0);return true}catch(e){if(e.code==='ESRCH')return false;throw e}};
 if(Number.isInteger(browser.pid)&&browser.pid>1&&alive()){process.kill(-browser.pid,'SIGTERM');for(let i=0;i<30&&alive();i++)await delay(100)}
 report.owned_process_group_gone=Number.isInteger(browser.pid)&&browser.pid>1&&!alive();
 if(report.owned_process_group_gone){rmSync(root,{recursive:true,force:true});report.owned_profile_and_downloads_removed=!existsSync(root)}else{report.errors.push('Cleanup unverified');process.exitCode=1}
 report.files=returned.map(({base64,...meta})=>meta);report.finished_utc=new Date().toISOString();if(report.errors.length)report.stderr_tail=stderr;
 console.log('BEGIN_BROWSER_ROUNDTRIP_RESULT');console.log(JSON.stringify(report,null,2));console.log('END_BROWSER_ROUNDTRIP_RESULT');
 for(const f of returned){console.log('BEGIN_RETURNED_PUBLIC_FILE '+f.name+' '+f.bytes+' '+f.sha256);console.log(f.base64);console.log('END_RETURNED_PUBLIC_FILE '+f.name)}
}
