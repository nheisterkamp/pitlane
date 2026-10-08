import CryptoKit
import Foundation

/// The Wine engine plus the renderers (D3DMetal, DXMT, DXVK, KosmicKrisp), both from
/// Sikarugir. Pinned by SHA-256: a newer engine is a one-line change here once it has been
/// tested with Ubisoft Connect. (Sikarugir's Wine 11 engine currently can't run wineboot on
/// macOS 27, and upstream Wine 9-11 leaves Ubisoft Connect blank; CX24 works.)
enum Runtime {
    struct Component {
        let file: String
        let url: URL
        let sha256: String
    }

    static let engine = Component(
        file: "WS12WineCX24.0.7_7.tar.xz",
        url: URL(string: "https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineCX24.0.7_7.tar.xz")!,
        sha256: "203f9e9fd6c2cc77e6525d798a434ced326145db34a356355e05659d3445fd1c")

    /// Template 1.0.21: D3DMetal 4.0b2 (GPTK 4), DXMT v0.80-244, DXVK 3.1.1, KosmicKrisp, MoltenVK.
    static let template = Component(
        file: "Template-1.0.21.tar.xz",
        url: URL(string: "https://github.com/Sikarugir-App/Template/releases/download/v1.0/Template-1.0.21.tar.xz")!,
        sha256: "bbe996e4e4375318485953d0c7818b7b4b0a4dc1f13303bcc584f99f7602f78d")

    static let id = "cx24.0.7_7-t1.0.21"
    static let description = "Wine CX24 · D3DMetal 4.0b2 · DXMT 0.80 · DXVK 3.1.1"

    static var dir: URL { Paths.runtimes.appendingPathComponent(id, isDirectory: true) }
    /// The engine's binaries resolve their dylibs via @rpath relative to this folder, so the
    /// wine bundle must live inside it.
    static var frameworks: URL { dir.appendingPathComponent("frameworks", isDirectory: true) }
    static var renderers: URL { frameworks.appendingPathComponent("renderer", isDirectory: true) }
    static var wine: URL { frameworks.appendingPathComponent("wswine.bundle/bin/wine") }
    static var wineserver: URL { frameworks.appendingPathComponent("wswine.bundle/bin/wineserver") }

    static var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: wine.path) }

    /// Vulkan ICD manifest for KosmicKrisp with an absolute library path.
    static func kosmicKrispICD() -> URL {
        let url = dir.appendingPathComponent("kosmickrisp_icd.json")
        if !FileManager.default.fileExists(atPath: url.path) {
            let lib = frameworks.appendingPathComponent("libvulkan_kosmickrisp.dylib").path
            let json = #"{"file_format_version":"1.0.1","ICD":{"library_path":"\#(lib)","api_version":"1.4.363"}}"#
            try? json.write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }

    static func install(status: @escaping @MainActor (String, Double?) -> Void) async throws {
        try Paths.ensure()
        var archives: [URL] = []
        for (i, c) in [engine, template].enumerated() {
            let label = i == 0 ? "Wine engine" : "graphics runtime"
            await status("Downloading \(label)…", 0)
            let file = try await Downloader.fetch(c.url, to: Paths.cache.appendingPathComponent(c.file)) { p in
                Task { @MainActor in status("Downloading \(label)…", p) }
            }
            await status("Verifying \(label)…", nil)
            guard try await sha256(file) == c.sha256 else {
                try? FileManager.default.removeItem(at: file)
                throw LauncherError("\(c.file) failed its checksum. Try again.")
            }
            archives.append(file)
        }

        await status("Unpacking runtime…", nil)
        let fm = FileManager.default
        let tmp = Paths.runtimes.appendingPathComponent(".unpack-\(id)", isDirectory: true)
        try? fm.removeItem(at: tmp)
        for a in archives { try await Shell.extract(a, into: tmp) }

        guard let templateApp = try fm.contentsOfDirectory(atPath: tmp.path).first(where: { $0.hasPrefix("Template") }) else {
            throw LauncherError("Unexpected runtime archive layout")
        }
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try fm.moveItem(at: tmp.appendingPathComponent("\(templateApp)/Contents/Frameworks"), to: frameworks)
        try fm.moveItem(at: tmp.appendingPathComponent("wswine.bundle"),
                        to: frameworks.appendingPathComponent("wswine.bundle"))
        try? fm.removeItem(at: tmp)
        // Keep disk usage down: the archives are only needed for a reinstall.
        for a in archives { try? fm.removeItem(at: a) }
        // Drop runtimes from older launcher versions.
        for old in (try? fm.contentsOfDirectory(atPath: Paths.runtimes.path)) ?? [] where old != id {
            try? fm.removeItem(at: Paths.runtimes.appendingPathComponent(old))
        }
        guard isInstalled else { throw LauncherError("Runtime install incomplete") }
    }

    private static func sha256(_ url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let h = try FileHandle(forReadingFrom: url)
            defer { try? h.close() }
            var hasher = SHA256()
            while let chunk = try h.read(upToCount: 8 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }
}
