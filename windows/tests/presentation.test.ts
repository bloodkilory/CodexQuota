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
