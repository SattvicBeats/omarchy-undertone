#!/usr/bin/env python3
"""Ground Control native engine — binaural pair, tanpura drone, taals, noise colours,
weather layers, sleep timer. numpy only; audio goes to PipeWire via pw-cat.

Control: JSON lines on stdin.   Status: JSON lines on stdout (1 Hz + after every change).
  {"cmd":"play"} {"cmd":"stop"} {"cmd":"toggle"} {"cmd":"status"} {"cmd":"quit"}
  {"cmd":"scene","name":"Rest"}
  {"cmd":"set","beat":7.83,"base":136,"vol":.35,"drone":.5,"rhythm":"Keherwa",
               "noise":"Pink","nlvl":.35,"nature":["Rain","Wind"],"timer":45,"breath":"Coherent"}
Test:  gc_engine.py --out mix.wav --seconds 6 --scene Flow
"""
import sys, os, json, time, math, threading, subprocess, argparse, wave, struct
import numpy as np
import base64
import plate as PLATE

SR = 48000
BLOCK = 1024
HERE = os.path.dirname(os.path.abspath(__file__))
DATA = json.load(open(os.path.join(HERE, "data.json")))
RHY = {r["name"]: r["pat"] for r in DATA["rhythms"]}
SCN = {s["name"]: s["set"] for s in DATA["scenes"]}

# ------------------------------------------------------------------ helpers
def leaky(x, a, y0):
    """y[n] = a*y[n-1] + x[n], vectorised for one block. Returns (y, last)."""
    # a^-k overflows for fast poles, so work in chunks short enough that a^-m < 1e100
    m = max(8, min(len(x), int(230 / -math.log(a))))
    y = np.empty(len(x))
    for i in range(0, len(x), m):
        xs = x[i:i + m]; k = np.arange(len(xs)); ak = a ** k
        ys = ak * (a * y0 + np.cumsum(xs / ak))   # a^k * (a*y0 + sum x[j] a^-j)
        y[i:i + m] = ys; y0 = float(ys[-1])
    return y, y0

def env_exp(n, tau):
    return np.exp(-np.arange(n) / (SR * tau))

def voice(kind):
    """Precomputed one-shot percussion voices (mono float32)."""
    rng = np.random.default_rng(7)
    if kind == "thump":              # heartbeat: 55 Hz sine, fast decay
        n = int(SR * .3); t = np.arange(n) / SR
        return (np.sin(2 * np.pi * 55 * t) * env_exp(n, .07)).astype(np.float32)
    if kind == "dha":                # bayan-ish: pitch sweep 160→85 Hz
        n = int(SR * .45); t = np.arange(n) / SR
        f = 85 + 75 * np.exp(-t / .06)
        ph = 2 * np.pi * np.cumsum(f) / SR
        return (np.sin(ph) * env_exp(n, .12) * .9).astype(np.float32)
    if kind == "tin":                # dayan ring: 620 Hz + 2nd partial, medium decay
        n = int(SR * .35); t = np.arange(n) / SR
        return ((np.sin(2 * np.pi * 620 * t) + .35 * np.sin(2 * np.pi * 1240 * t)) * env_exp(n, .09) * .5).astype(np.float32)
    if kind == "na":                 # short bright tap: filtered noise burst
        n = int(SR * .06)
        w = rng.standard_normal(n)
        hp, _ = leaky(w, .6, 0.0); hp = w - hp * .4
        return (hp * env_exp(n, .012) * .35).astype(np.float32)
    raise KeyError(kind)

VOICES = {k: voice(k) for k in ("thump", "dha", "tin", "na")}

CLIP_DIR = os.environ.get("UNDERTONE_CLIPS") or os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local", "share"), "undertone", "clips")
CLIP_EXT = (".wav", ".flac", ".mp3", ".ogg", ".opus", ".m4a", ".aiff", ".aif")

def load_clip(path):
    """Return float32 (n,2) at SR. WAV via stdlib; anything else via ffmpeg if present."""
    try:
        if path.lower().endswith(".wav"):
            with wave.open(path, "rb") as w:
                ch, sw, fr, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
                raw = w.readframes(n)
            if sw == 2: a = np.frombuffer(raw, "<i2").astype(np.float32) / 32768.0
            elif sw == 4: a = np.frombuffer(raw, "<i4").astype(np.float32) / 2147483648.0
            elif sw == 1: a = (np.frombuffer(raw, "u1").astype(np.float32) - 128) / 128.0
            else: return None, "unsupported wav sample width %d" % sw
            a = a.reshape(-1, ch)
        else:
            out = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"], capture_output=True)
            if out.returncode != 0: return None, "ffmpeg: " + out.stderr.decode(errors="ignore").strip()[:120]
            a = np.frombuffer(out.stdout, "<f4").reshape(-1, 2); fr = SR; ch = 2
        if ch == 1: a = np.repeat(a, 2, axis=1)
        elif ch > 2: a = a[:, :2]
        if fr != SR:
            n2 = int(len(a) * SR / fr); x = np.linspace(0, len(a) - 1, n2)
            a = np.stack([np.interp(x, np.arange(len(a)), a[:, 0]), np.interp(x, np.arange(len(a)), a[:, 1])], 1)
        return np.ascontiguousarray(a, dtype=np.float32), None
    except FileNotFoundError:
        return None, "ffmpeg not installed (needed for non-WAV)"
    except Exception as e:
        return None, str(e)[:120]

# ------------------------------------------------------------------ engine
class Engine:
    def __init__(self):
        self.S = dict(beat=10.0, base=196.0, vol=.35, drone=.5, rhythm="Silent", breath="No pacer",
                      noise="Off", nlvl=.4, nature=[], timer=0, scene=None)
        self.on = False
        self.t0 = 0            # absolute sample counter while on
        self.timer_end = 0     # absolute sample when timer stops
        self.ph = [0.0, 0.0]   # binaural phases
        self.plucks = []       # (start_sample, freq, amp)
        self.next_pluck = 0
        self.events = []       # (start_sample, voice_key, amp)
        self.step_i = 0
        self.next_step = 0
        self.nstate = {"p1": 0.0, "p2": 0.0, "p3": 0.0, "b": 0.0, "r": 0.0, "wmod": 0.0}
        self.rng = np.random.default_rng()
        self.master = 0.0      # smoothed master gain (0..1) for fades
        self.hits = []         # strong hits since last drain, for the visual pulse
        self.clips = {}        # name -> dict(data, pos, gain, loop, on, err)
        self.an = {"rms": 0.0, "lo": 0.0, "mid": 0.0, "hi": 0.0}   # smoothed analysis
        self.anst = {"lo": 0.0, "hi": 0.0}                            # filter state
        self.ring = np.zeros((8192, 2), np.float32)                   # last 171 ms of output for the FFT
        self.bands = np.zeros(32)                                      # smoothed log-spaced spectrum, 0..1
        self.peaks = [0.0, 0.0]                                        # measured strongest tone per ear, Hz
        self.win = np.hanning(8192).astype(np.float32)
        edges = np.geomspace(40, 16000, 33); self.bandIdx = np.searchsorted(np.fft.rfftfreq(8192, 1 / SR), edges)
        self.bandHz = np.sqrt(edges[:-1] * edges[1:])                 # band centres, for the plate response
        self.plate = None                                              # dict(modes, lut) once solved
        self.plate_msg = None                                          # the one-time message for the visual
        self.mode_amp = None                                           # smoothed per-mode response
        threading.Thread(target=self.solve_plate, daemon=True).start()
        self.lock = threading.Lock()

    # -------------------------------------------------- state changes
    def apply(self, d):
        with self.lock:
            for k in ("beat", "base", "vol", "drone", "nlvl", "timer"):
                if k in d and d[k] is not None: self.S[k] = float(d[k])
            for k in ("rhythm", "breath", "noise"):
                if k in d and d[k] in ({r["name"] for r in DATA["rhythms"]} | {b["name"] for b in DATA["breaths"]} | set(DATA["noises"])):
                    self.S[k] = d[k]
            if "nature" in d: self.S["nature"] = [n for n in (d["nature"] or []) if n in DATA["nature"]]
            if "scene" in d: self.S["scene"] = d["scene"]
            if "rhythm" in d: self.step_i = 0; self.next_step = self.t0
            if "timer" in d: self.arm_timer()

    def scene(self, name):
        st = SCN.get(name)
        if not st: return False
        d = {k: st.get(k) for k in ("beat", "base", "drone", "rhythm", "breath", "noise", "nlvl", "nature", "timer")}
        d["scene"] = name
        self.apply(d); return True

    def scan_clips(self):
        try: os.makedirs(CLIP_DIR, exist_ok=True)
        except Exception: pass
        names = sorted(f for f in os.listdir(CLIP_DIR) if f.lower().endswith(CLIP_EXT)) if os.path.isdir(CLIP_DIR) else []
        with self.lock:
            for n in names:
                if n not in self.clips: self.clips[n] = dict(data=None, pos=0, gain=0.6, loop=True, on=False, err=None, path=os.path.join(CLIP_DIR, n))
            for n in list(self.clips):
                if n not in names and not self.clips[n].get("external"): del self.clips[n]
        return names

    def add_clip(self, path):
        name = os.path.basename(path)
        with self.lock:
            self.clips[name] = dict(data=None, pos=0, gain=0.6, loop=True, on=False, err=None, path=path, external=True)
        return name

    def set_clip(self, name, d):
        with self.lock:
            c = self.clips.get(name)
            if not c: return False
            if "gain" in d: c["gain"] = max(0.0, min(2.0, float(d["gain"])))
            if "loop" in d: c["loop"] = bool(d["loop"])
            if "on" in d:
                c["on"] = bool(d["on"])
                if c["on"] and c["data"] is None and c["err"] is None:
                    data, err = load_clip(c["path"]); c["data"] = data; c["err"] = err; c["pos"] = 0
                    if err: c["on"] = False
            if d.get("restart"): c["pos"] = 0
        return True

    def clip_status(self):
        return [{"name": n, "on": c["on"], "gain": round(c["gain"], 2), "loop": c["loop"], "loaded": c["data"] is not None,
                 "seconds": round(len(c["data"]) / SR, 1) if c["data"] is not None else None, "err": c["err"]} for n, c in sorted(self.clips.items())]

    def arm_timer(self):
        self.timer_end = (self.t0 + int(self.S["timer"] * 60 * SR)) if (self.on and self.S["timer"] > 0) else 0

    def play(self):
        with self.lock:
            if self.on: return
            self.on = True; self.t0 = 0; self.plucks = []; self.events = []
            self.next_pluck = 0; self.step_i = 0; self.next_step = 0
            self.arm_timer()

    def stop(self):
        with self.lock: self.on = False; self.timer_end = 0

    def timer_left(self):
        return max(0, (self.timer_end - self.t0) / SR) if (self.on and self.timer_end) else 0

    def status(self):
        return {"on": self.on, "timerLeft": int(self.timer_left()), "beat": self.S["beat"], "base": self.S["base"],
                "scene": self.S["scene"], "rhythm": self.S["rhythm"], "breath": self.S["breath"],
                "noise": self.S["noise"], "nature": self.S["nature"], "drone": self.S["drone"],
                "vol": self.S["vol"], "nlvl": self.S["nlvl"], "timer": self.S["timer"], "clips": self.clip_status(), "clipDir": CLIP_DIR}

    # -------------------------------------------------- analysis (what the visuals listen to)
    def analyse(self, out):
        self.ring = np.roll(self.ring, -len(out), axis=0); self.ring[-len(out):] = out
        m = (out[:, 0] + out[:, 1]) * 0.5
        st = self.anst
        lo, st["lo"] = leaky(m * (1 - .985), .985, st["lo"])          # ~115 Hz one-pole
        hp, st["hi"] = leaky(m * (1 - .75), .75, st["hi"]); hi = m - hp  # ~2.2 kHz one-pole HP
        mid = m - lo - hi
        def e(x): return float(np.sqrt(np.mean(x * x)))
        a = self.an; k = .35                                             # smoothing across blocks
        for key, val in (("rms", e(m)), ("lo", e(lo)), ("mid", e(mid)), ("hi", e(hi))):
            a[key] += (val - a[key]) * (k if val > a[key] else k * .5)   # fast attack, slower release

    def solve_plate(self):
        """Free-edge circular plate eigenmodes (see plate.py). Cached on disk; ~3 s cold."""
        cache_dir = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
        cache = os.path.join(cache_dir, "undertone", "plate-v1.json")
        modes = None
        try:
            with open(cache) as fh: modes = json.load(fh)
        except Exception: pass
        if not modes:
            modes = PLATE.plate_table()
            try:
                os.makedirs(os.path.dirname(cache), exist_ok=True)
                with open(cache, "w") as fh: json.dump(modes, fh)
            except Exception: pass
        lut = PLATE.radial_lut(modes, 256)                             # (M, 256) in [-1, 1]
        # pack the LUT as an 8-bit BMP (rows = modes, x = radius) for the shader to sample
        M, N = lut.shape
        g = np.clip(np.round((lut + 1.0) * 127.5), 0, 255).astype(np.uint8)
        pad = (4 - (N * 3) % 4) % 4; rowb = N * 3 + pad
        hdr = b"BM" + (54 + rowb * M).to_bytes(4, "little") + b"\0\0\0\0" + (54).to_bytes(4, "little")
        hdr += (40).to_bytes(4, "little") + N.to_bytes(4, "little") + M.to_bytes(4, "little") + (1).to_bytes(2, "little") + (24).to_bytes(2, "little") + b"\0" * 4 + (rowb * M).to_bytes(4, "little") + b"\0" * 16
        body = b"".join(bytes(np.repeat(g[M - 1 - r], 3)) + b"\0" * pad for r in range(M))   # BMP rows bottom-up
        with self.lock:
            self.plate = dict(modes=modes, lut=lut)
            self.mode_amp = np.zeros(M)
            self.plate_msg = {"plate": {"count": M, "n": [m["n"] for m in modes], "f": [round(m["f"], 1) for m in modes],
                                        "lut": "data:image/bmp;base64," + base64.b64encode(hdr + body).decode("ascii")}}

    def spectrum(self):
        """FFT of the last 171 ms: 32 log bands (40 Hz-16 kHz) and the strongest tone in each ear."""
        r = self.ring
        for ch in (0, 1):
            X = np.abs(np.fft.rfft(r[:, ch] * self.win))
            if ch == 0: XL = X
            else: XR = X
            k = int(np.argmax(X[8:])) + 8                              # skip DC/sub-40 Hz
            if X[k] > 1.0 and 0 < k < len(X) - 1:                       # parabolic interpolation → sub-bin frequency
                a, b, c = np.log(X[k - 1] + 1e-9), np.log(X[k] + 1e-9), np.log(X[k + 1] + 1e-9)
                d = 0.5 * (a - c) / (a - 2 * b + c) if (a - 2 * b + c) != 0 else 0.0
                self.peaks[ch] = float((k + d) * SR / 8192)
            else:
                self.peaks[ch] = 0.0
        M = (XL + XR) * 0.5
        bands = np.array([M[self.bandIdx[i]:max(self.bandIdx[i] + 1, self.bandIdx[i + 1])].max() for i in range(32)])
        bands = np.clip((np.log10(bands + 1e-3) + 1.0) / 3.2, 0, 1)      # ~ -20 dB .. +44 dB window
        self.bands += (bands - self.bands) * np.where(bands > self.bands, .5, .18)
        if self.plate is not None:                                      # plate response to the measured spectrum
            amp = PLATE.response(self.plate["modes"], self.bandHz, self.bands ** 2)
            amp = amp / (amp.max() + 1e-9) * min(1.0, self.an["rms"] * 3.0)
            self.mode_amp += (amp - self.mode_amp) * np.where(amp > self.mode_amp, .45, .12)

    def analysis(self):
        a = self.an
        return {"a": [round(min(1.0, a["rms"] * 2.2), 3), round(min(1.0, a["lo"] * 4.0), 3), round(min(1.0, a["mid"] * 3.0), 3), round(min(1.0, a["hi"] * 6.0), 3),
                      round(self.peaks[0], 2), round(self.peaks[1], 2), 1 if self.on else 0],
                "s": [int(v * 100) for v in self.bands],
                "p": [int(v * 100) for v in self.mode_amp] if self.mode_amp is not None else []}

    # -------------------------------------------------- synthesis
    def block(self):
        """Return (BLOCK,2) float32. Called continuously; silent when off."""
        with self.lock:
            S = dict(self.S); on = self.on
        n = BLOCK
        out = np.zeros((n, 2), np.float32)
        target = 1.0 if on else 0.0
        if on and self.timer_end and self.t0 > self.timer_end - 60 * SR:
            target = max(0.0, (self.timer_end - self.t0) / (60 * SR))
            if self.t0 >= self.timer_end: self.stop(); target = 0.0
        if not on and self.master < 1e-4:
            return out
        t0 = self.t0
        t = np.arange(n) / SR

        # binaural pair: L = base, R = base + beat (hard L/R, as in the web app)
        fL, fR = S["base"], S["base"] + S["beat"]
        phL = self.ph[0] + 2 * np.pi * fL * t
        phR = self.ph[1] + 2 * np.pi * fR * t
        self.ph[0] = (phL[-1] + 2 * np.pi * fL / SR) % (2 * np.pi)
        self.ph[1] = (phR[-1] + 2 * np.pi * fR / SR) % (2 * np.pi)
        out[:, 0] += .28 * np.sin(phL); out[:, 1] += .28 * np.sin(phR)

        # tanpura: four strings (Pa, Sa', Sa', Sa) plucked in a 0.55 s cycle, additive with jawari-ish bright decay
        if S["drone"] > 0:
            sa = S["base"]
            strings = [sa * 1.5, sa * 2, sa * 2, sa]
            while self.next_pluck < t0 + n:
                i = (self.next_pluck // int(.55 * SR)) % 4
                self.plucks.append((self.next_pluck, strings[i], .16 * S["drone"]))
                self.next_pluck += int(.55 * SR)
            keep = []
            drone = np.zeros(n)
            for (st, f, a) in self.plucks:
                if st > t0 + n: keep.append((st, f, a)); continue
                tt = (np.arange(t0, t0 + n) - st) / SR
                m = tt >= 0
                if tt[-1] > 4.0: continue
                keep.append((st, f, a))
                tm = tt[m]
                sig = np.zeros(len(tm))
                for h in range(1, 9):
                    sig += (1.0 / h) * np.sin(2 * np.pi * f * h * tm) * np.exp(-tm * (0.9 + .35 * h))
                # jawari: a shimmering high band that decays more slowly than a plain string would
                sig += .12 * np.sin(2 * np.pi * f * 5.02 * tm) * np.exp(-tm * 1.2)
                drone[m] += a * sig * (1 - np.exp(-tm / .004))
            self.plucks = keep
            out[:, 0] += drone; out[:, 1] += drone

        # rhythm
        pat = RHY.get(S["rhythm"])
        if pat:
            step = 60.0 / pat["bpm"] * SR / (4 if not pat.get("matra") else 1)
            while self.next_step < t0 + n:
                for (si, vk, amp) in pat["hits"]:
                    if si == self.step_i:
                        self.events.append((self.next_step, vk, amp))
                        if amp >= .7 and vk in ("dha", "thump"): self.hits.append(amp)
                self.step_i = (self.step_i + 1) % pat["steps"]
                self.next_step += int(step)
            keep = []
            for (st, vk, amp) in self.events:
                v = VOICES[vk]
                a0 = st - t0
                if a0 >= n: keep.append((st, vk, amp)); continue
                b0 = max(0, -a0); b1 = min(len(v), n - a0)
                if b1 <= b0: continue
                seg = v[b0:b1] * amp * .8
                out[max(0, a0):max(0, a0) + len(seg), 0] += seg
                out[max(0, a0):max(0, a0) + len(seg), 1] += seg
                if b1 < len(v): keep.append((st, vk, amp))
            self.events = keep

        # noise colours (independent L/R for width)
        nz = None
        if S["noise"] != "Off" and S["nlvl"] > 0:
            w = self.rng.standard_normal((n, 2))
            if S["noise"] == "White": nz = w * .12
            else:
                st = self.nstate
                p1, st["p1"] = leaky(w[:, 0] * .0990460, .99765, st["p1"])
                p2, st["p2"] = leaky(w[:, 0] * .2965164, .96300, st["p2"])
                p3, st["p3"] = leaky(w[:, 0] * 1.0526913, .57000, st["p3"])
                pink = (p1 + p2 + p3 + w[:, 0] * .1848) * .09
                if S["noise"] == "Pink": nz = np.stack([pink, np.roll(pink, 97)], 1)
                elif S["noise"] == "Brown":
                    b, st["b"] = leaky(w[:, 0] * .02, .995, st["b"]); nz = np.stack([b, np.roll(b, 131)], 1) * 1.6
                else:  # Green: pink through a gentle mid band
                    g, st["r"] = leaky(pink, .90, st["r"]); nz = np.stack([g, np.roll(g, 61)], 1) * 1.4
            out += (nz * S["nlvl"]).astype(np.float32)

        # weather / places
        for name in S["nature"]:
            w = self.rng.standard_normal(n)
            if name == "Rain":
                hp, _ = leaky(w, .85, 0.0); r = w - hp * .85
                flutter = 1 + .25 * np.sin(2 * np.pi * .3 * (t0 + np.arange(n)) / SR)
                lay = r * flutter * .06
            elif name == "Wind":
                st = self.nstate
                b, st["wmod"] = leaky(w * .012, .997, st["wmod"])
                gust = .6 + .4 * np.sin(2 * np.pi * .07 * (t0 + np.arange(n)) / SR) ** 2
                lay = b * gust * 1.1
            elif name == "Surf":
                swell = (.5 + .5 * np.sin(2 * np.pi * (t0 + np.arange(n)) / SR / 9.0)) ** 2
                p, _ = leaky(w * .05, .985, 0.0); lay = p * swell * 1.2
            elif name == "Fire":
                b, _ = leaky(w * .03, .99, 0.0)
                crack = (self.rng.random(n) < .0008) * self.rng.standard_normal(n) * .6
                lay = b * .9 + crack * .5
            elif name == "Crickets":
                ch = (np.sin(2 * np.pi * 4300 * t) * (np.sin(2 * np.pi * 19 * (t0 + np.arange(n)) / SR) > .3))
                gate = (np.sin(2 * np.pi * .9 * (t0 + np.arange(n)) / SR) > -.2)
                lay = ch * gate * .05
            else: continue
            out[:, 0] += lay; out[:, 1] += lay * .92

        # user clips
        with self.lock: clips = [c for c in self.clips.values() if c["on"] and c["data"] is not None]
        for c in clips:
            data = c["data"]; L = len(data)
            if L == 0: continue
            pos = c["pos"]; got = 0
            while got < n:
                take = min(n - got, L - pos)
                out[got:got + take] += data[pos:pos + take] * c["gain"]
                got += take; pos += take
                if pos >= L:
                    if c["loop"]: pos = 0
                    else: c["on"] = False; pos = 0; break
            c["pos"] = pos

        # master gain with smooth fade (timer and start/stop) + volume
        g = self.master + (target - self.master) * (1 - np.exp(-np.arange(1, n + 1) / (SR * .08)))
        self.master = float(g[-1])
        out *= (g * S["vol"] * 2.0)[:, None]
        out = np.tanh(out * 1.15) * .95      # soft limiter
        self.analyse(out)
        self.t0 += n
        return out.astype(np.float32)

# ------------------------------------------------------------------ IO
def player_cmd():
    env = os.environ.get("GC_PLAYER")
    if env: return env.split()
    return ["pw-cat", "--playback", "--raw", "--rate=%d" % SR, "--channels=2", "--format=f32", "-"]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out"); ap.add_argument("--seconds", type=float, default=6)
    ap.add_argument("--scene"); ap.add_argument("--set")
    a = ap.parse_args()
    eng = Engine()
    if a.scene: eng.scene(a.scene)
    if a.set: eng.apply(json.loads(a.set))

    if a.out:  # offline render for tests
        eng.play()
        frames = []
        cpu0 = time.process_time()
        for _ in range(int(a.seconds * SR / BLOCK)): frames.append(eng.block())
        cpu = time.process_time() - cpu0
        pcm = np.concatenate(frames)
        with wave.open(a.out, "wb") as w:
            w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
            w.writeframes((pcm * 32767).astype("<i2").tobytes())
        eng.spectrum(); an = eng.analysis()["a"]
        print(json.dumps({"ok": True, "seconds": a.seconds, "cpu_seconds": round(cpu, 3), "analysis_rms_lo_mid_hi_phase": an[:5],
                          "rms_L": float(np.sqrt((pcm[:, 0] ** 2).mean())), "rms_R": float(np.sqrt((pcm[:, 1] ** 2).mean())),
                          "peak": float(np.abs(pcm).max()), "nan": bool(np.isnan(pcm).any())}))
        return

    # live: read commands on a thread, stream audio to the player while on
    def reader():
        for line in sys.stdin:
            line = line.strip()
            if not line: continue
            try: d = json.loads(line)
            except Exception: emit({"error": "bad json"}); continue
            c = d.get("cmd")
            if c == "play": eng.play()
            elif c == "stop": eng.stop()
            elif c == "toggle": (eng.stop() if eng.on else eng.play())
            elif c == "set": eng.apply(d)
            elif c == "scene": eng.scene(d.get("name", ""))
            elif c == "clips": eng.scan_clips()
            elif c == "clip":
                if d.get("add"): eng.add_clip(str(d["add"]))
                elif d.get("name"): eng.set_clip(str(d["name"]), d)
            elif c == "quit": os._exit(0)
            emit(eng.status())
        os._exit(0)
    elock = threading.Lock()
    def emit(o):
        with elock: sys.stdout.write(json.dumps(o) + "\n"); sys.stdout.flush()
    threading.Thread(target=reader, daemon=True).start()
    eng.scan_clips()
    emit({"ready": True, "clipDir": CLIP_DIR, **eng.status()})
    proc = None; last = 0; blk = 0
    while True:
        if eng.on or eng.master > 1e-4:
            if proc is None or proc.poll() is not None:
                try: proc = subprocess.Popen(player_cmd(), stdin=subprocess.PIPE, stdout=subprocess.DEVNULL)
                except FileNotFoundError: emit({"error": "player not found: " + " ".join(player_cmd())}); eng.stop(); time.sleep(1); continue
            try: proc.stdin.write(eng.block().tobytes())
            except BrokenPipeError: proc = None
            if eng.hits:
                a = max(eng.hits); eng.hits = []; emit({"hit": round(a, 2)})
            blk += 1
            if blk % 2 == 0:
                eng.spectrum(); emit(eng.analysis())          # ~23 Hz
        with eng.lock: pm = eng.plate_msg
        if pm is not None:
            with eng.lock: eng.plate_msg = None
            emit(pm)
        else:
            if proc is not None:
                try: proc.stdin.close()
                except Exception: pass
                proc.wait(); proc = None
            time.sleep(.05)
        if time.time() - last >= 1.0:
            last = time.time(); emit(eng.status())

if __name__ == "__main__":
    main()
