import AppKit
import SwiftUI

@main
struct TMLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var launcher = Launcher()

    init() {
        // `TMLauncher --diagnostics` prints the report to the terminal without opening a window.
        if CommandLine.arguments.contains("--diagnostics") {
            print(Diagnostics.report())
            exit(0)
        }
        // Developer aid: `--snapshot out.png` renders the main view off-screen (never shown).
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            Self.snapshot(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        }
    }

    @MainActor
    private static func snapshot(to url: URL) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let launcher = Launcher()
        let host = NSHostingView(rootView: ContentView().environmentObject(launcher))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 380, height: 240),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        Task { await launcher.refresh() }
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        window.setContentSize(host.fittingSize)
        // Below the desktop wallpaper: on screen for the window server, invisible to the user.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        window.setFrameOrigin(NSPoint(x: 200, y: 200))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        try? p.run()
        p.waitUntilExit()
        let presets = WindowSize.presets()
        print("phase: \(launcher.phase), window sizes: fit=\(presets.fit?.label ?? "-"), \(presets.sizes.map(\.label))")
        exit(0)
    }

    var body: some Scene {
        Window("Trackmania", id: "main") {
            ContentView()
                .environmentObject(launcher)
                .task { await launcher.refresh() }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        Window("Trackmania Logs", id: "logs") {
            LogsView()
        }
        .defaultSize(width: 900, height: 560)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }
}
