import AppKit
import Combine
import SwiftUI

struct LogsView: View {
    @State private var source: LogSource = .diagnostics
    @State private var text = ""
    @State private var filter = ""
    @State private var errorsOnly = false
    @State private var follow = true
    @State private var lastModified: Date?

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("Log", selection: $source) {
                    ForEach(LogSource.allCases) { s in
                        Text(s.exists ? s.label : "\(s.label) (none)").tag(s)
                    }
                }
                .labelsHidden()
                .frame(width: 250)

                TextField("Filter", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 120)
                Toggle("Errors only", isOn: $errorsOnly)
                Toggle("Follow", isOn: $follow)
                    .help("Reload when the file changes and scroll to the end")

                Spacer()
                Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Reload")
                Button { copy() } label: { Image(systemName: "doc.on.doc") }
                    .help("Copy what's shown")
                Button { reveal() } label: { Image(systemName: "folder") }
                    .help("Show in Finder")
            }
            .padding(10)

            Divider()
            LogTextView(text: shown, scrollToEnd: follow)
        }
        .frame(minWidth: 720, minHeight: 420)
        .onAppear(perform: reload)
        .onChange(of: source) { lastModified = nil; reload() }
        .onReceive(timer) { _ in
            // Diagnostics is cheap to regenerate but noisy to flicker; files reload on change only.
            guard follow, source != .diagnostics, source.modified != lastModified else { return }
            reload()
        }
    }

    private var shown: String {
        guard errorsOnly || !filter.isEmpty else { return text }
        let needle = filter.lowercased()
        return text.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
            let l = line.lowercased()
            if errorsOnly, !Self.errorWords.contains(where: l.contains) { return false }
            return needle.isEmpty || l.contains(needle)
        }.joined(separator: "\n")
    }

    private static let errorWords = ["err:", "error", "fail", "crash", "exception", "fatal", "unhandled", "not found", "abort"]

    private func reload() {
        let s = source
        lastModified = s.modified
        Task.detached(priority: .userInitiated) {
            let t = s.read()
            await MainActor.run { if source == s { text = t } }
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(shown, forType: .string)
    }

    private func reveal() {
        if let url = source.url, FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            try? Paths.ensure()
            NSWorkspace.shared.activateFileViewerSelecting([Paths.logs])
        }
    }
}

/// NSTextView instead of SwiftUI Text: selectable, and fast with large logs.
struct LogTextView: NSViewRepresentable {
    let text: String
    let scrollToEnd: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.isEditable = false
        tv.isRichText = false
        tv.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.textContainerInset = NSSize(width: 6, height: 6)
        tv.isAutomaticSpellingCorrectionEnabled = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let tv = scroll.documentView as! NSTextView
        guard tv.string != text else { return }
        tv.string = text
        if scrollToEnd { tv.scrollToEndOfDocument(nil) }
    }
}
