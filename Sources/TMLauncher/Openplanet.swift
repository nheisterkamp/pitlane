import Foundation

/// Openplanet (openplanet.dev), the Trackmania plugin framework. Its NSIS installer refuses
/// the game folder under Wine, so we extract the payload with 7-Zip instead; that is all the
/// installer copies. It loads through dinput8.dll, which Wine is told to prefer (dinput8=n,b).
enum Openplanet {
    /// Official 7-Zip command-line build for macOS (universal), pinned.
    private static let sevenZip = Runtime.Component(
        file: "7z2604-mac.tar.xz",
        url: URL(string: "https://github.com/ip7z/7zip/releases/download/26.04/7z2604-mac.tar.xz")!,
        sha256: "bee04358cbcbc7106273cee0e8d72916db2696c48067a3538c34d8cd6fd16578")

    private static var tools: URL { Paths.root.appendingPathComponent("tools", isDirectory: true) }
    private static var sevenZipBinary: URL { tools.appendingPathComponent("7zz") }
    private static var gameDir: URL { Paths.gameExe.deletingLastPathComponent() }
    private static var versionFile: URL { gameDir.appendingPathComponent("Openplanet/.launcher-version") }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: gameDir.appendingPathComponent("Openplanet.dll").path)
    }

    static var installedVersion: String? {
        isInstalled ? ((try? String(contentsOf: versionFile, encoding: .utf8)) ?? "unknown version") : nil
    }

    /// Resolves the newest Openplanet "Next" (Trackmania 2020) build: its CDN URL carries the version.
    static func latest() async throws -> (version: String, url: URL) {
        let page = URL(string: "https://openplanet.dev/download/next")!
        let (html, _) = try await URLSession.shared.data(from: page)
        let text = String(decoding: html, as: UTF8.self)
        let ids = text.matches(of: /download\/get\?id=(\d+)/).compactMap { Int($0.output.1) }
        guard let id = ids.max() else { throw LauncherError("Couldn't find an Openplanet download") }

        // The get endpoint answers with a redirect to the CDN file, but only with a Referer.
        var req = URLRequest(url: URL(string: "https://openplanet.dev/download/get?id=\(id)")!)
        req.httpMethod = "HEAD"
        req.setValue(page.absoluteString, forHTTPHeaderField: "Referer")
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let final = resp.url, final.pathExtension == "exe",
              let v = final.lastPathComponent.firstMatch(of: /_([\d.]+)\.exe$/)?.output.1 else {
            throw LauncherError("Openplanet download didn't resolve to an installer")
        }
        return (String(v), final)
    }

    static func install(status: @escaping @MainActor (String, Double?) -> Void) async throws -> String {
        guard FileManager.default.fileExists(atPath: Paths.gameExe.path) else {
            throw LauncherError("Install Trackmania first")
        }
        try Paths.ensure()
        try await ensureSevenZip(status: status)

        await status("Looking up the latest Openplanet…", nil)
        let (version, url) = try await latest()
        let installer = Paths.cache.appendingPathComponent(url.lastPathComponent)
        _ = try await Downloader.fetch(url, to: installer) { p in
            Task { @MainActor in status("Downloading Openplanet \(version)…", p) }
        }

        await status("Installing Openplanet \(version)…", nil)
        let rc = try await Shell.run(sevenZipBinary.path,
                                     ["x", "-y", "-o\(gameDir.path)", installer.path,
                                      "-x!$PLUGINSDIR", "-x!OpenplanetUninstall.exe"],
                                     log: Paths.logs.appendingPathComponent("openplanet.log"))
        try? FileManager.default.removeItem(at: installer)
        guard rc == 0, isInstalled else { throw LauncherError("Openplanet extraction failed. See logs/openplanet.log.") }
        try? version.write(to: versionFile, atomically: true, encoding: .utf8)
        return version
    }

    /// Removes what the installer adds. User plugins and settings live in
    /// Documents/OpenplanetNext and are kept.
    static func remove() throws {
        for item in ["Openplanet.dll", "dinput8.dll", "Openplanet"] {
            let url = gameDir.appendingPathComponent(item)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }

    private static func ensureSevenZip(status: @escaping @MainActor (String, Double?) -> Void) async throws {
        guard !FileManager.default.isExecutableFile(atPath: sevenZipBinary.path) else { return }
        await status("Downloading 7-Zip…", nil)
        let archive = try await Downloader.fetch(sevenZip.url, to: Paths.cache.appendingPathComponent(sevenZip.file)) { _ in }
        guard try await Runtime.sha256(archive) == sevenZip.sha256 else {
            try? FileManager.default.removeItem(at: archive)
            throw LauncherError("7-Zip download failed its checksum")
        }
        let tmp = tools.appendingPathComponent(".7z")
        try await Shell.extract(archive, into: tmp)
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: sevenZipBinary)
        try FileManager.default.moveItem(at: tmp.appendingPathComponent("7zz"), to: sevenZipBinary)
        try? FileManager.default.removeItem(at: tmp)
        try? FileManager.default.removeItem(at: archive)
    }
}
