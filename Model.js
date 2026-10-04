.pragma library
// predmaxim.workspaces: everything the shell side needs without QML — the config
// (same defaults as hypr/config.lua), desk labels, the login schedule, session plans.

var PLACES = { single: 1, "left-right": 2, "top-bottom": 2, "main-left": 3, grid: 4 }
var SCHEMES = ["single", "left-right", "top-bottom", "main-left", "grid"]
var CHOICES = { foreignWindow: ["tile", "float", "next"], collapse: ["free", "all", "off"], collapseInSession: ["free", "all", "off"] }
var DEFAULTS = { foreignWindow: "tile", collapse: "free", collapseInSession: "free", sequentialLaunch: false, schedule: true }

function desks(t) {
  var out = {}
  Object.keys(t || {}).forEach(function(ws) {
    var d = t[ws]
    if (typeof d !== "object" || d === null || isNaN(Number(ws))) return
    var scheme = PLACES[d.scheme] ? d.scheme : "single"
    var slots = [], slotArr = Array.isArray(d.slots) ? d.slots : []
    for (var i = 0; i < slotArr.length && i < PLACES[scheme]; i++) {
      var s = slotArr[i]
      if (typeof s === "object" && s !== null && typeof s.class === "string" && s.class !== "") {
        slots.push({ app: s.app, class: s.class })
      }
    }
    out[ws] = { scheme: scheme, slots: slots, name: typeof d.name === "object" && d.name !== null ? d.name : { mode: "number" } }
  })
  return out
}

function normalize(raw) {
  var r = raw && typeof raw === "object" ? raw : {}, c = {}
  Object.keys(DEFAULTS).forEach(function(k) {
    if (CHOICES[k]) c[k] = CHOICES[k].indexOf(r[k]) >= 0 ? r[k] : DEFAULTS[k]
    else c[k] = typeof r[k] === typeof DEFAULTS[k] ? r[k] : DEFAULTS[k]
  })
  c.singleInstance = Array.isArray(r.singleInstance) ? r.singleInstance : []
  c.workspaces = desks(r.workspaces)
  c.sessions = {}
  Object.keys(r.sessions || {}).forEach(function(n) {
    var s = r.sessions[n]
    if (typeof s === "object" && s !== null) c.sessions[n] = { workspaces: desks(s.workspaces), schedule: s.schedule || null }
  })
  c.activeSession = typeof r.activeSession === "string" ? r.activeSession : ""
  return c
}

function activeDesks(c) { return c.activeSession && c.sessions[c.activeSession] ? c.sessions[c.activeSession].workspaces : c.workspaces }

function trimName(text) { var t = String(text || ""); return t.length > 50 ? t.slice(0, 50) + "…" : t }

// "2 Firefox": dynamic — the fullscreen window, else the oldest one; static — own text.
function deskLabel(ws, desk, windows, appName) {
  var name = ""
  var mode = desk && desk.name ? desk.name.mode : "number"
  if (mode === "static") name = desk.name.text || ""
  else if (mode === "dynamic" && windows.length) {
    var w = windows.filter(function(x) { return x.fullscreen > 0 })[0] || windows[0]
    name = appName(w.class) || w.class
  }
  name = trimName(name)
  return name ? ws + " " + name : String(ws)
}

function minutes(hhmm) { var p = String(hhmm || "").split(":"); return Number(p[0]) * 60 + Number(p[1] || 0) }
function weekday(d) { return d.getDay() === 0 ? 7 : d.getDay() }

function scheduleAt(c, date) {
  if (!c.schedule) return ""
  var now = date.getHours() * 60 + date.getMinutes(), day = weekday(date)
  var names = Object.keys(c.sessions)
  for (var i = 0; i < names.length; i++) {
    var s = c.sessions[names[i]].schedule
    if (s && (s.days || []).indexOf(day) >= 0 && now >= minutes(s.from) && now < minutes(s.to)) return names[i]
  }
  return ""
}

function overlaps(sessions) {
  var names = Object.keys(sessions), out = []
  for (var i = 0; i < names.length; i++) for (var j = i + 1; j < names.length; j++) {
    var a = sessions[names[i]].schedule, b = sessions[names[j]].schedule
    if (!a || !b) continue
    var day = (a.days || []).some(function(d) { return (b.days || []).indexOf(d) >= 0 })
    if (day && minutes(a.from) < minutes(b.to) && minutes(b.from) < minutes(a.to)) out.push([names[i], names[j]])
  }
  return out
}

function classesOf(ds) {
  var out = Object.create(null)
  Object.keys(ds).forEach(function(ws) { ds[ws].slots.forEach(function(s) { out[s.class] = ws }) })
  return out
}

// First desk >= from that is not a session desk and holds no window that stays.
function freeDesk(next, occupied, moved, from) {
  var n = from
  while (next[String(n)] || (occupied[String(n)] && !moved[String(n)])) n++
  return n
}

// count free desks from `from` on, for windows leaving the session (unclosable ones).
// windows: the ones that stay (not the leaving ones).
function freeDesks(next, windows, count, from) {
  var occupied = Object.create(null), moved = Object.create(null), cls = classesOf(next), out = []
  windows.forEach(function(w) {
    occupied[String(w.ws)] = true
    if (cls[w.class] !== undefined || next[String(w.ws)]) moved[String(w.ws)] = true
  })
  var n = from
  for (var i = 0; i < count; i++) { n = freeDesk(next, occupied, moved, n); out.push(n++) }
  return out
}

// What a switch does to the open windows: close the previous session's apps that the
// next one doesn't have; move the next one's open apps to their desks; strangers on the
// next session's desks go after its last desk; launch the missing apps by place order.
function sessionPlan(c, from, to, windows) {
  var prev = from && c.sessions[from] ? c.sessions[from].workspaces : {}
  var next = to && c.sessions[to] ? c.sessions[to].workspaces : c.workspaces
  var prevCls = classesOf(prev), nextCls = classesOf(next)
  var nums = Object.keys(next).map(Number)
  var lastDesk = nums.length ? Math.max.apply(null, nums) : 0
  var plan = { close: [], move: [], launch: [] }, open = {}, moved = {}, occupied = Object.create(null)

  // Track which desks currently hold windows
  windows.forEach(function(w) { occupied[String(w.ws)] = true })

  var free = lastDesk + 1
  windows.forEach(function(w) {
    if (nextCls[w.class] !== undefined) {
      open[w.class] = true
      moved[String(w.ws)] = true
      if (String(w.ws) !== nextCls[w.class]) plan.move.push({ addr: w.address, ws: Number(nextCls[w.class]) })
    } else if (prevCls[w.class] !== undefined) {
      plan.close.push(w.address)
    } else if (next[String(w.ws)]) {
      moved[String(w.ws)] = true
      // Find next free desk: skip session desks and desks with unmoved windows
      free = freeDesk(next, occupied, moved, free)
      plan.move.push({ addr: w.address, ws: free })
      free++
    }
  })
  Object.keys(next).sort(function(a, b) { return a - b }).forEach(function(ws) {
    next[ws].slots.forEach(function(s, i) {
      if (!open[s.class]) plan.launch.push({ ws: ws, slot: i + 1, app: s.app, class: s.class })
    })
  })
  return plan
}
