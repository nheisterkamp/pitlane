import Foundation

/// Streams a file to disk and reports progress. Uses a delegate session so large archives
/// never sit in memory.
final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<URL, Error>?
    private var destination: URL!
    private var onProgress: (@Sendable (Double) -> Void)?

    static func fetch(_ url: URL, to destination: URL,
                      progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        let d = Downloader()
        d.destination = destination
        d.onProgress = progress
        let session = URLSession(configuration: .default, delegate: d, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { cont in
            d.continuation = cont
            // Ask for the exact bytes: some CDNs (e.g. Microsoft's) label .tar.gz files with
            // Content-Encoding: gzip, and URLSession would then decompress them, breaking checksums.
            var request = URLRequest(url: url)
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            session.downloadTask(with: request).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData _: Int64, totalBytesWritten written: Int64,
                    totalBytesExpectedToWrite expected: Int64) {
        guard expected > 0 else { return }
        onProgress?(Double(written) / Double(expected))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw LauncherError("Download failed (HTTP \(http.statusCode)): \(downloadTask.originalRequest?.url?.absoluteString ?? "")")
            }
            let partial = destination.appendingPathExtension("part")
            try? FileManager.default.removeItem(at: partial)
            try FileManager.default.moveItem(at: location, to: partial)
            try FileManager.default.moveItem(at: partial, to: destination)
            continuation?.resume(returning: destination)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { continuation?.resume(throwing: error); continuation = nil }
    }
}

/// Minimal GitHub "latest release" lookup so runtimes stay current without shipping URLs
/// that rot.
enum GitHub {
    struct Release: Decodable {
        let tag_name: String
        let assets: [Asset]
    }
    struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
    }

    static func latest(_ repo: String) async throws -> Release {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw LauncherError("GitHub lookup for \(repo) failed (HTTP \(http.statusCode))")
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }
}

struct LauncherError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
