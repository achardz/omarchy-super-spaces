// node --test tests/clipboard.test.js (no packages; all clipboard I/O is mocked)
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const os = require('node:os');
const { spawnSync } = require('node:child_process');
const repo = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(repo, 'Launcher.qml'), 'utf8');
function qmlFunction(name) {
  const start = source.indexOf('  function ' + name + '(');
  assert.notEqual(start, -1);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}
// Safe.js is a QML ".pragma library"; load its functions as a plain object.
const Safe = {};
new Function('exports', fs.readFileSync(path.join(repo, 'Safe.js'), 'utf8').replace(/^\.pragma library\s*$/m, '')
  + '\nexports.shown = shown; exports.monitorName = monitorName;')(Safe);
function launcher() {
  let rows = [];
  const proc = { running: false, snapshot: '', command: [] };
  const context = { maxClips: 50, movingWindow: '', binDir: path.join(repo, 'bin'), clipPaste: proc,
    dismiss() {}, clampSelection() {},
    displayModel: { get count() { return rows.length; }, get(i) { return rows[i]; },
      append(row) { rows.push({...row}); }, set(i,row) { rows[i] = {...row}; }, remove(i,n) { rows.splice(i,n); } },
    Quickshell: { env() { return ''; }, execDetached() {} } };
  context.root = context;
  context.Safe = Safe;
  vm.createContext(context);
  vm.runInContext(['terms', 'matchesAll', 'shownText', 'clipRows', 'showRows', 'useClip', 'pathQuery', 'typedPath', 'activate'].map(qmlFunction).join('\n'), context);
  return context;
}
const secret = {type:'text', text:'SYNTHETIC_PRIVATE'};
const benign = {type:'text', text:'PUBLIC_HELLO'};
const fresh = {type:'text', text:'NEW_COPY'};
for (const [name, history] of Object.entries({prepend:[fresh,secret,benign], reorder:[benign,secret], delete:[secret], clear:[], image:[fresh,{type:'image',path:'/synthetic.png',mime:'image/png'}]})) {
  test('rendered selection is immutable after ' + name, () => {
    const q = launcher(); q.clips=[secret,benign]; q.showRows(q.clipRows('PUBLIC_HELLO'));
    const payload = q.displayModel.get(0).payload;
    q.clips=history; q.activate(0,false);
    assert.deepEqual(JSON.parse(payload), benign);
    assert.equal(q.clipPaste.snapshot, payload);
    assert.deepEqual(Array.from(q.clipPaste.command),[path.join(repo,'bin','clipboard-paste')]);
  });
}
test('Shift+Enter uses same snapshot, and repeated activation cannot overwrite pending input', () => {
  const q=launcher(); q.clips=[benign]; q.showRows(q.clipRows('')); q.activate(0,true);
  const saved=q.clipPaste.snapshot;
  assert.equal(q.clipPaste.command[1],'--copy-only');
  q.useClip(JSON.stringify(secret),false);
  assert.equal(q.clipPaste.snapshot,saved);
});
function helper(entry, options={}) {
  const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'super-spaces-clipboard-'));
  try {
    fs.mkdirSync(path.join(tmp,'bin'));
    for (const [name, body] of Object.entries({
      'wl-copy':'cat > "$TEST_CAPTURE"\nexit "${TEST_COPY_EXIT:-0}"',
      'wtype':'printf "%s\\n" "$*" > "$TEST_KEYS"',
      'sleep':':'
    })) fs.writeFileSync(path.join(tmp,'bin',name),'#!/bin/bash\n'+body+'\n',{mode:0o700});
    // Mutating disk history cannot influence a snapshot-based helper.
    fs.mkdirSync(path.join(tmp,'.local/state/omarchy'),{recursive:true});
    fs.writeFileSync(path.join(tmp,'.local/state/omarchy/clipboard-history.json'),JSON.stringify([secret]));
    const image=path.join(tmp,'image.png'); fs.writeFileSync(image,'SYNTHETIC_IMAGE_BYTES');
    if(entry && entry.path === '@image')entry={...entry,path:image};
    const result=spawnSync(path.join(repo,'bin/clipboard-paste'),options.copy?['--copy-only']:[],{
      input:(typeof entry==='string'?entry:JSON.stringify(entry))+'\n', encoding:'utf8',
      env:{...process.env,HOME:tmp,PATH:path.join(tmp,'bin')+':'+process.env.PATH,TEST_CAPTURE:path.join(tmp,'copied'),TEST_KEYS:path.join(tmp,'keys'),TEST_COPY_EXIT:options.fail?'1':'0'},timeout:3000});
    assert.equal(result.error, undefined);
    return {status:result.status,error:result.error,stderr:result.stderr,
      copied:fs.existsSync(path.join(tmp,'copied'))?fs.readFileSync(path.join(tmp,'copied'),'utf8'):null,
      pasted:fs.existsSync(path.join(tmp,'keys'))};
  } finally {fs.rmSync(tmp,{recursive:true,force:true});}
}
for(const text of ['PUBLIC_HELLO','--option-looking\nไทย 🧪\n','  whitespace\n\n', 'x'.repeat(100000)]) {
  test('helper preserves exact selected text ('+text.length+' chars) regardless of disk history',()=>{
    const r=helper({type:'text',text}); assert.equal(r.status,0); assert.equal(r.copied,text); assert.equal(r.pasted,true);
  });
}
test('copy-only never sends paste',()=>{const r=helper(benign,{copy:true});assert.equal(r.status,0);assert.equal(r.copied,benign.text);assert.equal(r.pasted,false);});
test('image snapshot copies selected file',()=>{const r=helper({type:'image',path:'@image',mime:'image/png'});assert.equal(r.status,0);assert.equal(r.copied,'SYNTHETIC_IMAGE_BYTES');assert.equal(r.pasted,true);});
for(const entry of ['{bad','1',null,{}, {type:'text',text:3},{type:'text',text:''},{type:'image',path:'/missing-synthetic-file',mime:'image/png'},{type:'image',path:'@image',mime:'--invalid'}]) {
  test('invalid/missing entry fails without copying or pasting: '+JSON.stringify(entry),()=>{const r=helper(entry);assert.notEqual(r.status,0);assert.equal(r.copied,null);assert.equal(r.pasted,false);});
}
test('failed clipboard write never pastes previous clipboard',()=>{const r=helper(benign,{fail:true});assert.notEqual(r.status,0);assert.equal(r.pasted,false);});
test('identical truncated previews still bind different full text',()=>{
  const q=launcher();const prefix='x'.repeat(95);
  q.clips=[{type:'text',text:prefix+'A'},{type:'text',text:prefix+'B'}];q.showRows(q.clipRows(''));
  assert.equal(q.displayModel.get(0).title,q.displayModel.get(1).title);
  assert.notEqual(q.displayModel.get(0).payload,q.displayModel.get(1).payload);
  q.activate(1,false);assert.equal(JSON.parse(q.clipPaste.snapshot).text,prefix+'B');
  assert.ok(q.clipPaste.command.every(arg=>!arg.includes(prefix)));
});
test('image row retains selected path/mime when history changes to text',()=>{
  const q=launcher();const entry={type:'image',path:'/synthetic-original.png',mime:'image/png'};
  q.clips=[entry];q.showRows(q.clipRows(''));q.clips=[secret];q.activate(0,true);
  assert.deepEqual(JSON.parse(q.clipPaste.snapshot),entry);
});
test('rebuilding from new history creates fresh snapshots',()=>{
  const q=launcher();q.clips=[secret,benign];q.showRows(q.clipRows('PUBLIC_HELLO'));
  q.clips=[fresh,secret,benign];q.showRows(q.clipRows('PUBLIC_HELLO'));q.activate(0,false);
  assert.deepEqual(JSON.parse(q.clipPaste.snapshot),benign);
});
