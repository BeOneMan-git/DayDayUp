import Foundation

// Content pack schema, format 1.
// A pack (.ecopack) is a plain USTAR tar:
//   manifest.json, lexicon.json, articles/<id>.json, audio/<id>.m4a
// Every field that the pipeline may leave out is optional here.

struct PackManifest: Codable, Hashable, Sendable {
    var format: Int
    var packId: String
    var issue: String
    var part: Int
    var parts: Int
    var title: String
    var version: String
    var created: String?
    var articles: [ArticleMeta]
    var files: [String: FileInfo]?

    struct FileInfo: Codable, Hashable, Sendable {
        var size: Int
        var sha256: String
    }
}

struct ArticleMeta: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var section: String
    var fly: String?
    var title: String
    var dur: Double
    var nw: Int?
    var ns: Int?
    var n5: Int?
    var topics: [String]?
    var audio: String
}

// MARK: - Article

struct Article: Codable, Sendable {
    var id: String
    var issue: String
    var section: String
    var fly: String?
    var title: String
    var dur: Double
    var titleStart: Double?
    var titleEnd: Double?
    var paras: [Para]
}

struct Para: Codable, Sendable {
    /// "p" paragraph, "h" sub-heading, "rub" rubric (stand-first)
    var kind: String
    var sents: [Sent]
}

struct Sent: Codable, Sendable, Identifiable {
    var id: Int
    var s: Double?
    var e: Double?
    var unread: Bool?
    var zh: String?
    var gram: String?
    var allu: String?
    var ann: [Ann]?
    var toks: [Tok]

    var isTimed: Bool { s != nil && e != nil }
}

struct Tok: Codable, Sendable {
    var i: Int          // token index, unique inside the article
    var w: String       // word as printed
    var a: String?      // text printed before the word (opening quote, bracket)
    var z: String?      // text printed after the word (punctuation)
    var j: String?      // joiner: "-" hyphen, "_" nothing, nil space
    var k: String?      // lexicon key
    var s: Double?      // start time (s)
    var e: Double?      // end time (s)
    var B: Int?         // bold
    var I: Int?         // italic
    var S: Int?         // small caps
}

struct Ann: Codable, Sendable {
    /// "p" phrase, "e" entity, "n" number reading, "s" familiar word with a rare sense
    var t: String
    var r: [Int]        // token range [first, last]
    var text: String?
    var zh: String?
    var note: String?
    var bg: String?
    var m: String?
    var common: String?
    var read: String?
    var type: String?

    func covers(_ i: Int) -> Bool {
        guard r.count == 2 else { return false }
        return r[0] <= i && i <= r[1]
    }
}

// MARK: - Lexicon

struct LexFile: Codable, Sendable {
    var entries: [String: LexEntry]
    var xent: [String: XEnt]?
}

struct XEnt: Codable, Sendable {
    var zh: String?
    var bg: String?
}

struct LexEntry: Codable, Sendable {
    var b: Int?          // IELTS band 5...8
    var cefr: String?
    var awl: Int?
    var ph: String?      // dictionary phonetics
    var zh: String?      // dictionary glosses
    var pn: Bool?        // proper noun
    var num: Bool?       // number
    var card: Card?

    /// Same word from another pack: keep one card and append contexts that are new.
    mutating func mergeContexts(from other: LexEntry) {
        guard let more = other.card?.ctx, !more.isEmpty else { return }
        guard var c = card else { card = other.card; return }
        var list = c.ctx ?? []
        for x in more where !list.contains(where: { $0.sid == x.sid }) {
            list.append(x)
        }
        c.ctx = list
        card = c
    }
}

struct Card: Codable, Sendable {
    var pos: String?
    var ipa: IPA?
    var ctx: [Ctx]?
    var senses: [Sense]?
    var scene: String?
    var colloc: [Colloc]?
    var ielts: IeltsExample?
    var roots: [[String]]?
    var core: String?
    var memo: String?
    var family: [Family]?
    var diff: String?
}

struct IPA: Codable, Sendable {
    var br: String?
    var am: String?
    var ai: Bool?
}

/// Meaning in one sentence. sid = "<articleId>:<sentenceId>"; t = trap note (rare sense).
struct Ctx: Codable, Sendable, Hashable {
    var sid: String
    var m: String?
    var t: String?
}

struct Sense: Codable, Sendable {
    var pos: String?
    var zh: String?
    var en: String?
}

struct Colloc: Codable, Sendable {
    var en: String?
    var zh: String?
}

struct IeltsExample: Codable, Sendable {
    var en: String?
    var zh: String?
    var use: String?
}

struct Family: Codable, Sendable {
    var w: String?
    var pos: String?
    var zh: String?
}

// MARK: - References used by the app

/// An article is identified by issue + id. The pack id is looked up at runtime,
/// so a pack can be re-split later without breaking the learner's records.
struct ArticleRef: Hashable, Codable, Sendable {
    var issue: String
    var id: String

    var key: String { issue + "/" + id }

    init(issue: String, id: String) {
        self.issue = issue
        self.id = id
    }

    init?(key: String) {
        let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        issue = parts[0]
        id = parts[1]
    }
}

struct LibraryItem: Identifiable, Hashable, Sendable {
    var ref: ArticleRef
    var meta: ArticleMeta
    var packId: String
    var id: String { ref.key }
}

struct IssueGroup: Identifiable, Sendable {
    var issue: String
    var items: [LibraryItem]
    var id: String { issue }
}
