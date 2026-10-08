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

    /// Starts a process in its own session so it survives the launcher quitting. (launchd kills
    /// whatever is left in an app's process group when the app exits, which a plain
    /// `Process` child would be.)
    static func spawnDetached(_ tool: String, _ args: [String], env: [String: String],
                              cwd: URL? = nil, log: URL? = nil) throws {
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        let out = log?.path ?? "/dev/null"
        posix_spawn_file_actions_addopen(&actions, 1, out, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)
        if let cwd { posix_spawn_file_actions_addchdir_np(&actions, cwd.path) }

        let argv = ([tool] + args).map { strdup($0) } + [nil]
        let envp = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, tool, &actions, &attr, argv, envp)
        guard rc == 0 else { throw LauncherError("Could not start \(tool): \(String(cString: strerror(rc)))") }
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
