import Foundation

/// Everything the launcher owns lives under one folder, so uninstalling is a single delete.
enum Paths {
    static let root: URL = {
        // Override for testing a clean install without touching the real one.
        if let custom = ProcessInfo.processInfo.environment["TMLAUNCHER_ROOT"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("TMLauncher", isDirectory: true)
    }()

    static let runtimes = root.appendingPathComponent("runtimes", isDirectory: true)
    static let cache = root.appendingPathComponent("cache", isDirectory: true)
    static let prefix = root.appendingPathComponent("prefix", isDirectory: true)
    static let logs = root.appendingPathComponent("logs", isDirectory: true)
    static let state = root.appendingPathComponent("state.json")

    static var driveC: URL { prefix.appendingPathComponent("drive_c", isDirectory: true) }

    static var ubisoftDir: URL {
        driveC.appendingPathComponent("Program Files (x86)/Ubisoft/Ubisoft Game Launcher", isDirectory: true)
    }

    static var ubisoftExe: URL { ubisoftDir.appendingPathComponent("UbisoftConnect.exe") }

    /// The CrossOver-based engine names the Windows user "crossover".
    static var ubisoftSettings: URL {
        driveC.appendingPathComponent("users/crossover/AppData/Local/Ubisoft Game Launcher/settings.yaml")
    }

    /// Ubisoft Connect records where it installed a game in the registry; fall back to its default folder.
    static var gameExe: URL {
        if let reg = try? String(contentsOf: prefix.appendingPathComponent("system.reg"), encoding: .utf8),
           let key = reg.range(of: #"Ubisoft\\Launcher\\Installs\\5595]"#),
           let line = reg[key.upperBound...].split(separator: "\n").prefix(12)
               .first(where: { $0.hasPrefix("\"InstallDir\"=") }) {
            let win = line.dropFirst("\"InstallDir\"=\"".count).dropLast()
                .replacingOccurrences(of: "\\\\", with: "/")
            if win.count > 3, win.lowercased().hasPrefix("c:") {
                return driveC.appendingPathComponent(String(win.dropFirst(3)))
                    .appendingPathComponent("Trackmania.exe")
            }
        }
        return ubisoftDir.appendingPathComponent("games/Trackmania/Trackmania.exe")
    }

    static func ensure() throws {
        for dir in [root, runtimes, cache, logs] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
