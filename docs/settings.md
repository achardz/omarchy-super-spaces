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
| Trackpad swipe between workspaces | **Off** |
| Trackpad swipe up for overview | **Off** |
| Trackpad pinch to open search | **Off** |

Highlight one and press **Enter** to flip it. The search stays open, so you
can change several. Turning something off also stops it from running at all.

**Trackpad swipe** makes three fingers left/right slide between workspaces,
following your fingers; keep going or swipe back without lifting. It stops at
your last open workspace. **Trackpad swipe up** opens an overview in two
steps: three fingers up once shrinks this workspace's windows into a grid,
up again shows every workspace on the monitor. Down steps back; click a
window or workspace to go there, Escape or the background closes it.
**Trackpad pinch** opens this search
when four or five fingers pinch in. Flipping any of them reloads your
Hyprland config.

Hyprland only accepts gestures while it reads its config, so they need this
in `~/.config/hypr/input.lua` once:

```lua
do
  local file = io.open(os.getenv("HOME") .. "/.config/omarchy/super-spaces/settings.json", "r")
  local text = file and file:read("a") or ""
  if file then file:close() end
  _G.__superSpacesSwipe = text:match('"swipe"%s*:%s*true') ~= nil
  _G.__superSpacesSwipeUp = text:match('"swipeUp"%s*:%s*true') ~= nil
  _G.__superSpacesPinch = text:match('"pinch"%s*:%s*true') ~= nil
  if _G.__superSpacesSwipe then
    hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
    hl.config({ gestures = {
      workspace_swipe_forever = true,
      workspace_swipe_create_new = false,
      workspace_swipe_distance = 450,
      workspace_swipe_cancel_ratio = 0.15,
      workspace_swipe_min_speed_to_force = 10,
    } })
  end
  if _G.__superSpacesSwipeUp then
    hl.gesture({ fingers = 3, direction = "up", action = { start = function()
      hl.dispatch(hl.dsp.global("anz-super-spaces:overview-up"))
    end } })
    hl.gesture({ fingers = 3, direction = "down", action = { start = function()
      hl.dispatch(hl.dsp.global("anz-super-spaces:overview-down"))
    end } })
  end
  if _G.__superSpacesPinch then
    for fingers = 4, 5 do
      hl.gesture({ fingers = fingers, direction = "pinchin", action = { start = function()
        hl.dispatch(hl.dsp.global("anz-super-spaces:toggle"))
      end } })
    end
  end
end
```

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
