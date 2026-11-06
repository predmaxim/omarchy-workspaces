import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "I18n.js" as I18n
import "." as Local

// predmaxim.workspaces on the bar: [session ▾] then Omarchy's own desk row (Desks.qml:
// its Workspaces.qml with desks.patch, built by ./sync-desks), which asks this widget
// for desk names ("2 Firefox", ≤ 50 chars) and the desks with bindings. Session
// click — the list of sessions; desk click — go there; right click — the settings modal.
Panel {
  id: root
  moduleName: "predmaxim.workspaces"
  ipcTarget: "predmaxim.workspaces-panel"

  readonly property var tr: I18n.translator(I18n.textLanguage(Quickshell.env))
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  // The service is a separate plugin instance; look it up until it is there.
  property var service: null
  Timer {
    interval: 2000; repeat: true; running: root.service === null; triggeredOnStart: true
    onTriggered: {
      var host = root.bar && root.bar.shell ? root.bar.shell : null
      if (host && typeof host.serviceFor === "function") root.service = host.serviceFor("predmaxim.workspaces")
    }
  }

  readonly property var cfg: service ? service.cfg : Model.normalize({})
  readonly property string session: cfg.activeSession
  readonly property var desks: Model.activeDesks(cfg)
  // "" (no session) first, then the sessions.
  readonly property var sessionRows: [""].concat(Object.keys(cfg.sessions))
  // Under the sessions: take the open windows (the modal's draft), set up the sessions (the modal).
  readonly property var actionRows: [{ key: "capture", icon: "󰄀", text: tr("Take the open windows") }, { key: "edit", icon: "󰒓", text: tr("Set up sessions") }]
  property int cursor: 0

  // For the desk row (Desks.qml). Desks with bindings or an own name show even when empty.
  function shownSlots() {
    return Object.keys(root.desks).map(Number).filter(function(slot) {
      var d = root.desks[slot]
      return slot > 0 && slot <= 10 && (d.slots.length || d.name.mode === "static")
    })
  }

  // The name after the desk's number ("Firefox"), "" for none.
  function deskName(slot, workspace) {
    var label = Model.deskLabel(slot, root.desks[slot], root.windowsOf(workspace), root.appName)
    return label === String(slot) ? "" : label.slice(String(slot).length + 1)
  }

  // Super + L asks every instance of the row's widget to read the layout again
  // (BarWidget.broadcast); the row is ours, so pass it on.
  function refresh() { if (desks.item) desks.item.refresh() }

  function appName(cls) { return Model.appNameOf(cls, DesktopEntries.applications.values) }

  function windowsOf(workspace) {
    if (!workspace) return []
    return workspace.toplevels.values.map(function(t) {
      var o = t.lastIpcObject || ({})
      return { class: o["class"] || "", fullscreen: o.fullscreen || 0 }
    })
  }

  function pickSession(i) {
    if (i >= sessionRows.length && i < sessionRows.length + actionRows.length) {
      sessions.open = false
      root.open()
      if (actionRows[i - sessionRows.length].key === "capture") Qt.callLater(modal.startCapture)
      return
    }
    if (!root.service || i < 0 || i >= sessionRows.length) return
    sessions.open = false
    root.service.requestSession(sessionRows[i])
  }

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  RowLayout {
    id: row
    anchors.fill: parent
    spacing: Style.space(1)

    WidgetButton {
      id: sessionButton
      visible: root.session !== "" || !root.cfg.hideNoSession
      bar: root.bar
      text: (root.session || root.tr("Empty session")) + " ▾"
      horizontalMargin: 6
      verticalPadding: 6
      fixedHeight: root.barSize
      onPressed: function(button) {
        root.cursor = Math.max(0, root.sessionRows.indexOf(root.session))
        sessions.open = !sessions.open
      }
    }

    // Without Desks.qml (not built yet, or desks.patch no longer fits) Omarchy's row as it is.
    Loader {
      id: desks
      source: Qt.resolvedUrl("Desks.qml")
      onStatusChanged: {
        if (status === Loader.Error) source = "file://" + Quickshell.env("OMARCHY_PATH") + "/shell/plugins/bar/widgets/Workspaces.qml"
      }
      onLoaded: {
        item.bar = Qt.binding(function() { return root.bar })
        item.moduleName = root.moduleName
        if (item.host !== undefined) item.host = root
      }
    }
  }

  KeyboardPanel {
    id: sessions
    anchorItem: sessionButton
    bar: root.bar
    focusTarget: keyCatcher
    contentWidth: sessions.fittedContentWidth(Style.space(240))
    contentHeight: sessions.fittedContentHeight(list.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dy) { root.cursor = Math.max(0, Math.min(root.sessionRows.length + root.actionRows.length - 1, root.cursor + dy)); gate.reset() }
      }
      onActivateRequested: root.pickSession(root.cursor)
      onCloseRequested: sessions.open = false

      PointerMoveGate { id: gate; referenceItem: list }

      Column {
        id: list
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top

        Repeater {
          model: root.sessionRows

          CursorSurface {
            id: item
            required property string modelData
            required property int index
            width: list.width
            implicitHeight: label.implicitHeight + Style.spacing.xl
            foreground: root.fg
            hasCursor: root.cursor === index
            current: modelData === root.session

            MouseArea {
              id: area
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onPositionChanged: function(mouse) { if (gate.moved(area, mouse)) root.cursor = item.index }
              onClicked: root.pickSession(item.index)
            }

            Text {
              id: label
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.right: mark.left
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: item.modelData === "" ? root.tr("Empty session") : item.modelData
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: item.current
              elide: Text.ElideRight
            }

            Text {
              id: mark
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: item.current ? "✓" : ""
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }
        }

        // A gap around the line: the sessions apart from the actions.
        Item {
          width: list.width
          height: Style.space(6) * 2 + 1
          PanelSeparator { width: parent.width; anchors.verticalCenter: parent.verticalCenter; foreground: root.fg }
        }

        Repeater {
          model: root.actionRows

          CursorSurface {
            id: action
            required property var modelData
            required property int index
            readonly property int row: root.sessionRows.length + index
            width: list.width
            implicitHeight: actionLabel.implicitHeight + Style.spacing.xl
            foreground: root.fg
            hasCursor: root.cursor === row

            MouseArea {
              id: actionArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onPositionChanged: function(mouse) { if (gate.moved(actionArea, mouse)) root.cursor = action.row }
              onClicked: root.pickSession(action.row)
            }

            Text {
              id: actionIcon
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: action.modelData.icon
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Text {
              id: actionLabel
              anchors.left: actionIcon.right
              anchors.leftMargin: Style.space(8)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: action.modelData.text
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
          }
        }
      }
    }
  }

  // The session list from a hotkey (the bar's own target is taken by the modal).
  IpcHandler {
    target: "predmaxim.workspaces-sessions"
    function toggle(): void {
      root.cursor = Math.max(0, root.sessionRows.indexOf(root.session))
      sessions.open = !sessions.open
    }
  }

  // The settings modal and the session switch confirmation.
  Local.Panel {
    id: modal
    host: root
    service: root.service
    screen: root.QsWindow.window ? root.QsWindow.window.screen : null
  }
}
