# Marvel Unlimited high-fidelity reading

Everything lives on this drive (E:). Nothing on C: except a 4 KB Magpie
settings file that the app insists on keeping in AppData.

## Start reading

    E:\ComicUpscale\tools\START-COMIC-MODE.bat

Then: Firefox FULLSCREEN (F11) -> click Firefox -> Win+Shift+A.

Press the hotkey again to toggle off, so you can compare.

## The pipeline

    Firefox fullscreen      1920x1080 captured
      -> APISR 2x (AI)      3840x2160
      -> Lanczos fit        1920x1080   (supersampled)

Fullscreen is deliberate. Magpie captures the RENDERED WINDOW, so shrinking
Firefox would throw away Marvel's real pixels before the model ever sees
them. Shrinking only helps when the source is smaller than the area it is
drawn into - which is not the case here.

## Layout

    E:\ComicUpscale\
      Magpie\            the app; model.json and the .onnx files live here
      tools\             START-COMIC-MODE.bat, Set-ReaderWindow.ps1, probes
      models\            source .pth weights
      out\               converted .onnx (fp32 + fp16)
      venv\              python env for conversions
      convert.py         .pth -> Magpie-ready .onnx

## Current model

    2x_APISR_RRDB_fp16.onnx     ESRGAN RRDB-6B, 4,472,963 params, 2x, fp16

APISR is built around restoring hand-drawn lines damaged by compression,
which matches the defects in Marvel's WebP files. RRDB-6B (6 blocks, not
the usual 23) is what keeps it inside 4 GB of VRAM at 1080p input.

The DAT and GRL APISR variants are stronger but use architectures Magpie
cannot load. Magpie supports ESRGAN, SPAN and WAIFU2X only.

To revert to the fast lightweight model:
  in E:\ComicUpscale\Magpie\, replace model.json with model.json.animejanai-backup

## Swapping in a different model

1. Download any ESRGAN / SPAN / WAIFU2X .pth from https://openmodeldb.info
   into E:\ComicUpscale\models\
2. Edit the SRC path at the top of convert.py
3. Run:
      E:\ComicUpscale\venv\Scripts\python.exe E:\ComicUpscale\convert.py
4. Copy the resulting fp16 .onnx into E:\ComicUpscale\Magpie\
5. Point model.json at it (keep "scale" matching the model's real factor)

convert.py enforces Magpie's requirements and will refuse rather than
produce a file that silently fails: dynamic [-1,3,-1,-1] NCHW shapes,
matching input/output dtypes, and a verified integer scale factor.

## Magpie settings that matter

  scalingMode = Lanczos    Do NOT use ACNet/Anime4K here. Those add their
                           own 2x on top of the model's 2x, giving 4x total
                           (7680x4320) which will exhaust 4 GB of VRAM.
  duplicateFrameDetectionMode = 1
                           Static panels are not re-rendered, so a heavy
                           model only costs a pause on each panel turn.
  allowScalingMaximized = true

Config file: C:\Users\Work\AppData\Local\Magpie\config\v2\config.json
A .backup of the original sits beside it.

## If the E: drive is unplugged

None of this runs. Magpie, the models and the venv are all here. That is
the tradeoff for keeping C: clear.

## Known unknown

We never established what resolution Marvel actually serves inside the
reader - the probe scripts in tools\ kept measuring the outer page rather
than the reader frame. If you ever want to settle it, run tools\probe-v3.js
in the console with DevTools undocked AND the console pointed at the
reader's iframe via the DevTools frame picker.
