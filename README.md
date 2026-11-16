# Super Spaces

One search box for everything on your [Omarchy](https://omarchy.org/) desktop,
and a workspace bar that stays short however many workspaces you use.

![Folded (+) and open (-) states](preview.png)

![Search: apps, maths, the Omarchy menu and shortcuts](demo.gif)

## Who it's for

**New to Omarchy?** You don't have to learn every key first. Press
Super + Space and type what you want: an app, a file, a setting, a shortcut
you forgot, `12*7`. Type `:` to see everything the box can do.

**Keyboard-first, lots of workspaces?** Past 9 workspaces the bar folds the
rest behind `+N`. Type `14` to jump to workspace 14, `sp:14` to see its
windows as thumbnails, Shift+Enter to move a window (or a whole workspace)
somewhere else, and `~/` to walk folders without a file manager. Your hands
never leave the keyboard.

## What you get

- **Bar:** workspaces above 9 fold away behind `+N`.
- **Search (Super + Space):** windows, apps, files, folders, quick maths, the
  Omarchy menu, shortcuts, clipboard history and your AI agents in one box.
  With nothing typed it shows your recent apps, calculations, clips, windows
  and files.
- **Workspace previews:** `sp` lists every workspace, `sp:N` shows its windows
  as live thumbnails, and an overview key (or a three-finger swipe up) shows
  them all at once.
- **Light:** it runs inside the Omarchy shell you already have. Almost no
  memory when closed, about 7 MB while open.
- **Private:** your ranking and settings are saved only in folders that only
  you can read; recent files and calculations stay in memory.

## Install

```bash
omarchy plugin add https://github.com/achardz/omarchy-super-spaces.git --enable
omarchy restart shell
omarchy pkg add fd wl-clipboard
```

Then give the search a key: see [Getting started](docs/getting-started.md).
For a keyboard overview, add to `~/.config/hypr/bindings.lua`:

```lua
o.bind("F3", "Super Spaces overview", hl.dsp.global("anz-super-spaces:overview-toggle"))
```

## Cheat sheet

| Type | Get |
|---|---|
| an app, window or file name | open / jump to it |
| `12*7` | the answer (Enter copies) |
| `14` | go to workspace 14 |
| `sp`, `sp:2`, `sp:2:1` | workspaces, workspace 2's windows, its first window |
| `~/`, `/` | browse folders; Alt+T opens a terminal there |
| `menu …` | the Omarchy menu |
| `keys …` | Omarchy shortcuts |
| `clip …` | clipboard history |
| `ai …` | past AI agent sessions |
| `ask …` | ask your AI agent (off until you turn it on) |
| `settings` | turn results and trackpad gestures on and off |
| `:` | list all of the above |

| Key | Does |
|---|---|
| Enter | open, jump or copy |
| Shift+Enter / Ctrl+M | move the window (or workspace) to another workspace |
| Alt+T | terminal in the highlighted folder |
| Shift+Backspace | clear the search |
| Esc | close |

## Docs

| Page | What's in it |
|---|---|
| [Getting started](docs/getting-started.md) | install, set the key, your first minute, keys |
| [The bar](docs/bar.md) | folding workspaces, the `+N` button |
| [Searching](docs/search.md) | what you can type, closing and moving windows, nicknames |
| [Omarchy menu, shortcuts and clipboard](docs/omarchy.md) | `menu`, `keys`, `clip` |
| [AI agents](docs/ai.md) | find past sessions (`ai`), ask questions (`ask`) |
| [Settings](docs/settings.md) | turn results on and off, gestures, where things are saved |
| [Extras](docs/extras.md) | Super + N workspace picker, a Setup page in the Omarchy menu |
| [Questions and fixes](docs/faq.md) | common problems, removing it |

## License

MIT — based on Omarchy's `omarchy.workspaces` widget.
