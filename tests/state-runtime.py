#!/usr/bin/env python3
"""Super Spaces only writes its JSON files into private directories, and keeps
recent files and the bar fold in memory across shell reloads.

Regression for a symlink replacement: with state files in a shared,
non-sticky XDG_STATE_HOME/anz.super-spaces, another user could preplant
app-usage.json as a symlink, and an atomic save that follows it replaces the
file it points at. Runs the real ranking and recent-file code from
Launcher.qml (with the real bin/private-json helper) under Quickshell,
offscreen, in a fresh HOME:

  shared    0777 non-sticky state dir with planted symlinks: the helper
            refuses, the targets are untouched, nothing is written.
  private   0700 state dir: the ranking is saved as a regular 0600 file and
            read back by a second shell; a planted link is replaced by the
            rename, never followed; recent files stay off disk.
  settings  the same checks for ~/.config/omarchy/super-spaces/settings.json.
  reload    recent files (Launcher.qml) and the bar fold (Workspaces.qml)
            survive Quickshell.reload().
Requires quickshell and jq.
"""
import os
import stat
import subprocess
import tempfile
from pathlib import Path

repo = Path(__file__).resolve().parent.parent
source = (repo / 'Launcher.qml').read_text()

def block(start_marker, end_marker):
    start = source.index(start_marker)
    return source[start:source.index(end_marker, start)]

def function(name):
    start = source.index('  function ' + name + '(')
    return source[start:source.index('\n  }', start) + 4]

ranking = block('  property var usage: ({})', '\n  // The files opened from this search')
memory = block('  PersistentProperties {', '\n  // `omarchy-shell anz.super-spaces')

def run(tmp, state, actions):
    qml = '''import Quickshell
import Quickshell.Io
import QtQuick
ShellRoot {
 id: root
 property string home: Quickshell.env("HOME")
 readonly property string binDir: Quickshell.env("TEST_BIN")
 property var recentOwn: []
''' + ranking + '\n' + memory + '\n' + function('recordLaunch') + '\n' + function('recordFile') + '''
 Component.onCompleted: usageLoad.running = true
 Timer { interval: 700; running: true; onTriggered: {
''' + actions + '''
   console.log("USAGE", JSON.stringify(root.usage));
 }}
 Timer { interval: 1800; running: true; onTriggered: Qt.quit() }
}
'''
    (tmp / 'shell.qml').write_text(qml)
    env = {k: v for k, v in os.environ.items()
           if k not in ('DISPLAY', 'WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE')}
    env.update(HOME=str(tmp), XDG_RUNTIME_DIR=str(tmp / 'runtime'), XDG_STATE_HOME=str(state),
               TEST_BIN=str(repo / 'bin'), QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='')
    out = subprocess.run(['quickshell', '-p', str(tmp / 'shell.qml')], env=env,
                         capture_output=True, text=True, timeout=20)
    log = out.stdout + out.stderr
    assert out.returncode == 0, log
    lines = [l for l in log.splitlines() if 'USAGE' in l]
    assert lines, log
    return lines[0]

def files(root):
    return sorted(str(p.relative_to(root)) for p in root.rglob('*') if 'runtime' not in p.parts)

with tempfile.TemporaryDirectory(prefix='ss-state-') as d:
    tmp = Path(d)
    (tmp / 'runtime').mkdir(mode=0o700)
    victim = tmp / 'victim'
    victim.mkdir()

    # shared, non-sticky directory with planted symlinks
    shared = tmp / 'shared'
    (shared / 'anz.super-spaces').mkdir(parents=True)
    os.chmod(shared / 'anz.super-spaces', 0o777)
    targets = []
    for name in ['app-usage.json', 'recent-files.json']:
        t = victim / ('victim-' + name)
        t.write_text('ORIGINAL\n')
        targets.append((t, t.stat().st_ino))
        (shared / 'anz.super-spaces' / name).symlink_to(t)
    before = files(shared)
    held = run(tmp, shared, 'root.recordLaunch("firefox.desktop"); root.recordFile("/home/x/plan.txt", false);')
    assert '"firefox.desktop":{"count":1' in held, held
    for t, ino in targets:
        assert t.stat().st_ino == ino and t.read_text() == 'ORIGINAL\n', str(t) + ' was replaced'
    assert files(shared) == before, 'wrote into a shared dir: ' + str(files(shared))

    # private directory: saved, read back, planted link replaced not followed
    private = tmp / 'private'
    private.mkdir(mode=0o700)
    run(tmp, private, 'root.recordLaunch("firefox.desktop"); root.recordLaunch("firefox.desktop"); root.recordFile("/home/x/plan.txt", false);')
    saved = private / 'anz.super-spaces' / 'app-usage.json'
    assert saved.is_file() and not saved.is_symlink(), files(private)
    assert stat.S_IMODE(saved.stat().st_mode) == 0o600, oct(saved.stat().st_mode)
    assert stat.S_IMODE(saved.parent.stat().st_mode) == 0o700
    assert '"firefox.desktop":{"count":2' in saved.read_text(), saved.read_text()
    assert files(private) == ['anz.super-spaces', 'anz.super-spaces/app-usage.json'], files(private)

    planted = victim / 'victim-private'
    planted.write_text('ORIGINAL\n')
    ino = planted.stat().st_ino
    saved.unlink()
    saved.symlink_to(planted)
    held = run(tmp, private, 'root.recordLaunch("foot.desktop");')
    assert '"foot.desktop":{"count":1' in held, held
    assert planted.stat().st_ino == ino and planted.read_text() == 'ORIGINAL\n', 'followed the planted link'
    assert saved.is_file() and not saved.is_symlink() and '"foot.desktop"' in saved.read_text()

    held = run(tmp, private, '')
    assert '"foot.desktop":{"count":1' in held, 'ranking not read back: ' + held

    # settings.json: same helper, ~/.config/omarchy/super-spaces
    helper = repo / 'bin' / 'private-json'
    henv = dict(os.environ, HOME=str(tmp / 'home'))
    conf = tmp / 'home' / '.config' / 'omarchy' / 'super-spaces'
    conf.mkdir(parents=True)
    os.chmod(conf, 0o777)
    target = victim / 'victim-settings'
    target.write_text('ORIGINAL\n')
    ino = target.stat().st_ino
    (conf / 'settings.json').symlink_to(target)
    r = subprocess.run([helper, 'save', 'settings'], input='{"sources":{"ask":true}}\n',
                       env=henv, capture_output=True, text=True)
    assert r.returncode == 2, r
    r = subprocess.run([helper, 'load', 'settings'], env=henv, capture_output=True, text=True)
    assert r.returncode == 2 and not r.stdout, r
    assert target.stat().st_ino == ino and target.read_text() == 'ORIGINAL\n', 'shared settings dir written'
    os.chmod(conf, 0o700)
    r = subprocess.run([helper, 'load', 'settings'], env=henv, capture_output=True, text=True)
    assert r.returncode == 3, 'loaded through a planted settings link: ' + repr(r)
    r = subprocess.run([helper, 'save', 'settings'], input='{"sources":{"ask":true}}\n',
                       env=henv, capture_output=True, text=True)
    assert r.returncode == 0, r
    saved = conf / 'settings.json'
    assert target.read_text() == 'ORIGINAL\n', 'followed the planted settings link'
    assert saved.is_file() and not saved.is_symlink() and stat.S_IMODE(saved.stat().st_mode) == 0o600
    assert '"ask": true' in saved.read_text(), saved.read_text()   # pretty-printed for hand edits
    r = subprocess.run([helper, 'save', 'settings'], input='[1]\n', env=henv, capture_output=True, text=True)
    assert r.returncode == 1 and '"ask": true' in saved.read_text(), 'non-object accepted'
    fresh = dict(os.environ, HOME=str(tmp / 'fresh'))
    r = subprocess.run([helper, 'load', 'settings'], env=fresh, capture_output=True, text=True)
    assert r.returncode == 0 and r.stdout.strip() == '{}', r
    assert stat.S_IMODE((tmp / 'fresh/.config/omarchy/super-spaces').stat().st_mode) == 0o700

    # reload: recent files and the bar fold live in PersistentProperties
    bar_source = (repo / 'Workspaces.qml').read_text()
    start = bar_source.index('  PersistentProperties {')
    bar = bar_source[start:bar_source.index('\n  function setExtrasOpen', start)].replace('id: memory', 'id: barMemory')
    qml = '''import Quickshell
import QtQuick
ShellRoot {
 id: root
 property var recentOwn: []
''' + memory + '\n' + bar + '\n' + function('recordFile') + '''
 PersistentProperties { id: runs; reloadableId: "test-runs"; property int n: 0 }
 Timer { interval: 400; running: true; onTriggered: {
   if (runs.n === 0) {
     root.recordFile("/home/x/plan.txt", false); barMemory.extrasOpen = true
     runs.n = 1; Quickshell.reload(false)
   } else {
     console.log("RELOADED", JSON.stringify(root.recentOwn), barMemory.extrasOpen); Qt.quit()
   }
 }}
 Timer { interval: 5000; running: true; onTriggered: Qt.quit() }
}
'''
    (tmp / 'shell.qml').write_text(qml)
    env = {k: v for k, v in os.environ.items()
           if k not in ('DISPLAY', 'WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE')}
    env.update(HOME=str(tmp), XDG_RUNTIME_DIR=str(tmp / 'runtime'),
               QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='')
    out = subprocess.run(['quickshell', '-p', str(tmp / 'shell.qml')], env=env,
                         capture_output=True, text=True, timeout=20)
    log = out.stdout + out.stderr
    line = [l for l in log.splitlines() if 'RELOADED' in l]
    assert line and '/home/x/plan.txt' in line[0] and line[0].rstrip().endswith('true'), log

print('PASS: ranking and settings written only in private dirs, planted links never followed; recent files and bar fold survive reloads')
