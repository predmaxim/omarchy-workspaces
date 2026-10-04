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
// and the IPC `omarchy-shell predmaxim.workspaces-panel toggle`). Pages: main (the
// set — plain desks or a session —, its schedule, desks 1–9, the open desk's name,
// scheme and places), settings behind the gear, and the session switch
// confirmation, which opens by itself while the service waits for an answer.
// Rows come from Model.rows; ↑/↓ rows, ←/→ value, Enter open/press, Esc back.
Item {
  id: root
  property var host: null
  property var service: null
  property var screen: null

  readonly property var tr: I18n.translator(I18n.textLanguage(Quickshell.env))
  readonly property var cfg: service ? service.cfg : Model.normalize({})
  readonly property bool opened: host ? host.opened : false
  readonly property color fg: Color.popups.text
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property string font: Style.font.family

  property string page: "main"
  property string set: ""          // "" — plain desks, else a session
  property int expanded: 0         // the open desk
  property int cursor: 1
  property bool adding: false      // the new session's name field in the set row
  property bool confirming: false
  property string switchTo: ""
  property var draft: ({ days: [], from: "", to: "" })
  property string scheduleError: ""
  property string setHint: ""      // under the set row: why the session can't be deleted
  property int setCol: 0           // the set row's control under the cursor (Model.setCol)
  property int dayCursor: 0        // the day under the cursor in the days row

  readonly property var rows: confirming ? [] : Model.rows(page, cfg, set, expanded)
  readonly property var desks: set && cfg.sessions[set] ? cfg.sessions[set].workspaces : cfg.workspaces
  readonly property var sets: [""].concat(Object.keys(cfg.sessions))
  readonly property var apps: DesktopEntries.applications.values
    .map(function(e) { return { label: e.name, value: e.id, cls: e.startupClass || e.id.replace(/\.desktop$/, "") } })
    .sort(function(a, b) { return a.label.localeCompare(b.label) })
  readonly property bool typing: keyCatcher.Window.activeFocusItem !== null && keyCatcher.Window.activeFocusItem !== keyCatcher
  readonly property var choiceLabels: ({ tile: tr("Stays"), float: tr("Floating"), next: tr("Next desk"),
                                         free: tr("Only free"), all: tr("All"), off: tr("Don't collapse"),
                                         number: tr("Number"), dynamic: tr("By window"), static: tr("Custom"),
                                         focus: tr("Focus"), ask: tr("Ask"), replace: tr("Replace") })
  readonly property var rowLabels: ({ set: tr("Set"), days: tr("Days"), from: tr("From"), to: tr("To"), name: tr("Name"), scheme: tr("Scheme"),
                                      addRule: tr("One app window"), foreignWindow: tr("Foreign window on a laid-out desk"),
                                      collapse: tr("Collapsing without a session"), collapseInSession: tr("Collapsing in a session"),
                                      sequentialLaunch: tr("Launch one by one"), schedule_: tr("Scheduled session at login") })
  readonly property var schemeGlyphs: ({ single: "□", "left-right": "◫", "top-bottom": "⊟", "main-left": "◧", grid: "⊞" })
  readonly property var schemeNames: ({ single: tr("One window"), "left-right": tr("Left and right"), "top-bottom": tr("Top and bottom"),
                                        "main-left": tr("Main on the left"), grid: tr("Grid") })
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
        page = "main"; expanded = 0; cursor = 1; adding = false
        set = cfg.sessions[cfg.activeSession] ? cfg.activeSession : ""
        loadDraft()
      }
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else if (confirming && service && service.phase === "") service.cancelSwitch()
  }
  onSetChanged: { loadDraft(); setHint = ""; setCol = 0 }
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
  // The service asks (windows to close) → the confirmation page; it's done → close.
  function sync() {
    var s = root.service
    if (s.pendingPlan && s.pendingPlan.close.length && !root.confirming) {
      root.switchTo = s.pendingPlan.to; root.confirming = true; root.host.open()
    } else if (root.confirming && !s.pendingPlan && s.phase === "") {
      root.confirming = false; root.host.close()
    }
  }

  // ------------------------------------------------------------ editing: copy raw, change, save

  function edit(fn) {
    if (!root.service || root.service.loadError !== "") return   // broken config.json: no edits
    var next = JSON.parse(JSON.stringify(root.service.raw))
    fn(next)
    root.service.save(next)
  }
  function editDesk(ws, fn) {
    root.edit(function(next) {
      var ds = root.set ? (next.sessions[root.set].workspaces = next.sessions[root.set].workspaces || {})
                        : (next.workspaces = next.workspaces || {})
      fn(ds[ws] = ds[ws] || { scheme: "single", slots: [], name: { mode: "number" } })
    })
  }
  function setOption(key, value) { root.edit(function(next) { next[key] = value }) }
  function setScheme(ws, v) { root.editDesk(ws, function(d) { d.scheme = v; d.slots = (d.slots || []).slice(0, Model.PLACES[v]) }) }
  function setNameMode(ws, v) {
    root.editDesk(ws, function(d) { d.name = v === "static" ? { mode: v, text: d.name && d.name.text || "" } : { mode: v } })
  }
  function setNameText(ws, t) { root.editDesk(ws, function(d) { d.name = { mode: "static", text: t } }) }
  // Places fill in order: a slot past the last filled one becomes the next one.
  function setPlace(ws, i, id) {
    var app = root.apps.filter(function(a) { return a.value === id })[0]
    root.editDesk(ws, function(d) {
      d.slots = d.slots || []
      if (!app) d.slots.splice(i, 1)
      else d.slots[Math.min(i, d.slots.length)] = { app: app.value, class: app.cls }
    })
  }
  function addSession(name) {
    name = name.trim()
    root.adding = false
    keyCatcher.forceActiveFocus()
    if (!name || root.cfg.sessions[name]) return
    root.edit(function(next) { next.sessions = next.sessions || {}; next.sessions[name] = { workspaces: {} } })
    root.set = name
  }
  function deleteSession() {
    var name = root.set
    root.edit(function(next) { delete next.sessions[name]; if (next.activeSession === name) next.activeSession = "" })
    root.set = ""
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
  function showPage(p) { root.page = p; root.cursor = 1; root.expanded = 0 }
  function back() {
    if (root.confirming) { if (root.service.phase === "launching") root.host.close(); else root.service.cancelSwitch() }
    else if (root.page === "settings") root.showPage("main")
    else if (root.expanded) { root.cursor = root.rows.map(function(r) { return r.ws }).indexOf(root.expanded); root.expanded = 0 }
    else root.host.close()
  }
  function change(i, dx) {
    var r = root.rows[i]
    if (!r) return
    var desk = root.desks[String(r.ws)]
    if (r.type === "set") { if (!root.adding) root.setCol = Model.setCol(root.setCol, dx, root.set) }
    else if (r.type === "days") root.dayCursor = Math.max(0, Math.min(6, root.dayCursor + dx))
    else if (r.type === "name") root.setNameMode(r.ws, Model.step(Model.NAME_MODES, desk ? desk.name.mode || "number" : "number", dx))
    else if (r.type === "scheme") root.setScheme(r.ws, Model.step(Model.SCHEMES, desk ? desk.scheme : "single", dx))
    else if (r.type === "choice") root.setOption(r.key, Model.step(Model.CHOICES[r.key], root.cfg[r.key], dx))
    else if (r.type === "switch") root.setOption(r.key, !root.cfg[r.key])
    else if (r.type === "rule") root.setRule(r.index, Model.step(Model.ACTIONS, root.cfg.singleInstance[r.index].action, dx))
  }
  function activate(i) {
    var r = root.rows[i]
    if (root.confirming) { if (root.service.pendingPlan && root.service.phase === "") root.service.confirmSwitch(); return }
    if (!r) return
    if (r.type === "head") root.showPage(root.page === "settings" ? "main" : "settings")
    else if (r.type === "desk") root.expanded = root.expanded === r.ws ? 0 : r.ws
    else if (r.type === "set" && root.setCol === 1 && !root.adding) root.adding = true
    else if (r.type === "set" && root.setCol === 2 && !root.adding) root.askDelete()
    else if (r.type === "days") root.toggleDay(root.dayCursor + 1)
    else if (["set", "from", "to", "place", "addRule"].indexOf(r.type) >= 0) root.pressRow(i)
    else if (r.type === "name" && root.desks[String(r.ws)] && root.desks[String(r.ws)].name.mode === "static") root.pressRow(i)
    else root.change(i, 1)
  }
  function remove(i) {
    var r = root.rows[i]
    if (r && r.type === "set" && root.set) root.askDelete()
    else if (r && r.type === "rule") root.removeRule(r.index)
  }

  // ------------------------------------------------------------ texts

  function labelOf(r) {
    if (r.type === "desk") {
      var d = root.desks[String(r.ws)]
      var name = !d ? "" : d.name.mode === "static" ? d.name.text || "" : d.name.mode === "dynamic" ? root.tr("By window") : ""
      return r.ws + "   " + Model.trimName(name)
    }
    if (r.type === "place") return root.tr("Place %1", r.slot + 1)
    if (r.type === "rule") { var x = root.cfg.singleInstance[r.index]; return x.name || x.class || x.match || "" }
    return root.rowLabels[r.type === "switch" && r.key === "schedule" ? "schedule_" : r.key || r.type] || ""
  }
  function deskApps(ws) {
    var d = root.desks[String(ws)]
    if (!d) return ""
    return d.slots.map(function(s) {
      var a = root.apps.filter(function(x) { return x.value === s.app || x.cls === s.class })[0]
      return a ? a.label : s.class
    }).join(", ")
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
          else if (event.key === Qt.Key_Escape) { root.adding = false; keyCatcher.forceActiveFocus(); event.accepted = true }
        }

        PanelKeyCatcher {
          id: keyCatcher
          anchors.fill: parent
          focus: true
          blocked: confirmDelete.opened || root.typing
          onMoveRequested: function(dx, dy) {
            if (root.confirming) return
            if (dy) root.move(dy)
            else if (dx) root.change(root.cursor, dx)
          }
          onActivateRequested: root.activate(root.cursor)
          onCloseRequested: root.back()
          onDeleteRequested: root.remove(root.cursor)

          PointerMoveGate { id: pointerGate; referenceItem: list }

          Column {
            id: head
            width: parent.width
            spacing: Style.spacing.xs

            PanelHero {
              width: head.width
              title: root.confirming ? (root.switchTo ? root.tr("Switch to %1?", root.switchTo) : root.tr("Turn off the session?"))
                   : root.page === "settings" ? root.tr("Settings") : root.tr("Workspaces")
              meta: root.confirming ? "" : root.cfg.activeSession || root.tr("No session")
              foreground: root.fg
              fontFamily: root.font
              iconComponent: Text {
                text: "󰕰"
                color: root.fg
                font.family: root.font
                font.pixelSize: Style.font.display
              }
              trailingControl: IconButton {
                readonly property bool back: root.page === "settings"
                visible: !root.confirming
                iconText: back ? "󰁍" : "󰒓"
                tooltipText: back ? root.tr("Back") : root.tr("Settings")
                hasCursor: root.cursor === 0
                onClicked: { root.cursor = 0; root.activate(0) }
              }
            }

            Text {
              visible: !root.confirming && root.service && root.service.loadError !== ""
              width: head.width
              text: root.service ? root.tr("config.json is broken, edits are off: %1", root.service.loadError) : ""
              color: Color.urgent
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

          Column {
            id: confirmPage
            visible: root.confirming
            anchors.top: head.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Style.spacing.xs
            readonly property var plan: root.service ? root.service.pendingPlan : null
            readonly property string phase: root.service ? root.service.phase : ""
            // The first window of the plan still open (toplevels for the binding).
            readonly property string closingNow: {
              if (phase !== "closing" || !plan) return ""
              void Hyprland.toplevels.values
              var up = root.service.windowsNow().map(function(w) { return w.address })
              var left = plan.close.filter(function(w) { return up.indexOf(w.address) >= 0 })
              return left.length ? left[0].title || left[0].address : "…"
            }

            Repeater {
              model: confirmPage.plan ? confirmPage.plan.close : []
              Text {
                required property var modelData
                width: confirmPage.width
                text: "• " + (modelData.title || modelData.address)
                color: root.fg
                font.family: root.font
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }
            }
            Text {
              visible: text !== ""
              text: confirmPage.phase === "udisks" ? root.tr("Waiting for the flash drive…")
                  : confirmPage.phase === "closing" ? root.tr("Closing: %1", confirmPage.closingNow)
                  : confirmPage.phase === "launching" ? root.tr("Launching…") : ""
              color: root.dim
              font.family: root.font
              font.pixelSize: Style.font.body
            }
            Item { width: 1; height: Style.space(8) }
            Row {
              anchors.right: parent.right
              spacing: Style.space(10)
              Button {
                visible: confirmPage.phase !== "launching"
                bordered: true
                text: root.tr("Cancel")
                foreground: root.fg
                fontFamily: root.font
                onClicked: root.service.cancelSwitch()
              }
              Button {
                visible: confirmPage.plan !== null && confirmPage.phase === ""
                bordered: true
                hasCursor: true
                text: root.tr("Close and switch")
                foreground: root.fg
                fontFamily: root.font
                onClicked: root.service.confirmSwitch()
              }
            }
          }
        }
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
