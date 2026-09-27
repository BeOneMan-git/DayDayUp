import Foundation

enum TarError: LocalizedError {
    case badHeader(String)
    case truncated
    case unsafePath(String)

    var errorDescription: String? {
        switch self {
        case .badHeader(let n): return "文件头损坏（\(n)）"
        case .truncated: return "文件不完整，可能没有传完"
        case .unsafePath(let n): return "包里有不安全的路径（\(n)）"
        }
    }
}

struct TarEntry {
    let name: String
    /// Byte range of the file body inside the archive data (absolute indices).
    let range: Range<Data.Index>
}

/// Minimal reader for POSIX ustar / v7 tar archives (the format of .ecopack).
/// Only regular files are returned; pax/GNU extension records are skipped.
enum TarReader {
    static func entries(in data: Data) throws -> [TarEntry] {
        var result: [TarEntry] = []
        let start = data.startIndex
        let end = data.endIndex
        var offset = start
        while offset + 512 <= end {
            let header = data[offset..<(offset + 512)]
            if header.allSatisfy({ $0 == 0 }) { break }            // end-of-archive marker

            let name = text(header, 0, 100)
            let sizeText = text(header, 124, 12)
            let typeFlag = header[header.startIndex + 156]
            let magic = text(header, 257, 6)
            let prefix = magic.hasPrefix("ustar") ? text(header, 345, 155) : ""

            guard let size = Int(sizeText, radix: 8), size >= 0 else {
                throw TarError.badHeader(name.isEmpty ? "?" : name)
            }
            let bodyStart = offset + 512
            let bodyEnd = bodyStart + size
            guard bodyEnd <= end else { throw TarError.truncated }

            let fullName = prefix.isEmpty ? name : prefix + "/" + name
            // "0" (0x30) or NUL = regular file
            if typeFlag == 0x30 || typeFlag == 0 {
                guard isSafe(fullName) else { throw TarError.unsafePath(fullName) }
                result.append(TarEntry(name: fullName, range: bodyStart..<bodyEnd))
            }
            offset = bodyStart + ((size + 511) / 512) * 512
        }
        return result
    }

    /// NUL-terminated ASCII field, trimmed.
    private static func text(_ header: Data, _ from: Int, _ length: Int) -> String {
        let lower = header.startIndex + from
        var bytes = header[lower..<(lower + length)]
        if let zero = bytes.firstIndex(of: 0) {
            bytes = bytes[bytes.startIndex..<zero]
        }
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }

    private static func isSafe(_ path: String) -> Bool {
        if path.isEmpty || path.hasPrefix("/") || path.contains("\\") { return false }
        return !path.split(separator: "/").contains("..")
    }
}
