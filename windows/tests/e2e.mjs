// Real Tauri/WebView2 GUI checks through the standard WebDriver HTTP protocol.
// The --demo application argument keeps this suite independent of user credentials.
import {spawn,spawnSync} from 'node:child_process';
import {mkdir,writeFile,mkdtemp} from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
const resultDir=path.resolve('e2e-results');await mkdir(resultDir,{recursive:true});
const application=process.env.QUOTANEST_TEST_EXE||path.resolve('src-tauri/target/release/QuotaNest.exe');
const driver=spawn('msedgedriver',['--port=4444','--verbose',`--log-path=${path.join(resultDir,'webview-driver.log')}`],{stdio:['ignore','pipe','pipe']});
let log='';driver.stdout.on('data',v=>log+=v);driver.stderr.on('data',v=>log+=v);
let session;
const profile=await mkdtemp(path.join(os.tmpdir(),'quotanest-webview-'));
const app=spawn(application,['--demo'],{env:{...process.env,WEBVIEW2_USER_DATA_FOLDER:profile,WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS:'--remote-debugging-port=9222'},stdio:['ignore','pipe','pipe']});
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
 await wait(async()=>assert.match(await execute('return document.querySelector(".amount")?.textContent || ""'),/18.60/));
 // Exercise IPC reads while the worker updates the native tray.
 for(let n=0;n<10;n++){await click('#refresh');await new Promise(r=>setTimeout(r,150));await wait(async()=>assert.match(await execute('return document.querySelector(".amount")?.textContent || ""'),/18.60/));}
 await screenshot('windows-deepseek-en');
 await select('#source','codex');
 await wait(async()=>assert.match(await execute('return document.querySelector(".amount")?.textContent || ""'),/76%/));
 await screenshot('windows-codex-en');
 await click('#settings');await select('#language','zh');await click('#save');
 await wait(async()=>assert.equal(await execute('return document.documentElement.lang'),'zh-Hans'));
 await click('#back');await select('#source','api:claude|demo');
 await wait(async()=>assert.match(await execute('return document.querySelector(".amount")?.textContent || ""'),/18.60/));
 assert.equal(await execute('return document.querySelector("#refresh").textContent'),'立即刷新');
 await screenshot('windows-deepseek-zh');
 await click('#settings');await click('#check-update');
 await wait(async()=>assert.match(await execute('return document.body.innerText'),/暂无更新的 Windows 正式版/));
 await screenshot('windows-settings-zh');
 await writeFile(path.join(resultDir,'result.json'),JSON.stringify({passed:true,checks:['native-launch','deepseek-demo','source-switch','codex-demo','language-switch','settings-update-check'],credentials:'synthetic only'},null,2));
 console.log('PASS native Windows WebView2 GUI: source switch, language, balances, quotas, settings');
}catch(error){spawnSync('powershell.exe',['-NoProfile','-File','scripts/capture-diagnostics.ps1'],{stdio:'inherit'});if(session)await screenshot('failure').catch(()=>{});throw error;}
finally{if(session)await request('DELETE',`/session/${session}`).catch(()=>{});driver.kill();app.kill();await writeFile(path.join(resultDir,'native-app.log'),appLog);await writeFile(path.join(resultDir,'driver.log'),log);}
