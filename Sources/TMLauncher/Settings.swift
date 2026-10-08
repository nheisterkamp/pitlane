import Foundation

/// Direct3D 11 → Metal translation layer used for the game. Only layers that run Trackmania
/// are offered: DXVK fails (DXVK 3 needs shaderCullDistance, which MoltenVK lacks, and this
/// engine's Mac driver loads MoltenVK directly, so KosmicKrisp can't be used; DXVK 1.10 hangs),
/// and WineD3D can't (macOS OpenGL 4.1 has no compute shaders). Old values decode to D3DMetal.
enum Backend: String, Codable, CaseIterable, Identifiable {
    case d3dmetal, dxmt

    var id: String { rawValue }

    var label: String {
        switch self {
        case .d3dmetal: "D3DMetal (Apple Game Porting Toolkit)"
        case .dxmt: "DXMT (open source, supports MetalFX)"
        }
    }

    var short: String {
        switch self {
        case .d3dmetal: "D3DMetal"
        case .dxmt: "DXMT"
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
    /// MetalFX spatial upscaling of the output (DXMT only): render at 1/factor, upscale with MetalFX.
    var metalFX = false
    var metalFXFactor = 2.0
    /// Frame limit written to the game's MaxFps. nil keeps the game's own setting.
    var maxFps: Int?
    /// Mac keyboard: Command acts as Ctrl, Option as Alt (Wine Mac driver options).
    var commandIsCtrl = false
    var optionIsAlt = false
    /// Start Ubisoft Connect ourselves with Chromium memory switches (≈650 MB less while playing).
    var leanUbisoft = false
    /// Registry values last written, to skip the (slow) write when nothing changed.
    var appliedRegistry: [String: String] = [:]

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
        metalFX = (try? c.decodeIfPresent(Bool.self, forKey: .metalFX)) ?? d.metalFX
        metalFXFactor = (try? c.decodeIfPresent(Double.self, forKey: .metalFXFactor)) ?? d.metalFXFactor
        maxFps = try? c.decodeIfPresent(Int.self, forKey: .maxFps)
        commandIsCtrl = (try? c.decodeIfPresent(Bool.self, forKey: .commandIsCtrl)) ?? d.commandIsCtrl
        optionIsAlt = (try? c.decodeIfPresent(Bool.self, forKey: .optionIsAlt)) ?? d.optionIsAlt
        leanUbisoft = (try? c.decodeIfPresent(Bool.self, forKey: .leanUbisoft)) ?? d.leanUbisoft
        appliedRegistry = (try? c.decodeIfPresent([String: String].self, forKey: .appliedRegistry)) ?? d.appliedRegistry
    }

    /// Wine Mac driver registry values these settings map to.
    var registry: [String: String] {
        [
            "RetinaMode": retina ? "y" : "n",
            "LeftCommandIsCtrl": commandIsCtrl ? "y" : "n",
            "RightCommandIsCtrl": commandIsCtrl ? "y" : "n",
            "LeftOptionIsAlt": optionIsAlt ? "y" : "n",
            "RightOptionIsAlt": optionIsAlt ? "y" : "n",
        ]
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
