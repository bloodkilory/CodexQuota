'use strict';
// Calls the official Qoder WASM decoder, never the CLI entry point or model API.
const fs = require('node:fs');
const crypto = require('node:crypto');
const https = require('node:https');
const path = require('node:path');
const WASM_SHA256 = '6419471effa631519def7797d76d7ede38b9fcfa9a83c2148c8ef5d43355b43d';
function boundedRead(file, limit) {
  const fd = fs.openSync(file, 'r');
  try {
    if (!fs.fstatSync(fd).isFile()) throw Error('file');
    const data = Buffer.alloc(limit + 1);
    let size = 0, n;
    while (size < data.length && (n = fs.readSync(fd,data,size,data.length-size,null)) > 0) size += n;
    if (size > limit) throw Error('size');
    return data.subarray(0,size).toString('utf8');
  } finally { fs.closeSync(fd); }
}
function extractWasm(source) {
  // Version/region gate is deliberately strict. Future formats require review.
  if (!source.includes('vs="cn"==(TYs="global")')) throw Error('version');
  const match = /bAc="(AGFzbQ[A-Za-z0-9+/=]+)"/.exec(source);
  if (!match || match[1].length > 500000) throw Error('version');
  const bytes = Buffer.from(match[1],'base64');
  if (crypto.createHash('sha256').update(bytes).digest('hex') !== WASM_SHA256) throw Error('version');
  return bytes;
}
function decodeCredential(bytes, encrypted, key) {
  const module = new WebAssembly.Module(bytes);
  const heap = new Array(1024).fill(undefined); heap.push(undefined,null,true,false);
  const add = value => { heap.push(value); return heap.length-1; };
  let exports;
  const string = (p,n) => new TextDecoder('utf-8',{fatal:true}).decode(new Uint8Array(exports.memory.buffer,p,n));
  const functions = Object.create(null);
  for (const item of WebAssembly.Module.imports(module)) {
    if (item.module !== './qoder_auth_wasm_bg.js' || item.kind !== 'function') throw Error('abi');
    functions[item.name] = () => { throw Error('unsupported-import'); };
  }
  functions.__wbg_Error_2e59b1b37a9a34c3 = (p,n) => add(Error(string(p,n)));
  functions.__wbg___wbindgen_throw_81fc77679af83bc6 = () => { throw Error('decrypt'); };
  functions.__wbindgen_cast_0000000000000002 = (p,n) => add(string(p,n));
  functions.__wbindgen_object_drop_ref = i => { if (i >= 1028) heap[i] = undefined; };
  exports = new WebAssembly.Instance(module, {'./qoder_auth_wasm_bg.js':functions}).exports;
  const write = text => {
    const encoded = new TextEncoder().encode(text);
    const ptr = exports.__wbindgen_export2(encoded.length,1) >>> 0;
    new Uint8Array(exports.memory.buffer,ptr,encoded.length).set(encoded);
    return [ptr,encoded.length];
  };
  const ret = exports.__wbindgen_add_to_stack_pointer(-16);
  let output, length;
  try {
    exports.credential_storage_decrypt(ret,...write(encrypted),...write(key));
    const view = new DataView(exports.memory.buffer);
    if (view.getInt32(ret+12,true)) throw Error('decrypt');
    output = view.getUint32(ret,true); length = view.getUint32(ret+4,true);
    if (length > 65536) throw Error('size');
    return JSON.parse(string(output,length));
  } finally {
    exports.__wbindgen_add_to_stack_pointer(16);
    if (output !== undefined) exports.__wbindgen_export4(output,length,1);
  }
}
function browserToken(info, now = Date.now()/1000) {
  if (!info || info.login_method !== 'browser' || info.personal_access_token) throw Error('login');
  if (typeof info.expire_time !== 'number' || !Number.isFinite(info.expire_time) || info.expire_time <= now) throw Error('expired');
  const token = info.security_oauth_token || info.access_token;
  if (typeof token !== 'string' || token.length > 32768 || !/^[\x21-\x7e]+$/.test(token)) throw Error('login');
  return token;
}
function requestQuota(token) {
  return new Promise((resolve,reject) => {
    const request = https.get('https://openapi.qoder.sh/api/v2/quota/usage', {
      headers: { Authorization:`Bearer ${token}`, Accept:'application/json' },
      timeout:20000
    },response => {
      // No redirect handling, cookie storage, retries, token refresh, or inference.
      if (response.statusCode !== 200) { response.destroy(); reject(Error(response.statusCode === 401 ? 'expired' : 'network')); return; }
      const chunks=[]; let total=0;
      response.on('data', chunk => {
        total += chunk.length;
        if (total > 1048576) { response.destroy(); reject(Error('size')); } else chunks.push(chunk);
      });
      response.on('end',()=>resolve(Buffer.concat(chunks).toString('utf8')));
      response.on('error',()=>reject(Error('network')));
    });
    request.on('timeout',()=>request.destroy(Error('network')));
    request.on('error',()=>reject(Error('network')));
  });
}
async function main(bundle, home) {
  const bytes = extractWasm(boundedRead(bundle, 50*1024*1024));
  const root = path.join(home,'.qoder','.auth');
  const key = boundedRead(path.join(root,'machine_id'),4096).trim().slice(0,16);
  if (key.length !== 16) throw Error('login');
  const info = decodeCredential(bytes,boundedRead(path.join(root,'user'),131072),key);
  process.stdout.write(await requestQuota(browserToken(info)));
}
module.exports = {extractWasm,decodeCredential,browserToken,boundedRead};
if (require.main === module) {
  const timer=setTimeout(()=>process.exit(2),25000);
  main(process.argv[2],process.argv[3]).then(()=>clearTimeout(timer)).catch(error=>{
    const allowed=['version','expired','login','network','size'];
    // Only fixed status codes cross the process boundary; stderr is discarded by the parent.
    process.stdout.write(JSON.stringify({quotanest_error:allowed.includes(error.message) ? error.message : 'login'}));
    clearTimeout(timer);
  });
}
