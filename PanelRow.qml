import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One row of the Workspaces modal (Panel.qml): the label and, on the right, the
// control for the row's type (Model.rows). `panel` is the modal: state and edits.
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
  readonly property var desk: row.panel.desks[String(modelData.ws)] || null
  visible: modelData.type !== "head"
  implicitHeight: Math.max(Style.space(42), control.implicitHeight + Style.spacing.xs * 2, labels.implicitHeight + Style.spacing.xs * 2)
  foreground: row.panel.fg
  hasCursor: row.panel.cursor === index

  Connections {
    target: root
    function onPressRow(i) { if (i === row.index && control.item && control.item.press) control.item.press() }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    onPositionChanged: function(mouse) { if (row.panel.gate.moved(area, mouse)) row.panel.cursor = row.index }
    onClicked: { row.panel.cursor = row.index; if (row.modelData.type === "desk") row.panel.activate(row.index) }
  }

  Column {
    id: labels
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.rowPaddingX + (["name", "scheme", "place"].indexOf(row.modelData.type) >= 0 ? Style.space(24) : 0)
    anchors.right: control.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    Text {
      width: parent.width
      text: row.panel.labelOf(row.modelData)
      color: row.panel.fg
      font.family: row.panel.font
      font.pixelSize: Style.font.body
      font.bold: row.modelData.type === "desk"
      elide: Text.ElideRight
    }
    Text {
      visible: row.modelData.type === "schedule" && row.panel.scheduleError !== ""
      width: parent.width
      text: row.panel.scheduleError
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
    anchors.verticalCenter: parent.verticalCenter
    sourceComponent: ({ set: setControl, schedule: scheduleControl, desk: deskControl, name: nameControl, scheme: schemeControl,
                        place: placeControl, choice: choiceControl, switch: switchControl, rule: ruleControl, addRule: addRuleControl })[row.modelData.type] || null

    Component {
      id: setControl
      Row {
        spacing: Style.space(6)
        function press() { if (row.panel.adding) nameField.forceActiveFocus(); else setDropdown.open() }
        Dropdown {
          id: setDropdown
          visible: !row.panel.adding
          width: Style.space(200)
          showLabel: false
          options: row.panel.sets.map(function(n) { return { value: n, label: n || row.panel.tr("Regular") } })
          value: row.panel.set
          foreground: row.panel.fg
          fontFamily: row.panel.font
          onChanged: function(v) { row.panel.set = v }
          onPopupOpenChanged: if (!popupOpen) Qt.callLater(function() { row.panel.focusKeys() })
        }
        Field {
          id: nameField
          visible: row.panel.adding
          width: Style.space(200)
          placeholderText: row.panel.tr("Session name")
          onVisibleChanged: if (visible) forceActiveFocus()
          onAccepted: { row.panel.addSession(text); text = "" }
        }
        IconButton {
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰐕"
          tooltipText: row.panel.tr("New session")
          onClicked: row.panel.adding = !row.panel.adding
        }
        IconButton {
          anchors.verticalCenter: parent.verticalCenter
          visible: row.panel.set !== "" && !row.panel.adding
          iconText: "󰩺"
          tooltipText: row.panel.tr("Delete session")
          onClicked: row.panel.askDelete()
        }
      }
    }
    Component {
      id: scheduleControl
      Row {
        spacing: Style.space(4)
        function press() { fromField.forceActiveFocus() }
        Repeater {
          model: row.panel.days
          Button {
            required property string modelData
            required property int index
            anchors.verticalCenter: parent.verticalCenter
            text: modelData
            selected: row.panel.draft.days.indexOf(index + 1) >= 0
            horizontalPadding: Style.space(5)
            foreground: row.panel.fg
            fontFamily: row.panel.font
            onClicked: row.panel.toggleDay(index + 1)
          }
        }
        Field {
          id: fromField
          width: Style.space(64)
          placeholderText: row.panel.tr("from")
          text: row.panel.draft.from
          maximumLength: 5
          onEditingFinished: if (text.trim() !== row.panel.draft.from) row.panel.setTime("from", text)
        }
        Field {
          width: Style.space(64)
          placeholderText: row.panel.tr("to")
          text: row.panel.draft.to
          maximumLength: 5
          onEditingFinished: if (text.trim() !== row.panel.draft.to) row.panel.setTime("to", text)
        }
      }
    }
    Component {
      id: deskControl
      Text {
        width: Math.min(implicitWidth, row.width * 0.5)
        text: row.panel.deskApps(row.modelData.ws)
        color: row.panel.dim
        font.family: row.panel.font
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
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
          onEditingFinished: if (text !== (row.desk && row.desk.name.text || "")) row.panel.setNameText(row.modelData.ws, text)
        }
        ButtonGroup {
          anchors.verticalCenter: parent.verticalCenter
          options: row.panel.options(Model.NAME_MODES)
          value: row.desk ? row.desk.name.mode || "number" : "number"
          focusable: false
          foreground: row.panel.fg
          fontFamily: row.panel.font
          onChanged: function(v) { row.panel.setNameMode(row.modelData.ws, v) }
        }
      }
    }
    Component {
      id: schemeControl
      ButtonGroup {
        options: Model.SCHEMES.map(function(s) { return { value: s, label: row.panel.schemeGlyphs[s], tooltip: row.panel.schemeNames[s] } })
        value: row.desk ? row.desk.scheme : "single"
        focusable: false
        foreground: row.panel.fg
        fontFamily: row.panel.font
        onChanged: function(v) { row.panel.setScheme(row.modelData.ws, v) }
      }
    }
    Component {
      id: placeControl
      SearchableDropdown {
        readonly property var slot: row.desk ? row.desk.slots[row.modelData.slot] || null : null
        function press() { open() }
        width: Style.space(240)
        showLabel: false
        options: [{ value: "", label: row.panel.tr("Empty") }].concat(row.panel.apps)
        value: slot ? slot.app || "" : ""
        triggerLabel: slot && !row.panel.apps.some(function(a) { return a.value === slot.app }) ? slot.class : ""
        placeholderText: row.panel.tr("Search…")
        emptyText: row.panel.tr("No matches")
        foreground: row.panel.fg
        fontFamily: row.panel.font
        onChanged: function(v) { row.panel.setPlace(row.modelData.ws, row.modelData.slot, v) }
        onPopupOpenChanged: if (!popupOpen) Qt.callLater(function() { row.panel.focusKeys() })
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
