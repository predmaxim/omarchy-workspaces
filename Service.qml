import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "Model.js" as Model
import "I18n.js" as I18n

// predmaxim.workspaces: sessions — switching (polite close of the previous session's
// windows, waiting for udisks), launching, the login schedule; config.json for the
// bar widget and the modal. Window rules live in hypr/init.lua (Hyprland).
Item {
  id: root
  property var shell: null
  property var manifest: null
  readonly property var tr: I18n.translator(I18n.textLanguage(Quickshell.env))
  readonly property string path: Quickshell.env("HOME") + "/.config/predmaxim.workspaces/config.json"

  property var raw: ({})
  readonly property var cfg: Model.normalize(raw)
  property string loadError: ""
  property bool scheduleChecked: false

  property var pendingPlan: null   // { to, close: [{address, title}], waitingUdisks }
  property string phase: ""        // "" | "udisks" | "closing" | "launching"
  property var plan: null
  property var stuck: []
  property var launchQueue: []

  FileView {
    id: file
    path: root.path
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        root.raw = JSON.parse(text()); root.loadError = ""
        // At login (the shell starts with the session): the scheduled session, once,
        // after the first successful read.
        if (!root.scheduleChecked) {
          root.scheduleChecked = true
          var name = Model.scheduleAt(root.cfg, new Date())
          if (name && name !== root.cfg.activeSession) root.requestSession(name)
        }
      } catch (e) { root.loadError = String(e) }   // keep the last good one
    }
  }

  function save(next) {
    root.raw = next
    Quickshell.execDetached(["sh", "-c", 'mkdir -p "${1%/*}" && printf "%s\\n" "$2" > "$1.$$" && mv "$1.$$" "$1" && hyprctl reload >/dev/null',
                             "sh", root.path, JSON.stringify(next, null, 2)])
  }

  function windowsNow() {
    return Hyprland.toplevels.values.map(function(t) {
      var o = t.lastIpcObject || {}
      var a = String(t.address)
      return { address: a.indexOf("0x") === 0 ? a : "0x" + a, class: o.class || "", title: o.title || "", ws: t.workspace ? t.workspace.id : 0 }
    })
  }

  function dispatch(expr) { Quickshell.execDetached(["hyprctl", "dispatch", expr]) }

  // ------------------------------------------------------------ switching

  function requestSession(name) {
    if (root.phase !== "" || planTimer.running) return
    if (name !== "" && !root.cfg.sessions[name]) return
    // refreshToplevels is asynchronous: plan from fresh data after it settles.
    Hyprland.refreshToplevels()
    root.wanted = name
    root.pendingPlan = null; root.plan = null
    planTimer.restart()
  }
  property string wanted: ""
  Timer { id: planTimer; interval: 300; onTriggered: root.planFor(root.wanted) }
  function planFor(name) {
    if (root.phase !== "") return
    var now = root.windowsNow()
    var p = Model.sessionPlan(root.cfg, root.cfg.activeSession, name, now)
    root.plan = p
    root.pendingPlan = { to: name, close: now.filter(function(w) { return p.close.indexOf(w.address) >= 0 }), waitingUdisks: false }
    if (root.pendingPlan.close.length === 0) root.confirmSwitch()   // nothing to close — no question
  }
  function cancelSwitch() {
    if (root.phase === "launching") return
    planTimer.stop(); udisksRetry.stop(); closeWait.stop(); launchWait.stop()
    root.pendingPlan = null; root.plan = null; root.stuck = []; root.phase = ""
  }
  function confirmSwitch() {
    if (!root.pendingPlan || root.phase !== "") return
    root.phase = "udisks"
    udisksProc.running = true
  }

  // Unmounting or copying to a flash drive: wait until UDisks2 has no jobs.
  Process {
    id: udisksProc
    command: ["sh", "-c", "busctl --system --list tree org.freedesktop.UDisks2 2>/dev/null | grep -c /jobs/ || true"]
    stdout: StdioCollector {
      onStreamFinished: {
        if (root.phase !== "udisks") return
        if (Number(text.trim()) > 0) {
          root.pendingPlan = Object.assign({}, root.pendingPlan, { waitingUdisks: true })
          udisksRetry.start()
        } else root.startClosing()
      }
    }
  }
  Timer { id: udisksRetry; interval: 1000; onTriggered: udisksProc.running = true }

  // Close all at once, then wait until each is gone or 30 s have passed.
  function startClosing() {
    root.phase = "closing"
    root.stuck = []
    root.plan.close.forEach(function(a) { root.dispatch('hl.dsp.window.close({ window = "address:' + a + '" })') })
    closeWait.elapsed = 0
    closeWait.start()
  }
  Timer {
    id: closeWait
    property int elapsed: 0
    interval: 200; repeat: true
    onTriggered: {
      elapsed += interval
      var up = root.windowsNow().map(function(w) { return w.address })
      var left = root.plan.close.filter(function(a) { return up.indexOf(a) >= 0 })
      if (left.length === 0 || elapsed >= 30000) { stop(); root.stuck = left; root.finishSwitch() }
    }
  }

  function finishSwitch() {
    var to = root.pendingPlan.to
    var moves = root.plan.move.slice()
    var start = Math.max.apply(null, [0].concat(moves.map(function(m) { return m.ws }), Object.keys(root.cfg.sessions[to] ? root.cfg.sessions[to].workspaces : root.cfg.workspaces).map(Number))) + 1
    var staying = root.windowsNow().filter(function(w) { return root.stuck.indexOf(w.address) < 0 && root.plan.close.indexOf(w.address) < 0 })
    var spots = Model.freeDesks(to && root.cfg.sessions[to] ? root.cfg.sessions[to].workspaces : root.cfg.workspaces, staying, root.stuck.length, start)
    root.stuck.forEach(function(a, i) { moves.push({ addr: a, ws: spots[i] }) })
    moves.forEach(function(m) {
      root.dispatch('hl.dsp.window.move({ window = "address:' + m.addr + '", workspace = "' + m.ws + '", follow = false })')
    })
    if (root.stuck.length) {
      var titles = root.pendingPlan.close.filter(function(w) { return root.stuck.indexOf(w.address) >= 0 }).map(function(w) { return w.title })
      Quickshell.execDetached(["omarchy-notification-send", "-u", "normal", root.tr("Workspaces"), root.tr("Not closed: %1", titles.join(", "))])
    }
    var next = JSON.parse(JSON.stringify(root.raw))
    next.activeSession = to
    root.save(next)
    root.launchQueue = root.plan.launch.slice()
    root.pendingPlan = null
    root.phase = "launching"
    root.launchNext()
  }

  function launchNext() {
    if (root.launchQueue.length === 0) { root.phase = ""; root.plan = null; return }
    if (!root.cfg.sequentialLaunch) {
      root.launchQueue.forEach(function(l) { Quickshell.execDetached(["uwsm-app", "--", l.app]) })
      root.launchQueue = []
      root.launchNext()
      return
    }
    Quickshell.execDetached(["uwsm-app", "--", root.launchQueue[0].app])
    launchWait.cls = root.launchQueue[0].class
    launchWait.elapsed = 0
    launchWait.start()
  }
  Timer {
    id: launchWait
    property string cls: ""
    property int elapsed: 0
    interval: 200; repeat: true
    onTriggered: {
      elapsed += interval
      var up = root.windowsNow().some(function(w) { return w.class === cls })
      if (up || elapsed >= 15000) { stop(); root.launchQueue = root.launchQueue.slice(1); root.launchNext() }
    }
  }

  IpcHandler {
    target: "predmaxim.workspaces"
    function session(name: string): string {
      if (name !== "" && !root.cfg.sessions[name]) return "unknown session: " + name
      root.requestSession(name); return "ok"
    }
    function status(): string { return JSON.stringify({ active: root.cfg.activeSession, phase: root.phase, error: root.loadError }) }
  }
}
