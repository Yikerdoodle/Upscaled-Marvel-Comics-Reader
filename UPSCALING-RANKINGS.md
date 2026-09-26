# Upscaling rankings for pre-2000s Marvel comics

Which Magpie scaling chains look best on **older Marvel Unlimited comics**
(roughly 1960s-1990s), best to worst. These books are digital
restorations: hard-edged black line art at modest resolution, flat colour,
JPEG-compressed. That's a very different problem from modern digitally
drawn comics, and it's why the winner here is not a typical "sharpest
upscaler" pick.

Tested on a 1920x1080 laptop screen (150% scaling), GTX 1650, Magpie
onnx-preview2. Every chain is 8.5x total (the most a 1920px-wide source
can reach under Direct3D 11's 16384px texture limit) and is fitted back to
the screen, so this is supersampling, not a bigger picture.

## Ranking

"Your eye" = judged by the reader on the actual comic or zoomed
side-by-sides. That's the deciding evidence. The numbers explain why.

| Rank | Chain (Magpie mode name) | Verdict | Basis |
|---|---|---|---|
| **1** | **AntiJaggy 8.5x NNEDI3x2+CASx2** *(current default)* | Smooth, even lines with tiny stair-steps, still crisp, barely any halos | Your eye + measured |
| 2 | AntiJaggy 8.5x NNEDI3+CAS | Nearly as good; very slightly rougher lines | Your eye + measured |
| 3 | AntiJaggy 8.5x NNEDI3 | The breakthrough: steps become small and even; a little soft | Your eye + measured |
| 4 | AntiJaggy 8.5x NNEDI3x2+CASx2 1.0 | Crispest of the NNEDI3 family, but halos are obviously visible | Your eye + measured |
| 5 | AntiJaggy 8.5x NoSharp *(previous default)* | Sharp, clean colour, but sharpens the source's stair-steps so they stand out | Your eye + measured |
| 5 (tie) | AntiJaggy 8.5x PreAA | No visible difference from NoSharp (3% smoother on paper) | Your eye + measured |
| - | *Browser only (no upscaling)* | Reference: soft and blurry, which hides the steps | Your eye + measured |
| 6 | AntiJaggy 8.5x Sharp / Sharp-Light (LumaSharpen) | Visible black ink bleeding into colour | Your eye |
| 7 | Custom "DenoiseLineProtect" shader | Ink bled into colour areas, worse than no denoise | Your eye |
| 8 | APISR (GAN ONNX model) | Bright halos / ringing around ink lines | Your eye |
| 9 | CuNNy chains | Disliked on sight | Your eye |

### Measured only (not judged by eye)

| Chain | What the numbers say |
|---|---|
| NNEDI3>Restore Strong / NNEDI3>Restore | Running Anime4K's Restore *after* NNEDI3 makes it **softer** (edge width 1.2-1.3px): Restore reads NNEDI3's smooth edges as blur to keep |
| NNEDI3>Restore x2 | As crisp as NoSharp, but most of the stair-steps come back |
| NNEDI3+CAS late, NNEDI3+CAS1.0 | CAS at 4K resolution, or at full strength, after an Anime4K upscale: slightly rougher than doing both doublings with NNEDI3 |
| NNEDI3x2+CAS end | Smoothest of all (0.152) but softer than CAS after each doubling |

## Why NNEDI3 + CAS wins on these comics

- **Anime4K's upscalers sharpen edges wherever they find them,** and the
  source's stair-steps count as edges. NoSharp does exactly its job: the
  outlines actually got *less* wobbly than in the browser, but twice as
  sharp, so the remaining steps became visible.
- **NNEDI3 fills in new pixels by following the direction of the line**
  around them, so a stepped diagonal comes out as a smooth line. It adds
  no edge contrast of its own, which is why it alone is a little soft.
- **CAS** (AMD Contrast Adaptive Sharpening) restores edge contrast but
  limits itself to the local brightness range, so at 0.5 it doesn't
  overshoot into visible halos. At 1.0 it does.
- Using **NNEDI3 for both 2x steps** (instead of NNEDI3 then Anime4K)
  gives the same crispness with smoother lines and smaller halos: a
  second Anime4K upscale re-sharpens the steps.
- Pre-smoothing at the original resolution (SMAA "PreAA") can't help: the
  steps are a sub-pixel *path* problem, wider than SMAA's reach.

## The measurements

Lossless screen captures of the same panel (Fantastic Four #323, Mantis),
ink outlines traced automatically at sub-pixel precision, whole panel
(94 outlines, 6,564 rows). All chains captured in one session.

| Chain | Staircase roughness (px) ↓ | Edge width (px) ↓ | Light halo ↓ | Ink core (lower = blacker) | Line thickness (px) |
|---|---|---|---|---|---|
| Browser only | 0.176 | 1.51 | 12.4 | 24 | 3.99 |
| NoSharp | 0.190 | 0.74 | 4.4 | 26 | 4.02 |
| NNEDI3 | 0.153 | 1.04 | 6.6 | 26 | 4.02 |
| NNEDI3+CAS | 0.158 | 0.97 | 6.3 | 22 | 4.00 |
| NNEDI3+CAS1.0 | 0.162 | 0.93 | 6.4 | 20 | 3.99 |
| **NNEDI3x2+CASx2** | **0.155** | **0.93** | **5.3** | **21** | **4.02** |
| NNEDI3x2+CASx2 1.0 | 0.156 | 0.89 | 5.5 | 16 | 4.00 |
| NNEDI3x2+CAS end | 0.152 | 0.98 | 5.4 | 24 | 4.04 |

- **Staircase roughness:** how far each traced edge strays from a smooth
  curve fitted through it. Lower is smoother.
- **Edge width:** distance over which an edge goes from 20% to 80% of the
  ink-to-paper step. Lower is crisper.
- **Light halo:** brightest point just outside an ink edge minus the plain
  colour further out, in brightness levels out of 255. The browser's high
  value is JPEG ringing in Marvel's own source, which every upscaler
  reduces.
- The halo metric **underrated** the full-strength CAS version (5.5 vs 5.3)
  compared with how visible its halos are to the eye. Trust the eye test.

Caveats: one panel, one screen size. Chains were compared within the same
capture session, since numbers from different sessions (or lossy
screenshots) aren't directly comparable.

## Reproducing

The test tools are in `tools/quality-test/` (see its README). They switch
Magpie between chains, capture the upscaled screen losslessly, and
compute the table above.

## The winning chain

    Firefox fullscreen, 1920x1080 captured
      -> Anime4K_Denoise_Bilateral_Mode (intensitySigma 0.22)
      -> Anime4K_Restore_Soft_UL
      -> NNEDI3_nns128_win8x4 (2x)  -> CAS (sharpness 0.5)
      -> NNEDI3_nns128_win8x4 (2x)  -> CAS (sharpness 0.5)
      -> Lanczos 2.125x
      = 8.5x (16320x9180) -> fitted back to 1920x1080

It also needs noticeably less GPU memory than the old Anime4K-only chain,
which failed to start at all when the PC was low on memory.
