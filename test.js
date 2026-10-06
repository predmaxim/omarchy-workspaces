const assert = require("assert")
const fs = require("fs")
const M = new Function(fs.readFileSync(__dirname + "/Model.js", "utf8").replace(".pragma library", "") +
  "; return { launchPlan, applyPlan, prettyClass, appNameOf, renameSession, fitSlots, setSlot, hasSlots, normalize, activeDesks, trimName, deskLabel, scheduleAt, loginSession, overlaps, sessionPlan, freeDesks, PLACES, rows, step, scheduleError, mainMove, placeMove, isFree, dayRanges, swapDesks, swapMoves, captureDesks, mergeDesks, schemeOf, singleGroup, appClass, entryOf }")()

// Desks as the active session "S" — the empty session ("") has none.
const inS = (ws, extra) => M.normalize(Object.assign({ activeSession: "S", sessions: { S: { workspaces: ws } } }, extra))
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
// At login: the scheduled session; out of its time a scheduled one ends, an unscheduled one stays.
const work = (extra) => M.normalize(Object.assign({ sessions: { "Работа": cfg.sessions["Работа"], "Дом": {} } }, extra))
assert.strictEqual(M.loginSession(work({ activeSession: "" }), new Date(2026, 9, 6, 10, 0)), "Работа")
assert.strictEqual(M.loginSession(work({ activeSession: "Работа" }), new Date(2026, 9, 6, 21, 0)), "")
assert.strictEqual(M.loginSession(work({ activeSession: "Дом" }), new Date(2026, 9, 6, 21, 0)), "Дом")
assert.strictEqual(M.loginSession(work({ activeSession: "Работа", schedule: false }), new Date(2026, 9, 6, 21, 0)), "Работа")

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
// → the empty session: windows stay as they are — nothing closes, moves or launches
assert.deepStrictEqual(M.sessionPlan(s, "Работа", "", [{ address: "a", class: "code", ws: 1 }, { address: "b", class: "firefox", ws: 4 }]),
  { close: [], move: [], launch: [] })
// the empty session is always empty: config's plain desks aren't read
assert.deepStrictEqual(M.normalize({ workspaces: { "1": { slots: [{ app: "a.desktop", class: "a" }] } } }).workspaces, {})
// a removed session in activeSession → the empty session
assert.deepStrictEqual(M.activeDesks(M.normalize({ activeSession: "Нет", workspaces: { "1": {} } })), {})

// Edge cases for desks(): skip non-numeric keys and non-object values
const badDesks = M.normalize({ sessions: { S: { workspaces: { "foo": { slots: [] }, "1": { slots: [] } } } } }).sessions.S
assert.ok("1" in badDesks.workspaces && !("foo" in badDesks.workspaces), "non-numeric key ignored")

// Slots keep their places: [null, A] on left-right → A is place 2; trailing holes dropped
const badSlots = M.normalize({ sessions: { S: { workspaces: { "1": { scheme: "left-right", slots: [null, { app: "a.desktop", class: "a" }] }, "2": { slots: [{ class: "" }] } } } } }).sessions.S
assert.deepStrictEqual(badSlots.workspaces["1"].slots, [null, { app: "a.desktop", class: "a" }])
assert.deepStrictEqual(badSlots.workspaces["2"].slots, [])
assert.ok(M.hasSlots(badSlots.workspaces["1"]) && !M.hasSlots(badSlots.workspaces["2"]))
assert.deepStrictEqual(M.sessionPlan(M.normalize({ sessions: { S: { workspaces: badSlots.workspaces } } }), "", "S", []).launch,
  [{ ws: "1", slot: 2, app: "a.desktop", class: "a" }], "launch keeps place 2")
assert.deepStrictEqual(M.setSlot([], 2, { class: "x" }, 4), [null, null, { class: "x" }])
assert.deepStrictEqual(M.setSlot([null, null, { class: "x" }], 2, null, 4), [])
assert.deepStrictEqual(M.setSlot([{ class: "a" }, null, { class: "x" }], 0, null, 2), [], "cut to the new scheme")

// Name: keep object as-is, else { mode: "number" }
const nameTests = M.normalize({ sessions: { S: { workspaces: { "1": { name: { text: "x" } }, "2": { name: "string" }, "3": {} } } } }).sessions.S
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
assert.deepStrictEqual(M.applyPlan(M.normalize({ sessions: { S: { workspaces: { "3": { slots: [{ app: "f", class: "f" }] } } } } }), "S", [], 3, 1).launch, [{ ws: "3", slot: 1, app: "f", class: "f" }])
assert.deepStrictEqual(M.applyPlan(M.normalize({ workspaces: { "3": { slots: [{ app: "f", class: "f" }] } } }), "", [], 3, 1), { launch: [], move: [] }, "the empty session: nothing")
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
assert.strictEqual(M.renameSession(rr, "A", "  ", "Обычные").error, "empty"); assert.strictEqual(M.renameSession(rr, "A", "пустая сессия", "Пустая сессия").error, "regular")
assert.strictEqual(M.renameSession(rr, "A", "Empty session", "").error, "regular")
assert.strictEqual(M.renameSession(rr, "A", "C", "Обычные").error, "exists"); assert.strictEqual(M.renameSession(rr, "X", "Y", "").error, "missing")
// modal pages
const rc = M.normalize({ singleInstance: [{ class: "a" }] })
assert.deepStrictEqual(M.rows("settings", rc).map(x => x.type), ["head", "choice", "choice", "choice", "switch", "switch", "switch", "rule", "addRule"])
assert.deepStrictEqual(M.rows("desk", rc).map(x => x.type), ["head", "name", "scheme", "places"])
assert.deepStrictEqual(M.rows("schedule", rc).map(x => x.type), ["head", "days", "from", "to"])
// main page cursor
assert.strictEqual(M.mainMove(4, 1, 0, true), 5); assert.strictEqual(M.mainMove(5, 1, 0, true), 5)
assert.strictEqual(M.mainMove(1, 0, 1, false), 4); assert.strictEqual(M.mainMove(7, 0, 1, false), 9)
assert.strictEqual(M.mainMove(1, 0, -1, true), "sched"); assert.strictEqual(M.mainMove(1, 0, -1, false), "head0")
assert.strictEqual(M.mainMove("sched", 0, -1, true), "head0"); assert.strictEqual(M.mainMove("sched", 0, 1, true), 0)
assert.strictEqual(M.mainMove("head0", 1, 0, true), "head1"); assert.strictEqual(M.mainMove("head2", 1, 0, true), "head2")
assert.strictEqual(M.mainMove("head1", 0, 1, false), 0); assert.strictEqual(M.mainMove("head0", 0, 1, true), "sched")
// places by geometry
assert.strictEqual(M.placeMove("main-left", 0, 1, 0), 1); assert.strictEqual(M.placeMove("main-left", 1, 0, 1), 2)
assert.strictEqual(M.placeMove("main-left", 2, -1, 0), 0); assert.strictEqual(M.placeMove("main-left", 1, 0, -1), -1)
assert.strictEqual(M.placeMove("grid", 0, 0, 1), 2); assert.strictEqual(M.placeMove("grid", 3, -1, 0), 2)
assert.strictEqual(M.placeMove("main-right", 1, 1, 0), 2); assert.strictEqual(M.placeMove("main-right", 2, 0, 1), 3); assert.strictEqual(M.placeMove("main-right", 3, 1, 0), 0)
assert.strictEqual(M.placeMove("top-bottom", 1, 0, -1), 0); assert.strictEqual(M.placeMove("single", 0, 1, 0), -1)
// tiles
const tc = M.normalize({ sessions: { S: { workspaces: { "1": {}, "2": { scheme: "grid" }, "3": { name: { mode: "dynamic" } }, "4": { slots: [{ class: "a" }] } } } } }).sessions.S.workspaces
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
const swc = inS({ "1": { slots: [{ class: "b" }] }, "2": { slots: [{ class: "a" }] } })
assert.deepStrictEqual(M.swapMoves(swc, "S", [{ address: "1", ws: 1, class: "a" }, { address: "2", ws: 2, class: "b" },
  { address: "3", ws: 1, class: "z" }, { address: "4", ws: 3, class: "a" }], 1, 2), [{ addr: "1", ws: 2 }, { addr: "2", ws: 1 }])
// a window on a swapped desk bound to a third desk stays; one desk empty; a session set
const swd = M.normalize({ sessions: { P: { workspaces: { "5": { slots: [{ class: "a" }] }, "7": { slots: [{ class: "c" }] } } },
  S: { workspaces: { "2": { slots: [{ class: "s" }] } } } } })
assert.deepStrictEqual(M.swapMoves(swd, "P", [{ address: "1", ws: 1, class: "a" }, { address: "2", ws: 1, class: "c" }], 1, 5), [{ addr: "1", ws: 5 }])
assert.deepStrictEqual(M.swapMoves(swd, "S", [{ address: "3", ws: 4, class: "s" }, { address: "4", ws: 4, class: "a" }], 2, 4), [{ addr: "3", ws: 2 }])
// capture: schemes by count, a class once, no desktop entry, off desks 1–9, over 4 places
const ce = [{ id: "firefox.desktop", name: "Firefox", startupClass: "firefox" }, { id: "a.desktop", name: "A", startupClass: "a" },
  { id: "b.desktop", name: "B", startupClass: "b" }, { id: "c.desktop", name: "C", startupClass: "c" }, { id: "d.desktop", name: "D", startupClass: "d" },
  { id: "e.desktop", name: "E", startupClass: "e" }]
const cap = M.captureDesks([{ class: "firefox", ws: 1 }, { class: "firefox", ws: 2 }, { class: "zzz", ws: 2 },
  { class: "a", ws: 3 }, { class: "b", ws: 3 }, { class: "c", ws: 3 }, { class: "d", ws: 3 }, { class: "e", ws: 3 }, { class: "a", ws: -98 }], ce)
// two windows of an app on two desks: each stays on its own
assert.deepStrictEqual(cap.desks["1"], { scheme: "single", slots: [{ app: "firefox", class: "firefox" }], name: { mode: "number" } })
assert.deepStrictEqual(cap.desks["2"].slots.map(s => s.class), ["firefox"])
assert.strictEqual(cap.desks["3"].scheme, "grid"); assert.deepStrictEqual(cap.desks["3"].slots.map(s => s.class), ["a", "b", "c", "d", "e"])
assert.deepStrictEqual(cap.lost.sort(), ["a", "zzz"])
// a new set: the 5th window of desk 3 goes to the nearest empty desk (4)
const capm = M.mergeDesks({}, cap.desks)
assert.deepStrictEqual(capm.desks["3"].slots.map(s => s.class), ["a", "b", "c", "d"]); assert.deepStrictEqual(capm.desks["4"].slots.map(s => s.class), ["e"])
assert.strictEqual(M.captureDesks([{ class: "a", ws: 4 }, { class: "b", ws: 4 }], ce).desks["4"].scheme, "left-right")
assert.strictEqual(M.captureDesks([{ class: "a", ws: 4 }, { class: "b", ws: 4 }, { class: "c", ws: 4 }], ce).desks["4"].scheme, "main-left")
// the capture page: 2 header controls, "save" under the tiles; the main page: 4
assert.strictEqual(M.mainMove(7, 0, 1, false, 2, true), 9); assert.strictEqual(M.mainMove(9, 0, 1, false, 2, true), "save")
assert.strictEqual(M.mainMove("save", 0, -1, false, 2, true), 9); assert.strictEqual(M.mainMove(9, 0, -1, false, 2, true), 6)
assert.strictEqual(M.mainMove(9, 0, 1, false, 4), 9); assert.strictEqual(M.mainMove(9, 1, 0, false, 4), 9)
assert.strictEqual(M.mainMove("head0", 1, 0, false, 2, true), "head1"); assert.strictEqual(M.mainMove("head1", 1, 0, false, 2, true), "head1")
assert.strictEqual(M.mainMove("head2", 1, 0, true, 4), "head3")
// no guess by the last segment: org.omarchy.agent is not an "…agent" app
assert.deepStrictEqual(M.captureDesks([{ class: "chrome-telemost.360.yandex.ru__j_1-Default", ws: 3 }], [{ id: "Telemost.desktop", name: "Telemost", execString: "omarchy-launch-webapp \"https://telemost.360.yandex.ru/\"" }]).desks["3"].slots[0].app, "Telemost")
assert.deepStrictEqual(M.captureDesks([{ class: "org.omarchy.agent", ws: 1 }], [{ id: "ideco.desktop", name: "Ideco", startupClass: "com.ideco.agent" }]),
  { desks: {}, lost: ["org.omarchy.agent"] })
// merge: the set's apps stay, new ones take free places, the scheme grows, overflow is lost
const md = inS({ "1": { slots: [{ app: "y", class: "y" }] }, "2": { scheme: "grid", slots: [{ class: "a" }, { class: "b" }, { class: "c" }, { class: "d" }] } }).sessions.S.workspaces
const mg = M.mergeDesks(md, { "1": { slots: [{ class: "n" }, { class: "a" }] }, "2": { slots: [{ class: "m" }] }, "3": { slots: [{ class: "k" }] } })
assert.strictEqual(mg.desks["1"].scheme, "left-right"); assert.deepStrictEqual(mg.desks["1"].slots.map(x => x.class), ["y", "n"])
assert.deepStrictEqual(mg.desks["3"].slots.map(x => x.class), ["k"]); assert.deepStrictEqual(mg.desks["4"].slots.map(x => x.class), ["m"])
assert.deepStrictEqual(mg.lost, [])
// 4 + 4: the new four share one empty desk; no empty desk left — lost
const full = {}; for (let i = 1; i <= 9; i++) full[i] = { slots: [{ class: "s" + i }] }
const fm = M.mergeDesks(inS({ "2": { scheme: "grid", slots: ["a", "b", "c", "d"].map(c => ({ class: c })) } }).sessions.S.workspaces,
  { "2": { slots: ["e", "f", "g", "h"].map(c => ({ class: c })) } })
assert.deepStrictEqual(fm.desks["1"].slots.map(x => x.class), ["e", "f", "g", "h"]); assert.strictEqual(fm.desks["1"].scheme, "grid")
assert.deepStrictEqual(M.mergeDesks(inS(Object.assign({}, full, { "2": { scheme: "grid", slots: ["a", "b", "c", "d"].map(c => ({ class: c })) } })).sessions.S.workspaces,
  { "2": { slots: [{ class: "e" }] } }).lost, ["e"])
assert.strictEqual(md["1"].slots.length, 1)   // the input is untouched
// by count: the set has one "y" (desk 1), two are open on desk 3 — one takes the set's
// place (it'll move), the other stays on desk 3
const mc = M.mergeDesks(md, { "3": { slots: [{ class: "y" }, { class: "y" }] } })
assert.deepStrictEqual(mc.desks["1"].slots.map(x => x.class), ["y"]); assert.deepStrictEqual(mc.desks["3"].slots.map(x => x.class), ["y"])
// the user's case: Work has webstorm on 2; agent + foot added there, agent + foot + telemost on 3
const wk = inS({ "2": { slots: [{ app: "ws", class: "ws" }] } }).sessions.S.workspaces
const wm = M.mergeDesks(wk, { "2": { scheme: "main-left", slots: ["ws", "ag", "ft"].map(c => ({ app: c, class: c })) },
  "3": { scheme: "main-right", slots: ["tm", "ag", "ft", "ft"].map(c => ({ app: c, class: c })) } })
assert.deepStrictEqual(wm.desks["2"].slots.map(x => x.class), ["ws", "ag", "ft"]); assert.strictEqual(wm.desks["2"].scheme, "main-left")
assert.deepStrictEqual(wm.desks["3"].slots.map(x => x.class), ["tm", "ag", "ft", "ft"]); assert.strictEqual(wm.desks["3"].scheme, "main-right")
// launch: two places of a class, one window open — one launch
const dup = inS({ "1": { scheme: "left-right", slots: [{ app: "f", class: "f" }, { app: "f", class: "f" }] } })
assert.strictEqual(M.sessionPlan(dup, "", "S", [{ address: "1", ws: 1, class: "f" }]).launch.length, 1)
assert.strictEqual(M.sessionPlan(dup, "", "S", []).launch.length, 2)
// an app on two desks: each window keeps its desk, a missing one launches on its desk
const two = inS({ "2": { scheme: "left-right", slots: [{ app: "w", class: "w" }, { app: "f", class: "f" }] }, "3": { slots: [{ app: "f", class: "f" }] } })
const tp = M.sessionPlan(two, "", "S", [{ address: "a", ws: 3, class: "f" }, { address: "w", ws: 2, class: "w" }])
assert.deepStrictEqual(tp.move, []); assert.deepStrictEqual(tp.launch.map(l => l.ws + ":" + l.class), ["2:f"])
// both on desk 5: one goes to 2, the other to 3
assert.deepStrictEqual(M.sessionPlan(two, "", "S", [{ address: "a", ws: 5, class: "f" }, { address: "b", ws: 5, class: "f" }]).move, [{ addr: "a", ws: 2 }, { addr: "b", ws: 3 }])
// a third one joins the app's first desk
assert.strictEqual(M.sessionPlan(two, "", "S", [{ address: "a", ws: 2, class: "f" }, { address: "b", ws: 3, class: "f" }, { address: "c", ws: 7, class: "f" }]).move[0].ws, 2)
// applyPlan: the edited place on desk 3 — the window on 3 is its own, nothing to do
assert.deepStrictEqual(M.applyPlan(two, "S", [{ address: "a", ws: 3, class: "f" }], 2, 2), { launch: [{ ws: "2", slot: 2, app: "f", class: "f" }], move: [] })
// swap 2 ↔ 3 in the new config: the f window on 3 — desk 3 now has f too (from 2), it stays; w goes to 3
const sw2 = inS({ "3": { scheme: "left-right", slots: [{ app: "w", class: "w" }, { app: "f", class: "f" }] }, "2": { slots: [{ app: "f", class: "f" }] } })
assert.deepStrictEqual(M.swapMoves(sw2, "S", [{ address: "a", ws: 3, class: "f" }, { address: "w", ws: 2, class: "w" }], 2, 3), [{ addr: "w", ws: 3 }])
// single-instance apps: one launch per rule, none when one is open
const si = inS({ "2": { slots: [{ app: "t", class: "chrome-telemost.360.yandex.ru__-Default" }] }, "3": { slots: [{ app: "t", class: "chrome-telemost.360.yandex.ru__-Default" }] } }, { singleInstance: [{ match: "^chrome%-telemost%.[%w.]*yandex%.ru__%-Default$", action: "focus" }] })
assert.strictEqual(M.sessionPlan(si, "", "S", []).launch.length, 1)
assert.strictEqual(M.sessionPlan(si, "", "S", [{ address: "x", ws: 9, class: "chrome-telemost.360.yandex.ru__-Default" }]).launch.length, 0)
assert.strictEqual(M.singleGroup([{ match: "^chrome%-telemost%.[%w.]*yandex%.ru__j_" }], "chrome-telemost.360.yandex.ru__j_65-Default"), 0)
assert.strictEqual(M.singleGroup([{ match: "^chrome%-telemost%.[%w.]*yandex%.ru__j_" }], "chrome-telemost.360.yandex.ru__-Default"), -1)
assert.strictEqual(M.singleGroup([{ class: "foot" }], "foot"), 0)
console.log("ok")

// ws 3 as tiled live: agent ¼ | foot / foot ¼ | telemost ½ → main-right, telemost in place 1
const live = [{ ws: 3, at: [12, 57], size: [846, 1371] }, { ws: 3, at: [872, 57], size: [841, 679] },
  { ws: 3, at: [872, 750], size: [841, 678] }, { ws: 3, at: [1727, 57], size: [1701, 1371] }]
assert.deepStrictEqual(M.schemeOf(live, 3), { scheme: "main-right", order: [3, 0, 1, 2] })
assert.strictEqual(M.schemeOf([{ ws: 1, at: [0, 0], size: [10, 10] }, { ws: 1, at: [0, 10], size: [10, 10] }], 1).scheme, "top-bottom")
assert.strictEqual(M.schemeOf(live.map(w => Object.assign({}, w, { floating: true })), 3), null)
console.log("ok schemeOf")
const mr = M.mergeDesks({}, { "3": { scheme: "main-right", slots: ["t", "a", "f", "f"].map(c => ({ app: c, class: c })) } })
assert.strictEqual(mr.desks["3"].scheme, "main-right"); assert.deepStrictEqual(mr.desks["3"].slots.map(x => x.class), ["t", "a", "f", "f"])
console.log("ok merge scheme")
// the scratchpad desk: kept by normalize, last in order, moves go to special:scratchpad
const sc = inS({ scratchpad: { slots: [{ app: "k", class: "k" }] }, "2": { slots: [{ app: "w", class: "w" }] } })
assert.deepStrictEqual(Object.keys(sc.sessions.S.workspaces).sort(), ["2", "scratchpad"])
const sp = M.sessionPlan(sc, "", "S", [{ address: "a", ws: 3, class: "k" }, { address: "z", ws: "scratchpad", class: "zz" }])
assert.deepStrictEqual(sp.move, [{ addr: "a", ws: "special:scratchpad" }]); assert.deepStrictEqual(sp.launch.map(l => l.ws), ["2"])
assert.deepStrictEqual(M.sessionPlan(sc, "", "S", []).launch.map(l => l.ws), ["2", "scratchpad"])
assert.deepStrictEqual(M.captureDesks([{ class: "k", ws: "scratchpad" }], [{ id: "k.desktop", name: "K", startupClass: "k" }]).desks.scratchpad.slots[0].class, "k")
console.log("ok scratchpad")
// the class an app's windows get: StartupWMClass, a web app's Chromium class from its URL, else the id
assert.strictEqual(M.appClass({ id: "Telemost", startupClass: "", execString: 'omarchy-launch-webapp "https://telemost.360.yandex.ru/"' }), "chrome-telemost.360.yandex.ru__-Default")
assert.strictEqual(M.appClass({ id: "TS", execString: "omarchy-launch-webapp https://login.tailscale.com/admin/machines" }), "chrome-login.tailscale.com__admin_machines-Default")
assert.strictEqual(M.appClass({ id: "X", execString: 'omarchy-launch-webapp "https://x.com"' }), "chrome-x.com__-Default")
assert.strictEqual(M.appClass({ id: "org.gnome.Nautilus.desktop", startupClass: "", execString: "nautilus" }), "org.gnome.Nautilus")
assert.strictEqual(M.appClass({ id: "code.desktop", startupClass: "Code", execString: "code" }), "Code")
// a picked web app is found back by its window: entryOf agrees with appClass
const tm = { id: "Telemost", name: "Telemost", startupClass: "", execString: 'omarchy-launch-webapp "https://telemost.360.yandex.ru/"' }
assert.strictEqual(M.entryOf(M.appClass(tm), [tm], true), tm)
console.log("ok appClass")
