from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

import sys
IMG = Path(__file__).parent / "captures"
OUT = IMG
SHOTS = dict(a.split("=", 1) for a in sys.argv[1:])
CROPS = {"legs": (1040, 820, 1110, 1000), "neckline": (1030, 330, 1110, 470)}
SCALE = 5
try:
    font = ImageFont.truetype("segoeui.ttf", 22)
except OSError:
    font = ImageFont.load_default()
for name, box in CROPS.items():
    w, h = (box[2] - box[0]) * SCALE, (box[3] - box[1]) * SCALE
    sheet = Image.new("RGB", (len(SHOTS) * (w + 12) - 12, h + 36), "white")
    d = ImageDraw.Draw(sheet)
    for i, (label, f) in enumerate(SHOTS.items()):
        crop = Image.open(IMG / f).convert("RGB").crop(box).resize((w, h), Image.NEAREST)
        x = i * (w + 12)
        sheet.paste(crop, (x, 36))
        d.text((x + 4, 4), label, fill="black", font=font)
    sheet.save(OUT / f"all_{name}.png")
    print(OUT / f"all_{name}.png", sheet.size)
