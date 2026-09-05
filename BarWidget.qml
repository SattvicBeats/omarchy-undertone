import QtQuick
import Quickshell
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "bharat.undertone"

  readonly property var svc: bar?.shell?.serviceFor("bharat.undertone")
  readonly property bool playing: svc ? svc.playing : false
  readonly property int timerLeft: svc ? svc.timerLeft : 0
  readonly property bool showLabel: setting("showLabel", true)

  function fmtLeft(s) {
    if (s <= 0) return ""
    var m = Math.floor(s / 60), r = s % 60
    return m + ":" + (r < 10 ? "0" : "") + r
  }
  readonly property string label: {
    if (!svc || !svc.ready) return svc && svc.setupNeeded ? "setup" : ""
    var parts = []
    if (playing && svc.beat > 0) parts.push(svc.beat + " Hz")
    if (playing && timerLeft > 0) parts.push(fmtLeft(timerLeft))
    if (!playing && svc.scene) parts.push(svc.scene)
    return parts.join(" · ")
  }

  implicitWidth: row.implicitWidth + Style.space(14)
  implicitHeight: barSize

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)
    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: root.playing ? "󰓃" : "󰝚"
      color: root.playing ? root.bar.barForeground : Qt.darker(root.bar.barForeground, 1.5)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
    }
    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      visible: root.showLabel && !root.vertical && root.label !== ""
      text: root.label
      color: root.bar.barForeground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    onClicked: function(mouse) {
      if (!root.svc) return
      if (mouse.button === Qt.MiddleButton) root.svc.togglePlay()
      else if (mouse.button === Qt.RightButton) root.svc.stop()
      else root.svc.toggleWindow()
    }
  }
}
