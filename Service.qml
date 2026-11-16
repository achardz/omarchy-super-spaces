import QtQuick
import Quickshell
import Quickshell.Io
import "Gestures.js" as Gestures

// Always-loaded part of Super Spaces: the trackpad gestures. On start it
// brings Hyprland's gestures in line with settings.json (the search does the
// same whenever one of them is flipped), and it hosts the overview that three
// fingers up/down step through.
Item {
  id: root

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/super-spaces/settings.json"
    printErrors: false
    onLoaded: root.sync(text())
    onLoadFailed: root.sync("")
  }

  function sync(text) {
    var sources = {}
    try { sources = JSON.parse(text).sources } catch (e) {}
    Quickshell.execDetached(Gestures.syncCommand(sources))
  }

  Overview {}
}
