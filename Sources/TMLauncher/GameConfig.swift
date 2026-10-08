import AppKit
import Foundation

enum DisplayMode: String, Codable, CaseIterable {
    /// Borderless window covering the screen: no display mode switch, instant Cmd-Tab.
    case fullscreen = "windowedfull"
    case windowed

    var label: String { self == .fullscreen ? "Fullscreen" : "Windowed" }
}

/// A windowed-mode size in macOS points (what you see on screen).
struct WindowSize: Codable, Hashable, Comparable {
    let width: Int
    let height: Int

    var label: String { "\(width) × \(height)" }

    /// Value for Trackmania's "ScreenSizeWin" ("1920x1080"). Wine pixels equal points unless
    /// Retina mode is on, in which case the game needs the backing-pixel size.
    func configValue(retina: Bool) -> String {
        let scale = retina ? Int(NSScreen.main?.backingScaleFactor ?? 2) : 1
        return "\(width * scale)x\(height * scale)"
    }

    static func < (a: WindowSize, b: WindowSize) -> Bool { a.width * a.height < b.width * b.height }

    private static let common: [WindowSize] = [
        (1280, 720), (1366, 768), (1600, 900), (1920, 1080), (2560, 1440), (3200, 1800), (3840, 2160), // 16:9
        (1440, 900), (1680, 1050), (1920, 1200), (2560, 1600),                                          // 16:10
        (2560, 1080), (3440, 1440), (5120, 2160),                                                       // 21:9
    ].map { WindowSize(width: $0.0, height: $0.1) }

    /// Window title bar height in points, so a chosen size never runs off screen.
    private static let titleBar = 28

    /// Common sizes that fit the screen, plus the largest 16:9 size that does.
    static func presets(for screen: NSScreen? = NSScreen.main) -> (fit: WindowSize?, sizes: [WindowSize]) {
        guard let frame = screen?.visibleFrame else { return (nil, common.filter { $0.width <= 1920 }) }
        let maxW = Int(frame.width), maxH = Int(frame.height) - titleBar
        let sizes = common.filter { $0.width <= maxW && $0.height <= maxH }.sorted()
        let w = min(maxW, maxH * 16 / 9) / 8 * 8
        let fit = WindowSize(width: w, height: w * 9 / 16)
        return (sizes.contains(fit) ? nil : fit, sizes)
    }
}

/// Edits Trackmania's own settings file before launch. The game reads it at startup.
enum GameConfig {
    static var url: URL {
        Paths.driveC.appendingPathComponent("users/crossover/Documents/Trackmania/Config/Default.json")
    }

    static func setDisplayMode(_ mode: DisplayMode) { set("DisplayMode", mode.rawValue) }

    static var windowSize: String? { value("ScreenSizeWin") }

    static var maxFps: Int? { number("MaxFps") }

    static func setMaxFps(_ fps: Int) { setNumber("MaxFps", fps) }

    static func setWindowSize(_ size: WindowSize, retina: Bool) { set("ScreenSizeWin", size.configValue(retina: retina)) }

    /// Reads a string value inside the `"Display"` block (not `"DisplaySafe"`).
    static func value(_ key: String) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let r = valueRange(key, in: text) else { return nil }
        return String(text[r])
    }

    /// Rewrites one string value inside the `"Display"` block, leaving Nadeo's formatting and
    /// every other setting untouched. No-op if there is no config yet (the game creates one).
    static func set(_ key: String, _ value: String) {
        guard var text = try? String(contentsOf: url, encoding: .utf8),
              let r = valueRange(key, in: text), text[r] != value else { return }
        text.replaceSubrange(r, with: value)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Numeric values are unquoted: `"MaxFps" : 150,`
    static func number(_ key: String) -> Int? {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let r = numberRange(key, in: text) else { return nil }
        return Int(text[r])
    }

    static func setNumber(_ key: String, _ value: Int) {
        guard var text = try? String(contentsOf: url, encoding: .utf8),
              let r = numberRange(key, in: text), Int(text[r]) != value else { return }
        text.replaceSubrange(r, with: String(value))
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func numberRange(_ key: String, in text: String) -> Range<String.Index>? {
        guard let block = text.range(of: #""Display"\s*:\s*\{"#, options: .regularExpression),
              let k = text.range(of: #""\#(key)"\s*:\s*"#, options: .regularExpression,
                                 range: block.upperBound..<text.endIndex) else { return nil }
        let digits = text[k.upperBound...].prefix { $0.isNumber }
        return digits.isEmpty ? nil : k.upperBound..<digits.endIndex
    }

    private static func valueRange(_ key: String, in text: String) -> Range<String.Index>? {
        guard let block = text.range(of: #""Display"\s*:\s*\{"#, options: .regularExpression),
              let k = text.range(of: #""\#(key)"\s*:\s*""#, options: .regularExpression,
                                 range: block.upperBound..<text.endIndex),
              let end = text[k.upperBound...].firstIndex(of: "\"") else { return nil }
        return k.upperBound..<end
    }
}
