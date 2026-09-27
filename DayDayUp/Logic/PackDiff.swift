import Foundation

/// Compares two revisions of one article sentence by sentence (PKG-P03, ACC-07).
/// A sentence keeps its learning links only when its text is unchanged, or when the pack
/// gives an explicit old → new mapping and the new sentence exists. Everything else is "unmapped":
/// the old record stays as it was, with its text snapshot.
struct ArticleDiff: Equatable {
    var article: ArticleRef
    var unchanged: Set<Int> = []
    var mapped: [Int: Int] = [:]        // old sid -> new sid (text may differ)
    var unmapped: Set<Int> = []         // changed or removed, no trusted mapping
    var added: Set<Int> = []

    var hasChanges: Bool { !mapped.isEmpty || !unmapped.isEmpty || !added.isEmpty }

    /// New sentence id for an old one, or nil when the old one has no trusted successor.
    func newSid(for old: Int) -> Int? {
        if unchanged.contains(old) { return old }
        return mapped[old]
    }
}

enum PackDiffer {
    /// sid -> hash of the sentence text.
    static func hashes(_ article: Article) -> [Int: String] {
        var out: [Int: String] = [:]
        for p in article.paras {
            for s in p.sents {
                out[s.id] = SentenceText.hash(SentenceText.plain(s))
            }
        }
        return out
    }

    /// `idMap`: the pack's explicit mapping for this article, old sid (as text) -> new sid or nil (removed).
    static func diff(article: ArticleRef, old: [Int: String], new: [Int: String],
                     idMap: [String: Int?]?) -> ArticleDiff {
        var d = ArticleDiff(article: article)
        for (sid, h) in old {
            if let explicit = idMap?[String(sid)] {
                if let target = explicit, new[target] != nil {
                    d.mapped[sid] = target
                } else {
                    d.unmapped.insert(sid)
                }
            } else if let nh = new[sid], nh == h {
                d.unchanged.insert(sid)
            } else {
                d.unmapped.insert(sid)
            }
        }
        d.added = Set(new.keys).subtracting(d.unchanged).subtracting(d.mapped.values)
        return d
    }
}
