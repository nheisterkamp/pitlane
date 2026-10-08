import SwiftUI

@main
struct TMLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var launcher = Launcher()

    var body: some Scene {
        Window("Trackmania", id: "main") {
            ContentView()
                .environmentObject(launcher)
                .task { await launcher.refresh() }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }
}
