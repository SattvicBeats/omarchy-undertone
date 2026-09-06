#!/usr/bin/env python3
"""Engine continuity test: plays 12 s into a real-time sink while the control reader is
deliberately 10x too slow. Passes only if the player was launched exactly once and the
sink saw no gap > 50 ms. Catches the 0.5.0 'else bound to the wrong if' regression."""
import subprocess, json, time, sys, threading, os
H = os.path.dirname(os.path.abspath(__file__)); E = os.path.join(os.path.dirname(H), "engine", "gc_engine.py")
env = dict(os.environ, GC_PLAYER="%s %s" % (sys.executable, os.path.join(H, "slowsink.py")))
p = subprocess.Popen([sys.executable, E], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
def rd():
    for _ in p.stdout: time.sleep(0.5)
threading.Thread(target=rd, daemon=True).start()
def send(o): p.stdin.write(json.dumps(o) + "\n"); p.stdin.flush()
time.sleep(0.2); send({"cmd": "scene", "name": "Heart"}); send({"cmd": "play"}); time.sleep(12)   # play before the plate message: worst case for a blocking write
send({"cmd": "stop"}); time.sleep(2); send({"cmd": "quit"}); time.sleep(0.5)
e = p.stderr.read()
launches = e.count("AUDIO"); stalls = [l for l in e.splitlines() if "stalls>50ms: 0" not in l and "AUDIO" in l]
print(e.strip()); ok = launches == 1 and not stalls
print("PASS" if ok else "FAIL (launches=%d, stall lines=%d)" % (launches, len(stalls))); sys.exit(0 if ok else 1)
