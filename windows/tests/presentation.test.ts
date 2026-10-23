import test from 'node:test';
import assert from 'node:assert/strict';
import { text, present, demoSnapshot } from '../src/presentation.js';
test('Chinese and English render the same selected source without network calls',()=>{
 const s=demoSnapshot(); s.preferences.language='en';
 assert.equal(text(s,'refresh'),'Refresh now'); assert.match(present(s).amount,/18.60/);
 s.preferences.language='zh'; assert.equal(text(s,'refresh'),'立即刷新');
 assert.match(present(demoSnapshot('codex')).amount,/76/);
});
test('unknown is never zero and stale reading keeps its timestamp',()=>{
 const s=demoSnapshot(); s.reading.data=null; assert.equal(present(s).amount,'—');
 s.reading=demoSnapshot().reading; s.reading.error={code:'network',retryAt:null};
 assert.equal(present(s).stale,true); assert.match(present(s).amount,/18.60/); assert.equal(present(s).updated,s.reading.updated);
});
test('configuration names remain data and do not become markup',()=>{
 const s=demoSnapshot();s.connections[0].name='<img src=x onerror=alert(1)>';
 assert.equal(present(s).name,s.connections[0].name);
});
test('Claude is distinct from Claude Code API connections and weekly summary uses tightest group',()=>{
 const s=demoSnapshot('claude');
 assert.equal(present(s).name,'Claude');assert.equal(present(s).amount,'82%');
 s.preferences.display={claude:'10080'};assert.equal(present(s).amount,'39%');
 assert.equal(text(s,'claude'),'Claude · Subscription quota');
 s.preferences.language='zh';assert.match(text(s,'claude'),/套餐/);
});
test('missing primary duration uses the first explicit period, matching tray summary',()=>{
 const s=demoSnapshot('codex');s.reading.data={kind:'quota',value:{plan:null,windows:[{remaining:80,minutes:null,resetsAt:null},{remaining:50,minutes:10080,resetsAt:null}]}};
 assert.equal(present(s).amount,'50%');assert.equal(present(s).selected,'10080');
});
