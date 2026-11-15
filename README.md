# Super Spaces

Omarchy bar workspaces where workspaces past 9 fold away, like the tray drawer.

![Folded (+) and open (-) states](preview.png)

- Workspaces 1–9 show as usual.
- Workspaces 10 and up hide behind a **`+`**; click it to show them (with their
  full number, e.g. `15`), and **`-`** to hide them again.
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
- **Files**: found on demand with [`fd`](https://github.com/sharkdp/fd) while
  you type (home folder, skipping hidden tool data, plus `~/.config`). Nothing
  indexes in the background. Enter opens the file or folder.
- **Maths**: `12*7`, `(1+2)^3`, `= 10/4`; Enter copies the result.
- **Workspace number**: type `14` and pick "Go to workspace 14".

Up/Down or Tab move, Enter acts, Esc clears then closes. Needs `fd` and
`wl-copy` (`omarchy pkg add fd wl-clipboard`). Bind it in
`~/.config/hypr/bindings.lua` on a free key, for example:

```lua
o.bind("SUPER + SEMICOLON", "Super Spaces search", "omarchy-shell shell toggle anz.super-spaces '{}'")
```

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

## Remove

```bash
omarchy plugin remove anz.super-spaces
rm ~/.local/bin/workspace-goto   # if you set up the Super + N extra
```

Also delete the two `o.bind` lines if you added them.

MIT — based on Omarchy's `omarchy.workspaces` widget.
