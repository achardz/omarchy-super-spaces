import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Calc.js" as Calc

// Super Spaces search: one box for open windows (by app, title or workspace),
// apps, files and quick maths. It runs inside the Omarchy shell that is
// already running, so it costs a few MB rather than a separate launcher.
// Files are found on demand with `fd` while typing; nothing indexes in the
// background.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0

  readonly property string pluginId: (root.manifest && root.manifest.id) || "anz.super-spaces"
  readonly property string home: Quickshell.env("HOME")
  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null

  readonly property int maxWindows: 8
  readonly property int maxApps: 6
  readonly property int maxRecentApps: 5
  readonly property int maxFiles: 15

  // ---- app usage (what you launch most rises to the top) ---------------
  // Kept in the plugin's own state file, not shell.json, since it changes on
  // every launch: { "<desktop id>": { "count": n, "last": epoch ms } }.
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || root.home + "/.local/state") + "/anz.super-spaces"
  property var usage: ({})

  FileView {
    id: usageFile
    path: root.stateDir + "/app-usage.json"
    printErrors: false
    atomicWrites: true
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        root.usage = (parsed && typeof parsed === "object") ? parsed : ({})
      } catch (e) {
        root.usage = ({})
      }
    }
    onLoadFailed: root.usage = ({})
  }

  Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.stateDir])

  function recordLaunch(id) {
    if (!id) return
    var next = Object.assign({}, root.usage)
    var prev = next[id] || { count: 0, last: 0 }
    next[id] = { count: Math.min(9999, Number(prev.count || 0) + 1), last: Date.now() }
    root.usage = next
    usageFile.setText(JSON.stringify(next))
  }

  // Capped well under the gap between Omarchy's match tiers (prefix, contains,
  // keyword, acronym), so usage reorders apps within a tier but never lets a
  // weak match beat a strong one.
  function usageBoost(id) {
    var u = root.usage[id]
    if (!u) return 0
    var boost = Math.min(250, Math.round(80 * Math.log(1 + Number(u.count || 0)) / Math.LN2))
    if (Date.now() - Number(u.last || 0) < 24 * 3600 * 1000) boost += 50
    return boost
  }

  // Shares the [menu] surface tokens, so themes that style Omarchy's menu
  // style this too.
  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Commons.Color.menu.scrim
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color selectedText: Commons.Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int rowHeight: Math.max(Style.space(52), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  property int cardWidth: Math.min(Style.space(640), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(560), panel.height - Style.gapsOut * 2)

  // ---- lifecycle -------------------------------------------------------

  function open(payloadJson) {
    Hyprland.refreshToplevels()
    Hyprland.refreshWorkspaces()
    if (root.appLibrary) root.appLibrary.refreshIcons()
    usageFile.reload()
    root.opened = true
    root.setFilter("")
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    folderSearch.running = false
    fileSearch.running = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  // ---- searching -------------------------------------------------------

  function terms(query) {
    return String(query || "").toLowerCase().trim().split(/\s+/).filter(function(t) { return t.length > 0 })
  }

  function matchesAll(haystack, words) {
    var text = String(haystack || "").toLowerCase()
    for (var i = 0; i < words.length; i++) if (text.indexOf(words[i]) < 0) return false
    return true
  }

  function shortClass(cls) {
    var c = String(cls || "")
    if (c.indexOf("chrome-") === 0) return c.slice(7).replace(/__.*$/, "")
    var parts = c.split(".")
    return parts[parts.length - 1]
  }

  function appIconFor(cls) {
    var entry = cls ? DesktopEntries.heuristicLookup(cls) : null
    if (!entry || !entry.icon) return ""
    return root.appLibrary ? root.appLibrary.iconSource(entry.icon) : Quickshell.iconPath(entry.icon, true)
  }

  function windowRows(words) {
    var out = []
    var values = Hyprland.toplevels.values || []
    for (var i = 0; i < values.length; i++) {
      var t = values[i]
      var ipc = t.lastIpcObject || {}
      var ws = t.workspace ? t.workspace.id : (ipc.workspace ? ipc.workspace.id : 0)
      if (ws <= 0) continue
      var cls = ipc.class || ""
      var app = root.shortClass(cls)
      var title = String(t.title || "")
      var hay = app + " " + cls + " " + title + " workspace " + ws + " space " + ws
      if (words.length > 0 && !root.matchesAll(hay, words)) continue
      out.push({ kind: "window", title: title || app, subtitle: app + "  ·  workspace " + ws,
                 icon: root.appIconFor(cls), glyph: "", tag: String(ws), payload: String(t.address || "") })
    }
    out.sort(function(a, b) { return Number(a.tag) - Number(b.tag) })
    return out.slice(0, root.maxWindows)
  }

  // Address of an open window belonging to this app, matched on the desktop
  // entry's StartupWMClass or id against the window class ("" when none).
  function runningWindowFor(entry) {
    var id = String(entry.id || "").toLowerCase()
    var keys = [String(entry.startupClass || "").toLowerCase(), id, id.split(".").pop()]
      .filter(function(k) { return k.length > 0 })
    var values = Hyprland.toplevels.values || []
    for (var i = 0; i < values.length; i++) {
      var ipc = values[i].lastIpcObject || {}
      var cls = String(ipc.class || "").toLowerCase()
      if (!cls) continue
      if (keys.indexOf(cls) !== -1 || keys.indexOf(cls.split(".").pop()) !== -1) return String(values[i].address || "")
    }
    return ""
  }

  function appRow(entry, recent) {
    var running = root.runningWindowFor(entry)
    var sub = root.appLibrary.entrySubtext(entry) || "Application"
    return { kind: "app", title: root.appLibrary.entryName(entry),
             subtitle: running ? sub + "  ·  open, Enter switches (Shift+Enter: new window)" : sub,
             icon: root.appLibrary.iconSource(entry.icon), glyph: "",
             tag: running ? "Running" : (recent ? "Recent" : "App"),
             payload: String(entry.id || ""), window: running }
  }

  // Typed: Omarchy's fuzzy app ranking (sortedEntries returns {entry, score}
  // rows), nudged by how often you launch each app. Empty: your most-used apps.
  function appRows(query) {
    if (!root.appLibrary) return []
    var out = []
    if (!String(query).trim()) {
      var ids = Object.keys(root.usage).sort(function(a, b) {
        return root.usageBoost(b) - root.usageBoost(a)
      })
      for (var r = 0; r < ids.length && out.length < root.maxRecentApps; r++) {
        var known = DesktopEntries.byId(ids[r])
        if (known && !known.noDisplay) out.push(root.appRow(known, true))
      }
      return out
    }
    var ranked = (root.appLibrary.sortedEntries(query) || []).map(function(row) {
      return { entry: row.entry, score: row.score + root.usageBoost(String(row.entry.id || "")) }
    })
    ranked.sort(function(a, b) { return b.score - a.score })
    for (var i = 0; i < ranked.length && out.length < root.maxApps; i++) out.push(root.appRow(ranked[i].entry, false))
    return out
  }

  function rebuild() {
    var query = root.filterText
    var words = root.terms(query)
    var rows = []

    var calc = Calc.evaluate(query)
    if (calc !== null) {
      var value = Calc.format(calc)
      rows.push({ kind: "calc", title: "= " + value, subtitle: "Enter copies the result", icon: "",
                  glyph: "=", tag: "Calc", payload: value })
    }

    var n = /^\s*(\d{1,2})\s*$/.exec(query)
    if (n && Number(n[1]) >= 1) {
      rows.push({ kind: "workspace", title: "Go to workspace " + n[1], subtitle: "Switch to workspace " + n[1],
                  icon: "", glyph: "#", tag: n[1], payload: n[1] })
    }

    // Typing puts apps first (like Raycast); with no text, open windows lead
    // and your most-used apps follow.
    var hasText = String(query).trim().length > 0
    rows = hasText
      ? rows.concat(root.appRows(query)).concat(root.windowRows(words))
      : rows.concat(root.windowRows(words)).concat(root.appRows(query))

    displayModel.clear()
    // Every row carries the same roles; only running-app rows fill `window`.
    for (var i = 0; i < rows.length; i++) displayModel.append(Object.assign({ window: "" }, rows[i]))
    root.clampSelection()
    root.scheduleFiles(query)
  }

  // ---- files, on demand ------------------------------------------------

  property int fileGeneration: 0
  property string pendingFileQuery: ""

  function scheduleFiles(query) {
    root.fileGeneration++
    folderSearch.running = false
    fileSearch.running = false
    var q = String(query || "").trim()
    if (q.length < 2 || Calc.evaluate(q) !== null || /^\d{1,2}$/.test(q)) return
    root.pendingFileQuery = q
    fileDebounce.restart()
  }

  // Arguments go straight to fd, never through a shell. It walks the home
  // folder without hidden paths (so tool data like ~/.vscode or caches stay
  // out) plus ~/.config explicitly, where dotfiles live. fd also honours
  // .gitignore, which keeps build output and node_modules out of projects.
  function fdCommand(type, limit) {
    return ["fd", "--fixed-strings", "--ignore-case", "--type", type,
            "--max-results", String(limit), "--exclude", "node_modules",
            "--", root.pendingFileQuery, root.home, root.home + "/.config"]
  }

  function appendPaths(text, isDir) {
    var lines = String(text).split("\n").filter(function(l) { return l.length > 0 })
    for (var i = 0; i < lines.length; i++) {
      var path = lines[i].replace(/\/$/, "")
      var name = path.slice(path.lastIndexOf("/") + 1)
      var shown = path.indexOf(root.home) === 0 ? "~" + path.slice(root.home.length) : path
      displayModel.append({ kind: "file", title: name, subtitle: shown, icon: "",
                            glyph: isDir ? "▸" : "·", tag: isDir ? "Folder" : "File", payload: path, window: "" })
    }
    root.clampSelection()
  }

  Timer {
    id: fileDebounce
    interval: 160
    onTriggered: {
      if (!root.opened) return
      folderSearch.generation = root.fileGeneration
      fileSearch.generation = root.fileGeneration
      folderSearch.command = root.fdCommand("d", 5)
      fileSearch.command = root.fdCommand("f", root.maxFiles)
      folderSearch.running = true
      fileSearch.running = true
    }
  }

  Process {
    id: folderSearch
    property int generation: -1
    stdout: StdioCollector {
      onStreamFinished: {
        if (folderSearch.generation === root.fileGeneration && root.opened) root.appendPaths(text, true)
      }
    }
  }

  Process {
    id: fileSearch
    property int generation: -1
    stdout: StdioCollector {
      onStreamFinished: {
        if (fileSearch.generation === root.fileGeneration && root.opened) root.appendPaths(text, false)
      }
    }
  }

  // ---- selection and activation ---------------------------------------

  function clampSelection() {
    if (displayModel.count === 0) root.selectedIndex = 0
    else if (root.selectedIndex >= displayModel.count) root.selectedIndex = displayModel.count - 1
    else if (root.selectedIndex < 0) root.selectedIndex = 0
  }

  function setFilter(text) {
    root.filterText = text
    root.selectedIndex = 0
    root.rebuild()
  }

  function move(delta) {
    if (displayModel.count === 0) return
    root.selectedIndex = (root.selectedIndex + delta + displayModel.count) % displayModel.count
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function dispatch(expression) {
    Quickshell.execDetached(["hyprctl", "dispatch", expression])
  }

  function focusWindow(address) {
    var addr = address.indexOf("0x") === 0 ? address : "0x" + address
    if (/^0x[0-9a-fA-F]+$/.test(addr)) root.dispatch("hl.dsp.focus({ window = \"address:" + addr + "\" })")
  }

  // forceNew (Shift+Enter) launches another instance even if the app is open.
  function activate(index, forceNew) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    var kind = row.kind
    var payload = String(row.payload)
    var title = String(row.title)
    var windowAddress = String(row.window || "")
    root.dismiss()

    if (kind === "window") {
      root.focusWindow(payload)
    } else if (kind === "workspace") {
      if (/^\d{1,2}$/.test(payload)) root.dispatch("hl.dsp.focus({ workspace = \"" + payload + "\" })")
    } else if (kind === "app") {
      if (!payload) return
      root.recordLaunch(payload)
      if (windowAddress && !forceNew) root.focusWindow(windowAddress)
      else if (root.appLibrary) root.appLibrary.launch(payload, title)
    } else if (kind === "file") {
      Quickshell.execDetached(["xdg-open", payload])
    } else if (kind === "calc") {
      Quickshell.execDetached(["wl-copy", "--", payload])
    }
  }

  ListModel { id: displayModel }

  // ---- UI --------------------------------------------------------------

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "anz-super-spaces-search"

    Rectangle { anchors.fill: parent; color: root.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier)) || event.key === Qt.Key_Backtab) {
            root.move(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
            root.move(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activate(root.selectedIndex, (event.modifiers & Qt.ShiftModifier) !== 0)
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.md

        Item {
          width: parent.width
          height: root.headerHeight

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || "Search windows, apps, files, or type maths…"
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }
        }

        ListView {
          id: resultList
          width: parent.width
          height: parent.height - root.headerHeight - Style.spacing.md
          model: displayModel
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          delegate: Rectangle {
            id: row
            required property int index
            required property string kind
            required property string title
            required property string subtitle
            required property string icon
            required property string glyph
            required property string tag

            readonly property bool hasCursor: index === root.selectedIndex

            width: ListView.view.width
            height: root.rowHeight
            radius: root.cornerRadius
            color: hasCursor ? root.selectedBackground : "transparent"

            Item {
              id: iconBox
              width: Style.space(28)
              height: Style.space(28)
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.rowPaddingX
              anchors.verticalCenter: parent.verticalCenter

              IconImage {
                anchors.fill: parent
                source: row.icon
                visible: row.icon !== ""
              }
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                visible: row.icon === ""
                text: row.glyph
                color: row.hasCursor ? root.selectedText : root.foreground
                opacity: 0.8
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
              }
            }

            Column {
              anchors.left: iconBox.right
              anchors.leftMargin: Style.spacing.md
              anchors.right: tagText.left
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: row.title
                color: row.hasCursor ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }
              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: row.subtitle
                color: row.hasCursor ? root.selectedText : root.foreground
                opacity: 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideMiddle
              }
            }

            Text {
              id: tagText
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.rowPaddingX
              anchors.verticalCenter: parent.verticalCenter
              text: row.kind === "window" ? "Space " + row.tag : row.tag
              color: row.hasCursor ? root.selectedText : root.foreground
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onContainsMouseChanged: if (containsMouse) root.selectedIndex = row.index
              onClicked: root.activate(row.index)
            }
          }

          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            visible: displayModel.count === 0
            text: root.filterText ? "Nothing found" : "No open windows"
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }
      }
    }
  }
}
