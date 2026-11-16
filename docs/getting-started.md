# Getting started

Super Spaces gives Omarchy two things:

1. **A tidier workspace bar.** Workspaces above 9 tuck away behind a `+`.
2. **A search box** (like Raycast or Spotlight) for your windows, apps, files
   and more.

## Install

Open a terminal and run:

```bash
omarchy plugin add https://github.com/achardz/omarchy-super-spaces.git --enable
omarchy restart shell
omarchy pkg add fd wl-clipboard
```

The last line installs two small tools: `fd` finds files, `wl-clipboard`
copies results.

## Give the search a key

Open your key settings: Omarchy menu → **Setup → Keybindings**
(the file `~/.config/hypr/bindings.lua`). Add these two lines at the end:

```lua
o.rebind("SUPER + SPACE", "Super Spaces search", hl.dsp.global("anz-super-spaces:toggle"))
o.rebind("SUPER + ALT + SPACE", "Omarchy menu", { menu = "root" })
```

Now **Super + Space** opens the search, and the Omarchy menu moves to
**Super + Alt + Space**. Save the file; it applies straight away.

> Want it to pop up instantly, with no fade? Add this line to
> `~/.config/hypr/looknfeel.lua`:
>
> ```lua
> hl.layer_rule({ match = { namespace = "^anz-super-spaces-search$" }, no_anim = true })
> ```

## Your first minute

1. Press **Super + Space**.
2. Type a few letters of an app, say `fle`. Press **Enter** to open it.
3. Press **Super + Space** again and type `12*7`. Press **Enter**: `84` is
   copied.
4. Type `menu`. You'll see the whole Omarchy menu, searchable.
5. Press **Esc** to close.

## Keys inside the search

| Key | What it does |
|---|---|
| ↑ / ↓ (or Tab) | move up and down |
| Enter | open / run the highlighted result |
| Shift + Enter | the other option (new window, copy instead of paste) |
| Ctrl + W | close the highlighted window |
| Ctrl + M | move the highlighted window to another workspace |
| Alt + T | open a terminal in the highlighted folder (or the highlighted file's folder) |
| Backspace / Shift + Backspace (or Ctrl + U) | delete a letter / clear everything |
| Esc | clear, then close |

## Next

- [The bar](bar.md)
- [Searching](search.md)
- [Omarchy menu, shortcuts and clipboard](omarchy.md)
- [AI agents](ai.md)
- [Settings](settings.md)
- [Extras](extras.md)
- [Questions and fixes](faq.md)
