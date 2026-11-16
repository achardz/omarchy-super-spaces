# Clipboard regression tests

Run `node --test tests/clipboard.test.js` (Node 22+, bash, jq). No npm packages
are needed. Tests run the real launcher JavaScript functions and copy helper;
only the QML model/process boundary and wl-copy/wtype are mocked. All history,
clipboard bytes and image fixtures are synthetic and private temporary files
are removed after each helper test. No real clipboard or keys are used.

With Quickshell installed, run `python3 tests/clipboard-runtime.py` to additionally
exercise actual FileView watching, ListModel snapshots, and Process stdin. It
uses Qt offscreen, a fresh HOME/runtime directory, and mock clipboard commands.
It is not an end-to-end test of the full visible overlay or compositor focus.

Covered: history prepends, reorder, removal/clear, text/image index shifts,
copy-only, repeated activation, helper-time history independence, Unicode and
trailing newlines, large text, malformed snapshots, missing images, and failed
clipboard writes. Saved image paths are not immutable image-byte snapshots;
external modification of an image file is outside this fix's guarantee.

Run all Node checks with `node --test tests/*.test.js`.

For an opt-in full-window test inside an Omarchy Wayland session, run
`python3 tests/launcher-wayland.py`. It briefly opens the actual complete
launcher on your display with a synthetic HOME and history, verifies selection
through a history change, and dismisses it. Clipboard and keystroke commands
remain mocked. It imports the installed host Commons/Ui and uses the host
OmarchyLoadPatch pragma. This tests full-window loading and programmatic
activation, not physical keyboard events or pasting into another application.

## Saved state

With Quickshell and jq installed, run `python3 tests/state-runtime.py`. It runs
the real app-ranking and recent-file code from `Launcher.qml`, with the real
`bin/private-json` helper, offscreen. In a shared, non-sticky
`XDG_STATE_HOME/anz.super-spaces` with `app-usage.json` and `recent-files.json`
preplanted as symlinks, it fails if either target is replaced or anything is
written. In a private directory, it checks the ranking is saved as a `0600`
file and read back, that a planted link is replaced rather than followed, and
that recent files never reach disk. It runs the same checks on
`~/.config/omarchy/super-spaces/settings.json`, and checks that recent files and
the bar fold survive `Quickshell.reload()`.
