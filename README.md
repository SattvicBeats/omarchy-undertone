# Undertone — native Omarchy shell plugin

A binaural-beat instrument that runs entirely inside the Omarchy shell: hard-L/R
beat, tanpura drone, Hindustani taals, noise colours, weather layers, breath
pacer, sleep timer. No browser, no network, no account. Audio is synthesised
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

## Layout

    manifest.json        service + bar-widget, keepLoaded
    Service.qml          engine process, state, IPC, control panel window
    BarWidget.qml        bar pill
    engine/gc_engine.py  synthesis + JSON-line control protocol
    engine/data.json     scenes / bands / rhythms / breaths (shared with the web app)

Headphones for the beat. Nothing here is medical advice.
