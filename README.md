# Super Spaces

Omarchy bar workspaces where workspaces past 9 fold away, like the tray drawer.

![Folded (+) and open (-) states](preview.png)

- Workspaces 1–9 show as usual.
- Workspaces 10 and up hide behind **`+N`** (N = how many are folded); click
  it to show them (with their full number, e.g. `15`), and **`-`** to hide
  them again. Open/closed is remembered across shell restarts.
- The toggle turns the theme's urgent colour when a folded workspace has a
  window asking for attention (e.g. a terminal bell).
- The workspace you are on always stays visible, even when folded.

Replaces the built-in `omarchy.workspaces` widget and keeps everything it does:
click to switch, click the current one to cycle its layout, scroll to move.

## Search (windows, apps, files, maths)

Super Spaces also ships a lightweight Raycast-style search that runs inside the
Omarchy shell you already have, so it costs a few MB instead of a separate
launcher process.

- **Windows**: every open window with its app icon, title and workspace. Type
  an app, a title or `space 3` to filter; Enter jumps to it.
- **Apps**: installed applications through Omarchy's own app launcher.
- **Recent files**: files and folders you open from the search come first,
  then the desktop's shared recent list; up to 5 when empty, 3 when typing.
- **Files**: found on demand with [`fd`](https://github.com/sharkdp/fd) while
  you type (home folder, skipping hidden tool data, plus `~/.config`). Nothing
  indexes in the background. Enter opens the file or folder.
- **Maths**: `12*7`, `(1+2)^3`, `= 10/4`; Enter copies the result.
- **Workspace number**: type `14` and pick "Go to workspace 14".
- **Omarchy shortcuts**: start with `keys` (or `shortcut`, `kb`), e.g.
  `keys theme`, to search the same list as Omarchy's keybindings menu. Enter
  runs the shortcut through Omarchy's own `omarchy-menu-keybindings`: the
  plugin starts it with `bin/omarchy-menu-select` first on PATH, a stand-in
  that answers with the chosen line, so Omarchy dispatches it exactly as its
  menu would.
- **Omarchy menu**: start with `menu` (or `omarchy`, `om`) to search every
  page and action of the Omarchy menu, e.g. `menu install`, listed in Omarchy's
  own order with their path (`Install › Development › …`). The best few menu
  matches also appear in normal searches (`lock` → System › Lock). Enter goes
  through `omarchy menu summon`: pages open in the Omarchy menu, actions run
  as they would there, and actions with a `when`/`disabled` condition open
  their parent page so Omarchy decides what is available. Entries come from
  Omarchy's menu file plus `~/.config/omarchy/extensions/omarchy-menu.jsonc`.
- **Clipboard**: start with `clip` (or `cb`) to search Omarchy's clipboard
  history; Enter pastes into the focused window, Shift+Enter only copies. It
  goes through Omarchy's own clipboard helpers.
- **Window actions**: on a window (or a running app) press **Ctrl+W** to close
  it (the search stays open) or **Ctrl+M** to move it: type a workspace number,
  Enter. Esc cancels.
- **Web**: every search ends with "Search the web for …" in your default browser.
- **Other names**: `chrome`/`browser` finds your browser, `files` your file
  manager, `code` your editor, `terminal` your terminal (installed apps only).
  Add your own in `~/.config/omarchy/super-spaces/aliases.json` as
  `{ "<desktop id>": "word word" }` (see `extras/aliases.example.json`); they
  win over the built-in ones and apply the next time the search opens.

Up/Down or Tab move, Enter acts, Esc clears then closes. Needs `fd` and
`wl-copy` (`omarchy pkg add fd wl-clipboard`). Bind it in
`~/.config/hypr/bindings.lua` on a free key. The plugin registers the Hyprland
global shortcut `anz-super-spaces:toggle`, so the key reaches it directly with
no process started per press:

```lua
o.bind("SUPER + SPACE", "Super Spaces search", hl.dsp.global("anz-super-spaces:toggle"))
```

For an instant appearance (Hyprland otherwise fades new layers in over
~180-400 ms), add to `~/.config/hypr/looknfeel.lua`:

```lua
hl.layer_rule({ match = { namespace = "^anz-super-spaces-search$" }, no_anim = true })
```

Performance on a laptop (Arrow Lake, Hyprland 0.56): opening takes ~30 ms of
which the search's own work is 4-9 ms; each keystroke re-ranks windows, apps
and ~430 menu entries in 0-4 ms; file search via fd answers in ~10-15 ms. When
closed it runs nothing and adds no measurable memory to the shell.

## Install

```bash
omarchy plugin add https://github.com/achardz/omarchy-super-spaces.git --enable
omarchy restart shell
```

## Optional: jump to any workspace with Super + N

`extras/workspace-goto` opens a list of your workspaces showing what is on each
one, as `app: window title` (the current workspace is marked `●`). Typing
filters on that content too, so `youtube`, a file name or a project finds the
workspace that has it open. Enter goes there, or pick **Other number…** to
type any workspace from 1 to 99. With `--move` it takes the focused window along.

The plugin installer never runs scripts or touches keybindings, so this is
opt-in. Link the script onto your PATH:

```bash
ln -s ~/.config/omarchy/plugins/anz.super-spaces/extras/workspace-goto ~/.local/bin/workspace-goto
```

Then bind it in `~/.config/hypr/bindings.lua` (check the keys are free with
`omarchy menu keybindings --print`):

```lua
o.bind("SUPER + N", "Go to workspace number", os.getenv("HOME") .. "/.local/bin/workspace-goto")
o.bind("SUPER + ALT + N", "Move window to workspace number", os.getenv("HOME") .. "/.local/bin/workspace-goto --move")
```

## Optional: Setup › Super Spaces in the Omarchy menu

`extras/omarchy-menu.super-spaces.jsonc` adds a **Super Spaces** page under
Setup with: Open Search, Go to Workspace…, Keybindings, Edit Search, Plugin
Folder, Reset App Ranking, Restart Shell and Update Plugin. Paste its entries
inside the `{ }` of `~/.config/omarchy/extensions/omarchy-menu.jsonc`; the
menu reloads on save. The same entries then show up in Super Spaces search
(`menu super`, or just `super spaces`).

## Remove

```bash
omarchy plugin remove anz.super-spaces
rm ~/.local/bin/workspace-goto   # if you set up the Super + N extra
# and delete the "setup.super-spaces…" lines from omarchy-menu.jsonc if added
```

Also delete the two `o.bind` lines if you added them.

MIT — based on Omarchy's `omarchy.workspaces` widget.
