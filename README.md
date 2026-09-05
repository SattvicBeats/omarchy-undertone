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

- CLI: `omarchy-shell undertone playpause|play|stop|show|hide|status`,
  `omarchy-shell undertone scene Rest`

## Screensaver

The visual runs fullscreen on every monitor; any key or mouse movement closes it.

- Panel → **Screensaver**, or `omarchy-shell undertone screensaver`
- Idle trigger: panel → *idle → 2/5/10 min* (its own timer, independent of Omarchy's)
- To use it instead of the ASCII one: `omarchy toggle screensaver` (turns Omarchy's off;
  the lock screen is unaffected) and bind Super+Esc:

      bindd = SUPER, Escape, Screensaver, exec, omarchy-shell undertone screensaver

- `omarchy-shell undertone visual lava` switches the model (field · lava · flow)

## Layout

    manifest.json        service + bar-widget, keepLoaded
    Service.qml          engine process, state, IPC, control panel window
    BarWidget.qml        bar pill
    Visual.qml           canvas host (panel strip + screensaver)
    visual.js            the three visual models, ported from the web instrument
    engine/gc_engine.py  synthesis + JSON-line control protocol
    engine/data.json     scenes / bands / rhythms / breaths (shared with the web app)

Headphones for the beat. Nothing here is medical advice.
