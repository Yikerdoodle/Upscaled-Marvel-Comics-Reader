"""Measure the width of every ink line in a capture (in screen pixels).

For each capture: find ink (darker than the half-way level between the
local ink and the local fill colour), trace each stroke's centre line
(skeleton) and read the stroke width there (twice the distance to the
nearest edge), at 4x sub-pixel resolution. Solid black areas (wider than
10px) are left out - only lines count.

Usage: python linewidths.py Label=capture.png [Label=capture.png ...]
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image
from scipy import ndimage
from skimage.morphology import skeletonize

CAP = Path(__file__).parent / "captures"
BOXES = {"whole panel": (430, 180, 1495, 1070), "Torch hatching": (480, 290, 620, 500), "Thing rock": (700, 590, 900, 930)}
UP = 4


def widths(path, box):
    a = np.asarray(Image.open(CAP / path).convert("RGB"), dtype=np.float64)
    lum = 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]
    x0, y0, x1, y1 = box
    sub = lum[y0:y1, x0:x1]
    mn = ndimage.minimum_filter(sub, 9); mx = ndimage.maximum_filter(sub, 9)
    valid = (mx - mn > 60) & (mn < 100)
    mid = ndimage.gaussian_filter((mn + mx) / 2, 2)
    big = ndimage.zoom(sub, UP, order=3)
    ink = (big < ndimage.zoom(mid, UP, order=1)) & ndimage.zoom(valid, UP, order=0)
    dist = ndimage.distance_transform_edt(ink)
    sk = skeletonize(ink)
    w = 2 * dist[sk] / UP
    return w[(w > 0.3) & (w < 10)]


if __name__ == "__main__":
    shots = dict(a.split("=", 1) for a in sys.argv[1:])
    for bname, box in BOXES.items():
      print(f"-- {bname} --")
      print(f"{'':24}{'finest 10%':>11}{'fine 25%':>10}{'median':>8}{'outline 75%':>12}{'heavy 90%':>10}   (px on screen; x0.18 = mm)")
      for k, f in shots.items():
        w = widths(f, box)
        p = np.percentile(w, [10, 25, 50, 75, 90])
        print(f"{k:24}" + "".join(f"{v:>{n}.2f}" for v, n in zip(p, (11, 10, 8, 12, 10))))
