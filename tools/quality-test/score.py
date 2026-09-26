"""Rank every version in captures/mega_latest.csv (made by mega.py).

Prints the top two in each category, then an overall "best of all worlds"
score: each version's rank in every category (0 = worst, 1 = best),
weighted by what matters most for reading old comics here - smooth, even
outlines first, then black ink, no halos and no lost detail.
"""
import csv
from pathlib import Path

CSV = Path(__file__).parent / "captures" / "mega_latest.csv"
# Versions that leave the page about as soft as the browser shows it (edge
# width >= 1.4px, browser = 1.5) barely change the image, so they "keep all
# detail" trivially. They're listed separately, not ranked.
SOFT = 1.4


def metrics(browser):
    # column, label, weight, sort key (smaller = better)
    return [
        ("Whole panel|rough", "Smoothest stair-steps", 3.0, lambda v, c: v),
        ("Whole panel|ink", "Darkest ink", 2.0, lambda v, c: v),
        ("Whole panel|halo_strict", "Fewest halos", 1.5, lambda v, c: v),
        ("Thing rock texture|match", "Most detail kept (rock)", 1.5, lambda v, c: -v),
        ("Torch hatching|match", "Most detail kept (Torch lines)", 1.5, lambda v, c: -v),
        ("Whole panel|width", "Crispest edges", 1.0, lambda v, c: v),
        ("Whole panel|thick", "Truest line thickness", 1.0, lambda v, c: abs(v - float(browser[c]))),
        ("Whole panel|dkring", "Least ink bleed", 1.0, lambda v, c: v),
        ("Thing rock texture|black%", "Least merging into black", 1.0, lambda v, c: v),
        ("Fine lines|rough", "Smoothest fine lines", 1.0, lambda v, c: v),
        ("Fine lines|roping", "Steadiest fine lines", 1.0, lambda v, c: v),
        ("Faces|shape", "Most faithful faces", 1.5, lambda v, c: v),
    ]


def load():
    """Returns (ranked rows, soft rows, browser row, metrics, {name: score 0-100})."""
    rows = list(csv.DictReader(open(CSV, encoding="utf-8")))
    browser = next(r for r in rows if r["name"] == "Browser only")
    rows = [r for r in rows if r["name"] != "Browser only"]
    soft = [r for r in rows if float(r["Whole panel|width"]) >= SOFT]
    rows = [r for r in rows if float(r["Whole panel|width"]) < SOFT]
    ms = metrics(browser)
    score = {r["name"]: 0.0 for r in rows}
    for c, _, w, key in ms:
        ranked = sorted(rows, key=lambda r: key(float(r[c]), c))
        for i, r in enumerate(ranked):
            score[r["name"]] += w * (1 - i / (len(ranked) - 1))
    total = sum(w for _, _, w, _ in ms)
    return rows, soft, browser, ms, {n: 100 * s / total for n, s in score.items()}


if __name__ == "__main__":
    rows, soft, browser, ms, score = load()
    print(f"Not ranked (about as soft as no upscaling): {', '.join(r['name'] for r in soft)}\n")
    print("== Top two in each category ==")
    for c, label, w, key in ms:
        a, b = sorted(rows, key=lambda r: key(float(r[c]), c))[:2]
        print(f"{label:32} 1) {a['name']} ({float(a[c]):.3f})   2) {b['name']} ({float(b[c]):.3f})")
    print("\n== Best of all worlds (weighted rank score, 100 = best in every category) ==")
    cur = next(r for r in rows if r["name"].startswith("InkContour G4"))
    for n, s in sorted(score.items(), key=lambda kv: -kv[1])[:15]:
        r = next(x for x in rows if x["name"] == n)
        better = sum(key(float(r[c]), c) < key(float(cur[c]), c) for c, _, _, key in ms)
        print(f"{s:5.1f}  {n:34} beats the laptop default (G4) in {better}/{len(ms)} categories")
    print(f"{score[cur['name']]:5.1f}  {cur['name']}")
    prev = next(r for r in rows if r["name"].startswith("NNEDI3x2+CASx2 (previous default)"))
    print(f"{score[prev['name']]:5.1f}  {prev['name']}")
