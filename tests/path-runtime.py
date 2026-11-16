#!/usr/bin/env python3
"""Typing a path lists the next level of that folder: folders only until a
name is started, then folders and files starting with it. Runs the real path
code from Launcher.qml under Quickshell (offscreen, fresh HOME) against a
folder holding 5000 files, so a bare "/" style listing must not return them.
Requires quickshell and fd.
"""
import json
import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

repo = Path(__file__).resolve().parent.parent
source = (repo / 'Launcher.qml').read_text()
start = source.index('  // ---- paths: "/", "~"')
paths = source[start:source.index('\n  // ---- selection and activation', start)]
for name in ['fdPaths', 'shownText']:
    at = source.index('  function ' + name + '(')
    paths += '\n' + source[at:source.index('\n  }', at) + 4]

CASES = [
    ('~/big/', 'folders only: 5000 files left out'),
    ('~/big/a', 'names starting with a, folders then files'),
    ('~/big/.', 'hidden only once a dot is typed'),
    ('~/many/', 'capped at maxPathRows'),
    ('~/missing/', 'missing folder'),
    ('~', 'bare ~ is home'),
    ('~/odd/', 'newline and bidi names (another user\'s folder)'),
    ('~/odd/r', 'a newline name stays one row'),
]

with tempfile.TemporaryDirectory(prefix='ss-path-') as d:
    tmp = Path(d)
    (tmp / 'runtime').mkdir(mode=0o700)
    big = tmp / 'big'
    for name in ['alpha', 'Apples', 'beta', '.hidden-dir']:
        (big / name).mkdir(parents=True)
    for i in range(5000):
        (big / f'file{i:05}.txt').touch()
    (big / 'apple.txt').touch()
    (big / '.hidden-file').touch()
    for i in range(250):
        (tmp / 'many' / f'd{i:03}').mkdir(parents=True)
    odd = tmp / 'odd'
    (odd / 'doc\u202efdp.exe').mkdir(parents=True)
    (odd / 'report\nDocuments').touch()

    qml = '''import Quickshell
import Quickshell.Io
import QtQuick
import "Safe.js" as Safe
ShellRoot {
 id: root
 property string home: Quickshell.env("HOME")
 property bool opened: true
 property string filterText: ""
 property int fileGeneration: 0
 property var cases: ''' + json.dumps([c for c, _ in CASES]) + '''
 property int at: -1
 property double started: 0
 Timer { id: fileDebounce }
 Process { id: folderSearch }
 Process { id: fileSearch }
 function showRows(rows) {
   console.log("ROWS " + JSON.stringify({ q: root.filterText, ms: Date.now() - root.started,
     rows: rows.map(function(r) { return [r.kind, r.title, r.subtitle, r.tag, r.payload] }) }))
   next()
 }
 function next() {
   root.at++
   if (root.at >= root.cases.length) { Qt.quit(); return }
   root.filterText = root.cases[root.at]
   root.started = Date.now()
   root.schedulePath(root.pathQuery(root.filterText))
 }
''' + paths + '''
 Component.onCompleted: next()
 Timer { interval: 15000; running: true; onTriggered: Qt.quit() }
}
'''
    (tmp / 'shell.qml').write_text(qml)
    shutil.copy(repo / 'Safe.js', tmp / 'Safe.js')
    env = {k: v for k, v in os.environ.items()
           if k not in ('DISPLAY', 'WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE')}
    env.update(HOME=str(tmp), XDG_RUNTIME_DIR=str(tmp / 'runtime'),
               QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='')
    out = subprocess.run(['quickshell', '-p', str(tmp / 'shell.qml')], env=env,
                         capture_output=True, text=True, timeout=30)
    log = out.stdout + out.stderr
    results = {}
    for line in log.splitlines():
        if 'ROWS ' in line:
            r = json.loads(line[line.index('ROWS ') + 5:])
            results[r['q']] = r
    assert len(results) == len(CASES), log

    def rows(q, tag=None):
        return [r for r in results[q]['rows'] if tag is None or r[3] == tag]

    r = results['~/big/']
    assert [x[1] for x in rows('~/big/', 'Folder')] == ['alpha', 'Apples', 'beta'], r
    assert not rows('~/big/', 'File'), 'files listed before a name was started'
    assert rows('~/big/')[-1][1] == 'Folders only', r
    assert rows('~/big/', 'Folder')[0][2] == '~/big/alpha', 'subtitle not written with ~'

    names = [(x[3], x[1]) for x in rows('~/big/a') if x[0] == 'file']
    assert names == [('Folder', 'alpha'), ('Folder', 'Apples'), ('File', 'apple.txt')], names

    names = sorted(x[1] for x in rows('~/big/.') if x[0] == 'file')
    assert names == ['.hidden-dir', '.hidden-file'], names

    many = rows('~/many/', 'Folder')
    assert len(many) == 200 and rows('~/many/')[-1][1] == 'Showing the first 200', len(many)

    assert rows('~/missing/')[0][:2] == ['info', 'No folders here'], rows('~/missing/')
    assert 'big' in [x[1] for x in rows('~', 'Folder')], rows('~')

    # A newline in a name must not split it into two rows (one a relative path
    # chosen by the file's owner), and a bidi override must not disguise it.
    shown = [x for x in rows('~/odd/') if x[0] == 'file']
    assert [(x[1], x[4]) for x in shown] == [('doc?fdp.exe', str(odd / 'doc\u202efdp.exe'))], shown
    shown = [x for x in rows('~/odd/r') if x[0] == 'file']
    assert [(x[1], x[4]) for x in shown] == [('report?Documents', str(odd / 'report\nDocuments'))], shown
    for q in results:
        for x in rows(q):
            assert x[0] != 'file' or x[4].startswith('/'), ('relative payload', x)

    for q, what in CASES:
        print(f"{results[q]['ms']:>4} ms  {q:<12} {what}")

print('PASS: folders only until a name is started; prefix, hidden, cap and missing folder handled')
