import SwiftUI

struct ContentView: View {
    @EnvironmentObject var launcher: Launcher
    @Environment(\.openWindow) private var openWindow

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
                SettingsLink { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless)
                    .help("Settings (⌘,)")
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
        if mode == .windowed {
            // Split button: click plays, the arrow picks the window size.
            let menu = Menu {
                windowSizeItems
            } label: {
                Label("Play Windowed", systemImage: "macwindow").frame(maxWidth: .infinity)
            } primaryAction: {
                Task { await launcher.play(.windowed) }
            }
            .menuStyle(.button)
            .help("Window size: \(currentSizeLabel)")
            if last {
                menu.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            } else {
                menu.buttonStyle(.bordered)
            }
        } else {
            let button = Button { Task { await launcher.play(mode) } } label: {
                Label("Play Fullscreen", systemImage: "arrow.up.left.and.arrow.down.right")
                    .frame(maxWidth: .infinity)
            }
            if last {
                button.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            } else {
                button.buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var windowSizeItems: some View {
        let presets = WindowSize.presets()
        Section("Window size") {
            sizeItem(nil, "Keep game setting (\(GameConfig.windowSize?.replacingOccurrences(of: "x", with: " × ") ?? "default"))")
            if let fit = presets.fit { sizeItem(fit, "Fit screen (\(fit.label))") }
            ForEach(presets.sizes.reversed(), id: \.self) { sizeItem($0, $0.label) }
        }
    }

    private func sizeItem(_ size: WindowSize?, _ title: String) -> some View {
        Toggle(title, isOn: Binding(
            get: { launcher.settings.windowSize == size },
            set: { if $0 { launcher.settings.windowSize = size; launcher.saveSettings() } }))
    }

    private var currentSizeLabel: String {
        launcher.settings.windowSize?.label ?? "game setting"
    }
}
