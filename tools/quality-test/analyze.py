"""Objective comparison of the upscaling screenshots of the same panel.

Metrics (all in screen pixels / 0-255 luma):
  roughness   RMS distance of each traced outline edge from a smooth local
              quadratic fit (21-row window). Staircase steps + wobble. Lower
              = smoother lines.
  edge width  20%->80% transition distance across an ink edge. Lower =
              crisper; higher = softer/blurrier.
  visibility  roughness / edge width: how exposed the wobble is. A soft
              edge hides the same wobble a crisp edge shows.
  thickness   ink line width between the two 50% crossings. Compared with
              the browser-only image = fidelity to the original line weight.
  ink core    darkest luma inside the line. Lower = solid black ink.
  halo        brightest point within 1-3px outside the edge minus the plain
              colour 5-7px out. Positive = a light ring (halo) around lines.
  dark ring   plain colour minus the darkest point 2-4px outside the edge.
              Positive = a dark fringe / ink bleeding into the colour.
  flat noise  luma std-dev inside flat colour areas (7x7 windows, away
              from edges). Lower = cleaner flat colour.
Tracks are found once (on the second image given) and traced identically in every image.
"""
from pathlib import Path
import itertools
import numpy as np
from PIL import Image

import sys
IMG = Path(__file__).parent / "captures"
SHOTS = dict(a.split("=", 1) for a in sys.argv[1:])  # e.g. Browser=cap_Browser.png NoSharp=cap_NoSharp.png ...
REF = list(SHOTS)[1] if len(SHOTS) > 1 else list(SHOTS)[0]  # outlines are found on the first upscaled image
REGIONS = {"Mantis legs": (1000, 600, 1130, 1040), "Mantis neckline": (1000, 320, 1130, 480), "Whole panel": (430, 180, 1495, 1070)}

def luma(path):
    a = np.asarray(Image.open(IMG / path).convert("RGB"), dtype=np.float64)
    return 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]

L = {k: luma(v) for k, v in SHOTS.items()}

def find_tracks(img, box, dark=80, light=140, min_len=30):
    x0, y0, x1, y1 = box
    tracks, active = [], []
    for y in range(y0, y1):
        row, runs, x = img[y], [], x0 + 2
        while x < x1 - 2:
            if row[x] < dark:
                s = x
                while x < x1 - 2 and row[x] < dark: x += 1
                e = x - 1
                if 2 <= e - s + 1 <= 8 and row[s - 2] > light and row[e + 2] > light: runs.append((s + e) / 2)
            x += 1
        nxt = []
        for c in runs:
            best = min((t for t in active if abs(t[-1][1] - c) <= 2), key=lambda t: abs(t[-1][1] - c), default=None)
            if best is not None: best.append((y, c)); nxt.append(best); active.remove(best)
            else: nxt.append([(y, c)])
        tracks += [t for t in active if len(t) >= min_len]
        active = nxt
    return tracks + [t for t in active if len(t) >= min_len]

def crossing(row, start, direction, level, limit=10):
    prev = start
    for i in range(1, limit):
        xi = start + direction * i
        if row[xi] >= level:
            a, b = row[prev], row[xi]
            return prev + direction * ((level - a) / (b - a) if b != a else 0)
        prev = xi
    return None

def trace_row(img, y, center):
    row = img[y]; c = int(round(center))
    core = row[c - 2:c + 3].min()
    res = {"core": core}
    for name, d in (("L", -1), ("R", 1)):
        x = c
        while abs(x - c) < 10 and row[x] < 140: x += d
        plain = np.median(row[x + 4 * d: x + 7 * d: d]) if d > 0 else np.median(row[x - 6:x - 3])
        span = plain - core
        if span < 60: return None
        p50 = crossing(row, c, d, core + 0.5 * span)
        p20 = crossing(row, c, d, core + 0.2 * span)
        p80 = crossing(row, c, d, core + 0.8 * span)
        if None in (p50, p20, p80): return None
        e = int(round(p80))
        near = row[e + d: e + 4 * d: d] if d > 0 else row[e - 3:e]
        ring = row[e + 2 * d: e + 5 * d: d] if d > 0 else row[e - 4:e - 1]
        res[name] = (p50, abs(p80 - p20), max(0.0, near.max() - plain), max(0.0, plain - ring.min()))
    return res

def roughness(ys, xs, win=21):
    ys, xs, h, out = np.asarray(ys, float), np.asarray(xs, float), win // 2, []
    for i in range(h, len(xs) - h):
        yy, xx = ys[i - h:i + h + 1], xs[i - h:i + h + 1]
        if np.any(np.diff(yy) != 1): continue
        p = np.polyfit(yy - yy.mean(), xx, 2)
        out.append(xx[h] - np.polyval(p, yy[h] - yy.mean()))
    return out

def flat_noise(img, box, mask):
    x0, y0, x1, y1 = box
    sub = img[y0:y1, x0:x1]; m = mask[y0:y1, x0:x1]
    stds = []
    for yy in range(0, sub.shape[0] - 7, 7):
        for xx in range(0, sub.shape[1] - 7, 7):
            if m[yy:yy + 7, xx:xx + 7].all(): stds.append(sub[yy:yy + 7, xx:xx + 7].std())
    return np.mean(stds) if stds else float("nan"), len(stds)

# Flat-colour mask from the browser-only image: low gradient, away from edges.
b = L[list(SHOTS)[0]]
gy, gx = np.gradient(b)
grad = np.hypot(gx, gy)
edge = grad > 6
dil = edge.copy()
for dy, dx in itertools.product(range(-4, 5), repeat=2):
    dil |= np.roll(np.roll(edge, dy, 0), dx, 1)
flat_mask = ~dil

print("Screens: 1920x1080 each. Tracks found on NoSharp, traced identically in all.\n")
for rname, box in REGIONS.items():
    tracks = find_tracks(L[REF], box)
    print(f"== {rname}: {len(tracks)} ink-outline tracks, {sum(len(t) for t in tracks)} outline rows ==")
    print(f"{'':13}{'rough':>7}{'width':>7}{'visib':>7}{'thick':>7}{'ink':>6}{'halo':>6}{'dkring':>7}{'flatnz':>7}")
    for k, img in L.items():
        rough, widths, thick, cores, halos, rings = [], [], [], [], [], []
        for t in tracks:
            ys, lx, rx = [], [], []
            for (y, c) in t:
                r = trace_row(img, y, c)
                if r is None: continue
                ys.append(y); lx.append(r["L"][0]); rx.append(r["R"][0])
                thick.append(r["R"][0] - r["L"][0]); cores.append(r["core"])
                for s in ("L", "R"):
                    widths.append(r[s][1]); halos.append(r[s][2]); rings.append(r[s][3])
            if len(ys) >= 25:
                rough += roughness(ys, lx) + roughness(ys, rx)
        rr = np.sqrt(np.mean(np.square(rough))); ww = np.median(widths)
        fn, _ = flat_noise(img, box, flat_mask)
        print(f"{k:21}{rr:7.3f}{ww:7.2f}{rr / ww:7.3f}{np.median(thick):7.2f}{np.median(cores):6.0f}{np.mean(halos):6.1f}{np.mean(rings):7.1f}{fn:7.2f}")
    print()

print("== Mean absolute luma difference between each pair (whole panel) ==")
x0, y0, x1, y1 = REGIONS["Whole panel"]
names = list(L)
print(f"{'':13}" + "".join(f"{n[:11]:>12}" for n in names))
for a in names:
    print(f"{a:21}" + "".join(f"{np.abs(L[a][y0:y1, x0:x1] - L[bn][y0:y1, x0:x1]).mean():12.2f}" for bn in names))
