.pragma library

// Trackpad gestures ("swipe": left/right between workspaces, "swipeUp":
// up/down steps the overview, "pinch": four or more fingers pinching in opens
// the search). Hyprland only honours gestures registered while its config is
// parsed, so the Hyprland config reads settings.json itself (see
// docs/settings.md) and records what it registered in _G.__superSpacesSwipe,
// _G.__superSpacesSwipeUp and _G.__superSpacesPinch. This returns the
// `hyprctl eval` command that reloads the config when those disagree with
// `sources`; once they agree it does nothing, so running it twice is safe.
function syncCommand(sources) {
  var s = sources || {}
  return ["hyprctl", "eval",
    "if (_G.__superSpacesSwipe == true) ~= " + (s.swipe === true)
    + " or (_G.__superSpacesSwipeUp == true) ~= " + (s.swipeUp === true)
    + " or (_G.__superSpacesPinch == true) ~= " + (s.pinch === true)
    + " then hl.exec_cmd(\"hyprctl reload config-only\") end"]
}
