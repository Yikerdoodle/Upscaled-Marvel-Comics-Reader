"""Make captures/flipbook/: every version full-size, with the unmodified
browser capture between each, so arrow-keying through them in an image
viewer flips version -> browser -> next version.

Order: laptop default (InkContour G4) first, then best overall score first (see
score.py), then the versions too soft to rank. Uses the aligned copies from
mega.py, so nothing jumps sideways between files.
"""
import re
import shutil
from pathlib import Path
import score

CAP = Path(__file__).parent / "captures"
OUT = CAP / "flipbook"

rows, soft, browser, _, sc = score.load()
cur = next(r for r in rows if r["name"].startswith("InkContour G4"))
order = [(cur, None)]  # its name already says it is the laptop default
order += [(r, f"rank {i:02d}, score {sc[r['name']]:.0f}")
          for i, r in enumerate(sorted(rows, key=lambda r: -sc[r["name"]]), 1) if r is not cur]
order += [(r, "too soft to rank") for r in soft]

if OUT.exists():
    shutil.rmtree(OUT)
OUT.mkdir()
safe = lambda s: re.sub(r'[<>:"/\\|?*]', "_", s)
n = 0
for r, tag in order:
    n += 1
    shutil.copyfile(CAP / browser["file"], OUT / f"{n:03d} Browser (no upscaling).png")
    n += 1
    shutil.copyfile(CAP / r["file"], OUT / safe(f"{n:03d} {r['name']}" + (f" ({tag})" if tag else "") + ".png"))
n += 1
shutil.copyfile(CAP / browser["file"], OUT / f"{n:03d} Browser (no upscaling).png")
print(f"{n} files in {OUT}")
