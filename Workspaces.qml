import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Safe.js" as Safe

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  // Every monitor has workspaces 1-10 of its own, which Hyprland numbers in a
  // block of ten per monitor: 1-10, 11-20, and so on (see
  // default/hypr/monitor-workspaces.lua). Each bar shows its own monitor's block,
  // numbered 1-10, and the one that monitor shows, whichever monitor has focus.
  readonly property int slots: 10

  readonly property var monitor: {
    var window = root.QsWindow.window
    var screen = window ? window.screen : null
    return screen ? Hyprland.monitorFor(screen) : Hyprland.focusedMonitor
  }
  readonly property string monitorName: root.monitor ? root.monitor.name : ""

  // Connector -> block, from the file Hyprland keeps them in.
  property var blocks: ({})

  function readBlocks(text) {
    var next = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var fields = lines[i].split("\t")
      if (fields.length >= 3 && fields[1] !== "") next[fields[1]] = parseInt(fields[0], 10)
    }
    root.blocks = next
  }

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/monitor-workspaces"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.readBlocks(text())
    onLoadFailed: root.readBlocks("")
  }

  function blockOf(id) {
    return Math.floor((id - 1) / root.slots)
  }

  function slotOf(id) {
    return (id - 1) % root.slots + 1
  }

  function activeWorkspaceId() {
    return root.monitor && root.monitor.activeWorkspace ? root.monitor.activeWorkspace.id : -1
  }

  // Until Hyprland has written the file, the workspace a monitor shows is in
  // its own block.
  readonly property int block: {
    var block = root.blocks[root.monitorName]
    if (block !== undefined) return block
    var active = root.activeWorkspaceId()
    return active > 0 ? root.blockOf(active) : 0
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  // The first five of the monitor's own, and any of the rest that exist. After
  // them come workspaces that are only visiting: those of a monitor that is
  // unplugged, which had no room to join this one's.
  function workspaceIds() {
    var base = root.block * root.slots
    var ids = [base + 1, base + 2, base + 3, base + 4, base + 5]
    var guests = []
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id <= 0) continue
      if (root.blockOf(id) === root.block) {
        if (ids.indexOf(id) === -1) ids.push(id)
      } else if (values[i].monitor && values[i].monitor.name === root.monitorName) {
        guests.push(id)
      }
    }

    ids.sort(function(left, right) { return left - right })
    guests.sort(function(left, right) { return left - right })
    return ids.concat(guests)
  }

  // Workspaces past 9 (own 10 and up, plus any visiting ones) fold behind a
  // + / - toggle, like the tray drawer. The one being shown always stays visible.
  // Open/closed is kept in memory (PersistentProperties), not a state file,
  // for the same symlink reason as the search's app ranking: it survives shell
  // reloads, and a shell restart starts folded.
  property bool extrasOpen: memory.extrasOpen

  PersistentProperties {
    id: memory
    reloadableId: "anz.super-spaces.bar"
    property bool extrasOpen: false
  }

  function setExtrasOpen(open) {
    memory.extrasOpen = open
  }

  function isExtra(id) {
    return root.blockOf(id) !== root.block || root.slotOf(id) > 9
  }

  function mainIds() {
    return root.workspaceIds().filter(function(id) { return !root.isExtra(id) })
  }

  function allExtraIds() {
    return root.workspaceIds().filter(function(id) { return root.isExtra(id) })
  }

  function shownExtraIds() {
    var active = root.activeWorkspaceId()
    return root.allExtraIds().filter(function(id) { return root.extrasOpen || id === active })
  }

  // Folded away right now: the count on "+N" and where urgency is hidden.
  function hiddenExtraIds() {
    var shown = root.shownExtraIds()
    return root.allExtraIds().filter(function(id) { return shown.indexOf(id) === -1 })
  }

  // Windows asking for attention, by address (Hyprland's "urgent" event);
  // focusing or closing one clears it.
  property var urgentAddresses: ({})

  function setUrgent(address, on) {
    var a = String(address || "").replace(/^0x/, "")
    if (!a || (root.urgentAddresses[a] === true) === on) return
    var next = Object.assign({}, root.urgentAddresses)
    if (on) next[a] = true
    else delete next[a]
    root.urgentAddresses = next
  }

  // True when a window wanting attention sits on a folded workspace.
  readonly property bool hiddenUrgent: {
    var hidden = root.hiddenExtraIds()
    if (hidden.length === 0) return false
    var values = Hyprland.toplevels.values || []
    for (var i = 0; i < values.length; i++) {
      var t = values[i]
      var a = String(t.address || "").replace(/^0x/, "")
      var ws = t.workspace ? t.workspace.id : -1
      if (root.urgentAddresses[a] && hidden.indexOf(ws) !== -1) return true
    }
    return false
  }

  function dispatch(expression) {
    if (root.bar) root.bar.run("hyprctl dispatch " + Util.shellQuote(expression))
  }

  // The monitor name goes inside a Lua string, so only a plain connector
  // name is used; anything else focuses the workspace by id instead.
  function focusWorkspace(id) {
    var monitor = Safe.monitorName(root.monitorName)
    if (monitor && root.blockOf(id) === root.block) {
      root.dispatch("o.workspaces.focus(" + root.slotOf(id) + ", \"" + monitor + "\")")
    } else {
      root.dispatch("hl.dsp.focus({ workspace = \"" + id + "\" })")
    }
  }

  // A wheel notch moves one entry along the row, and a touchpad adds up its
  // smaller deltas until they make a notch's worth.
  property real wheelAccumulator: 0

  function scrollWorkspaces(delta) {
    var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
    root.wheelAccumulator = wheel.remainder
    if (wheel.steps === 0) return

    // Holds at either end rather than wrapping, so a touchpad swipe that runs
    // long stops on the last workspace.
    var ids = root.workspaceIds()
    var index = ids.indexOf(root.activeWorkspaceId())
    if (index === -1) return
    var target = ids[Util.clamp(index - wheel.steps, 0, ids.length - 1)]
    if (target !== ids[index]) root.focusWorkspace(target)
  }

  // The workspace each monitor shows carries its layout: a square tiles, a
  // circle scrolls, and a triangle floats. Clicking it cycles to the next one,
  // as Super + L does.
  property string activeMode: "dwindle"
  property bool modeStale: false

  function modeGlyph(mode) {
    if (mode === "scrolling") return "󰝥"
    if (mode === "floating") return "󰔶"
    return "󱓻"
  }

  // A layout only changes through the layout commands, which ask for a refresh,
  // or a config reload, so each workspace's mode is read once and cached rather
  // than running the script on every workspace switch.
  property var modeCache: ({})
  property int modeGeneration: 0
  property int modeProcWorkspace: -1
  property int modeProcGeneration: 0

  function showActiveMode() {
    var mode = root.modeCache[root.activeWorkspaceId()]
    if (mode !== undefined) root.activeMode = mode
    else readMode()
  }

  function readMode() {
    if (modeProc.running) {
      root.modeStale = true
      return
    }
    var id = root.activeWorkspaceId()
    if (id === -1) return
    root.modeProcWorkspace = id
    root.modeProcGeneration = root.modeGeneration
    modeProc.command = ["omarchy-hyprland-workspace-layout-current", String(id)]
    modeProc.running = true
  }

  function refresh() {
    root.modeCache = ({})
    root.modeGeneration++
    readMode()
  }

  // The layout commands act on the focused workspace, so a click on another
  // monitor's bar focuses that monitor first.
  function cycleLayout() {
    if (!root.bar) return
    var command = "omarchy-hyprland-workspace-layout-toggle"
    var monitor = Safe.monitorName(root.monitorName)
    if (monitor && root.monitor && !root.monitor.focused) {
      command = "hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ monitor = \"" + monitor + "\" })") + " >/dev/null && " + command
    }
    root.bar.run(command)
  }

  Component.onCompleted: refresh()
  onMonitorChanged: root.showActiveMode()

  Connections {
    target: root.monitor
    function onActiveWorkspaceChanged() { root.showActiveMode() }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (name === "configreloaded") root.refresh()
      // Quickshell credits every workspace switch to the focused monitor, as
      // the event doesn't say which one switched, and misses the workspace a
      // monitor falls back to when its own is moved away. Moving workspaces
      // between monitors switches the others, so ask Hyprland for the truth.
      // A workspace that changes number is only learned by asking too. Every
      // bar shares what Hyprland answers, so one asks after a plain switch.
      var switched = name === "workspacev2" && root.monitor !== null && root.monitor.focused
      if (switched || name === "moveworkspacev2" || name === "changeworkspaceid") {
        Hyprland.refreshMonitors()
        Hyprland.refreshWorkspaces()
      }
      var data = event ? String(event.data || "") : ""
      if (name === "urgent") root.setUrgent(data, true)
      else if (name === "activewindowv2" || name === "closewindow") root.setUrgent(data, false)
    }
  }

  Process {
    id: modeProc
    stdout: StdioCollector {
      onStreamFinished: {
        var mode = text.trim()
        // A read that started before a refresh may predate the change.
        if (!mode || root.modeProcGeneration !== root.modeGeneration) return
        root.modeCache[root.modeProcWorkspace] = mode
        if (root.modeProcWorkspace === root.activeWorkspaceId()) root.activeMode = mode
      }
    }
    onExited: {
      if (!root.modeStale) return
      root.modeStale = false
      // Deferred: the process still reports running while it signals exit.
      Qt.callLater(root.showActiveMode)
    }
  }

  // Super + L and the default layout change the mode without a focus change,
  // so they ask every bar to read it again.
  ShellIpc {
    target: "omarchy.workspaces"

    function refresh(): void { root.broadcast("refresh") }
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  component WorkspaceButton: WidgetButton {
    required property int modelData

    readonly property var workspace: root.workspaceById(modelData)
    readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
    readonly property bool shown: root.monitor !== null && root.monitor.activeWorkspace !== null && root.monitor.activeWorkspace.id === modelData
    readonly property bool extra: root.isExtra(modelData)
    // Extras carry their full number (10, 14, ...); 1-9 keep the bare digit.
    readonly property string wsLabel: extra
      ? String(root.blockOf(modelData) === root.block ? root.slotOf(modelData) : modelData)
      : String(root.slotOf(modelData))

    bar: root.bar
    text: shown ? root.modeGlyph(root.activeMode) : wsLabel
    opacity: occupied || shown ? 1 : 0.5
    horizontalMargin: 6
    verticalPadding: 6
    fixedWidth: root.vertical ? root.barSize : Style.space(extra ? 26 : 20)
    fixedHeight: root.barSize
    onPressed: function() {
      if (shown) root.cycleLayout()
      else root.focusWorkspace(modelData)
    }
    onWheelMoved: function(delta) { root.scrollWorkspaces(delta) }
  }

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.mainIds().length + (root.allExtraIds().length > 0 ? 1 : 0) + root.shownExtraIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.mainIds()
      WorkspaceButton {}
    }

    // Drawer toggle for workspaces past 9: "+N" counts what is folded away,
    // "-" hides them again. It takes the theme's urgent colour when a folded
    // workspace has a window asking for attention. Only there when some exist.
    WidgetButton {
      readonly property int hiddenCount: root.hiddenExtraIds().length
      visible: root.allExtraIds().length > 0
      bar: root.bar
      text: root.extrasOpen ? "-" : (hiddenCount > 0 ? "+" + hiddenCount : "+")
      active: root.hiddenUrgent
      opacity: root.hiddenUrgent ? 1 : 0.7
      tooltipText: root.extrasOpen
        ? "Hide workspaces past 9"
        : hiddenCount + (hiddenCount === 1 ? " folded workspace" : " folded workspaces")
          + (root.hiddenUrgent ? " (one needs attention)" : "")
      horizontalMargin: 4
      verticalPadding: 6
      fixedWidth: root.vertical ? root.barSize : Style.space(!root.extrasOpen && hiddenCount > 0 ? 22 : 14)
      fixedHeight: root.barSize
      onPressed: function() { root.setExtrasOpen(!root.extrasOpen) }
      onWheelMoved: function(delta) { root.scrollWorkspaces(delta) }
    }

    Repeater {
      model: root.shownExtraIds()
      WorkspaceButton {}
    }
  }
}
