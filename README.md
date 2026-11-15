# Super Spaces

Workspaces and search for [Omarchy](https://omarchy.org/), in one plugin:

- **A smarter workspace bar**: workspaces past 9 fold away, like the tray drawer.
- **A Raycast-style search**: windows, apps, files, maths, clipboard, Omarchy's
  menu and shortcuts in one box. It runs inside the Omarchy shell you already
  have, so it costs a few MB instead of a separate launcher process.

![Folded (+) and open (-) states](preview.png)

## Features at a glance

| Area | What you get |
|---|---|
| Bar | Workspaces 1–9 as usual; 10+ folded behind **`+N`**; urgent highlight; remembers open/closed |
| Search | Windows · apps · recent files · files · maths · workspace numbers · web |
| Omarchy | Its menu (`menu …`), its keyboard shortcuts (`keys …`), its clipboard history (`clip …`) |
| AI agents | Past sessions of agents logged on this PC (`ai …`), resumed in a terminal; ask an agent to search the web (`ask …`) |
| Settings | Switch each search source on or off (`settings`) |
| Window actions | **Ctrl+W** close, **Ctrl+M** move to a workspace, straight from the search |
| Learns | Apps you launch and files you open rise to the top |
| Extras | `Super + N` workspace picker, a Setup › Super Spaces page in the Omarchy menu |

## The bar

Replaces Omarchy's built-in workspaces widget and keeps everything it does:
click to switch, click the current one to cycle its layout, scroll to move.

- **Workspaces 1–9** show as usual.
- **10 and up** fold behind **`+N`** (N = how many are hidden). Click it to
  show them with their full number (`12`, `15`…), **`-`** hides them again.
- **The workspace you are on** always stays visible, even when folded.
- **Attention**: the toggle takes the theme's urgent colour when a folded
  workspace has a window asking for attention (e.g. a terminal bell).
- **Remembered**: open/closed survives shell restarts.

## The search

Open it with your key (see [Setup](#setup)) and type.

**Without a prefix**, results are mixed and ranked:

| You type | You get | Enter does |
|---|---|---|
| *(nothing)* | open windows, your most-used apps, recent files | jump / launch / open |
| an app name, or `chrome`, `files`, `code`, `terminal` | installed apps (running ones tagged *Running*) | switch to it; **Shift+Enter** opens a new window |
| part of a window title, or `space 3` | open windows with their workspace | focus that window |
| part of a file or folder name | recent files first, then files found with `fd` | open it |
| `12*7`, `(1+2)^3`, `= 10/4` | the result | copy it |
| `14` | "Go to workspace 14" | switch there |
| `lock`, `theme`… | the best few Omarchy menu entries | open / run them |
| words from a past agent task | the 3 best matching agent sessions | resume it |
| anything | "Search the web for …" at the end | open in your browser |
| anything (3+ letters), once Ask AI is on | "Ask AI: …" last | your default agent searches the web; the answer shows here |

**With a prefix**, only one source is searched:

| Prefix | Searches | Enter does |
|---|---|---|
| `menu …` (`omarchy`, `om`) | every page and action of the Omarchy menu, in its own order, with their path | open the page or run the action, via `omarchy menu summon` |
| `keys …` (`shortcut`, `kb`) | Omarchy's keybindings, by name or key combo | run the shortcut, via Omarchy's own keybindings script |
| `clip …` (`cb`) | Omarchy's clipboard history | paste it; **Shift+Enter** only copies |
| `ai …` (`agent`, `session`) | sessions of AI agents logged on this PC: omp, plus Claude Code and Codex when their logs exist; newest first, with folder and age | resume it in a terminal in its folder (`omp --resume`, `claude --resume`, `codex resume`) |
| `ask …` (`?`) | — (one row with your question) | ask the system's default agent (`omarchy default agent`) in the background and show its answer here, with sources. Enter copies it, **Ctrl+O** follows up in a terminal, ↑↓ scroll, Esc back. omp uses your `smol` model with thinking off (~10 s); Claude Code, Codex, OpenCode, Pi, Gemini and Qwen use their print modes; other agents open in a terminal via `omarchy agent prompt` |
| `settings` (`options`) | the search sources, each **On**/**Off**. All start on except **Ask AI**, which uses agent quota and is opt-in | flip it (the search stays open) |

**Keys**

| Key | Does |
|---|---|
| Up / Down, Tab / Shift+Tab | move |
| Enter / Shift+Enter | act / alternative action |
| Ctrl+W | close the selected window (the search stays open) |
| Ctrl+M | move the selected window: type a workspace number, Enter |
| Backspace, Ctrl+Backspace, Ctrl+U | delete a character, a word, everything |
| Esc | clear the text, then close |

**Learning and your own names**

- Apps you launch rank higher (capped, so a weak match never beats a strong one).
- Files and folders you open come first in recent files, merged with the
  desktop's shared recent list.
- Your own app names go in `~/.config/omarchy/super-spaces/aliases.json` as
  `{ "<desktop id>": "word word" }` (see `extras/aliases.example.json`). They
  win over the built-in ones and apply the next time the search opens.

**How it reaches things**

- Files are found **on demand** with [`fd`](https://github.com/sharkdp/fd)
  while you type (your home folder without hidden tool data, plus `~/.config`).
  Nothing indexes in the background.
- Maths uses a small parser (numbers and `+ - * / % ^ ( )` only), never `eval`.
- Menu, shortcuts and clipboard go through Omarchy's own commands, so they
  behave exactly as in Omarchy.

## Setup

```bash
omarchy plugin add https://github.com/achardz/omarchy-super-spaces.git --enable
omarchy restart shell
omarchy pkg add fd wl-clipboard   # file search and copying
```

Bind the search in `~/.config/hypr/bindings.lua`. The plugin registers the
Hyprland global shortcut `anz-super-spaces:toggle`, so the key reaches it
directly with no process started per press:

```lua
o.rebind("SUPER + SPACE", "Super Spaces search", hl.dsp.global("anz-super-spaces:toggle"))
-- SUPER + SPACE was the Omarchy menu; keep it reachable, e.g.:
o.rebind("SUPER + ALT + SPACE", "Omarchy menu", { menu = "root" })
```

For an instant appearance (Hyprland otherwise fades new layers in over
~180–400 ms), add to `~/.config/hypr/looknfeel.lua`:

```lua
hl.layer_rule({ match = { namespace = "^anz-super-spaces-search$" }, no_anim = true })
```

## Optional extras

The plugin installer never runs scripts or edits your config, so these are opt-in.

**`Super + N` workspace picker** (`extras/workspace-goto`): a list of your
workspaces showing `app: window title` for each; type to filter by number or
content, Enter goes there, or pick **Other number…** for any workspace 1–99.
`--move` takes the focused window along.

```bash
ln -s ~/.config/omarchy/plugins/anz.super-spaces/extras/workspace-goto ~/.local/bin/workspace-goto
```

```lua
o.bind("SUPER + N", "Go to workspace number", os.getenv("HOME") .. "/.local/bin/workspace-goto")
o.bind("SUPER + ALT + N", "Move window to workspace number", os.getenv("HOME") .. "/.local/bin/workspace-goto --move")
```

**Setup › Super Spaces page** (`extras/omarchy-menu.super-spaces.jsonc`):
Open Search, Go to Workspace…, Keybindings, Edit Search, Plugin Folder, Reset
App Ranking, Restart Shell, Update Plugin. Paste its entries inside the `{ }` of
`~/.config/omarchy/extensions/omarchy-menu.jsonc`; they then also show up in the
search (`super spaces`).

## Files

| Path | Holds |
|---|---|
| `~/.local/state/anz.super-spaces/app-usage.json` | app launch counts (ranking) |
| `~/.local/state/anz.super-spaces/recent-files.json` | files and folders you opened |
| `~/.local/state/anz.super-spaces/bar.json` | bar open/closed |
| `~/.config/omarchy/super-spaces/aliases.json` | your own app names (optional) |
| `~/.config/omarchy/super-spaces/settings.json` | which search sources are on |

Read only: Omarchy's menu files, `~/.local/state/omarchy/clipboard-history.json`,
`~/.local/share/recently-used.xbel`, and the first lines of agent logs
(`~/.omp/agent/sessions`, `~/.claude/projects`, `~/.codex/sessions`) for each
session's title, folder and id.

## Performance

Measured on a laptop (Intel Arrow Lake, Hyprland 0.56): opening takes ~30 ms,
of which the search's own work is 4–9 ms; each keystroke re-ranks windows, apps
and ~430 menu entries in 0–4 ms; `fd` answers in ~10–15 ms. Closed, it runs
nothing and adds no measurable memory to the shell (~7 MB while open).

## Remove

```bash
omarchy plugin remove anz.super-spaces
rm ~/.local/bin/workspace-goto            # if you set up Super + N
rm -r ~/.local/state/anz.super-spaces     # rankings, recent files, bar state
```

Then delete the `o.bind`/`o.rebind` lines you added, and any
`"setup.super-spaces…"` entries in `omarchy-menu.jsonc`.

## License

MIT — based on Omarchy's `omarchy.workspaces` widget.
