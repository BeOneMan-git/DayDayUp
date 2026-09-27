import Foundation

/// JSON coders shared by all data files: ISO 8601 dates, sorted keys.
enum DataCoding {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

/// An append-only log: one JSON object per line (DATA-08, DATA-11).
/// A damaged line (for example after a crash in the middle of a write) is skipped, never "repaired".
struct JSONLines<T: Codable> {
    let url: URL

    /// Adds records at the end. Creates the file on first use.
    func append(_ values: [T]) throws {
        guard !values.isEmpty else { return }
        var blob = Data()
        for v in values {
            var line = try DataCoding.encoder.encode(v)
            line.append(0x0A)
            blob.append(line)
        }
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fm.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let handle = try FileHandle(forUpdating: url)     // read + write: we look at the last byte
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        // A file that does not end with a newline had a partial last line: start on a fresh line.
        if end > 0 {
            try handle.seek(toOffset: end - 1)
            let last = try handle.read(upToCount: 1)
            if last != Data([0x0A]) {
                try handle.seekToEnd()
                try handle.write(contentsOf: Data([0x0A]))
            } else {
                try handle.seekToEnd()
            }
        }
        try handle.write(contentsOf: blob)
    }

    /// All readable records, oldest first, and the number of lines that could not be read.
    func readAll() -> (records: [T], badLines: Int) {
        guard let data = try? Data(contentsOf: url) else { return ([], 0) }
        return JSONLines.decode(data)
    }

    static func decode(_ data: Data) -> (records: [T], badLines: Int) {
        var out: [T] = []
        var bad = 0
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            if let value = try? DataCoding.decoder.decode(T.self, from: Data(line)) {
                out.append(value)
            } else {
                bad += 1
            }
        }
        return (out, bad)
    }

    static func encode(_ values: [T]) throws -> Data {
        var blob = Data()
        for v in values {
            blob.append(try DataCoding.encoder.encode(v))
            blob.append(0x0A)
        }
        return blob
    }
}
