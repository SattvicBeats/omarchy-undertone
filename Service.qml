import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Undertone (native). Owns the audio engine process (engine/gc_engine.py →
// PipeWire via pw-cat), mirrors its status for the bar widget, exposes an IPC
// target, and hosts the control panel in a floating window. Nothing here
// touches the network or a browser; the web instrument is only linked.
Item {
  id: root
  visible: false

  property var shell: null
  property var manifest: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || ""

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace("file://", "")
  readonly property string enginePath: pluginDir + "engine/gc_engine.py"
  readonly property string webUrl: "https://groundcontrol.sworn.legal/"

  // ---- data tables shared with the engine (engine/data.json)
  property var data: ({ scenes: [], rhythms: [], breaths: [], noises: [], nature: [], bands: [] })
  FileView {
    path: root.pluginDir + "engine/data.json"
    onLoaded: { try { root.data = JSON.parse(text()) } catch (e) { console.warn("groundcontrol: data.json", e) } }
  }

  // ---- mirrored engine state
  property bool ready: false
  property bool setupNeeded: false
  property string setupMessage: ""
  property bool playing: false
  property int timerLeft: 0
  property real beat: 10
  property real base: 196
  property real vol: 0.35
  property real drone: 0.5
  property real nlvl: 0.4
  property real timer: 0
  property string scene: ""
  property string rhythm: "Silent"
  property string breath: "No pacer"
  property string noise: "Off"
  property var nature: []
  readonly property bool windowOpen: win.visible

  function applyStatus(s) {
    if (s.error) { console.warn("groundcontrol engine:", s.error); root.setupMessage = String(s.error); root.setupNeeded = true; return }
    if (s.ready === true) { root.ready = true; root.setupNeeded = false }
    if ("on" in s) root.playing = s.on === true
    if ("timerLeft" in s) root.timerLeft = Number(s.timerLeft) || 0
    if ("beat" in s) root.beat = Number(s.beat)
    if ("base" in s) root.base = Number(s.base)
    if ("vol" in s) root.vol = Number(s.vol)
    if ("drone" in s) root.drone = Number(s.drone)
    if ("nlvl" in s) root.nlvl = Number(s.nlvl)
    if ("timer" in s) root.timer = Number(s.timer)
    if ("scene" in s) root.scene = s.scene ? String(s.scene) : ""
    if ("rhythm" in s) root.rhythm = String(s.rhythm)
    if ("breath" in s) root.breath = String(s.breath)
    if ("noise" in s) root.noise = String(s.noise)
    if ("nature" in s) root.nature = s.nature || []
  }

  // ---- engine process
  Process {
    id: engine
    command: ["python3", root.enginePath]
    running: true
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) {
        try { root.applyStatus(JSON.parse(String(line))) } catch (e) {}
      }
    }
    stderr: SplitParser {
      onRead: function(line) {
        var t = String(line)
        if (t.indexOf("No module named") !== -1 || t.indexOf("ModuleNotFoundError") !== -1) {
          root.setupNeeded = true
          root.setupMessage = "python-numpy is missing.  Run:  omarchy-pkg-add python-numpy"
        }
      }
    }
    onExited: function(code) {
      root.ready = false; root.playing = false
      if (code !== 0 && !root.setupNeeded) { root.setupNeeded = true; root.setupMessage = "engine exited (" + code + ") — check python3 / pw-cat" }
      restart.restart()
    }
  }
  Timer { id: restart; interval: 3000; onTriggered: if (!root.setupNeeded) engine.running = true }

  function send(o) {
    if (!engine.running) engine.running = true
    engine.write(JSON.stringify(o) + "\n")
  }
  function play() { send({ cmd: "play" }) }
  function stop() { send({ cmd: "stop" }) }
  function togglePlay() { send({ cmd: "toggle" }) }
  function set(o) { o.cmd = "set"; send(o) }
  function setScene(name) { send({ cmd: "scene", name: String(name) }) }
  function retrySetup() { root.setupNeeded = false; root.setupMessage = ""; engine.running = true }

  function toggleWindow() { if (win.visible) hideWindow(); else showWindow() }
  function showWindow() { win.visible = true; win.requestActivate() }
  function hideWindow() { win.visible = false }

  // CLI / hotkey:  omarchy-shell undertone toggle
  IpcHandler {
    target: "undertone"
    function toggle(): void { root.toggleWindow() }
    function show(): void { root.showWindow() }
    function hide(): void { root.hideWindow() }
    function play(): void { root.play() }
    function stop(): void { root.stop() }
    function playpause(): void { root.togglePlay() }
    function scene(name: string): void { root.setScene(name) }
    function status(): string {
      return JSON.stringify({ playing: root.playing, timerLeft: root.timerLeft, beat: root.beat, base: root.base, scene: root.scene, rhythm: root.rhythm })
    }
  }

  // ---- breath pacer clock (visual only; audio is untouched by it)
  readonly property var breathPhases: {
    for (var i = 0; i < data.breaths.length; i++) if (data.breaths[i].name === breath) return data.breaths[i].phases
    return null
  }
  property real breathT: 0
  Timer { interval: 50; repeat: true; running: win.visible && root.playing && root.breathPhases !== null; onTriggered: root.breathT += 0.05 }
  // 0..1 ring size: rises on inhale, holds, falls on exhale, holds
  readonly property real breathLevel: {
    var p = breathPhases; if (!p) return 0.5
    var total = p[0] + p[1] + p[2] + p[3]; var t = breathT % total
    if (t < p[0]) return t / p[0]
    t -= p[0]; if (t < p[1]) return 1
    t -= p[1]; if (t < p[2]) return 1 - t / p[2]
    return 0
  }
  readonly property string breathWord: {
    var p = breathPhases; if (!p) return ""
    var total = p[0] + p[1] + p[2] + p[3]; var t = breathT % total
    if (t < p[0]) return "in"; t -= p[0]; if (t < p[1]) return "hold"; t -= p[1]; if (t < p[2]) return "out"; return "hold"
  }

  // ---- control panel
  FloatingWindow {
    id: win
    title: "Undertone"
    visible: false
    color: Color.background
    implicitWidth: 760
    implicitHeight: 720
    minimumSize: Qt.size(560, 480)

    Flickable {
      anchors.fill: parent
      anchors.margins: Style.space(18)
      contentWidth: width
      contentHeight: col.implicitHeight
      clip: true

      ColumnLayout {
        id: col
        width: parent.width
        spacing: Style.space(12)

        // header
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(10)
          Text { text: "Undertone"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body * 1.6; font.bold: true }
          Item { Layout.fillWidth: true }
          Text {
            visible: root.playing && root.timerLeft > 0
            text: Math.floor(root.timerLeft / 60) + ":" + (root.timerLeft % 60 < 10 ? "0" : "") + (root.timerLeft % 60)
            color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.body
          }
          Button { text: root.playing ? "Pause" : "Play"; selected: root.playing; onClicked: root.togglePlay() }
        }

        // setup card
        Rectangle {
          visible: root.setupNeeded
          Layout.fillWidth: true
          implicitHeight: setupCol.implicitHeight + Style.space(24)
          radius: Style.cornerRadius; color: Qt.darker(Color.background, 0.9); border.color: Color.urgent; border.width: 1
          ColumnLayout {
            id: setupCol; anchors.fill: parent; anchors.margins: Style.space(12); spacing: Style.space(8)
            Text { text: "Engine needs setup"; color: Color.urgent; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true }
            Text { text: root.setupMessage; wrapMode: Text.Wrap; Layout.fillWidth: true; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body }
            RowLayout {
              Button { text: "Install python-numpy"; onClicked: Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", "omarchy-pkg-add python-numpy"]) }
              Button { text: "Retry"; onClicked: root.retrySetup() }
            }
          }
        }

        Text {
          Layout.fillWidth: true; wrapMode: Text.Wrap
          text: "Headphones for the beat: the left ear gets the base tone, the right ear the base plus the beat. Nothing here is medical advice."
          color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
        }

        // scenes
        PanelSectionHeader { text: "Scenes" }
        Flow {
          Layout.fillWidth: true; spacing: Style.space(6)
          Repeater {
            model: root.data.scenes
            delegate: Button {
              required property var modelData
              text: modelData.name + "  ·  " + modelData.evidence
              selected: root.scene === modelData.name
              tooltipText: modelData.desc
              onClicked: root.setScene(modelData.name)
            }
          }
        }

        // tones
        PanelSectionHeader { text: "Beat  " + root.beat.toFixed(2) + " Hz     Base  " + Math.round(root.base) + " Hz" }
        Flow {
          Layout.fillWidth: true; spacing: Style.space(6)
          Repeater {
            model: root.data.bands
            delegate: Button {
              required property var modelData
              text: modelData.name + " " + modelData.beat
              selected: Math.abs(root.beat - modelData.beat) < 0.01
              tooltipText: modelData.desc
              onClicked: root.set({ beat: modelData.beat })
            }
          }
        }
        RowLayout {
          Layout.fillWidth: true; spacing: Style.space(10)
          Text { text: "Beat"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; Layout.preferredWidth: 60 }
          PanelSlider { Layout.fillWidth: true; minimum: 0.5; maximum: 47; step: 0.01; value: root.beat; onReleased: function(v) { root.set({ beat: Math.round(v * 100) / 100 }) } }
        }
        RowLayout {
          Layout.fillWidth: true; spacing: Style.space(10)
          Text { text: "Base"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; Layout.preferredWidth: 60 }
          PanelSlider { Layout.fillWidth: true; minimum: 60; maximum: 440; step: 1; integer: true; value: root.base; onReleased: function(v) { root.set({ base: Math.round(v) }) } }
        }
        RowLayout {
          Layout.fillWidth: true; spacing: Style.space(10)
          Text { text: "Volume"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; Layout.preferredWidth: 60 }
          PanelSlider { Layout.fillWidth: true; minimum: 0; maximum: 1; step: 0.01; value: root.vol; onReleased: function(v) { root.set({ vol: v }) } }
        }
        RowLayout {
          Layout.fillWidth: true; spacing: Style.space(10)
          Text { text: "Tanpura"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; Layout.preferredWidth: 60 }
          PanelSlider { Layout.fillWidth: true; minimum: 0; maximum: 1; step: 0.01; value: root.drone; onReleased: function(v) { root.set({ drone: v }) } }
        }

        // rhythm
        PanelSectionHeader { text: "Pattern" }
        Flow {
          Layout.fillWidth: true; spacing: Style.space(6)
          Repeater {
            model: root.data.rhythms
            delegate: Button {
              required property var modelData
              text: modelData.name
              selected: root.rhythm === modelData.name
              tooltipText: modelData.desc
              onClicked: root.set({ rhythm: modelData.name })
            }
          }
        }

        // breath
        PanelSectionHeader { text: "Breath pacer" }
        RowLayout {
          Layout.fillWidth: true; spacing: Style.space(12)
          Item {
            Layout.preferredWidth: 72; Layout.preferredHeight: 72
            Rectangle {
              anchors.centerIn: parent
              width: 24 + 44 * root.breathLevel; height: width; radius: width / 2
              color: "transparent"; border.width: 2; border.color: root.breathPhases ? Color.accent : Color.muted
              Behavior on width { NumberAnimation { duration: 60 } }
            }
            Text { anchors.centerIn: parent; text: root.breathWord; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
          }
          Flow {
            Layout.fillWidth: true; spacing: Style.space(6)
            Repeater {
              model: root.data.breaths
              delegate: Button {
                required property var modelData
                text: modelData.name
                selected: root.breath === modelData.name
                tooltipText: modelData.desc
                onClicked: { root.set({ breath: modelData.name }); root.breathT = 0 }
              }
            }
          }
        }

        // noise + places
        PanelSectionHeader { text: "Noise" }
        RowLayout {
          Layout.fillWidth: true; spacing: Style.space(10)
          Flow {
            Layout.fillWidth: true; spacing: Style.space(6)
            Repeater {
              model: root.data.noises
              delegate: Button {
                required property var modelData
                text: modelData
                selected: root.noise === modelData
                onClicked: root.set({ noise: modelData })
              }
            }
          }
          PanelSlider { Layout.preferredWidth: 160; minimum: 0; maximum: 1; step: 0.01; value: root.nlvl; onReleased: function(v) { root.set({ nlvl: v }) } }
        }
        PanelSectionHeader { text: "Places" }
        Flow {
          Layout.fillWidth: true; spacing: Style.space(6)
          Repeater {
            model: root.data.nature
            delegate: Button {
              required property var modelData
              text: modelData
              selected: root.nature.indexOf(modelData) !== -1
              onClicked: {
                var n = root.nature.slice(); var i = n.indexOf(modelData)
                if (i === -1) n.push(modelData); else n.splice(i, 1)
                root.set({ nature: n })
              }
            }
          }
        }

        // sleep timer
        PanelSectionHeader { text: "Sleep timer" }
        Flow {
          Layout.fillWidth: true; spacing: Style.space(6)
          Repeater {
            model: [0, 15, 20, 30, 45, 60, 90]
            delegate: Button {
              required property var modelData
              text: modelData === 0 ? "Off" : modelData + " min"
              selected: Math.round(root.timer) === modelData
              onClicked: root.set({ timer: modelData })
            }
          }
        }
        Text {
          Layout.fillWidth: true; wrapMode: Text.Wrap
          text: "Fades out over the last minute, then stops."
          color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
        }

        PanelSeparator { Layout.fillWidth: true }
        RowLayout {
          Layout.fillWidth: true
          Text {
            Layout.fillWidth: true; wrapMode: Text.Wrap
            text: "The full instrument — interference-field visuals, Lava and Flow, saved mixes, share links, Tune to a place, MIDI Listen — lives in the browser."
            color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
          }
          Button { text: "Open Ground Control on the web"; onClicked: Quickshell.execDetached(["omarchy-launch-browser", root.webUrl]) }
        }
      }
    }
  }
}
