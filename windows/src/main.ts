import {invoke} from '@tauri-apps/api/core';
import {demoSnapshot,isChinese,present,text,type Snapshot} from './presentation';
import './style.css';
const native=!!(window as unknown as {__TAURI_INTERNALS__?:unknown}).__TAURI_INTERNALS__;
let snapshot=demoSnapshot();let settings=false;let pending=false;let localError='';let preferencesEditing=false;
const root=document.querySelector<HTMLDivElement>('#app')!;
function element<K extends keyof HTMLElementTagNameMap>(tag:K,value?:string,cls?:string):HTMLElementTagNameMap[K] {
 const node=document.createElement(tag);if(value!==undefined)node.textContent=value;if(cls)node.className=cls;return node;
}
function label(key:string){return text(snapshot,key);}
function button(key:string,action:()=>Promise<void>|void,cls=''):HTMLButtonElement {
 const b=element('button',label(key),cls);b.type='button';b.onclick=()=>void run(action);return b;
}
async function run(action:()=>Promise<void>|void){if(pending)return;pending=true;localError='';try{await action();}catch(e){localError=typeof e==='object'&&e&&'code'in e?String(e.code):'http_error';}finally{pending=false;render();}}
async function command<T>(name:string,args?:Record<string,unknown>):Promise<T>{return invoke<T>(name,args);}
async function sync(){if(native && !pending && !preferencesEditing){const next=await command<Snapshot>('snapshot');if(JSON.stringify(next)!==JSON.stringify(snapshot)){snapshot=next;render();}}}
async function selectSource(source:string){
 if(native){snapshot=await command<Snapshot>('select_source',{source});}
 else {const prefs={...snapshot.preferences,source};snapshot=demoSnapshot(source);snapshot.preferences=prefs;}
}
function languageSelect(){
 const select=element('select');select.id='language';select.setAttribute('aria-label',label('language'));
 for(const [value,title] of [['system',label('system')],['en','English'],['zh','中文']]){const option=element('option',title);option.value=value;select.append(option);}
 select.value=snapshot.preferences.language;return select;
}
function render(){
 const focused=(document.activeElement as HTMLElement|null)?.id;
 root.replaceChildren();document.documentElement.lang=isChinese(snapshot)?'zh-Hans':'en';
 const shell=element('main',undefined,'shell');const header=element('header');const brand=element('div');
 brand.append(element('span','QUOTANEST','eyebrow'),element('h1',label('title')));header.append(brand,element('span',label('beta'),'badge'));shell.append(header);
 if(!native)shell.append(element('p',label('demo'),'demo'));
 if(settings){
  const back=button('back',()=>{settings=false;preferencesEditing=false;});back.id='back';shell.append(back,element('h2',label('settings')));
  const form=element('form');const language=languageSelect();const languageLabel=element('label',label('language'));languageLabel.htmlFor='language';form.append(languageLabel,language);
  const path=element('input');path.id='directory';path.value=snapshot.preferences.directory;const pathLabel=element('label',label('directory'));pathLabel.htmlFor='directory';form.append(pathLabel,path);
  const autostart=element('input');autostart.type='checkbox';autostart.id='autostart';autostart.checked=snapshot.preferences.autostart;
  const autoLabel=element('label',label('autostart'),'check');autoLabel.prepend(autostart);form.append(autoLabel);
  const save=button('save',async()=>{const preferences={...snapshot.preferences,language:language.value,directory:path.value,autostart:autostart.checked};snapshot=native?await command<Snapshot>('save_preferences',{preferences}):{...snapshot,preferences};});save.id='save';
  const scan=button('scan',async()=>{snapshot=native?await command<Snapshot>('discover',{directory:path.value}):snapshot;});scan.id='scan';form.append(save,scan,element('p',label('privacy'),'muted'));
  if(snapshot.discoveryError)form.append(element('p',label(snapshot.discoveryError.code),'error'));
  const update=element('section',undefined,'settings-section');update.append(element('h2',label('checkUpdate')),element('p',label(snapshot.updateStatus),'muted'));
  const check=button('checkUpdate',async()=>{if(native){await command('check_update');await syncAfter();}else{snapshot.updateStatus='current';}});check.id='check-update';update.append(check);
  if(snapshot.update){update.append(element('p',snapshot.update.version));const install=button('install',async()=>{if(native)await command('install_update');});install.id='install-update';install.disabled=snapshot.updateStatus==='downloading';update.append(install);}
  const quit=button('quit',async()=>{if(native)await command('quit');});quit.id='quit';shell.append(form,update,element('p',label('scope'),'muted'),quit);
 }else{
  const sourceLabel=element('label',label('source'));sourceLabel.htmlFor='source';const select=element('select');select.id='source';
  const codex=element('option',label('codex'));codex.value='codex';select.append(codex);
  for(const c of snapshot.connections){const option=element('option',`${c.name||'DeepSeek'} · ${c.harness==='claude'?'Claude Code':'Codex'}${c.supported?'':` · ${label('unsupported')}`}`);option.value=`api:${c.id}`;option.disabled=!c.supported;select.append(option);}
  if(!Array.from(select.options).some(o=>o.value===snapshot.preferences.source)){const option=element('option',label('source_missing'));option.value=snapshot.preferences.source;select.append(option);}
  select.value=snapshot.preferences.source;select.onchange=()=>void run(()=>selectSource(select.value));shell.append(sourceLabel,select);
  if(snapshot.preferences.source!=='codex')shell.append(element('p',label('configuration'),'muted'));
  const view=present(snapshot);const card=element('section',undefined,view.stale?'card stale':'card');card.setAttribute('aria-live','polite');
  card.append(element('span',snapshot.preferences.source==='codex'?label('codex'):`DeepSeek · ${label('api')}`,'eyebrow'),element('h2',view.name),element('div',view.amount,'amount'));
  if(snapshot.reading.data?.kind==='balance')for(const wallet of snapshot.reading.data.value){
   const group=element('dl');const items=[[label('available'),`${wallet.currency} ${wallet.total}`],[label('paid'),`${wallet.currency} ${wallet.toppedUp}`],[label('granted'),`${wallet.currency} ${wallet.granted}`]];for(const [k,v]of items)group.append(element('dt',k),element('dd',v));card.append(group);
  }
  if(snapshot.reading.data?.kind==='quota')for(const quota of snapshot.reading.data.value.windows){
   const window=element('div',undefined,'quota-window');const period=quota.minutes?`${quota.minutes>=1440?`${quota.minutes/1440}d`:quota.minutes>=60?`${quota.minutes/60}h`:`${quota.minutes}m`}`:label('window');
   window.append(element('p',`${period} · ${quota.remaining==null?'—':`${quota.remaining.toFixed(1)}% ${label('remaining')}`}`));
   if(quota.remaining!=null){const meter=element('progress');meter.max=100;meter.value=quota.remaining;meter.setAttribute('aria-label',period);window.append(meter);}
   if(quota.resetsAt)window.append(element('p',`${label('reset')}: ${new Date(quota.resetsAt*1000).toLocaleString(document.documentElement.lang)}`,'muted'));card.append(window);
  }
  if(view.stale)card.append(element('p',label('stale'),'error'));
  if(snapshot.reading.error)card.append(element('p',label(snapshot.reading.error.code),'error'));
  const updated=snapshot.reading.updated?`${label('updated')}: ${new Date(snapshot.reading.updated*1000).toLocaleTimeString(document.documentElement.lang)}`:label('never');
  card.append(element('p',updated,'muted'));const refresh=button(snapshot.reading.refreshing?'refreshing':'refresh',async()=>{if(native){await command('refresh');snapshot=await command<Snapshot>('snapshot');}} ,'primary');refresh.id='refresh';refresh.disabled=snapshot.reading.refreshing;card.append(refresh);shell.append(card);
  const footer=element('footer');const set=button('settings',()=>{settings=true;preferencesEditing=true;});set.id='settings';footer.append(element('span',label('everyMinute'),'muted'),set);shell.append(footer);
  if(!snapshot.connections.length){shell.append(element('p',label('empty'),'muted'),button('connect',async()=>{snapshot=native?await command<Snapshot>('discover',{directory:snapshot.preferences.directory}):snapshot;}));}
  if(snapshot.discoveryError)shell.append(element('p',label(snapshot.discoveryError.code),'error'));
 }
 if(localError)shell.append(element('p',label(localError),'error'));
 root.append(shell);if(focused)document.getElementById(focused)?.focus({preventScroll:true});
}
async function syncAfter(){snapshot=await command<Snapshot>('snapshot');}
async function start(){if(native){try{snapshot=await command<Snapshot>('snapshot');}catch{localError='http_error';}}render();setInterval(()=>void sync().catch(()=>{}),1000);}
void start();
