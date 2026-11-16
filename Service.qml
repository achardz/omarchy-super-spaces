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

  // Read through bin/private-json, like the search does: when the settings
  // folder isn't private to this user, nothing is read and the gestures stay
  // at their defaults (off).
  Process {
    running: true
    command: [decodeURIComponent(String(Qt.resolvedUrl("bin")).replace(/^[a-z]+:\/\//, "")) + "/private-json", "load", "settings"]
    stdout: StdioCollector { onStreamFinished: root.sync(text) }
  }

  function sync(text) {
    var sources = {}
    try { sources = JSON.parse(text).sources } catch (e) {}
    Quickshell.execDetached(Gestures.syncCommand(sources))
  }

  Overview {}
}
