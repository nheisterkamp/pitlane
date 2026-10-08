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
