const assert = require("assert")
const fs = require("fs")
const M = new Function(fs.readFileSync(__dirname + "/Model.js", "utf8").replace(".pragma library", "") +
  "; return { normalize, activeDesks, trimName, deskLabel, scheduleAt, overlaps, sessionPlan, PLACES }")()

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

// translations: every tr("...") in QML and Model.js has a Russian line, no unused ones
const I = new Function(fs.readFileSync(__dirname + "/I18n.js", "utf8").replace(".pragma library", "") + "; return { TABLES }")()
const used = new Set()
for (const f of ["Model.js", "Service.qml", "BarWidget.qml", "Panel.qml"]) {
  if (!fs.existsSync(__dirname + "/" + f)) continue
  for (const m of fs.readFileSync(__dirname + "/" + f, "utf8").matchAll(/tr\("((?:[^"\\]|\\.)*)"/g)) {
    used.add(m[1]); assert.ok(m[1] in I.TABLES.ru, f + ": no ru for " + m[1])
  }
}
for (const k of Object.keys(I.TABLES.ru)) assert.ok(used.has(k), "unused translation: " + k)
console.log("ok")
