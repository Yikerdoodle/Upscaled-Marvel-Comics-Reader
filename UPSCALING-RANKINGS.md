# Upscaling rankings for pre-2000s Marvel comics

Which Magpie scaling chains look best on **older Marvel Unlimited comics**
(roughly 1960s-1990s), best to worst. These books are digital
restorations: hard-edged black line art at modest resolution, flat colour,
JPEG-compressed. That's a very different problem from modern digitally
drawn comics, and it's why the winner here is not a typical "sharpest
upscaler" pick.

Tested on a 1920x1080 laptop screen (15.6", 150% scaling), GTX 1650,
Magpie onnx-preview2, on two panels: Fantastic Four #323 (Mantis and the
Thing walking) and Avengers #296 (hooded man with a yellow face,
red-haired woman - the panel where moved details were easiest to see).
The upscaling chains are 8.5x total (the most a 1920px-wide source can
reach under Direct3D 11's 16384px texture limit) and are fitted back to
the screen, so this is supersampling, not a bigger picture.

## Ranking

"Your eye" = judged by the reader, live on the comic or flipping between
full-size captures. That's the deciding evidence; the numbers explain why.

| Rank | Chain (Magpie mode name) | Verdict | Basis |
|---|---|---|---|
| **1** | **AntiJaggy 8.5x InkContour G4** *(laptop default)* | "Basically perfect": smooth, even outlines, near-black ink, and small features (mouths, eyelids, hair tips) keep their drawn shape | Your eye (beat #2 in a full-image flip) + measured |
| 2 | ★ Liked 2: InkContour Protected k0.8 | Slightly smoother still, but small strokes come out bolder and rounder - details move | Your eye + measured |
| 3 | InkContour s3 black (first InkContour you saw) | Liked the direction; merges dense detail (the Thing's rock skin, hair strands, fine sleeve lines) into black | Your eye + measured |
| 4 | AntiJaggy 8.5x NNEDI3x2+CASx2 *(previous default)* | Crisp, stair-steps small and even, but still visible | Your eye + measured |
| 5 | AntiJaggy 8.5x NNEDI3+CAS | Nearly as good as #4; very slightly rougher lines | Your eye + measured |
| 6 | AntiJaggy 8.5x NNEDI3 | The first breakthrough: steps become small and even; a little soft | Your eye + measured |
| 7 | B6 (NNEDI3 > InkContour > Anime4K) | Very smooth, but not sharp enough and too much ink bleed | Your eye + measured |
| 8 | AntiJaggy 8.5x NNEDI3x2+CASx2 1.0 | Crispest of the NNEDI3 family, but halos are obviously visible | Your eye + measured |
| 9 | AntiJaggy 8.5x NoSharp / PreAA *(earlier default)* | Sharp, clean colour, but sharpens the source's stair-steps so they stand out | Your eye + measured |
| 10 | AntiJaggy 8.5x Sharp / Sharp-Light (LumaSharpen) | Visible black ink bleeding into colour | Your eye |
| 11 | Custom "DenoiseLineProtect" shader | Ink bled into colour areas (measured bleed 6.8, the worst of all) | Your eye + measured |
| 12 | APISR (GAN ONNX model) | Bright halos / ringing around ink lines (measured halo 11.6; every other version 3.3 or less) | Your eye + measured |
| 13 | CuNNy chains | Disliked on sight | Your eye |

### Measured only (not judged by eye)

103 captures (about 90 different chains and settings) were measured in total. The notable ones:

| Chain | What the numbers say |
|---|---|
| AntiJaggy MAX / C3 (MAX rebuilt at 8.5x) | Best detail and face faithfulness of the sharp chains (Anime4K + SMAA + FXAA), but grey ink (25-27) and only average stair-steps |
| C5 (NNEDI3 > InkContour > FXAA > Anime4K) | Among the smoothest (0.111) with the fewest halos, but soft like B6 |
| RAVU x2 | Smoother than NNEDI3 but soft, with 3x the halo |
| NNEDI3 nns256 (biggest network), 3 NNEDI3 passes | No visible difference from nns128 x2 |
| NNAA (NNEDI3 anti-alias round trip) | Crisper, but loses detail |
| AnimeJaNai (ONNX model) | Soft, and its stair-steps are as bad as the browser's |
| Lanczos, FSR, FSRCNNX, CuNNy, ACNet, Anime4K, "Smooth" modes | Barely change the page: as soft and stepped as no upscaling |
| Stronger InkContour smoothing (4) | Thins and fades lines; with detail protection it even ends up *less* smooth, because more lines are protected |
| InkContour line thinning | Works (every line thinned in proportion to its own width), but rejected: thinner lines on a zoomed panel no longer match the printed page's proportions |

## Why InkContour G4 wins on these comics

- **NNEDI3 fills in new pixels by following the direction of the line**,
  so a stepped diagonal comes out as a smooth line - but some small, even
  steps remain, because they're drawn into Marvel's scan.
- **InkContour then treats the outline like a vectorizer would.** A
  blurred copy's half-way level follows the averaged outline, not its
  steps. The shader redraws each ink edge along that path, from the local
  ink colour to the local fill colour, so outlines become smooth curves.
  It only blends colours already beside the edge, so it can't make halos.
- **Three guards keep it from changing the drawing:** detail protection
  (skip spots where smoothing would merge nearby shapes, like rock
  texture or hatching), fine features left exactly as NNEDI3 drew them,
  and curve protection (original pixels kept wherever an outline bends
  tighter than 6px: mouth and eyelid lines, stroke ends, hair tips,
  lettering). Without them, smoothing rounded off and moved small strokes.
- **Only solid ink is deepened towards black.** Darkening half-dark pixels
  too made shading and thin gaps merge into solid black.
- **CAS** (AMD Contrast Adaptive Sharpening) restores edge contrast after
  each NNEDI3 doubling; at 0.5 it doesn't overshoot into halos. At 1.0 it
  does.

## The measurements

Lossless screen captures, ink outlines traced automatically at sub-pixel
precision, every capture aligned to the same pixel and measured in one
run (`tools/quality-test/mega.py`).

**Fantastic Four #323, Mantis panel** (94 outlines, 6,723 rows):

| Chain | Stair-steps ↓ | Edge width ↓ | Ink (0 = black) | Halo ↓ | Ink bleed ↓ | Rock detail kept | Fine-line steps ↓ | Face shape change ↓ |
|---|---|---|---|---|---|---|---|---|
| Browser only | 0.179 | 1.52 | 24 | 2.39 | 3.20 | 1.000 | 0.233 | 0 |
| **InkContour G4** | **0.126** | 1.06 | **4** | 0.70 | 3.00 | 0.971 | 0.188 | 9.7 |
| Protected k0.8 | 0.122 | 1.01 | 4 | 0.92 | 2.92 | 0.962 | 0.181 | 11.2 |
| InkContour s3 black | 0.117 | 1.02 | 4 | 0.94 | 1.86 | 0.956 | 0.150 | 13.3 |
| NNEDI3x2+CASx2 | 0.159 | 0.91 | 21 | 0.89 | 2.47 | 0.974 | 0.202 | 8.4 |
| NNEDI3+CAS | 0.161 | 0.95 | 22 | 0.49 | 2.44 | 0.987 | 0.199 | 7.0 |
| NNEDI3 | 0.156 | 1.03 | 26 | 0.41 | 2.32 | 0.988 | 0.195 | 7.1 |
| NNEDI3x2+CASx2 1.0 | 0.160 | 0.86 | 16 | 2.23 | 2.56 | 0.972 | 0.203 | 8.7 |
| B6 | 0.117 | 1.35 | 8 | 0.50 | 2.55 | 0.979 | 0.172 | 9.8 |
| AntiJaggy MAX | 0.136 | 1.05 | 25 | 0.55 | 2.26 | 0.998 | 0.177 | 7.2 |
| NoSharp | 0.190 | 0.74 | 26 | 0.49 | 2.29 | 0.997 | 0.239 | 7.4 |
| DenoiseLineProtect | 0.192 | 0.75 | 27 | 0.73 | 6.80 | 0.996 | 0.268 | 10.4 |
| APISR | 0.207 | 0.67 | 0 | 11.60 | 3.24 | 0.985 | 0.297 | 10.6 |

**Avengers #296** (hooded man and red-haired woman):

| Chain | Stair-steps ↓ | Edge width ↓ | Ink | Halo ↓ | His mouth | His eye | Her hair | Lettering | Face shape change ↓ |
|---|---|---|---|---|---|---|---|---|---|
| Browser only | 0.181 | 1.23 | 5 | 3.04 | 0 | 0 | 0 | 0 | 0 |
| **InkContour G4** | **0.148** | 1.00 | **1** | 1.24 | 10.4 | 9.1 | 14.3 | 10.5 | 11.2 |
| Protected k0.8 | 0.139 | 1.05 | 1 | 1.01 | 10.9 | 10.1 | 15.5 | 10.8 | 11.9 |
| NNEDI3x2+CASx2 | 0.178 | 0.82 | 6 | 1.65 | 8.3 | 6.8 | 10.7 | 9.7 | 9.0 |
| AntiJaggy MAX | 0.181 | 1.01 | 8 | 0.74 | 6.1 | 4.9 | 10.1 | 8.5 | 7.4 |

- **Stair-steps:** how far each traced edge strays from a smooth curve
  fitted through it (px). Lower is smoother.
- **Edge width:** distance over which an edge goes from 20% to 80% of the
  ink-to-paper step (px). Lower is crisper. About 1px is the least that
  still lets a 1080p screen draw a diagonal smoothly.
- **Halo:** how much brighter the colour right beside ink lines gets than
  the flat colour further out, on edges beside truly flat colour. The
  browser's value is JPEG ringing in Marvel's own scan.
- **Ink bleed:** dark fringe of ink spreading into the colour beside lines.
- **Rock detail kept:** texture-scale shape match with the browser capture
  in the Thing's rock skin (1 = the same shapes).
- **Face shape change:** % of ink area in small features that moved,
  appeared or vanished compared with the browser capture. It also counts
  intended smoothing of stair-steps as change, so it overstates the
  difference - the zoomed crops showed G4's small features matching the
  previous default closely.

Caveats: two panels, one screen size. The weighted overall score in
`score.py` ranks G4 mid-table because it rewards closeness to the soft
browser image in several categories; the reader's eye, full-size,
decided.

## Reproducing

The test tools are in `tools/quality-test/` (see its README). They switch
Magpie between chains, capture the upscaled screen losslessly, measure
everything above, and build full-size flipbooks for comparing by eye.

## The winning chain

    Firefox fullscreen, 1920x1080 captured
      -> Anime4K_Denoise_Bilateral_Mode (intensitySigma 0.22)
      -> Anime4K_Restore_Soft_UL
      -> NNEDI3_nns128_win8x4 (2x)
      -> InkContour (smoothing 3, edge width 3, ink darken 0.8 on solid
         ink only, detail protection 0.8, fine features untouched,
         curve protection 6px)
      -> CAS (sharpness 0.5)
      -> NNEDI3_nns128_win8x4 (2x)  -> CAS (sharpness 0.5)
      -> Lanczos 2.125x
      = 8.5x (16320x9180) -> fitted back to 1920x1080
