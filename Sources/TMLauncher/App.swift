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
        // `--setup` runs first-run setup headless (no window, Ubisoft Connect not opened).
        // With TMLAUNCHER_ROOT set, this tests a clean install without touching the real one.
        if CommandLine.arguments.contains("--setup") {
            Self.headlessSetup()
        }
        // `--play fullscreen|windowed` starts the game without showing the launcher
        // (usable from scripts, Raycast/Alfred or a Dock shortcut).
        if let i = CommandLine.arguments.firstIndex(of: "--play") {
            let mode: DisplayMode = CommandLine.arguments.dropFirst(i + 1).first == "windowed" ? .windowed : .fullscreen
            Self.headlessPlay(mode)
        }
        // Developer aid: `--snapshot out.png` renders the main view off-screen (never shown).
        // `--snapshot out.png settings 1` renders a Settings tab instead.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            let tab = args.count > i + 3 && args[i + 2] == "settings" ? Int(args[i + 3]) : nil
            Self.snapshot(to: URL(fileURLWithPath: args[i + 1]), settingsTab: tab)
        }
    }

    @MainActor
    private static func headlessSetup() -> Never {
        Launcher.echo = true
        let launcher = Launcher()
        let start = Date()
        Task { @MainActor in
            await launcher.setup(openStore: false)
            let ok = launcher.phase == .needsGame || launcher.phase == .ready
            print("RESULT: \(ok ? "OK" : "FAILED") phase=\(launcher.phase) in \(Int(Date().timeIntervalSince(start)))s")
            exit(ok ? 0 : 1)
        }
        RunLoop.main.run()
        exit(1)
    }

    @MainActor
    private static func headlessPlay(_ mode: DisplayMode) -> Never {
        Launcher.echo = true
        let launcher = Launcher()
        Task { @MainActor in
            await launcher.refresh()
            guard launcher.phase == .ready else {
                print("Not ready: \(launcher.status)")
                exit(1)
            }
            await launcher.play(mode)
            exit(launcher.phase == .failed ? 1 : 0)
        }
        RunLoop.main.run()
        exit(1)
    }

    @MainActor
    private static func snapshot(to url: URL, settingsTab: Int?) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let launcher = Launcher()
        let root: AnyView = settingsTab.map { AnyView(SettingsView(tab: $0).environmentObject(launcher)) }
            ?? AnyView(ContentView().environmentObject(launcher))
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 520, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        Task { await launcher.refresh() }
        RunLoop.main.run(until: Date().addingTimeInterval(settingsTab == nil ? 2 : 5))
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
        Window("Pitlane", id: "main") {
            ContentView()
                .environmentObject(launcher)
                .task { await launcher.refresh() }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        Window("Pitlane Logs", id: "logs") {
            LogsView()
        }
        .defaultSize(width: 900, height: 560)

        SwiftUI.Settings {
            SettingsView().environmentObject(launcher)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }
}
