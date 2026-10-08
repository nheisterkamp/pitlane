# Trackmania Launcher for Apple Silicon

A ~270 KB native SwiftUI launcher that installs and runs Trackmania (2020) on M-series Macs.
On first run it downloads everything it needs into one folder: the Wine engine, Apple's
D3DMetal, Ubisoft Connect and the game. After that, Play starts the game and the launcher quits, so
it uses no memory while you race.

```bash
scripts/build-app.sh --install
```

This builds `dist/Trackmania Launcher.app` and copies it to `~/Applications`. It needs Xcode 16+
and Rosetta 2.

## Stack

| Layer | Component | Why |
|---|---|---|
| Wine | Sikarugir **WineCX 24.0.7_7** (CrossOver 24 sources) | Newest engine that runs current Ubisoft Connect. Upstream Wine 9 to 11 leaves its window blank, Sikarugir's Wine 11.0_1 can't run wineboot on macOS 27, and Apple's GPTK Wine 7.7 is too old. Uses msync. |
| D3D11 → Metal | **D3DMetal 4.0b2** (GPTK 4), default | Apple's translation layer, the fastest on Apple Silicon. |
| | **DXMT v0.80-244** | Open-source D3D11 → Metal. |
| | **DXVK 3.1.1 + KosmicKrisp** | DXVK on Mesa's Vulkan 1.4-on-Metal driver (instead of MoltenVK). |
| | WineD3D (OpenGL) | Compatibility fallback. |
| Store | Ubisoft Connect (latest, silent install) | Needed for login and online play. |

The renderers come from Sikarugir Template 1.0.21. Both archives are pinned by SHA-256 in
[`Runtime.swift`](Sources/TMLauncher/Runtime.swift). Proton isn't an option: it is Linux-only.

## Fullscreen or windowed

The launcher has two buttons, **Play Fullscreen** and **Play Windowed**. Before starting the
game it sets `DisplayMode` in Trackmania's own `Documents/Trackmania/Config/Default.json` and
leaves every other setting alone. Fullscreen uses the game's borderless mode (`windowedfull`):
no display mode switch, and Cmd-Tab is instant. The mode you used last becomes the default
button (Return).

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

`TMLAUNCHER_ROOT=/some/dir open -n "dist/Trackmania Launcher.app"` runs a fully separate
install, for testing.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Track parts missing | In game: set shader quality to High or Very High. |
| Crash or stutter on one renderer | Settings ⚙ → Graphics → try DXMT, then DXVK. |
| Ubisoft Connect window blank | It updated to a new Chromium build. Check `logs/` and update the signature in `LibcefPatch.swift`. |
| Anything else | Settings ⚙ → Kill Wine, then Play again. Logs are in `TMLauncher/logs/` and in the prefix's Ubisoft `logs/` folder. |

Credits: the Ubisoft Connect fixes were found by
[Esvalirion/trackmania-mac](https://github.com/Esvalirion/trackmania-mac) (MIT). The runtimes
are by [Sikarugir](https://github.com/Sikarugir-App), [3Shain/dxmt](https://github.com/3Shain/dxmt),
DXVK, Mesa and Apple. D3DMetal is licensed by Apple for non-commercial use. Not affiliated with
Ubisoft, Nadeo, Apple or CodeWeavers.
