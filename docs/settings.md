# Settings

## Turn things on and off

Type `settings` (or `options`) in the search. You'll see every kind of result
with **On** or **Off**:

| Setting | Starts |
|---|---|
| Apps | On |
| Open windows | On |
| Recent files | On |
| File search | On |
| AI agent sessions | On |
| Omarchy menu in normal results | On |
| Calculator | On |
| Web search row | On |
| Ask AI agent (web search) | **Off** |

Highlight one and press **Enter** to flip it. The search stays open, so you
can change several. Turning something off also stops it from running at all.

## Where things are saved

| File | What's in it |
|---|---|
| `~/.config/omarchy/super-spaces/settings.json` | which results are on or off |
| `~/.config/omarchy/super-spaces/aliases.json` | your app nicknames (you create this) |
| `~/.local/state/anz.super-spaces/app-usage.json` | how often you open each app |
| `~/.local/state/anz.super-spaces/recent-files.json` | files you opened from the search |
| `~/.local/state/anz.super-spaces/bar.json` | whether the bar is folded |

Delete any of these to start fresh. Nothing is ever sent anywhere, except the
questions you `ask` an AI agent.

## Reset the app ranking

Omarchy menu → **Setup → Super Spaces → Reset App Ranking** (if you added the
[Setup page](extras.md)), or delete `app-usage.json` above.
