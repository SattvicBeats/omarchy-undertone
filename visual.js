// Undertone visuals — ported from Ground Control v9 (drawField / stepLava+drawLava / drawFlow).
// Pure JS over a small RGBA pixel buffer (160 x N); the host scales it up. No DOM, no QML types.
.pragma library

var FW = 160, FH = 80;
var img = null, d = null;             // {width,height,data} provided by host (Canvas ImageData)
var RGB = { L: [242, 192, 99], R: [127, 183, 201], bg2: [13, 19, 34] };
var S = { beat: 10, base: 196, vis: 0 };
var blobs = [], parts = null, perm = [], hitFlash = 0, breath = null;

function hex2rgb(h) { h = String(h).replace("#", ""); if (h.length === 8) h = h.slice(0, 6); var n = parseInt(h, 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; }
function setPalette(L, R, F) { RGB.L = hex2rgb(L); RGB.R = hex2rgb(R); RGB.bg2 = hex2rgb(F); }
function setState(beat, base, vis) { S.beat = +beat || 10; S.base = +base || 196; S.vis = vis | 0; }
function setBreath(level) { breath = (level === null || level === undefined) ? null : +level; }
function hit(a) { hitFlash = Math.max(hitFlash, +a || 0); }

function setup(imageData) {
  img = imageData; d = img.data; FW = img.width; FH = img.height;
  resetVis();
}
function resetVis() {
  blobs = [];
  for (var i = 0; i < 10; i++) blobs.push({ x: Math.random() * FW, y: FH * (0.3 + Math.random() * 0.7), vx: 0, vy: 0, r: FH * (0.09 + Math.random() * 0.07), T: Math.random() });
  parts = null;
  if (!perm.length) { for (var k = 0; k < 256; k++) perm[k] = k; for (var m = 255; m > 0; m--) { var j = Math.floor(Math.random() * (m + 1)), t = perm[m]; perm[m] = perm[j]; perm[j] = t; } perm = perm.concat(perm); }
}

function put(p, B, Lc, Rc, a, c, g) {
  d[p] = B[0] + a * (Lc[0] - B[0]) * g + c * (Rc[0] - B[0]) * g;
  d[p + 1] = B[1] + a * (Lc[1] - B[1]) * g + c * (Rc[1] - B[1]) * g;
  d[p + 2] = B[2] + a * (Lc[2] - B[2]) * g + c * (Rc[2] - B[2]) * g;
  d[p + 3] = 255;
}

// --- model 0: interference field ---
function drawField(t) {
  var drift = t * Math.min(2, Math.max(.3, S.beat / 10)), kL = 0.09 * Math.pow(S.base / 196, .35), kR = kL * (1 + S.beat / S.base * 40);
  var sx = FW * 0.32, sy = FH / 2, p = 0, B = RGB.bg2, Lc = RGB.L, Rc = RGB.R;
  for (var y = 0; y < FH; y++) for (var x = 0; x < FW; x++, p += 4) {
    var dx1 = x - sx, dx2 = x - (FW - sx), dy = y - sy, r1 = Math.sqrt(dx1 * dx1 + dy * dy), r2 = Math.sqrt(dx2 * dx2 + dy * dy);
    var v = (Math.cos(kL * r1 - drift) + Math.cos(kR * r2 + drift)) / 2;
    put(p, B, Lc, Rc, Math.max(0, v), Math.max(0, -v), 0.15 + 0.85 * Math.abs(v));
  }
}

// --- model 1: lava — metaballs with a thermal loop ---
function stepLava(dt) {
  var heat = 0.25 + 0.35 * Math.min(1, S.beat / 20), g = 9.0;
  blobs.forEach(function (b) {
    var depth = b.y / FH;
    b.T += dt * (depth > 0.85 ? heat : (depth < 0.15 ? -0.35 : -0.08)); b.T = Math.max(0, Math.min(1, b.T));
    var buoy = (b.T - 0.45) * g; b.vy += -buoy * dt; b.vy *= Math.pow(0.35, dt); b.vx *= Math.pow(0.25, dt);
    if (hitFlash > 0.3) b.vx += (Math.random() - 0.5) * 6 * hitFlash;
    b.x += b.vx * dt * 10; b.y += b.vy * dt * 10;
    if (b.y < b.r * 0.6) { b.y = b.r * 0.6; b.vy = Math.abs(b.vy) * 0.2; } if (b.y > FH - b.r * 0.6) { b.y = FH - b.r * 0.6; b.vy = -Math.abs(b.vy) * 0.2; }
    if (b.x < b.r) { b.x = b.r; b.vx = Math.abs(b.vx); } if (b.x > FW - b.r) { b.x = FW - b.r; b.vx = -Math.abs(b.vx); }
  });
  for (var i = 0; i < blobs.length; i++) for (var j = i + 1; j < blobs.length; j++) {
    var a = blobs[i], c = blobs[j], dx = c.x - a.x, dy = c.y - a.y, d2 = dx * dx + dy * dy, md = (a.r + c.r) * 0.8;
    if (d2 < md * md && d2 > 0.01) { var dd = Math.sqrt(d2), f = (md - dd) / md * 2 * dt; a.vx -= dx / dd * f; a.vy -= dy / dd * f; c.vx += dx / dd * f; c.vy += dy / dd * f; }
  }
}
function drawLava() {
  var p = 0, B = RGB.bg2, Lc = RGB.L, Rc = RGB.R, thr = 1.0 - (breath == null ? 0 : breath * 0.25);
  for (var y = 0; y < FH; y++) for (var x = 0; x < FW; x++, p += 4) {
    var f = 0, tw = 0;
    for (var i = 0; i < blobs.length; i++) { var b = blobs[i], dx = x - b.x, dy = y - b.y, q = b.r * b.r / (dx * dx + dy * dy + 0.5); f += q; tw += q * b.T; }
    var T = f > 0 ? tw / f : 0, inside = f > thr, edge = Math.max(0, Math.min(1, (f - thr * 0.75) / (thr * 0.25)));
    if (inside) put(p, B, Lc, Rc, T, 1 - T, 1); else put(p, B, Lc, Rc, T * edge, (1 - T) * edge, 0.55 * edge);
  }
}

// --- model 2: flow — curl noise advection ---
function vnoise(x, y, z) {
  var X = Math.floor(x), Y = Math.floor(y), Z = Math.floor(z), fx = x - X, fy = y - Y, fz = z - Z;
  var s = function (t) { return t * t * (3 - 2 * t) };
  var h = function (i, j, k) { return perm[(perm[(perm[(X + i) & 255] + Y + j) & 255] + Z + k) & 255] / 255 };
  var u = s(fx), v = s(fy), w = s(fz);
  var l = function (a, b, t) { return a + (b - a) * t };
  return l(l(l(h(0, 0, 0), h(1, 0, 0), u), l(h(0, 1, 0), h(1, 1, 0), u), v), l(l(h(0, 0, 1), h(1, 0, 1), u), l(h(0, 1, 1), h(1, 1, 1), u), v), w);
}
function drawFlow(t, dt) {
  if (!parts) { parts = []; for (var i = 0; i < 700; i++) parts.push({ x: Math.random() * FW, y: Math.random() * FH, c: Math.random() }); }
  var B = RGB.bg2;
  for (var p = 0; p < d.length; p += 4) { d[p] += (B[0] - d[p]) * 0.06; d[p + 1] += (B[1] - d[p + 1]) * 0.06; d[p + 2] += (B[2] - d[p + 2]) * 0.06; d[p + 3] = 255; }
  var sc = 0.045, tz = t * 0.12 * Math.min(2, Math.max(.4, S.beat / 10)), eps = 0.6, spd = (6 + S.beat * 0.4) * dt * 10 + hitFlash * 8;
  parts.forEach(function (q) {
    var n1 = vnoise(q.x * sc, (q.y + eps) * sc, tz), n2 = vnoise(q.x * sc, (q.y - eps) * sc, tz), n3 = vnoise((q.x + eps) * sc, q.y * sc, tz), n4 = vnoise((q.x - eps) * sc, q.y * sc, tz);
    var vx = (n1 - n2) / (2 * eps), vy = -(n3 - n4) / (2 * eps), m = Math.sqrt(vx * vx + vy * vy) + 1e-6; q.x += vx / m * spd; q.y += vy / m * spd;
    if (q.x < 0 || q.x >= FW || q.y < 0 || q.y >= FH) { q.x = Math.random() * FW; q.y = Math.random() * FH; }
    var i = (Math.floor(q.y) * FW + Math.floor(q.x)) * 4, C = q.c < 0.5 ? RGB.L : RGB.R; d[i] = C[0]; d[i + 1] = C[1]; d[i + 2] = C[2]; d[i + 3] = 255;
  });
}

// Rect painter: reads the buffer back and paints it with fillRect, so the pixels
// never depend on ImageData.data being a live view. Merges horizontal runs of
// identical colour (field/lava have long runs; flow is mostly background).
function paintRects(ctx) {
  var p = 0, y, x, x0, r, g, b, key, last;
  for (y = 0; y < FH; y++) {
    x0 = 0; last = -1;
    for (x = 0; x < FW; x++, p += 4) {
      r = (d[p] | 0) & 252; g = (d[p + 1] | 0) & 252; b = (d[p + 2] | 0) & 252; key = (r << 16) | (g << 8) | b;   // 6-bit: invisible, merges a little
      if (key !== last) {
        if (last >= 0) { ctx.fillStyle = "#" + ("000000" + last.toString(16)).slice(-6); ctx.fillRect(x0, y, x - x0, 1); }
        last = key; x0 = x;
      }
    }
    ctx.fillStyle = "#" + ("000000" + last.toString(16)).slice(-6); ctx.fillRect(x0, y, FW - x0, 1);
  }
}
// BMP painter: encode the buffer as a 24-bit bottom-up BMP (binary string) for a
// data: URL. Header is built once per size; rows are padded to 4 bytes.
var bmpHead = null, bmpW = 0, bmpH = 0, bmpPad = 0;
function bmpHeader(w, h) {
  var pad = (4 - (w * 3) % 4) % 4, rowBytes = w * 3 + pad, size = 54 + rowBytes * h;
  var b = [], u16 = function (v) { b.push(v & 255, (v >> 8) & 255) }, u32 = function (v) { b.push(v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >>> 24) & 255) };
  b.push(66, 77); u32(size); u16(0); u16(0); u32(54);
  u32(40); u32(w); u32(h); u16(1); u16(24); u32(0); u32(rowBytes * h); u32(2835); u32(2835); u32(0); u32(0);
  bmpHead = String.fromCharCode.apply(null, b); bmpW = w; bmpH = h; bmpPad = pad;
}
function toBmp() {
  if (bmpW !== FW || bmpH !== FH) bmpHeader(FW, FH);
  var rows = new Array(FH), padStr = bmpPad ? String.fromCharCode.apply(null, new Array(bmpPad).fill(0)) : "";
  for (var y = FH - 1; y >= 0; y--) {
    var p = y * FW * 4, line = new Array(FW * 3), k = 0;
    for (var x = 0; x < FW; x++, p += 4) { line[k++] = d[p + 2] & 255; line[k++] = d[p + 1] & 255; line[k++] = d[p] & 255; }
    rows[FH - 1 - y] = String.fromCharCode.apply(null, line) + padStr;
  }
  return bmpHead + rows.join("");
}
// Base64 straight from bytes. Qt.btoa UTF-8-encodes first, which mangles bytes >= 0x80.
var B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
var B64T = null;   // 4096-entry table: two bytes' worth of the top 12 bits → 2 chars
function b64init() { B64T = new Array(4096); for (var i = 0; i < 4096; i++) B64T[i] = B64[i >> 6] + B64[i & 63]; }
function bytesToB64(a) {
  if (!B64T) b64init();
  var out = new Array(Math.ceil(a.length / 3)), n = a.length - (a.length % 3), k = 0, i;
  for (i = 0; i < n; i += 3) { var v = (a[i] << 16) | (a[i + 1] << 8) | a[i + 2]; out[k++] = B64T[v >> 12] + B64T[v & 4095]; }
  if (a.length - n === 1) { var v1 = a[i] << 16; out[k++] = B64T[v1 >> 12] + "=="; }
  else if (a.length - n === 2) { var v2 = (a[i] << 16) | (a[i + 1] << 8); out[k++] = B64T[v2 >> 12] + B64[(v2 >> 6) & 63] + "="; }
  return out.join("");
}
var bmpBytes = null;
function toBmpBase64() {
  if (bmpW !== FW || bmpH !== FH) bmpHeader(FW, FH);
  var rowBytes = FW * 3 + bmpPad, total = 54 + rowBytes * FH;
  if (!bmpBytes || bmpBytes.length !== total) { bmpBytes = new Array(total); for (var z = 0; z < 54; z++) bmpBytes[z] = bmpHead.charCodeAt(z); for (var q = 54; q < total; q++) bmpBytes[q] = 0; }
  var o = 54;
  for (var y = FH - 1; y >= 0; y--) {
    var p = y * FW * 4;
    for (var x = 0; x < FW; x++, p += 4) { bmpBytes[o++] = d[p + 2] & 255; bmpBytes[o++] = d[p + 1] & 255; bmpBytes[o++] = d[p] & 255; }
    o += bmpPad;
  }
  return bytesToB64(bmpBytes);
}
function bufferSize() { return [FW, FH] }
function probe() { return d ? [d[0] | 0, d[1] | 0, d[2] | 0, d[3] | 0] : null }
function useOwnBuffer(w, h) { FW = w; FH = h; d = new Array(w * h * 4); for (var i = 0; i < d.length; i++) d[i] = 0; img = { width: w, height: h, data: d }; resetVis(); }

// Host calls frame(t, dt) then putImageData(img).
function frame(t, dt) {
  if (!img) return;
  hitFlash *= Math.pow(0.02, dt);
  if (S.vis === 1) { stepLava(dt); drawLava(); }
  else if (S.vis === 2) drawFlow(t, dt);
  else drawField(t);
}
