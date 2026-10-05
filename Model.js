.pragma library
// predmaxim.workspaces: everything the shell side needs without QML — the config
// (same defaults as hypr/config.lua), desk labels, the login schedule, session plans.

var PLACES = { single: 1, "left-right": 2, "top-bottom": 2, "main-left": 3, grid: 4 }
var SCHEMES = ["single", "left-right", "top-bottom", "main-left", "grid"]
var CHOICES = { foreignWindow: ["tile", "float", "next"], collapse: ["free", "all", "off"], collapseInSession: ["free", "all", "off"] }
var DEFAULTS = { foreignWindow: "tile", collapse: "free", collapseInSession: "free", sequentialLaunch: false, schedule: true, hideNoSession: true }

function desks(t) {
  var out = {}
  Object.keys(t || {}).forEach(function(ws) {
    var d = t[ws]
    if (typeof d !== "object" || d === null || isNaN(Number(ws))) return
    var scheme = PLACES[d.scheme] ? d.scheme : "single"
    // Places keep their numbers: an empty place is null (trailing ones dropped).
    var slots = [], slotArr = Array.isArray(d.slots) ? d.slots : []
    for (var i = 0; i < slotArr.length && i < PLACES[scheme]; i++) {
      var s = slotArr[i]
      slots.push(typeof s === "object" && s !== null && typeof s.class === "string" && s.class !== "" ? { app: s.app, class: s.class } : null)
    }
    while (slots.length && !slots[slots.length - 1]) slots.pop()
    out[ws] = { scheme: scheme, slots: slots, name: typeof d.name === "object" && d.name !== null ? d.name : { mode: "number" } }
  })
  return out
}

// Raw slots with place i (0-based) set to `slot` (null clears it), cut to `places`,
// holes as null, no trailing nulls.
function setSlot(slots, i, slot, places) {
  var out = (Array.isArray(slots) ? slots : []).slice(0, places)
  while (out.length < i) out.push(null)
  if (i < places) out[i] = slot
  while (out.length && !out[out.length - 1]) out.pop()
  return out
}

// Raw slots cut to `places`, no trailing nulls.
function fitSlots(slots, places) {
  var out = (Array.isArray(slots) ? slots : []).slice(0, places)
  while (out.length && !out[out.length - 1]) out.pop()
  return out
}

function hasSlots(desk) { return !!desk && desk.slots.some(function(s) { return s }) }

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

// A window class as people read it: "org.omarchy.agent" → "Agent",
// "chrome-youtube.com__-Default" (a web app) → "Youtube".
function prettyClass(cls) {
  var c = String(cls || ""), web = c.match(/^(?:chrome|brave|chromium|msedge)-(.+?)__/)
  var part = web ? web[1].replace(/^www\./, "").split(".")[0] : c.split(".").pop()
  return part ? part.charAt(0).toUpperCase() + part.slice(1) : c
}

// The app name for a window class from desktop entries [{id, name, startupClass}]:
// by startupClass, by id without ".desktop", then by the class's last dot-segment
// (not for web apps — their segments are domains); else prettyClass.
function appNameOf(cls, entries) {
  var hit = entryOf(cls, entries)
  return hit && hit.name ? hit.name : prettyClass(cls)
}
// The desktop entry of a window class (same matching as appNameOf), null if none;
// exact — only by startupClass or id, no guess by the last segment.
function entryOf(cls, entries, exact) {
  var lc = String(cls || "").toLowerCase(), last = lc.split(".").pop(), web = /__/.test(lc)
  var low = function(s) { return String(s || "").toLowerCase() }
  var id = function(e) { return low(e.id).replace(/\.desktop$/, "") }
  var tests = [function(e) { return low(e.startupClass) === lc }, function(e) { return id(e) === lc }]
  if (!exact && !web && last) tests.push(function(e) { return id(e).split(".").pop() === last || low(e.startupClass).split(".").pop() === last })
  for (var t = 0; t < tests.length; t++) {
    var hit = (entries || []).filter(function(e) { return e.name && tests[t](e) })[0]
    if (hit) return hit
  }
  return null
}

// Open windows as raw desks of a set: desks 1–9, one place per window in their order,
// the smallest scheme that holds them. Not kept (`lost`, their classes): windows with
// no desktop entry of exactly their class (a guess would launch another app),
// windows off desks 1–9. Every window of an app is kept, on the desk of its first one:
// the engine binds a class to one desk. A desk may come out with more than 4 windows:
// mergeDesks moves the rest.
var SCHEME_FOR = [null, "single", "left-right", "main-left", "grid"]
function captureDesks(windows, entries) {
  var byWs = {}, deskOf = {}, lost = []
  ;(windows || []).forEach(function(w) {
    var e = w.class ? entryOf(w.class, entries, true) : null
    if (!e || !(w.ws >= 1 && w.ws <= 9)) return lost.push(w.class || w.title || "?")
    var ws = deskOf[w.class] = deskOf[w.class] || w.ws
    ;(byWs[ws] = byWs[ws] || []).push({ app: String(e.id).replace(/\.desktop$/, ""), class: w.class })
  })
  var desks = {}
  Object.keys(byWs).forEach(function(ws) {
    var slots = byWs[ws]
    desks[ws] = { scheme: SCHEME_FOR[Math.min(slots.length, 4)], slots: slots, name: { mode: "number" } }
  })
  return { desks: desks, lost: lost }
}

// Rename session `from` to `to` in raw config: same key order, the active one too.
// {raw} or {error: "empty" | "regular" | "exists" | "missing"}.
function renameSession(raw, from, to, regularName) {
  to = String(to || "").trim()
  var ss = raw && raw.sessions || {}
  var has = function(k) { return Object.prototype.hasOwnProperty.call(ss, k) }
  if (!has(from)) return { error: "missing" }
  if (!to) return { error: "empty" }
  if (to.toLowerCase() === String(regularName || "").toLowerCase() || to === "Regular") return { error: "regular" }
  if (to !== from && has(to)) return { error: "exists" }
  var next = JSON.parse(JSON.stringify(raw)), out = {}
  Object.keys(ss).forEach(function(k) { out[k === from ? to : k] = next.sessions[k] })
  next.sessions = out
  if (next.activeSession === from) next.activeSession = to
  return { raw: next }
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
  Object.keys(ds).forEach(function(ws) { ds[ws].slots.forEach(function(s) { if (s) out[s.class] = ws }) })
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
  // open[class]: windows of it open — that many of its places need no launch.

  // Track which desks currently hold windows
  windows.forEach(function(w) { occupied[String(w.ws)] = true })

  var free = lastDesk + 1
  windows.forEach(function(w) {
    if (nextCls[w.class] !== undefined) {
      open[w.class] = (open[w.class] || 0) + 1
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
      if (s && !(open[s.class]-- > 0)) plan.launch.push({ ws: ws, slot: i + 1, app: s.app, class: s.class })
    })
  })
  return plan
}

// A place of the desks in force was edited (ws, slot 1-based): launch its app if no
// window of it is open, else move that window to the desk. Other places, other
// windows and closed apps of other places are left alone.
function applyPlan(c, active, windows, ws, slot) {
  var ds = active && c.sessions[active] ? c.sessions[active].workspaces : c.workspaces
  var d = ds[String(ws)], s = d && d.slots[slot - 1], out = { launch: [], move: [] }
  if (!s) return out
  var w = windows.filter(function(x) { return x.class === s.class })[0]
  if (!w) out.launch.push({ ws: String(ws), slot: slot, app: s.app, class: s.class })
  else if (String(w.ws) !== String(ws)) out.move.push({ addr: w.address, ws: Number(ws) })
  return out
}

// «Launch» on the set in force: every missing app of it, open bound apps to their
// desks; nothing closes, windows of other apps stay.
function launchPlan(c, active, windows) {
  var p = sessionPlan(c, active, active, windows)
  var cls = classesOf(active && c.sessions[active] ? c.sessions[active].workspaces : c.workspaces), byAddr = {}
  windows.forEach(function(w) { byAddr[w.address] = w })
  return { launch: p.launch, move: p.move.filter(function(m) { return byAddr[m.addr] && cls[byAddr[m.addr].class] !== undefined }) }
}

// Desks a and b of a set ("" — regular) trade places: name, scheme, slots; the numbers
// stay. A deep copy of raw; an absent desk stays absent on the other number.
function swapDesks(raw, set, a, b) {
  var next = JSON.parse(JSON.stringify(raw || {}))
  var holder = set ? (next.sessions = next.sessions || {}, next.sessions[set] = next.sessions[set] || {}) : next
  var ds = holder.workspaces = holder.workspaces || {}, da = ds[String(a)], db = ds[String(b)]
  delete ds[String(a)]; delete ds[String(b)]
  if (db !== undefined) ds[String(a)] = db
  if (da !== undefined) ds[String(b)] = da
  return next
}

// After a swap of desks a and b in the set in force (c — the new config): open windows
// on those desks whose class is bound go to their desk; unbound ones stay.
function swapMoves(c, active, windows, a, b) {
  var cls = classesOf(active && c.sessions[active] ? c.sessions[active].workspaces : c.workspaces)
  return windows.filter(function(w) {
    var to = cls[w.class]
    // Only between the two swapped desks: a window bound to a third desk stays put.
    return (String(w.ws) === String(a) || String(w.ws) === String(b)) && (to === String(a) || to === String(b)) && to !== String(w.ws)
  }).map(function(w) { return { addr: w.address, ws: Number(cls[w.class]) } })
}

// The draft: a set's desks (`setDesks`, normalized; {} for a new set) with the captured
// windows (`captured`, captureDesks().desks) added, counted by app: as many windows of
// an app as the set has places for it stay where they are; more of an app the set has
// join its desk; a new app takes a free place of its desk. The scheme grows to fit (up
// to the grid); a new app that doesn't fit goes to the nearest empty desk, then the
// next one; the rest — to `lost` (classes).
function mergeDesks(setDesks, captured) {
  var desks = JSON.parse(JSON.stringify(setDesks || {})), lost = [], over = [], have = classesOf(desks), left = {}
  Object.keys(desks).forEach(function(ws) { desks[ws].slots.forEach(function(s) { if (s) left[s.class] = (left[s.class] || 0) + 1 }) })
  var put = function(ws, s) {
    var d = desks[ws] = desks[ws] || { scheme: "single", slots: [], name: { mode: "number" } }
    var i = 0
    while (d.slots[i]) i++
    if (i >= 4) return false
    while (i >= PLACES[d.scheme]) d.scheme = SCHEME_FOR[PLACES[d.scheme] + 1]
    d.slots[i] = s
    have[s.class] = ws
    return true
  }
  Object.keys(captured || {}).sort(function(a, b) { return a - b }).forEach(function(ws) {
    captured[ws].slots.forEach(function(s) {
      if (!s) return
      if (left[s.class]) { left[s.class]--; return }
      var known = have[s.class] !== undefined
      if (!put(known ? have[s.class] : ws, s)) (known ? lost : over).push(known ? s.class : s)
    })
  })
  var empty = function(ws) { return !desks[ws] || !desks[ws].slots.some(function(x) { return x }) }
  var free = [1, 2, 3, 4, 5, 6, 7, 8, 9].map(String).filter(empty), at = 0
  over.forEach(function(s) {
    while (at < free.length && !put(free[at], s)) at++
    if (at >= free.length) lost.push(s.class)
  })
  return { desks: desks, lost: lost }
}

// ------------------------------------------------------------ the modal

var NAME_MODES = ["number", "dynamic", "static"]
var ACTIONS = ["focus", "ask", "replace"]

// Rows of a list page: settings, desk (the desk page), schedule (a session's).
// The main page is the 3×3 tiles (mainMove).
function rows(page, c) {
  if (page === "desk") return [{ type: "head" }, { type: "name" }, { type: "scheme" }, { type: "places" }]
  if (page === "schedule") return [{ type: "head" }, { type: "days" }, { type: "from" }, { type: "to" }, { type: "rename" }, { type: "deleteSession" }]
  var out = [{ type: "head" }]
  ;["foreignWindow", "collapse", "collapseInSession"].forEach(function(k) { out.push({ type: "choice", key: k }) })
  ;["sequentialLaunch", "schedule", "hideNoSession"].forEach(function(k) { out.push({ type: "switch", key: k }) })
  c.singleInstance.forEach(function(r, i) { out.push({ type: "rule", index: i }) })
  out.push({ type: "addRule" })
  return out
}

// The main page's cursor: a tile 0–8, "sched" (the schedule row, sessions only) or
// "head0"…"head<heads-1>" (the header's controls, left to right) or "save" (the capture
// page's button under the tiles, `foot`). Arrows over the 3×3 grid; ↑ from the top
// row — the schedule row, then the header; ↓ from the bottom row — "save".
function mainMove(pos, dx, dy, sched, heads, foot) {
  heads = heads || 3
  if (pos === "save") return dy < 0 ? 7 : pos
  if (typeof pos === "number") {
    var r = Math.floor(pos / 3), col = pos % 3
    if (dy < 0 && r === 0) return sched ? "sched" : "head0"
    if (dy > 0 && r === 2 && foot) return "save"
    return Math.max(0, Math.min(2, r + dy)) * 3 + Math.max(0, Math.min(2, col + dx))
  }
  if (pos === "sched") return dy < 0 ? "head0" : dy > 0 ? 0 : pos
  if (dy > 0) return sched ? "sched" : 0
  return dx ? "head" + Math.max(0, Math.min(heads - 1, Number(pos.slice(4)) + dx)) : pos
}

// Places of a scheme as {x, y, w, h} fractions of the desk, in place order
// (grid: as the engine fills it — top left, top right, bottom left, bottom right).
var GEOMETRY = {
  single: [[0, 0, 1, 1]],
  "left-right": [[0, 0, 0.6, 1], [0.6, 0, 0.4, 1]],
  "top-bottom": [[0, 0, 1, 0.5], [0, 0.5, 1, 0.5]],
  "main-left": [[0, 0, 0.6, 1], [0.6, 0, 0.4, 0.5], [0.6, 0.5, 0.4, 0.5]],
  grid: [[0, 0, 0.5, 0.5], [0.5, 0, 0.5, 0.5], [0, 0.5, 0.5, 0.5], [0.5, 0.5, 0.5, 0.5]]
}
function geometry(scheme) {
  return (GEOMETRY[scheme] || GEOMETRY.single).map(function(g) { return { x: g[0], y: g[1], w: g[2], h: g[3] } })
}

// The place next to place i (0-based) in direction dx/dy: the nearest one whose
// centre lies that way; -1 when there is none (↑ from the top leaves the drawing).
function placeMove(scheme, i, dx, dy) {
  var g = geometry(scheme), c = g[i], best = -1, bestD = Infinity
  var cx = c.x + c.w / 2, cy = c.y + c.h / 2
  g.forEach(function(p, j) {
    var px = p.x + p.w / 2 - cx, py = p.y + p.h / 2 - cy
    if (j === i || px * dx <= 0 && dx || py * dy <= 0 && dy) return
    var d = Math.abs(px) + Math.abs(py)
    if (d < bestD) { bestD = d; best = j }
  })
  return best
}

// Tile of the main page: free — nothing to show (no bindings, no name, one window).
function isFree(desk) {
  return !desk || (!hasSlots(desk) && desk.scheme === "single" && (desk.name.mode || "number") === "number")
}

// Schedule days as text: runs of 3+ days as "Mon–Fri", others by commas.
function dayRanges(days, names) {
  var d = (days || []).slice().sort(function(a, b) { return a - b }), out = []
  for (var i = 0; i < d.length; i++) {
    var j = i
    while (j + 1 < d.length && d[j + 1] === d[j] + 1) j++
    if (j - i >= 2) { out.push(names[d[i] - 1] + "–" + names[d[j] - 1]); i = j }
    else out.push(names[d[i] - 1])
  }
  return out.join(", ")
}

// The value next to `value` in `list`, dx steps away, round the list.
function step(list, value, dx) {
  var i = Math.max(0, list.indexOf(value))
  return list[((i + dx) % list.length + list.length) % list.length]
}

function validTime(t) { return /^([01]\d|2[0-3]):[0-5]\d$/.test(String(t)) }

// Why `name` can't get schedule `s` ({days, from, to}): "" when it can.
// Overnight ranges (to <= from) are not supported.
function scheduleError(sessions, name, s) {
  if (!validTime(s.from) || !validTime(s.to)) return "time"
  if (minutes(s.to) <= minutes(s.from)) return "order"
  var all = {}
  Object.keys(sessions).forEach(function(n) { all[n] = { schedule: n === name ? s : sessions[n].schedule } })
  var hit = overlaps(all).filter(function(p) { return p.indexOf(name) >= 0 })[0]
  return hit ? "overlap:" + (hit[0] === name ? hit[1] : hit[0]) : ""
}
