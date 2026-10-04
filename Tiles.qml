import QtQuick
import qs.Commons
import qs.Ui
import "." as Local
import "Model.js" as Model

// The modal's main page: the session's schedule row (sessions only) and desks 1–9
// as 3×3 tiles — number, name, a drawing of the scheme with the apps in their places.
// `panel` is the modal (Panel.qml): state, texts, edits; its `pos` is the cursor.
Column {
  id: root
  property var panel: null
  spacing: Style.spacing.xs

  CursorSurface {
    visible: root.panel.set !== ""
    width: root.width
    implicitHeight: Style.space(42)
    foreground: root.panel.fg
    hasCursor: root.panel.pos === "sched"
    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.verticalCenter: parent.verticalCenter
      text: root.panel.scheduleText()
      color: root.panel.fg
      font.family: root.panel.font
      font.pixelSize: Style.font.body
    }
    MouseArea {
      anchors.fill: parent
      onClicked: { root.panel.pos = "sched"; root.panel.activate() }
    }
  }

  Grid {
    id: grid
    columns: 3
    spacing: Style.spacing.xs
    readonly property real tileWidth: (root.width - spacing * 2) / 3

    Repeater {
      model: 9
      CursorSurface {
        id: tile
        required property int index
        readonly property int ws: index + 1
        readonly property var desk: root.panel.desks[String(ws)] || null
        readonly property bool free: Model.isFree(desk)
        width: grid.tileWidth
        implicitHeight: Style.space(110)
        foreground: root.panel.fg
        bordered: true
        hasCursor: root.panel.pos === index
        opacity: free ? 0.55 : 1

        MouseArea {
          id: area
          anchors.fill: parent
          hoverEnabled: true
          onPositionChanged: function(mouse) { if (root.panel.gate.moved(area, mouse)) root.panel.pos = tile.index }
          onClicked: { root.panel.pos = tile.index; root.panel.activate() }
        }

        Column {
          anchors.fill: parent
          anchors.margins: Style.space(8)
          spacing: Style.space(6)
          Row {
            width: parent.width
            spacing: Style.space(8)
            Text {
              id: num
              text: tile.ws
              color: root.panel.fg
              font.family: root.panel.font
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              width: parent.width - num.width - parent.spacing
              text: !tile.desk ? "" : tile.desk.name.mode === "static" ? Model.trimName(tile.desk.name.text || "")
                  : tile.desk.name.mode === "dynamic" ? root.panel.tr("by window") : ""
              color: tile.desk && tile.desk.name.mode === "dynamic" ? root.panel.dim : root.panel.fg
              font.family: root.panel.font
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
          }
          Local.Scheme {
            width: parent.width
            height: parent.height - num.height - parent.spacing
            scheme: tile.desk ? tile.desk.scheme : "single"
            labels: tile.free ? [] : root.panel.appNames(tile.desk)
            emptyText: tile.free ? root.panel.tr("free") : "+"
            foreground: root.panel.fg
            fontFamily: root.panel.font
          }
        }
      }
    }
  }
}
