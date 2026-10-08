import Foundation

/// Direct3D 11 → Metal translation layer used for the game.
enum Backend: String, Codable, CaseIterable, Identifiable {
    case d3dmetal, dxmt, dxvk, wined3d

    var id: String { rawValue }

    var label: String {
        switch self {
        case .d3dmetal: "D3DMetal (Apple GPTK), fastest"
        case .dxmt: "DXMT (open source Metal)"
        case .dxvk: "DXVK + MoltenVK"
        case .wined3d: "WineD3D (OpenGL), compatibility"
        }
    }

    var short: String {
        switch self {
        case .d3dmetal: "D3DMetal"
        case .dxmt: "DXMT"
        case .dxvk: "DXVK"
        case .wined3d: "WineD3D"
        }
    }
}

struct Settings: Codable, Equatable {
    var backend: Backend = .d3dmetal
    var retina = false
    var metalHUD = false
    var quitOnLaunch = true
    var cleanupAfterExit = true
    var deprioritizeUbisoft = true
    var displayMode: DisplayMode = .fullscreen
    /// nil keeps whatever size the game has saved.
    var windowSize: WindowSize?
    /// Wine error output in the logs. Off by default: logging costs CPU on every call.
    var debugLogging = false
    /// What RetinaMode was last written to the registry as, to skip the write when unchanged.
    var appliedRetina: Bool?

    init() {}

    /// Missing keys (from older versions) fall back to defaults instead of failing the decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        backend = (try? c.decodeIfPresent(Backend.self, forKey: .backend)) ?? d.backend
        retina = (try? c.decodeIfPresent(Bool.self, forKey: .retina)) ?? d.retina
        metalHUD = (try? c.decodeIfPresent(Bool.self, forKey: .metalHUD)) ?? d.metalHUD
        quitOnLaunch = (try? c.decodeIfPresent(Bool.self, forKey: .quitOnLaunch)) ?? d.quitOnLaunch
        cleanupAfterExit = (try? c.decodeIfPresent(Bool.self, forKey: .cleanupAfterExit)) ?? d.cleanupAfterExit
        deprioritizeUbisoft = (try? c.decodeIfPresent(Bool.self, forKey: .deprioritizeUbisoft)) ?? d.deprioritizeUbisoft
        displayMode = (try? c.decodeIfPresent(DisplayMode.self, forKey: .displayMode)) ?? d.displayMode
        debugLogging = (try? c.decodeIfPresent(Bool.self, forKey: .debugLogging)) ?? d.debugLogging
        windowSize = try? c.decodeIfPresent(WindowSize.self, forKey: .windowSize)
        appliedRetina = try? c.decodeIfPresent(Bool.self, forKey: .appliedRetina)
    }

    private static let url = Paths.root.appendingPathComponent("settings.json")

    static func load() -> Settings {
        guard let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return s
    }

    func save() {
        try? Paths.ensure()
        try? JSONEncoder().encode(self).write(to: Self.url, options: .atomic)
    }
}
