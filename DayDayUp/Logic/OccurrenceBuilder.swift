import Foundation

/// Builds an Occurrence (where a word or chunk was met) from a sentence of a pack article,
/// with a text snapshot, the exact printed form, its position and the original-audio clip.
enum OccurrenceBuilder {
    static func make(ref: ArticleRef, sentence s: Sent, first: Int, last: Int, audioSha: String?) -> Occurrence {
        var o = Occurrence(issue: ref.issue, article: ref.id, sid: s.id)
        let lo = min(first, last), hi = max(first, last)
        o.r = [lo, hi]
        let plain = SentenceText.plain(s)
        o.sentence = plain
        o.textHash = SentenceText.hash(plain)
        let surface = SentenceText.span(s.toks, first: lo, last: hi)
        o.surface = surface.isEmpty ? nil : surface
        o.start = SentenceText.offset(ofToken: lo, in: s.toks)
        let part = s.toks.filter { $0.i >= lo && $0.i <= hi }
        if let start = part.first?.s, let end = part.last?.e, end > start {
            o.clip = [start, end]
            o.audioSha = audioSha
        }
        return o
    }

    /// The whole sentence as a clip (for 例句朗读 and the 听词 list).
    static func sentenceClip(_ s: Sent) -> [Double]? {
        if let start = s.s, let end = s.e, end > start { return [start, end] }
        let timed = s.toks.filter { $0.s != nil && $0.e != nil }
        if let start = timed.first?.s, let end = timed.last?.e, end > start { return [start, end] }
        return nil
    }

    /// Picks the sense that best matches a context meaning: most shared characters (Chinese glosses).
    static func bestSense(_ senses: [Sense], contextMeaning: String?) -> Int? {
        guard !senses.isEmpty else { return nil }
        guard let m = contextMeaning, !m.isEmpty else { return 0 }
        let ctx = Set(m.filter { !$0.isWhitespace && !$0.isPunctuation })
        var best = 0
        var bestScore = -1
        for (i, s) in senses.enumerated() {
            let zh = Set((s.zh ?? "").filter { !$0.isWhitespace && !$0.isPunctuation && $0 != "；" && $0 != "（" && $0 != "）" })
            let score = zh.intersection(ctx).count
            if score > bestScore {
                bestScore = score
                best = i
            }
        }
        return best
    }
}
