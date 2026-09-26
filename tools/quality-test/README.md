# Upscaling quality test tools

Used to produce the numbers in [`../../UPSCALING-RANKINGS.md`](../../UPSCALING-RANKINGS.md).

## 1. Capture

Put a comic page fullscreen (F11) on the laptop screen, then in PowerShell:

    . .\capture-lib.ps1
    Save-Screen 'cap_Browser'                              # no upscaling
    Restart-MagpieInMode 'AntiJaggy 8.5x NoSharp'
    Capture-Upscaled 'cap_NoSharp'
    Restart-MagpieInMode 'AntiJaggy 8.5x NNEDI3x2+CASx2'
    Capture-Upscaled 'cap_NNEDI3x2+CASx2'
    Focus-Claude                                           # or just click back

Each capture restarts Magpie in the named mode (closing it first, since
Magpie reverts config edits made while it runs), turns upscaling on over
the comic, waits for it to render, saves a lossless PNG to `captures/`,
and turns upscaling off again. Hands off the laptop while it runs.
Capture every chain you want to compare in **one session** - numbers from
different sessions or lossy screenshots aren't directly comparable.

`captures/` is git-ignored: it holds screenshots of copyrighted comic art.

## 2. Measure

    ..\..\venv\Scripts\python.exe analyze.py Browser=cap_Browser.png NoSharp=cap_NoSharp.png NNEDI3=cap_NNEDI3.png

The first image should be the browser-only capture (used to find flat
colour areas); ink outlines are found on the second image and traced
identically in all of them. Regions (Mantis's legs/neckline, whole panel)
are hard-coded for Fantastic Four #323 in `analyze.py` - adjust `REGIONS`
for another page. See the docstring for what each metric means.

## 3. Look

    ..\..\venv\Scripts\python.exe montage.py Browser=cap_Browser.png NoSharp=cap_NoSharp.png

Writes 5x nearest-neighbour zoomed side-by-sides (`all_legs.png`,
`all_neckline.png`) into `captures/`. Eyes beat metrics: the halo number
underrated a version whose halos were obvious in these crops.
