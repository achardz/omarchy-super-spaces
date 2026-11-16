#!/usr/bin/env python3
"""Isolated actual Qt FileView/ListModel/Process regression, not full overlay QA.
Requires quickshell. Never connects to a display or the user's clipboard.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

repo = Path(__file__).resolve().parent.parent
source = (repo / 'Launcher.qml').read_text()
def function(name):
    start = source.index('  function ' + name + '(')
    return source[start:source.index('\n  }', start) + 4]
start = source.index('  FileView {', source.index('// ---- clipboard history'))
watcher = source[start:source.index('\n  // "clip"', start)]
start = source.index('  Process {\n    id: clipPaste')
process = source[start:source.index('\n  }', start) + 4]
with tempfile.TemporaryDirectory(prefix='ss-clipboard-runtime-') as directory:
    tmp = Path(directory)
    (tmp / 'bin').mkdir()
    (tmp / 'runtime').mkdir(mode=0o700)
    history = tmp / '.local/state/omarchy/clipboard-history.json'
    history.parent.mkdir(parents=True)
    benign = {'type': 'text', 'text': 'PUBLIC_HELLO\nไทย 🧪\n'}
    secret = {'type': 'text', 'text': 'SYNTHETIC_PRIVATE'}
    history.write_text(json.dumps([secret, benign]))
    for name, body in {'wl-copy': 'cat > "$TEST_CAPTURE"',
                       'wtype': 'printf "%s\\n" "$*" > "$TEST_KEYS"'}.items():
        script = tmp / 'bin' / name
        script.write_text('#!/bin/bash\n' + body + '\n')
        script.chmod(0o700)
    harness = '''import Quickshell
import Quickshell.Io
import QtQuick
ShellRoot {
 id: root
 property string home: Quickshell.env("HOME")
 property string binDir: Quickshell.env("TEST_HELPERS")
 property var clips: []
 readonly property int maxClips: 50
 property string movingWindow: ""
 function dismiss() {}
 function clampSelection() {}
 ListModel { id: displayModel }
'''
    harness += watcher + process + '\n'.join(function(n) for n in
                  ['terms','matchesAll','clipRows','useClip','showRows','pathQuery','typedPath','activate'])
    harness += '''
 Timer { interval: 500; running: true; onTriggered: {
   root.showRows(root.clipRows("PUBLIC_HELLO")); console.log("RENDERED");
 }}
 Timer { interval: 1800; running: true; onTriggered: {
   console.log("WATCHER_UPDATED", root.clips[1].text === "SYNTHETIC_PRIVATE");
   root.activate(0, false);
 }}
 Timer { interval: 2600; running: true; onTriggered: Qt.quit() }
}
'''
    (tmp / 'shell.qml').write_text(harness)
    env = os.environ.copy()
    for key in ['DISPLAY', 'WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE']:
        env.pop(key, None)
    env.update(HOME=str(tmp), XDG_RUNTIME_DIR=str(tmp / 'runtime'),
               XDG_STATE_HOME=str(tmp / '.local/state'), QT_QPA_PLATFORM='offscreen',
               PATH=str(tmp / 'bin') + ':' + env['PATH'], TEST_HELPERS=str(repo / 'bin'),
               TEST_CAPTURE=str(tmp / 'copied'), TEST_KEYS=str(tmp / 'keys'))
    proc = subprocess.Popen(['quickshell', '-p', str(tmp / 'shell.qml')], env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try:
        time.sleep(1)
        history.write_text(json.dumps([{'type':'text','text':'FRESH_WRITER'}, secret, benign]))
        output, _ = proc.communicate(timeout=8)
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
    assert proc.returncode == 0, output
    assert 'WATCHER_UPDATED true' in output, output
    assert 'ERROR' not in output, output
    assert (tmp / 'copied').read_bytes() == benign['text'].encode(), output
    assert (tmp / 'keys').read_text().strip() == '-M shift -k Insert -m shift'
    print('PASS: real FileView update + stale ListModel + Process stdin preserves selected bytes')
