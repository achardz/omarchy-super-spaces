import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// Surface.qml on shells without OverlayWindow: a plain full-screen overlay
// layer, placed on the focused monitor each time it is shown.
PanelWindow {
  id: window

  property bool shown: false
  property string namespace: ""

  function focusedScreen() {
    var name = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name) : ""
    for (var i = 0; i < Quickshell.screens.length; i++)
      if (Quickshell.screens[i].name === name) return Quickshell.screens[i]
    return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
  }

  onShownChanged: if (shown) screen = focusedScreen()

  visible: shown
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  WlrLayershell.namespace: namespace
}
