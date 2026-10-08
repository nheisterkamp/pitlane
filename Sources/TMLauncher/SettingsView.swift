import GameController
import SwiftUI

/// The Settings window (⌘,).
struct SettingsView: View {
    @EnvironmentObject var launcher: Launcher
    @State var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }.tag(0)
            GraphicsTab().tabItem { Label("Graphics", systemImage: "display") }.tag(1)
            InputTab().tabItem { Label("Input", systemImage: "keyboard") }.tag(2)
            OpenplanetTab().tabItem { Label("Openplanet", systemImage: "puzzlepiece.extension") }.tag(3)
            MaintenanceTab().tabItem { Label("Maintenance", systemImage: "wrench.and.screwdriver") }.tag(4)
            UpdatesTab().tabItem { Label("Updates", systemImage: "arrow.down.circle") }.tag(5)
        }
        .environmentObject(launcher)
        .frame(width: 520)
        .onChange(of: launcher.settings) { launcher.saveSettings() }
    }
}

/// Status line shared by tabs that run tasks, so results are visible without the main window.
private struct TaskStatus: View {
    @EnvironmentObject var launcher: Launcher

    var body: some View {
        if launcher.busy || launcher.phase == .failed {
            HStack(spacing: 8) {
                if launcher.busy { ProgressView().controlSize(.small) }
                Text(launcher.status).font(.callout).foregroundStyle(launcher.phase == .failed ? .red : .secondary)
            }
        }
    }
}

private struct GeneralTab: View {
    @EnvironmentObject var launcher: Launcher

    var body: some View {
        Form {
            Section("When playing") {
                Toggle("Quit the launcher when the game starts", isOn: $launcher.settings.quitOnLaunch)
                Toggle("Run Ubisoft Connect on efficiency cores", isOn: $launcher.settings.deprioritizeUbisoft)
                Toggle("Shut down Ubisoft Connect after playing", isOn: $launcher.settings.cleanupAfterExit)
            }
            Section("Troubleshooting") {
                Toggle("Debug logging (slower)", isOn: $launcher.settings.debugLogging)
                HStack {
                    Button("Open Ubisoft Connect") { Task { await launcher.openUbisoft() } }
                    Button("Stop Wine") { Task { await launcher.stop() } }
                    Button("Show files") { launcher.revealFiles() }
                }
            }
            TaskStatus()
        }
        .formStyle(.grouped)
    }
}

private struct GraphicsTab: View {
    @EnvironmentObject var launcher: Launcher

    private var refreshRate: Int { NSScreen.main?.maximumFramesPerSecond ?? 60 }

    var body: some View {
        Form {
            Section {
                Picker("Translation layer", selection: $launcher.settings.backend) {
                    ForEach(Backend.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Retina resolution (sharper, up to 4× the pixels)", isOn: $launcher.settings.retina)
                Toggle("Performance HUD (FPS, frame time)", isOn: $launcher.settings.metalHUD)
            } footer: {
                Text("Changes apply the next time the game starts.").foregroundStyle(.secondary)
            }

            Section {
                Toggle("MetalFX upscaling", isOn: $launcher.settings.metalFX)
                    .disabled(launcher.settings.backend != .dxmt)
                if launcher.settings.metalFX && launcher.settings.backend == .dxmt {
                    Picker("Upscale factor", selection: $launcher.settings.metalFXFactor) {
                        Text("1.25×").tag(1.25)
                        Text("1.5×").tag(1.5)
                        Text("2× (renders a quarter of the pixels)").tag(2.0)
                    }
                }
            } header: {
                Text("Upscaling")
            } footer: {
                Text(launcher.settings.backend == .dxmt
                     ? "Renders at a lower resolution and upscales with Apple's MetalFX. Most useful on Retina screens."
                     : "Needs the DXMT translation layer. (D3DMetal's MetalFX only replaces DLSS, which Trackmania doesn't have.)")
                    .foregroundStyle(.secondary)
            }

            Section("Frame rate") {
                Picker("Frame limit", selection: $launcher.settings.maxFps) {
                    Text("Keep game setting\(GameConfig.maxFps.map { " (\($0))" } ?? "")").tag(Int?.none)
                    Text("Display refresh rate (\(refreshRate))").tag(Int?.some(refreshRate))
                    ForEach([60, 120, 144, 165, 240, 300].filter { $0 != refreshRate }, id: \.self) {
                        Text("\($0) FPS").tag(Int?.some($0))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct InputTab: View {
    @EnvironmentObject var launcher: Launcher
    @State private var controllers: [String] = []

    var body: some View {
        Form {
            Section {
                Toggle("Command key acts as Ctrl", isOn: $launcher.settings.commandIsCtrl)
                Toggle("Option key acts as Alt", isOn: $launcher.settings.optionIsAlt)
            } header: {
                Text("Mac keyboard")
            } footer: {
                Text("Applies the next time Wine starts.").foregroundStyle(.secondary)
            }
            Section("Controllers detected by macOS") {
                if controllers.isEmpty {
                    Text("None connected").foregroundStyle(.secondary)
                } else {
                    ForEach(controllers, id: \.self) { Text($0) }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidConnect)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)) { _ in reload() }
    }

    private func reload() { controllers = Controllers.names() }
}

private struct OpenplanetTab: View {
    @EnvironmentObject var launcher: Launcher
    @State private var latest: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Installed", value: Openplanet.installedVersion ?? "no")
                LabeledContent("Latest", value: latest ?? "…")
                HStack {
                    Button(Openplanet.isInstalled ? "Update Openplanet" : "Install Openplanet") {
                        Task { await launcher.installOpenplanet() }
                    }
                    .disabled(launcher.busy)
                    if Openplanet.isInstalled {
                        Button("Remove", role: .destructive) { Task { await launcher.removeOpenplanet() } }
                            .disabled(launcher.busy)
                    }
                }
            } footer: {
                Text("Openplanet is the plugin framework for Trackmania (openplanet.dev). Press F3 in game to open it. Online play requires Openplanet's signed plugin mode, which is the default.")
                    .foregroundStyle(.secondary)
            }
            TaskStatus()
        }
        .formStyle(.grouped)
        .task { latest = (try? await Openplanet.latest().version) ?? "unavailable" }
    }
}

private struct MaintenanceTab: View {
    @EnvironmentObject var launcher: Launcher
    @State private var confirmReset = false
    @State private var confirmUninstall = false

    var body: some View {
        Form {
            Section("Disk usage") {
                if let u = launcher.usage {
                    LabeledContent("Game", value: Maintenance.format(u.game))
                    LabeledContent("Windows environment + Ubisoft Connect", value: Maintenance.format(u.prefix))
                    LabeledContent("Wine and graphics runtime", value: Maintenance.format(u.runtime))
                    LabeledContent("Downloads and logs", value: Maintenance.format(u.cache + u.logs))
                    LabeledContent("Total", value: Maintenance.format(u.total)).bold()
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            Section {
                Button("Clear downloads, logs and temporary files") { Task { await launcher.clearCaches() } }
                Button("Repair runtime (download Wine and graphics again)") { Task { await launcher.repairRuntime() } }
                Button("Reset Windows environment…") { confirmReset = true }
                Button("Uninstall…", role: .destructive) { confirmUninstall = true }
            } footer: {
                Text("Game settings and replays in Documents/Trackmania are never removed.").foregroundStyle(.secondary)
            }
            .disabled(launcher.busy)
            TaskStatus()
        }
        .formStyle(.grouped)
        .task { await launcher.measureUsage() }
        .confirmationDialog("Reset the Windows environment?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { Task { await launcher.resetEnvironment() } }
        } message: {
            Text("Wine's Windows folder and Ubisoft Connect are reinstalled. The game files are kept; you sign in to Ubisoft Connect again and it verifies them instead of downloading.")
        }
        .confirmationDialog("Uninstall the Trackmania launcher?", isPresented: $confirmUninstall) {
            Button("Uninstall", role: .destructive) { Task { await launcher.uninstall() } }
        } message: {
            Text("Removes the game, Ubisoft Connect, Wine and the launcher app. Game settings and replays in Documents/Trackmania are kept.")
        }
    }
}

private struct UpdatesTab: View {
    @EnvironmentObject var launcher: Launcher

    var body: some View {
        Form {
            Section("Installed") {
                ForEach(Runtime.componentVersions, id: \.0) { LabeledContent($0.0, value: $0.1) }
                LabeledContent("Status", value: Runtime.isPinned ? "Tested configuration" : "Newer graphics runtime (not yet tested)")
            }
            Section {
                if let r = launcher.updates {
                    if let v = r.templateVersion {
                        LabeledContent("Graphics runtime", value: "\(v) available")
                        Button("Install graphics runtime \(v)") { Task { await launcher.installUpdate() } }
                    } else {
                        Text("The graphics runtime is up to date.")
                    }
                    if !r.engines.isEmpty {
                        LabeledContent("Newer Wine engines", value: r.engines.joined(separator: ", "))
                    }
                }
                HStack {
                    Button("Check for updates") { Task { await launcher.checkUpdates() } }
                    if !Runtime.isPinned {
                        Button("Revert to tested runtime") { Task { await launcher.revertRuntime() } }
                    }
                }
            } header: {
                Text("Sikarugir updates")
            } footer: {
                Text("New graphics runtimes (D3DMetal, DXMT, DXVK) are verified with GitHub's SHA-256 digest. If one causes problems, revert with one click. Newer Wine engines need testing with Ubisoft Connect first, so they're listed but not installed.")
                    .foregroundStyle(.secondary)
            }
            .disabled(launcher.busy)
            TaskStatus()
        }
        .formStyle(.grouped)
    }
}

enum Controllers {
    static func names() -> [String] {
        GCController.controllers().map { c in
            let kind = c.extendedGamepad != nil ? "gamepad" : (c.microGamepad != nil ? "remote" : "controller")
            return "\(c.vendorName ?? "Controller") (\(c.productCategory), \(kind))"
        }
    }
}
