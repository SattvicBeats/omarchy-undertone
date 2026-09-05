import QtQuick
import "visual.js" as V

// One canvas, three models, same 160-px buffer the web instrument paints; the
// GPU scales it to whatever size this item is given (panel strip or a monitor).
Canvas {
  id: cv
  property real beat: 10
  property real base: 196
  property int model: 0            // 0 field · 1 lava · 2 flow
  property color colL: "#F2C063"
  property color colR: "#7FB7C9"
  property color colF: "#0D1322"
  property var breathLevel: null   // 0..1 or null
  property bool running: true
  property int fps: 30
  property int bufferWidth: 160

  readonly property int bw: bufferWidth
  readonly property int bh: Math.max(40, Math.round(bw * Math.max(1, height) / Math.max(1, width)))
  canvasSize: Qt.size(bw, bh)
  smooth: true
  renderStrategy: Canvas.Cooperative

  property var img: null
  property real t: 0
  property real lastMs: 0

  function ensure(ctx) {
    if (!img || img.width !== bw || img.height !== bh) { img = ctx.createImageData(bw, bh); V.setup(img) }
  }
  function pulse(a) { V.hit(a) }
  function resetVisual() { V.resetVis() }

  onColLChanged: V.setPalette(colL, colR, colF)
  onColRChanged: V.setPalette(colL, colR, colF)
  onColFChanged: V.setPalette(colL, colR, colF)
  onBeatChanged: V.setState(beat, base, model)
  onBaseChanged: V.setState(beat, base, model)
  onModelChanged: { V.setState(beat, base, model); V.resetVis() }
  onBreathLevelChanged: V.setBreath(breathLevel)
  onBhChanged: img = null
  Component.onCompleted: { V.setPalette(colL, colR, colF); V.setState(beat, base, model) }

  Timer {
    interval: Math.round(1000 / cv.fps)
    repeat: true
    running: cv.running && cv.visible && cv.width > 0
    onTriggered: {
      var now = Date.now(); var dt = cv.lastMs ? Math.min(0.1, (now - cv.lastMs) / 1000) : 1 / cv.fps; cv.lastMs = now
      cv.t += dt; cv.requestPaint()
    }
  }
  onRunningChanged: if (!running) lastMs = 0

  onPaint: {
    var ctx = getContext("2d")
    ensure(ctx)
    V.frame(t, 1 / fps)
    ctx.putImageData(img, 0, 0)
  }
}
