import CryptoKit
import Foundation

/// The Wine engine plus the renderers (D3DMetal, DXMT, DXVK, KosmicKrisp), both from
/// Sikarugir. The pinned manifest is tested; Settings → Updates can switch to a newer graphics
/// package (verified against GitHub's SHA-256 digest) and back.
/// Sikarugir's Wine 11 engine currently can't run wineboot on macOS 27, and upstream Wine 9-11
/// leaves Ubisoft Connect blank, so the engine stays on CX24.
enum Runtime {
    struct Component: Codable, Equatable {
        let file: String
        let url: URL
        let sha256: String
    }

    struct Manifest: Codable, Equatable {
        var engine: Component
        var template: Component

        /// e.g. "cx24.0.7_7-t1.0.21"
        var id: String {
            let e = engine.file.replacingOccurrences(of: ".tar.xz", with: "")
                .replacingOccurrences(of: "WS12Wine", with: "").replacingOccurrences(of: "WS11Wine", with: "")
                .lowercased()
            let t = template.file.replacingOccurrences(of: ".tar.xz", with: "")
                .replacingOccurrences(of: "Template-", with: "t")
            return "\(e)-\(t)"
        }

        var templateVersion: String {
            template.file.replacingOccurrences(of: "Template-", with: "").replacingOccurrences(of: ".tar.xz", with: "")
        }
    }

    static let pinned = Manifest(
        engine: Component(
            file: "WS12WineCX24.0.7_7.tar.xz",
            url: URL(string: "https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineCX24.0.7_7.tar.xz")!,
            sha256: "203f9e9fd6c2cc77e6525d798a434ced326145db34a356355e05659d3445fd1c"),
        // Template 1.0.21: D3DMetal 4.0b2 (GPTK 4), DXMT v0.80-244, DXVK 3.1.1, KosmicKrisp, MoltenVK.
        template: Component(
            file: "Template-1.0.21.tar.xz",
            url: URL(string: "https://github.com/Sikarugir-App/Template/releases/download/v1.0/Template-1.0.21.tar.xz")!,
            sha256: "bbe996e4e4375318485953d0c7818b7b4b0a4dc1f13303bcc584f99f7602f78d"))

    private static var manifestURL: URL { Paths.root.appendingPathComponent("runtime.json") }

    /// The runtime in use: the pinned one unless the user switched in Settings → Updates.
    static var active: Manifest {
        guard let data = try? Data(contentsOf: manifestURL),
              let m = try? JSONDecoder().decode(Manifest.self, from: data) else { return pinned }
        return m
    }

    static var isPinned: Bool { active == pinned }

    static var id: String { active.id }
    static var dir: URL { Paths.runtimes.appendingPathComponent(id, isDirectory: true) }
    /// The engine's binaries resolve their dylibs via @rpath relative to this folder, so the
    /// wine bundle must live inside it.
    static var frameworks: URL { dir.appendingPathComponent("frameworks", isDirectory: true) }
    static var renderers: URL { frameworks.appendingPathComponent("renderer", isDirectory: true) }
    static var wine: URL { frameworks.appendingPathComponent("wswine.bundle/bin/wine") }
    static var wineserver: URL { frameworks.appendingPathComponent("wswine.bundle/bin/wineserver") }

    static var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: wine.path) }

    /// Versions read from the installed files, so the UI never claims what isn't there.
    static var componentVersions: [(String, String)] {
        func file(_ p: String) -> String? {
            (try? String(contentsOf: renderers.appendingPathComponent(p), encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let plist = renderers.appendingPathComponent("d3dmetal/external/D3DMetal.framework/Resources/Info.plist")
        let d3dm = (NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String)
        let wineVersion = (try? String(contentsOf: frameworks.appendingPathComponent("wswine.bundle/version"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return [("Wine", wineVersion ?? "?"), ("D3DMetal", d3dm ?? "?"), ("DXMT", file("dxmt/version") ?? "?"),
                ("Template", active.templateVersion)]
    }

    static var description: String {
        let v = Dictionary(uniqueKeysWithValues: componentVersions)
        // "WineCX 24.0.7 (revision 6)" → "Wine CX24.0.7"
        let wine = (v["Wine"] ?? "?").replacingOccurrences(of: "WineCX ", with: "CX")
            .replacingOccurrences(of: #" \(revision \d+\)"#, with: "", options: .regularExpression)
        return "Wine \(wine) · D3DMetal \(v["D3DMetal"] ?? "?")"
    }

    /// Makes `manifest` the active runtime, installing what's missing. Parts already present in
    /// another installed runtime are APFS-cloned instead of downloaded again.
    static func activate(_ manifest: Manifest, status: @escaping @MainActor (String, Double?) -> Void) async throws {
        let previous = active
        try save(manifest)
        do {
            try await install(status: status)
        } catch {
            try? save(previous)
            throw error
        }
    }

    private static func save(_ m: Manifest) throws {
        try Paths.ensure()
        if m == pinned { try? FileManager.default.removeItem(at: manifestURL); return }
        try JSONEncoder().encode(m).write(to: manifestURL, options: .atomic)
    }

    static func install(status: @escaping @MainActor (String, Double?) -> Void) async throws {
        try Paths.ensure()
        let fm = FileManager.default
        let m = active
        let installed = installedManifests()
        let tmp = Paths.runtimes.appendingPathComponent(".unpack-\(m.id)", isDirectory: true)
        try? fm.removeItem(at: tmp)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)

        // Engine → tmp/wswine.bundle
        if let donor = installed.first(where: { $0.value.engine == m.engine })?.key {
            await status("Reusing Wine engine…", nil)
            try await clone(donor.appendingPathComponent("frameworks/wswine.bundle"), to: tmp.appendingPathComponent("wswine.bundle"))
        } else {
            let a = try await fetch(m.engine, label: "Wine engine", status: status)
            await status("Unpacking Wine engine…", nil)
            try await Shell.extract(a, into: tmp)
            try? fm.removeItem(at: a)
        }

        // Template → tmp/Frameworks
        let frameworksTmp = tmp.appendingPathComponent("Frameworks")
        if let donor = installed.first(where: { $0.value.template == m.template })?.key {
            await status("Reusing graphics runtime…", nil)
            try await clone(donor.appendingPathComponent("frameworks"), to: frameworksTmp)
            try? fm.removeItem(at: frameworksTmp.appendingPathComponent("wswine.bundle"))
        } else {
            let a = try await fetch(m.template, label: "graphics runtime", status: status)
            await status("Unpacking graphics runtime…", nil)
            try await Shell.extract(a, into: tmp)
            try? fm.removeItem(at: a)
            guard let app = try fm.contentsOfDirectory(atPath: tmp.path).first(where: { $0.hasPrefix("Template") }) else {
                throw LauncherError("Unexpected graphics runtime archive layout")
            }
            try fm.moveItem(at: tmp.appendingPathComponent("\(app)/Contents/Frameworks"), to: frameworksTmp)
        }

        await status("Finishing runtime…", nil)
        try fm.moveItem(at: tmp.appendingPathComponent("wswine.bundle"), to: frameworksTmp.appendingPathComponent("wswine.bundle"))
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try fm.moveItem(at: frameworksTmp, to: frameworks)
        try JSONEncoder().encode(m).write(to: dir.appendingPathComponent("manifest.json"))
        try? fm.removeItem(at: tmp)
        // Keep only the active runtime (and the pinned one, so reverting is instant).
        for other in installed.keys where other.lastPathComponent != m.id && other.lastPathComponent != pinned.id {
            try? fm.removeItem(at: other)
        }
        guard isInstalled else { throw LauncherError("Runtime install incomplete") }
    }

    /// Installed runtime folders and what they contain.
    private static func installedManifests() -> [URL: Manifest] {
        var result: [URL: Manifest] = [:]
        for name in (try? FileManager.default.contentsOfDirectory(atPath: Paths.runtimes.path)) ?? [] where !name.hasPrefix(".") {
            let d = Paths.runtimes.appendingPathComponent(name, isDirectory: true)
            if let data = try? Data(contentsOf: d.appendingPathComponent("manifest.json")),
               let m = try? JSONDecoder().decode(Manifest.self, from: data) {
                result[d] = m
            } else if name == pinned.id {
                result[d] = pinned // installed before manifests existed
            }
        }
        return result
    }

    private static func fetch(_ c: Component, label: String,
                              status: @escaping @MainActor (String, Double?) -> Void) async throws -> URL {
        await status("Downloading \(label)…", 0)
        let file = try await Downloader.fetch(c.url, to: Paths.cache.appendingPathComponent(c.file)) { p in
            Task { @MainActor in status("Downloading \(label)…", p) }
        }
        await status("Verifying \(label)…", nil)
        guard try await sha256(file) == c.sha256 else {
            try? FileManager.default.removeItem(at: file)
            throw LauncherError("\(c.file) failed its checksum. Try again.")
        }
        return file
    }

    private static func clone(_ src: URL, to dst: URL) async throws {
        guard try await Shell.run("/bin/cp", ["-c", "-R", src.path, dst.path]) == 0 else {
            throw LauncherError("Could not copy \(src.lastPathComponent)")
        }
    }

    static func sha256(_ url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let h = try FileHandle(forReadingFrom: url)
            defer { try? h.close() }
            var hasher = SHA256()
            while let chunk = try h.read(upToCount: 8 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }
}
