# Marvel Unlimited high-fidelity reading setup

Hardware this was tuned for: ASUS TUF FX505GT, i5-9300H, GTX 1650 4GB,
1920x1080 panel at **150% display scaling**, Optimus (panel driven by Intel UHD 630).

## What is already done

- `Magpie-onnx/` — Magpie onnx-preview2 (DirectML build), extracted and ready.
  Downloaded from the official repo:
  https://github.com/Blinue/Magpie/releases/download/onnx-preview2/Magpie-onnx-preview2-x64.zip
  SHA256 80A1D5D802C15C8BE671829B0D36711843CCF4ADA40C4BE8843512E960725B74
- `Magpie-onnx/model.json` — written, pointing at the bundled model:
      { "path": "2x_AnimeJaNai_HD_V3_UltraCompact_425k-fp16.onnx",
        "scale": 2, "backend": "directml" }
  The build ships this model already. It is 2x, UltraCompact (425k params,
  built for real-time), fp16, and trained on compression-damaged line art —
  which is the right profile for a GTX 1650 with no tensor cores.
- GPU preference — Magpie.exe is pinned to the GTX 1650 in the registry
  (HKCU\Software\Microsoft\DirectX\UserGpuPreferences, GpuPreference=2).
  This matters: your panel hangs off the Intel iGPU, and DirectML landing
  there would be far slower. Undo by deleting that value.
- `Set-ReaderWindow.ps1` — DPI-aware exact window sizer.
- `probe-source-resolution.js` — measures what Marvel actually serves you.

DirectML.dll and onnxruntime.dll are bundled in `Magpie-onnx/third_party/`.
The 973 MB TensorRT extra is NOT needed and was not downloaded.

## What you need to do

### 1. Measure (needs your Marvel login — I can't do this part)

Open a comic in Firefox, press F12, paste the whole of
`probe-source-resolution.js` into the Console, Enter.

Read the `source px` and `bits/px` figures. That tells us the real ceiling.

### 2. Decide your display scaling

Run the probe at your current 150%, then set Windows scaling to 100%
(Settings > System > Display > Scale), reload, run it again.

- Bigger `source px` at 150%  -> Marvel serves HiDPI assets. Stay at 150%.
- Identical                   -> no HiDPI. Use 100% for a roomier layout.

This is the only step in the whole setup that can add REAL pixels rather
than reconstructed ones, so it is worth being certain about.

### 3. Size the window

    powershell -ExecutionPolicy Bypass -File Set-ReaderWindow.ps1 -Width 960 -Height 540 -Center

960x540 device px = exact 2x to your 1920x1080 screen, matching the model's
native 2x with no secondary resampling. This is the clean configuration.

At 150% scaling that window reports as a 640x360 CSS viewport, which may be
narrow enough that Marvel's reader drops to a mobile layout. If it does,
either switch to 100% scaling or accept a non-integer factor.

### 4. Run Magpie

    Magpie-onnx\Magpie.exe

Because `model.json` exists, the ONNX model is applied automatically, BEFORE
the scaling mode's effect chain. There is no UI toggle for this.

Therefore: pick a MINIMAL scaling mode (Lanczos or Bicubic). The model has
already done the exact 2x to 1920x1080, so anything heavier just resamples
an image that is already at target resolution. Do not stack Anime4K or FSR
on top — you would be sharpening the model's output for no reason.

Then: focus the Firefox window, press Magpie's scale hotkey (check Settings
for the current binding), and read with the arrow keys.

## Expectations

Marvel serves roughly 1050x1500 at ~300 KiB, about 0.16 bits/px. Your enemy
is compression damage more than missing resolution. This setup will remove
aliasing and give clean, smooth linework. It cannot add detail that was
never encoded — it reconstructs plausible ink, it does not reveal real ink.

## Disk warning

C: is at 1% free (6.0 GB of 442.8 GB). Windows wants far more headroom than
that, and ONNX Runtime / DirectML write kernel caches to disk — low space can
make this setup fail in confusing ways. E: has 529 GB free; put anything
further there.
