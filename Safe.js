.pragma library

// Text other people choose (file names, window titles, clips, agent logs):
// control characters (escape sequences included) and bidi overrides could
// make one thing read as another ("doc<RLO>fdp.exe" shows as "docexe.pdf"),
// so they are shown as "?". Only for display; payloads keep the real value.
function shown(s) {
  return String(s).replace(/[\u0000-\u001f\u007f\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, "?")
}

// A Hyprland monitor name that can sit inside a Lua string literal, or ""
// when it holds anything a connector name doesn't (a quote, say).
function monitorName(s) {
  s = String(s || "")
  return /^[A-Za-z0-9_.:-]+$/.test(s) ? s : ""
}
