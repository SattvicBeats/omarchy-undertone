# Undertone plugin — release ledger

| version | git tag | sha256 (tarball, first 16) | behaviours added / changed | gate at release |
|---|---|---|---|---|
| 0.5.3 | v0.5.3 | 37b78a4d9eead35a | FIX player restart bug (choppy audio); non-blocking stdout; plate solve in subprocess; JS painters ≤160/15fps | service harness ✓ · continuity ✓ (first version to have it) |
| 0.5.4 | v0.5.4 | df471dec86e7c393 | live sliders + 20 ms glide; log base 40–800; beat 0.5–50; wheel steps; L/R readout; audio thread never blocks stdout (ctl/drop queues) | service ✓ · continuity ×3 ✓ · visual models ✓ |
| 0.5.5 | v0.5.5 | a2c31479d29711c5 | Left/Right/Beat readouts; Pure pair; IPC set/pure | service ✓ · continuity ✓ |
| 0.6.0 | v0.6.0 | c81467b9e9908c27 | Mandala, Lissajous, Scope, Tunnel; waveform stream; BreathFlower pacer | service ✓ · continuity ✓ · 9 models rendered ✓ |
| 0.6.1 | v0.6.1 | 0af78c8debfec49c | Om voice (male/female); Beach, Ocean waves, Om scenes; surf foam | service ✓ · continuity ✓ · Om pitch/cycle ✓ |
| 0.6.2 | v0.6.2 | cf218f65f12fbec2 | BreathFlower bounded (≤0.46 d) + label clearance | service ✓ · continuity ✓ · flower render ✓ — **user report: panel does not open** (unreproduced in harness) |
| 0.6.3 | v0.6.3 | 4684fd623f3fca0a | winfo IPC; hard re-show (diagnostic build) | service ✓ |

Last version confirmed working on BOMARCHY by the user: **0.6.1** (flower visible, panel open).

## Rollback
    undertone-release list
    undertone-release rollback 0.6.1
