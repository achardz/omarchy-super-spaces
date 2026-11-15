.pragma library

// Reads Omarchy's menu definition (JSONC: comments and trailing commas) into
// a flat, searchable list. Strings are skipped while stripping, so "//" in a
// URL inside an action survives.

function stripJsonc(text) {
  var src = String(text || "")
  var out = ""
  var i = 0
  var inString = false
  while (i < src.length) {
    var c = src.charAt(i)
    var n = src.charAt(i + 1)
    if (inString) {
      out += c
      if (c === "\\") { out += n; i += 2; continue }
      if (c === "\"") inString = false
      i++
      continue
    }
    if (c === "\"") { inString = true; out += c; i++; continue }
    if (c === "/" && n === "/") { while (i < src.length && src.charAt(i) !== "\n") i++; continue }
    if (c === "/" && n === "*") {
      i += 2
      while (i < src.length && !(src.charAt(i) === "*" && src.charAt(i + 1) === "/")) i++
      i += 2
      continue
    }
    if (c === ",") {
      // Drop a trailing comma: the next non-space character closes a block.
      var j = i + 1
      while (j < src.length && /\s/.test(src.charAt(j))) j++
      if (src.charAt(j) === "}" || src.charAt(j) === "]") { i++; continue }
    }
    out += c
    i++
  }
  return out
}

function parse(text) {
  try {
    var value = JSON.parse(stripJsonc(text))
    return value && typeof value === "object" ? value : {}
  } catch (e) {
    return {}
  }
}

// User entries extend or override defaults field by field, as Omarchy does.
function merge(defaults, user) {
  var items = {}
  var k
  for (k in defaults) items[k] = Object.assign({}, defaults[k])
  for (k in user) items[k] = Object.assign({}, items[k] || {}, user[k])
  return items
}

function parentOf(id) {
  var at = id.lastIndexOf(".")
  return at === -1 ? "" : id.slice(0, at)
}

// Flat rows: { id, label, path ("System › Lock"), icon, iconFont, kind,
// conditional, search }. kind follows Omarchy: action, link (target), submenu.
function entries(items) {
  var out = []
  for (var id in items) {
    var item = items[id]
    if (!item || !item.label) continue
    var labels = []
    var cursor = parentOf(id)
    while (cursor) {
      labels.unshift(items[cursor] && items[cursor].label ? items[cursor].label : cursor)
      cursor = parentOf(cursor)
    }
    var kind = item.action ? "action" : (item.target ? "link" : "submenu")
    var aliases = Array.isArray(item.aliases) ? item.aliases.join(" ") : ""
    out.push({
      id: id,
      // Position in Omarchy's menu file (object keys keep file order), so ties
      // list entries the way Omarchy's own menu does.
      order: out.length,
      label: String(item.label),
      path: labels.join(" › "),
      icon: String(item.icon || ""),
      iconFont: String(item.iconFont || ""),
      kind: kind,
      conditional: !!(item.when || item.disabled),
      search: (labels.join(" ") + " " + item.label + " " + aliases + " " + (item.description || "") + " " + id.replace(/[._-]/g, " ")).toLowerCase()
    })
  }
  return out
}
