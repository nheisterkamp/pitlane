import Foundation

/// A log file the viewer can show, or the generated diagnostics report.
enum LogSource: String, CaseIterable, Identifiable {
    case diagnostics, game, gamePrevious, ubisoftWine, ubisoftLauncher, ubisoftService, setup, ugcErrors, openplanet

    var id: String { rawValue }

    var label: String {
        switch self {
        case .diagnostics: "Diagnostics"
        case .game: "Game: Wine output"
        case .gamePrevious: "Game: previous run"
        case .ubisoftWine: "Ubisoft Connect: Wine output"
        case .ubisoftLauncher: "Ubisoft Connect: launcher log"
        case .ubisoftService: "Ubisoft Connect: service log"
        case .setup: "Setup"
        case .ugcErrors: "Trackmania: UGC errors"
        case .openplanet: "Openplanet"
        }
    }

    var url: URL? {
        let docs = Paths.driveC.appendingPathComponent("users/crossover/Documents")
        let ubiLogs = Paths.ubisoftDir.appendingPathComponent("logs")
        switch self {
        case .diagnostics: return nil
        case .game: return Paths.logs.appendingPathComponent("game.log")
        case .gamePrevious: return Paths.logs.appendingPathComponent("game.prev.log")
        case .ubisoftWine: return Paths.logs.appendingPathComponent("ubisoft.log")
        case .ubisoftLauncher: return ubiLogs.appendingPathComponent("launcher_log.txt")
        case .ubisoftService: return ubiLogs.appendingPathComponent("service_log.txt")
        case .setup: return Paths.logs.appendingPathComponent("setup.log")
        case .ugcErrors: return docs.appendingPathComponent("Trackmania/UGCErrorsLog.txt")
        case .openplanet: return docs.appendingPathComponent("OpenplanetNext/Openplanet.log")
        }
    }

    var exists: Bool { url.map { FileManager.default.fileExists(atPath: $0.path) } ?? true }

    /// Last `maxBytes` of the file, so multi-megabyte Wine logs stay fast to show.
    func read(maxBytes: Int = 1 << 20) -> String {
        guard let url else { return Diagnostics.report() }
        guard let h = try? FileHandle(forReadingFrom: url) else { return "(\(url.path) does not exist yet)" }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? h.seek(toOffset: start)
        let data = (try? h.readToEnd()) ?? Data()
        var text = String(decoding: data, as: UTF8.self)
        if start > 0, let nl = text.firstIndex(of: "\n") {
            text = "… (showing the last \(maxBytes >> 10) KB of \(size >> 10) KB)\n" + text[text.index(after: nl)...]
        }
        return text.isEmpty ? "(empty)" : text
    }

    var modified: Date? {
        url.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
    }
}

enum Diagnostics {
    static func report() -> String {
        let s = Settings.load()
        let fm = FileManager.default
        func yes(_ b: Bool) -> String { b ? "yes" : "no" }
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let ram = ProcessInfo.processInfo.physicalMemory >> 30
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"

        let cef = Paths.ubisoftDir.appendingPathComponent("libcef.dll")
        let cefState: String
        if !fm.fileExists(atPath: cef.path) {
            cefState = "not installed"
        } else {
            switch LibcefPatch.status(of: cef) {
            case .already: cefState = "patched"
            case .patched: cefState = "not patched yet (is patched on next launch)"
            case .unknown: cefState = "UNKNOWN BUILD (signature not found, window may be blank)"
            }
        }

        let reg = (try? String(contentsOf: Paths.prefix.appendingPathComponent("system.reg"), encoding: .utf8)) ?? ""
        let registered = reg.contains(#"Ubisoft\\Launcher\\Installs\\5595]"#)
        let staging = Paths.gameExe.deletingLastPathComponent().appendingPathComponent("uplay_download")
        let stagingFiles = (try? fm.contentsOfDirectory(atPath: staging.path))?.count ?? 0
        let config = (try? String(contentsOf: GameConfig.url, encoding: .utf8)) ?? ""
        let displayMode = config.range(of: #""DisplayMode"\s*:\s*"([a-z]+)""#, options: .regularExpression)
            .map { String(config[$0]).components(separatedBy: "\"").dropLast().last ?? "?" } ?? "no config yet"

        return """
        Trackmania Launcher \(version)
        Generated \(Date().formatted(date: .abbreviated, time: .standard))

        System
          macOS        \(os)
          Chip         \(cpuName()), \(ram) GB RAM
          Rosetta 2    \(yes(rosetta()))

        Runtime
          Engine       \(Runtime.id)
          Components   \(Runtime.description)
          Installed    \(yes(Runtime.isInstalled))  \(Runtime.dir.path)

        Settings
          Graphics     \(s.backend.label)
          Display      \(s.displayMode.label) (game config: \(displayMode))
          Retina       \(yes(s.retina))   Metal HUD \(yes(s.metalHUD))   Debug logging \(yes(s.debugLogging))
          Efficiency cores for Ubisoft \(yes(s.deprioritizeUbisoft))   Shutdown after play \(yes(s.cleanupAfterExit))

        Prefix
          Path         \(Paths.prefix.path)
          Created      \(yes(fm.fileExists(atPath: Paths.prefix.appendingPathComponent("system.reg").path)))
          Ubisoft      \(yes(fm.fileExists(atPath: Paths.ubisoftExe.path)))   libcef: \(cefState)

        Game
          Exe          \(yes(fm.fileExists(atPath: Paths.gameExe.path)))  \(Paths.gameExe.path)
          Registered   \(yes(registered))   Download staging files: \(stagingFiles)

        Now
          wineserver   \(yes(Wine.serverRunning))
          Trackmania   \(yes(Wine.gameRunning))
          Watcher      \(yes(Shell.isRunning("[t]m-watch")))

        Logs folder    \(Paths.logs.path)
        """
    }

    private static func cpuName() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buf = [UInt8](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        return String(decoding: buf.prefix { $0 != 0 }, as: UTF8.self)
    }

    private static func rosetta() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        p.arguments = ["-x86_64", "/usr/bin/true"]
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit() } catch { return false }
        return p.terminationStatus == 0
    }
}
