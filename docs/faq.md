# Questions and fixes

**Super + Space does nothing.**
Check the key line is in `~/.config/hypr/bindings.lua` (see
[Getting started](getting-started.md)). Then run `omarchy restart shell`.

**The search opens but files never show up.**
Install `fd`: `omarchy pkg add fd`.

**Enter on a calculation doesn't copy.**
Install `wl-clipboard`: `omarchy pkg add wl-clipboard`.

**`ask` says "Ask AI is off".**
That's the default. Type `settings` and turn on **Ask AI agent (web search)**.
See [AI agents](ai.md).

**`ask` keeps searching and never answers.**
Check your default agent works on its own: run `omarchy agent prompt "hi"` in
a terminal. If it asks you to log in, do that first.

**I added a nickname but it doesn't work.**
Check `aliases.json` is valid JSON (quotes around both sides, commas between
lines). It loads the next time you open the search.

**`ai` shows no sessions.**
Only agents that keep logs on this computer show up: omp, Claude Code, Codex.
Use one of them once and the sessions appear.

**I changed something in the plugin and nothing happened.**
Run `omarchy restart shell`.

**How much memory does it use?**
Almost nothing when closed; about 7 MB while the search is open. It runs inside
the Omarchy shell you already have.

**How do I remove it?**

```bash
omarchy plugin remove anz.super-spaces
rm ~/.local/bin/workspace-goto            # if you set up Super + N
rm -r ~/.local/state/anz.super-spaces     # app ranking
```

Then delete the Super Spaces lines you added to `bindings.lua`,
`looknfeel.lua` and `omarchy-menu.jsonc`.
