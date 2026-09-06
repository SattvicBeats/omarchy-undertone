# Undertone — native Omarchy shell plugin

A binaural-beat instrument that runs entirely inside the Omarchy shell: hard-L/R
beat, tanpura drone, Hindustani taals, noise colours, weather layers, breath
pacer, sleep timer — and the three Ground Control visuals (interference field,
Lava, Flow) in the panel and as a fullscreen screensaver. No browser, no network, no account. Audio is synthesised
by a small numpy engine and played through PipeWire (`pw-cat`).

The full web instrument with visuals, saved mixes, share links and MIDI Listen
is the separate [Ground Control](https://groundcontrol.sworn.legal/) — linked
from the panel, never required.

## Install

    omarchy plugin add https://github.com/SattvicBeats/omarchy-undertone.git --enable

Needs `python-numpy` (`omarchy-pkg-add python-numpy`); the panel shows a setup
card with that command if it's missing. `pw-cat` ships with PipeWire.

## Use

- Bar pill: left-click panel · middle-click play/pause · right-click stop
- Hotkey — `~/.config/hypr/bindings.conf`:

      bindd = SUPER ALT, U, Undertone, exec, omarchy-shell undertone toggle

- CLI: `omarchy-shell undertone playpause|play|stop|show|hide|status`, `omarchy-shell undertone set beat 47`, `omarchy-shell undertone pure` (two ear tones only),
  `omarchy-shell undertone scene Rest`

## Visuals listen to the sound

Nothing in the visuals is taken from the settings. The engine FFTs its own output
(8192-sample window, ~23×/s) and streams what it measures: loudness, low/mid/high energy,
a 32-band log spectrum (40 Hz–16 kHz), the strongest tone in each ear, and the taal hits.

- **Field** — ring geometry from the two measured ear tones; drift is the integral of
  their measured difference, i.e. the beat as heard; brightness = loudness
- **Lava** — plate heat from bass energy, brightness from loudness, hits shove the blobs
- **Flow** — particle speed from mid/high energy, hits accelerate
- **Spectrum** — 32 bars with peak hold, left-tone colour low, right-tone colour high
- **Mandala** — the 32 measured bands folded into 6–12-fold radial symmetry (petal count from bass), rotating at the measured beat
- **Lissajous** — left ear vs right ear, raw samples: for a binaural pair the figure rotates at exactly the beat frequency — the beat made visible (best in *Pure pair*)
- **Scope** — Black Dawn's "waveform interference · time domain": the L+R sum over 171 ms with its envelope, pulsing at the beat
- **Tunnel** — MilkDrop-style tunnel; depth scrolls at the beat, rings lit by the spectrum (bass near, treble far)
- **Cymatics** (default) — a real Chladni plate. `engine/plate.py` solves the free-edge circular
  plate equation (Bessel J/I by quadrature, free-edge boundary determinant, eigenvalues match
  Leissa's table to 3 digits; lowest mode (2,0) tuned to 40 Hz; 43 modes to ~2.9 kHz, cached in
  `~/.cache/undertone/plate-v2.json`). Every frame each mode's amplitude is the plate's Lorentzian
  resonant response to the measured 32-band spectrum (linear power, so the peaks dominate); the shader sums a_i·R_i(r)·cos(n_i θ) from
  the eigenmode lookup texture and puts sand where the plate is still. A tone between resonances
  superposes its neighbours exactly as a driven plate does. Line sharpness follows loudness;
  hits shake the grain.

Silence → still. Clips you add drive them exactly the same way, because they are measured
from the same output.

## Breath pacer

A six-petal flower (Apple-Breathe style) that opens on the inhale, holds, and closes on the exhale,
with the phase word and seconds left. It sits in the corner of the panel visual and in the centre of
the screensaver whenever a pacer is selected and audio is playing.

## Clips

Drop audio files in `~/.local/share/undertone/clips/` (override with `UNDERTONE_CLIPS`).
WAV plays natively; mp3/ogg/flac/m4a/opus go through `ffmpeg` if installed. Each clip
shows in the panel with play/pause, gain and loop. Scripts: `omarchy-shell undertone clip /path/to/file.wav`
(adds it to the list for this session), `omarchy-shell undertone clips` (JSON).

## Screensaver

The visual runs fullscreen on every monitor; any key or mouse movement closes it.

- Panel → **Screensaver**, or `omarchy-shell undertone screensaver`
- Panel → **System screensaver: Undertone** makes it *the* screensaver: it fires at
  Omarchy's own idle time (Style > Idle, `idle.screensaver` in shell.json) and switches
  the ASCII saver off (`screensaver-off` toggle flag). Click again to hand back to Omarchy.
  Also: `omarchy-shell undertone systemsaver on|off`.
- Or leave that off and use its own timer (*or own timer → 2/5/10 min*).
- Super+Esc still forces Omarchy's ASCII one; to summon Undertone instead, bind:

      bindd = SUPER, Escape, Screensaver, exec, omarchy-shell undertone screensaver

- `omarchy-shell undertone visual lava` switches the model (field · lava · flow)

## Layout

    manifest.json        service + bar-widget, keepLoaded
    Service.qml          engine process, state, IPC, control panel window
    BarWidget.qml        bar pill
    Visual.qml           visual host: field + lava as GPU fragment shaders, flow via JS
    visual.js            the three visual models ported from the web instrument (blob physics, flow, JS fallback)
    shaders/*.frag       GLSL sources (field, lava, cymatics); *.frag.qsb are the baked Qt shaders (qsb --glsl "100 es,120,150" --hlsl 50 --msl 12)
    engine/gc_engine.py  synthesis + JSON-line control protocol
    engine/data.json     scenes / bands / rhythms / breaths (shared with the web app)

Headphones for the beat. Nothing here is medical advice.
