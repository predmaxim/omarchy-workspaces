import QtQuick
import "." as Local
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "I18n.js" as I18n

// The «Workspaces» modal (BarWidget.qml holds it; its Panel gives opened/open/close
// and the IPC `omarchy-shell predmaxim.workspaces-panel toggle`). Pages: main (desks
// 1–9 as tiles of the set — plain desks or a session — picked in the header, and the
// session's schedule row; Tiles.qml), desk (name, scheme, apps by place), schedule,
// settings behind the gear, and the session switch confirmation, which opens by
// itself while the service waits for an answer. List pages' rows come from
// Model.rows (PanelRow.qml); ↑/↓ rows, ←/→ value, Enter open/press, Esc back.
Item {
  id: root
  // Fixed status colours (FixedColors.qml): a theme's red can be any colour.
  readonly property QtObject fixedColors: FixedColors {}
  property var host: null
  property var service: null
  property var screen: null

  readonly property var tr: I18n.translator(I18n.textLanguage(Quickshell.env))
  readonly property var cfg: service ? service.cfg : Model.normalize({})
  readonly property bool opened: host ? host.opened : false
  readonly property color fg: Color.popups.text
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property string font: Style.font.family

  property string page: "main"     // main | desk | schedule | settings
  property string set: ""          // "" — the empty session, else a session
  // The empty session has nothing to edit: no tiles, the cursor stays in the header.
  readonly property bool locked: set === "" && !capture
  property var deskWs: 1           // the desk page's desk: 1–9 or "scratchpad"
  function wsOf(pos) { return pos === 9 ? "scratchpad" : pos + 1 }   // a tile's desk
  property var pos: 0              // main page cursor (Model.mainMove)
  property int cursor: 1           // list pages: the row
  property int place: 0            // desk page: the place under the cursor
  property bool adding: false      // the new session's name field in the header
  property bool renaming: false    // the same field renames the session
  // Header controls: set ▾, ▶, snapshot, then for a session ✎ and delete, the gear last.
  readonly property string gearHead: set !== "" ? "head5" : "head3"
  property bool confirming: false
  property string switchTo: ""
  property var draft: ({ days: [], from: "", to: "" })
  property string scheduleError: ""
  property string setHint: ""      // why the session can't be deleted
  property string renameHint: ""   // why the new name doesn't fit
  property int dayCursor: 0        // the day under the cursor in the days row
  property var setPicker: null     // the header's set Dropdown
  property var capture: null       // the draft: {desks, lost, taken} — taken: Model.captureDesks of the open windows
  property string target: ""       // where the draft goes: a set or newSet
  property string captureHint: ""  // why the draft can't go under that name

  // The scratchpad has no name: the bar doesn't show it.
  readonly property var rows: confirming || page === "main" ? [] : Model.rows(page, cfg)
    .filter(function(r) { return !(page === "desk" && deskWs === "scratchpad" && r.type === "name") })
  readonly property var desks: capture ? capture.desks : set && cfg.sessions[set] ? cfg.sessions[set].workspaces : cfg.workspaces
  readonly property var desk: desks[String(deskWs)] || null
  readonly property var sets: [""].concat(Object.keys(cfg.sessions))
  readonly property var apps: DesktopEntries.applications.values
    .map(function(e) { return { label: e.name, value: e.id, cls: Model.appClass(e) } })
    .sort(function(a, b) { return a.label.localeCompare(b.label) })
  readonly property bool typing: keyCatcher.Window.activeFocusItem !== null && keyCatcher.Window.activeFocusItem !== keyCatcher
  readonly property var choiceLabels: ({ tile: tr("Stays"), float: tr("Floating"), next: tr("Next desk"),
                                         free: tr("Only free"), all: tr("All"), off: tr("Don't collapse"),
                                         number: tr("Number"), dynamic: tr("By window"), static: tr("Custom"),
                                         focus: tr("Focus"), ask: tr("Ask"), replace: tr("Replace") })
  readonly property var rowLabels: ({ places: tr("Apps by place"), days: tr("Days"), from: tr("From"), to: tr("To"), name: tr("Name"), scheme: tr("Scheme"),
                                      addRule: tr("One app window"), foreignWindow: tr("Foreign window on a laid-out desk"),
                                      collapse: tr("Collapsing without a session"), collapseInSession: tr("Collapsing in a session"),
                                      sequentialLaunch: tr("Launch one by one"), schedule_: tr("Scheduled session at login"),
                                      hideNoSession: tr("Hide the name without a session") })
  readonly property var schemeNames: ({ single: tr("One window"), "left-right": tr("Left and right"), "top-bottom": tr("Top and bottom"),
                                        "main-left": tr("Main on the left"), grid: tr("Grid"), "main-right": tr("Main on the right") })
  readonly property var days: [tr("Mon"), tr("Tue"), tr("Wed"), tr("Thu"), tr("Fri"), tr("Sat"), tr("Sun")]

  signal pressRow(int i)
  readonly property alias gate: pointerGate
  function focusKeys() { keyCatcher.forceActiveFocus() }
  // The active session isn't deleted: end it first.
  function askDelete() {
    if (root.set === root.cfg.activeSession) root.setHint = root.tr("End the session first")
    else confirmDelete.opened = true
  }

  onOpenedChanged: {
    if (opened) {
      if (!confirming) {
        page = "main"; pos = 0; cursor = 1; adding = false; capture = null
        set = cfg.sessions[cfg.activeSession] ? cfg.activeSession : ""
        loadDraft()
      }
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else if (confirming && service && service.phase === "") service.cancelSwitch()
  }
  onSetChanged: { loadDraft(); setHint = ""; renameHint = ""; renaming = false; if (pos === "head3" || pos === "head4" || pos === "head5") pos = gearHead }
  onPageChanged: flick.contentY = 0
  onSetsChanged: if (sets.indexOf(set) < 0) set = ""
  onRowsChanged: if (cursor >= rows.length) cursor = Math.max(0, rows.length - 1)
  onCursorChanged: {
    var it = rep.itemAt(cursor)
    if (!it) return
    if (it.y < flick.contentY) flick.contentY = it.y
    else if (it.y + it.height > flick.contentY + flick.height) flick.contentY = it.y + it.height - flick.height
  }

  Connections {
    target: root.service
    function onPendingPlanChanged() { root.sync() }
    function onPhaseChanged() { root.sync() }
  }
  // The service asks (windows to close) → the confirmation page; closing → hide it, so the
  // apps' "save?" dialogs get the keyboard (the modal holds it exclusively); it's done → close.
  function sync() {
    var s = root.service
    if (s.phase === "closing") root.host.close()
    else if (s.pendingPlan && s.pendingPlan.close.length && !root.confirming) {
      root.switchTo = s.pendingPlan.to; root.confirming = true; root.host.open()
    } else if (root.confirming && !s.pendingPlan && s.phase === "") {
      root.confirming = false; root.host.close()
    }
  }

  // ------------------------------------------------------------ editing: copy raw, change, save

  function edit(fn, then) {
    if (!root.service || root.service.loadError !== "") return   // broken config.json: no edits
    var next = JSON.parse(JSON.stringify(root.service.raw))
    fn(next)
    root.service.save(next, then)
  }
  // apply: the 1-based place that changed — on the desks in force, launch/move at once.
  function editDesk(fn, apply) {
    if (root.locked) return
    var deskWs = root.deskWs
    var ws = String(root.deskWs)
    // The draft of open windows lives in memory until it's saved.
    if (root.capture) {
      var c = JSON.parse(JSON.stringify(root.capture))
      fn(c.desks[ws] = c.desks[ws] || { scheme: "single", slots: [], name: { mode: "number" } })
      root.capture = c
      return
    }
    root.edit(function(next) {
      var ds = next.sessions[root.set].workspaces = next.sessions[root.set].workspaces || {}
      fn(ds[ws] = ds[ws] || { scheme: "single", slots: [], name: { mode: "number" } })
    }, function(ok) {
      // The desks in force changed: apply now (launch, move), after the reload.
      var active = root.cfg.sessions[root.cfg.activeSession] ? root.cfg.activeSession : ""
      if (ok && apply && root.set === active) root.service.applyActive(deskWs, apply)
    })
  }
  // Desks a and b (1–9) of the edited set trade places; in the set in force their
  // bound windows follow after the reload.
  function swapDesks(a, b) {
    if (a === b || root.locked || !root.service || root.service.loadError !== "") return
    if (root.capture) {
      root.capture = Object.assign({}, root.capture, { desks: Model.swapDesks({ workspaces: root.capture.desks }, "", a, b).workspaces })
      return
    }
    var set = root.set
    root.service.save(Model.swapDesks(root.service.raw, set, a, b), function(ok) {
      if (ok && set === root.activeSet) root.service.moveSwapped(a, b)
    })
  }
  function setOption(key, value) { root.edit(function(next) { next[key] = value }) }
  function setScheme(v) { root.editDesk(function(d) { d.scheme = v; d.slots = Model.fitSlots(d.slots, Model.PLACES[v]) }) }
  function setNameMode(v) {
    root.editDesk(function(d) { d.name = v === "static" ? { mode: v, text: d.name && d.name.text || "" } : { mode: v } })
  }
  function setNameText(t) { root.editDesk(function(d) { d.name = { mode: "static", text: t } }) }
  // Places keep their numbers: an empty one stays null.
  function setPlace(i, id) {
    var app = root.apps.filter(function(a) { return a.value === id })[0]
    root.editDesk(function(d) {
      d.slots = Model.setSlot(d.slots, i, app ? { app: app.value, class: app.cls } : null, Model.PLACES[d.scheme] || 1)
    }, i + 1)
  }
  function addSession(name) {
    name = name.trim()
    root.adding = false
    keyCatcher.forceActiveFocus()
    if (!name || root.cfg.sessions[name]) return
    root.edit(function(next) { next.sessions = next.sessions || {}; next.sessions[name] = { workspaces: {} } })
    root.set = name
  }
  // Same order, schedule and desks; the active session keeps running under the new name.
  function renameSet(to) {
    var r = Model.renameSession(root.service.raw, root.set, to, root.tr("Empty session"))
    root.renameHint = r.error === "empty" ? root.tr("Type a name") : r.error === "regular" ? root.tr("This name is taken by the empty session")
      : r.error === "exists" ? root.tr("A session with this name exists") : ""
    if (r.error) return false
    if (to.trim() !== root.set && root.service.loadError === "") { root.service.save(r.raw); root.set = to.trim() }
    return true
  }
  readonly property string activeSet: cfg.sessions[cfg.activeSession] ? cfg.activeSession : ""
  // «Launch»: the set in force — launch its missing apps; another one — switch to it
  // (the switch asks before closing and launches its apps). Editing alone launches nothing
  // but the edited place of the set in force.
  function launchSet() {
    if (!root.service) return
    if (root.set === root.activeSet) root.service.launchActive()
    else root.service.requestSession(root.set)
  }
  // «Take the open windows»: a draft of the desks as they are now, saved only on «Save».
  // refreshToplevels is asynchronous (classes come later): read after it settles, like the service.
  function startCapture() {
    if (!root.service) return
    Hyprland.refreshToplevels()
    captureTimer.restart()
  }
  Timer {
    id: captureTimer
    interval: 300
    onTriggered: {
      root.target = root.set || root.newSet   // the empty session takes no desks
      root.draftFor(Model.captureDesks(root.service.windowsNow(), DesktopEntries.applications.values))
      root.pos = 0
    }
  }
  // The draft for the target: an existing set with apps — its desks plus the new windows
  // (Model.mergeDesks); a new or empty one — the open windows alone. Edits of the draft
  // go when the target changes.
  function draftFor(taken) {
    var t = root.target === root.newSet ? null : root.target ? (root.cfg.sessions[root.target] || {}).workspaces : root.cfg.workspaces
    var m = Model.mergeDesks(t && Object.keys(Model.classesOf(t)).length ? t : {}, taken.desks)
    root.capture = { desks: m.desks, lost: taken.lost.concat(m.lost), taken: taken }
    root.captureHint = ""
  }
  // Draft places of desk `ws` the target set doesn't have there (by count per app);
  // none when the set is new or empty.
  function newMarks(d, ws) {
    if (!root.capture || !d || root.target === root.newSet) return []
    var t = root.target ? (root.cfg.sessions[root.target] || {}).workspaces || {} : root.cfg.workspaces
    if (!Object.keys(Model.classesOf(t)).length) return []
    var had = {}
    ;((t[String(ws)] || {}).slots || []).forEach(function(s) { if (s) had[s.class] = (had[s.class] || 0) + 1 })
    return d.slots.map(function(s) { return !!s && !(had[s.class]-- > 0) })
  }
  // A new session asks its name; an existing set is rewritten only after a yes.
  function askSave() {
    if (root.target === root.newSet) { root.adding = true; root.focusNameField() }
    else confirmOverwrite.opened = true
  }
  // The draft becomes session `name` (its schedule stays)
  // and the set in force: its windows are already open, nothing to launch.
  function saveCapture(name, isNew) {
    name = name.trim()
    if (isNew) {
      root.adding = false
      keyCatcher.forceActiveFocus()
      if (!name) return
      if (root.cfg.sessions[name] || name.toLowerCase() === root.tr("Empty session").toLowerCase() || name === "Empty session") {
        root.captureHint = root.tr("A session with this name exists"); return
      }
    }
    var desks = root.capture.desks
    root.edit(function(next) {
      next.sessions = next.sessions || {}
      var old = next.sessions[name]
      next.sessions[name] = { workspaces: desks, schedule: old && old.schedule || null }
      next.activeSession = name
    })
    root.capture = null
    root.set = name
    root.pos = "head0"
  }
  function deleteSession() {
    var name = root.set
    root.edit(function(next) { delete next.sessions[name]; if (next.activeSession === name) next.activeSession = "" })
    root.set = ""
    root.showPage("main")
    root.pos = "head0"
  }
  function addRule(cls) {
    cls = cls.trim()
    keyCatcher.forceActiveFocus()
    if (cls) root.edit(function(next) { next.singleInstance = (next.singleInstance || []).concat([{ class: cls, action: "focus" }]) })
  }
  function setRule(i, action) { root.edit(function(next) { next.singleInstance[i].action = action }) }
  function removeRule(i) { root.edit(function(next) { next.singleInstance.splice(i, 1) }) }

  function loadDraft() {
    var s = root.set && root.cfg.sessions[root.set] ? root.cfg.sessions[root.set].schedule : null
    root.draft = s ? { days: (s.days || []).slice(), from: s.from || "", to: s.to || "" } : { days: [], from: "", to: "" }
    root.scheduleError = ""
  }
  function toggleDay(d) {
    var days = root.draft.days.slice(), i = days.indexOf(d)
    if (i >= 0) days.splice(i, 1); else days.push(d)
    days.sort(function(a, b) { return a - b })
    root.draft = Object.assign({}, root.draft, { days: days })
    root.saveSchedule()
  }
  function setTime(key, t) {
    var change = {}; change[key] = t.trim()
    root.draft = Object.assign({}, root.draft, change)
    root.saveSchedule()
  }
  // Nothing set — no schedule; otherwise only a valid one that overlaps nothing.
  function saveSchedule() {
    var d = root.draft, name = root.set, err = ""
    // No time typed yet: nothing to check; with no days either, the schedule goes.
    if (d.from || d.to) err = !d.days.length ? "days" : Model.scheduleError(root.cfg.sessions, name, d)
    else if (d.days.length) { root.scheduleError = ""; return }
    root.scheduleError = err === "days" ? root.tr("Pick the days")
      : err === "time" ? root.tr("Time is HH:MM")
      : err === "order" ? root.tr("The end must be after the start")
      : err ? root.tr("Overlaps with %1", err.slice(8)) : ""
    if (err) return
    root.edit(function(next) { next.sessions[name].schedule = d.days.length ? { days: d.days, from: d.from, to: d.to } : null })
  }

  // ------------------------------------------------------------ keys

  function move(dy) {
    root.cursor = Math.max(0, Math.min(root.rows.length - 1, root.cursor + dy))
    pointerGate.reset()
  }
  function startRename() { root.setHint = ""; root.renameHint = ""; root.renaming = true; root.focusNameField() }
  function showPage(p) { root.adding = false; root.renaming = false; root.page = p; root.cursor = 1; root.place = 0 }
  function openDesk(ws) { root.deskWs = ws; root.showPage("desk") }
  function back() {
    if (root.confirming) { if (root.service.phase === "launching") root.host.close(); else root.service.cancelSwitch() }
    else if (root.page === "desk") { root.pos = root.deskWs === "scratchpad" ? 9 : root.deskWs - 1; root.showPage("main") }
    else if (root.page === "schedule") { root.pos = "sched"; root.showPage("main") }
    else if (root.page === "settings") { root.pos = root.gearHead; root.showPage("main") }
    else if (root.capture) { root.capture = null; root.pos = "head2" }
    else root.host.close()
  }
  function arrow(dx, dy) {
    if (root.page === "main") {
      if (root.locked) root.pos = typeof root.pos === "number" ? "head0" : Model.mainMove(root.pos, dx, 0, false, Number(root.gearHead.slice(4)) + 1)
      else root.pos = Model.mainMove(root.pos, dx, dy, root.set !== "" && !root.capture, root.capture ? 2 : Number(root.gearHead.slice(4)) + 1, !!root.capture)
      pointerGate.reset(); return
    }
    var r = root.rows[root.cursor]
    if (r && r.type === "places") {
      var n = Model.placeMove(root.desk ? root.desk.scheme : "single", root.place, dx, dy)
      if (n >= 0) root.place = n
      else if (dy < 0) root.move(-1)
    } else if (dy) root.move(dy)
    else root.change(root.cursor, dx)
  }
  function change(i, dx) {
    var r = root.rows[i], d = root.desk
    if (!r) return
    if (r.type === "days") root.dayCursor = Math.max(0, Math.min(6, root.dayCursor + dx))
    else if (r.type === "name") root.setNameMode(Model.step(Model.NAME_MODES, d ? d.name.mode || "number" : "number", dx))
    else if (r.type === "scheme") root.setScheme(Model.step(Model.SCHEMES, d ? d.scheme : "single", dx))
    else if (r.type === "choice") root.setOption(r.key, Model.step(Model.CHOICES[r.key], root.cfg[r.key], dx))
    else if (r.type === "switch") root.setOption(r.key, !root.cfg[r.key])
    else if (r.type === "rule") root.setRule(r.index, Model.step(Model.ACTIONS, root.cfg.singleInstance[r.index].action, dx))
  }
  function activate() {
    if (root.confirming) { if (root.service.pendingPlan && root.service.phase === "") root.service.confirmSwitch(); return }
    if (root.page === "main") {
      if (typeof root.pos === "number") { if (!root.locked) root.openDesk(root.wsOf(root.pos)) }
      else if (root.pos === "sched") root.showPage("schedule")
      else if (root.pos === "save") root.askSave()
      else if (root.capture && root.pos === "head1") root.back()
      else if (root.pos === "head1") root.launchSet()
      else if (root.pos === "head2") root.startCapture()
      else if (root.pos === root.gearHead) root.showPage("settings")
      else if (root.pos === "head3") root.startRename()
      else if (root.pos === "head4") root.askDelete()
      else if (root.adding) root.focusNameField()
      else if (root.setPicker) root.setPicker.open()
      return
    }
    var i = root.cursor, r = root.rows[i]
    if (!r) return
    if (r.type === "head") root.back()
    else if (r.type === "days") root.toggleDay(root.dayCursor + 1)
    else if (["from", "to", "places", "addRule"].indexOf(r.type) >= 0) root.pressRow(i)
    else if (r.type === "name" && root.desk && root.desk.name.mode === "static") root.pressRow(i)
    else root.change(i, 1)
  }
  // Desk ws (1–9) of the edited set loses its apps, scheme and name. The draft clears at
  // once (it's in memory), a saved set after a yes. Open windows stay.
  property var clearWs: 0
  function askClearDesk(ws) {
    if (Model.isFree(root.desks[String(ws)])) return
    if (root.capture) { root.clearDesk(ws); return }
    root.clearWs = ws
    confirmClear.opened = true
  }
  function clearDesk(ws) {
    if (root.capture) {
      var c = JSON.parse(JSON.stringify(root.capture))
      delete c.desks[String(ws)]
      root.capture = c
      return
    }
    root.edit(function(next) {
      var ds = (next.sessions[root.set] || {}).workspaces
      if (ds) delete ds[String(ws)]
    })
  }

  function remove() {
    if (root.page === "main" && typeof root.pos === "number") { if (!root.locked) root.askClearDesk(root.wsOf(root.pos)); return }
    var r = root.page === "main" ? null : root.rows[root.cursor]
    if (r && r.type === "places") root.setPlace(root.place, "")
    else if (r && r.type === "rule") root.removeRule(r.index)
  }
  signal focusNameField()
  // The set switcher: a session, or "+ New session" → the name field.
  readonly property string newSet: "\u0001new"
  function pickSet(v) {
    if (root.capture) { root.target = v; root.draftFor(root.capture.taken) }
    else if (v === root.newSet) root.adding = true
    else root.set = v
  }

  // ------------------------------------------------------------ texts

  function labelOf(r) {
    if (r.type === "rule") { var x = root.cfg.singleInstance[r.index]; return x.name || x.class || x.match || "" }
    return root.rowLabels[r.type === "switch" && r.key === "schedule" ? "schedule_" : r.key || r.type] || ""
  }
  // App names of a desk's places, "" for an empty place.
  function appNames(d) {
    var out = []
    for (var i = 0; i < Model.PLACES[d ? d.scheme : "single"]; i++) {
      var s = d && d.slots[i]
      var a = s ? root.apps.filter(function(x) { return x.value === s.app || x.cls === s.class })[0] : null
      out.push(!s ? "" : a ? a.label : Model.appNameOf(s.class, DesktopEntries.applications.values))
    }
    return out
  }
  function scheduleText() {
    var s = root.set && root.cfg.sessions[root.set] ? root.cfg.sessions[root.set].schedule : null
    return root.tr("Schedule: %1", s && s.days && s.days.length ? Model.dayRanges(s.days, root.days) + " " + s.from + "–" + s.to : root.tr("none"))
  }
  function title() {
    if (root.confirming) return root.switchTo ? root.tr("Switch to %1?", root.switchTo) : root.tr("Turn off the session?")
    if (root.capture && root.page === "main") return root.tr("Open windows")
    if (root.page === "settings") return root.tr("Settings")
    if (root.page === "schedule") return root.tr("Schedule")
    if (root.page === "desk") {
      var n = root.desk && root.desk.name.mode === "static" ? Model.trimName(root.desk.name.text || "") : ""
      if (root.deskWs === "scratchpad") return root.tr("Scratchpad")
      return root.tr("Desk %1", root.deskWs) + (n ? " · " + n : "")
    }
    return root.tr("Workspaces")
  }
  function options(list) { return list.map(function(v) { return { value: v, label: root.choiceLabels[v] } }) }

  component IconButton: Button {
    iconSize: Style.font.subtitle * 1.5
    horizontalPadding: Style.space(5)
    verticalPadding: Style.space(2)
    width: Math.max(implicitWidth, implicitHeight)   // square, like an icon button
    height: width
    foreground: root.fg
    fontFamily: root.font
  }

  // A click on the dimmed screen or Esc closes it.
  PanelWindow {
    id: modal
    screen: root.screen
    visible: root.opened
    color: Color.menu.scrim
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "predmaxim-workspaces-panel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; onClicked: root.host.close() }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(600), modal.width - Style.space(80))
      height: card.contentTopInset + card.contentBottomInset + head.height
              + (root.confirming ? confirmPage.implicitHeight : flick.height)
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding
      radius: Style.cornerRadius

      MouseArea { anchors.fill: parent }   // clicks on the card stay on it

      // Keys a blocked catcher lets through: the delete dialog's, Esc from a text field.
      Item {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        Keys.onPressed: function(event) {
          if (confirmDelete.opened) event.accepted = confirmDelete.handleKey(event)
          else if (confirmClear.opened) event.accepted = confirmClear.handleKey(event)
          else if (confirmOverwrite.opened) event.accepted = confirmOverwrite.handleKey(event)
          else if (event.key === Qt.Key_Escape) { root.adding = false; root.renaming = false; root.renameHint = ""; keyCatcher.forceActiveFocus(); event.accepted = true }
        }

        PanelKeyCatcher {
          id: keyCatcher
          anchors.fill: parent
          focus: true
          blocked: confirmDelete.opened || confirmClear.opened || confirmOverwrite.opened || root.typing
          onMoveRequested: function(dx, dy) { if (!root.confirming) root.arrow(dx, dy) }
          onActivateRequested: root.activate()
          onCloseRequested: root.back()
          onDeleteRequested: root.remove()

          // Ctrl+arrows on the tiles: swap the desk with its neighbour (the catcher
          // ignores modifiers, so this goes first).
          Keys.forwardTo: [swapKeys]
          Item {
            id: swapKeys
            Keys.onPressed: function(event) {
              var d = { [Qt.Key_Left]: [-1, 0], [Qt.Key_Right]: [1, 0], [Qt.Key_Up]: [0, -1], [Qt.Key_Down]: [0, 1] }[event.key]
              if (!d || !(event.modifiers & Qt.ControlModifier) || keyCatcher.blocked || root.confirming
                  || root.page !== "main" || typeof root.pos !== "number" || root.pos > 8) return
              event.accepted = true
              var col = root.pos % 3 + d[0], row = Math.floor(root.pos / 3) + d[1]
              if (col < 0 || col > 2 || row < 0 || row > 2) return
              root.swapDesks(root.pos + 1, row * 3 + col + 1)
              root.pos = row * 3 + col
            }
          }

          PointerMoveGate { id: pointerGate; referenceItem: list }

          Column {
            id: head
            width: parent.width
            spacing: Style.spacing.xs

            PanelHero {
              width: head.width
              title: root.title()
              meta: root.confirming ? "" : root.capture && root.page === "main" ? root.tr("Now on the desks") : root.page === "schedule" ? root.set : root.cfg.activeSession || root.tr("Empty session")
              foreground: root.fg
              fontFamily: root.font
              iconComponent: Text {
                text: "󰕰"
                color: root.fg
                font.family: root.font
                font.pixelSize: Style.font.display
              }
              // Main page: the set switcher and the gear; other pages: Back.
              trailingControl: Row {
                spacing: Style.space(6)
                visible: !root.confirming
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: root.capture !== null && root.page === "main" && !root.adding
                  text: root.tr("Save to")
                  color: root.dim
                  font.family: root.font
                  font.pixelSize: Style.font.body
                }
                Dropdown {
                  id: setDropdown
                  anchors.verticalCenter: parent.verticalCenter
                  visible: root.page === "main" && !root.adding && !root.renaming
                  width: Style.space(180)
                  showLabel: false
                  options: (root.capture ? Object.keys(root.cfg.sessions) : root.sets).map(function(n) { return { value: n, label: n || root.tr("Empty session") } })
                    .concat([{ value: root.newSet, label: "+ " + root.tr("New session") }])
                  value: root.capture ? root.target : root.set
                  foreground: root.fg
                  fontFamily: root.font
                  hasCursor: root.pos === "head0"
                  onChanged: function(v) { root.pickSet(v); value = Qt.binding(function() { return root.capture ? root.target : root.set }) }
                  // After "+ New session" the name field keeps the keys.
                  onPopupOpenChanged: if (!popupOpen) Qt.callLater(function() { if (root.adding) root.focusNameField(); else root.focusKeys() })
                  Component.onCompleted: root.setPicker = setDropdown
                }
                TextField {
                  id: nameField
                  anchors.verticalCenter: parent.verticalCenter
                  visible: root.page === "main" && (root.adding || root.renaming)
                  width: Style.space(180)
                  placeholderText: root.tr("Session name")
                  foreground: root.fg
                  font.family: root.font
                  font.pixelSize: Style.font.body
                  onVisibleChanged: if (visible) { text = root.renaming ? root.set : ""; forceActiveFocus(); selectAll() }
                  onAccepted: {
                    if (root.renaming) { if (root.renameSet(text)) { root.renaming = false; root.focusKeys() } return }
                    if (root.capture) root.saveCapture(text, true); else root.addSession(text)
                    text = ""
                  }
                  Connections { target: root; function onFocusNameField() { nameField.forceActiveFocus() } }
                }
                IconButton {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: root.page === "main" && !root.capture
                  iconText: "󰐊"
                  tooltipText: root.set === root.activeSet ? root.tr("Launch the apps") : root.tr("Switch to this set")
                  hasCursor: root.pos === "head1"
                  iconSpinning: root.service !== null && root.service.phase === "launching"
                  onClicked: { root.pos = "head1"; root.launchSet() }
                }
                IconButton {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: root.page === "main" && !root.capture
                  iconText: "󰄀"
                  tooltipText: root.tr("Take the open windows")
                  hasCursor: root.pos === "head2"
                  onClicked: { root.pos = "head2"; root.startCapture() }
                }
                IconButton {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: root.page === "main" && !root.capture && root.set !== ""
                  iconText: "󰏫"
                  tooltipText: root.tr("Rename session")
                  hasCursor: root.pos === "head3"
                  onClicked: { root.pos = "head3"; root.startRename() }
                }
                IconButton {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: root.page === "main" && !root.capture && root.set !== ""
                  iconText: "󰩺"
                  tooltipText: root.tr("Delete session")
                  hasCursor: root.pos === "head4"
                  onClicked: { root.pos = "head4"; root.askDelete() }
                }
                IconButton {
                  readonly property bool back: root.page !== "main" || root.capture !== null
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: back ? "󰁍" : "󰒓"
                  tooltipText: back ? root.tr("Back") : root.tr("Settings")
                  hasCursor: root.page !== "main" ? root.cursor === 0 : root.pos === (root.capture ? "head1" : root.gearHead)
                  onClicked: { if (back) root.back(); else root.showPage("settings") }
                }
              }
            }

            // Why the rename or the delete didn't go.
            Text {
              visible: root.page === "main" && text !== ""
              width: head.width
              text: root.renameHint || root.setHint
              color: fixedColors.red
              font.family: root.font
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
            Text {
              visible: !root.confirming && root.service && root.service.loadError !== ""
              width: head.width
              text: root.service ? root.tr("config.json is broken, edits are off: %1", root.service.loadError) : ""
              color: fixedColors.red
              font.family: root.font
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            // The Bluetooth panel's gap: Style.space(14) above and below the line.
            Item {
              width: head.width
              height: Style.space(14) * 2 + 1 - head.spacing * 2
              PanelSeparator { anchors.verticalCenter: parent.verticalCenter; foreground: root.fg }
            }
          }

          Flickable {
            id: flick
            visible: !root.confirming
            anchors.top: head.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: Math.min(list.implicitHeight, modal.height * 0.85 - head.height - card.contentTopInset - card.contentBottomInset)
            contentHeight: list.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: list
              width: flick.width
              spacing: Style.spacing.xs

              Local.Tiles {
                visible: root.page === "main" && !root.locked
                width: list.width
                panel: root
              }
              Text {
                visible: root.page === "main" && root.locked
                width: list.width
                text: root.tr("Windows and desks stay as they are, nothing is bound. To set up desks, create a session.")
                color: root.dim
                font.family: root.font
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }

              // The draft's footer: what won't be kept, why the name doesn't fit, and Save
              // with the target spelled out — it saves the open windows, not the set above.
              Text {
                visible: root.page === "main" && root.capture !== null && (root.capture.lost.length > 0 || root.captureHint !== "")
                width: list.width
                topPadding: Style.space(6)
                text: root.captureHint || (root.capture ? root.tr("Not saved: %1", root.capture.lost.map(Model.prettyClass).join(", ")) : "")
                color: root.captureHint ? fixedColors.red : root.dim
                font.family: root.font
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
              Button {
                visible: root.page === "main" && root.capture !== null
                width: list.width
                bordered: true
                text: root.target === root.newSet ? root.tr("Save the open windows as a new session")
                  : root.tr("Save the open windows to %1", root.target)
                foreground: root.fg
                fontFamily: root.font
                hasCursor: root.pos === "save"
                onClicked: { root.pos = "save"; root.askSave() }
              }

              Repeater {
                id: rep
                model: root.rows

                Local.PanelRow {
                  panel: root
                  width: list.width
                }
              }
            }
          }

          Local.ConfirmPage {
            id: confirmPage
            panel: root
            visible: root.confirming
            anchors.top: head.bottom
            anchors.left: parent.left
            anchors.right: parent.right
          }
        }
      }

      ConfirmDialog {
        id: confirmOverwrite
        anchors.fill: parent
        z: 10
        message: root.tr("Save the open windows to %1?", root.target)
        cancelText: root.tr("Cancel")
        confirmText: root.tr("Save")
        foreground: root.fg
        fontFamily: root.font
        onCanceled: { opened = false; keyCatcher.forceActiveFocus() }
        onConfirmed: { opened = false; root.saveCapture(root.target, false); keyCatcher.forceActiveFocus() }
      }
      ConfirmDialog {
        id: confirmClear
        anchors.fill: parent
        z: 10
        message: root.clearWs === "scratchpad" ? root.tr("Clear the scratchpad?") : root.tr("Clear desk %1?", root.clearWs)
        cancelText: root.tr("Cancel")
        confirmText: root.tr("Clear")
        foreground: root.fg
        fontFamily: root.font
        onCanceled: { opened = false; keyCatcher.forceActiveFocus() }
        onConfirmed: { opened = false; root.clearDesk(root.clearWs); keyCatcher.forceActiveFocus() }
      }
      ConfirmDialog {
        id: confirmDelete
        anchors.fill: parent
        z: 10
        message: root.tr("Delete session %1?", root.set)
        cancelText: root.tr("Cancel")
        confirmText: root.tr("Delete")
        foreground: root.fg
        fontFamily: root.font
        onCanceled: { opened = false; keyCatcher.forceActiveFocus() }
        onConfirmed: { opened = false; root.deleteSession(); keyCatcher.forceActiveFocus() }
      }
    }
  }
}
