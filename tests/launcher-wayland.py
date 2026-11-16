#!/usr/bin/env python3
"""Opt-in full launcher test: briefly displays a synthetic panel on Wayland.
Run inside Omarchy. Never reads/writes the real clipboard or types real keys.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

repo = Path(__file__).resolve().parent.parent
host = Path(os.environ.get('OMARCHY_PATH', '/usr/share/omarchy')) / 'shell'
assert os.environ.get('WAYLAND_DISPLAY'), 'Run inside a Wayland session'
with tempfile.TemporaryDirectory(prefix='ss-launcher-wayland-') as directory:
    tmp = Path(directory)
    for name in ['Launcher.qml', 'Calc.js', 'MenuSource.js']:
        shutil.copy(repo / name, tmp / name)
    for name in ['Commons', 'Ui']:
        (tmp / name).symlink_to(host / name, target_is_directory=True)
    (tmp / 'bin').symlink_to(repo / 'bin', target_is_directory=True)
    (tmp / 'mock-bin').mkdir()
    for name, body in {'wl-copy':'cat > "$TEST_CAPTURE"',
                       'wtype':'printf "%s\\n" "$*" > "$TEST_KEYS"'}.items():
        script=tmp / 'mock-bin' / name
        script.write_text('#!/bin/bash\n'+body+'\n')
        script.chmod(0o700)
    history=tmp / '.local/state/omarchy/clipboard-history.json'
    history.parent.mkdir(parents=True)
    benign={'type':'text','text':'PUBLIC_HELLO\nไทย 🧪\n'}
    secret={'type':'text','text':'SYNTHETIC_PRIVATE'}
    history.write_text(json.dumps([secret,benign]))
    (tmp / 'shell.qml').write_text('''//@ pragma OmarchyLoadPatch
import Quickshell
import QtQuick
ShellRoot {
 Launcher { id: launcher }
 Timer { interval: 500; running: true; onTriggered: {
  launcher.opened=true; launcher.setFilter("clip PUBLIC_HELLO");
  console.log("FULL_OVERLAY_OPEN", launcher.opened);
 }}
 Timer { interval: 1800; running: true; onTriggered: {
  console.log("WATCHER_UPDATED", launcher.clips[1].text === "SYNTHETIC_PRIVATE");
  launcher.activate(0,false); console.log("FULL_OVERLAY_DISMISSED", !launcher.opened);
 }}
 Timer { interval: 2600; running: true; onTriggered: Qt.quit() }
}
''')
    env=os.environ.copy()
    env.update(HOME=str(tmp),XDG_STATE_HOME=str(tmp / '.local/state'),
               QT_QPA_PLATFORM='wayland',PATH=str(tmp / 'mock-bin')+':'+env['PATH'],
               TEST_CAPTURE=str(tmp / 'copied'),TEST_KEYS=str(tmp / 'keys'))
    proc=subprocess.Popen(['quickshell','-p',str(tmp / 'shell.qml')],env=env,
                          stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    try:
        time.sleep(1)
        history.write_text(json.dumps([{'type':'text','text':'FRESH_WRITER'},secret,benign]))
        output,_=proc.communicate(timeout=8)
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
    assert proc.returncode == 0, output
    for marker in ['FULL_OVERLAY_OPEN true','WATCHER_UPDATED true','FULL_OVERLAY_DISMISSED true']:
        assert marker in output, output
    assert 'ERROR' not in output, output
    assert (tmp / 'copied').read_bytes() == benign['text'].encode(), output
    assert (tmp / 'keys').read_text().strip() == '-M shift -k Insert -m shift'
    print('PASS: full Wayland launcher opens, copies selected synthetic bytes after history shift, and dismisses')
