import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Safe.js" as Safe

// Mission Control style overview, stepped by the "swipeUp" trackpad setting
// (Hyprland config binds three fingers up/down to the global shortcuts
// below). Up once: this workspace's windows shrink from where they are into
// a grid on one page. Up again: every workspace on this monitor side by side.
// Down steps back; Escape, a click on the backdrop, or picking a window or
// workspace closes it. Thumbnails are live screen copies, only while shown.
Item {
  id: ov

  function dispatch(expression) {
    Quickshell.execDetached(["hyprctl", "dispatch", expression])
  }

  // 0 hidden, 1 windows of the active workspace, 2 every workspace.
  property int stage: 0
  // Hidden: drop the thumbnails so no screen copy keeps running.
  onStageChanged: if (stage === 0) { windows = []; spaces = [] }
  // Stage 1 thumbnails sit where their windows are until this turns on, then
  // animate into the grid, and back out on closing.
  property bool spread: false
  property var windows: []
  property var spaces: []
  property int activeWs: 0
  property real monX: 0
  property real monY: 0

  readonly property int duration: 260
  readonly property color backdrop: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b, 0.94)
  readonly property color text: Commons.Color.foreground
  readonly property color accent: Commons.Color.accent

  function up() {
    if (stage === 0) open()
    else if (stage === 1) { refresh(); stage = 2 }
  }

  function down() {
    if (stage === 2) { refresh(); stage = 1 }
    else if (stage === 1) close()
  }

  function open() {
    Hyprland.refreshToplevels()
    Hyprland.refreshWorkspaces()
    refresh()
    spread = false
    stage = 1
    // The first frame shows the windows in place; the next spreads them.
    spreadTimer.restart()
    Qt.callLater(function() { keys.forceActiveFocus() })
  }

  function close() {
    if (stage === 0) return
    if (stage === 1 && spread) {
      spread = false
      hideTimer.restart()
    } else {
      stage = 0
    }
  }

  function goWindow(address) {
    var addr = String(address).indexOf("0x") === 0 ? address : "0x" + address
    if (/^0x[0-9a-fA-F]+$/.test(addr)) ov.dispatch("hl.dsp.focus({ window = \"address:" + addr + "\" })")
    stage = 0
  }

  function goWorkspace(id) {
    ov.dispatch("hl.dsp.focus({ workspace = \"" + id + "\" })")
    stage = 0
  }

  Timer { id: spreadTimer; interval: 16; onTriggered: ov.spread = true }
  Timer { id: hideTimer; interval: ov.duration; onTriggered: if (!ov.spread) ov.stage = 0 }

  function refresh() {
    var mon = Hyprland.focusedMonitor
    var m = mon ? (mon.lastIpcObject || {}) : {}
    ov.monX = Number(m.x || 0)
    ov.monY = Number(m.y || 0)
    ov.activeWs = m.activeWorkspace ? Number(m.activeWorkspace.id) : 0
    var monName = mon ? String(mon.name) : ""

    var all = []
    var tops = Hyprland.toplevels.values
    for (var i = 0; i < tops.length; i++) {
      var t = tops[i]
      var ipc = t.lastIpcObject || {}
      if (!ipc.workspace || !ipc.at || !ipc.size || ipc.hidden) continue
      all.push({
        toplevel: t,
        address: String(t.address || ipc.address || ""),
        ws: Number(ipc.workspace.id),
        x: Number(ipc.at[0]) - ov.monX,
        y: Number(ipc.at[1]) - ov.monY,
        w: Number(ipc.size[0]),
        h: Number(ipc.size[1]),
        title: String(ipc.title || ipc.class || "")
      })
    }
    // Floating windows above tiled ones, as on screen.
    all.sort(function(a, b) { return (a.toplevel.lastIpcObject.floating ? 1 : 0) - (b.toplevel.lastIpcObject.floating ? 1 : 0) })

    ov.windows = all.filter(function(w) { return w.ws === ov.activeWs })

    var ids = []
    var wss = Hyprland.workspaces.values
    for (var j = 0; j < wss.length; j++) {
      var ws = wss[j]
      if (ws.id > 0 && ws.monitor && String(ws.monitor.name) === monName) ids.push(ws.id)
    }
    ids.sort(function(a, b) { return a - b })
    ov.spaces = ids.map(function(id) {
      return { id: id, slot: (id - 1) % 10 + 1, windows: all.filter(function(w) { return w.ws === id }) }
    })
  }

  // Grid for stage 1: the column count that lets the windows be largest.
  function layout(list, areaW, areaH) {
    var n = list.length
    if (n === 0) return []
    var gap = Style.space(24)
    var best = null
    for (var cols = 1; cols <= n; cols++) {
      var rows = Math.ceil(n / cols)
      var cw = (areaW - gap * (cols - 1)) / cols
      var ch = (areaH - gap * (rows - 1)) / rows
      var score = 0
      for (var i = 0; i < n; i++) score += Math.min(cw / list[i].w, ch / list[i].h, 1)
      if (!best || score > best.score) best = { cols: cols, rows: rows, cw: cw, ch: ch, score: score }
    }
    var out = []
    for (var k = 0; k < n; k++) {
      var r = Math.floor(k / best.cols)
      var inRow = Math.min(best.cols, n - r * best.cols)
      var rowOffset = (best.cols - inRow) * (best.cw + gap) / 2
      var c = k % best.cols
      var s = Math.min(best.cw / list[k].w, best.ch / list[k].h, 1)
      var w = list[k].w * s, h = list[k].h * s
      out.push({
        x: rowOffset + c * (best.cw + gap) + (best.cw - w) / 2,
        y: r * (best.ch + gap) + (best.ch - h) / 2 + (areaH - best.rows * best.ch - (best.rows - 1) * gap) / 2,
        w: w, h: h
      })
    }
    return out
  }

  GlobalShortcut {
    appid: "anz-super-spaces"
    name: "overview-up"
    description: "Overview: one step up (windows, then workspaces)"
    onPressed: ov.up()
  }

  GlobalShortcut {
    appid: "anz-super-spaces"
    name: "overview-down"
    description: "Overview: one step down"
    onPressed: ov.down()
  }

  // A key that opens the overview (like one swipe up) and closes it again
  // (like swiping back down), for keyboards without the trackpad gesture.
  GlobalShortcut {
    appid: "anz-super-spaces"
    name: "overview-toggle"
    description: "Overview: open this workspace's windows, or close"
    onPressed: ov.stage === 0 ? ov.open() : ov.close()
  }

  Connections {
    target: Hyprland
    enabled: ov.stage > 0
    function onRawEvent(event) {
      if (["openwindow", "closewindow", "movewindowv2", "changefloatingmode"].indexOf(event.name) !== -1) {
        Hyprland.refreshToplevels()
        Qt.callLater(ov.refresh)
      }
    }
  }

  // OverlayWindow where the shell has it, PanelWindow otherwise (Surface.qml).
  Surface {
    id: win
    shown: ov.stage > 0
    namespace: "anz-super-spaces-overview"

    Rectangle {
      anchors.fill: parent
      color: ov.backdrop
      opacity: ov.stage === 2 || ov.spread ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: ov.duration; easing.type: Easing.OutCubic } }
    }
    MouseArea { anchors.fill: parent; onClicked: ov.close() }

    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) ov.close()
        else if (event.key === Qt.Key_Up) ov.up()
        else if (event.key === Qt.Key_Down) ov.down()
        event.accepted = true
      }
    }

    // ---- stage 1: this workspace's windows -----------------------------
    Item {
      id: stage1
      readonly property real margin: Math.max(Style.space(48), win.windowHeight * 0.07)
      x: margin
      y: margin
      width: win.windowWidth - margin * 2
      height: win.windowHeight - margin * 2
      visible: ov.stage === 1
      readonly property var targets: ov.layout(ov.windows, width, height)

      Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        visible: ov.windows.length === 0 && ov.spread
        text: "No windows on this workspace"
        color: ov.text
        font.pixelSize: Style.font.title
      }

      Repeater {
        // Only while this stage shows, so its screen copies stop otherwise.
        model: ov.stage === 1 ? ov.windows : []
        delegate: Item {
          id: thumb
          required property var modelData
          required property int index
          readonly property var target: stage1.targets[index] || { x: 0, y: 0, w: 0, h: 0 }
          // Unspread: the window's own place, in stage1's coordinates.
          x: ov.spread ? target.x : modelData.x - stage1.x
          y: ov.spread ? target.y : modelData.y - stage1.y
          width: ov.spread ? target.w : modelData.w
          height: ov.spread ? target.h : modelData.h
          Behavior on x { NumberAnimation { duration: ov.duration; easing.type: Easing.OutCubic } }
          Behavior on y { NumberAnimation { duration: ov.duration; easing.type: Easing.OutCubic } }
          Behavior on width { NumberAnimation { duration: ov.duration; easing.type: Easing.OutCubic } }
          Behavior on height { NumberAnimation { duration: ov.duration; easing.type: Easing.OutCubic } }

          Rectangle {
            anchors.fill: parent
            anchors.margins: -Style.space(3)
            radius: Style.cornerRadius + Style.space(3)
            color: "transparent"
            border.width: Style.space(2)
            border.color: ov.accent
            visible: hover.containsMouse && ov.spread
          }

          ScreencopyView {
            anchors.fill: parent
            captureSource: thumb.modelData.toplevel.wayland
            live: true
          }

          Text {
            textFormat: Text.PlainText
            anchors.top: parent.bottom
            anchors.topMargin: Style.space(6)
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(implicitWidth, parent.width)
            elide: Text.ElideRight
            // A title is whatever the app (or a web page) sets: plain text,
            // never markup, with control and bidi characters shown as "?".
            text: Safe.shown(thumb.modelData.title)
            color: ov.text
            font.pixelSize: Style.font.body
            opacity: ov.spread ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: ov.duration } }
          }

          MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            onClicked: ov.goWindow(thumb.modelData.address)
          }
        }
      }
    }

    // ---- stage 2: every workspace on this monitor ----------------------
    Item {
      id: stage2
      anchors.fill: parent
      anchors.margins: Math.max(Style.space(48), win.windowHeight * 0.07)
      visible: ov.stage === 2
      opacity: visible ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: ov.duration; easing.type: Easing.OutCubic } }

      readonly property real gap: Style.space(28)
      readonly property real labelH: Style.font.body + Style.space(10)
      readonly property int count: Math.max(1, ov.spaces.length)
      readonly property int cols: Math.ceil(Math.sqrt(count * 1.6))
      readonly property int rows: Math.ceil(count / cols)
      readonly property real aspect: win.windowWidth / Math.max(1, win.windowHeight)
      readonly property real cellW: Math.min((width - gap * (cols - 1)) / cols,
                                             ((height - gap * (rows - 1)) / rows - labelH) * aspect)
      readonly property real cellH: cellW / aspect
      readonly property real scale: cellW / Math.max(1, win.windowWidth)

      Grid {
        anchors.centerIn: parent
        columns: stage2.cols
        spacing: stage2.gap

        Repeater {
          model: ov.stage === 2 ? ov.spaces : []
          delegate: Column {
            id: cell
            required property var modelData
            spacing: Style.space(6)

            Rectangle {
              width: stage2.cellW
              height: stage2.cellH
              radius: Style.cornerRadius
              color: Qt.rgba(ov.text.r, ov.text.g, ov.text.b, 0.06)
              border.width: cell.modelData.id === ov.activeWs || cellHover.containsMouse ? Style.space(2) : Style.space(1)
              border.color: cell.modelData.id === ov.activeWs || cellHover.containsMouse
                ? ov.accent : Qt.rgba(ov.text.r, ov.text.g, ov.text.b, 0.15)
              clip: true

              Repeater {
                model: cell.modelData.windows
                delegate: ScreencopyView {
                  required property var modelData
                  x: modelData.x * stage2.scale
                  y: modelData.y * stage2.scale
                  width: modelData.w * stage2.scale
                  height: modelData.h * stage2.scale
                  captureSource: modelData.toplevel.wayland
                  // Windows on hidden workspaces don't change: one copy.
                  live: modelData.ws === ov.activeWs
                }
              }

              MouseArea {
                id: cellHover
                anchors.fill: parent
                hoverEnabled: true
                onClicked: ov.goWorkspace(cell.modelData.id)
              }
            }

            Text {
              textFormat: Text.PlainText
              anchors.horizontalCenter: parent.horizontalCenter
              text: String(cell.modelData.slot)
              color: ov.text
              font.pixelSize: Style.font.body
              font.bold: cell.modelData.id === ov.activeWs
            }
          }
        }
      }
    }
  }
}
