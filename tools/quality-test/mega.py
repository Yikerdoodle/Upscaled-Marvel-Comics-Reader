"""Mega comparison: every capture ever kept, measured in ONE run.

All images are traced along the same ink outlines (found on the round-7
NNEDI3x2+CASx2 capture) and compared with the same browser-only reference,
so numbers from different capture rounds are directly comparable. (That chain
was re-captured in every round and measured the same each time, which is
what makes mixing rounds fair.)

Writes captures/mega_latest.csv (copied to mega.csv when not open elsewhere), captures/mega_chart.html and
captures/mega_sidebyside.png.
"""
import csv, html, os, shutil, subprocess, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).parent
CAP = HERE / "captures"

# (label, file, what it is). First = browser reference, second = outline reference.
SHOTS = [
    ("Browser only", "cap7_Browser.png", "No upscaling"),
    ("NNEDI3x2+CASx2 (previous default)", "cap7_Current.png", "Laptop default until InkContour G4"),
    ("NoSharp", "cap3_NoSharp.png", "Previous default: Anime4K chain"),
    ("NNEDI3", "cap3_NNEDI3.png", "NNEDI3 then Anime4K"),
    ("NNEDI3+CAS", "cap3_NNEDI3_CAS.png", "NNEDI3 + CAS 0.5"),
    ("NNEDI3+CAS 1.0", "cap3_NNEDI3_CAS10.png", "NNEDI3 + CAS 1.0"),
    ("NNEDI3x2+CASx2 (r3)", "cap3_NNx2_CASx2.png", "Previous default, round-3 capture"),
    ("NNEDI3x2+CASx2 1.0", "cap3_NNx2_CASx2_10.png", "CAS at 1.0 (halos)"),
    ("NNEDI3x2+CAS end", "cap3_NNx2_CASend.png", "One CAS at the end"),
    ("NNEDI3 nns256 x2", "cap4_NN256x2.png", "Biggest NNEDI3 network"),
    ("nns256 CAS 0.3", "cap4_NN256x2_c03.png", "Biggest NNEDI3, gentler CAS"),
    ("nns256 CAS 0.7", "cap4_NN256x2_c07.png", "Biggest NNEDI3, stronger CAS"),
    ("NNEDI3 x3", "cap4_NN128x3.png", "Three NNEDI3 doublings"),
    ("nns256 x3", "cap4_NN256x3.png", "Three biggest-NNEDI3 doublings"),
    ("NNAA", "cap4_NNAA.png", "NNEDI3 anti-alias round trip first"),
    ("NNAA x2", "cap4_NNAAx2.png", "Two anti-alias round trips"),
    ("RAVU x2", "cap4_RAVUx2.png", "RAVU instead of NNEDI3"),
    ("InkContour v1 s1.5", "cap5_IC15.png", "First shader version, too sharp"),
    ("InkContour v1 s2", "cap5_IC20.png", "First shader version, too sharp"),
    ("InkContour v1 s3", "cap5_IC30.png", "First shader version, too sharp"),
    ("InkContour v1 s2 black", "cap5_IC20black.png", "First shader version, black ink"),
    ("InkContour v1 s2 crisp", "cap5_IC20crisp.png", "First shader version, crispest"),
    ("InkContour s2 w2", "cap6_ICs2w2.png", "Smoothing 2, edge 2"),
    ("InkContour s2 w3", "cap6_ICs2w3.png", "Smoothing 2, edge 3"),
    ("InkContour s3 w3", "cap6_ICs3w3.png", "Smoothing 3, edge 3"),
    ("InkContour s3 w4", "cap6_ICs3w4.png", "Smoothing 3, edge 4"),
    ("InkContour s4 w4", "cap6_ICs4w4.png", "Smoothing 4 - thins lines"),
    ("InkContour s3 black", "cap7_ICs3blk.png", "What you saw live: merges dense detail"),
    ("Protected k0.7", "cap7_ICp07.png", "Detail protection 0.7"),
    ("Protected k0.8", "cap7_ICp08.png", "Detail protection 0.8"),
    ("Protected k0.9", "cap7_ICp09.png", "Detail protection 0.9"),
    ("Protected k0.8 fine1.6", "cap7_ICp08f16.png", "Gentler fallback blur"),
    ("Protected+ink-only d0.8", "cap7_P3d08.png", "Only true ink darkened, strong"),
    ("Protected+ink-only d0.5", "cap7_P3d05.png", "Only true ink darkened, medium"),
    ("Protected+ink-only d0", "cap7_P2d0.png", "No darkening"),
    ("Protected+ink-only k0.9", "cap7_P2k09.png", "More protection"),
    ("Protected+ink-only reach 0.1", "cap7_P3r01.png", "Darkening only the very core"),
]
SHOTS = [s for s in SHOTS if (CAP / s[1]).exists()]

# Round 8 re-captured every earlier mode still in Magpie's list, plus the
# "best of all worlds" candidates (B1..); round 9 the next candidates
# (C1..) and the two AI models from the very start (APISR, AnimeJaNai).
# Labels come from the file names.
_known = {f for _, f, _ in SHOTS}
import re
_later = [(int(m.group(1)), p) for p in CAP.glob("cap*_*.png") if (m := re.match(r"cap(\d+)_", p.name)) and int(m.group(1)) >= 8]
for rnd, p in sorted(_later, key=lambda t: (t[0], t[1].name)):
    stem = p.stem.split("_", 1)[1]
    if p.name in _known or stem == "Browser":
        continue
    label = stem.replace("AJ85_", "AntiJaggy 8.5x ").replace("AJ_", "AntiJaggy ").replace("_", " ")
    if stem in ("AJ85_NNEDI3x2_CASx2", "Current"):
        label, what = f"NNEDI3x2+CASx2 (round {rnd})", "Previous default, re-captured to check rounds agree"
    elif stem == "G4":
        label, what = "InkContour G4 (laptop default)", "Laptop default: NNEDI3 + InkContour with curve protection"
    elif label[:1] in "HI" and label[1:2].isdigit():
        what = "G4 with one or two settings changed"
    elif label.startswith("R7"):
        what = "Round-7 Protected k0.8 look" + (", with an edge-shift limit" if "shift" in label else ", re-captured")
    elif label[:1] in "BC" and label[1:2].isdigit():
        what = "Best-of-all-worlds candidate"
    elif label.startswith("LW"):
        what = "Line-weight test (all lines thinned in proportion)"
    elif label.startswith("Model"):
        what = "AI model (ONNX) from the very first experiments"
    else:
        what = "Early chain, re-captured"
    SHOTS.append((label, p.name, what))

# Headline metrics: (csv column, short name, lower_is_better, explanation)
METRICS = [
    ("Whole panel|rough", "Stair-steps", True, "How far outlines wobble from a smooth curve (px). Lower = smoother, more even."),
    ("Whole panel|width", "Edge softness", True, "Ink-to-colour transition width (px). Lower = crisper."),
    ("Whole panel|ink", "Ink", True, "Darkness of the ink core (0 = pure black)."),
    ("Whole panel|halo_strict", "Halo", True, "How much brighter the colour right beside ink lines gets than the flat colour further out. 0 = no halo."),
    ("Whole panel|thick", "Line thickness", None, "Median line width (px). Browser = true weight."),
    ("Thing rock texture|match", "Detail kept (rock)", False, "Shape match with the original in the Thing's rock texture. 1 = identical."),
    ("Torch hatching|match", "Detail kept (Torch)", False, "Shape match with the original in the Torch's fine lines. 1 = identical."),
    ("Thing rock texture|black%", "Merged black (rock)", True, "Share of the rock area that is solid black."),
    ("Whole panel|dkring", "Ink bleed", True, "Dark fringe of ink spreading into the colour beside lines. Lower = less bleed."),
    ("Fine lines|rough", "Fine-line stair-steps", True, "Stair-steps on the thinnest lines (under 3.2px). Lower = smoother."),
    ("Fine lines|roping", "Fine-line pulsing", True, "How much the darkness of thin lines pulses along their length. Lower = steadier."),
    ("Faces|shape", "Face shape change", True, "How much of the ink in faces (mouth, eyelids, hair tips) moved or changed shape vs the original, %. Lower = more faithful."),
]


def align_all():
    """The page can sit a few pixels differently from round to round (round 3
    was 3px to the left). Find each capture's offset from the outline
    reference by phase correlation and save shifted copies in aligned/."""
    import numpy as np
    (CAP / "aligned").mkdir(exist_ok=True)
    gray = lambda f: np.asarray(Image.open(CAP / f).convert("L"), dtype=np.float64)
    ref = gray(SHOTS[1][1]); B = np.conj(np.fft.fft2(ref - ref.mean()))
    out = []
    for label, f, d in SHOTS:
        a = gray(f); R = np.fft.fft2(a - a.mean()) * B; R /= np.abs(R) + 1e-9
        dy, dx = np.unravel_index(np.fft.ifft2(R).real.argmax(), a.shape)
        dy -= a.shape[0] if dy > a.shape[0] // 2 else 0
        dx -= a.shape[1] if dx > a.shape[1] // 2 else 0
        rgb = np.asarray(Image.open(CAP / f).convert("RGB"))
        Image.fromarray(np.roll(np.roll(rgb, -dy, 0), -dx, 1)).save(CAP / "aligned" / f)
        if dy or dx:
            print(f"aligned {f}: shifted by ({-dx}, {-dy}) px")
        out.append((label, f"aligned/{f}", d))
    return out


def run_analysis():
    env = dict(os.environ, ANALYZE_CSV=str(CAP / "mega_latest.csv"), NO_PAIRS="1")
    args = [f"{label}={f}" for label, f, _ in SHOTS]
    subprocess.run([sys.executable, str(HERE / "analyze.py"), *args], env=env, check=True,
                   stdout=subprocess.DEVNULL)
    try:  # mega.csv may be open in Excel - then only mega_latest.csv is updated
        shutil.copyfile(CAP / "mega_latest.csv", CAP / "mega.csv")
    except PermissionError:
        print("mega.csv is open elsewhere; new numbers are in mega_latest.csv")
    with open(CAP / "mega_latest.csv", encoding="utf-8") as f:
        return {r["name"]: r for r in csv.DictReader(f)}


def chart_html(rows):
    desc = {label: d for label, _, d in SHOTS}
    names = [label for label, _, _ in SHOTS]
    parts = []
    for col, short, lower, expl in METRICS:
        vals = {n: float(rows[n][col]) for n in names if rows[n].get(col) not in (None, "", "nan")}
        order = sorted(vals, key=lambda n: vals[n], reverse=(lower is False)) if lower is not None else names
        vmax = max(vals.values()) or 1
        bars = []
        for rank, n in enumerate(order, 1):
            v = vals.get(n)
            if v is None:
                continue
            cls = "cur" if n.startswith("InkContour G4") else ("ref" if n == "Browser only" else ("ic" if "InkContour" in n or "Protected" in n or (n[:1] in "BC" and n[1:2].isdigit()) or n.startswith("LW") else ""))
            bars.append(f'<div class="row {cls}"><span class="rk">{rank if lower is not None else ""}</span>'
                        f'<span class="nm" title="{html.escape(desc[n])}">{html.escape(n)}</span>'
                        f'<span class="bar"><i style="width:{100 * v / vmax:.1f}%"></i></span><span class="v">{v:.3f}</span></div>')
        better = "lower is better" if lower else ("higher is better" if lower is False else "closest to Browser is most faithful")
        parts.append(f'<section><h2>{short} <small>{better}</small></h2><p>{html.escape(expl)}</p>{"".join(bars)}</section>')
    head = "".join(f"<th>{s}</th>" for _, s, _, _ in METRICS)
    body = "".join("<tr><td>" + html.escape(n) + "</td>" + "".join(
        f"<td>{float(rows[n][c]):.3f}</td>" if rows[n].get(c) not in (None, "", "nan") else "<td>-</td>" for c, _, _, _ in METRICS)
        + f"<td>{html.escape(desc[n])}</td></tr>" for n in names)
    return f"""<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Upscaling Mega Chart</title><style>
:root{{--bg:#fff;--fg:#1b1b1f;--mut:#666;--bar:#9aa4b8;--cur:#2f6fdb;--ic:#1f9d6b;--ref:#b8b8b8;--line:#e3e3e8}}
@media (prefers-color-scheme:dark){{:root{{--bg:#16171b;--fg:#e8e8ec;--mut:#9a9aa4;--bar:#59627a;--cur:#6b9cff;--ic:#3cc48e;--ref:#555;--line:#2c2d33}}}}
body{{background:var(--bg);color:var(--fg);font:14px/1.45 system-ui,sans-serif;margin:0;padding:16px;max-width:1100px}}
h1{{font-size:22px}} h2{{font-size:17px;margin:28px 0 4px}} small{{color:var(--mut);font-weight:normal}} p{{color:var(--mut);margin:0 0 8px}}
.row{{display:grid;grid-template-columns:2em minmax(120px,260px) 1fr 4.5em;gap:8px;align-items:center;margin:2px 0}}
.rk{{color:var(--mut);text-align:right}} .nm{{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}} .v{{text-align:right;font-variant-numeric:tabular-nums}}
.bar{{background:var(--line);height:12px;border-radius:3px;overflow:hidden}} .bar i{{display:block;height:100%;background:var(--bar)}}
.cur .bar i{{background:var(--cur)}} .ic .bar i{{background:var(--ic)}} .ref .bar i{{background:var(--ref)}} .cur .nm{{font-weight:600}}
.tw{{overflow-x:auto}} table{{border-collapse:collapse;font-size:12px;margin-top:12px}} td,th{{border-bottom:1px solid var(--line);padding:4px 6px;text-align:left;white-space:nowrap}}
</style></head><body><h1>Every upscaling version tested - Fantastic Four #323, Mantis panel</h1>
<p>All {len(names)} captures measured in one run, along the same ink outlines, against the same browser-only reference.
Blue = your current default, green = InkContour versions, grey = no upscaling. Hover a name for what it is.</p>
{"".join(parts)}<h2>All numbers</h2><div class="tw"><table><tr><th>Version</th>{head}<th>What it is</th></tr>{body}</table></div></body></html>"""


def sidebyside():
    crops = {"Mantis legs": (1000, 600, 1130, 1040), "Thing rock": (700, 590, 900, 830)}
    zoom, cols = 3, 8
    font = ImageFont.load_default()
    tiles = []
    for label, f, _ in SHOTS:
        im = Image.open(CAP / f).convert("RGB")
        parts = [im.crop(b).resize(((b[2] - b[0]) * zoom, (b[3] - b[1]) * zoom), Image.NEAREST) for b in crops.values()]
        w = sum(p.width for p in parts) + 6; h = max(p.height for p in parts) + 18
        t = Image.new("RGB", (w, h), "white"); d = ImageDraw.Draw(t); d.text((2, 2), label, fill="black", font=font)
        x = 0
        for p in parts:
            t.paste(p, (x, 18)); x += p.width + 6
        tiles.append(t)
    tw, th = tiles[0].size
    rows = (len(tiles) + cols - 1) // cols
    out = Image.new("RGB", (cols * (tw + 8), rows * (th + 8)), "white")
    for i, t in enumerate(tiles):
        out.paste(t, ((i % cols) * (tw + 8), (i // cols) * (th + 8)))
    out.save(CAP / "mega_sidebyside.png")
    return out.size


if __name__ == "__main__":
    SHOTS = align_all()
    rows = run_analysis()
    (CAP / "mega_chart.html").write_text(chart_html(rows), encoding="utf-8")
    print("chart:", CAP / "mega_chart.html")
    print("side-by-side:", CAP / "mega_sidebyside.png", sidebyside())
