import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "I18n.js" as I18n
import "." as Local

// predmaxim.workspaces on the bar: [session ▾] then the desks as the stock widget
// draws them, with names ("2 Firefox", ≤ 50 chars). Session click — the list of
// sessions; desk click — go there; right click — the settings modal.
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
  property int cursor: 0

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }
    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  function appName(cls) {
    var apps = DesktopEntries.applications.values
    for (var i = 0; i < apps.length; i++) {
      if (apps[i].startupClass === cls || apps[i].id === cls) return apps[i].name
    }
    return ""
  }

  function windowsOf(workspace) {
    if (!workspace) return []
    return workspace.toplevels.values.map(function(t) {
      var o = t.lastIpcObject || ({})
      return { class: o["class"] || "", fullscreen: o.fullscreen || 0 }
    })
  }

  function pickSession(i) {
    if (!root.service || i < 0 || i >= sessionRows.length) return
    sessions.open = false
    root.service.requestSession(sessionRows[i])
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: row.implicitWidth + trailingGap
  implicitHeight: row.implicitHeight

  RowLayout {
    id: row
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    spacing: Style.space(1)

    WidgetButton {
      id: sessionButton
      visible: root.session !== ""
      bar: root.bar
      text: root.session + " ▾"
      horizontalMargin: 6
      verticalPadding: 6
      fixedHeight: root.barSize
      onPressed: function(button) {
        root.cursor = Math.max(0, root.sessionRows.indexOf(root.session))
        sessions.open = !sessions.open
      }
    }

    GridLayout {
      id: grid
      columns: root.vertical ? 1 : root.workspaceIds().length
      columnSpacing: root.vertical ? 0 : Style.space(1)
      rowSpacing: root.vertical ? Style.space(2) : 0

      Repeater {
        model: root.workspaceIds()

        WidgetButton {
          required property int modelData

          readonly property var workspace: root.workspaceById(modelData)
          readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
          readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
          readonly property string label: Model.deskLabel(modelData, root.desks[modelData], root.windowsOf(workspace), root.appName)
          readonly property string number: modelData === 10 ? "0" : String(modelData)
          readonly property bool named: label !== String(modelData)

          bar: root.bar
          text: focused ? "󱓻" + (named ? label.slice(String(modelData).length) : "") : (named ? label : number)
          opacity: occupied || focused ? 1 : 0.5
          horizontalMargin: 6
          verticalPadding: 6
          fixedWidth: root.vertical ? root.barSize : (named ? -1 : Style.space(20))
          fixedHeight: root.barSize
          onPressed: function(button) {
            if (button === Qt.RightButton) root.toggle()
            else root.focusWorkspace(modelData)
          }
        }
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
        if (dy) { root.cursor = Math.max(0, Math.min(root.sessionRows.length - 1, root.cursor + dy)); gate.reset() }
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
              text: item.modelData === "" ? root.tr("No session") : item.modelData
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
      }
    }
  }

  // The settings modal and the session switch confirmation.
  Local.Panel {
    host: root
    service: root.service
    screen: root.QsWindow.window ? root.QsWindow.window.screen : null
  }
}
