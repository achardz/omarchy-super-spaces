import Quickshell.Wayland
import qs.Ui

// Surface.qml on shells that ship OverlayWindow. Fails to load where qs.Ui
// has no OverlayWindow, which is how Surface.qml picks PanelSurface.qml.
OverlayWindow {
  property string namespace: ""
  WlrLayershell.namespace: namespace
}
