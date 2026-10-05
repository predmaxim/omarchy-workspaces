import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "." as Local
import "Model.js" as Model

// One row of a list page of the Workspaces modal (Panel.qml): the label and, on the
// right, the control for the row's type (Model.rows); "places" — the label above and
// the large scheme drawing under it. `panel` is the modal: state and edits.
CursorSurface {
  id: row
  property var panel: null

  component Field: TextField {
    foreground: row.panel.fg
    font.family: row.panel.font
    font.pixelSize: Style.font.body
  }
  component IconButton: Button {
    iconSize: Style.font.subtitle * 1.5
    horizontalPadding: Style.space(5)
    verticalPadding: Style.space(2)
    width: Math.max(implicitWidth, implicitHeight)   // square, like an icon button
    height: width
    foreground: row.panel.fg
    fontFamily: row.panel.font
  }
  required property var modelData
  required property int index
  readonly property var desk: row.panel.desk
  readonly property bool wide: modelData.type === "places"
  visible: modelData.type !== "head"
  implicitHeight: wide ? labels.implicitHeight + control.implicitHeight + Style.spacing.xs * 3
                : Math.max(Style.space(42), control.implicitHeight + Style.spacing.xs * 2, labels.implicitHeight + Style.spacing.xs * 2)
  foreground: row.panel.fg
  hasCursor: row.panel.cursor === index

  Connections {
    target: row.panel
    function onPressRow(i) { if (i === row.index && control.item && control.item.press) control.item.press() }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    onPositionChanged: function(mouse) { if (row.panel.gate.moved(area, mouse)) row.panel.cursor = row.index }
    onClicked: row.panel.cursor = row.index
  }

  Column {
    id: labels
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.rowPaddingX
    anchors.right: row.wide ? parent.right : control.left
    anchors.rightMargin: row.wide ? Style.spacing.rowPaddingX : Style.space(8)
    anchors.verticalCenter: row.wide ? undefined : parent.verticalCenter
    anchors.top: row.wide ? parent.top : undefined
    anchors.topMargin: Style.spacing.xs
    Text {
      width: parent.width
      text: row.panel.labelOf(row.modelData)
      color: row.panel.fg
      font.family: row.panel.font
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }
    Text {
      visible: text !== ""
      width: parent.width
      text: row.modelData.type === "to" ? row.panel.scheduleError : ""
      color: Color.urgent
      font.family: row.panel.font
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }

  Loader {
    id: control
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.rowPaddingX
    anchors.verticalCenter: row.wide ? undefined : parent.verticalCenter
    anchors.top: row.wide ? labels.bottom : undefined
    anchors.topMargin: Style.spacing.xs
    anchors.left: row.wide ? parent.left : undefined
    anchors.leftMargin: Style.spacing.rowPaddingX
    sourceComponent: ({ days: daysControl, from: timeControl, to: timeControl, name: nameControl, scheme: schemeControl,
                        places: placesControl, choice: choiceControl, switch: switchControl,
                        rule: ruleControl, addRule: addRuleControl })[row.modelData.type] || null

    Component {
      id: daysControl
      Row {
        spacing: Style.space(4)
        Repeater {
          model: row.panel.days
          Button {
            required property string modelData
            required property int index
            text: modelData
            selected: row.panel.draft.days.indexOf(index + 1) >= 0
            hasCursor: row.hasCursor && row.panel.dayCursor === index
            horizontalPadding: Style.space(5)
            foreground: row.panel.fg
            fontFamily: row.panel.font
            onClicked: { row.panel.dayCursor = index; row.panel.toggleDay(index + 1) }
          }
        }
      }
    }
    Component {
      id: timeControl
      // Enter or Esc gives the keys back to the rows; leaving the field saves.
      Field {
        readonly property string key: row.modelData.type
        function press() { forceActiveFocus() }
        width: Style.space(80)
        placeholderText: row.panel.tr("HH:MM")
        text: row.panel.draft[key]
        maximumLength: 5
        onAccepted: row.panel.focusKeys()
        onEditingFinished: if (text.trim() !== row.panel.draft[key]) row.panel.setTime(key, text)
      }
    }
    Component {
      id: nameControl
      Row {
        spacing: Style.space(6)
        function press() { textField.forceActiveFocus() }
        Field {
          id: textField
          visible: row.desk !== null && row.desk.name.mode === "static"
          width: Style.space(160)
          maximumLength: 50
          text: row.desk && row.desk.name.text || ""
          onEditingFinished: if (text !== (row.desk && row.desk.name.text || "")) row.panel.setNameText(text)
        }
        ButtonGroup {
          anchors.verticalCenter: parent.verticalCenter
          options: row.panel.options(Model.NAME_MODES)
          value: row.desk ? row.desk.name.mode || "number" : "number"
          focusable: false
          foreground: row.panel.fg
          fontFamily: row.panel.font
          onChanged: function(v) { row.panel.setNameMode(v) }
        }
      }
    }
    Component {
      id: schemeControl
      // The five schemes as drawings; the current one outlined.
      Row {
        spacing: Style.space(6)
        Repeater {
          model: Model.SCHEMES
          Rectangle {
            required property string modelData
            width: Style.space(56)
            height: Style.space(36)
            radius: Style.space(4)
            color: "transparent"
            border.width: (row.desk ? row.desk.scheme : "single") === modelData ? Math.max(2, Style.space(2)) : 0
            border.color: row.panel.fg
            Local.Scheme {
              anchors.fill: parent
              anchors.margins: Style.space(4)
              scheme: parent.modelData
              labels: Model.geometry(parent.modelData).map(function() { return " " })
              foreground: row.panel.fg
            }
            MouseArea {
              id: pick
              anchors.fill: parent
              hoverEnabled: true
              onClicked: row.panel.setScheme(parent.modelData)
            }
            PanelToolTip { visible: pick.containsMouse; text: row.panel.schemeNames[parent.modelData] }
          }
        }
      }
    }
    Component {
      id: placesControl
      // The chosen scheme, large: a place per cell; Enter/click — the app list below.
      Column {
        spacing: Style.spacing.xs
        function press() { picker.open() }
        Local.Scheme {
          width: parent.width
          height: Style.space(180)
          scheme: row.desk ? row.desk.scheme : "single"
          labels: row.panel.appNames(row.desk)
          subs: Model.geometry(scheme).map(function(g, i) { return row.panel.tr("place %1", i + 1) })
          emptyText: "+"
          cursor: row.hasCursor ? row.panel.place : -1
          interactive: true
          fontSize: Style.font.body
          foreground: row.panel.fg
          fontFamily: row.panel.font
          onPicked: function(i) { row.panel.cursor = row.index; row.panel.place = i; picker.open() }
        }
        SearchableDropdown {
          id: picker
          readonly property var slot: row.desk ? row.desk.slots[row.panel.place] || null : null
          width: parent.width
          showLabel: false
          options: [{ value: "", label: row.panel.tr("Empty") }].concat(row.panel.apps)
          value: slot ? slot.app || "" : ""
          triggerLabel: slot && !row.panel.apps.some(function(a) { return a.value === slot.app }) ? slot.class : ""
          placeholderText: row.panel.tr("Search…")
          emptyText: row.panel.tr("No matches")
          foreground: row.panel.fg
          fontFamily: row.panel.font
          onChanged: function(v) {
            row.panel.setPlace(row.panel.place, v)
            value = Qt.binding(function() { return picker.slot ? picker.slot.app || "" : "" })
          }
          onPopupOpenChanged: if (!popupOpen) Qt.callLater(function() { row.panel.focusKeys() })
        }
      }
    }
    Component {
      id: choiceControl
      ButtonGroup {
        options: row.panel.options(Model.CHOICES[row.modelData.key])
        value: row.panel.cfg[row.modelData.key]
        focusable: false
        foreground: row.panel.fg
        fontFamily: row.panel.font
        onChanged: function(v) { row.panel.setOption(row.modelData.key, v) }
      }
    }
    Component {
      id: switchControl
      ToggleSwitch {
        checked: row.panel.cfg[row.modelData.key]
        foreground: row.panel.fg
        onToggled: row.panel.change(row.index, 1)
      }
    }
    Component {
      id: ruleControl
      Row {
        spacing: Style.space(6)
        ButtonGroup {
          anchors.verticalCenter: parent.verticalCenter
          options: row.panel.options(Model.ACTIONS)
          value: row.panel.cfg.singleInstance[row.modelData.index].action
          focusable: false
          foreground: row.panel.fg
          fontFamily: row.panel.font
          onChanged: function(v) { row.panel.setRule(row.modelData.index, v) }
        }
        IconButton {
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰩺"
          tooltipText: row.panel.tr("Delete rule")
          onClicked: row.panel.removeRule(row.modelData.index)
        }
      }
    }
    Component {
      id: addRuleControl
      Field {
        function press() { forceActiveFocus() }
        width: Style.space(240)
        placeholderText: row.panel.tr("Window class, Enter to add")
        onAccepted: { row.panel.addRule(text); text = "" }
      }
    }
  }
}
