import QtQuick
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// The session switch confirmation page of the Workspaces modal (Panel.qml is `panel`):
// the windows to close, the phase, Cancel / Close and switch.
Column {
  id: confirmPage
  property var panel: null
  spacing: Style.spacing.xs
  readonly property var plan: confirmPage.panel.service ? confirmPage.panel.service.pendingPlan : null
  readonly property string phase: confirmPage.panel.service ? confirmPage.panel.service.phase : ""
  // The first window of the plan still open (toplevels for the binding).
  readonly property string closingNow: {
    if (phase !== "closing" || !plan) return ""
    void Hyprland.toplevels.values
    var up = confirmPage.panel.service.windowsNow().map(function(w) { return w.address })
    var left = plan.close.filter(function(w) { return up.indexOf(w.address) >= 0 })
    return left.length ? left[0].title || left[0].address : "…"
  }

  Repeater {
    model: confirmPage.plan ? confirmPage.plan.close : []
    Text {
      required property var modelData
      width: confirmPage.width
      text: "• " + (modelData.title || modelData.address)
      color: confirmPage.panel.fg
      font.family: confirmPage.panel.font
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }
  }
  Text {
    visible: text !== ""
    text: confirmPage.phase === "udisks" ? confirmPage.panel.tr("Waiting for the flash drive…")
        : confirmPage.phase === "closing" ? confirmPage.panel.tr("Closing: %1", confirmPage.closingNow)
        : confirmPage.phase === "launching" ? confirmPage.panel.tr("Launching…") : ""
    color: confirmPage.panel.dim
    font.family: confirmPage.panel.font
    font.pixelSize: Style.font.body
  }
  Item { width: 1; height: Style.space(8) }
  Row {
    anchors.right: parent.right
    spacing: Style.space(10)
    Button {
      visible: confirmPage.phase !== "launching"
      bordered: true
      text: confirmPage.panel.tr("Cancel")
      foreground: confirmPage.panel.fg
      fontFamily: confirmPage.panel.font
      onClicked: confirmPage.panel.service.cancelSwitch()
    }
    Button {
      visible: confirmPage.plan !== null && confirmPage.phase === ""
      bordered: true
      hasCursor: true
      text: confirmPage.panel.tr("Close and switch")
      foreground: confirmPage.panel.fg
      fontFamily: confirmPage.panel.font
      onClicked: confirmPage.panel.service.confirmSwitch()
    }
  }
}
