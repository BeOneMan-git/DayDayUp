import Foundation

// Seven pronunciation layers for 跟读 (SHD-A01…A07, DATA-04, SHD-AS).
// Pack file annotations/<articleId>.json holds the machine-made candidates, bound to each
// sentence's text hash and to the audio file hash. The learner's own changes (status, hidden,
// notes, reports) live in annotations-user.json and apply only while the sentence text is unchanged.

enum AnnLayer: String, Codable, CaseIterable, Identifiable, Sendable {
    case thought = "tg"        // 意群
    case stress = "st"         // 重音
    case linking = "li"        // 连读
    case weak = "wk"           // 弱读
    case elision = "el"        // 省音
    case assimilation = "as"   // 同化
    case intonation = "in"     // 语调

    var id: String { rawValue }

    var code: String {
        switch self {
        case .thought: return "SHD-A01"
        case .stress: return "SHD-A02"
        case .linking: return "SHD-A03"
        case .weak: return "SHD-A04"
        case .elision: return "SHD-A05"
        case .assimilation: return "SHD-A06"
        case .intonation: return "SHD-A07"
        }
    }

    var title: String {
        switch self {
        case .thought: return "意群"
        case .stress: return "重音"
        case .linking: return "连读"
        case .weak: return "弱读"
        case .elision: return "省音"
        case .assimilation: return "同化"
        case .intonation: return "语调"
        }
    }

    /// One line on what the mark means and how far it can be trusted.
    var detail: String {
        switch self {
        case .thought: return "一句话里的意义分组，用 / 分开。可以有多种合理分法。"
        case .stress: return "粗体是句中重读的词；点开看词典重音。句中重音随语境变化。"
        case .linking: return "‿ 表示两个词可能连起来读。没有停顿不等于一定连读。"
        case .weak: return "功能词不重读时可以读弱式，比如 to /tə/。强调时读强式也对。"
        case .elision: return "括号里的音在快读时可能省掉，比如 nex(t) day。不是必须省。"
        case .assimilation: return "相邻的音可能互相影响，比如 don't you → /ˈdəʊntʃu/。"
        case .intonation: return "↘ 下降、↗ 上升、↘↗ 降升。语调跟意思有关，和主播不同不等于错。"
        }
    }

    /// UI-P05: 意群 and 重音 on by default; the others off.
    var defaultOn: Bool { self == .thought || self == .stress }
}

enum AnnStatus: String, Codable, CaseIterable, Sendable {
    case suggestion = "sug"    // 教学建议: general teaching advice
    case verified = "chk"      // 原声已核对: the learner checked it against the recording
    case pending = "pend"      // 待核对: machine-made, nobody checked it (the default)
    case disputed = "disp"     // 有争议

    var title: String {
        switch self {
        case .suggestion: return "教学建议"
        case .verified: return "原声已核对"
        case .pending: return "待核对"
        case .disputed: return "有争议"
        }
    }
}

struct PronAnnotation: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var sid: Int
    var layer: AnnLayer
    var r: [Int]               // token range: [first, last]; linking/assimilation span two tokens
    var v: String?             // value: "/tə/", "t", "↘", "t+j→tʃ" …
    var src: String?           // "rule", "dict", "audio"
    var ev: String?            // evidence, e.g. "原声停顿 0.28 秒"
    var st: AnnStatus
    var note: String?

    enum CodingKeys: String, CodingKey {
        case id, sid, layer, r, v, src, ev, st, note
    }

    init(id: String, sid: Int, layer: AnnLayer, r: [Int], v: String? = nil, src: String? = nil,
         ev: String? = nil, st: AnnStatus = .pending, note: String? = nil) {
        self.id = id
        self.sid = sid
        self.layer = layer
        self.r = r
        self.v = v
        self.src = src
        self.ev = ev
        self.st = st
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        sid = try c.decode(Int.self, forKey: .sid)
        layer = try c.decode(AnnLayer.self, forKey: .layer)
        r = try c.decode([Int].self, forKey: .r)
        v = try? c.decodeIfPresent(String.self, forKey: .v)
        src = try? c.decodeIfPresent(String.self, forKey: .src)
        ev = try? c.decodeIfPresent(String.self, forKey: .ev)
        st = (try? c.decodeIfPresent(AnnStatus.self, forKey: .st)) ?? .pending
        note = try? c.decodeIfPresent(String.self, forKey: .note)
    }

    var first: Int { r.first ?? 0 }
    var last: Int { r.last ?? first }
}

/// annotations/<articleId>.json inside a content pack.
struct AnnotationFile: Codable, Sendable {
    var articleId: String
    var producer: String?
    var version: String?
    var audioSha: String?
    /// sid (as text) -> sentence hash when the annotations were made.
    var sentenceHashes: [String: String]
    var items: [PronAnnotation]

    enum CodingKeys: String, CodingKey {
        case articleId, producer, version, audioSha, sentenceHashes, items
    }

    init(articleId: String, sentenceHashes: [String: String], items: [PronAnnotation]) {
        self.articleId = articleId
        self.sentenceHashes = sentenceHashes
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        articleId = (try? c.decodeIfPresent(String.self, forKey: .articleId)) ?? ""
        producer = try? c.decodeIfPresent(String.self, forKey: .producer)
        version = try? c.decodeIfPresent(String.self, forKey: .version)
        audioSha = try? c.decodeIfPresent(String.self, forKey: .audioSha)
        sentenceHashes = (try? c.decodeIfPresent([String: String].self, forKey: .sentenceHashes)) ?? [:]
        items = c.lossyArray(PronAnnotation.self, forKey: .items)
    }
}

/// A problem the learner reported on one annotation.
struct AnnReport: Codable, Equatable, Sendable {
    var at: Date
    var kind: String          // 标错了 / 位置不对 / 读法不对 / 其他
    var note: String
}

/// The learner's own layer on top of one annotation. Bound to the sentence text it was made on.
struct AnnUserState: Codable, Equatable, Sendable {
    var status: AnnStatus?
    var hidden: Bool = false
    var note: String?
    var reports: [AnnReport] = []
    var sentenceHash: String
    var updated: Date

    init(sentenceHash: String, updated: Date) {
        self.sentenceHash = sentenceHash
        self.updated = updated
    }

    enum CodingKeys: String, CodingKey {
        case status, hidden, note, reports, sentenceHash, updated
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try? c.decodeIfPresent(AnnStatus.self, forKey: .status)
        hidden = (try? c.decodeIfPresent(Bool.self, forKey: .hidden)) ?? false
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        reports = c.lossyArray(AnnReport.self, forKey: .reports)
        sentenceHash = (try? c.decodeIfPresent(String.self, forKey: .sentenceHash)) ?? ""
        updated = (try? c.decodeIfPresent(Date.self, forKey: .updated)) ?? Date(timeIntervalSince1970: 0)
    }
}

/// annotations-user.json: the learner's changes and the layer switches per practice mode.
struct AnnotationUserFile: Codable, Equatable {
    var schema = 1
    /// "<issue>/<article>#<annotationId>" -> state.
    var entries: [String: AnnUserState] = [:]
    /// practice mode -> enabled layers (raw values). Missing = defaults.
    var layers: [String: [String]] = [:]

    init() {}

    enum CodingKeys: String, CodingKey {
        case schema, entries, layers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = (try? c.decodeIfPresent(Int.self, forKey: .schema)) ?? 1
        entries = (try? c.decodeIfPresent([String: AnnUserState].self, forKey: .entries)) ?? [:]
        layers = (try? c.decodeIfPresent([String: [String]].self, forKey: .layers)) ?? [:]
    }
}

/// What the workbench shows for one annotation after the learner's layer is applied.
struct EffectiveAnnotation: Identifiable, Hashable, Sendable {
    var ann: PronAnnotation
    var status: AnnStatus
    var hidden: Bool
    var note: String?
    var reports: Int
    var id: String { ann.id }
}

enum AnnotationResolver {
    static func key(ref: ArticleRef, id: String) -> String { "\(ref.key)#\(id)" }

    /// Annotations of one sentence that still fit its text (ACC-22): when the sentence changed since the
    /// annotations were made, none are shown; the learner's changes apply only to the text they were made on.
    static func resolve(file: AnnotationFile?, ref: ArticleRef, sentence: Sent,
                        user: AnnotationUserFile) -> (items: [EffectiveAnnotation], stale: Bool) {
        guard let file else { return ([], false) }
        let hash = SentenceText.hash(SentenceText.plain(sentence))
        let made = file.sentenceHashes[String(sentence.id)]
        let mine = file.items.filter { $0.sid == sentence.id }
        guard !mine.isEmpty else { return ([], false) }
        if let made, made != hash { return ([], true) }
        let out = mine.map { a -> EffectiveAnnotation in
            let u = user.entries[key(ref: ref, id: a.id)]
            let applies = u.map { $0.sentenceHash == hash } ?? false
            return EffectiveAnnotation(ann: a,
                                       status: applies ? (u?.status ?? a.st) : a.st,
                                       hidden: applies ? (u?.hidden ?? false) : false,
                                       note: applies ? u?.note : nil,
                                       reports: applies ? (u?.reports.count ?? 0) : 0)
        }
        return (out, false)
    }
}
