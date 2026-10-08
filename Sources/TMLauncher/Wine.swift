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
            "WINEDEBUG": "-all",                       // logging costs CPU on every call
            "WINEMSYNC": "1",                          // Mach-semaphore sync: lowest overhead on macOS
            "WINE_SIMULATE_WRITECOPY": "1",            // CEF expects PAGE_READWRITE, not PAGE_WRITECOPY
            "DYLD_FALLBACK_LIBRARY_PATH": "\(Runtime.frameworks.path):/usr/lib",
            "WINEDLLOVERRIDES": "dinput8=n,b",         // lets Openplanet load if present
            "MTL_HUD_ENABLED": s.metalHUD ? "1" : "0",
        ]

        let r = Runtime.renderers
        switch s.backend {
        case .d3dmetal:
            let ext = r.appendingPathComponent("d3dmetal/external")
            e["WINEDLLPATH_PREPEND"] = r.appendingPathComponent("d3dmetal/wine").path
            e["CX_APPLEGPTK_LIBD3DSHARED_PATH"] = ext.appendingPathComponent("libd3dshared.dylib").path
            e["DYLD_FALLBACK_FRAMEWORK_PATH"] = ext.path
        case .dxmt:
            e["WINEDLLPATH_PREPEND"] = r.appendingPathComponent("dxmt/wine").path
        case .dxvk:
            // DXVK 3 needs Vulkan 1.3+, which only KosmicKrisp provides on macOS.
            let icd = Runtime.kosmicKrispICD().path
            e["WINEDLLPATH_PREPEND"] = r.appendingPathComponent("dxvk3/wine").path
            e["VK_DRIVER_FILES"] = icd
            e["VK_ICD_FILENAMES"] = icd
            e["DXVK_ASYNC"] = "1"
            e["DXVK_SHADER_CACHE_PATH"] = Paths.cache.path
            e["DXVK_HUD"] = s.metalHUD ? "fps,frametimes" : "0"
        case .wined3d:
            break
        }
        return e
    }

    /// Starts a Windows program and returns immediately. The process outlives the launcher.
    static func spawn(_ exe: URL, args: [String] = [], settings: Settings, log: String) throws {
        let p = Process()
        p.executableURL = Runtime.wine
        p.arguments = [exe.path] + args
        p.environment = environment(settings)
        p.currentDirectoryURL = exe.deletingLastPathComponent()
        let logURL = Paths.logs.appendingPathComponent(log)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let h = try FileHandle(forWritingTo: logURL)
        p.standardOutput = h
        p.standardError = h
        p.standardInput = FileHandle.nullDevice
        try p.run()
    }

    /// Runs a Wine command to completion (setup steps).
    @discardableResult
    static func run(_ args: [String], settings: Settings = Settings(), log: String = "setup.log") async throws -> Int32 {
        try await Shell.run(Runtime.wine.path, args, env: environment(settings),
                            log: Paths.logs.appendingPathComponent(log))
    }

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

    static var gameRunning: Bool { Shell.isRunning(#"[T]rackmania\.exe"#) }

    /// A tiny detached shell that watches the game after the launcher has quit (it sleeps, so
    /// it costs nothing):
    /// - while playing, it moves Ubisoft Connect (~2.5 GB of Chromium, needed for the online
    ///   session) to background QoS, so macOS keeps it on the efficiency cores and leaves the
    ///   performance cores to the game. It repeats every minute to catch respawned renderers.
    /// - after the game exits, it optionally shuts the prefix down.
    static func scheduleWatcher(demote: Bool, cleanup: Bool) throws {
        let script = """
        i=0; until pgrep -qf '[T]rackmania\\.exe'; do i=$((i+1)); [ $i -gt 120 ] && exit 0; sleep 2; done
        n=9
        while pgrep -qf '[T]rackmania\\.exe'; do
          n=$((n+1))
          if [ "$2" = 1 ] && [ $n -ge 12 ]; then
            n=0
            for p in $(pgrep -f '[u]pc\\.exe|[U]playWebCore\\.exe|[U]bisoftGameLauncher|[U]playService\\.exe'); do
              /usr/sbin/taskpolicy -b -p "$p" 2>/dev/null
            done
          fi
          sleep 5
        done
        [ "$3" = 1 ] && { sleep 3; exec "$1" -k; }
        exit 0
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script, "tm-watch", Runtime.wineserver.path, demote ? "1" : "0", cleanup ? "1" : "0"]
        p.environment = ["WINEPREFIX": Paths.prefix.path, "PATH": "/usr/bin:/bin"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
    }
}
