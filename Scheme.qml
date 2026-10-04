import QtQuick
import qs.Commons
import "Model.js" as Model

// A drawing of a desk scheme (Model.geometry): filled places show `labels[i]`
// (an app name) and `subs[i]` under it; empty ones are outlined with `emptyText`.
// Tiles, the scheme picker and the desk page's places use it.
Item {
  id: root
  property string scheme: "single"
  property var labels: []
  property var subs: []
  property string emptyText: "+"
  property int cursor: -1          // the place under the keyboard cursor
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.caption
  property real gap: Style.space(3)
  property bool interactive: false
  signal picked(int i)

  Repeater {
    model: Model.geometry(root.scheme)
    Rectangle {
      required property var modelData
      required property int index
      readonly property bool filled: !!root.labels[index]
      x: modelData.x * root.width + root.gap / 2
      y: modelData.y * root.height + root.gap / 2
      width: modelData.w * root.width - root.gap
      height: modelData.h * root.height - root.gap
      radius: Style.space(3)
      color: filled ? Util.alpha(root.foreground, 0.16) : "transparent"
      border.width: root.cursor === index ? Math.max(2, Style.space(2)) : filled ? 0 : 1
      border.color: root.cursor === index ? root.foreground : Util.alpha(root.foreground, 0.35)

      Column {
        anchors.centerIn: parent
        width: parent.width - Style.space(4)
        Text {
          width: parent.width
          visible: text !== ""
          text: parent.parent.filled ? root.labels[parent.parent.index] : root.emptyText
          color: parent.parent.filled ? root.foreground : Util.alpha(root.foreground, 0.5)
          font.family: root.fontFamily
          font.pixelSize: root.fontSize
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          visible: text !== ""
          text: root.subs[parent.parent.index] || ""
          color: Util.alpha(root.foreground, 0.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }
      }
      MouseArea { anchors.fill: parent; enabled: root.interactive; onClicked: root.picked(parent.index) }
    }
  }
}
