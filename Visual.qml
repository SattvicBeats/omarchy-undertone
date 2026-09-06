import QtQuick
import "visual.js" as V

// One buffer, three models, same 160-px resolution the web instrument paints.
// The Canvas is exactly buffer-sized; a Scale transform stretches it to fill
// this item, so the GPU does the upscaling (linear-filtered, like the web).
Item {
  id: host
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
  property int paints: 0
  property int ticks: 0
  property string lastError: ""
  property bool ctxOk: false

  readonly property int bw: bufferWidth
  readonly property int bh: Math.max(40, Math.round(bw * Math.max(1, height) / Math.max(1, width)))

  function pulse(a) { V.hit(a) }
  function resetVisual() { V.resetVis() }

  onColLChanged: V.setPalette(colL, colR, colF)
  onColRChanged: V.setPalette(colL, colR, colF)
  onColFChanged: V.setPalette(colL, colR, colF)
  onBeatChanged: V.setState(beat, base, model)
  onBaseChanged: V.setState(beat, base, model)
  onModelChanged: { V.setState(beat, base, model); V.resetVis() }
  onBreathLevelChanged: V.setBreath(breathLevel)
  Component.onCompleted: { V.setPalette(colL, colR, colF); V.setState(beat, base, model) }

  Canvas {
    id: cv
    width: host.bw
    height: host.bh
    smooth: true
    antialiasing: false
    transform: Scale { xScale: host.width / Math.max(1, cv.width); yScale: host.height / Math.max(1, cv.height) }

    property var img: null
    property real t: 0
    property real lastMs: 0

    onWidthChanged: img = null
    onHeightChanged: img = null

    onPaint: {
      host.paints++
      try {
        var ctx = getContext("2d")
        host.ctxOk = !!ctx
        if (!img || img.width !== width || img.height !== height) { img = ctx.createImageData(width, height); V.setup(img) }
        V.frame(t, 1 / host.fps)
        ctx.putImageData(img, 0, 0)
      } catch (e) { host.lastError = String(e) }
    }
  }

  Timer {
    interval: Math.round(1000 / host.fps)
    repeat: true
    running: host.running && host.visible && host.width > 0
    onTriggered: {
      var now = Date.now(); var dt = cv.lastMs ? Math.min(0.1, (now - cv.lastMs) / 1000) : 1 / host.fps; cv.lastMs = now
      cv.t += dt; host.ticks++; cv.requestPaint()
    }
  }
  onRunningChanged: if (!running) cv.lastMs = 0
  function diag() { return { w: Math.round(width), h: Math.round(height), bw: bw, bh: bh, running: running, visible: visible, ticks: ticks, paints: paints, ctxOk: ctxOk, err: lastError, avail: cv.available } }
}
