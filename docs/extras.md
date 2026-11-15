# Extras

Two optional add-ons. Omarchy never installs scripts or changes your keys on
its own, so you turn these on yourself.

## Super + N: pick a workspace

A small list of all your workspaces, each showing what's open on it:

```
● 2   ghostty: ~  ·  btop
○ 4   flea
○ 9   Zed: my-project
  Other number…
```

Type to filter (by number **or** by what's open, like `zed`), press **Enter**
to go there. **Other number…** lets you type any workspace from 1 to 99.

**Turn it on** — run this once in a terminal:

```bash
ln -s ~/.config/omarchy/plugins/anz.super-spaces/extras/workspace-goto ~/.local/bin/workspace-goto
```

Then add to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + N", "Go to workspace number", os.getenv("HOME") .. "/.local/bin/workspace-goto")
o.bind("SUPER + ALT + N", "Move window to workspace number", os.getenv("HOME") .. "/.local/bin/workspace-goto --move")
```

**Super + Alt + N** does the same but takes the window you're in along with you.

## A Super Spaces page in the Omarchy menu

Adds **Setup → Super Spaces** with handy buttons: open the search, go to a
workspace, edit keys, open the plugin folder, reset app ranking, restart,
update.

**Turn it on:** open `extras/omarchy-menu.super-spaces.jsonc` from the plugin
folder, copy its lines, and paste them between the `{ }` in
`~/.config/omarchy/extensions/omarchy-menu.jsonc`. Save — it appears at once.
