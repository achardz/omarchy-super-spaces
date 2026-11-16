const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
test('launcher uses standard Quickshell overlay panel supported by Omarchy 4.0.6',()=>{
 const qml=fs.readFileSync(path.join(__dirname,'../Launcher.qml'),'utf8');
 assert.doesNotMatch(qml,/\bOverlayWindow\s*\{/);
 assert.match(qml,/PanelWindow\s*\{\s*id: panel\s*visible: root.opened/);
 for(const token of ['WlrLayershell.layer: WlrLayer.Overlay','WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive','exclusionMode: ExclusionMode.Ignore'])assert.ok(qml.includes(token));
});
