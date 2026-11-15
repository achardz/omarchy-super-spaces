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
import "MenuSource.js" as MenuSource

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

  // ---- Omarchy menu entries ("menu …", and the best few in any search) --
  // Read from Omarchy's own menu definition plus the user's extensions file
  // (which overrides it), and reloaded when either changes.
  readonly property int maxMenuInline: 4
  readonly property int maxMenu: 60
  property var menuDefaults: ({})
  property var menuUser: ({})
  property var menuEntries: []

  function rebuildMenuEntries() {
    root.menuEntries = MenuSource.entries(MenuSource.merge(root.menuDefaults, root.menuUser))
    if (root.opened) root.rebuild()
  }

  FileView {
    path: (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/default/omarchy/omarchy-menu.jsonc"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { root.menuDefaults = MenuSource.parse(text()); root.rebuildMenuEntries() }
  }

  FileView {
    path: root.home + "/.config/omarchy/extensions/omarchy-menu.jsonc"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { root.menuUser = MenuSource.parse(text()); root.rebuildMenuEntries() }
    onLoadFailed: { root.menuUser = ({}); root.rebuildMenuEntries() }
  }

  // "menu …", "omarchy …" or "om …"; null when the query isn't a menu search.
  function menuQuery(query) {
    var m = /^\s*(menu|omarchy|om)(?:\s+(.*))?$/i.exec(String(query || ""))
    return m ? (m[2] || "") : null
  }

  // Label starting with a word beats label containing it beats a match only
  // in the path, aliases or id; shallower entries win ties.
  function menuScore(entry, words) {
    var label = entry.label.toLowerCase()
    var score = 0
    for (var i = 0; i < words.length; i++) {
      if (entry.search.indexOf(words[i]) < 0) return -1
      if (label.indexOf(words[i]) === 0 || label.indexOf(" " + words[i]) >= 0) score += 30
      else if (label.indexOf(words[i]) >= 0) score += 20
      else score += 10
    }
    return score - entry.id.split(".").length
  }

  function menuRows(rest, limit) {
    var words = root.terms(rest)
    var scored = []
    for (var i = 0; i < root.menuEntries.length; i++) {
      var e = root.menuEntries[i]
      var s = words.length > 0 ? root.menuScore(e, words) : -e.id.split(".").length
      if (s >= (words.length > 0 ? 0 : -1)) scored.push({ e: e, s: s })
    }
    // Ties keep Omarchy's own menu order (its file order).
    scored.sort(function(a, b) { return (b.s - a.s) || (a.e.order - b.e.order) })
    var out = []
    for (var j = 0; j < scored.length && out.length < limit; j++) {
      var entry = scored[j].e
      // Conditional rows (when/disabled) open their parent page so Omarchy
      // decides what's available; everything else goes straight to its id.
      var route = entry.conditional && entry.kind === "action" ? entry.id.split(".").slice(0, -1).join(".") : entry.id
      var hint = entry.kind === "action"
        ? (entry.conditional ? "Opens " + (entry.path || "the Omarchy menu") : "Runs from the Omarchy menu")
        : "Opens in the Omarchy menu"
      out.push({ kind: "menu", title: entry.label,
                 subtitle: (entry.path ? entry.path + "  ·  " : "") + hint,
                 icon: "", glyph: entry.icon || "›", tag: entry.kind === "action" ? "Action" : "Menu", payload: route })
    }
    return out
  }

  // ---- Omarchy shortcuts ("keys …") -----------------------------------
  // The same list as Omarchy's keybindings menu, read when the search opens.
  // Each entry keeps the exact line Omarchy prints, because running one goes
  // back through Omarchy's own script (see runShortcut).
  readonly property int maxShortcuts: 60
  property var shortcuts: []

  Process {
    id: shortcutList
    command: ["omarchy-menu-keybindings", "--print"]
    stdout: StdioCollector {
      onStreamFinished: {
        var out = []
        var lines = String(text).split("\n")
        for (var i = 0; i < lines.length; i++) {
          var parts = lines[i].split("→")
          if (parts.length < 2) continue
          var keys = parts[0].trim()
          var desc = parts.slice(1).join("→").trim()
          if (keys && desc) out.push({ keys: keys, desc: desc, line: lines[i] })
        }
        root.shortcuts = out
        if (root.opened && root.shortcutQuery(root.filterText) !== null) root.rebuild()
      }
    }
  }

  // "keys", "key", "shortcut(s)" or "kb", optionally followed by a search;
  // null when the query isn't a shortcut search.
  function shortcutQuery(query) {
    var m = /^\s*(keys?|shortcuts?|kb)(?:\s+(.*))?$/i.exec(String(query || ""))
    return m ? (m[2] || "") : null
  }

  function shortcutRows(rest) {
    var words = root.terms(rest)
    var out = []
    for (var i = 0; i < root.shortcuts.length && out.length < root.maxShortcuts; i++) {
      var s = root.shortcuts[i]
      if (words.length > 0 && !root.matchesAll(s.desc + " " + s.keys, words)) continue
      out.push({ kind: "key", title: s.desc, subtitle: s.keys, icon: "", glyph: "⌘",
                 tag: "Shortcut", payload: s.line })
    }
    if (out.length === 0 && root.shortcuts.length === 0)
      out.push({ kind: "info", title: "Loading Omarchy shortcuts…", subtitle: "", icon: "", glyph: "⌘", tag: "", payload: "" })
    return out
  }

  // Folder holding the stand-in picker, as a plain path (the plugin URL may
  // be file:// or qs://).
  readonly property string binDir: decodeURIComponent(String(Qt.resolvedUrl("bin")).replace(/^[a-z]+:\/\//, ""))

  // Runs a shortcut exactly as Omarchy's keybindings menu does: start
  // omarchy-menu-keybindings with bin/omarchy-menu-select first on PATH; that
  // stand-in answers with the chosen line, and Omarchy dispatches it.
  function runShortcut(line) {
    if (!line) return
    Quickshell.execDetached(["env", "PATH=" + root.binDir + ":" + Quickshell.env("PATH"),
                             "SUPER_SPACES_PICK=" + line, "omarchy-menu-keybindings"])
  }

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
    shortcutList.running = true
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

  // Hyprland global shortcut "anz-super-spaces:toggle". A key bound to
  // hl.dsp.global("anz-super-spaces:toggle") reaches this directly, with no
  // process started per press (omarchy-shell costs ~30 ms of bash + socat).
  // Going through shell.toggle keeps the shell's open/closed state in step.
  GlobalShortcut {
    appid: "anz-super-spaces"
    name: "toggle"
    description: "Toggle Super Spaces search"
    onPressed: {
      if (root.opened) root.dismiss()
      else if (root.shell && typeof root.shell.toggle === "function") root.shell.toggle(root.pluginId, "{}")
      else root.open("{}")
    }
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

  // Other names people type for an app, keyed by desktop id. Only apps that
  // are installed show up (DesktopEntries.byId is null otherwise). Earlier
  // entries win ties, so Zen, the default browser here, leads for "chrome".
  readonly property var aliases: [
    { id: "zen", words: "chrome google chrome firefox safari browser web internet" },
    { id: "chromium", words: "chrome google chrome browser" },
    { id: "com.thisisgm.flea", words: "files finder explorer file manager folders" },
    { id: "org.gnome.Nautilus", words: "files finder explorer file manager" },
    { id: "dev.zed.Zed", words: "code vscode visual studio editor ide" },
    { id: "com.mitchellh.ghostty", words: "terminal console shell iterm" },
    { id: "omacalc", words: "calculator calc" }
  ]

  function aliasMatches(words) {
    var out = []
    if (words.length === 0) return out
    for (var a = 0; a < root.aliases.length; a++) {
      if (!root.matchesAll(root.aliases[a].words, words)) continue
      var entry = DesktopEntries.byId(root.aliases[a].id)
      // Scored like a keyword hit (Omarchy's 6000 tier) minus list order.
      if (entry && !entry.noDisplay) out.push({ entry: entry, score: 6500 - a })
    }
    return out
  }

  // Typed: Omarchy's fuzzy app ranking (sortedEntries returns {entry, score}
  // rows) merged with alias hits, nudged by how often you launch each app.
  // Empty: your most-used apps.
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
    var best = ({})
    var candidates = (root.appLibrary.sortedEntries(query) || []).concat(root.aliasMatches(root.terms(query)))
    for (var c = 0; c < candidates.length; c++) {
      var id = String(candidates[c].entry.id || "")
      var score = candidates[c].score + root.usageBoost(id)
      if (!best[id] || score > best[id].score) best[id] = { entry: candidates[c].entry, score: score }
    }
    var ranked = Object.keys(best).map(function(k) { return best[k] })
    ranked.sort(function(a, b) { return b.score - a.score })
    for (var i = 0; i < ranked.length && out.length < root.maxApps; i++) out.push(root.appRow(ranked[i].entry, false))
    return out
  }

  function rebuild() {
    var query = root.filterText
    var words = root.terms(query)
    var rows = []

    // "keys …" searches Omarchy's shortcuts only, "menu …" its menu only.
    var keysRest = root.shortcutQuery(query)
    var menuRest = keysRest === null ? root.menuQuery(query) : null
    if (keysRest !== null || menuRest !== null) {
      // Cancel file searches still waiting from earlier keystrokes ("ke…").
      root.fileGeneration++
      fileDebounce.stop()
      folderSearch.running = false
      fileSearch.running = false
      rows = keysRest !== null ? root.shortcutRows(keysRest) : root.menuRows(menuRest, root.maxMenu)
      displayModel.clear()
      for (var k = 0; k < rows.length; k++) displayModel.append(Object.assign({ window: "" }, rows[k]))
      root.clampSelection()
      return
    }

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

    // Typing puts apps first (like Raycast), then windows and a web search
    // (files arrive below as fd answers); with no text, open windows lead
    // and your most-used apps follow.
    var hasText = String(query).trim().length > 0
    if (hasText) {
      var q = String(query).trim()
      rows = rows.concat(root.appRows(query))
      if (q.length >= 2) rows = rows.concat(root.menuRows(q, root.maxMenuInline))
      rows = rows.concat(root.windowRows(words))
      rows.push({ kind: "web", title: "Search the web for “" + q + "”", subtitle: "Opens in your default browser",
                  icon: "", glyph: "⌕", tag: "Web", payload: "https://www.google.com/search?q=" + encodeURIComponent(q) })
    } else {
      rows = rows.concat(root.windowRows(words)).concat(root.appRows(query))
    }

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
    // fd answers a home folder in ~10-15 ms, so a short pause after the last
    // keystroke is enough; longer only adds felt delay.
    interval: 80
    onTriggered: {
      if (!root.opened || root.shortcutQuery(root.filterText) !== null) return
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
    } else if (kind === "web") {
      if (payload.indexOf("https://www.google.com/search?q=") === 0) Quickshell.execDetached(["xdg-open", payload])
    } else if (kind === "menu") {
      // Same as `omarchy menu summon <route>`: submenus open, actions run.
      if (payload) Quickshell.execDetached(["omarchy-menu", "summon", payload])
      else Quickshell.execDetached(["omarchy-menu"])
    } else if (kind === "key") {
      root.runShortcut(payload)
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
            text: root.filterText || "Search windows, apps, files, maths — or “keys …” for shortcuts"
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
