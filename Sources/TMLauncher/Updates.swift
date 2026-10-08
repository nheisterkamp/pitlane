import Foundation

/// Looks for newer Sikarugir graphics packages (D3DMetal/DXMT/DXVK) and Wine engines.
enum Updates {
    struct Report {
        var template: Runtime.Component?   // newer than the active one, ready to install
        var templateVersion: String?
        var engines: [String]              // newer engine archives, for information only
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
            let digest: String?
        }
        let assets: [Asset]
    }

    static func check() async throws -> Report {
        async let templates = assets("Sikarugir-App/Template")
        async let engines = assets("Sikarugir-App/Engines")
        let active = Runtime.active

        // Template-1.0.N: compare by version components, not string order (1.0.9 < 1.0.21).
        let current = versionParts(active.templateVersion)
        let newest = try await templates
            .filter { $0.name.hasPrefix("Template-") && $0.name.hasSuffix(".tar.xz") }
            .compactMap { a -> (Release.Asset, [Int])? in
                let v = a.name.replacingOccurrences(of: "Template-", with: "").replacingOccurrences(of: ".tar.xz", with: "")
                return (a, versionParts(v))
            }
            .max { $0.1.lexicographicallyPrecedes($1.1) }

        var report = Report(template: nil, templateVersion: nil, engines: [])
        if let (asset, v) = newest, current.lexicographicallyPrecedes(v),
           let digest = asset.digest, digest.hasPrefix("sha256:") {
            report.template = Runtime.Component(file: asset.name, url: asset.browser_download_url,
                                                sha256: String(digest.dropFirst("sha256:".count)))
            report.templateVersion = v.map(String.init).joined(separator: ".")
        }

        // Engines in the same family (CX) with a higher version than ours.
        let ours = engineVersion(active.engine.file)
        report.engines = try await engines.map(\.name)
            .filter { $0.hasPrefix("WS12WineCX") && $0.hasSuffix(".tar.xz") }
            .filter { ours.lexicographicallyPrecedes(engineVersion($0)) }
            .map { $0.replacingOccurrences(of: ".tar.xz", with: "") }
        return report
    }

    /// Installs a newer graphics package, keeping the current Wine engine.
    static func installTemplate(_ c: Runtime.Component, status: @escaping @MainActor (String, Double?) -> Void) async throws {
        var m = Runtime.active
        m.template = c
        try await Runtime.activate(m, status: status)
    }

    static func revertToPinned(status: @escaping @MainActor (String, Double?) -> Void) async throws {
        try await Runtime.activate(Runtime.pinned, status: status)
    }

    private static func assets(_ repo: String) async throws -> [Release.Asset] {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/tags/v1.0")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw LauncherError("GitHub lookup for \(repo) failed (HTTP \(http.statusCode))")
        }
        return try JSONDecoder().decode(Release.self, from: data).assets
    }

    private static func versionParts(_ s: String) -> [Int] {
        s.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }

    /// "WS12WineCX24.0.7_7.tar.xz" → [24, 0, 7, 7]
    private static func engineVersion(_ file: String) -> [Int] {
        versionParts(file.replacingOccurrences(of: "WS12Wine", with: "").replacingOccurrences(of: ".tar.xz", with: ""))
    }
}
