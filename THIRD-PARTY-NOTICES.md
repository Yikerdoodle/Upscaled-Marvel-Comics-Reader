# Third-party software and credits

This repository bundles, or builds on, other people's work. All credit
and rights belong to their authors; each is used under its own license.
Where this repo includes binaries or installers, the source code is
available from the upstream projects linked here.

| Project | What's used here | License | Source |
|---|---|---|---|
| Magpie (Blinue) | The real-time upscaler app in `Magpie/` and `Magpie-onnx-preview2-x64.zip` | GPL-3.0 | https://github.com/Blinue/Magpie |
| Anime4K (bloc97) | Denoise / Restore / Upscale shaders, ported in Magpie's `effects/Anime4K/` | MIT | https://github.com/bloc97/Anime4K |
| NNEDI3 shaders (hauuau/magpie-prescalers) | `effects/NNEDI3/` - the edge-directed doubler in the current chain | GPL-3.0-or-later (per file header) | https://github.com/hauuau/magpie-prescalers |
| AMD FidelityFX CAS | `effects/CAS/` sharpening, shipped with Magpie | See upstream | https://github.com/GPUOpen-Effects/FidelityFX-CAS |
| SMAA | `effects/SMAA/`, shipped with Magpie | See upstream | https://github.com/iryoku/smaa |
| ONNX Runtime (Microsoft) | `Magpie/third_party/onnxruntime.dll` | MIT | https://github.com/microsoft/onnxruntime |
| DirectML (Microsoft) | `Magpie/third_party/DirectML.dll` | Microsoft DirectML redistributable license | https://github.com/microsoft/DirectML |
| Sunshine (LizardByte) | Installer in `4K-TV-Setup/` for streaming to the TV | GPL-3.0 | https://github.com/LizardByte/Sunshine |
| Virtual Display Driver (VirtualDrivers / MikeTheTech) | VDD Control app and signed driver in `4K-TV-Setup/` | See upstream | https://github.com/VirtualDrivers/Virtual-Display-Driver |
| APISR | `models/` weights and converted `.onnx` (rejected, not in use) | See upstream | https://github.com/Kiteretsu77/APISR |
| AnimeJaNai | `2x_AnimeJaNai_*.onnx` in `Magpie/` (not in use) | See upstream | https://github.com/the-database/mpv-upscale-2x_animejanai |

"See upstream" means check the linked project for its exact license terms.

Comic images in the experiment folders (`skeleton-test/`, `vector-test/`)
are small crops of Marvel Comics artwork, © Marvel, included only for
image-processing analysis. Marvel Unlimited is a Marvel service; this
project is not affiliated with Marvel or any of the projects above.
