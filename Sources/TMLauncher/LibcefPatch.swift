import Foundation

/// Re-enables Chromium command-line switches in Ubisoft Connect's 32-bit libcef.dll.
///
/// Ubisoft sets `cef_settings_t.command_line_args_disabled`, so CEF ignores the
/// `--in-process-gpu --disable-gpu` switches the CrossOver-based engine adds. Without them
/// every renderer crashes and the Ubisoft Connect window stays blank. CrossOver patches this
/// in memory ("CW HACK 25737"); we patch the file, and redo it before every launch because
/// Ubisoft Connect restores libcef.dll when it self-updates.
///
/// Instead of a fixed offset we scan for the field copy `settings.command_line_args_disabled
/// = src->command_line_args_disabled` plus the instructions after it, which survives
/// relinks of the same CEF major version.
enum LibcefPatch {
    enum Result { case patched, already, unknown }

    // mov eax,[edi+34]; mov [esi+34],eax; mov eax,[edi+38]; mov [esi+38],eax;
    // lea eax,[esi+3c]; push ebx; push eax; push [edi+40]; push [edi+3c]
    private static let before: [UInt8] = [0x8B, 0x47, 0x34, 0x89, 0x46, 0x34, 0x8B, 0x47, 0x38, 0x89, 0x46, 0x38,
                                          0x8D, 0x46, 0x3C, 0x53, 0x50, 0xFF, 0x77, 0x40, 0xFF, 0x77, 0x3C]
    // Same, but `xor eax,eax; nop` instead of loading the flag.
    private static let after: [UInt8] = [0x8B, 0x47, 0x34, 0x89, 0x46, 0x34, 0x31, 0xC0, 0x90, 0x89, 0x46, 0x38,
                                         0x8D, 0x46, 0x3C, 0x53, 0x50, 0xFF, 0x77, 0x40, 0xFF, 0x77, 0x3C]

    /// Read-only check, for diagnostics.
    static func status(of url: URL) -> Result {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return .unknown }
        if ranges(of: after, in: data).count == 1 { return .already }
        return ranges(of: before, in: data).count == 1 ? .patched : .unknown
    }

    static func apply(to url: URL) -> Result {
        guard var data = try? Data(contentsOf: url) else { return .unknown }
        let afterHits = ranges(of: after, in: data)
        if afterHits.count == 1 { return .already }
        let hits = ranges(of: before, in: data)
        guard hits.count == 1, let range = hits.first else { return .unknown }
        data.replaceSubrange(range, with: after)
        do { try data.write(to: url, options: .atomic) } catch { return .unknown }
        return .patched
    }

    private static func ranges(of needle: [UInt8], in data: Data) -> [Range<Int>] {
        var found: [Range<Int>] = []
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            let bytes = buf.bindMemory(to: UInt8.self)
            let n = needle.count, first = needle[0]
            guard bytes.count >= n else { return }
            var i = 0
            while i <= bytes.count - n {
                if bytes[i] == first {
                    var j = 1
                    while j < n && bytes[i + j] == needle[j] { j += 1 }
                    if j == n { found.append(i..<(i + n)); if found.count > 1 { return } }
                }
                i += 1
            }
        }
        return found
    }
}
