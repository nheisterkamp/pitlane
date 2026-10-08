import Foundation

enum Shell {
    /// Runs a tool to completion and returns stdout. Output goes to a log file when given,
    /// so chatty Wine processes never fill a pipe and stall.
    @discardableResult
    static func run(_ tool: String, _ args: [String], env: [String: String]? = nil,
                    cwd: URL? = nil, log: URL? = nil) async throws -> Int32 {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            if let env { p.environment = env }
            if let cwd { p.currentDirectoryURL = cwd }
            if let log {
                FileManager.default.createFile(atPath: log.path, contents: nil)
                let h = try? FileHandle(forWritingTo: log)
                p.standardOutput = h
                p.standardError = h
            } else {
                p.standardOutput = FileHandle.nullDevice
                p.standardError = FileHandle.nullDevice
            }
            p.terminationHandler = { cont.resume(returning: $0.terminationStatus) }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }

    /// Extracts .tar.xz / .tar.gz / .zip archives with the system tools (no bundled deps).
    static func extract(_ archive: URL, into dir: URL) async throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let status: Int32
        if archive.pathExtension == "zip" {
            status = try await run("/usr/bin/ditto", ["-x", "-k", archive.path, dir.path])
        } else {
            status = try await run("/usr/bin/tar", ["-xf", archive.path, "-C", dir.path])
        }
        guard status == 0 else { throw LauncherError("Could not extract \(archive.lastPathComponent)") }
        // Downloaded binaries carry the quarantine flag; Wine can't load quarantined dylibs.
        _ = try? await run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", dir.path])
    }

    /// True if any process command line contains `needle` (case-insensitive).
    static func isRunning(_ needle: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-if", needle]
        p.standardOutput = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
