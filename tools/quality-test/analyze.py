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
ROWS = {k: {"name": k, "file": v} for k, v in SHOTS.items()}  # everything measured, for ANALYZE_CSV

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
        if near.size == 0 or ring.size == 0: return None
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

print(f"Screens: 1920x1080 each. Tracks found on {REF}, traced identically in all.\n")
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
        ROWS[k].update({f"{rname}|{m}": v for m, v in zip(("rough", "width", "thick", "ink", "halo", "dkring"),
                        (rr, ww, np.median(thick), np.median(cores), np.mean(halos), np.mean(rings)))})
        print(f"{k:21}{rr:7.3f}{ww:7.2f}{rr / ww:7.3f}{np.median(thick):7.2f}{np.median(cores):6.0f}{np.mean(halos):6.1f}{np.mean(rings):7.1f}{fn:7.2f}")
    print()

# Strict halo: only ink edges with truly flat colour beside them (so JPEG
# noise and busy areas can't count as "halo"), and how much brighter the
# 5px right next to the ink get than that flat colour. The per-outline
# "halo" above can be fooled by uneven surroundings; this one can't.
def strict_halo_sites(ref, box):
    x0, y0, x1, y1 = box
    ys, xs, ds = [], [], []
    for y in range(y0, y1):
        row = ref[y]
        for x in range(x0 + 16, x1 - 16):
            for d in (1, -1):
                if row[x] < 60 and row[x + d] >= 60:
                    plain = row[x + 6 * d: x + 15 * d: d]
                    if plain.mean() > 100 and plain.std() < 4:
                        ys.append(y); xs.append(x); ds.append(d)
    return np.array(ys), np.array(xs), np.array(ds)

hy, hx, hd = strict_halo_sites(L[REF], REGIONS["Whole panel"])
near_idx = hx[:, None] + hd[:, None] * np.arange(1, 6)[None, :]
plain_idx = hx[:, None] + hd[:, None] * np.arange(6, 15)[None, :]
print(f"== Strict halo: {len(hy)} ink edges beside flat colour (brightest of the 5px next to the ink"
      " minus the flat colour; 0 = no halo) ==")
for k, img in L.items():
    over = img[hy[:, None], near_idx].max(1) - img[hy[:, None], plain_idx].mean(1)
    h = np.clip(over, 0, None)
    ROWS[k]["Whole panel|halo_strict"] = h.mean()
    print(f"{k:21}{h.mean():7.2f}  (edges with a visible 3+ level halo: {100 * (h >= 3).mean():5.1f}%)")
print()

# Fine lines: the thinnest traced lines (under 3.2px wide in the reference).
# Thinning lines too far makes these jaggy first: their edges wobble
# (rough), their core can't reach full black (core) and its darkness pulses
# along the line as it crosses the pixel grid (roping).
all_tracks = find_tracks(L[REF], REGIONS["Whole panel"])
def track_thickness(img, t):
    th = [r["R"][0] - r["L"][0] for r in (trace_row(img, y, c) for y, c in t) if r]
    return np.median(th) if th else np.nan
fine_tracks = [t for t in all_tracks if track_thickness(L[REF], t) < 3.2]
print(f"== Fine lines: {len(fine_tracks)} traced lines under 3.2px wide ==")
print(f"{'':13}{'rough':>7}{'thick':>7}{'core':>6}{'roping':>8}")
for k, img in L.items():
    rough, thick, cores, roping = [], [], [], []
    for t in fine_tracks:
        ys, lx, rx, cs = [], [], [], []
        for (y, c) in t:
            r = trace_row(img, y, c)
            if r is None: continue
            ys.append(y); lx.append(r["L"][0]); rx.append(r["R"][0]); cs.append(r["core"])
            thick.append(r["R"][0] - r["L"][0])
        if len(ys) >= 25:
            rough += roughness(ys, lx) + roughness(ys, rx)
            cs = np.asarray(cs)
            # pulsing = row-to-row change of the core darkness along the line
            roping.append(np.abs(np.diff(cs)).mean()); cores.append(np.median(cs))
    rr = np.sqrt(np.mean(np.square(rough))) if rough else np.nan
    vals = (rr, np.median(thick) if thick else np.nan, np.median(cores) if cores else np.nan, np.mean(roping) if roping else np.nan)
    ROWS[k].update({f"Fine lines|{m}": v for m, v in zip(("rough", "thick", "core", "roping"), vals)})
    print(f"{k:21}{vals[0]:7.3f}{vals[1]:7.2f}{vals[2]:6.0f}{vals[3]:8.2f}")
print()

from scipy import ndimage

# Busy areas where smoothing can merge nearby shapes: fine detail survival.
DETAIL_REGIONS = {"Thing rock texture": (700, 590, 900, 930), "Torch hatching": (480, 290, 620, 500)}

def detail_stats(img, ref, box):
    x0, y0, x1, y1 = box
    sub = img[y0:y1, x0:x1]
    black = (sub < 45).mean() * 100
    def count(mask):
        lab, n = ndimage.label(mask)
        return int((np.bincount(lab.ravel())[1:] >= 6).sum()) if n else 0
    gaps, inks = count(sub > 110), count(sub < 70)
    # Structure match: band-pass (texture-scale) correlation with the
    # browser-only image, which has the true shapes, just blurrier.
    bp = lambda a: ndimage.gaussian_filter(a, 1.0) - ndimage.gaussian_filter(a, 4.0)
    s, r = bp(sub), bp(ref[y0:y1, x0:x1])
    corr = np.corrcoef(s.ravel(), r.ravel())[0, 1]
    return black, gaps, inks, corr

print("== Fine detail: black% (merging into solid black, lower = less), light gaps / ink shapes"
      " still separate (higher = more detail), structure match with browser (1 = same shapes) ==")
for rname, box in DETAIL_REGIONS.items():
    print(f"-- {rname} --")
    print(f"{'':13}{'black%':>8}{'gaps':>6}{'inks':>6}{'match':>7}")
    for k, img in L.items():
        bl, g, i, c = detail_stats(img, L[list(SHOTS)[0]], box)
        ROWS[k].update({f"{rname}|black%": bl, f"{rname}|gaps": g, f"{rname}|inks": i, f"{rname}|match": c})
        print(f"{k:21}{bl:8.1f}{g:6d}{i:6d}{c:7.3f}")
    print()

import os, csv
if os.environ.get("ANALYZE_CSV"):  # machine-readable copy of every number above
    cols = list(dict.fromkeys(c for r in ROWS.values() for c in r))
    with open(os.environ["ANALYZE_CSV"], "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, cols); w.writeheader(); w.writerows(ROWS.values())
if os.environ.get("NO_PAIRS"):
    sys.exit(0)

print("== Mean absolute luma difference between each pair (whole panel) ==")
x0, y0, x1, y1 = REGIONS["Whole panel"]
names = list(L)
print(f"{'':13}" + "".join(f"{n[:11]:>12}" for n in names))
for a in names:
    print(f"{a:21}" + "".join(f"{np.abs(L[a][y0:y1, x0:x1] - L[bn][y0:y1, x0:x1]).mean():12.2f}" for bn in names))
