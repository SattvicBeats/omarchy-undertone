# Undertone — a sound instrument for the Omarchy shell

Binaural beats, a tanpura drone, Hindustani taals, noise colours, weather, an Om, a breath pacer,
a sleep timer — and visuals that draw what you actually hear, including a solved Chladni plate.
Runs natively inside the Omarchy shell: no browser, no account, no network.

    omarchy plugin add https://github.com/SattvicBeats/omarchy-undertone.git --enable

**Needs:** `python-numpy` (`omarchy-pkg-add python-numpy` — the panel tells you if it's missing) and
PipeWire's `pw-cat` (present on every Omarchy install). `ffmpeg` only if you add mp3/flac clips.

**What it runs:** a `service` (the audio engine as a child process, `engine/gc_engine.py`) and a
`bar-widget` (play state + timer). Audio never runs in the shell thread. The engine talks JSON over
stdin/stdout, writes only to `~/.local/state/omarchy/undertone.json`, `~/.cache/undertone/`, and the
`screensaver-off` toggle flag (only when you switch the system screensaver on/off). Read `engine/`
before you enable it — it's ~700 lines of numpy.

## Use

- **Bar pill:** left-click panel · middle-click play/pause · right-click stop
- **Scenes** (17): Rest, Focus, Sit, Heart, Om, Beach, Ocean waves, … each with an evidence tag
- **Tones:** Left ear = base, Right ear = base + beat; base 40–800 Hz (log), beat 0.5–50 Hz; sliders are
  live; **Pure pair** strips everything but the two tones. Ctrl+wheel nudges a slider; wheel scrolls.
- **Layers:** tanpura (jawari), 11 taals, White/Pink/Brown/Green noise, Rain/Wind/Fire/Surf/Crickets
- **Om:** any audio files you put in `~/.local/share/undertone/om/` become one button each (as recorded,
  looped; optional Tune-to-Sa). Synth fallback for `male`/`female` if no file.
- **Clips:** files in `~/.local/share/undertone/clips/` mix into the bus with gain/loop.
- **Breath pacer:** 4-7-8, Box, Coherent … a six-petal flower over the visual.
- **Sleep timer:** 15–90 min, one-minute fade.
- **Visuals** (all measured from the output, none from the settings): Field, Lava, Flow, Spectrum,
  **Cymatics** (free-edge circular plate, eigenmodes solved on first run and cached), Mandala,
  Lissajous, Scope, Tunnel. 14 palettes + follow-theme.
- **Screensaver:** the visual fullscreen on every monitor. *System screensaver: Undertone* makes it fire
  at Omarchy's own idle time and mutes the ASCII one; click again to give it back.
- **Hotkeys:** add to `~/.config/hypr/bindings.conf`
  `bindd = SUPER ALT, U, Undertone, exec, omarchy-shell undertone toggle`
- **CLI:** `omarchy-shell undertone toggle|show|hide|play|stop|playpause|scene <name>|set <param> <value>|pure|visual <name>|palette <name>|screensaver|systemsaver on|off|clip <path>|clips|modes|status|diag`

## Headphones for the beat. Nothing here is medical advice.

The evidence tags on scenes are honest: *measured* means there is a trial behind it, *series* a case
series, *tradition* means people have done it for a long time and that's all we claim.

## Development

    test/run.sh              real Service.qml under a stub shell (reference errors, cross-wired ids)
    test/engine_test.py      12 s into a real-time sink with a hostile reader — exactly one player launch, no gaps
    qmllint -I "$OMARCHY_PATH/shell" *.qml
    RELEASES.md              ledger; test/undertone-release for install / rollback of stored versions

Every release passes the whole suite before it is tagged — see `DR-004` in the BYOAI wiki for why.
Shaders are GLSL 440 baked with `qsb --glsl "100 es,120,150" --hlsl 50 --msl 12` (sources in `shaders/`).

## Credits

Web sibling: [Ground Control](https://groundcontrol.sworn.legal/). Plate theory after Leissa,
*Vibration of Plates* (1969). Omarchy by 37signals. MIT.
