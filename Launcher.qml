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
import "Gestures.js" as Gestures

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
  readonly property int maxRecentFiles: 5
  readonly property int maxRecentFilesTyped: 3
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
    var label = entry.labelLower
    var score = 0
    for (var i = 0; i < words.length; i++) {
      if (entry.search.indexOf(words[i]) < 0) return -1
      if (label.indexOf(words[i]) === 0 || label.indexOf(" " + words[i]) >= 0) score += 30
      else if (label.indexOf(words[i]) >= 0) score += 20
      else score += 10
    }
    return score - entry.depth
  }

  function menuRows(rest, limit) {
    var words = root.terms(rest)
    var scored = []
    // One property read; reading root.menuEntries inside the loop goes back
    // through the QML property each time.
    var entries = root.menuEntries
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      var s = words.length > 0 ? root.menuScore(e, words) : -e.depth
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

  // ---- clipboard history ("clip …") -----------------------------------
  // Omarchy's own history (~/.local/state/omarchy/clipboard-history.json,
  // written by its clipboard manager). Rows own a snapshot, not a position
  // in this mutable list. Never resolve an old row against newer history.
  readonly property int maxClips: 50
  property var clips: []

  FileView {
    path: root.home + "/.local/state/omarchy/clipboard-history.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        root.clips = Array.isArray(parsed) ? parsed : []
      } catch (e) {
        root.clips = []
      }
    }
    onLoadFailed: root.clips = []
  }

  // "clip", "clipboard" or "cb", optionally followed by a search.
  function clipQuery(query) {
    var m = /^\s*(clip|clipboard|cb)(?:\s+(.*))?$/i.exec(String(query || ""))
    return m ? (m[2] || "") : null
  }

  function clipRows(rest) {
    var words = root.terms(rest)
    var out = []
    for (var i = 0; i < root.clips.length && out.length < root.maxClips; i++) {
      var c = root.clips[i]
      var isImage = c && c.type === "image"
      var text = isImage ? String(c.path || "image") : String((c && c.text) || "")
      if (!text) continue
      if (words.length > 0 && !root.matchesAll(text, words)) continue
      var flat = text.replace(/\s+/g, " ").trim()
      var lines = text.split("\n").length
      out.push({ kind: "clip", title: flat.length > 90 ? flat.slice(0, 90) + "…" : flat,
                 subtitle: (isImage ? "Image" : (lines > 1 ? lines + " lines" : text.length + " characters"))
                   + "  ·  Enter pastes, Shift+Enter copies",
                 icon: "", glyph: isImage ? "▣" : "❐", tag: "Clip", payload: JSON.stringify(isImage
                   ? { type: "image", path: String(c.path), mime: String(c.mime || "image/png") }
                   : { type: "text", text: text }) })
    }
    if (out.length === 0)
      out.push({ kind: "info", title: root.clips.length ? "No matching clips" : "Clipboard history is empty",
                 subtitle: "", icon: "", glyph: "❐", tag: "", payload: "" })
    return out
  }

  function useClip(snapshot, copyOnly) {
    // Keep clipboard contents out of argv, environment, logs and temp files.
    // One in-flight request owns its input until the helper has consumed it.
    if (clipPaste.running) return
    clipPaste.snapshot = snapshot
    clipPaste.command = copyOnly
      ? [root.binDir + "/clipboard-paste", "--copy-only"]
      : [root.binDir + "/clipboard-paste"]
    clipPaste.running = true
  }

  Process {
    id: clipPaste
    property string snapshot: ""
    stdinEnabled: true
    onStarted: {
      write(snapshot + "\n")
      snapshot = ""
    }
    onExited: snapshot = ""
  }

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
  // { "<desktop id>": { "count": n, "last": epoch ms } }, saved through
  // bin/private-json, which only touches XDG_STATE_HOME/anz.super-spaces when
  // it is a private directory of ours: a directory another user can write
  // would let them plant app-usage.json as a symlink, and a save that follows
  // it replaces the file it points at. When the directory isn't private the
  // helper refuses, and the ranking lasts only until the shell restarts.
  property var usage: ({})
  property bool usageLoaded: false

  Process {
    id: usageLoad
    command: [root.binDir + "/private-json", "load", "usage"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          if (parsed && typeof parsed === "object" && !Array.isArray(parsed))
            root.usage = Object.assign(parsed, root.usage)
        } catch (e) {}
      }
    }
    // A launch before the saved ranking arrived was merged in above; save
    // only now, so it can't overwrite the file with just that launch.
    onExited: {
      root.usageLoaded = true
      if (usageSave.pending) root.saveUsage()
    }
  }

  Process {
    id: usageSave
    property string pending: ""
    command: [root.binDir + "/private-json", "save", "usage"]
    stdinEnabled: true
    onStarted: {
      write(pending + "\n")
      pending = ""
    }
    onExited: if (pending) running = true
  }

  function saveUsage() {
    usageSave.pending = JSON.stringify(root.usage)
    if (root.usageLoaded && !usageSave.running) usageSave.running = true
  }

  // The files opened from this search are kept in memory only (a list of
  // paths is better left off disk); PersistentProperties carries them across
  // shell reloads, as JSON text so they survive the reload's new JS engine.
  PersistentProperties {
    id: memory
    reloadableId: "anz.super-spaces.launcher"
    property string recentJson: "[]"
    onLoaded: {
      try {
        var recent = JSON.parse(memory.recentJson)
        root.recentOwn = Array.isArray(recent) ? recent : []
      } catch (e) {
        root.recentOwn = []
      }
    }
  }

  // `omarchy-shell anz.super-spaces resetRanking` (the Setup menu's Reset App
  // Ranking row) forgets the launch counts.
  ShellIpc {
    target: "anz.super-spaces"
    function resetRanking(): void {
      root.usage = ({})
      root.saveUsage()
    }
  }

  Component.onCompleted: {
    usageLoad.running = true
    settingsLoad.running = true
  }

  function recordLaunch(id) {
    if (!id) return
    var next = Object.assign({}, root.usage)
    var prev = next[id] || { count: 0, last: 0 }
    next[id] = { count: Math.min(9999, Number(prev.count || 0) + 1), last: Date.now() }
    root.usage = next
    root.saveUsage()
  }

  // Apps started any other way (keybindings, the dock, a terminal) count too:
  // Hyprland reports every new window, and the first window of an app that
  // had none open is a launch. Later windows of a running app (dialogs, a
  // second window) aren't. A launch picked in this search was counted when
  // it was picked, so its first window is skipped for a few seconds.
  property var launchedHere: ({})

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name !== "openwindow") return
      // openwindow>>ADDRESS,WORKSPACE,CLASS,TITLE (the title may hold commas)
      var parts = String(event.data).split(",")
      if (parts.length >= 3) root.countWindowLaunch(parts[0], parts[2])
    }
  }

  function countWindowLaunch(address, cls) {
    if (!cls) return
    var own = String(address).replace(/^0x/, "")
    var lower = cls.toLowerCase()
    var values = Hyprland.toplevels.values || []
    for (var i = 0; i < values.length; i++) {
      if (String(values[i].address || "").replace(/^0x/, "") === own) continue
      if (String((values[i].lastIpcObject || {}).class || "").toLowerCase() === lower) return
    }
    var entry = DesktopEntries.heuristicLookup(cls)
    if (!entry || !entry.id) return
    var id = String(entry.id)
    if (Date.now() - (root.launchedHere[id] || 0) < 10000) return
    root.recordLaunch(id)
  }

  // ---- search sources you can switch on and off ("settings") -----------
  // Saved in ~/.config/omarchy/super-spaces/settings.json as
  // { "sources": { "<name>": true|false } }; anything unset uses its default
  // below. Read and written through bin/private-json, with the same private
  // directory check as the app ranking. Ask AI starts off: it spends agent
  // quota, so it is opt-in. The trackpad rows (swipe, swipeUp, pinch) are not
  // sources: they are gestures, owned by Service.qml and Gestures.js.
  readonly property var sourceList: [
    { key: "apps", label: "Apps", on: true },
    { key: "windows", label: "Open windows", on: true },
    { key: "recent", label: "Recent files", on: true },
    { key: "files", label: "File search (fd)", on: true },
    { key: "agents", label: "AI agent sessions", on: true },
    { key: "menu", label: "Omarchy menu in normal results", on: true },
    { key: "calc", label: "Calculator", on: true },
    { key: "web", label: "Web search row", on: true },
    { key: "ask", label: "Ask AI agent (web search)", on: false },
    { key: "swipe", label: "Trackpad swipe between workspaces", on: false },
    { key: "swipeUp", label: "Trackpad swipe up for overview", on: false },
    { key: "pinch", label: "Trackpad pinch to open search", on: false }
  ]
  // Only what the settings file says explicitly; the rest follow defaults.
  property var sourceState: ({})

  function on(key) {
    if (root.sourceState[key] === true || root.sourceState[key] === false) return root.sourceState[key]
    for (var i = 0; i < root.sourceList.length; i++) if (root.sourceList[i].key === key) return root.sourceList[i].on
    return true
  }

  // Read on start and on every open, so edits made by hand show up without a
  // shell restart.
  Process {
    id: settingsLoad
    command: [root.binDir + "/private-json", "load", "settings"]
    stdout: StdioCollector {
      onStreamFinished: {
        var state = ({})
        try {
          var s = JSON.parse(text).sources || {}
          for (var k in s) if (s[k] === true || s[k] === false) state[k] = s[k]
        } catch (e) {
          if (String(text).trim()) console.warn("Super Spaces: ignoring settings.json, it is not valid JSON")
        }
        root.sourceState = state
        if (root.opened && !root.movingWindow) root.rebuild()
      }
    }
  }

  // The Hyprland config reads settings.json itself, so a gesture toggle syncs
  // Hyprland only once the save has landed.
  Process {
    id: settingsSave
    property string pending: ""
    property var gestureSources: null
    command: [root.binDir + "/private-json", "save", "settings"]
    stdinEnabled: true
    onStarted: {
      write(pending + "\n")
      pending = ""
    }
    onExited: {
      if (pending) {
        running = true
      } else if (gestureSources) {
        Quickshell.execDetached(Gestures.syncCommand(gestureSources))
        gestureSources = null
      }
    }
  }

  function toggleSource(key) {
    var state = Object.assign({}, root.sourceState)
    state[key] = !root.on(key)
    root.sourceState = state
    var sources = ({})
    for (var i = 0; i < root.sourceList.length; i++) sources[root.sourceList[i].key] = root.on(root.sourceList[i].key)
    settingsSave.pending = JSON.stringify({ sources: sources })
    if (!settingsSave.running) settingsSave.running = true
    if (key === "swipe" || key === "swipeUp" || key === "pinch") settingsSave.gestureSources = sources
  }

  // "settings" or "options" lists the sources; Enter flips one.
  function settingsQuery(query) {
    var m = /^\s*(settings|options)(?:\s+(.*))?$/i.exec(String(query || ""))
    return m ? (m[2] || "") : null
  }

  function settingsRows(rest) {
    var words = root.terms(rest)
    var out = []
    for (var i = 0; i < root.sourceList.length; i++) {
      var s = root.sourceList[i]
      if (words.length > 0 && !root.matchesAll(s.label + " " + s.key, words)) continue
      var isOn = root.on(s.key)
      out.push({ kind: "toggle", title: s.label, subtitle: isOn ? "On  ·  Enter turns it off" : "Off  ·  Enter turns it on",
                 icon: "", glyph: isOn ? "●" : "○", tag: isOn ? "On" : "Off", payload: s.key })
    }
    return out
  }

  // ---- AI agent sessions ("ai …") --------------------------------------
  // Sessions of agents logged on this machine (omp; Claude Code and Codex
  // when their logs exist), listed by bin/agent-sessions when the search
  // opens. Enter resumes one in a terminal, in the folder it ran in.
  readonly property int maxAgentsInline: 3
  readonly property int maxAgents: 40
  property var agentSessions: []

  Process {
    id: agentList
    stdout: StdioCollector {
      onStreamFinished: {
        var out = []
        var lines = String(text).split("\n")
        for (var i = 0; i < lines.length; i++) {
          var f = lines[i].split("\t")
          if (f.length < 5 || !f[1]) continue
          out.push({ agent: f[0], id: f[1], title: f[2], cwd: f[3], time: Number(f[4]) || 0 })
        }
        root.agentSessions = out
        if (root.opened && !root.movingWindow) root.rebuild()
      }
    }
  }

  // ---- ask an AI agent to search the web ("ask …") ---------------------
  // Opens omp in a terminal with the question as its first prompt; omp
  // uses its own web_search tool and keeps the chat for follow-ups. The
  // question goes straight into argv, never through a shell.
  // "ask <question>" or "? <question>"; "asks…"/"askew" stay normal searches.
  function askQuery(query) {
    var m = /^\s*(?:ask(?:\s+|$)|\?\s*)(.*)$/i.exec(String(query || ""))
    return m ? m[1] : null
  }

  function askRow(q) {
    return { kind: "ask", title: "Ask AI: “" + q + "”",
             subtitle: (root.defaultAgent || "Your default agent") + " searches the web and answers here",
             icon: "", glyph: "✦", tag: "Ask AI", payload: q }
  }

  function askRows(rest) {
    if (!root.on("ask"))
      return [{ kind: "info", title: "Ask AI is off", subtitle: "Turn it on with “settings” → Ask AI agent (web search)",
                icon: "", glyph: "✦", tag: "Off", payload: "" }]
    var q = String(rest || "").trim()
    if (!q) return [{ kind: "info", title: "Type a question after “ask”", subtitle: "e.g. ask latest hyprland release notes",
                      icon: "", glyph: "✦", tag: "", payload: "" }]
    return [root.askRow(q)]
  }

  // ---- answers rendered in the search ----------------------------------
  // Enter on "Ask AI" runs bin/agent-ask, which asks the system default
  // agent (omarchy-default-agent) non-interactively; the answer is drawn
  // here as plain text. Agents without such a mode open in a terminal via
  // `omarchy agent prompt`, Omarchy's own way. The question is an argv
  // element, never shell text.
  property string defaultAgent: ""
  property bool askView: false
  property bool askRunning: false
  property string askQuestion: ""
  property string askAnswer: ""
  property string askError: ""
  property real askStartedAt: 0
  property int askElapsed: 0

  Process {
    id: whichAgent
    command: [root.binDir + "/agent-ask", "--which"]
    stdout: StdioCollector { onStreamFinished: root.defaultAgent = String(text).trim() }
  }

  Process {
    id: askProc
    stdout: StdioCollector { id: askOut }
    stderr: StdioCollector { id: askErr }
    // A cancelled ask (Esc, or a new question) must not overwrite the view:
    // only an exit while its answer is still awaited counts.
    onExited: function(code) {
      Qt.callLater(function() {
        if (askProc.running || !root.askRunning) return
        root.askRunning = false
        askTicker.stop()
        if (code === 3) {
          // No non-interactive mode for this agent: hand over to Omarchy.
          root.askView = false
          Quickshell.execDetached(["omarchy-agent-prompt", root.askQuestion])
          root.dismiss()
          return
        }
        var out = root.cleanAnswer(String(askOut.text || ""))
        if (code === 0 && out) root.askAnswer = out
        else root.askError = (String(askErr.text || "").trim().split("\n").filter(function(l) { return l && l !== "Working..." }).slice(-3).join("\n"))
          || ("The agent stopped with exit code " + code)
      })
    }
  }

  Timer {
    id: askTicker
    interval: 1000
    repeat: true
    onTriggered: root.askElapsed = Math.round((Date.now() - root.askStartedAt) / 1000)
  }

  // Plain text only (web content never becomes markup); light Markdown tidy.
  function cleanAnswer(text) {
    return String(text).replace(/\*\*(.+?)\*\*/g, "$1").replace(/^#+\s*/gm, "").replace(/`([^`]+)`/g, "$1").trim()
  }

  function startAsk(q) {
    q = String(q || "").trim()
    if (!q) return
    if (askProc.running) askProc.running = false
    root.askQuestion = q
    root.askAnswer = ""
    root.askError = ""
    root.askView = true
    root.askRunning = true
    root.askStartedAt = Date.now()
    root.askElapsed = 0
    askTicker.restart()
    askProc.command = [root.binDir + "/agent-ask", q]
    askProc.running = true
  }

  function leaveAsk() {
    if (askProc.running) askProc.running = false
    askTicker.stop()
    root.askRunning = false
    root.askView = false
    root.setFilter("ask " + root.askQuestion)
  }

  function copyAnswer() {
    if (root.askAnswer) Quickshell.execDetached(["wl-copy", "--", root.askAnswer])
  }

  // Ctrl+O: keep going with the default agent in a terminal.
  function continueAskInTerminal() {
    if (!root.askQuestion) return
    Quickshell.execDetached(["omarchy-agent-prompt", root.askQuestion])
    root.dismiss()
  }


  function agentQuery(query) {
    var m = /^\s*(ai|agents?|sessions?)(?:\s+(.*))?$/i.exec(String(query || ""))
    return m ? (m[2] || "") : null
  }

  function ago(seconds) {
    var d = Math.max(0, Date.now() / 1000 - seconds)
    if (d < 3600) return Math.max(1, Math.round(d / 60)) + " min ago"
    if (d < 86400) return Math.round(d / 3600) + " h ago"
    return Math.round(d / 86400) + " d ago"
  }

  function agentRows(rest, limit) {
    var words = root.terms(rest)
    var out = []
    for (var i = 0; i < root.agentSessions.length && out.length < limit; i++) {
      var s = root.agentSessions[i]
      if (words.length > 0 && !root.matchesAll(s.agent + " " + s.title + " " + s.cwd + " " + s.id, words)) continue
      var where = s.cwd.indexOf(root.home) === 0 ? "~" + s.cwd.slice(root.home.length) : s.cwd
      out.push({ kind: "agent", title: s.title || ("Session " + s.id.slice(0, 8)),
                 subtitle: s.agent + "  ·  " + (where || "~") + "  ·  " + root.ago(s.time),
                 icon: "", glyph: "✦", tag: "Agent",
                 payload: JSON.stringify({ agent: s.agent, id: s.id, cwd: s.cwd }) })
    }
    if (out.length === 0 && limit === root.maxAgents)
      out.push({ kind: "info", title: root.agentSessions.length ? "No matching sessions" : "No agent sessions found",
                 subtitle: "", icon: "", glyph: "✦", tag: "", payload: "" })
    return out
  }

  // Resume command per agent; ids are checked so nothing odd reaches argv.
  function resumeAgent(payload) {
    var s
    try { s = JSON.parse(payload) } catch (e) { return }
    if (!s || !/^[A-Za-z0-9_-]+$/.test(String(s.id))) return
    var cmd = s.agent === "omp" ? ["omp", "--resume", s.id]
      : s.agent === "claude" ? ["claude", "--resume", s.id]
      : s.agent === "codex" ? ["codex", "resume", s.id]
      : null
    if (!cmd) return
    var dir = String(s.cwd || "") || root.home
    Quickshell.execDetached(["uwsm-app", "--", "xdg-terminal-exec", "--dir=" + dir].concat(cmd))
  }

  // ---- recent files ----------------------------------------------------
  // Our own list (files and folders opened from this search, newest first,
  // kept in memory with the app ranking above) merged with the desktop's
  // shared list, which other apps write to.
  property var recentOwn: []
  property var recentSystem: []

  // ~/.local/share/recently-used.xbel: <bookmark href="file://…" modified="…">.
  FileView {
    id: systemRecent
    path: root.home + "/.local/share/recently-used.xbel"
    printErrors: false
    onLoaded: {
      var out = []
      var re = /<bookmark\s[^>]*href="file:\/\/([^"]+)"[^>]*?modified="([^"]+)"/g
      var m
      var text = String(systemRecent.text())
      while ((m = re.exec(text)) !== null) {
        try { out.push({ path: decodeURIComponent(m[1]), last: Date.parse(m[2]) || 0 }) } catch (e) {}
      }
      out.sort(function(a, b) { return b.last - a.last })
      root.recentSystem = out.slice(0, 200)
    }
    onLoadFailed: root.recentSystem = []
  }

  // Both lists load a moment after the search opens; redraw an empty search
  // when they arrive so recent files show up without typing.
  onRecentOwnChanged: if (root.opened && !root.filterText.trim() && !root.movingWindow) root.rebuild()
  onRecentSystemChanged: if (root.opened && !root.filterText.trim() && !root.movingWindow) root.rebuild()

  function recordFile(path, isDir) {
    if (!path) return
    var next = root.recentOwn.filter(function(r) { return r.path !== path })
    next.unshift({ path: path, dir: !!isDir, last: Date.now() })
    root.recentOwn = next.slice(0, 100)
    memory.recentJson = JSON.stringify(root.recentOwn)
  }

  // Paths already listed as recent, so fd results don't repeat them.
  property var shownRecentPaths: ({})

  function recentFileRows(words, limit) {
    var seen = ({})
    var out = []
    var merged = root.recentOwn.concat(root.recentSystem)
    for (var i = 0; i < merged.length && out.length < limit; i++) {
      var r = merged[i]
      var path = String(r.path || "").replace(/\/$/, "")
      if (!path || seen[path]) continue
      seen[path] = true
      if (words.length > 0 && !root.matchesAll(path, words)) continue
      var name = path.slice(path.lastIndexOf("/") + 1) || path
      var shown = path.indexOf(root.home) === 0 ? "~" + path.slice(root.home.length) : path
      out.push({ kind: "file", title: root.shownText(name), subtitle: root.shownText(shown), icon: "",
                 glyph: r.dir ? "▸" : "·", tag: "Recent", payload: path })
    }
    var shownMap = ({})
    for (var j = 0; j < out.length; j++) shownMap[out[j].payload] = true
    root.shownRecentPaths = shownMap
    return out
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
  property int cardWidth: Math.min(Style.space(640), panel.windowWidth - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(560), panel.windowHeight - Style.gapsOut * 2)

  // ---- lifecycle -------------------------------------------------------

  property real iconsScannedAt: 0
  // False while an icon rescan this open may still replace icon paths.
  property bool iconCacheOn: true

  function open(payloadJson) {
    Hyprland.refreshToplevels()
    // Icons can change between opens (an app installed); look them up afresh.
    root.iconCache = ({})
    root.iconCacheOn = true
    Hyprland.refreshWorkspaces()
    // Omarchy rescans icons by itself whenever installed apps change; the
    // scan (find over ~7k icon files, parsed line by line in JS, then every
    // icon binding re-evaluated) is only a backstop for icons that land
    // without an app change, so it runs at most every 5 minutes instead of
    // on every open. While it runs, window icons aren't cached, so this open
    // can't keep paths from before the scan.
    if (root.appLibrary && Date.now() - root.iconsScannedAt > 5 * 60 * 1000) {
      root.appLibrary.refreshIcons()
      root.iconsScannedAt = Date.now()
      root.iconCacheOn = false
    }
    // A file created after the shell started has no watch yet; reading it on
    // each open picks it up (and edits) without a shell restart.
    aliasFile.reload()
    systemRecent.reload()
    if (!settingsLoad.running) settingsLoad.running = true
    if (root.on("agents")) {
      agentList.command = [root.binDir + "/agent-sessions"]
      agentList.running = true
    }
    shortcutList.running = true
    whichAgent.running = true
    root.opened = true
    // An answer still loading (or shown) when the search was closed comes
    // back. `omarchy-shell shell toggle anz.super-spaces '{"query":"sp:2"}'`
    // opens with that text typed (a keybinding can open "sp:" directly).
    var start = ""
    try { start = String(JSON.parse(payloadJson || "{}").query || "") } catch (e) {}
    if (start) root.setFilter(start)
    else if (!root.askView) root.setFilter("")
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.movingWindow = ""
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

  // Window class -> icon. heuristicLookup scans every desktop entry, so it
  // runs once per class while the search is open, not per window per key.
  property var iconCache: ({})

  function appIconFor(cls) {
    if (!cls) return ""
    var hit = root.iconCache[cls]
    if (hit !== undefined) return hit
    var entry = DesktopEntries.heuristicLookup(cls)
    var icon = !entry || !entry.icon ? ""
      : root.appLibrary ? root.appLibrary.iconSource(entry.icon) : Quickshell.iconPath(entry.icon, true)
    if (root.iconCacheOn) root.iconCache[cls] = icon
    return icon
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
  // The windows are indexed once per search (class, and its last dotted part,
  // -> address) instead of rescanned and resplit for every app row.
  property var windowIndex: null

  function runningWindowFor(entry) {
    if (root.windowIndex === null) {
      var index = ({})
      var values = Hyprland.toplevels.values || []
      for (var i = values.length - 1; i >= 0; i--) {
        var cls = String((values[i].lastIpcObject || {}).class || "").toLowerCase()
        if (!cls) continue
        var address = String(values[i].address || "")
        // Walking backwards and writing over earlier hits keeps the first
        // window in Hyprland's order, as the old scan returned.
        index[cls] = address
        index["." + cls.split(".").pop()] = address
      }
      root.windowIndex = index
    }
    var id = String(entry.id || "").toLowerCase()
    var keys = [String(entry.startupClass || "").toLowerCase(), id, id.split(".").pop()]
    for (var k = 0; k < keys.length; k++) {
      if (!keys[k]) continue
      var hit = root.windowIndex[keys[k]] || root.windowIndex["." + keys[k]]
      if (hit) return hit
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
  readonly property var defaultAliases: [
    { id: "zen", words: "chrome google chrome firefox safari browser web internet" },
    { id: "chromium", words: "chrome google chrome browser" },
    { id: "com.thisisgm.flea", words: "files finder explorer file manager folders" },
    { id: "org.gnome.Nautilus", words: "files finder explorer file manager" },
    { id: "dev.zed.Zed", words: "code vscode visual studio editor ide" },
    { id: "com.mitchellh.ghostty", words: "terminal console shell iterm" },
    { id: "omacalc", words: "calculator calc" }
  ]

  // Your own names, from ~/.config/omarchy/super-spaces/aliases.json:
  // { "<desktop id>": "word word …" }. They come first, so they win ties.
  property var userAliases: []
  readonly property var aliases: root.userAliases.concat(root.defaultAliases)

  FileView {
    id: aliasFile
    path: root.home + "/.config/omarchy/super-spaces/aliases.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var out = []
      try {
        var parsed = JSON.parse(text())
        for (var id in parsed) {
          if (typeof parsed[id] === "string" && parsed[id].trim()) out.push({ id: id, words: parsed[id].toLowerCase() })
        }
      } catch (e) {
        console.warn("Super Spaces: ignoring aliases.json, it is not valid JSON")
      }
      root.userAliases = out
    }
    onLoadFailed: root.userAliases = []
  }

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
      // Each app's boost (a log and a clock read) once, not per comparison.
      var boosts = ({})
      var ids = Object.keys(root.usage)
      for (var u = 0; u < ids.length; u++) boosts[ids[u]] = root.usageBoost(ids[u])
      ids.sort(function(a, b) { return boosts[b] - boosts[a] })
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

  // Words that switch the search to one source: badges under the search box
  // with nothing typed, and the list ":" shows (":cl" narrows it).
  readonly property var prefixes: [
    { label: "keys", fill: "keys ", about: "Omarchy keyboard shortcuts" },
    { label: "menu", fill: "menu ", about: "Omarchy menu entries" },
    { label: "clip", fill: "clip ", about: "Clipboard history" },
    { label: "ai", fill: "ai ", about: "AI agent sessions" },
    { label: "ask", fill: "ask ", about: "Ask your AI agent (turn it on in settings)" },
    { label: "settings", fill: "settings", about: "Turn sources on and off" },
    { label: "sp:", fill: "sp:", about: "A workspace's windows as thumbnails: sp:2, then sp:2:1 picks the first" },
    { label: "~/", fill: "~/", about: "Browse folders, starting at home" }
  ]

  function prefixRows(rest) {
    var q = String(rest || "").trim().toLowerCase()
    var out = []
    for (var i = 0; i < root.prefixes.length; i++) {
      var p = root.prefixes[i]
      if (q && p.label.indexOf(q) !== 0 && p.about.toLowerCase().indexOf(q) < 0) continue
      out.push({ kind: "prefix", title: p.label, subtitle: p.about, icon: "", glyph: ":", tag: "Prefix", payload: p.fill })
    }
    if (out.length === 0)
      out.push({ kind: "info", title: "No prefix matches “" + q + "”", subtitle: "Type : on its own to see them all",
                 icon: "", glyph: ":", tag: "", payload: "" })
    return out
  }

  // ---- "sp:N" and "sp:N:I": a workspace's windows, with thumbnails -------
  // "sp:" lists the workspaces that have windows; "sp:2" lists workspace 2's
  // windows, numbered left to right, above a thumbnail of the workspace laid
  // out as on screen; "sp:2:3" highlights the third. Enter (or a click on a
  // thumbnail) goes to that window.
  property var spPreview: null

  function spQuery(query) {
    var m = /^\s*sp:(\d{1,2})?(?::(\d{0,2}))?\s*$/i.exec(String(query || ""))
    return m ? { ws: m[1] ? Number(m[1]) : 0, index: m[2] ? Number(m[2]) : 0 } : null
  }

  function spWindows(ws) {
    var out = []
    var values = Hyprland.toplevels.values || []
    for (var i = 0; i < values.length; i++) {
      var t = values[i]
      var ipc = t.lastIpcObject || {}
      if (!ipc.workspace || Number(ipc.workspace.id) !== ws || !ipc.at || !ipc.size || ipc.hidden) continue
      out.push({ toplevel: t, address: String(t.address || ipc.address || ""),
                 x: Number(ipc.at[0]), y: Number(ipc.at[1]), w: Number(ipc.size[0]), h: Number(ipc.size[1]),
                 cls: String(ipc.class || ""), title: String(t.title || ipc.title || ""), floating: !!ipc.floating })
    }
    out.sort(function(a, b) { return a.x - b.x || a.y - b.y })
    return out
  }

  function spRows(sp) {
    var rows = []
    if (!sp.ws) {
      var ids = (Hyprland.workspaces.values || []).map(function(w) { return w.id })
        .filter(function(id) { return id > 0 }).sort(function(a, b) { return a - b })
      for (var i = 0; i < ids.length; i++) {
        var n = root.spWindows(ids[i]).length
        if (n === 0) continue
        rows.push({ kind: "prefix", title: "sp:" + ids[i], subtitle: n + (n === 1 ? " window" : " windows"),
                    icon: "", glyph: "▦", tag: "Space " + ids[i], payload: "sp:" + ids[i] })
      }
      if (rows.length === 0)
        rows.push({ kind: "info", title: "No windows open", subtitle: "", icon: "", glyph: "▦", tag: "", payload: "" })
      return rows
    }

    var space = (Hyprland.workspaces.values || []).filter(function(w) { return w.id === sp.ws })[0]
    var m = space && space.monitor ? (space.monitor.lastIpcObject || {}) : {}
    var scale = Number(m.scale || 1)
    var monW = Number(m.width || 1920) / scale
    var monH = Number(m.height || 1080) / scale
    if (Number(m.transform || 0) % 2 === 1) { var t = monW; monW = monH; monH = t }
    var monX = Number(m.x || 0), monY = Number(m.y || 0)
    var wins = root.spWindows(sp.ws)
    root.spPreview = {
      ws: sp.ws, monW: monW, monH: monH,
      live: !!(m.activeWorkspace && Number(m.activeWorkspace.id) === sp.ws),
      windows: wins.map(function(w) {
        return { toplevel: w.toplevel, x: w.x - monX, y: w.y - monY, w: w.w, h: w.h, floating: w.floating }
      })
    }
    for (var j = 0; j < wins.length; j++) {
      var w = wins[j]
      rows.push({ kind: "window", title: (j + 1) + "   " + root.shownText(w.title || root.shortClass(w.cls)),
                  subtitle: root.shortClass(w.cls) + "  ·  workspace " + sp.ws, icon: root.appIconFor(w.cls),
                  glyph: "", tag: String(sp.ws), payload: w.address })
    }
    if (wins.length === 0)
      rows.push({ kind: "info", title: "Workspace " + sp.ws + " has no windows", subtitle: "", icon: "", glyph: "▦", tag: "", payload: "" })
    rows.push({ kind: "workspace", title: "Go to workspace " + sp.ws, subtitle: "Switch to workspace " + sp.ws,
                icon: "", glyph: "#", tag: String(sp.ws), payload: String(sp.ws) })
    return rows
  }

  function rebuild() {
    var query = root.filterText
    var words = root.terms(query)
    var rows = []
    root.windowIndex = null
    root.spPreview = null

    // Ctrl+M on a window: the list becomes target workspaces.
    if (root.movingWindow) {
      root.fileGeneration++
      fileDebounce.stop()
      folderSearch.running = false
      fileSearch.running = false
      rows = root.moveRows(query)
      root.showRows(rows)
      return
    }

    // "sp:N[:I]": that workspace's windows with thumbnails.
    var sp = root.spQuery(query)
    if (sp) {
      root.fileGeneration++
      fileDebounce.stop()
      folderSearch.running = false
      fileSearch.running = false
      root.showRows(root.spRows(sp))
      if (sp.index > 0 && root.spPreview && sp.index <= root.spPreview.windows.length)
        root.selectedIndex = sp.index - 1
      return
    }

    // ":" lists the prefixes; Enter types the highlighted one.
    if (/^\s*:/.test(query)) {
      root.fileGeneration++
      fileDebounce.stop()
      folderSearch.running = false
      fileSearch.running = false
      root.showRows(root.prefixRows(query.replace(/^\s*:/, "")))
      return
    }

    // A path ("/", "~", "~/Doc…") lists the next level of that folder.
    var path = root.pathQuery(query)
    if (path) {
      root.schedulePath(path)
      return
    }

    // "keys …", "menu …", "clip …", "ai …" and "settings" each search one
    // source only.
    var keysRest = root.shortcutQuery(query)
    var menuRest = keysRest === null ? root.menuQuery(query) : null
    var clipRest = keysRest === null && menuRest === null ? root.clipQuery(query) : null
    var agentRest = keysRest === null && menuRest === null && clipRest === null ? root.agentQuery(query) : null
    var setRest = root.settingsQuery(query)
    var askRest = root.askQuery(query)
    if (keysRest !== null || menuRest !== null || clipRest !== null || agentRest !== null || setRest !== null || askRest !== null) {
      // Cancel file searches still waiting from earlier keystrokes ("ke…").
      root.fileGeneration++
      fileDebounce.stop()
      folderSearch.running = false
      fileSearch.running = false
      rows = setRest !== null ? root.settingsRows(setRest)
        : keysRest !== null ? root.shortcutRows(keysRest)
        : menuRest !== null ? root.menuRows(menuRest, root.maxMenu)
        : clipRest !== null ? root.clipRows(clipRest)
        : agentRest !== null ? root.agentRows(agentRest, root.maxAgents)
        : root.askRows(askRest)
      root.showRows(rows)
      return
    }

    var calc = root.on("calc") ? Calc.evaluate(query) : null
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
      if (root.on("apps")) rows = rows.concat(root.appRows(query))
      if (root.on("recent")) rows = rows.concat(root.recentFileRows(words, root.maxRecentFilesTyped))
      if (q.length >= 2 && root.on("agents")) rows = rows.concat(root.agentRows(q, root.maxAgentsInline))
      if (q.length >= 2 && root.on("menu")) rows = rows.concat(root.menuRows(q, root.maxMenuInline))
      if (root.on("windows")) rows = rows.concat(root.windowRows(words))
      if (root.on("web"))
        rows.push({ kind: "web", title: "Search the web for “" + q + "”", subtitle: "Opens in your default browser",
                    icon: "", glyph: "⌕", tag: "Web", payload: "https://www.google.com/search?q=" + encodeURIComponent(q) })
      if (root.on("ask") && q.length >= 3) rows.push(root.askRow(q))
    } else {
      if (root.on("windows")) rows = rows.concat(root.windowRows(words))
      if (root.on("apps")) rows = rows.concat(root.appRows(query))
      if (root.on("recent")) rows = rows.concat(root.recentFileRows(words, root.maxRecentFiles))
    }

    root.showRows(rows)
    root.scheduleFiles(query, calc !== null)
  }

  // Writes rows into the list in place. Clearing and refilling the model made
  // the list destroy and rebuild every row (a rectangle, an icon image and
  // three texts each) on each keystroke; overwriting keeps those rows alive
  // and only changes their text and icon. Every row carries the same roles;
  // only running-app rows fill `window`.
  function showRows(rows) {
    for (var i = 0; i < rows.length; i++) {
      var r = rows[i]
      if (r.window === undefined) r.window = ""
      if (i < displayModel.count) displayModel.set(i, r)
      else displayModel.append(r)
    }
    if (displayModel.count > rows.length) displayModel.remove(rows.length, displayModel.count - rows.length)
    root.clampSelection()
  }

  // ---- files, on demand ------------------------------------------------

  property int fileGeneration: 0
  property string pendingFileQuery: ""

  function scheduleFiles(query, isMath) {
    // A search queued by an earlier keystroke must not fire for this one.
    fileDebounce.stop()
    root.fileGeneration++
    folderSearch.running = false
    fileSearch.running = false
    var q = String(query || "").trim()
    if (!root.on("files")) return
    if (q.length < 2 || isMath || /^\d{1,2}$/.test(q)) return
    // With the calculator off, maths still shouldn't start a file search.
    if (!root.on("calc") && Calc.evaluate(q) !== null) return
    root.pendingFileQuery = q
    fileDebounce.restart()
  }

  // Arguments go straight to fd, never through a shell. It walks the home
  // folder without hidden paths (so tool data like ~/.vscode or caches stay
  // out) plus ~/.config explicitly, where dotfiles live. fd also honours
  // .gitignore, which keeps build output and node_modules out of projects.
  // --print0: a file name may hold a newline, and split on lines it would
  // turn into two rows, one of them a relative path chosen by whoever named
  // the file. Paths are split on NUL, which no name can hold.
  function fdCommand(type, limit) {
    return ["fd", "--fixed-strings", "--ignore-case", "--type", type, "--print0",
            "--max-results", String(limit), "--exclude", "node_modules",
            "--", root.pendingFileQuery, root.home, root.home + "/.config"]
  }

  // Absolute paths from fd --print0 output, without trailing slashes.
  function fdPaths(text) {
    return String(text).split("\u0000").filter(function(l) { return l.charAt(0) === "/" })
      .map(function(l) { return l.length > 1 ? l.replace(/\/$/, "") : l })
  }

  // Names are chosen by whoever made the file: control characters and bidi
  // overrides could make one read as another ("doc<RLO>fdp.exe" shows as
  // "docexe.pdf"), so they are shown as "?". The payload keeps the real path.
  function shownText(s) {
    return String(s).replace(/[\u0000-\u001f\u007f\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, "?")
  }

  function appendPaths(text, isDir) {
    var lines = root.fdPaths(text)
    for (var i = 0; i < lines.length; i++) {
      var path = lines[i]
      if (root.shownRecentPaths[path]) continue
      var name = path.slice(path.lastIndexOf("/") + 1)
      var shown = path.indexOf(root.home) === 0 ? "~" + path.slice(root.home.length) : path
      displayModel.append({ kind: "file", title: root.shownText(name), subtitle: root.shownText(shown), icon: "",
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

  // ---- paths: "/", "~" and "~/Doc…" list the next level of a folder ------
  // Folders only until a letter of the next name is typed: a big folder can
  // hold thousands of files, and listing and drawing them all for "/" or
  // "~/Downloads/" would stall the search. fd stops after maxPathRows; the
  // rows are sorted here. Enter goes into a folder, Shift+Enter opens it.
  readonly property int maxPathRows: 200
  property var pathRequest: null
  property var pathFolders: []

  // { dir: absolute folder, typedDir: as typed ("~/Doc/"), prefix: the part
  // of the next name typed so far }, or null when the query isn't a path.
  function pathQuery(query) {
    var q = String(query || "")
    if (!/^(\/|~$|~\/)/.test(q)) return null
    var cut = q.lastIndexOf("/")
    var typedDir = cut < 0 ? "~/" : q.slice(0, cut + 1)
    var dir = typedDir.charAt(0) === "~" ? root.home + typedDir.slice(1) : typedDir
    return { dir: dir, typedDir: typedDir, prefix: cut < 0 ? "" : q.slice(cut + 1) }
  }

  // A full path written the way the query writes it: "~/…" when typed with ~.
  function typedPath(full, path) {
    if (path.typedDir.charAt(0) === "~" && (full === root.home || full.indexOf(root.home + "/") === 0))
      return "~" + full.slice(root.home.length)
    return full
  }

  // Names starting with what was typed, case-insensitive; hidden ones only
  // once a "." is typed. Arguments go straight to fd, never through a shell.
  function pathCommand(path, type) {
    var cmd = ["fd", "--exact-depth", "1", "--type", type, "--max-results", String(root.maxPathRows),
               "--no-ignore", "--ignore-case", "--absolute-path", "--color", "never", "--print0"]
    if (path.prefix.charAt(0) === ".") cmd.push("--hidden")
    cmd.push("--", "^" + path.prefix.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), path.dir)
    return cmd
  }

  function schedulePath(path) {
    fileDebounce.stop()
    root.fileGeneration++
    folderSearch.running = false
    fileSearch.running = false
    pathFolderList.running = false
    pathFileList.running = false
    root.pathRequest = path
    pathDebounce.restart()
  }

  function pathLines(text) {
    return root.fdPaths(text).sort(function(a, b) {
      return a.toLowerCase() < b.toLowerCase() ? -1 : a.toLowerCase() > b.toLowerCase() ? 1 : 0
    })
  }

  function showPathRows(folders, files) {
    var path = root.pathRequest
    var rows = []
    function add(list, isDir) {
      for (var i = 0; i < list.length; i++) {
        var full = list[i]
        rows.push({ kind: "file", title: root.shownText(full.slice(full.lastIndexOf("/") + 1)),
                    subtitle: root.shownText(root.typedPath(full, path)),
                    icon: "", glyph: isDir ? "▸" : "·", tag: isDir ? "Folder" : "File", payload: full })
      }
    }
    add(folders, true)
    add(files, false)
    if (rows.length === 0)
      rows.push({ kind: "info", title: path.prefix ? "Nothing here starts with “" + path.prefix + "”" : "No folders here",
                  subtitle: path.prefix ? path.typedDir : "Type the start of a name to see files too",
                  icon: "", glyph: "▸", tag: "", payload: "" })
    else if (folders.length >= root.maxPathRows || files.length >= root.maxPathRows)
      rows.push({ kind: "info", title: "Showing the first " + root.maxPathRows, subtitle: "Type more of the name to narrow it down",
                  icon: "", glyph: "…", tag: "", payload: "" })
    else if (!path.prefix)
      rows.push({ kind: "info", title: "Folders only", subtitle: "Type the start of a name to see files too",
                  icon: "", glyph: "▸", tag: "", payload: "" })
    root.showRows(rows)
  }

  Timer {
    id: pathDebounce
    interval: 60
    onTriggered: {
      if (!root.opened || !root.pathRequest || root.pathQuery(root.filterText) === null) return
      pathFolderList.generation = root.fileGeneration
      pathFolderList.command = root.pathCommand(root.pathRequest, "d")
      pathFolderList.running = true
    }
  }

  // Folders first; files are only asked for once a name has been started.
  Process {
    id: pathFolderList
    property int generation: -1
    stdout: StdioCollector {
      onStreamFinished: {
        if (pathFolderList.generation !== root.fileGeneration || !root.opened) return
        root.pathFolders = root.pathLines(text)
        if (!root.pathRequest.prefix) {
          root.showPathRows(root.pathFolders, [])
          return
        }
        pathFileList.generation = root.fileGeneration
        pathFileList.command = root.pathCommand(root.pathRequest, "f")
        pathFileList.running = true
      }
    }
  }

  Process {
    id: pathFileList
    property int generation: -1
    stdout: StdioCollector {
      onStreamFinished: {
        if (pathFileList.generation === root.fileGeneration && root.opened)
          root.showPathRows(root.pathFolders, root.pathLines(text))
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

  // ---- window actions on the selected row ------------------------------
  // A window row, or an app row whose app is open, has a window to act on.
  function selectedWindow() {
    if (root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return ""
    var row = displayModel.get(root.selectedIndex)
    var addr = row.kind === "window" ? String(row.payload) : String(row.window || "")
    if (!addr) return ""
    addr = addr.indexOf("0x") === 0 ? addr : "0x" + addr
    return /^0x[0-9a-fA-F]+$/.test(addr) ? addr : ""
  }

  // Alt+T: a terminal in the highlighted folder, or in the folder of the
  // highlighted file; with nothing usable highlighted while typing a path,
  // in that path's folder. Started the way Omarchy starts its terminals, but
  // with the shell as the command: Ghostty runs as a single instance, and a
  // new window with no command ignores --dir and opens in ~.
  function terminalDir() {
    if (root.selectedIndex >= 0 && root.selectedIndex < displayModel.count) {
      var row = displayModel.get(root.selectedIndex)
      if (row.kind === "file") {
        var p = String(row.payload)
        return row.glyph === "▸" ? p : (p.slice(0, p.lastIndexOf("/")) || "/")
      }
    }
    var path = root.pathQuery(root.filterText)
    return path ? path.dir : ""
  }

  function terminalAtSelected() {
    var dir = root.terminalDir()
    if (!dir) return
    root.dismiss()
    Quickshell.execDetached(["uwsm-app", "--", "xdg-terminal-exec", "--dir=" + dir, "sh", "-c",
      "exec \"${SHELL:-$(getent passwd \"$(id -un)\" | cut -d: -f7)}\""])
  }

  // Ctrl+W: close the window, keep the search open so you can close more.
  function closeSelectedWindow() {
    var addr = root.selectedWindow()
    if (!addr) return
    root.dispatch("hl.dsp.window.close({ window = \"address:" + addr + "\" })")
    windowRefresh.restart()
  }

  Timer {
    id: windowRefresh
    interval: 250
    onTriggered: {
      Hyprland.refreshToplevels()
      if (root.opened) root.rebuild()
    }
  }

  // Ctrl+M: pick a target workspace for the window, by number.
  property string movingWindow: ""

  function startMove() {
    var addr = root.selectedWindow()
    if (!addr) return
    root.movingWindow = addr
    root.setFilter("")
  }

  function moveRows(rest) {
    var out = []
    var n = /^\s*(\d{1,2})\s*$/.exec(rest)
    if (n && Number(n[1]) >= 1)
      out.push({ kind: "move", title: "Move to workspace " + n[1], subtitle: "Enter moves the window there; Esc cancels",
                 icon: "", glyph: "→", tag: n[1], payload: n[1] })
    var ids = (Hyprland.workspaces.values || []).map(function(w) { return w.id })
      .filter(function(id) { return id > 0 }).sort(function(a, b) { return a - b })
    for (var i = 0; i < ids.length; i++) {
      if (n && String(ids[i]) === n[1]) continue
      if (rest.trim() && String(ids[i]).indexOf(rest.trim()) !== 0) continue
      out.push({ kind: "move", title: "Move to workspace " + ids[i], subtitle: "Existing workspace",
                 icon: "", glyph: "→", tag: String(ids[i]), payload: String(ids[i]) })
    }
    return out
  }

  // forceNew (Shift+Enter) launches another instance even if the app is open,
  // and copies a clip instead of pasting it.
  function activate(index, forceNew) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    var kind = row.kind
    var payload = String(row.payload)
    var title = String(row.title)
    var windowAddress = String(row.window || "")
    if (kind === "info") return
    // A prefix row types its word and keeps the search open.
    if (kind === "prefix") {
      root.setFilter(payload)
      return
    }
    // Switching a source keeps the search open to flip more.
    if (kind === "toggle") {
      root.toggleSource(payload)
      root.rebuild()
      return
    }
    // Asking keeps the search open and shows the answer in it.
    if (kind === "ask") {
      root.startAsk(payload)
      return
    }
    // In a path, Enter on a folder goes into it (Shift+Enter opens it).
    var path = root.pathQuery(root.filterText)
    if (kind === "file" && path && row.glyph === "▸" && !forceNew) {
      root.setFilter(root.typedPath(payload, path) + "/")
      return
    }
    var moving = root.movingWindow
    root.movingWindow = ""
    root.dismiss()

    if (kind === "move") {
      if (moving && /^\d{1,2}$/.test(payload))
        root.dispatch("hl.dsp.window.move({ window = \"address:" + moving + "\", workspace = \"" + payload + "\", follow = false })")
    } else if (kind === "window") {
      root.focusWindow(payload)
    } else if (kind === "workspace") {
      if (/^\d{1,2}$/.test(payload)) root.dispatch("hl.dsp.focus({ workspace = \"" + payload + "\" })")
    } else if (kind === "app") {
      if (!payload) return
      root.recordLaunch(payload)
      root.launchedHere[payload] = Date.now()
      if (windowAddress && !forceNew) root.focusWindow(windowAddress)
      else if (root.appLibrary) root.appLibrary.launch(payload, title)
    } else if (kind === "file") {
      root.recordFile(payload, row.glyph === "▸")
      // gio opens it with the default app for its type, and starts a
      // terminal app (nvim for text, say) in a terminal. xdg-open runs those
      // in the terminal it was called from, and the shell has none, so the
      // file never showed up.
      Quickshell.execDetached(["gio", "open", "--", payload])
    } else if (kind === "web") {
      if (payload.indexOf("https://www.google.com/search?q=") === 0) Quickshell.execDetached(["xdg-open", payload])
    } else if (kind === "menu") {
      // Same as `omarchy menu summon <route>`: submenus open, actions run.
      if (payload) Quickshell.execDetached(["omarchy-menu", "summon", payload])
      else Quickshell.execDetached(["omarchy-menu"])
    } else if (kind === "key") {
      root.runShortcut(payload)
    } else if (kind === "clip") {
      root.useClip(payload, forceNew)
    } else if (kind === "ask") {
      root.startAsk(payload)
    } else if (kind === "agent") {
      root.resumeAgent(payload)
    } else if (kind === "calc") {
      Quickshell.execDetached(["wl-copy", "--", payload])
    }
  }

  ListModel { id: displayModel }

  // ---- UI --------------------------------------------------------------

  // OverlayWindow where the shell has it, PanelWindow otherwise (Surface.qml).
  Surface {
    id: panel
    shown: root.opened
    namespace: "anz-super-spaces-search"

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
          if (root.askView) {
            if (event.key === Qt.Key_Escape) root.leaveAsk()
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.copyAnswer(); root.dismiss() }
            else if (event.key === Qt.Key_O && event.modifiers === Qt.ControlModifier) root.continueAskInTerminal()
            else if (event.key === Qt.Key_Down) answerFlick.contentY = Math.min(answerFlick.contentY + 40, Math.max(0, answerFlick.contentHeight - answerFlick.height))
            else if (event.key === Qt.Key_Up) answerFlick.contentY = Math.max(0, answerFlick.contentY - 40)
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Escape) {
            if (root.movingWindow) { root.movingWindow = ""; root.setFilter("") }
            else if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_W && event.modifiers === Qt.ControlModifier && !root.movingWindow) {
            root.closeSelectedWindow()
            event.accepted = true
          } else if (event.key === Qt.Key_M && event.modifiers === Qt.ControlModifier && !root.movingWindow) {
            root.startMove()
            event.accepted = true
          } else if (event.key === Qt.Key_T && event.modifiers === Qt.AltModifier && !root.movingWindow) {
            root.terminalAtSelected()
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
            text: root.askView ? "Ask " + (root.defaultAgent || "AI") + ": " + root.askQuestion
              : root.filterText || (root.movingWindow
              ? "Move window to workspace… (type a number)"
              : "Search windows, apps, files, maths")
            color: root.foreground
            opacity: root.filterText || root.askView ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }
        }

        // With nothing typed, the words that switch the search to one source,
        // as small badges under the search box; clicking one types it.
        Row {
          id: prefixBadges
          visible: !root.filterText && !root.askView && !root.movingWindow
          spacing: Style.space(6)

          Repeater {
            model: root.prefixes
            delegate: Rectangle {
              required property var modelData
              width: prefixText.implicitWidth + Style.space(12)
              height: prefixText.implicitHeight + Style.space(4)
              radius: height / 2
              color: "transparent"
              border.width: 1
              border.color: root.foreground
              opacity: prefixMouse.containsMouse ? 0.9 : 0.5

              Text {
                id: prefixText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: modelData.label
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: prefixMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.setFilter(modelData.fill)
                  keyCatcher.forceActiveFocus()
                }
              }
            }
          }
        }

        // "sp:N": the workspace laid out as on screen, each window a screen
        // copy, numbered as in the list. Live only for the workspace on
        // screen; others are one still copy each. Hover highlights, a click
        // goes to the window.
        Rectangle {
          id: spBox
          readonly property var p: root.spPreview
          visible: !root.askView && p !== null && p.windows.length > 0
          width: parent.width
          height: visible ? Math.min(width * p.monH / p.monW, (parent.height - root.headerHeight) * 0.45) : 0
          radius: root.cornerRadius
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
          readonly property real s: visible ? Math.min((width - Style.space(16)) / p.monW, (height - Style.space(16)) / p.monH) : 1

          Item {
            width: spBox.visible ? spBox.p.monW * spBox.s : 0
            height: spBox.visible ? spBox.p.monH * spBox.s : 0
            anchors.centerIn: parent

            Repeater {
              model: spBox.visible ? spBox.p.windows : []
              delegate: Item {
                id: spThumb
                required property var modelData
                required property int index
                readonly property bool picked: index === root.selectedIndex
                x: modelData.x * spBox.s
                y: modelData.y * spBox.s
                width: modelData.w * spBox.s
                height: modelData.h * spBox.s
                z: modelData.floating ? 1 : 0

                ScreencopyView {
                  anchors.fill: parent
                  captureSource: spThumb.modelData.toplevel.wayland
                  live: spBox.p.live
                }
                Rectangle {
                  anchors.fill: parent
                  color: spThumb.picked ? "transparent" : Qt.rgba(0, 0, 0, 0.35)
                  border.width: spThumb.picked ? Style.space(2) : 1
                  border.color: spThumb.picked ? Commons.Color.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.3)
                }
                Rectangle {
                  x: Style.space(4)
                  y: Style.space(4)
                  width: spNum.implicitWidth + Style.space(10)
                  height: spNum.implicitHeight + Style.space(2)
                  radius: height / 2
                  color: spThumb.picked ? Commons.Color.accent : root.background
                  Text {
                    id: spNum
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: String(spThumb.index + 1)
                    color: spThumb.picked ? root.background : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.selectedIndex = spThumb.index
                  onClicked: root.activate(spThumb.index, false)
                }
              }
            }
          }
        }

        ListView {
          visible: !root.askView
          id: resultList
          width: parent.width
          height: parent.height - root.headerHeight - Style.spacing.md
            - (prefixBadges.visible ? prefixBadges.height + Style.spacing.md : 0)
            - (spBox.visible ? spBox.height + Style.spacing.md : 0)
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
              anchors.right: keyBadge.visible ? keyBadge.left : tagText.left
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

            // The highlighted file or folder shows its terminal shortcut.
            Rectangle {
              id: keyBadge
              visible: row.hasCursor && row.kind === "file"
              anchors.right: tagText.left
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              width: badgeText.implicitWidth + Style.space(12)
              height: badgeText.implicitHeight + Style.space(4)
              radius: height / 2
              color: "transparent"
              border.width: 1
              border.color: root.selectedText
              opacity: 0.6

              Text {
                id: badgeText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "Alt+T  Terminal"
                color: root.selectedText
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
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

        // The answer, as plain text, with the keys that act on it.
        Item {
          visible: root.askView
          width: parent.width
          height: parent.height - root.headerHeight - Style.spacing.md

          Flickable {
            id: answerFlick
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: askHint.top
            anchors.bottomMargin: Style.spacing.md
            contentHeight: answerText.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Text {
              id: answerText
              width: answerFlick.width
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              text: root.askRunning
                ? "Searching the web with " + (root.defaultAgent || "your default agent") + "… " + root.askElapsed + " s"
                : (root.askAnswer || root.askError)
              color: root.foreground
              opacity: root.askRunning || root.askError ? 0.6 : 1
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              lineHeight: 1.15
            }
          }

          Text {
            id: askHint
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            textFormat: Text.PlainText
            text: root.askRunning
              ? "Esc cancels  ·  Ctrl+O continue in a terminal"
              : (root.askAnswer ? "Enter copies the answer  ·  Ctrl+O follow up in a terminal  ·  ↑↓ scroll  ·  Esc back"
                                : "Ctrl+O try in a terminal  ·  Esc back")
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }
    }
  }
}
