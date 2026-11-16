import QtQuick
import Quickshell.Wayland

// A window's screen copy drawn opaque. With Omarchy's glassy windows a
// terminal's background is 65% opaque, so its copy let whatever sits behind
// the thumbnail show through. Stacking the copy over itself (one capture,
// drawn again through ShaderEffectSource, no shader needed) builds the alpha
// up to 1 - 0.35^5 ≈ 99.5% and brings the colours back to the window's own;
// the solid base takes the rest.
Item {
  id: root

  property var captureSource: null
  property bool live: false
  property color base: "black"

  Rectangle {
    anchors.fill: parent
    color: root.base
  }

  ScreencopyView {
    id: copy
    anchors.fill: parent
    captureSource: root.captureSource
    live: root.live
  }

  Repeater {
    model: 4
    delegate: ShaderEffectSource {
      anchors.fill: parent
      sourceItem: copy
      live: root.live
    }
  }
}
