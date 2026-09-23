# Streaming Marvel Unlimited to the living-room 4K TV

Bedroom PC -> Sunshine (NVENC hardware encode) -> home WiFi -> Apple TV
running Moonlight -> HDMI (already-decoded, zero-loss) -> 55" LG 4K TV.

Wired HDMI was ruled out (different floors). WiGig/60GHz wireless-HDMI
extenders were ruled out too - that tech needs same-room line of sight and
doesn't cross a structural floor. This (Sunshine + a real 4K virtual
display + Moonlight) is the best remaining option for genuine native 4K,
as opposed to AirPlay/Miracast/Chromecast, which cap live screen mirroring
at 1080p regardless of the receiving hardware - not a bug, just how those
protocols are built.

## What's built and verified (PC side - done)

- **Sunshine** installed (`C:\Program Files\Sunshine\`), service running.
  Config tuned for max quality over max speed - this is a static comic
  reader, not a game, so there's no latency budget to protect:
    - `encoder = nvenc` (GTX 1650, Turing NVENC, HEVC hardware encode)
    - `nvenc_preset = 7` (slowest/highest quality, not the gaming default P1)
    - `nvenc_twopass = full_res` (not the default quarter_res)
    - `nvenc_spatial_aq = enabled` (more bits to ink linework, fewer to flat fills)
    - `bitrate = 60000` (generous ceiling; real usage will be far lower on
      mostly-static content - lower this if the WiFi path can't sustain it)
  All of the above confirmed loaded from Sunshine's own log, not assumed.

- **Firewall rules** added (TCP+UDP, all profiles), confirmed via `netsh`.

- **Virtual Display Driver** (VirtualDrivers/Virtual-Display-Driver on
  GitHub) installed and genuinely active - confirmed via direct
  EnumDisplaySettings readback, not just Device Manager status:
    - Real monitor, "VDD by MTT", currently at **3840x2160@60Hz**
    - If this ever needs reinstalling: a soft PnP disable/enable cycle
      was NOT enough to make it work. What actually fixed it was running
      the app's "Install Driver" button a **second time**, which triggers
      a full `devcon`-based reinstall, not just a settings push. If the
      monitor shows as present but inactive, that's the fix - not a
      reboot (a reboot would probably also work, but wasn't needed).
    - Its config lives at `C:\VirtualDisplayDriver\vdd_settings.xml`,
      NOT the copy inside this project's downloaded zip - that copy is
      only the install-time template.

- **Sunshine targets the virtual display specifically**, not the laptop
  panel: `output_name = {d54a4360-26df-5f1a-b161-298c03c03b66}`.
  Two distinct GUID pitfalls here, both confirmed via Sunshine's own log,
  not assumed:
    - Sunshine's config parser treats `#` as a comment start, so the full
      `\\?\DISPLAY#...#{GUID}` Windows device-interface path gets silently
      truncated - only a bare `{GUID}` survives.
    - That bare GUID must be **Sunshine's own internal `device_id`**, which
      it derives/hashes itself and is *not* the same value as the raw
      Windows device-interface GUID. Every startup, Sunshine logs the true
      value under "Currently available display devices" - match on
      `"friendly_name": "VDD by MTT"` to find the right entry. Targeting
      the wrong (Windows-native) GUID here doesn't error cleanly; it
      caused Sunshine to hang/crash on every startup while the virtual
      display was present, regardless of any other setting.
  `dd_resolution_option`/`dd_manual_resolution` force the stream to
  exactly 3840x2160@60 rather than letting Sunshine auto-negotiate.

- **`capture = ddx`, not `wgc`.** Windows.Graphics.Capture (`wgc`) was the
  first thing tried, on the reasoning that it's the same capture method
  Magpie itself uses elsewhere in this project. That reasoning doesn't
  transfer to Sunshine: Sunshine's own docs mark `wgc` as beta and
  explicitly **"not compatible with the Sunshine service."** Running as
  that service, `wgc` reliably crashed Sunshine (`abort()`, exception
  `0xc0000409` in `ucrtbase.dll`, confirmed via Windows Event Viewer) a
  few seconds into every startup, every time the virtual display was
  present - completely independent of encoder, GPU-preference registry
  settings, resolution, or Windows display scaling, all of which were
  separately tried and ruled out first. `ddx` (the classic DirectX Desktop
  Duplication API) is what Sunshine's docs call "well-supported" on
  Windows and is what actually works here, running as a normal service.

- **Magpie "TV 4K" scaling mode** built (see
  `magpie-scaling-modes-snapshot.json` in the parent folder for the full
  JSON). NOT set as the active/default mode - your laptop reading setup
  is untouched. Select it manually from Magpie's tray icon only when
  reading on the TV:

      Denoise (Bilateral Mode, 0.22) -> Restore (largest non-GAN network)
        -> Upscale 2x -> SMAA -> Upscale 2x -> SMAA
        = 4x total supersample -> 15360x8640

  Why 4x and not more: same hard 16384px D3D11 texture ceiling discovered
  earlier in this project. At a 3840px-wide source the true ceiling is
  16384/3840 = 4.27x. 4x lands at 15360px wide, 1024px of margin - the
  *same* absolute safety margin as the proven-safe "AntiJaggy 8x" mode
  used on the 1920px-wide laptop source. Also a clean power of 2 (two
  exact 2x passes), so no extra fractional resize step is needed.

- **Sunshine's "Desktop" app entry** confirmed present and correctly
  minimal (streams whatever's on screen, no specific program launched) -
  this is the entry to pick in Moonlight for general mirroring.
  (apps.json also has two unrelated entries - Playnite and RetroArch -
  referencing a different Windows user account than this session used.
  Left untouched; irrelevant to this setup either way.)

## What needs to happen on your end

1. **Install Moonlight** from the Apple TV's own App Store (search
   "Moonlight Game Streaming"). Nobody can do this remotely.

2. **Pair it with Sunshine.** Open Moonlight on the Apple TV - it should
   auto-discover this PC on the network (mDNS, registered by Sunshine on
   startup). Select it, and tvOS will show a PIN. Enter that PIN at
   Sunshine's own web UI: `https://localhost:47990` on this PC (or from
   any browser on the same network, since `origin_web_ui_allowed = lan`
   by default). First visit to that URL also sets the admin
   username/password for Sunshine's web UI, if not already done.

3. **Double-click [`tools/Read Marvel Comics Upscaled - 4K TV Mode.vbs`](../tools/Read%20Marvel%20Comics%20Upscaled%20-%204K%20TV%20Mode.vbs).**
   This replaces steps 3-4 below entirely - it silently checks the virtual
   display and Sunshine are up (fixing them if needed), switches Magpie to
   "TV 4K", and either jumps straight to an already-open marvel.com/comics/
   issue tab (moving+fullscreening it on the virtual display and turning
   Magpie's upscaling on) or preps a `marvel0 ` search box on your laptop
   screen and waits in the background for you to press F11 yourself once
   you've picked an issue, then finishes the move automatically. See
   `tools/TVModeCommon.ps1` and `tools/Start-ComicMode-TV.ps1` for exactly
   how each piece works. A warning popup only appears if something
   couldn't be fixed automatically - otherwise it's silent end to end.

   (Doing it by hand instead: drag Firefox onto the virtual display -
   Win+Shift+Left/Right cycles a window between displays - fullscreen it
   there with F11, switch Magpie's mode to "TV 4K" from its tray icon,
   then press Win+Shift+A with that window focused.)

   The launcher also leaves a small "4K" icon in the system tray (separate
   from Magpie's and Sunshine's own tray icons) - right-click it and choose
   **Quit** when you're done reading. That stops Magpie and Sunshine,
   disables the virtual 4K display entirely, and puts Windows back to
   "PC screen only" (Win+P), so the invisible monitor only exists while
   you're actually streaming to the TV. Double-clicking the launcher again
   brings everything back from scratch in order: re-enable the display ->
   Extend (Windows usually restores this by itself; the launcher forces it
   if not) -> enforce 3840x2160 -> restart Sunshine last, since Sunshine
   only discovers displays at its own startup. Sunshine's `output_name`
   device ID stays stable across this cycle even though Windows renumbers
   the display (`DISPLAY17` -> `DISPLAY18` -> ...), confirmed from its log.

4. **In Moonlight on the Apple TV:** select "Desktop" and start streaming.

5. **On the LG TV itself:** switch its picture mode to something like
   "Filmmaker Mode" or "Game Mode" if available. Most non-OLED LG TVs
   ship with motion interpolation, edge enhancement, and dynamic
   contrast enabled by default - none of that is Apple TV's or Sunshine's
   fault, but it actively reprocesses the image after everything upstream
   already did its job correctly, and it matters more to final
   perceived quality than anything in this pipeline.

## The TV-mode launcher's silent-elevation setup

The launcher needs to silently fix the virtual display / Sunshine on the
rare occasion one is off (e.g. right after a reboot) - both normally need
admin rights, which would mean a UAC prompt breaking the "silent" part.

This machine's everyday account (`nk`) isn't an administrator - only a
separate `Admin` account is - so achieving zero-prompt elevation took a
few dead ends worth recording:

- A Scheduled Task with `LogonType Password` (Task Scheduler's "Run
  whether user is logged on or not") needs a stored password, and this
  being **Windows 10 Home** (which lacks the Local Security Policy editor
  the normal "Log on as a batch job" fix relies on), Task Scheduler
  rejected it outright with "the user account is unknown, the password is
  incorrect, or the user account does not have permission" - correct
  password included.
- **`LogonType S4U`** was the fix: it runs the task as `Admin` with a full
  elevated token, without ever storing or needing that account's
  password. Administrators-group accounts get the underlying "Log on as
  a batch job" right by default on every Windows edition including Home,
  which is exactly what S4U relies on.
- One more wrinkle: a task's *default* ACL only lets Administrators
  start/query it via the Task Scheduler API - a standard user gets
  "Access is denied" even though the task itself runs fine once
  triggered. NTFS file permissions on the task's file under
  `C:\Windows\System32\Tasks\` do NOT control this - it's a separate,
  internal security descriptor Task Scheduler enforces itself. Fixed by
  explicitly granting `BUILTIN\Users` execute rights on this one task via
  `ITaskFolder.GetTask().SetSecurityDescriptor()` - deliberately run by
  hand in an elevated PowerShell window rather than by any automated
  script, since programmatically loosening a privileged task's ACL is a
  real security boundary worth a human's deliberate action, not something
  to automate quietly.

The task itself (`ComicUpscale-TVMode-ElevatedHelper`, defined in
`tools/Setup-TVModeElevationTask.ps1`, doing the actual work in
`tools/Ensure-TVModeInfra.ps1`) only ever does two things: enable the
virtual display if it's off, and restart the Sunshine service if it
needed that or wasn't already running - nothing else.

## Known limitation

Magpie has exactly one global scaling-mode setting - there's no built-in
per-display or per-mirroring-state auto-switching. The TV-mode launcher
above works around this for you (closes Magpie, flips the config to
"TV 4K", relaunches it, only when it's not already in that mode) rather
than requiring you to do it by hand every time - but the underlying
limitation is still real if you ever drive Magpie any other way.
