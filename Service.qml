import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
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
  property var tables: ({ scenes: [], rhythms: [], breaths: [], noises: [], nature: [], bands: [] })
  FileView {
    path: root.pluginDir + "engine/data.json"
    onLoaded: { try { root.tables = JSON.parse(text()) } catch (e) { console.warn("groundcontrol: data.json", e) } }
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
  property string om: "off"
  property real omlvl: 0.5
  readonly property bool windowOpen: win.visible
  property int visModel: 4               // 0 field · 1 lava · 2 flow · 3 spectrum · 4 cymatics
  property var saverDiag: null
  property string painter: "bmp"
  property string palette: "Station"     // a name from tables.palettes, or "Omarchy" to follow the theme
  readonly property var pal: {
    if (palette === "Omarchy") return { L: Color.accent, R: Color.urgent, F: Color.background, I: Color.foreground }
    var ps = tables && tables.palettes ? tables.palettes : []
    for (var i = 0; i < ps.length; i++) if (ps[i].name === palette) return ps[i]
    return { L: "#F2C063", R: "#7FB7C9", F: "#0D1322", I: "#E8E4D9" }
  }
  property int screensaverAfter: 0       // manual idle seconds; 0 = off (used when systemSaver is false)
  property bool systemSaver: false       // true: Undertone IS the screensaver — fires on Omarchy's own idle timing
  readonly property int omarchySaverSeconds: {
    var v = shell && shell.shellConfig && shell.shellConfig.idle ? shell.shellConfig.idle.screensaver : undefined
    var n = Number(v); return (isFinite(n) && n > 0) ? Math.round(n) : 150
  }
  readonly property int idleSeconds: systemSaver ? omarchySaverSeconds : screensaverAfter
  readonly property string stateFile: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/undertone.json"
  readonly property string toggleFlag: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/toggles/screensaver-off"
  readonly property bool saverOpen: saverLoader.active
  signal hit(real amp)
  property var audio: [0, 0, 0, 0, 0, 0, 0]
  property var spectrum: []
  property var plateMsg: null           // the solved plate (eigenmode LUT + n list), arrives once from the engine
  property var modeAmps: []
  property var wave: [[], [], []]
  property var clips: []
  property string clipDir: ""

  function applyStatus(s) {
    if ("plate" in s) { root.plateMsg = s.plate; return }
    if ("a" in s) { if ("s" in s) root.spectrum = s.s; if ("p" in s) root.modeAmps = s.p; if ("w" in s) root.wave = [s.w, s.x, s.y]; root.audio = s.a; return }
    if ("hit" in s) { root.hit(Number(s.hit) || 0); return }
    if ("clips" in s) root.clips = s.clips || []
    if ("clipDir" in s) root.clipDir = String(s.clipDir)
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
    if ("om" in s) root.om = String(s.om)
    if ("omlvl" in s) root.omlvl = Number(s.omlvl)
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
  // sliders send while dragging, throttled to ~20/s; the engine glides between values
  property var pendingSet: null
  Timer { id: setThrottle; interval: 50; repeat: false; onTriggered: { if (root.pendingSet) { var o = root.pendingSet; root.pendingSet = null; root.set(o) } } }
  function setLive(o) {
    if (setThrottle.running) { root.pendingSet = Object.assign(root.pendingSet || {}, o); return }
    root.set(o); setThrottle.start()
  }
  // log-scale base: slider position 0..1 <-> 40..800 Hz (each octave gets equal travel)
  readonly property real baseLo: 40
  readonly property real baseHi: 800
  function posToHz(p) { return baseLo * Math.pow(baseHi / baseLo, Math.max(0, Math.min(1, p))) }
  function hzToPos(f) { return Math.log(Math.max(baseLo, Math.min(baseHi, f)) / baseLo) / Math.log(baseHi / baseLo) }
  function setScene(name) { send({ cmd: "scene", name: String(name) }) }
  // Black Dawn mode: just the two ear tones — the beat is the whole sound
  function purePair() { root.set({ drone: 0, noise: "Off", nlvl: 0, nature: [], rhythm: "Silent", om: "off" }) }
  function rescanClips() { send({ cmd: "clips" }) }
  function setClip(name, o) { o.cmd = "clip"; o.name = name; send(o) }
  function addClip(path) { send({ cmd: "clip", add: String(path) }) }
  function retrySetup() { root.setupNeeded = false; root.setupMessage = ""; engine.running = true }

  function toggleWindow() { if (win.visible) hideWindow(); else showWindow() }
  function showWindow() { win.visible = true }
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
    function set(param: string, value: string): void { var o = {}; var k = String(param); var v = Number(value); o[k] = (k === "rhythm" || k === "noise" || k === "breath" || k === "om") ? String(value) : (isFinite(v) ? v : value); root.set(o) }
    function pure(): void { root.purePair() }
    function screensaver(): void { root.openSaver() }
    function painter(mode: string): void { root.painter = String(mode) }
    function palette(name: string): void { root.palette = String(name) }
    function diag(): string { return JSON.stringify({ version: "0.6.1", panel: panelVisual.diag(), saverOpen: root.saverOpen, saver: root.saverDiag, tables: !!(root.tables && root.tables.scenes && root.tables.scenes.length) }) }
    function clip(path: string): void { root.addClip(path) }
    function clips(): string { return JSON.stringify(root.clips) }
    function modes(): string {
      // the plate's current excitation: top 5 modes by amplitude — run it twice with different bases
      if (!root.plateMsg || !root.modeAmps.length) return JSON.stringify({ plate: !!root.plateMsg, note: "no plate/amps yet (engine solves the plate ~6 s after start; amps stream while playing)" })
      var idx = []; for (var i = 0; i < root.modeAmps.length; i++) idx.push(i)
      idx.sort(function(a, b) { return root.modeAmps[b] - root.modeAmps[a] })
      var out = []; for (var k = 0; k < 5 && k < idx.length; k++) { var i2 = idx[k]; out.push({ n: root.plateMsg.n[i2], f: root.plateMsg.f[i2], amp: root.modeAmps[i2] }) }
      return JSON.stringify({ modes: root.plateMsg.count, earTones: [root.audio[4], root.audio[5]], top: out })
    }
    function systemsaver(on: string): void { root.setSystemSaver(String(on) === "on" || String(on) === "true" || String(on) === "1") }
    function visual(model: string): void { var k = String(model).toLowerCase(); if (k === "field") root.visModel = 0; else if (k === "lava") root.visModel = 1; else if (k === "flow") root.visModel = 2; else if (k === "spectrum") root.visModel = 3; else if (k === "cymatics") root.visModel = 4; else if (k === "mandala") root.visModel = 5; else if (k === "lissajous") root.visModel = 6; else if (k === "scope") root.visModel = 7; else if (k === "tunnel") root.visModel = 8 }
    function status(): string {
      return JSON.stringify({ playing: root.playing, timerLeft: root.timerLeft, beat: root.beat, base: root.base, scene: root.scene, rhythm: root.rhythm })
    }
  }

  // ---- breath pacer clock (visual only; audio is untouched by it)
  readonly property var breathPhases: {
    var bl = tables && tables.breaths ? tables.breaths : []
    for (var i = 0; i < bl.length; i++) if (bl[i].name === breath) return bl[i].phases
    return null
  }
  property real breathT: 0
  Timer { interval: 50; repeat: true; running: (win.visible || root.saverOpen) && root.playing && root.breathPhases !== null; onTriggered: root.breathT += 0.05 }
  // 0..1 ring size: rises on inhale, holds, falls on exhale, holds
  readonly property real breathLevel: {
    var p = breathPhases; if (!p) return 0.5
    var total = p[0] + p[1] + p[2] + p[3]; var t = breathT % total
    if (t < p[0]) return t / p[0]
    t -= p[0]; if (t < p[1]) return 1
    t -= p[1]; if (t < p[2]) return 1 - t / p[2]
    return 0
  }
  readonly property real breathSecondsLeft: {
    var p = breathPhases; if (!p) return 0
    var total = p[0] + p[1] + p[2] + p[3]; var t = breathT % total
    if (t < p[0]) return p[0] - t; t -= p[0]; if (t < p[1]) return p[1] - t; t -= p[1]; if (t < p[2]) return p[2] - t; t -= p[2]; return p[3] - t
  }
  readonly property string breathWord: {
    var p = breathPhases; if (!p) return ""
    var total = p[0] + p[1] + p[2] + p[3]; var t = breathT % total
    if (t < p[0]) return "in"; t -= p[0]; if (t < p[1]) return "hold"; t -= p[1]; if (t < p[2]) return "out"; return "hold"
  }

  // ---- screensaver: the same visual, fullscreen on every monitor, closed by any input
  function openSaver() { saverLoader.active = true }
  function closeSaver() { saverLoader.active = false }

  IdleMonitor {
    enabled: root.idleSeconds > 0
    timeout: root.idleSeconds
    respectInhibitors: true
    onIsIdleChanged: if (isIdle && root.idleSeconds > 0) root.openSaver()
  }

  // ---- persistence + the Omarchy screensaver-off flag
  FileView {
    id: stateView
    path: root.stateFile
    onLoaded: {
      try {
        var o = JSON.parse(text())
        if ("visModel" in o) root.visModel = o.visModel | 0
        if ("screensaverAfter" in o) root.screensaverAfter = o.screensaverAfter | 0
        if ("systemSaver" in o) root.systemSaver = o.systemSaver === true
        if ("palette" in o) root.palette = String(o.palette)
      } catch (e) {}
      root.stateLoaded = true
    }
    onLoadFailed: root.stateLoaded = true
  }
  property bool stateLoaded: false
  Process { id: stateWriter }
  function saveState() {
    if (!stateLoaded) return
    var j = JSON.stringify({ visModel: visModel, screensaverAfter: screensaverAfter, systemSaver: systemSaver, palette: palette })
    stateWriter.command = ["bash", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s\n' \"$2\" > \"$1\"", "_", stateFile, j]
    stateWriter.running = true
  }
  Process { id: flagWriter }
  function setSystemSaver(on) {
    root.systemSaver = on
    // on: create the flag so Omarchy's ASCII saver stays quiet; off: remove it so Omarchy's comes back
    flagWriter.command = on ? ["bash", "-c", "mkdir -p \"$(dirname \"$1\")\" && touch \"$1\"", "_", toggleFlag]
                            : ["rm", "-f", toggleFlag]
    flagWriter.running = true
  }
  onVisModelChanged: saveState()
  onScreensaverAfterChanged: saveState()
  onSystemSaverChanged: saveState()
  onPaletteChanged: saveState()

  Loader {
    id: saverLoader
    active: false
    sourceComponent: Variants {
      model: Quickshell.screens
      delegate: PanelWindow {
        required property var modelData
        screen: modelData
        anchors { top: true; bottom: true; left: true; right: true }
        color: root.pal.F
        WlrLayershell.namespace: "undertone-screensaver"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore

        Visual {
          id: saverVisual
          painter: root.painter
          anchors.fill: parent
          model: root.visModel
          beat: root.beat; base: root.base
          colL: root.pal.L; colR: root.pal.R; colF: root.pal.F
          breathLevel: root.breathPhases ? root.breathLevel : null
            Connections { target: root; function onAudioChanged() { saverVisual.setAudio(root.audio, root.spectrum); saverVisual.setModeAmps(root.modeAmps); saverVisual.setWave(root.wave[0], root.wave[1], root.wave[2]) } function onPlateMsgChanged() { if (root.plateMsg) saverVisual.setPlate(root.plateMsg) } }
            Component.onCompleted: if (root.plateMsg) setPlate(root.plateMsg)
          bufferWidth: 320
          fps: 30
        }
        Connections { target: root; function onHit(amp) { saverVisual.pulse(amp) } }
        BreathFlower { visible: root.breathPhases !== null && root.playing; anchors.centerIn: parent; width: Math.min(parent.width, parent.height) * 0.42; height: width
                       level: root.breathLevel; word: root.breathWord; secondsLeft: root.breathSecondsLeft; petal: root.pal.R; petal2: root.pal.L; ink: root.pal.I || Color.foreground }
        Timer { interval: 500; repeat: true; running: true; onTriggered: root.saverDiag = saverVisual.diag() }

        // the 640-ms grace stops the click/keypress that opened it from closing it
        Timer { id: armed; interval: 640; running: true }
        Item { anchors.fill: parent; focus: true; Keys.onPressed: function(e) { if (!armed.running) root.closeSaver(); e.accepted = true } }
        MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.BlankCursor
          onPositionChanged: if (!armed.running) root.closeSaver()
          onPressed: if (!armed.running) root.closeSaver() }
      }
    }
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

        // visual
        Rectangle {
          Layout.fillWidth: true
          implicitHeight: Math.round(width * 0.42)
          radius: Style.cornerRadius; color: root.pal.F; clip: true
          Visual {
            id: panelVisual
            bufferWidth: 240
            painter: root.painter
            anchors.fill: parent
            model: root.visModel
            beat: root.beat; base: root.base
            colL: root.pal.L; colR: root.pal.R; colF: root.pal.F
            breathLevel: root.breathPhases ? root.breathLevel : null
            Connections { target: root; function onAudioChanged() { panelVisual.setAudio(root.audio, root.spectrum); panelVisual.setModeAmps(root.modeAmps); panelVisual.setWave(root.wave[0], root.wave[1], root.wave[2]) } function onPlateMsgChanged() { if (root.plateMsg) panelVisual.setPlate(root.plateMsg) } }
          Component.onCompleted: if (root.plateMsg) setPlate(root.plateMsg)
            running: win.visible && !root.saverOpen
          }
          Connections { target: root; function onHit(amp) { panelVisual.pulse(amp) } }
          BreathFlower { visible: root.breathPhases !== null; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Style.space(8); width: parent.height * 0.5; height: width; compact: true
                         level: root.breathLevel; word: root.breathWord; secondsLeft: root.breathSecondsLeft; petal: root.pal.R; petal2: root.pal.L; ink: root.pal.I || Color.foreground }
        }
        RowLayout {
          Layout.fillWidth: true; spacing: Style.space(6)
          Repeater {
            model: ["Field", "Lava", "Flow", "Spectrum", "Cymatics", "Mandala", "Lissajous", "Scope", "Tunnel"]
            delegate: Button { required property var modelData; required property int index; text: modelData; selected: root.visModel === index; onClicked: root.visModel = index }
          }
          Item { Layout.fillWidth: true }
          Button { text: "Screensaver"; tooltipText: "Fullscreen on every monitor; any key or mouse movement closes it"; onClicked: root.openSaver() }
        }
        Flow {
          Layout.fillWidth: true; spacing: Style.space(6)
          Repeater {
            model: [{ name: "Omarchy", L: Color.accent, R: Color.urgent, F: Color.background }].concat(root.tables && root.tables.palettes ? root.tables.palettes : [])
            delegate: Rectangle {
              required property var modelData
              width: sw.implicitWidth + Style.space(22); height: Style.font.body + Style.space(14); radius: height / 2
              color: modelData.F; border.width: root.palette === modelData.name ? 2 : 1
              border.color: root.palette === modelData.name ? Color.foreground : Qt.rgba(1, 1, 1, 0.18)
              Row {
                anchors.centerIn: parent; spacing: Style.space(6)
                Rectangle { width: 10; height: 10; radius: 5; color: modelData.L; anchors.verticalCenter: parent.verticalCenter }
                Rectangle { width: 10; height: 10; radius: 5; color: modelData.R; anchors.verticalCenter: parent.verticalCenter }
                Text { id: sw; text: modelData.name; color: Qt.lighter(modelData.L, 1.2); font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
              }
              MouseArea { anchors.fill: parent; onClicked: root.palette = modelData.name }
            }
          }
        }
        RowLayout {
          Layout.fillWidth: true; spacing: Style.space(8)
          Button {
            text: root.systemSaver ? "System screensaver: Undertone" : "System screensaver: Omarchy ASCII"
            selected: root.systemSaver
            tooltipText: "On: Undertone takes over at Omarchy's idle time (" + root.omarchySaverSeconds + " s, from Style > Idle) and the ASCII saver is switched off. Off: restores Omarchy's."
            onClicked: root.setSystemSaver(!root.systemSaver)
          }
          Text { visible: !root.systemSaver; text: "or own timer →"; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
          Repeater {
            model: root.systemSaver ? [] : [0, 120, 300, 600]
            delegate: Button { required property var modelData; text: modelData === 0 ? "Off" : (modelData / 60) + " min"; selected: root.screensaverAfter === modelData; onClicked: root.screensaverAfter = modelData }
          }
          Text { visible: root.systemSaver; text: "fires after " + root.omarchySaverSeconds + " s idle · lock unchanged"; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
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
            model: root.tables.scenes
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
        PanelSectionHeader { text: "Tones" }
        RowLayout {
          Layout.fillWidth: true; spacing: Style.space(8)
          Repeater {
            model: [ { l: "Left ear", v: root.base.toFixed(2), hi: false }, { l: "Right ear", v: (root.base + root.beat).toFixed(2), hi: false }, { l: "The beat", v: root.beat.toFixed(2), hi: true } ]
            delegate: Rectangle {
              required property var modelData
              Layout.fillWidth: true; implicitHeight: Style.space(58); radius: Style.cornerRadius
              color: Qt.darker(Color.background, 0.9); border.width: 1; border.color: modelData.hi ? Color.accent : Qt.rgba(1, 1, 1, 0.1)
              Column {
                anchors.centerIn: parent; spacing: 2
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.l.toUpperCase(); color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; font.letterSpacing: 1.5 }
                Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: 4
                  Text { text: modelData.v; color: modelData.hi ? Color.accent : Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body * 1.6 }
                  Text { text: "Hz"; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; anchors.baseline: parent.children[0].baseline } }
              }
            }
          }
          Button { text: "Pure pair"; tooltipText: "Only the two ear tones (drone, noise, places, pattern off) — the beat becomes the whole sound, like Black Dawn"; selected: root.drone === 0 && root.noise === "Off" && root.nature.length === 0 && root.rhythm === "Silent"; onClicked: root.purePair() }
        }
        Flow {
          Layout.fillWidth: true; spacing: Style.space(6)
          Repeater {
            model: root.tables.bands
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
          PanelSlider { id: beatSlider; Layout.fillWidth: true; minimum: 0.5; maximum: 50; step: 0.01; value: root.beat
            onMoved: function(v) { root.beat = v; root.setLive({ beat: Math.round(v * 100) / 100 }) }
            onReleased: function(v) { root.set({ beat: Math.round(v * 100) / 100 }) }
            // wheel: ±0.1 Hz; with Shift ±1 Hz
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; onWheel: function(w) { var d = (w.angleDelta.y > 0 ? 1 : -1) * (w.modifiers & Qt.ShiftModifier ? 1 : 0.1); var nb = Math.max(0.5, Math.min(50, Math.round((root.beat + d) * 100) / 100)); root.set({ beat: nb }); w.accepted = true } } }
        }
        RowLayout {
          Layout.fillWidth: true; spacing: Style.space(10)
          Text { text: "Base"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; Layout.preferredWidth: 60 }
          PanelSlider { id: baseSlider; Layout.fillWidth: true; minimum: 0; maximum: 1; step: 0.001; value: root.hzToPos(root.base); tickCount: 5
            onMoved: function(p) { var hz = Math.round(root.posToHz(p) * 10) / 10; root.base = hz; root.setLive({ base: hz }) }
            onReleased: function(p) { root.set({ base: Math.round(root.posToHz(p) * 10) / 10 }) }
            // wheel: ±1 Hz; with Shift ±10 Hz
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; onWheel: function(w) { var d = (w.angleDelta.y > 0 ? 1 : -1) * (w.modifiers & Qt.ShiftModifier ? 10 : 1); var nb = Math.max(40, Math.min(800, Math.round((root.base + d) * 10) / 10)); root.set({ base: nb }); w.accepted = true } } }
        }
        RowLayout {
          Layout.fillWidth: true; spacing: Style.space(10)
          Text { text: "Volume"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; Layout.preferredWidth: 60 }
          PanelSlider { Layout.fillWidth: true; minimum: 0; maximum: 1; step: 0.01; value: root.vol; onMoved: function(v) { root.setLive({ vol: v }) }; onReleased: function(v) { root.set({ vol: v }) } }
        }
        RowLayout {
          Layout.fillWidth: true; spacing: Style.space(10)
          Text { text: "Tanpura"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; Layout.preferredWidth: 60 }
          PanelSlider { Layout.fillWidth: true; minimum: 0; maximum: 1; step: 0.01; value: root.drone; onMoved: function(v) { root.setLive({ drone: v }) }; onReleased: function(v) { root.set({ drone: v }) } }
        }

        // rhythm
        PanelSectionHeader { text: "Pattern" }
        Flow {
          Layout.fillWidth: true; spacing: Style.space(6)
          Repeater {
            model: root.tables.rhythms
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
          BreathFlower { Layout.preferredWidth: 120; Layout.preferredHeight: 120; level: root.breathPhases ? root.breathLevel : 0.15; word: root.breathWord; secondsLeft: root.breathSecondsLeft; petal: root.pal.R; petal2: root.pal.L; ink: Color.foreground }
          Flow {
            Layout.fillWidth: true; spacing: Style.space(6)
            Repeater {
              model: root.tables.breaths
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

        // Om
        PanelSectionHeader { text: "Om" }
        RowLayout {
          Layout.fillWidth: true; spacing: Style.space(8)
          Repeater {
            model: ["off", "male", "female"]
            delegate: Button { required property var modelData; text: modelData === "off" ? "Off" : modelData.charAt(0).toUpperCase() + modelData.slice(1); selected: root.om === modelData; onClicked: root.set({ om: modelData }) }
          }
          Text { text: "level"; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
          PanelSlider { Layout.preferredWidth: 160; minimum: 0; maximum: 1; step: 0.01; value: root.omlvl; onMoved: function(v) { root.setLive({ omlvl: v }) }; onReleased: function(v) { root.set({ omlvl: v }) } }
          Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: "A synthesised voice on the same Sa as the drone: o → m over eight seconds, then a breath."; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
        }

        // noise + places
        PanelSectionHeader { text: "Noise" }
        RowLayout {
          Layout.fillWidth: true; spacing: Style.space(10)
          Flow {
            Layout.fillWidth: true; spacing: Style.space(6)
            Repeater {
              model: root.tables.noises
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
            model: root.tables.nature
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

        // clips
        PanelSectionHeader { text: "Clips" }
        Text {
          Layout.fillWidth: true; wrapMode: Text.Wrap
          text: "Drop audio files in " + root.clipDir + " (WAV plays natively; other formats need ffmpeg). They mix into the same bus, so they drive the visuals too."
          color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
        }
        Repeater {
          model: root.clips
          delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true; spacing: Style.space(8)
            Button { text: modelData.on ? "▮▮ " + modelData.name : "▶ " + modelData.name; selected: modelData.on; tooltipText: modelData.err ? modelData.err : (modelData.seconds ? modelData.seconds + " s" : "");
                     onClicked: root.setClip(modelData.name, { on: !modelData.on }) }
            Text { visible: !!modelData.err; text: modelData.err || ""; color: Color.urgent; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; Layout.fillWidth: true; elide: Text.ElideRight }
            Item { visible: !modelData.err; Layout.fillWidth: true }
            PanelSlider { Layout.preferredWidth: 140; minimum: 0; maximum: 1.5; step: 0.05; value: modelData.gain; onReleased: function(v) { root.setClip(modelData.name, { gain: v }) } }
            Button { text: modelData.loop ? "loop" : "once"; selected: modelData.loop; onClicked: root.setClip(modelData.name, { loop: !modelData.loop }) }
          }
        }
        RowLayout {
          spacing: Style.space(8)
          Button { text: "Rescan folder"; onClicked: root.rescanClips() }
          Button { text: "Open folder"; onClicked: Qt.openUrlExternally("file://" + root.clipDir) }
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
          Button { text: "Open Ground Control on the web"; onClicked: Qt.openUrlExternally(root.webUrl) }
        }
      }
    }
  }
}
