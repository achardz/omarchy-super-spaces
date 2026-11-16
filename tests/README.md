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
