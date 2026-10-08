import Foundation

enum Wine {
    /// A minimal, explicit environment: nothing from the launcher's own environment leaks in
    /// except what Wine and macOS need.
    static func environment(_ s: Settings) -> [String: String] {
        let host = ProcessInfo.processInfo.environment
        var e: [String: String] = [
            "HOME": NSHomeDirectory(),
            "USER": NSUserName(),
            "LOGNAME": NSUserName(),
            "TMPDIR": host["TMPDIR"] ?? NSTemporaryDirectory(),
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LANG": host["LANG"] ?? "en_US.UTF-8",
            "WINEPREFIX": Paths.prefix.path,
            // Logging costs CPU on every call; the debug setting turns on errors only.
            "WINEDEBUG": s.debugLogging ? "err+all,fixme-all" : "-all",
            "WINEMSYNC": "1",                          // Mach-semaphore sync: lowest overhead on macOS
            "WINE_SIMULATE_WRITECOPY": "1",            // CEF expects PAGE_READWRITE, not PAGE_WRITECOPY
            "DYLD_FALLBACK_LIBRARY_PATH": "\(Runtime.frameworks.path):/usr/lib",
            "WINEDLLOVERRIDES": "dinput8=n,b",         // lets Openplanet load if present
            "MTL_HUD_ENABLED": s.metalHUD ? "1" : "0",
        ]

        if s.debugLogging { e["DXMT_LOG_LEVEL"] = "info" }

        let r = Runtime.renderers
        switch s.backend {
        case .d3dmetal:
            let ext = r.appendingPathComponent("d3dmetal/external")
            e["WINEDLLPATH_PREPEND"] = r.appendingPathComponent("d3dmetal/wine").path
            e["CX_APPLEGPTK_LIBD3DSHARED_PATH"] = ext.appendingPathComponent("libd3dshared.dylib").path
            e["DYLD_FALLBACK_FRAMEWORK_PATH"] = ext.path
        case .dxmt:
            e["WINEDLLPATH_PREPEND"] = r.appendingPathComponent("dxmt/wine").path
            if s.metalFX && !s.retina && MetalFXSupport.available {
                // MetalFX spatial upscales the game's output by `factor` (e.g. points → Retina pixels).
                e["DXMT_METALFX_SPATIAL_SWAPCHAIN"] = "1"
                e["DXMT_CONFIG"] = "d3d11.metalSpatialUpscaleFactor=\(String(format: "%.2f", s.metalFXFactor));"
            }
        }
        return e
    }

    /// Starts a Windows program and returns immediately. The process outlives the launcher.
    static func spawn(_ exe: URL, args: [String] = [], settings: Settings, log: String) throws {
        // Keep the previous run's log: after a crash you usually relaunch before looking.
        let logURL = Paths.logs.appendingPathComponent(log)
        let prev = logURL.deletingPathExtension().appendingPathExtension("prev.log")
        if let size = try? logURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 {
            try? FileManager.default.removeItem(at: prev)
            try? FileManager.default.moveItem(at: logURL, to: prev)
        }
        try Shell.spawnDetached(Runtime.wine.path, [exe.path] + args, env: environment(settings),
                                cwd: exe.deletingLastPathComponent(),
                                log: Paths.logs.appendingPathComponent(log))
    }

    /// Runs a Wine command to completion (setup steps).
    @discardableResult
    static func run(_ args: [String], settings: Settings = Settings(), log: String = "setup.log") async throws -> Int32 {
        try await Shell.run(Runtime.wine.path, args, env: environment(settings),
                            log: Paths.logs.appendingPathComponent(log))
    }

    /// Chromium switches for Ubisoft Connect, honoured thanks to the libcef patch: one renderer
    /// process, no site isolation, small JS heap and disk cache. Measured while playing:
    /// ≈2.05 GB instead of ≈2.7 GB. The login and online session work as normal.
    static let leanUbisoftSwitches = [
        "-upc_desktop_mode", "--renderer-process-limit=1", "--disable-site-isolation-trials",
        "--disable-features=site-per-process,IsolateOrigins,Translate,MediaRouter,BackForwardCache,AudioServiceOutOfProcess",
        "--js-flags=--max-old-space-size=192", "--disk-cache-size=1048576", "--disable-gpu-shader-disk-cache",
    ]

    static func waitIdle() async {
        _ = try? await Shell.run(Runtime.wineserver.path, ["-w"], env: environment(Settings()))
    }

    static func killAll() async {
        _ = try? await Shell.run(Runtime.wineserver.path, ["-k"], env: environment(Settings()))
    }

    static func regAdd(_ key: String, _ name: String, _ value: String, type: String = "REG_SZ") async throws {
        try await run(["reg", "add", key, "/v", name, "/t", type, "/d", value, "/f"])
    }

    /// True while the prefix's wineserver is up (i.e. Ubisoft Connect or the game is running).
    /// Wine starts it as `…/wswine.bundle/lib/wine/../../bin/wineserver`, so match loosely.
    static var serverRunning: Bool {
        Shell.isRunning(NSRegularExpression.escapedPattern(for: "\(Runtime.id)/frameworks/wswine.bundle/") + ".*wineserver")
    }

    /// A path separator before the name: matches the game, not shells or editors mentioning it.
    static var gameRunning: Bool { Shell.isRunning(#"[/\\][T]rackmania\.exe"#) }

    /// A tiny detached shell that watches the game after the launcher has quit (it sleeps, so
    /// it costs nothing):
    /// - while playing, it moves Ubisoft Connect (~2.5 GB of Chromium, needed for the online
    ///   session) to background QoS, so macOS keeps it on the efficiency cores and leaves the
    ///   performance cores to the game. It repeats every minute to catch respawned renderers.
    /// - after the game exits, it optionally shuts the prefix down.
    static func scheduleWatcher(demote: Bool, cleanup: Bool) throws {
        // Trackmania.exe exits right away and Ubisoft Connect relaunches it 10-20 s later, so
        // "gone" only counts after a real session: up for 1 min, then absent for 30 s. If the
        // game never really runs (e.g. a long Ubisoft update), leave everything alone.
        let script = """
        seen=0; gone=0; t=0; n=11
        while :; do
          if pgrep -qf '[/\\\\][T]rackmania\\.exe'; then
            seen=$((seen+1)); gone=0; n=$((n+1))
            if [ "$2" = 1 ] && [ $n -ge 12 ]; then
              n=0
              for p in $(pgrep -f '[u]pc\\.exe|[U]playWebCore\\.exe|[U]bisoftGameLauncher|[U]playService\\.exe'); do
                /usr/sbin/taskpolicy -b -p "$p" 2>/dev/null
              done
            fi
          else
            gone=$((gone+1))
            [ $seen -ge 12 ] && [ $gone -ge 6 ] && break
            [ $seen -lt 12 ] && [ $t -gt 360 ] && exit 0
          fi
          t=$((t+1)); sleep 5
        done
        [ "$3" = 1 ] && exec "$1" -k
        exit 0
        """
        try Shell.spawnDetached("/bin/sh",
                                ["-c", script, "tm-watch", Runtime.wineserver.path, demote ? "1" : "0", cleanup ? "1" : "0"],
                                env: ["WINEPREFIX": Paths.prefix.path, "PATH": "/usr/bin:/bin"])
    }
}
