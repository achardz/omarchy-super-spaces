import QtQuick

// Full-screen overlay on the focused monitor, for the search. Uses Omarchy's
// own OverlayWindow when the installed shell has it (opens sharp, follows a
// monitor that goes away); shells without it get a plain layer-shell
// PanelWindow instead. Children go inside the window.
Item {
  id: surface

  property bool shown: false
  property string namespace: ""
  default property alias content: holder.data

  property var window: null
  readonly property real windowWidth: window ? window.width : 0
  readonly property real windowHeight: window ? window.height : 0

  Item {
    id: holder
    anchors.fill: parent
  }

  Component.onCompleted: {
    var component = Qt.createComponent("OverlaySurface.qml")
    if (component.status !== Component.Ready) {
      console.info("Super Spaces: this Omarchy has no OverlayWindow, using PanelWindow")
      component = Qt.createComponent("PanelSurface.qml")
    }
    surface.window = component.createObject(surface, { namespace: surface.namespace })
    surface.window.shown = Qt.binding(function() { return surface.shown })
    holder.parent = surface.window.contentItem
  }
}
