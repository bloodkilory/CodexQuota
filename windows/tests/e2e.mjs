// Real Tauri/WebView2 GUI checks through the standard WebDriver HTTP protocol.
// The --demo application argument keeps this suite independent of user credentials.
import {spawn,spawnSync} from 'node:child_process';
import {mkdir,writeFile,mkdtemp,readFile} from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
const resultDir=path.resolve('e2e-results');await mkdir(resultDir,{recursive:true});
const application=process.env.QUOTANEST_TEST_EXE||path.resolve('src-tauri/target/release/QuotaNest.exe');
const driver=spawn('msedgedriver',['--port=4444','--verbose',`--log-path=${path.join(resultDir,'webview-driver.log')}`],{stdio:['ignore','pipe','pipe']});
let log='';driver.stdout.on('data',v=>log+=v);driver.stderr.on('data',v=>log+=v);
let session;
const profile=await mkdtemp(path.join(os.tmpdir(),'quotanest-webview-'));
const app=spawn(application,['--demo'],{env:{...process.env,WEBVIEW2_USER_DATA_FOLDER:profile,WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS:'--remote-debugging-port=9222'},stdio:['ignore','pipe','pipe'],windowsHide:true});
let appLog='';app.stdout.on('data',v=>appLog+=v);app.stderr.on('data',v=>appLog+=v);
app.on('exit',code=>appLog+=`\nNative exit: ${code}`);
async function request(method,route,body){const r=await fetch(`http://127.0.0.1:4444${route}`,{method,headers:{'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(45000)});const v=await r.json();if(!r.ok||v.value?.error)throw new Error(JSON.stringify(v));return v.value;}
async function wait(action){let last;for(let n=0;n<80;n++){try{return await action();}catch(e){last=e;await new Promise(r=>setTimeout(r,250));}}throw last;}
async function find(css){const v=await request('POST',`/session/${session}/element`,{using:'css selector',value:css});return v['element-6066-11e4-a52e-4f735466cecf'];}
async function execute(script,args=[]){return request('POST',`/session/${session}/execute/sync`,{script,args});}
async function click(css){const id=await find(css);await request('POST',`/session/${session}/element/${id}/click`,{});}
async function select(css,value){
 // Native <select> interactions use WebDriver's element click, including options.
 const id=await find(`${css} option[value="${value}"]`);await request('POST',`/session/${session}/element/${id}/click`,{});
}
async function screenshot(name){const png=await request('GET',`/session/${session}/screenshot`);await writeFile(path.join(resultDir,`${name}.png`),Buffer.from(png,'base64'));}
try{
 await wait(()=>request('GET','/status'));
 await wait(async()=>{const r=await fetch('http://127.0.0.1:9222/json/version',{signal:AbortSignal.timeout(1000)});assert.equal(r.status,200);});
 const created=await request('POST','/session',{capabilities:{alwaysMatch:{browserName:'webview2','ms:edgeOptions':{debuggerAddress:'127.0.0.1:9222'}}}});session=created.sessionId;
 await wait(async()=>{
  const handles=await request('GET',`/session/${session}/window/handles`);
  for(const handle of handles){await request('POST',`/session/${session}/window`,{handle});if(await execute('return !!document.querySelector("#back")'))return;}
  throw new Error('Main controls WebView not ready');
 });
 await wait(()=>find('#back'));await click('#back');
 await wait(async()=>assert.match(await execute('return document.querySelector(".amount")?.textContent || ""'),/18.60/));
 // Exercise IPC reads while the worker updates the native tray.
 for(let n=0;n<10;n++){await click('#refresh');await new Promise(r=>setTimeout(r,150));await wait(async()=>assert.match(await execute('return document.querySelector(".amount")?.textContent || ""'),/18.60/));}
 await screenshot('windows-deepseek-en');
 await select('#display','USD');
 await wait(async()=>assert.match(await execute('return document.querySelector(".amount")?.textContent || ""'),/USD 3.20/));
 await select('#display','CNY');
 await select('#source','codex');
 await wait(async()=>assert.match(await execute('return document.querySelector(".amount")?.textContent || ""'),/76%/));
 await screenshot('windows-codex-en');
 await select('#display','10080');
 await wait(async()=>assert.match(await execute('return document.querySelector(".amount")?.textContent || ""'),/62%/));
 await select('#source','claude');
 await wait(async()=>assert.match(await execute('return document.querySelector(".amount")?.textContent || ""'),/82%/));
 assert.match(await execute('return document.body.innerText'),/Sonnet weekly/);
 assert.match(await execute('return document.body.innerText'),/Opus weekly/);
 assert.equal(await execute('return document.querySelector(".card .eyebrow").textContent'),'Claude · Subscription quota');
 await screenshot('windows-claude-en');
 await select('#display','10080');
 await wait(async()=>assert.match(await execute('return document.querySelector(".amount")?.textContent || ""'),/39%/));
 await select('#source','codex');
 await wait(async()=>assert.match(await execute('return document.querySelector(".amount")?.textContent || ""'),/62%/));
 await select('#source','claude');
 await wait(async()=>assert.match(await execute('return document.querySelector(".amount")?.textContent || ""'),/39%/));
 await click('#settings');await select('#language','zh');await click('#save');
 await wait(async()=>assert.equal(await execute('return document.documentElement.lang'),'zh-Hans'));
 await click('#back');
 await wait(async()=>assert.match(await execute('return document.querySelector(".amount")?.textContent || ""'),/39%/));
 assert.match(await execute('return document.body.innerText'),/Sonnet 周额度/);
 await screenshot('windows-claude-zh');
 await select('#source','api:claude|demo');
 await wait(async()=>assert.match(await execute('return document.querySelector(".amount")?.textContent || ""'),/18.60/));
 assert.equal(await execute('return document.querySelector("#refresh").textContent'),'立即刷新');
 await screenshot('windows-deepseek-zh');
 await click('#settings');await click('#check-update');
 await wait(async()=>assert.match(await execute('return document.body.innerText'),/暂无更新的 Windows 正式版/));
 await screenshot('windows-settings-zh');
 // Exercise the actual native notification icon with real Windows pointer input.
 await execute("return window.__TAURI_INTERNALS__.invoke('select_source',{source:'claude'})");
 await execute("return window.__TAURI_INTERNALS__.invoke('select_display',{value:'300'})");
 await execute("return window.__TAURI_INTERNALS__.invoke('hide_controls')");
 function native(mode,options={}){const args=['-NoProfile','-File','scripts/native-tray.ps1','-Mode',mode];for(const [k,v] of Object.entries(options))args.push(`-${k}`,String(v));const r=spawnSync('powershell.exe',args,{encoding:'utf8',windowsHide:true});if(r.status!==0)throw new Error(r.stderr||r.stdout);}
 native('Prepare');const rect=JSON.parse((await readFile(path.join(resultDir,'native-tray-rect.json'),'utf8')).replace(/^\uFEFF/,''));
 native('Move',{X:rect.x+rect.w/2,Y:rect.y+rect.h/2});
 let bounds=await execute("return window.__TAURI_INTERNALS__.invoke('demo_tray_bounds')");await writeFile(path.join(resultDir,'hover-bounds.json'),JSON.stringify(bounds));
 if(!bounds.visible){native('Click',{X:rect.x+rect.w/2,Y:rect.y+rect.h/2});await writeFile(path.join(resultDir,'tray-click-diagnostic.json'),JSON.stringify(await execute("return window.__TAURI_INTERNALS__.invoke('demo_tray_bounds')")));}
 assert.equal(bounds.visible,true,'hover card should appear');
 assert.ok(bounds.card.w<=260&&bounds.card.h<=160,'hover card must match the compact target');
 assert.ok(bounds.card.y+bounds.card.h<=rect.y||bounds.card.y>=rect.y+rect.h,'hover card must not cover the tray icon');
 const left=Math.min(bounds.card.x,rect.x)-8,top=Math.min(bounds.card.y,rect.y)-8;
 native('Capture',{X:left,Y:top,W:Math.max(bounds.card.x+bounds.card.w,rect.x+rect.w)-left+8,H:Math.max(bounds.card.y+bounds.card.h,rect.y+rect.h)-top+8,Name:'windows-tray-claude'});
 native('Capture',{X:rect.x,Y:rect.y,W:rect.w,H:rect.h,Name:'windows-tray-icon'});
 const focus=JSON.parse((await readFile(path.join(resultDir,'native-focus.json'),'utf8')).replace(/^\uFEFF/,''));assert.notEqual(focus.foreground,'QuotaNest Usage','hover must not steal focus');
 native('Move',{X:bounds.card.x+bounds.card.w/2,Y:bounds.card.y+40});
 assert.equal((await execute("return window.__TAURI_INTERNALS__.invoke('demo_tray_bounds')")).visible,true,'moving into card keeps it visible');
 native('Move',{X:100,Y:100});
 assert.equal((await execute("return window.__TAURI_INTERNALS__.invoke('demo_tray_bounds')")).visible,false,'moving away dismisses card');
 native('Click',{X:rect.x+rect.w/2,Y:rect.y+rect.h/2});
 await wait(()=>find('#language'));assert.equal((await execute("return window.__TAURI_INTERNALS__.invoke('demo_tray_bounds')")).visible,false);
 assert.ok(await execute('return document.querySelector("#close").getBoundingClientRect().top >= 0'),'settings reopens at the top');
 await screenshot('windows-tray-click-settings');
 // Check the rendered hover WebView too: a small window must retain all rows without clipping.
 for(const handle of await request('GET',`/session/${session}/window/handles`)){
  await request('POST',`/session/${session}/window`,{handle});
  if(!await execute('return !!document.querySelector(".hover-shell")'))continue;
  const layout=await execute('const shell=document.querySelector(".hover-shell");return {width:innerWidth,height:innerHeight,contentHeight:shell.getBoundingClientRect().height,scrollWidth:document.querySelector("#app").scrollWidth,rows:document.querySelectorAll(".hover-row").length,text:shell.innerText}');
  await writeFile(path.join(resultDir,'compact-layout.json'),JSON.stringify(layout));
  assert.equal(layout.width,240);assert.ok(layout.contentHeight<=layout.height,'all compact quota rows fit vertically');assert.ok(layout.scrollWidth<=layout.width,'compact hover has no horizontal clipping');assert.equal(layout.rows,4);assert.match(layout.text,/Sonnet/);assert.match(layout.text,/Opus/);
  break;
 }
 await writeFile(path.join(resultDir,'result.json'),JSON.stringify({passed:true,checks:['native-launch','deepseek-demo','source-switch','codex-demo','claude-demo','claude-model-groups','period-selection-retained','currency-selection','language-switch','settings-update-check','native-tray-hover','hover-preserves-focus','hover-card-retention','tray-click-settings'],credentials:'synthetic only'},null,2));
 console.log('PASS native Windows WebView2 GUI: source switch, language, balances, quotas, settings');
}catch(error){spawnSync('powershell.exe',['-NoProfile','-File','scripts/capture-diagnostics.ps1'],{stdio:'inherit'});if(session)await screenshot('failure').catch(()=>{});throw error;}
finally{if(session)await request('DELETE',`/session/${session}`).catch(()=>{});driver.kill();app.kill();spawnSync('taskkill.exe',['/IM','QuotaNest.exe','/T','/F'],{windowsHide:true});await writeFile(path.join(resultDir,'native-app.log'),appLog);await writeFile(path.join(resultDir,'driver.log'),log);}
