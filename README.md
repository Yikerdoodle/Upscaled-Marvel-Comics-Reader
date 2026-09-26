# Marvel Unlimited high-fidelity reading

Everything lives on this drive (E:), including Magpie itself - see
"Where the live config actually lives" below for the one exception.

## Start reading

    E:\ComicUpscale\tools\START-COMIC-MODE.vbs

Double-click it. Nothing visible pops up - no console window, no Magpie
window, nothing in the taskbar. Magpie's tray icon still appears near the
clock as usual; right-click it for Settings or Exit.

Then: Firefox **fullscreen** (F11) -> click the Firefox window ->
**Win+Shift+A** to toggle upscaling on/off, so you can compare.

Before starting Magpie, the launcher checks Magpie is on the best laptop
settings (the chain below, GPU pinned to the GTX 1650, no AI model) and
quietly fixes anything that isn't - e.g. after 4K TV mode switched it.
Other favourites stay in Magpie's mode list as "★ Liked ..." to try by
hand.

(`START-COMIC-MODE.bat` still exists and does the same launch, but shows
a console window with instructions text. The .vbs is silent.)

**Reading on the living-room TV** instead: `tools\Read Marvel Comics
Upscaled - 4K TV Mode.vbs` - see [`4K-TV-Setup/README.md`](4K-TV-Setup/README.md).

## Which upscaling looks best

See **[UPSCALING-RANKINGS.md](UPSCALING-RANKINGS.md)**: every chain tried
on older Marvel comics, ranked best to worst, with the measurements and
the reasons.

## The pipeline - shader chain, not an ONNX model

The active approach is a chain of Magpie's built-in real-time shaders,
**not** the ONNX model this project started with. The GAN-trained APISR
model (still present in `Magpie/`) produced visible halo/ringing artifacts
on Marvel's already-clean remastered line art - it's built to *add*
contrast, which shows up as a bright rim around ink lines. Rejected on
sight; not used in the current recipe.

Current chain ("AntiJaggy 8.5x InkContour G4" - see
`magpie-scaling-modes-snapshot.json` for the exact JSON):

    Firefox fullscreen (1920x1080 captured)
      -> Denoise (Anime4K Bilateral Mode, intensitySigma 0.22)
      -> Restore (Anime4K_Restore_Soft_UL - largest non-GAN line-restore
                   network Magpie ships)
      -> NNEDI3 2x (nns128, win8x4)
      -> InkContour (custom shader, Magpie/effects/Custom/InkContour.hlsl)
      -> CAS (sharpness 0.5)
      -> NNEDI3 2x                  -> CAS (sharpness 0.5)
      -> Lanczos 2.125x (explicit scale, cheap final step)
      = 8.5x total supersample -> 16320x9180 -> fit back to 1920x1080

Why NNEDI3 + CAS rather than Anime4K's upscalers: these old pages have
hard, slightly stair-stepped line art, and Anime4K's upscalers sharpen
those steps along with everything else. NNEDI3 interpolates *along* each
line's direction, so the steps become small and even; CAS then restores
edge contrast without overshooting into halos.

InkContour is a small real-time "vectorizer" for the ink outlines: it
finds the smooth path each outline follows (the half-way level of a
blurred copy) and redraws the edge along it, from the local ink colour
to the local fill colour, with solid ink deepened towards black. Settings
in this chain: smoothing 3px, edge width 3px (at 2x), and three guards
that keep it from changing the drawing - detail protection (skip spots
where smoothing would merge nearby shapes), fine features left untouched,
and curve protection (original pixels kept wherever an outline bends
tighter than 6px: mouths, eyelids, stroke ends, hair tips, lettering).
Full reasoning and numbers in [UPSCALING-RANKINGS.md](UPSCALING-RANKINGS.md).

Fullscreen is deliberate. Magpie captures the *rendered window*, so
shrinking Firefox would throw away Marvel's real pixels before any shader
sees them - the opposite of what an early version of this project did.

Why 8.5x and not more: Direct3D 11 caps a single texture at 16384px per
side. 1920 * 8.53 = 16384 exactly, so **8.5x is the hard mathematical
ceiling for this screen, on any GPU** - not a VRAM limit, a fixed API
limit. Confirmed by actually hitting it: a 10x attempt (19200px wide)
failed instantly with `CreateTexture2D` HRESULT 0x80070057 ("parameter is
incorrect"), logged in `Magpie/logs/`. 8.5x runs with ~64px of margin
under that wall.

Memory: if the PC is nearly out of memory (RAM + page file), heavy chains
can fail to start with `CreateTexture2D` HRESULT 0x8007000E (out of
memory) in Magpie's log, even with the GPU's own memory free. The NNEDI3
chain is lighter than the old Anime4K-only one, but closing big browser
tabs or `wsl --shutdown` helps if upscaling silently won't start.

Why this over more resolution or a bigger model: two specific defects
kept surfacing on close, parallel thin lines (crosshatching, shading) -
denoise merging them into one blob, and FXAA smearing fine repeated
texture. Both are why denoise is deliberately weak and FXAA is absent
from the chain, even though both would normally be "quality" settings to
turn up.

## Layout

    E:\ComicUpscale\
      Magpie\                     the app (onnx-preview2 build)
        effects\                    bundled HLSL shaders (SMAA, Anime4K, ...)
        *.onnx, model.json.*        both currently INACTIVE - see below
      tools\                       launchers + diagnostic probes
        quality-test\                capture + measure upscaling chains
      4K-TV-Setup\                 Sunshine / virtual 4K display setup for the TV
      UPSCALING-RANKINGS.md        which chains look best, and why
      models\                      source .pth weights (for convert.py)
      out\                         converted .onnx (fp32 + fp16)
      vector-test\, skeleton-test\  offline vectorization experiments
      venv\                        python env for convert.py (gitignored)
      convert.py, verify_chain.py
      magpie-scaling-modes-snapshot.json   copy of the live config - see below

## Where the live config actually lives

Every scaling mode (all the "AntiJaggy" chains, denoise values, etc.)
lives in Magpie's own settings file, **outside this folder entirely**:

    C:\Users\Work\AppData\Local\Magpie\config\v2\config.json

`magpie-scaling-modes-snapshot.json` in this repo is a **copy** for
reference and version history. Editing it does nothing to the running
app - Magpie only ever reads the AppData path above. If you change
scaling modes through Magpie's own UI, re-copy that file into the repo
to keep the snapshot current.

Magpie also rewrites its entire config on exit, so any script-based edit
to it must happen while Magpie is **closed** - editing it live gets
silently overwritten the next time Magpie exits.

## If you want the ONNX model instead of the shader chain

The APISR conversion still works and is still in `Magpie/`, just not
wired up:

    2x_APISR_RRDB_fp16.onnx     ESRGAN RRDB-6B, 4,472,963 params, 2x, fp16

RRDB-6B (6 blocks, not the usual 23) is what kept it inside 4GB VRAM at
1080p input. To use it: close Magpie, rename `model.json.APISR-disabled`
back to `model.json`, pick a scaling mode with no other upscale effects
in the chain (the model already does 2x - stacking Anime4K/ACNet on top
means 4x total, which risks exhausting VRAM).

Expect the halo/ringing artifacts mentioned above if you do this on
already-clean art. It suits genuinely low-quality or heavily compressed
source images better than Marvel's current remasters.

## Swapping in a different model

1. Download any ESRGAN / SPAN / WAIFU2X `.pth` from
   https://openmodeldb.info into `models\`
2. Edit the `SRC` path at the top of `convert.py`
3. Run: `venv\Scripts\python.exe convert.py`
4. Copy the resulting fp16 `.onnx` into `Magpie\`
5. Point `model.json` at it (`scale` must match the model's real factor)

`convert.py` enforces Magpie's requirements and refuses rather than
produce a file that silently fails: dynamic `[-1,3,-1,-1]` NCHW shapes,
matching input/output dtypes, and a verified integer scale factor.
`verify_chain.py` separately checks a scaling mode's effect files exist
and computes its resulting resolution before you try running it.

## If the E: drive is unplugged

None of this runs - Magpie, the models, and the venv are all here. That's
the deliberate tradeoff for keeping C: clear.

## Known unknown

Never established what resolution Marvel Unlimited actually serves
inside the reader itself. The probe scripts in `tools\` kept measuring
the outer marvel.com page - the reader runs in an iframe, and
`document.querySelectorAll` doesn't cross into it. At real reading scale
the practical result (8x chain, denoise 0.12-0.16) reads as clean with no
visible artifacts, so this was never blocking, just unresolved.
