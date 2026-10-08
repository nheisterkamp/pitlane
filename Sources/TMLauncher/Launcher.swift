import AppKit
import Foundation

@MainActor
final class Launcher: ObservableObject {
    enum Phase: Equatable { case working, needsSetup, needsGame, ready, running, failed }

    @Published var phase: Phase = .working
    @Published var status = "Checking…" { didSet { if Self.echo { print(status) } } }
    @Published var progress: Double?
    @Published var settings = Settings.load()

    var busy: Bool { phase == .working }
    var engineSummary: String { "\(settings.backend.short) · \(Runtime.description.components(separatedBy: " · ").first ?? "")" }

    /// Headless mode (`--setup`) prints status lines instead of showing them.
    static var echo = false

    /// Results shown in Settings.
    @Published var updates: Updates.Report?
    @Published var usage: Maintenance.Usage?

    private static let trackmaniaId = "5595"
    private var gameWatch: Task<Void, Never>?

    private var prefixReady: Bool {
        FileManager.default.fileExists(atPath: Paths.prefix.appendingPathComponent("system.reg").path)
    }
    private var ubisoftReady: Bool { FileManager.default.fileExists(atPath: Paths.ubisoftExe.path) }
    /// Ubisoft Connect registers the install when it starts; while it downloads it stages files
    /// in `uplay_download`, which is empty once the install is complete.
    private var gameReady: Bool {
        let exe = Paths.gameExe
        guard installRegistered, FileManager.default.fileExists(atPath: exe.path) else { return false }
        let staging = exe.deletingLastPathComponent().appendingPathComponent("uplay_download")
        return ((try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? []).isEmpty
    }

    // MARK: - State

    func refresh() async {
        progress = nil
        if !Self.hasRosetta {
            fail("Rosetta 2 is required. In Terminal run:\nsoftwareupdate --install-rosetta --agree-to-license")
            return
        }
        if !Runtime.isInstalled || !prefixReady || !ubisoftReady {
            phase = .needsSetup
            status = "First run: downloads Wine, D3DMetal and Ubisoft Connect (about 550 MB)."
        } else if Wine.gameRunning {
            phase = .running
            status = "Trackmania is running."
            watchGame()
        } else if !gameReady {
            phase = .needsGame
            status = "Sign in to Ubisoft Connect and install Trackmania (free). This window updates when it's done."
            watchForInstall()
        } else {
            phase = .ready
            status = "Ready."
        }
    }

    func saveSettings() { settings.save() }

    // MARK: - Actions

    func setup(openStore: Bool = true) async {
        phase = .working
        do {
            if !Runtime.isInstalled {
                try await Runtime.install(status: report)
            }
            progress = nil
            if !prefixReady {
                status = "Creating Windows environment…"
                try await Wine.run(["wineboot", "--init"])
                // Wine's own D3D on Vulkan crashes Ubisoft Connect's GPU probe; OpenGL doesn't.
                try await Wine.regAdd(#"HKCU\Software\Wine\Direct3D"#, "renderer", "gl")
                try await Wine.regAdd(#"HKCU\Software\Wine\WineDbg"#, "ShowCrashDialog", "0", type: "REG_DWORD")
                try await applyRegistry(force: true)
                await Wine.waitIdle()
            }
            if !ubisoftReady {
                let installer = try await Downloader.fetch(
                    URL(string: "https://static3.cdn.ubi.com/orbit/launcher_installer/UbisoftConnectInstaller.exe")!,
                    to: Paths.cache.appendingPathComponent("UbisoftConnectInstaller.exe")) { p in
                        Task { @MainActor in self.status = "Downloading Ubisoft Connect…"; self.progress = p }
                    }
                progress = nil
                status = "Installing Ubisoft Connect…"
                try await Wine.run([installer.path, "/S"])
                await Wine.waitIdle()
                try? FileManager.default.removeItem(at: installer)
                guard ubisoftReady else { throw LauncherError("Ubisoft Connect did not install. See logs/setup.log.") }
            }
            // After "Reset Windows environment" the game waits outside the prefix.
            let restored = try Maintenance.restoreParkedGame()
            await refresh()
            if phase == .needsGame, openStore || restored { await installGame() }
        } catch {
            fail(error.localizedDescription)
        }
    }

    func installGame() async {
        let target = Paths.ubisoftDir.appendingPathComponent("games/Trackmania", isDirectory: true)
        var seeded = false
        if !FileManager.default.fileExists(atPath: target.path), let existing = Self.existingInstall() {
            phase = .working
            status = "Reusing your existing Trackmania files…"
            seeded = await Self.clone(existing, to: target)
        }
        await startUbisoft(args: ["uplay://install/\(Self.trackmaniaId)"])
        phase = .needsGame
        status = seeded
            ? "Existing game files copied. In Ubisoft Connect, install Trackmania to the default folder; it will only verify and patch."
            : "In Ubisoft Connect: sign in, then install Trackmania. This window updates when it's done."
        watchForInstall()
    }

    /// A Trackmania install from CrossOver/Steam or another prefix, to skip a 7 GB download.
    private static func existingInstall() -> URL? {
        let fm = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let bottles = home.appendingPathComponent("Library/Application Support/CrossOver/Bottles")
        var candidates: [URL] = []
        for b in (try? fm.contentsOfDirectory(atPath: bottles.path)) ?? [] {
            let c = bottles.appendingPathComponent(b).appendingPathComponent("drive_c/Program Files (x86)")
            candidates.append(c.appendingPathComponent("Ubisoft/Ubisoft Game Launcher/games/Trackmania"))
            candidates.append(c.appendingPathComponent("Steam/steamapps/common/Trackmania"))
        }
        return candidates.first { fm.fileExists(atPath: $0.appendingPathComponent("Trackmania.exe").path) }
    }

    /// APFS clone: instant and shares disk blocks with the original until either changes.
    private static func clone(_ src: URL, to dst: URL) async -> Bool {
        try? FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        let ok = (try? await Shell.run("/bin/cp", ["-c", "-R", src.path, dst.path])) == 0
        if ok {
            // Store-specific leftovers that Ubisoft Connect doesn't need.
            // Nadeo.ini marks the Steam edition (Updater=Steam), which makes Ubisoft Connect try to
            // install Steam; without it Ubisoft Connect verifies and restores its own.
            for junk in ["UbisoftConnectInstaller.exe", "Installer", "Nadeo.ini"] {
                try? FileManager.default.removeItem(at: dst.appendingPathComponent(junk))
            }
        }
        return ok
    }

    func openUbisoft() async { await startUbisoft(args: []) }

    func play(_ mode: DisplayMode) async {
        guard gameReady else { await refresh(); return }
        phase = .working
        status = "Starting Trackmania (\(mode.label.lowercased()))…"
        settings.displayMode = mode
        settings.save()
        do {
            try await prepare()
            GameConfig.setDisplayMode(mode)
            if let fps = settings.maxFps { GameConfig.setMaxFps(fps) }
            if mode == .windowed, let size = settings.windowSize {
                GameConfig.setWindowSize(size, retina: settings.retina)
            }
            if settings.leanUbisoft && !Wine.serverRunning {
                // Start Ubisoft Connect ourselves with memory-saving switches; the game connects to it.
                status = "Starting Ubisoft Connect (lean)…"
                try Wine.spawn(Paths.ubisoftDir.appendingPathComponent("upc.exe"), args: Wine.leanUbisoftSwitches,
                               settings: settings, log: "ubisoft.log")
                for _ in 0..<20 where !Shell.isRunning(#"[u]pc\.exe"#) { try? await Task.sleep(for: .seconds(1)) }
                try? await Task.sleep(for: .seconds(8))
            }
            // Start the game directly: Ubisoft Connect launches in the background for the login
            // only. Its "Play" button can hang on "Preparing to launch".
            try Wine.spawn(Paths.gameExe, settings: settings, log: "game.log")
            if settings.deprioritizeUbisoft || settings.cleanupAfterExit {
                try Wine.scheduleWatcher(demote: settings.deprioritizeUbisoft, cleanup: settings.cleanupAfterExit)
            }
            if settings.quitOnLaunch {
                status = "Launching… the launcher will close."
                if Self.echo { return } // headless `--play`: the caller exits
                try? await Task.sleep(for: .seconds(2))
                NSApp.terminate(nil)
            } else {
                phase = .running
                status = "Trackmania is running."
                watchGame()
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    func stop() async {
        phase = .working
        status = "Stopping Wine…"
        await Wine.killAll()
        await refresh()
    }

    /// Deletes and reinstalls the active runtime (e.g. after a damaged download).
    func repairRuntime() async {
        await perform("Repairing runtime…") {
            await Wine.killAll()
            try? FileManager.default.removeItem(at: Runtime.dir)
            try await Runtime.install(status: self.report)
            return "Runtime reinstalled."
        }
    }

    // MARK: Openplanet

    func installOpenplanet() async {
        await perform("Installing Openplanet…") {
            let v = try await Openplanet.install(status: self.report)
            return "Openplanet \(v) installed. Press F3 in game to open it."
        }
    }

    func removeOpenplanet() async {
        await perform("Removing Openplanet…") {
            try Openplanet.remove()
            return "Openplanet removed. Your plugins in Documents/OpenplanetNext are kept."
        }
    }

    // MARK: Updates

    func checkUpdates() async {
        await perform("Checking for updates…") {
            let r = try await Updates.check()
            self.updates = r
            if let v = r.templateVersion { return "Graphics runtime \(v) is available (Settings → Updates)." }
            return "Up to date."
        }
    }

    func installUpdate() async {
        guard let c = updates?.template else { return }
        await perform("Installing graphics runtime…") {
            await Wine.killAll()
            try await Updates.installTemplate(c, status: self.report)
            self.updates = nil
            return "Now using graphics runtime \(Runtime.active.templateVersion). Revert in Settings → Updates if anything breaks."
        }
    }

    func revertRuntime() async {
        await perform("Reverting to the tested runtime…") {
            await Wine.killAll()
            try await Updates.revertToPinned(status: self.report)
            return "Back on the tested runtime (\(Runtime.pinned.templateVersion))."
        }
    }

    // MARK: Maintenance

    func measureUsage() async { usage = await Maintenance.usage() }

    func clearCaches() async {
        await perform("Clearing caches…") {
            Maintenance.clearCaches()
            await self.measureUsage()
            return "Downloads, logs and temporary files cleared."
        }
    }

    /// Rebuilds the Windows environment and Ubisoft Connect, keeping the game files. You sign in
    /// to Ubisoft Connect again; it then verifies the game instead of downloading it.
    func resetEnvironment() async {
        phase = .working
        status = "Resetting Windows environment…"
        do {
            try await Maintenance.dismantlePrefix()
        } catch {
            fail(error.localizedDescription)
            return
        }
        await setup(openStore: true)
    }

    func uninstall() async {
        phase = .working
        status = "Uninstalling…"
        await Maintenance.uninstall()
    }

    func revealFiles() {
        try? Paths.ensure()
        NSWorkspace.shared.activateFileViewerSelecting([Paths.root])
    }

    // MARK: - Helpers

    private func startUbisoft(args: [String]) async {
        do {
            try await prepare()
            try Wine.spawn(Paths.ubisoftExe, args: args, settings: settings, log: "ubisoft.log")
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Fixes applied before anything in the prefix starts. Ubisoft Connect self-updates and
    /// restores its files, so these are re-checked every time (a few ms when already done).
    private func prepare() async throws {
        if !Wine.serverRunning {
            try await applyRegistry(force: false)
            disableUbisoftOverlay()
        }
        let cef = Paths.ubisoftDir.appendingPathComponent("libcef.dll")
        let result = await Task.detached { LibcefPatch.apply(to: cef) }.value
        if result == .unknown {
            status = "Note: unknown Ubisoft Connect build, so its window may stay blank. The game can still start."
        }
    }

    /// The Ubisoft overlay hooks the game's swapchain: a per-frame cost, and unreliable on Metal.
    private func disableUbisoftOverlay() {
        let url = Paths.ubisoftSettings
        guard var yaml = try? String(contentsOf: url, encoding: .utf8),
              let r = yaml.range(of: "overlay:\n  enabled: true") else { return }
        yaml.replaceSubrange(r, with: "overlay:\n  enabled: false")
        try? yaml.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Writes Mac driver options (Retina mode, keyboard mapping) that changed since last time.
    /// Each write costs a Wine start, so unchanged values are skipped. Wine reads them at start.
    private func applyRegistry(force: Bool) async throws {
        for (name, value) in settings.registry.sorted(by: { $0.key < $1.key })
        where force || settings.appliedRegistry[name] != value {
            try await Wine.regAdd(#"HKCU\Software\Wine\Mac Driver"#, name, value)
            settings.appliedRegistry[name] = value
        }
        settings.save()
    }

    /// Runs a maintenance task with the window showing progress, then restores the normal state.
    private func perform(_ title: String, _ work: @escaping () async throws -> String?) async {
        phase = .working
        status = title
        progress = nil
        do {
            let message = try await work()
            await refresh()
            if let message { status = message }
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func report(_ text: String, _ p: Double?) {
        status = text
        progress = p
    }

    private func watchForInstall() {
        gameWatch?.cancel()
        gameWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard let self else { return }
                if self.gameReady {
                    await self.refresh()
                    return
                }
            }
        }
    }

    private func watchGame() {
        gameWatch?.cancel()
        gameWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                if !Wine.gameRunning { await self.refresh(); return }
            }
        }
    }

    private var installRegistered: Bool {
        guard let reg = try? String(contentsOf: Paths.prefix.appendingPathComponent("system.reg"), encoding: .utf8)
        else { return false }
        return reg.contains(#"Ubisoft\\Launcher\\Installs\\5595]"#)
    }

    private func fail(_ message: String) {
        phase = .failed
        progress = nil
        status = message
    }

    private static let hasRosetta: Bool = {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        p.arguments = ["-x86_64", "/usr/bin/true"]
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit() } catch { return false }
        return p.terminationStatus == 0
    }()
}
