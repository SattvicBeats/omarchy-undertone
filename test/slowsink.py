import sys, time
t0 = time.time(); last = t0; n = 0; gaps = 0; worst = 0
while True:
    b = sys.stdin.buffer.read(4096)
    if not b: break
    now = time.time(); d = now - last; last = now; n += len(b)
    if d > 0.05: gaps += 1; worst = max(worst, d)
    time.sleep(len(b) / 8 / 48000)      # consume at real-time speed like pw-cat would
print("AUDIO %.1fs streamed, stalls>50ms: %d, worst %.0f ms" % (n / 8 / 48000, gaps, worst * 1000), file=sys.stderr)
