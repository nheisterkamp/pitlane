import SwiftUI

struct ContentView: View {
    @EnvironmentObject var launcher: Launcher
    @Environment(\.openWindow) private var openWindow
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trackmania").font(.title2.bold())
                    Text(launcher.engineSummary)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { openWindow(id: "logs") } label: { Image(systemName: "doc.text.magnifyingglass") }
                    .buttonStyle(.borderless)
                    .help("Logs and diagnostics")
                Button { showSettings.toggle() } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless)
                    .help("Settings")
                    .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                        SettingsView().environmentObject(launcher).padding()
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(launcher.status)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(3)
                if let p = launcher.progress {
                    ProgressView(value: p).progressViewStyle(.linear)
                } else if launcher.busy {
                    ProgressView().progressViewStyle(.linear)
                }
            }
            .frame(minHeight: 44, alignment: .top)

            primaryButton
                .controlSize(.large)
        }
        .padding(20)
        .frame(width: 380)
    }

    @ViewBuilder private var primaryButton: some View {
        switch launcher.phase {
        case .needsSetup:
            wide("Install Wine + Ubisoft Connect") { await launcher.setup() }
        case .needsGame:
            HStack {
                wide("Install Trackmania") { await launcher.installGame() }
                Button("Recheck") { Task { await launcher.refresh() } }
            }
        case .ready:
            // Two Play buttons; the mode used last is the prominent one (and Return).
            HStack {
                ForEach(DisplayMode.allCases, id: \.self) { mode in
                    playButton(mode, last: launcher.settings.displayMode == mode)
                }
            }
        case .running:
            wide("Stop game") { await launcher.stop() }
        case .failed:
            HStack {
                wide("Retry") { await launcher.refresh() }
                Button("View logs") { openWindow(id: "logs") }
            }
        case .working:
            wide("Working…") {}.disabled(true)
        }
    }

    private func wide(_ title: String, _ action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
    }

    @ViewBuilder
    private func playButton(_ mode: DisplayMode, last: Bool) -> some View {
        let button = Button { Task { await launcher.play(mode) } } label: {
            Label("Play \(mode.label)",
                  systemImage: mode == .fullscreen ? "arrow.up.left.and.arrow.down.right" : "macwindow")
                .frame(maxWidth: .infinity)
        }
        if last {
            button.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var launcher: Launcher

    var body: some View {
        Form {
            Picker("Graphics", selection: $launcher.settings.backend) {
                ForEach(Backend.allCases) { b in
                    Text(b.label).tag(b)
                }
            }
            Toggle("Retina resolution (sharper, slower)", isOn: $launcher.settings.retina)
            Toggle("Metal performance HUD", isOn: $launcher.settings.metalHUD)
            Toggle("Debug logging (slower, for troubleshooting)", isOn: $launcher.settings.debugLogging)
            Toggle("Quit launcher when the game starts", isOn: $launcher.settings.quitOnLaunch)
            Toggle("Run Ubisoft Connect on efficiency cores while playing", isOn: $launcher.settings.deprioritizeUbisoft)
            Toggle("Shut down Ubisoft Connect after playing", isOn: $launcher.settings.cleanupAfterExit)
            Divider()
            HStack {
                Button("Open Ubisoft Connect") { Task { await launcher.openUbisoft() } }
                Button("Show files") { launcher.revealFiles() }
            }
            HStack {
                Button("Reinstall runtime") { Task { await launcher.updateRuntime() } }
                Button("Kill Wine") { Task { await launcher.stop() } }
            }
        }
        .frame(width: 340)
        .onChange(of: launcher.settings) { launcher.saveSettings() }
    }
}
