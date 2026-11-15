.pragma library

// Tiny arithmetic evaluator for the launcher: numbers, + - * / % ^, parentheses
// and unary minus. A real parser rather than eval(), so typed text can never
// run as code. Returns a finite number, or null when the input isn't maths.

function tokenize(src) {
  var tokens = []
  var i = 0
  while (i < src.length) {
    var c = src.charAt(i)
    if (c === " ") { i++; continue }
    if ("+-*/%^()".indexOf(c) !== -1) { tokens.push(c); i++; continue }
    var m = /^(\d+(\.\d*)?|\.\d+)/.exec(src.slice(i))
    if (!m) return null
    tokens.push(parseFloat(m[0]))
    i += m[0].length
  }
  return tokens
}

function evaluate(input) {
  var src = String(input || "").replace(/^=\s*/, "").replace(/,/g, "").replace(/[x×]/g, "*").replace(/÷/g, "/")
  if (!/\d/.test(src)) return null
  var tokens = tokenize(src)
  if (!tokens || tokens.length === 0) return null
  var pos = 0

  function peek() { return tokens[pos] }
  function next() { return tokens[pos++] }

  // expr := term (('+'|'-') term)*
  function expr() {
    var v = term()
    while (peek() === "+" || peek() === "-") v = next() === "+" ? v + term() : v - term()
    return v
  }
  // term := power (('*'|'/'|'%') power)*
  function term() {
    var v = power()
    while (peek() === "*" || peek() === "/" || peek() === "%") {
      var op = next()
      var r = power()
      v = op === "*" ? v * r : op === "/" ? v / r : v % r
    }
    return v
  }
  // power := unary ('^' power)?   (right-associative)
  function power() {
    var b = unary()
    if (peek() === "^") { next(); return Math.pow(b, power()) }
    return b
  }
  function unary() {
    if (peek() === "-") { next(); return -unary() }
    if (peek() === "+") { next(); return unary() }
    return atom()
  }
  function atom() {
    var t = next()
    if (typeof t === "number") return t
    if (t === "(") {
      var v = expr()
      if (next() !== ")") throw "paren"
      return v
    }
    throw "token"
  }

  try {
    var result = expr()
    if (pos !== tokens.length) return null
    // A bare number ("42") isn't a calculation worth showing.
    if (tokens.length === 1) return null
    return isFinite(result) ? result : null
  } catch (e) {
    return null
  }
}

function format(value) {
  if (value === null) return ""
  var rounded = Math.round(value * 1e10) / 1e10
  return String(rounded)
}
