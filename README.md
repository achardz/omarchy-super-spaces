# Super Spaces

Omarchy bar workspaces where workspaces past 9 fold away, like the tray drawer.

![Folded (+) and open (-) states](preview.png)

- Workspaces 1–9 show as usual.
- Workspaces 10 and up hide behind a **`+`**; click it to show them (with their
  full number, e.g. `15`), and **`-`** to hide them again.
- The workspace you are on always stays visible, even when folded.

Replaces the built-in `omarchy.workspaces` widget and keeps everything it does:
click to switch, click the current one to cycle its layout, scroll to move.

## Install

```bash
omarchy plugin add https://github.com/achardz/omarchy-super-spaces.git --enable
omarchy restart shell
```

## Optional: jump to any workspace with Super + N

`extras/workspace-goto` opens a list of your workspaces with the apps on each
(the current one marked `●`). Type to filter, Enter to go, or pick
**Other number…** to type any workspace from 1 to 99. With `--move` it takes
the focused window along.

The plugin installer never runs scripts or touches keybindings, so this is
opt-in. Link the script onto your PATH:

```bash
ln -s ~/.config/omarchy/plugins/anzlaptop.super-spaces/extras/workspace-goto ~/.local/bin/workspace-goto
```

Then bind it in `~/.config/hypr/bindings.lua` (check the keys are free with
`omarchy menu keybindings --print`):

```lua
o.bind("SUPER + N", "Go to workspace number", os.getenv("HOME") .. "/.local/bin/workspace-goto")
o.bind("SUPER + ALT + N", "Move window to workspace number", os.getenv("HOME") .. "/.local/bin/workspace-goto --move")
```

## Remove

```bash
omarchy plugin remove anzlaptop.super-spaces
rm ~/.local/bin/workspace-goto   # if you set up the Super + N extra
```

Also delete the two `o.bind` lines if you added them.

MIT — based on Omarchy's `omarchy.workspaces` widget.
