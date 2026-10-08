import Foundation

enum DisplayMode: String, Codable, CaseIterable {
    /// Borderless window covering the screen: no display mode switch, instant Cmd-Tab.
    case fullscreen = "windowedfull"
    case windowed

    var label: String { self == .fullscreen ? "Fullscreen" : "Windowed" }
}

/// Edits Trackmania's own settings file before launch. The game reads it at startup.
enum GameConfig {
    static var url: URL {
        Paths.driveC.appendingPathComponent("users/crossover/Documents/Trackmania/Config/Default.json")
    }

    /// Rewrites only `"DisplayMode"` inside the `"Display"` block (not `"DisplaySafe"`),
    /// leaving Nadeo's formatting and every other setting untouched.
    static func setDisplayMode(_ mode: DisplayMode) {
        guard var text = try? String(contentsOf: url, encoding: .utf8),
              let block = text.range(of: #""Display"\s*:\s*\{"#, options: .regularExpression),
              let key = text.range(of: #""DisplayMode"\s*:\s*""#, options: .regularExpression,
                                   range: block.upperBound..<text.endIndex),
              let end = text[key.upperBound...].firstIndex(of: "\"")
        else { return } // no config yet: the game creates one on first start
        guard text[key.upperBound..<end] != mode.rawValue else { return }
        text.replaceSubrange(key.upperBound..<end, with: mode.rawValue)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
