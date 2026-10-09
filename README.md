# Pitlane

**An unofficial, lightweight Trackmania (2020) launcher for Apple Silicon Macs.**

> Pitlane is not affiliated with or endorsed by Ubisoft, Nadeo, Apple, CodeWeavers or
> Sikarugir. Trackmania is a trademark of Ubisoft/Nadeo. Pitlane contains no game, Wine,
> Apple or Ubisoft binaries; it downloads them from their publishers on your Mac.

A small native SwiftUI app that installs and runs Trackmania (2020) on M-series Macs.
On first run it downloads everything it needs into one folder: the Wine engine, Apple's
D3DMetal, Ubisoft Connect and the game. After that, Play starts the game and the launcher quits, so
it uses no memory while you race.

```bash
scripts/build-app.sh --install
```

This builds `dist/Pitlane.app` and copies it to `~/Applications`. It needs Xcode 16+
and Rosetta 2.

## Stack

| Layer | Component | Why |
|---|---|---|
| Wine | Sikarugir **WineCX 24.0.7_7** (CrossOver 24 sources) | Newest engine that runs current Ubisoft Connect. Upstream Wine 9 to 11 leaves its window blank, Sikarugir's Wine 11.0_1 can't run wineboot on macOS 27, and Apple's GPTK Wine 7.7 is too old. Uses msync. |
| D3D11 → Metal | **D3DMetal 4.0b2** (GPTK 4), default | Apple's translation layer. |
| | **DXMT v0.80-244** | Open-source D3D11 → Metal, with MetalFX upscaling. |
| Store | Ubisoft Connect (latest, silent install) | Needed for login and online play. |

The renderers come from Sikarugir Template 1.0.21. Both archives are pinned by SHA-256 in
[`Runtime.swift`](Sources/TMLauncher/Runtime.swift). Proton isn't an option: it is Linux-only.

### Tested on an M5 Max, macOS 27 (menu scene, frame limit 144)

| Option | Result |
|---|---|
| D3DMetal, 3440×1440 | ✅ 144 FPS, 1.6 ms GPU time per frame |
| DXMT, 3440×1440 | ✅ 144 FPS, 1.7–2.0 ms GPU time per frame |
| DXMT + MetalFX 2× | ✅ works, but on a 1× display it upscales 3440×1440 → 6880×2880 (3.5 ms), so it's only offered on Retina screens |
| DXVK 3.1.1 | ❌ needs `shaderCullDistance`, which MoltenVK lacks. This engine's Mac driver loads MoltenVK directly, and swapping in KosmicKrisp through the Vulkan loader gives a white window |
| DXVK 1.10.3 (MoltenVK) | ❌ game hangs on a white window |
| WineD3D (OpenGL) | ❌ white window: macOS OpenGL 4.1 has no compute shaders |
| macOS Game Mode | ❌ stays off, even with a game category added to Wine's embedded Info.plist and in exclusive fullscreen. Wine doesn't use native macOS fullscreen |
| Lean Ubisoft Connect | ✅ 0.7–2.0 GB instead of ~2.7 GB while playing, online session OK |

## Fullscreen or windowed

The launcher has two buttons, **Play Fullscreen** and **Play Windowed**. Before starting the
game it sets `DisplayMode` in Trackmania's own `Documents/Trackmania/Config/Default.json` and
leaves every other setting alone. Fullscreen uses the game's borderless mode (`windowedfull`):
no display mode switch, and Cmd-Tab is instant. The mode you used last becomes the default
button (Return).

The arrow on **Play Windowed** picks the window size. It offers common 16:9, 16:10 and
ultrawide sizes that fit your screen, plus "Fit screen" (the largest 16:9 that fits). Sizes are
in screen points and are scaled for Retina mode. The default, "Keep game setting", leaves the
size the game saved alone.

## Performance choices

- The launcher starts `Trackmania.exe` directly and quits. Ubisoft Connect runs in the
  background only for the login.
- A small detached shell script (sleeping, ~1 MB) moves Ubisoft Connect's ~2.5 GB of
  Chromium processes to background QoS while you play. macOS then keeps them on the
  efficiency cores and leaves the performance cores to the game. When the game exits, the
  script shuts Wine down.
- `WINEMSYNC=1` (Mach-semaphore sync) and `WINEDEBUG=-all` (no logging overhead).
- The Ubisoft overlay is disabled, because it hooks every frame.
- Retina mode is off by default. Native resolution can mean 4× the pixels.
- If a Trackmania install from CrossOver/Steam is found, it is APFS-cloned (instant, no extra
  disk space). Ubisoft Connect then only verifies and patches it instead of downloading 7 GB.

## Fixes it applies

- **libcef.dll patch.** Ubisoft builds its Chromium with command-line switches disabled, so
  the `--in-process-gpu --disable-gpu` switches the engine passes are ignored and the window
  stays blank. This is the file equivalent of CrossOver's "CW HACK 25737". It finds the
  instruction by signature, not a fixed offset, and re-applies before every launch because
  Ubisoft Connect restores the file when it updates.
- `HKCU\Software\Wine\Direct3D\renderer=gl`, because Ubisoft Connect's GPU probe crashes on
  wined3d-Vulkan.
- `WINE_SIMULATE_WRITECOPY=1` for Chromium.

## Files

Everything lives in `~/Library/Application Support/TMLauncher` (runtime, Wine prefix with
Ubisoft Connect and the game, logs, settings). Delete that folder and the app to uninstall.
Game settings and replays live in `~/Documents/Trackmania`, the same place CrossOver uses.

`TMLAUNCHER_ROOT=/some/dir open -n "dist/Pitlane.app"` runs a fully separate
install, for testing. `TMLauncher --setup` runs first-run setup headless, which with
`TMLAUNCHER_ROOT` gives a clean-install test. `TMLauncher --snapshot out.png` renders the
main window invisibly.

## Releasing

`scripts/build-app.sh` always signs with the hardened runtime (ad-hoc by default).
`scripts/release.sh` builds a Developer ID-signed, notarized and stapled DMG. It needs two
one-time steps with your Apple Developer account, listed at the top of the script: create a
*Developer ID Application* certificate, and save notarytool credentials.

## Settings (⌘,)

| Tab | What |
|---|---|
| General | Quit on launch, efficiency cores for Ubisoft Connect, shutdown after play, **lean Ubisoft Connect** (Chromium memory switches, about 650 MB+ less RAM), debug logging |
| Graphics | Translation layer (D3DMetal or DXMT), Retina, performance HUD, **MetalFX upscaling** (DXMT on Retina screens), **frame limit** (the game's MaxFps) |
| Input | Command → Ctrl and Option → Alt (Wine Mac driver), controllers detected by macOS |
| Openplanet | One-click install/update/remove of [Openplanet](https://openplanet.dev). The installer refuses the game folder under Wine, so its payload is extracted with a pinned 7-Zip build. |
| Maintenance | Disk usage, clear downloads/logs/temp, repair runtime, reset the Windows environment (keeps the game; you sign in to Ubisoft Connect again and it verifies the files), uninstall |
| Updates | Installed component versions; checks Sikarugir for newer graphics runtimes (verified with GitHub's SHA-256 digest, one-click revert to the tested one). Newer Wine engines are listed but not installed until tested. |

About MetalFX: D3DMetal's `D3DM_ENABLE_METALFX` only replaces DLSS, which Trackmania doesn't
have. DXMT's swapchain upscaler multiplies the output resolution. With Retina mode off on a
Retina screen, the game renders at point resolution and MetalFX produces the Retina pixels.

## Logs and diagnostics

Click the 🔍 button next to ⚙ (or **View logs** when something fails) to open the logs window:

- **Diagnostics**: a generated report covering system, runtime, settings, libcef patch state,
  install state, and whether wineserver, the game and the watcher are running. Copy it into
  a bug report.
- **Game / Ubisoft Connect Wine output**, the **previous game run** (kept so a crash log
  survives a relaunch), Ubisoft Connect's **launcher** and **service** logs, **setup**,
  Trackmania's **UGC errors** and **Openplanet**.
- Filter, **Errors only**, **Follow** (reloads live and scrolls to the end), Copy, Show in Finder.

Wine output is silent by default for performance. Turn on Settings ⚙ → **Debug logging** to get
Wine errors (`WINEDEBUG=err+all`) plus DXMT/DXVK logs on the next launch.

From Terminal: `"~/Applications/Pitlane.app/Contents/MacOS/TMLauncher" --diagnostics`
prints the report without opening a window.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Black bars at the sides on an ultrawide screen | Seen in the menus with every renderer and resolution setting: the window is full width, but the menu scene renders 16:9. Not a launcher setting. |
| Track parts missing | In game: set shader quality to High or Very High. |
| Crash or stutter on one renderer | Settings ⚙ → Graphics → switch between D3DMetal and DXMT. |
| Ubisoft Connect window blank | It updated to a new Chromium build. Check `logs/` and update the signature in `LibcefPatch.swift`. |
| Anything else | Settings ⚙ → Kill Wine, then Play again. Logs are in `TMLauncher/logs/` and in the prefix's Ubisoft `logs/` folder. |

Credits: the Ubisoft Connect fixes were found by
[Esvalirion/trackmania-mac](https://github.com/Esvalirion/trackmania-mac) (MIT). The runtimes
are by [Sikarugir](https://github.com/Sikarugir-App), [3Shain/dxmt](https://github.com/3Shain/dxmt),
DXVK, Mesa and Apple. D3DMetal is licensed by Apple for non-commercial use. The Pitlane icon is
original artwork: an Icon Composer document (`Resources/Pitlane.icon`, SVG layers) compiled by
`actool` into a vector `Assets.car` for macOS 26+, with an `.icns` fallback for older macOS.

## AI disclosure

Pitlane was built with AI assistance. Most of the code, scripts, documentation and the icon were
written by Anthropic's Claude (in Claude Code), directed, reviewed and tested by Niels
Heisterkamp on his own Mac. Treat it like any community project: read the code
before you trust it, and report problems in the issues.
