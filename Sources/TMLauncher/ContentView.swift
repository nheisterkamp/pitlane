import SwiftUI

struct ContentView: View {
    @EnvironmentObject var launcher: Launcher
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
                .keyboardShortcut(.defaultAction)
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
            wide("Play") { await launcher.play() }
        case .running:
            wide("Stop game") { await launcher.stop() }
        case .failed:
            wide("Retry") { await launcher.refresh() }
        case .working:
            wide("Working…") {}.disabled(true)
        }
    }

    private func wide(_ title: String, _ action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
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
