import AppKit
import Foundation

enum Maintenance {
    struct Usage {
        var runtime: Int64 = 0
        var game: Int64 = 0
        var prefix: Int64 = 0   // Windows environment + Ubisoft Connect, without the game
        var cache: Int64 = 0
        var logs: Int64 = 0
        var total: Int64 { runtime + game + prefix + cache + logs }
    }

    /// Allocated sizes. APFS clones (e.g. a game copied from Steam) share blocks with their
    /// source, so the real extra space can be smaller than shown.
    static func usage() async -> Usage {
        await Task.detached(priority: .utility) {
            let gameDir = Paths.gameExe.deletingLastPathComponent()
            let game = size(of: gameDir)
            return Usage(runtime: size(of: Paths.runtimes) + size(of: Paths.root.appendingPathComponent("tools")),
                         game: game,
                         prefix: max(0, size(of: Paths.prefix) - game),
                         cache: size(of: Paths.cache),
                         logs: size(of: Paths.logs))
        }.value
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Downloads, logs and DXVK's shader cache. Leaves D3DMetal's shader cache alone (it lives
    /// in macOS's Metal cache and speeds up loading) and never touches the Ubisoft login.
    static func clearCaches() {
        let fm = FileManager.default
        for dir in [Paths.cache, Paths.logs] {
            for f in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] {
                try? fm.removeItem(at: dir.appendingPathComponent(f))
            }
        }
        let wineTemp = Paths.driveC.appendingPathComponent("users/crossover/AppData/Local/Temp")
        for f in (try? fm.contentsOfDirectory(atPath: wineTemp.path)) ?? [] {
            try? fm.removeItem(at: wineTemp.appendingPathComponent(f))
        }
    }

    /// Where the game waits while the Windows environment is rebuilt.
    static var parkedGame: URL { Paths.root.appendingPathComponent("game-parked", isDirectory: true) }

    /// Moves the game out of the prefix and deletes the prefix. The caller then runs setup,
    /// which rebuilds it and puts the game back.
    static func dismantlePrefix() async throws {
        await Wine.killAll()
        let fm = FileManager.default
        let game = Paths.ubisoftDir.appendingPathComponent("games/Trackmania")
        if fm.fileExists(atPath: game.path), !fm.fileExists(atPath: parkedGame.path) {
            try fm.moveItem(at: game, to: parkedGame)
        }
        try? fm.removeItem(at: Paths.prefix)
    }

    /// Puts a parked game back after setup. Ubisoft Connect then verifies and registers it.
    static func restoreParkedGame() throws -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: parkedGame.path) else { return false }
        let games = Paths.ubisoftDir.appendingPathComponent("games", isDirectory: true)
        try fm.createDirectory(at: games, withIntermediateDirectories: true)
        try fm.moveItem(at: parkedGame, to: games.appendingPathComponent("Trackmania"))
        return true
    }

    /// Removes everything the launcher installed, then moves the app to the Trash.
    /// Game settings and replays in ~/Documents/Trackmania are kept.
    static func uninstall() async {
        await Wine.killAll()
        try? FileManager.default.removeItem(at: Paths.root)
        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private static func size(of url: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
                                                     options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            total += Int64((try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }
}
