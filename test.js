const assert = require("assert")
const fs = require("fs")
const M = new Function(fs.readFileSync(__dirname + "/Model.js", "utf8").replace(".pragma library", "") +
  "; return { launchPlan, applyPlan, prettyClass, appNameOf, renameSession, fitSlots, setSlot, hasSlots, normalize, activeDesks, trimName, deskLabel, scheduleAt, overlaps, sessionPlan, freeDesks, PLACES, rows, step, scheduleError, mainMove, placeMove, isFree, dayRanges, swapDesks, swapMoves, captureDesks }")()

const c = M.normalize({})
assert.strictEqual(c.foreignWindow, "tile"); assert.strictEqual(c.collapse, "free")
assert.strictEqual(M.normalize({ collapse: "x" }).collapse, "free")

assert.strictEqual(M.trimName("a".repeat(50)), "a".repeat(50))
assert.strictEqual(M.trimName("a".repeat(51)), "a".repeat(50) + "…")

const dyn = { name: { mode: "dynamic" } }
assert.strictEqual(M.deskLabel("2", dyn, [{ class: "foot", fullscreen: 0 }, { class: "firefox", fullscreen: 2 }], c => ({ foot: "Foot", firefox: "Firefox" })[c]), "2 Firefox")
assert.strictEqual(M.deskLabel("2", dyn, [{ class: "foot", fullscreen: 0 }], c => "Foot"), "2 Foot")
assert.strictEqual(M.deskLabel("3", { name: { mode: "static", text: "Почта" } }, [], () => ""), "3 Почта")
assert.strictEqual(M.deskLabel("4", null, [], () => ""), "4")
assert.strictEqual(M.deskLabel("5", dyn, [], () => ""), "5")

const cfg = M.normalize({ sessions: { "Работа": { schedule: { days: [1, 2, 3, 4, 5], from: "09:00", to: "18:00" }, workspaces: {} } } })
assert.strictEqual(M.scheduleAt(cfg, new Date(2026, 9, 6, 9, 0)), "Работа")   // Вт 09:00 — включительно
assert.strictEqual(M.scheduleAt(cfg, new Date(2026, 9, 6, 18, 0)), "")        // 18:00 — уже нет
assert.strictEqual(M.scheduleAt(cfg, new Date(2026, 9, 4, 10, 0)), "")        // Вс
assert.strictEqual(M.scheduleAt(M.normalize({ schedule: false, sessions: cfg.sessions }), new Date(2026, 9, 6, 10, 0)), "")

assert.deepStrictEqual(M.overlaps({
  A: { schedule: { days: [1], from: "09:00", to: "12:00" } },
  B: { schedule: { days: [1, 2], from: "11:00", to: "13:00" } },
  C: { schedule: { days: [1], from: "12:00", to: "14:00" } } }), [["A", "B"], ["B", "C"]])

// Session switch: Дом (desk 1: foot) → Работа (desk 1: code, desk 2: firefox)
const s = M.normalize({ sessions: {
  "Дом": { workspaces: { "1": { scheme: "single", slots: [{ app: "foot.desktop", class: "foot" }] } } },
  "Работа": { workspaces: { "1": { scheme: "single", slots: [{ app: "code.desktop", class: "code" }] },
                             "2": { scheme: "single", slots: [{ app: "firefox.desktop", class: "firefox" }] } } } } })
const plan = M.sessionPlan(s, "Дом", "Работа", [
  { address: "a", class: "foot", ws: 1 },       // Дом's window → closed
  { address: "b", class: "firefox", ws: 4 },    // Работа's app already open → moves to 2
  { address: "c", class: "nautilus", ws: 2 }])  // stranger on a session desk → after the last session desk
assert.deepStrictEqual(plan.close, ["a"])
assert.deepStrictEqual(plan.move, [{ addr: "b", ws: 2 }, { addr: "c", ws: 3 }])
assert.deepStrictEqual(plan.launch, [{ ws: "1", slot: 1, app: "code.desktop", class: "code" }])
// a removed session in activeSession → plain desks
assert.deepStrictEqual(Object.keys(M.activeDesks(M.normalize({ activeSession: "Нет", workspaces: { "1": {} } }))), ["1"])

// Edge cases for desks(): skip non-numeric keys and non-object values
const badDesks = M.normalize({ workspaces: { "foo": { slots: [] }, "1": { slots: [] } } })
assert.ok("1" in badDesks.workspaces && !("foo" in badDesks.workspaces), "non-numeric key ignored")

// Slots keep their places: [null, A] on left-right → A is place 2; trailing holes dropped
const badSlots = M.normalize({ workspaces: { "1": { scheme: "left-right", slots: [null, { app: "a.desktop", class: "a" }] }, "2": { slots: [{ class: "" }] } } })
assert.deepStrictEqual(badSlots.workspaces["1"].slots, [null, { app: "a.desktop", class: "a" }])
assert.deepStrictEqual(badSlots.workspaces["2"].slots, [])
assert.ok(M.hasSlots(badSlots.workspaces["1"]) && !M.hasSlots(badSlots.workspaces["2"]))
assert.deepStrictEqual(M.sessionPlan(M.normalize({ sessions: { S: { workspaces: badSlots.workspaces } } }), "", "S", []).launch,
  [{ ws: "1", slot: 2, app: "a.desktop", class: "a" }], "launch keeps place 2")
assert.deepStrictEqual(M.setSlot([], 2, { class: "x" }, 4), [null, null, { class: "x" }])
assert.deepStrictEqual(M.setSlot([null, null, { class: "x" }], 2, null, 4), [])
assert.deepStrictEqual(M.setSlot([{ class: "a" }, null, { class: "x" }], 0, null, 2), [], "cut to the new scheme")

// Name: keep object as-is, else { mode: "number" }
const nameTests = M.normalize({ workspaces: { "1": { name: { text: "x" } }, "2": { name: "string" }, "3": {} } })
assert.deepStrictEqual(nameTests.workspaces["1"].name, { text: "x" })
assert.deepStrictEqual(nameTests.workspaces["2"].name, { mode: "number" })
assert.deepStrictEqual(nameTests.workspaces["3"].name, { mode: "number" })

// Sessions: skip non-object values
const badSessions = M.normalize({ sessions: { "Good": { workspaces: {} }, "Bad": null } })
assert.ok("Good" in badSessions.sessions && !("Bad" in badSessions.sessions), "non-object session dropped")

// sessionPlan: to="" (no session) and from="" (no session)
const emptyPlan = M.sessionPlan(s, "", "", [{ address: "a", class: "foot", ws: 1 }])
assert.deepStrictEqual(emptyPlan.close, [], "from='' doesn't close anything")

// Stranger past occupied desk: session desks 1–2, stranger on 2, unvacated window on 3 → stranger goes to 4
const strangerPast = M.normalize({ sessions: {
  "A": { workspaces: { "1": { slots: [] }, "2": { slots: [] } } } } })
const plan2 = M.sessionPlan(strangerPast, "", "A", [
  { address: "x", class: "stranger", ws: 2 },   // stranger on session desk 2
  { address: "y", class: "unrelated", ws: 3 }]) // unrelated window on desk 3 (won't be moved)
assert.deepStrictEqual(plan2.move, [{ addr: "x", ws: 4 }], "stranger skips occupied desk 3")

// translations: every tr("...") in QML and Model.js has a Russian line, no unused ones
const I = new Function(fs.readFileSync(__dirname + "/I18n.js", "utf8").replace(".pragma library", "") + "; return { TABLES }")()
const used = new Set()
for (const f of ["Model.js", "Service.qml", "BarWidget.qml", "Panel.qml", "PanelRow.qml", "Tiles.qml", "Scheme.qml", "ConfirmPage.qml"]) {
  if (!fs.existsSync(__dirname + "/" + f)) continue
  for (const m of fs.readFileSync(__dirname + "/" + f, "utf8").matchAll(/tr\("((?:[^"\\]|\\.)*)"/g)) {
    used.add(m[1]); assert.ok(m[1] in I.TABLES.ru, f + ": no ru for " + m[1])
  }
}
for (const k of Object.keys(I.TABLES.ru)) assert.ok(used.has(k), "unused translation: " + k)

// freeDesks: skips session desks and desks with staying windows
const fd = M.normalize({ sessions: { A: { workspaces: { "9": { slots: [{ app: "x", class: "x" }] } } } } })
assert.deepStrictEqual(M.freeDesks(fd.sessions.A.workspaces, [{ class: "q", ws: 11 }], 3, 9), [10, 12, 13])
assert.deepStrictEqual(M.freeDesks(fd.sessions.A.workspaces, [{ class: "x", ws: 10 }], 2, 9), [10, 11])
assert.deepStrictEqual(M.fitSlots([{ class: "a" }, null, { class: "x" }], 2), [{ class: "a" }])
assert.deepStrictEqual(M.fitSlots([null, { class: "b" }], 4), [null, { class: "b" }])
// applying an edit of the desks in force: only the edited place
const ap = M.normalize({ activeSession: "S", sessions: { S: { workspaces: {
  "1": { scheme: "left-right", slots: [null, { app: "foot.desktop", class: "foot" }] }, "2": { slots: [{ app: "fx.desktop", class: "fx" }] } } } } })
const wins = [{ address: "a", class: "fx", ws: 5 }, { address: "b", class: "x", ws: 1 }]
assert.deepStrictEqual(M.applyPlan(ap, "S", wins, 1, 2), { launch: [{ ws: "1", slot: 2, app: "foot.desktop", class: "foot" }], move: [] })
assert.deepStrictEqual(M.applyPlan(ap, "S", wins, 2, 1), { launch: [], move: [{ addr: "a", ws: 2 }] })
assert.deepStrictEqual(M.applyPlan(ap, "S", wins, 1, 1), { launch: [], move: [] }, "cleared place: nothing")
assert.deepStrictEqual(M.applyPlan(M.normalize({ workspaces: { "3": { slots: [{ app: "f", class: "f" }] } } }), "", [], 3, 1).launch, [{ ws: "3", slot: 1, app: "f", class: "f" }])
assert.strictEqual(M.renameSession({ sessions: { A: {} } }, "A", "toString", "").raw.sessions.toString !== undefined, true)
assert.strictEqual(M.renameSession({ sessions: { A: {} } }, "constructor", "B", "").error, "missing")
assert.strictEqual(M.appNameOf("foo", [{ id: "foo.desktop", name: "", startupClass: "" }]), "Foo")
assert.deepStrictEqual(M.launchPlan(ap, "S", wins), { launch: [{ ws: "1", slot: 2, app: "foot.desktop", class: "foot" }], move: [{ addr: "a", ws: 2 }] },
  "launch: all missing apps, bound moves only, no close")
// app names
assert.strictEqual(M.prettyClass("org.omarchy.agent"), "Agent"); assert.strictEqual(M.prettyClass("chrome-www.youtube.com__-Default"), "Youtube")
assert.strictEqual(M.prettyClass("foot"), "Foot")
const ents = [{ id: "org.gnome.Nautilus.desktop", name: "Files", startupClass: "" }, { id: "firefox.desktop", name: "Firefox", startupClass: "firefox" },
  { id: "omarchy-agent.desktop", name: "Agent App", startupClass: "Agent" }]
assert.strictEqual(M.appNameOf("Firefox", ents), "Firefox"); assert.strictEqual(M.appNameOf("org.gnome.nautilus", ents), "Files")
assert.strictEqual(M.appNameOf("org.omarchy.agent", ents), "Agent App"); assert.strictEqual(M.appNameOf("org.x.zzz", ents), "Zzz")
assert.strictEqual(M.appNameOf("chrome-mail.google.com__-Default", ents), "Mail")
// rename a session
const rr = { activeSession: "B", sessions: { A: { schedule: null }, B: { workspaces: { "1": {} }, schedule: { days: [1] } }, C: {} } }
const rn = M.renameSession(rr, "B", " Work ", "Обычные")
assert.deepStrictEqual(Object.keys(rn.raw.sessions), ["A", "Work", "C"]); assert.strictEqual(rn.raw.activeSession, "Work")
assert.deepStrictEqual(rn.raw.sessions.Work, rr.sessions.B); assert.strictEqual(rr.activeSession, "B", "input untouched")
assert.strictEqual(M.renameSession(rr, "A", "Z", "Обычные").raw.activeSession, "B")
assert.strictEqual(M.renameSession(rr, "A", "  ", "Обычные").error, "empty"); assert.strictEqual(M.renameSession(rr, "A", "обычные", "Обычные").error, "regular")
assert.strictEqual(M.renameSession(rr, "A", "C", "Обычные").error, "exists"); assert.strictEqual(M.renameSession(rr, "X", "Y", "").error, "missing")
// modal pages
const rc = M.normalize({ singleInstance: [{ class: "a" }] })
assert.deepStrictEqual(M.rows("settings", rc).map(x => x.type), ["head", "choice", "choice", "choice", "switch", "switch", "switch", "rule", "addRule"])
assert.deepStrictEqual(M.rows("desk", rc).map(x => x.type), ["head", "name", "scheme", "places"])
assert.deepStrictEqual(M.rows("schedule", rc).map(x => x.type), ["head", "days", "from", "to", "rename", "deleteSession"])
// main page cursor
assert.strictEqual(M.mainMove(4, 1, 0, true), 5); assert.strictEqual(M.mainMove(5, 1, 0, true), 5)
assert.strictEqual(M.mainMove(1, 0, 1, false), 4); assert.strictEqual(M.mainMove(7, 0, 1, false), 7)
assert.strictEqual(M.mainMove(1, 0, -1, true), "sched"); assert.strictEqual(M.mainMove(1, 0, -1, false), "head0")
assert.strictEqual(M.mainMove("sched", 0, -1, true), "head0"); assert.strictEqual(M.mainMove("sched", 0, 1, true), 0)
assert.strictEqual(M.mainMove("head0", 1, 0, true), "head1"); assert.strictEqual(M.mainMove("head2", 1, 0, true), "head2")
assert.strictEqual(M.mainMove("head1", 0, 1, false), 0); assert.strictEqual(M.mainMove("head0", 0, 1, true), "sched")
// places by geometry
assert.strictEqual(M.placeMove("main-left", 0, 1, 0), 1); assert.strictEqual(M.placeMove("main-left", 1, 0, 1), 2)
assert.strictEqual(M.placeMove("main-left", 2, -1, 0), 0); assert.strictEqual(M.placeMove("main-left", 1, 0, -1), -1)
assert.strictEqual(M.placeMove("grid", 0, 0, 1), 2); assert.strictEqual(M.placeMove("grid", 3, -1, 0), 2)
assert.strictEqual(M.placeMove("top-bottom", 1, 0, -1), 0); assert.strictEqual(M.placeMove("single", 0, 1, 0), -1)
// tiles
const tc = M.normalize({ workspaces: { "1": {}, "2": { scheme: "grid" }, "3": { name: { mode: "dynamic" } }, "4": { slots: [{ class: "a" }] } } }).workspaces
assert.deepStrictEqual([undefined, tc["1"], tc["2"], tc["3"], tc["4"]].map(M.isFree), [true, true, false, false, false])
const dn = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
assert.strictEqual(M.dayRanges([5, 1, 2, 3, 4], dn), "Mon–Fri"); assert.strictEqual(M.dayRanges([1, 2, 6, 7], dn), "Mon, Tue, Sat, Sun")
assert.strictEqual(M.dayRanges([1, 3, 4, 5, 7], dn), "Mon, Wed–Fri, Sun")
assert.strictEqual(M.step(["a", "b", "c"], "b", 1), "c"); assert.strictEqual(M.step(["a", "b", "c"], "c", 1), "a"); assert.strictEqual(M.step(["a", "b"], "a", -1), "b")
const ss = { A: { schedule: { days: [1], from: "09:00", to: "12:00" } }, B: { schedule: null } }
assert.strictEqual(M.scheduleError(ss, "B", { days: [1], from: "9:00", to: "10:00" }), "time")
assert.strictEqual(M.scheduleError(ss, "B", { days: [1], from: "22:00", to: "02:00" }), "order")
assert.strictEqual(M.scheduleError(ss, "B", { days: [1], from: "11:00", to: "13:00" }), "overlap:A")
assert.strictEqual(M.scheduleError(ss, "B", { days: [2], from: "11:00", to: "13:00" }), "")
assert.strictEqual(M.scheduleError(ss, "A", { days: [1], from: "08:00", to: "10:00" }), "")
// swapping desks
const sw = { workspaces: { "1": { scheme: "grid" }, "2": { name: { mode: "dynamic" } } }, sessions: { S: { workspaces: { "4": { slots: [{ class: "x" }] } } } } }
const sw1 = M.swapDesks(sw, "", 1, 2)
assert.deepStrictEqual(sw1.workspaces, { "1": { name: { mode: "dynamic" } }, "2": { scheme: "grid" } })
assert.deepStrictEqual(sw.workspaces["1"], { scheme: "grid" })   // the input is untouched
assert.deepStrictEqual(M.swapDesks(sw, "", 1, 5).workspaces, { "2": { name: { mode: "dynamic" } }, "5": { scheme: "grid" } })
assert.deepStrictEqual(M.swapDesks(sw, "", 7, 8).workspaces, sw.workspaces)
assert.deepStrictEqual(M.swapDesks(sw, "S", 4, 1).sessions.S.workspaces, { "1": { slots: [{ class: "x" }] } })
assert.deepStrictEqual(M.swapDesks(sw, "S", 4, 1).workspaces, sw.workspaces)
const swc = M.normalize({ workspaces: { "1": { slots: [{ class: "b" }] }, "2": { slots: [{ class: "a" }] } } })
assert.deepStrictEqual(M.swapMoves(swc, "", [{ address: "1", ws: 1, class: "a" }, { address: "2", ws: 2, class: "b" },
  { address: "3", ws: 1, class: "z" }, { address: "4", ws: 3, class: "a" }], 1, 2), [{ addr: "1", ws: 2 }, { addr: "2", ws: 1 }])
// a window on a swapped desk bound to a third desk stays; one desk empty; a session set
const swd = M.normalize({ workspaces: { "5": { slots: [{ class: "a" }] }, "7": { slots: [{ class: "c" }] } },
  sessions: { S: { workspaces: { "2": { slots: [{ class: "s" }] } } } } })
assert.deepStrictEqual(M.swapMoves(swd, "", [{ address: "1", ws: 1, class: "a" }, { address: "2", ws: 1, class: "c" }], 1, 5), [{ addr: "1", ws: 5 }])
assert.deepStrictEqual(M.swapMoves(swd, "S", [{ address: "3", ws: 4, class: "s" }, { address: "4", ws: 4, class: "a" }], 2, 4), [{ addr: "3", ws: 2 }])
// capture: schemes by count, a class once, no desktop entry, off desks 1–9, over 4 places
const ce = [{ id: "firefox.desktop", name: "Firefox", startupClass: "firefox" }, { id: "a.desktop", name: "A", startupClass: "a" },
  { id: "b.desktop", name: "B", startupClass: "b" }, { id: "c.desktop", name: "C", startupClass: "c" }, { id: "d.desktop", name: "D", startupClass: "d" },
  { id: "e.desktop", name: "E", startupClass: "e" }]
const cap = M.captureDesks([{ class: "firefox", ws: 1 }, { class: "firefox", ws: 2 }, { class: "zzz", ws: 2 },
  { class: "a", ws: 3 }, { class: "b", ws: 3 }, { class: "c", ws: 3 }, { class: "d", ws: 3 }, { class: "e", ws: 3 }, { class: "a", ws: -98 }], ce)
assert.deepStrictEqual(cap.desks["1"], { scheme: "single", slots: [{ app: "firefox", class: "firefox" }], name: { mode: "number" } })
assert.strictEqual(cap.desks["2"], undefined)
assert.strictEqual(cap.desks["3"].scheme, "grid"); assert.deepStrictEqual(cap.desks["3"].slots.map(s => s.class), ["a", "b", "c", "d"])
assert.deepStrictEqual(cap.lost.sort(), ["a", "e", "firefox", "zzz"])
assert.strictEqual(M.captureDesks([{ class: "a", ws: 4 }, { class: "b", ws: 4 }], ce).desks["4"].scheme, "left-right")
assert.strictEqual(M.captureDesks([{ class: "a", ws: 4 }, { class: "b", ws: 4 }, { class: "c", ws: 4 }], ce).desks["4"].scheme, "main-left")
// the capture page: 2 header controls, "save" under the tiles; the main page: 4
assert.strictEqual(M.mainMove(7, 0, 1, false, 2, true), "save"); assert.strictEqual(M.mainMove("save", 0, -1, false, 2, true), 7)
assert.strictEqual(M.mainMove("head0", 1, 0, false, 2, true), "head1"); assert.strictEqual(M.mainMove("head1", 1, 0, false, 2, true), "head1")
assert.strictEqual(M.mainMove("head2", 1, 0, true, 4), "head3")
// no guess by the last segment: org.omarchy.agent is not an "…agent" app
assert.deepStrictEqual(M.captureDesks([{ class: "org.omarchy.agent", ws: 1 }], [{ id: "ideco.desktop", name: "Ideco", startupClass: "com.ideco.agent" }]),
  { desks: {}, lost: ["org.omarchy.agent"] })
console.log("ok")
