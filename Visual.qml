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
  property string painter: "bmp"       // "bmp" (Image from data URL) | "rects" (Canvas fillRect fallback)
  property var probe: null
  property var readback: null

  readonly property int bw: painter === "rects" ? Math.min(bufferWidth, 160) : bufferWidth
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

  Image {
    id: im
    visible: host.painter === "bmp"
    width: host.bw
    height: host.bh
    smooth: true
    mipmap: false
    cache: false
    asynchronous: false
    fillMode: Image.Stretch
    transform: Scale { xScale: host.width / Math.max(1, im.width); yScale: host.height / Math.max(1, im.height) }
    property bool ready: false
    onStatusChanged: if (status === Image.Error) { host.lastError = "Image decode failed — falling back to rects"; host.painter = "rects" }
  }
  function paintBmp() {
    host.paints++
    try {
      if (!im.ready || V.bufferSize()[0] !== host.bw || V.bufferSize()[1] !== host.bh) { V.useOwnBuffer(host.bw, host.bh); im.ready = true }
      V.frame(cv.t, 1 / host.fps)
      im.source = "data:image/bmp;base64," + Qt.btoa(V.toBmp())
      if ((host.paints & 31) === 0) host.probe = V.probe()
    } catch (e) { host.lastError = String(e); host.painter = "rects" }
  }

  Canvas {
    id: cv
    visible: host.painter !== "bmp"
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
        if (host.painter === "imagedata") {
          if (!img || img.width !== width || img.height !== height) { img = ctx.createImageData(width, height); V.setup(img) }
          V.frame(t, 1 / host.fps)
          ctx.putImageData(img, 0, 0)
        } else {
          if (!img || img.width !== width || img.height !== height) { V.useOwnBuffer(width, height); img = { width: width, height: height } }
          V.frame(t, 1 / host.fps)
          V.paintRects(ctx)
        }
        if ((host.paints & 31) === 0) { host.probe = V.probe(); var rb = ctx.getImageData(0, 0, 1, 1); host.readback = rb && rb.data ? [rb.data[0] | 0, rb.data[1] | 0, rb.data[2] | 0, rb.data[3] | 0] : null }
      } catch (e) { host.lastError = String(e) }
    }
  }

  Timer {
    interval: Math.round(1000 / host.fps)
    repeat: true
    running: host.running && host.visible && host.width > 0
    onTriggered: {
      var now = Date.now(); var dt = cv.lastMs ? Math.min(0.1, (now - cv.lastMs) / 1000) : 1 / host.fps; cv.lastMs = now
      cv.t += dt; host.ticks++
      if (host.painter === "bmp") host.paintBmp(); else cv.requestPaint()
    }
  }
  onPainterChanged: { cv.img = null; im.ready = false }
  onRunningChanged: if (!running) cv.lastMs = 0
  function diag() { return { w: Math.round(width), h: Math.round(height), bw: bw, bh: bh, running: running, visible: visible, ticks: ticks, paints: paints, ctxOk: ctxOk, err: lastError, avail: cv.available, painter: painter, bufferPixel: probe, canvasPixel: readback, imageStatus: im.status } }
}
