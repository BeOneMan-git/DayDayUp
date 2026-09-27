import Foundation
import CryptoKit

/// Plain text, normalisation and hashes for sentences (PKG-P03 / DATA-03).
/// The content pipeline (tools/make_packs.py) uses the same normalisation, so a hash made
/// in the app and one written into a pack agree.
enum SentenceText {
    /// Text as printed: before-text, word, after-text, then the joiner to the next token.
    static func plain(_ s: Sent) -> String {
        plain(s.toks)
    }

    static func plain(_ toks: [Tok]) -> String {
        var out = ""
        for (n, t) in toks.enumerated() {
            out += (t.a ?? "") + t.w + (t.z ?? "")
            if n < toks.count - 1 {
                switch t.j {
                case "-": out += "-"
                case "_": break
                default: out += " "
                }
            }
        }
        return out
    }

    /// Words of tokens first...last (inclusive), as printed, without the outer punctuation.
    static func span(_ toks: [Tok], first: Int, last: Int) -> String {
        let part = toks.filter { $0.i >= first && $0.i <= last }
        guard !part.isEmpty else { return "" }
        var out = ""
        for (n, t) in part.enumerated() {
            if n > 0 { out += t.a ?? "" }
            out += t.w
            if n < part.count - 1 {
                out += t.z ?? ""
                switch t.j {
                case "-": out += "-"
                case "_": break
                default: out += " "
                }
            }
        }
        return out
    }

    /// Character offset of token `index` inside `plain(toks)`.
    static func offset(ofToken index: Int, in toks: [Tok]) -> Int? {
        var count = 0
        for (n, t) in toks.enumerated() {
            count += (t.a ?? "").count
            if t.i == index { return count }
            count += t.w.count + (t.z ?? "").count
            if n < toks.count - 1 {
                switch t.j {
                case "-": count += 1
                case "_": break
                default: count += 1
                }
            }
        }
        return nil
    }

    /// Lower case, straight quotes, single spaces, trimmed.
    static func normalize(_ text: String) -> String {
        var s = text.lowercased()
        let swaps: [(String, String)] = [("\u{2019}", "'"), ("\u{2018}", "'"), ("\u{201C}", "\""),
                                         ("\u{201D}", "\""), ("\u{2013}", "-"), ("\u{2014}", "-"),
                                         ("\u{00A0}", " ")]
        for (a, b) in swaps { s = s.replacingOccurrences(of: a, with: b) }
        let parts = s.split(whereSeparator: { $0.isWhitespace })
        return parts.joined(separator: " ")
    }

    /// First 12 hex digits of SHA-256 of the normalised text.
    static func hash(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(normalize(text).utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(12))
    }

    /// The range of `needle` in `text` that starts at character `near`, or the closest one.
    static func range(of needle: String, in text: String, near offset: Int) -> Range<String.Index>? {
        guard !needle.isEmpty else { return nil }
        if offset >= 0, offset <= text.count,
           let start = text.index(text.startIndex, offsetBy: offset, limitedBy: text.endIndex),
           text[start...].hasPrefix(needle) {
            return start..<text.index(start, offsetBy: needle.count)
        }
        var best: Range<String.Index>?
        var bestDistance = Int.max
        var searchStart = text.startIndex
        while let r = text.range(of: needle, range: searchStart..<text.endIndex) {
            let d = abs(text.distance(from: text.startIndex, to: r.lowerBound) - offset)
            if d < bestDistance {
                bestDistance = d
                best = r
            }
            searchStart = text.index(after: r.lowerBound)
        }
        return best
    }
}
