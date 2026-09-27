import Foundation
import os

/// Plain-text diagnostic log in Caches/diag.log.
/// There is no Mac and no debugger in this setup, so this file is how problems
/// on the iPad reach the developer. "导出诊断日志" copies it into Documents/诊断,
/// where the Files app and iTunes file sharing can read it.
final class DiagLog: @unchecked Sendable {
    static let shared = DiagLog()

    private let queue = DispatchQueue(label: "daydayup.diaglog")
    private let url: URL
    private let maxBytes = 512 * 1024
    private let stamp: ISO8601DateFormatter

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        url = caches.appendingPathComponent("diag.log")
        stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func log(_ category: String, _ message: String) {
        // Also into the system log (stays on the iPad), so a connected computer can follow it live:
        // pymobiledevice3 syslog live -m <app process name>.
        Logger(subsystem: "com.daydayup", category: category).notice("\(message, privacy: .public)")
        let line = "\(stamp.string(from: Date())) [\(category)] \(message)\n"
        let url = self.url
        let maxBytes = self.maxBytes
        queue.async {
            let fm = FileManager.default
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               let size = (attrs[.size] as? NSNumber)?.intValue, size > maxBytes,
               let data = try? Data(contentsOf: url) {
                // Keep the newer half.
                try? Data(data.suffix(maxBytes / 2)).write(to: url, options: .atomic)
            }
            let bytes = Data(line.utf8)
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: bytes)
                try? handle.close()
            } else {
                try? bytes.write(to: url, options: .atomic)
            }
        }
    }

    /// The whole log as text, after pending writes have finished.
    func contents() -> String {
        let url = self.url
        return queue.sync {
            guard let data = try? Data(contentsOf: url) else { return "" }
            return String(decoding: data, as: UTF8.self)
        }
    }

    func clear() {
        let url = self.url
        queue.sync {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
