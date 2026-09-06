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
  property string painter: "bmp"       // JS path for Flow / fallback: "bmp" (Image from data URL) | "rects" (Canvas fillRect)
  property bool gpu: true              // field + lava as fragment shaders at native resolution
  readonly property bool useGpu: gpu && model !== 2
  property real shaderTime: 0
  // live analysis from the engine (Service pushes these ~23x/s)
  property real energy: 0
  property real lo: 0
  property real mid: 0
  property real hi: 0
  property real beatPhase: 0
  property bool audioOn: false
  function setAudio(a) { energy = a[0]; lo = a[1]; mid = a[2]; hi = a[3]; beatPhase = a[4]; audioOn = a[5] === 1; V.setAudio(a[0], a[1], a[2], a[3], a[4], a[5]) }
  property var probe: null
  property var readback: null

  readonly property int bw: useGpu ? 160 : (painter === "rects" ? Math.min(bufferWidth, 160) : bufferWidth)
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

  ShaderEffect {
    id: fieldFx
    anchors.fill: parent
    visible: host.useGpu && host.model === 0
    property real time: host.shaderTime
    property real beat: host.beat
    property real base: host.base
    property real aspect: width / Math.max(1, height)
    property real energy: host.energy
    property real beatPhase: host.beatPhase
    property real lo: host.lo
    property real hi: host.hi
    property color colL: host.colL
    property color colR: host.colR
    property color colF: host.colF
    fragmentShader: Qt.resolvedUrl("shaders/field.frag.qsb")
    onStatusChanged: if (status === ShaderEffect.Error) { host.lastError = "field shader: " + log; host.gpu = false }
  }
  ShaderEffect {
    id: lavaFx
    anchors.fill: parent
    visible: host.useGpu && host.model === 1
    property real thr: 1.0 - (host.breathLevel === null || host.breathLevel === undefined ? 0 : Number(host.breathLevel) * 0.25)
    property real aspect: width / Math.max(1, height)
    property real energy: host.energy
    property real hi: host.hi
    property color colL: host.colL
    property color colR: host.colR
    property color colF: host.colF
    property vector4d b0: Qt.vector4d(0, 0, 0, 0); property vector4d b1: Qt.vector4d(0, 0, 0, 0); property vector4d b2: Qt.vector4d(0, 0, 0, 0)
    property vector4d b3: Qt.vector4d(0, 0, 0, 0); property vector4d b4: Qt.vector4d(0, 0, 0, 0); property vector4d b5: Qt.vector4d(0, 0, 0, 0)
    property vector4d b6: Qt.vector4d(0, 0, 0, 0); property vector4d b7: Qt.vector4d(0, 0, 0, 0); property vector4d b8: Qt.vector4d(0, 0, 0, 0)
    property vector4d b9: Qt.vector4d(0, 0, 0, 0)
    fragmentShader: Qt.resolvedUrl("shaders/lava.frag.qsb")
    onStatusChanged: if (status === ShaderEffect.Error) { host.lastError = "lava shader: " + log; host.gpu = false }
    function setBlobs(bl) {
      var q = [b0, b1, b2, b3, b4, b5, b6, b7, b8, b9]
      for (var i = 0; i < 10 && i < bl.length; i++) {
        var b = bl[i], vv = Qt.vector4d(b.x, b.y, b.r, b.T)
        if (i === 0) b0 = vv; else if (i === 1) b1 = vv; else if (i === 2) b2 = vv; else if (i === 3) b3 = vv; else if (i === 4) b4 = vv
        else if (i === 5) b5 = vv; else if (i === 6) b6 = vv; else if (i === 7) b7 = vv; else if (i === 8) b8 = vv; else b9 = vv
      }
    }
  }
  function gpuFrame(dt) {
    host.paints++
    if (V.bufferSize()[0] !== host.bw || V.bufferSize()[1] !== host.bh) V.useOwnBuffer(host.bw, host.bh)
    if (host.model === 0) { V.tickFlash(dt); host.shaderTime += dt }
    else lavaFx.setBlobs(V.stepLavaOnly(dt))
  }

  Image {
    id: im
    visible: !host.useGpu && host.painter === "bmp"
    anchors.fill: parent
    smooth: true
    mipmap: false
    cache: false
    asynchronous: false
    fillMode: Image.Stretch
    property bool ready: false
    onStatusChanged: if (status === Image.Error) { host.lastError = "Image decode failed — falling back to rects"; host.painter = "rects" }
  }
  function paintBmp() {
    host.paints++
    try {
      if (!im.ready || V.bufferSize()[0] !== host.bw || V.bufferSize()[1] !== host.bh) { V.useOwnBuffer(host.bw, host.bh); im.ready = true }
      V.frame(cv.t, 1 / host.fps)
      im.source = "data:image/bmp;base64," + V.toBmpBase64()
      if ((host.paints & 31) === 0) host.probe = V.probe()
    } catch (e) { host.lastError = String(e); host.painter = "rects" }
  }

  Canvas {
    id: cv
    visible: !host.useGpu && host.painter !== "bmp"
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
      if (host.useGpu) host.gpuFrame(dt); else if (host.painter === "bmp") host.paintBmp(); else cv.requestPaint()
    }
  }
  onPainterChanged: { cv.img = null; im.ready = false }
  onRunningChanged: if (!running) cv.lastMs = 0
  function diag() { return { w: Math.round(width), h: Math.round(height), bw: bw, bh: bh, running: running, visible: visible, ticks: ticks, paints: paints, ctxOk: ctxOk, err: lastError, avail: cv.available, painter: painter, bufferPixel: probe, canvasPixel: readback, imageStatus: im.status, gpu: useGpu, fieldShader: fieldFx.status, lavaShader: lavaFx.status } }
}
