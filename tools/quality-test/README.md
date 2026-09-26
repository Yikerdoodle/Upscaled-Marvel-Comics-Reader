# Upscaling quality test tools

Used to produce the numbers in [`../../UPSCALING-RANKINGS.md`](../../UPSCALING-RANKINGS.md).

## 1. Capture

Put a comic page fullscreen (F11) on the laptop screen, then in PowerShell:

    . .\capture-lib.ps1
    Save-Screen 'cap_Browser'                              # no upscaling
    Restart-MagpieInMode 'AntiJaggy 8.5x NoSharp'
    Capture-Upscaled 'cap_NoSharp'
    Restart-MagpieInMode 'AntiJaggy 8.5x InkContour G4'
    Capture-Upscaled 'cap_G4'
    Focus-Claude                                           # or just click back

Each capture restarts Magpie in the named mode (closing it first, since
Magpie reverts config edits made while it runs), turns upscaling on over
the comic, waits for it to render, saves a lossless PNG to `captures/`,
and turns upscaling off again. Hands off the laptop while it runs.
Captures refuse to run unless the fullscreen window's title matches
`$ComicTitle` in `capture-lib.ps1` (Fantastic Four #323), so a different
comic can't slip into the set by accident. To test another comic, set
`$script:ComicTitle` (and `$script:OutDir`, to keep its captures apart)
after dot-sourcing.
Capture every chain you want to compare in **one session** - numbers from
different sessions or lossy screenshots aren't directly comparable.

`captures/` is git-ignored: it holds screenshots of copyrighted comic art.

## 2. Measure

    ..\..\venv\Scripts\python.exe analyze.py Browser=cap_Browser.png NoSharp=cap_NoSharp.png G4=cap_G4.png

The first image should be the browser-only capture (flat colour areas,
fine detail and face shapes are compared against it); ink outlines are
found on the second image and traced identically in all of them. See the
docstring and each section's comment for what the numbers mean:

- **Outlines** (per region): stair-step roughness, edge width, line
  thickness, ink darkness, halo, dark ring (ink bleed), flat-colour noise.
- **Strict halo**: only edges beside truly flat colour.
- **Fine lines**: the thinnest traced lines - stair-steps, core darkness,
  and "roping" (darkness pulsing along the line).
- **Fine detail**: solid-black share, separate gaps/shapes and structure
  match in busy areas (the Thing's rock skin, the Torch's hatching).
- **Faces**: % of ink area in small features (mouths, eyelids, hair tips,
  lettering) that moved or changed shape vs the browser capture.

Regions come from a panel preset: `ANALYZE_PANEL=mantis` (default,
Fantastic Four #323) or `ANALYZE_PANEL=death` (Avengers #296, the hooded
man and red-haired woman). Add a preset to `PANELS` for another page.
`ANALYZE_CSV=file.csv` also writes every number to a CSV;
`NO_PAIRS=1` skips the pairwise difference table.

## 3. Compare everything ever captured

    ..\..\venv\Scripts\python.exe mega.py      # measure all captures in one run
    ..\..\venv\Scripts\python.exe score.py     # top two per category + overall ranking
    ..\..\venv\Scripts\python.exe flipbook.py  # full images to flip through

`mega.py` lines every capture up to the same pixel (a page can sit a few
pixels differently from round to round), measures them all in one run,
and writes `captures/mega_latest.csv` (copied to `mega.csv` unless that's
open elsewhere), `mega_chart.html` (ranked bars per measure plus a full
table) and `mega_sidebyside.png`. `score.py` ranks the versions per
category and by a weighted overall score (smooth, even outlines weigh
most). `flipbook.py` fills `captures/flipbook/` with every version
full-size, the unmodified browser capture between each, so arrow-keying
through them in an image viewer flips version -> original -> next.

    ..\..\venv\Scripts\python.exe linewidths.py Browser=cap_Browser.png G4=cap_G4.png

Width of every ink line in screen pixels (x0.18 = mm on the 15.6" 1080p
panel): finest 10%, median and heaviest 10%, per region.

## 4. Look

    ..\..\venv\Scripts\python.exe montage.py Browser=cap_Browser.png NoSharp=cap_NoSharp.png

Writes 5x nearest-neighbour zoomed side-by-sides (`all_legs.png`,
`all_neckline.png`) into `captures/`. Eyes beat metrics: the halo number
underrated a version whose halos were obvious in these crops, and the
face measure also counts intended smoothing as change - judge the final
pick by eye, full-size.
