#!/usr/bin/env python3
"""Free-edge circular plate (a Chladni plate): eigenmodes from the plate equation, numpy only.

W_nm(r, theta) = [J_n(lam r) + C I_n(lam r)] cos(n theta),  r in [0, 1]
with the free-edge conditions at r = 1: radial bending moment M_r = 0, Kirchhoff shear V_r = 0.
Mode frequency f_nm = F0 * lam_nm^2 / lam_20^2  (the (2,0) mode - four sand lines - tuned to F0).

plate_table(...)                    -> [dict(n, s, lam, C, f)] sorted by f
radial_lut(modes, N)                -> (len(modes), N) float32 radial shapes, r = 0..1, peak-normalised
response(modes, band_hz, band_amp)  -> per-mode amplitude excited by a measured spectrum
render(modes, amps, lut, size)      -> uint8 sand image (offline check)
"""
import numpy as np

NU = 0.33      # Poisson ratio
F0 = 40.0      # Hz of the lowest mode (2,0): fixes the plate size/thickness (larger plate = denser modes)
TAU = np.linspace(0, np.pi, 1201)
_trap = getattr(np, "trapezoid", None) or getattr(np, "trapz")

def Jn(n, x):
    """Bessel J_n by Bessel's integral (integer n >= 0)."""
    x = np.atleast_1d(np.asarray(x, float))
    return _trap(np.cos(n * TAU[None, :] - x[:, None] * np.sin(TAU)[None, :]), TAU, axis=1) / np.pi

def In(n, x):
    """Modified Bessel I_n by its integral (integer n >= 0)."""
    x = np.atleast_1d(np.asarray(x, float))
    return _trap(np.exp(x[:, None] * np.cos(TAU)[None, :]) * np.cos(n * TAU)[None, :], TAU, axis=1) / np.pi

def J(n, x):
    return ((-1.0) ** (-n)) * Jn(-n, x) if n < 0 else Jn(n, x)

def I(n, x):
    return In(abs(n), x)

def derivs(kind, n, lam):
    """R, R', R'', R''' at r = 1 for R(r) = B_n(lam r), via the Bessel recurrences."""
    B = J if kind == "J" else I
    sgn = -1.0 if kind == "J" else 1.0
    x = np.array([lam])
    b = {k: float(B(n + k, x)[0]) for k in range(-3, 4)}
    R = b[0]
    R1 = lam * (b[-1] + sgn * b[1]) / 2.0
    R2 = lam ** 2 * (b[-2] + 2.0 * sgn * b[0] + b[2]) / 4.0
    R3 = lam ** 3 * (b[-3] + 3.0 * sgn * b[-1] + 3.0 * b[1] + sgn * b[3]) / 8.0
    return R, R1, R2, R3

def bc_rows(kind, n, lam, nu=NU):
    R, R1, R2, R3 = derivs(kind, n, lam)
    m = R2 + nu * (R1 - n * n * R)                   # M_r at r = 1
    dlap = R3 + R2 - R1 - n * n * (R1 - 2.0 * R)     # d/dr (Laplacian) at r = 1
    v = dlap - (1.0 - nu) * n * n * (R1 - R)         # V_r at r = 1
    return m, v

def free_edge_matrix(n, lam, nu=NU):
    mJ, vJ = bc_rows("J", n, lam, nu)
    mI, vI = bc_rows("I", n, lam, nu)
    return np.array([[mJ, mI], [vJ, vI]])

def det(n, lam):
    M = free_edge_matrix(n, lam)
    M = M / (np.abs(M).max(axis=1, keepdims=True) + 1e-300)   # row-scale (I_n grows fast)
    return M[0, 0] * M[1, 1] - M[0, 1] * M[1, 0]

def find_roots(n, lam_max=16.0, step=0.02, max_modes=3):
    lo = 1.2 if n <= 1 else 0.8
    lams = np.arange(lo, lam_max, step)
    vals = np.array([det(n, l) for l in lams])
    roots = []
    for i in range(len(lams) - 1):
        if np.sign(vals[i]) != np.sign(vals[i + 1]):
            a, b = lams[i], lams[i + 1]
            fa = det(n, a)
            for _ in range(40):
                m = 0.5 * (a + b); fm = det(n, m)
                if np.sign(fa) != np.sign(fm): b = m
                else: a, fa = m, fm
            lam = 0.5 * (a + b)
            if all(abs(lam - q) > 0.05 for q in roots): roots.append(lam)
            if len(roots) >= max_modes: break
    return roots

def plate_table(n_max=11, per_n=4, lam_max=20.0):
    modes = []
    for n in range(0, n_max + 1):
        for s, lam in enumerate(find_roots(n, lam_max=lam_max, max_modes=per_n)):
            M = free_edge_matrix(n, lam)
            C = -M[0, 0] / M[0, 1] if abs(M[0, 1]) > 1e-300 else 0.0
            modes.append(dict(n=n, s=s, lam=float(lam), C=float(C)))
    lam20 = [m["lam"] for m in modes if m["n"] == 2 and m["s"] == 0][0]
    for m in modes:
        m["f"] = F0 * (m["lam"] / lam20) ** 2
    modes.sort(key=lambda m: m["f"])
    return modes

def radial_shape(m, r):
    R = Jn(m["n"], m["lam"] * r) + m["C"] * In(m["n"], m["lam"] * r)
    return R / (np.abs(R).max() + 1e-12)

def radial_lut(modes, N=256):
    r = np.linspace(0, 1, N)
    return np.stack([radial_shape(m, r) for m in modes]).astype(np.float32)

def response(modes, band_hz, band_amp, gamma_ratio=0.06):
    """Lorentzian resonant response of each mode to a measured spectrum (damping ~ f)."""
    f = np.array([m["f"] for m in modes]); a = np.zeros(len(modes))
    for fk, sk in zip(band_hz, band_amp):
        if sk <= 0: continue
        g = gamma_ratio * f
        a += sk * (g * g) / ((fk - f) ** 2 + g * g)
    return a

def render(modes, amps, lut, size=512, sand_sigma=0.06, phases=None, seed=1):
    y, x = np.mgrid[-1:1:size * 1j, -1:1:size * 1j]
    r = np.sqrt(x * x + y * y); th = np.arctan2(y, x); inside = r <= 1
    W = np.zeros_like(r)
    rr = np.linspace(0, 1, lut.shape[1])
    for i, m in enumerate(modes):
        if amps[i] < 1e-4: continue
        R = np.interp(r, rr, lut[i])
        ph = 0.0 if phases is None else phases[i]
        W += amps[i] * R * np.cos(m["n"] * th + ph)
    W /= (np.abs(W[inside]).max() + 1e-9)
    sand = np.exp(-(W * W) / (2 * sand_sigma * sand_sigma))
    rng = np.random.default_rng(seed); grain = 0.55 + 0.45 * rng.random(W.shape)
    return (np.clip(np.where(inside, sand * grain, 0.0), 0, 1) * 255).astype(np.uint8)

if __name__ == "__main__":
    import time
    t0 = time.time(); modes = plate_table(); dt = time.time() - t0
    print("modes:", len(modes), "computed in %.1fs" % dt)
    for m in modes[:16]:
        print("  (n=%d,s=%d)  lam=%.3f  C=%+.4f  f=%.1f Hz" % (m["n"], m["s"], m["lam"], m["C"], m["f"]))
