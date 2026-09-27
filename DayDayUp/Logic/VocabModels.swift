import Foundation

// V0.3 vocabulary data (DATA-05…08). Saved as vocab.json (items, cards, settings)
// plus vocab-events.jsonl, an append-only log of every answer (never rewritten).
// Everything decodes tolerantly: a missing field falls back to its default.

/// The six task types (VOC-T01…T06). One item can have several; new items open only 认义.
enum VocabTask: String, Codable, CaseIterable, Identifiable, Sendable {
    case recognize, listen, spell, cloze, readAloud, produce

    var id: String { rawValue }

    var code: String {
        switch self {
        case .recognize: return "VOC-T01"
        case .listen: return "VOC-T02"
        case .spell: return "VOC-T03"
        case .cloze: return "VOC-T04"
        case .readAloud: return "VOC-T05"
        case .produce: return "VOC-T06"
        }
    }

    var title: String {
        switch self {
        case .recognize: return "认义"
        case .listen: return "听辨"
        case .spell: return "拼写"
        case .cloze: return "语境填空"
        case .readAloud: return "例句朗读"
        case .produce: return "主动表达"
        }
    }

    var detail: String {
        switch self {
        case .recognize: return "看词和语境，先想意思，再揭晓。"
        case .listen: return "只听声音，想出或写出这个词。"
        case .spell: return "看中文义、听声音，写出这个词。"
        case .cloze: return "原句挖空，填出这个词。"
        case .readAloud: return "听原句，录下自己读，再对照。只记证据。"
        case .produce: return "在新话题里用它说一句或写一句。"
        }
    }

    var ability: VocabAbility {
        switch self {
        case .recognize: return .meaning
        case .listen: return .listening
        case .spell, .cloze: return .form
        case .readAloud: return .readAloud
        case .produce: return .use
        }
    }

    /// Answer is checked against a target (typing), not only self-rated.
    var isObjective: Bool {
        self == .listen || self == .spell || self == .cloze
    }

    /// Seconds one answer usually takes, before the learner has history (used for the 10-minute budget).
    var defaultSeconds: Double {
        switch self {
        case .recognize: return 12
        case .listen: return 15
        case .spell: return 20
        case .cloze: return 25
        case .readAloud: return 40
        case .produce: return 60
        }
    }
}

/// What a task gives evidence for. Shown separately; never merged into one "mastered" number.
enum VocabAbility: String, CaseIterable, Identifiable, Sendable {
    case meaning, listening, form, readAloud, use

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meaning: return "认义"
        case .listening: return "听辨"
        case .form: return "拼写 / 填空"
        case .readAloud: return "朗读证据"
        case .use: return "主动使用"
        }
    }
}

/// Where a word or chunk was met: one sentence of one article, with a text snapshot
/// so the card still reads correctly after the pack is updated or deleted.
struct Occurrence: Codable, Hashable, Sendable {
    var issue: String
    var article: String
    var sid: Int
    var r: [Int]?            // first and last token index
    var surface: String?     // the word(s) as printed in that sentence
    var sentence: String?    // sentence text when saved
    var start: Int?          // character offset of `surface` in `sentence`
    var clip: [Double]?      // [start, end] seconds in the article audio
    var audioSha: String?    // the audio file the clip belongs to (nil = not known)
    var textHash: String?    // SentenceText.hash(sentence)
    var unmapped: Bool?      // a pack update changed this sentence and gave no mapping

    init(issue: String, article: String, sid: Int) {
        self.issue = issue
        self.article = article
        self.sid = sid
    }

    var ref: ArticleRef { ArticleRef(issue: issue, id: article) }
    var sentenceKey: String { "\(issue)/\(article)#\(sid)" }

    enum CodingKeys: String, CodingKey {
        case issue, article, sid, r, surface, sentence, start, clip, audioSha, textHash, unmapped
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        issue = try c.decode(String.self, forKey: .issue)
        article = try c.decode(String.self, forKey: .article)
        sid = try c.decode(Int.self, forKey: .sid)
        r = try? c.decodeIfPresent([Int].self, forKey: .r)
        surface = try? c.decodeIfPresent(String.self, forKey: .surface)
        sentence = try? c.decodeIfPresent(String.self, forKey: .sentence)
        start = try? c.decodeIfPresent(Int.self, forKey: .start)
        clip = try? c.decodeIfPresent([Double].self, forKey: .clip)
        audioSha = try? c.decodeIfPresent(String.self, forKey: .audioSha)
        textHash = try? c.decodeIfPresent(String.self, forKey: .textHash)
        unmapped = try? c.decodeIfPresent(Bool.self, forKey: .unmapped)
    }

    /// The sentence with `surface` replaced by a blank, for 语境填空 and 拼写.
    func blanked(_ blank: String = "＿＿＿") -> String? {
        guard let sentence, let surface, !surface.isEmpty else { return nil }
        if let start, let range = SentenceText.range(of: surface, in: sentence, near: start) {
            return sentence.replacingCharacters(in: range, with: blank)
        }
        if let range = sentence.range(of: surface) {
            return sentence.replacingCharacters(in: range, with: blank)
        }
        return nil
    }
}

/// One learning target: a sense of a word, or a lexical chunk (词群). DATA-05 / DATA-06.
struct VocabItem: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case sense, chunk }
    enum Origin: String, Codable, Sendable { case reader, annotation, legacyStar, csv, manual, family }

    var id: String
    var kind: Kind
    var key: String?             // lexicon key (sense only)
    var text: String             // headword or chunk text
    var pos: String?
    var gloss: String            // Chinese meaning of this sense or chunk
    var senseIndex: Int?         // index in the card's sense list when chosen
    var note: String?
    var variants: [String]?      // chunk: other forms
    var function: String?        // chunk: what it is used for, limits
    var sources: [Occurrence]
    var created: Date
    var origin: Origin
    var legacyKnown: Date?       // the old "认识" mark: history only
    var starred: Bool
    var archived: Bool

    init(id: String, kind: Kind, key: String?, text: String, gloss: String, created: Date, origin: Origin) {
        self.id = id
        self.kind = kind
        self.key = key
        self.text = text
        self.gloss = gloss
        self.sources = []
        self.created = created
        self.origin = origin
        self.starred = false
        self.archived = false
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, key, text, pos, gloss, senseIndex, note, variants, function, sources
        case created, origin, legacyKnown, starred, archived
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .sense
        key = try? c.decodeIfPresent(String.self, forKey: .key)
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? (key ?? "")
        pos = try? c.decodeIfPresent(String.self, forKey: .pos)
        gloss = (try? c.decodeIfPresent(String.self, forKey: .gloss)) ?? ""
        senseIndex = try? c.decodeIfPresent(Int.self, forKey: .senseIndex)
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        variants = try? c.decodeIfPresent([String].self, forKey: .variants)
        function = try? c.decodeIfPresent(String.self, forKey: .function)
        sources = c.lossyArray(Occurrence.self, forKey: .sources)
        created = (try? c.decodeIfPresent(Date.self, forKey: .created)) ?? Date(timeIntervalSince1970: 0)
        origin = (try? c.decodeIfPresent(Origin.self, forKey: .origin)) ?? .manual
        legacyKnown = try? c.decodeIfPresent(Date.self, forKey: .legacyKnown)
        starred = (try? c.decodeIfPresent(Bool.self, forKey: .starred)) ?? false
        archived = (try? c.decodeIfPresent(Bool.self, forKey: .archived)) ?? false
    }

    static func senseID(key: String, senseIndex: Int?) -> String {
        "s:\(key)#\(senseIndex.map(String.init) ?? "?")"
    }

    static func chunkID(_ text: String) -> String {
        "c:" + SentenceText.normalize(text)
    }

    var firstSource: Occurrence? { sources.first }
}

/// One task of one item, scheduled by FSRS. DATA-07.
struct VocabCard: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var itemId: String
    var task: VocabTask
    var created: Date
    var fsrs: FSRSCard
    var suspended: Bool
    var promptVersion: Int

    init(itemId: String, task: VocabTask, created: Date) {
        self.id = VocabCard.makeID(itemId: itemId, task: task)
        self.itemId = itemId
        self.task = task
        self.created = created
        self.fsrs = FSRSCard(due: created)
        self.suspended = false
        self.promptVersion = 1
    }

    static func makeID(itemId: String, task: VocabTask) -> String {
        itemId + "|" + task.rawValue
    }

    var isNew: Bool { fsrs.isNew }

    enum CodingKeys: String, CodingKey {
        case id, itemId, task, created, fsrs, suspended, promptVersion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        itemId = try c.decode(String.self, forKey: .itemId)
        task = try c.decode(VocabTask.self, forKey: .task)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? VocabCard.makeID(itemId: itemId, task: task)
        created = (try? c.decodeIfPresent(Date.self, forKey: .created)) ?? Date(timeIntervalSince1970: 0)
        fsrs = (try? c.decodeIfPresent(FSRSCard.self, forKey: .fsrs)) ?? FSRSCard(due: created)
        suspended = (try? c.decodeIfPresent(Bool.self, forKey: .suspended)) ?? false
        promptVersion = (try? c.decodeIfPresent(Int.self, forKey: .promptVersion)) ?? 1
    }
}

/// One line of vocab-events.jsonl. Events are only ever appended (DATA-08).
struct ReviewEvent: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case review      // an answer that updated the schedule
        case undo        // takes back the review in `undoes`
        case listen      // heard in the 听词 list; no scheduling
    }

    var id: String
    var kind: Kind
    var itemId: String
    var cardId: String?
    var task: VocabTask?
    var at: Date
    var tz: Int                  // seconds from GMT when it happened
    var day: String              // local yyyy-MM-dd when it happened
    var rating: Int?
    var correct: Bool?           // objective tasks
    var answer: String?
    var expected: String?
    var hint: Int?               // 0 none, 1 first letter, 2 meaning, 3 more
    var revealedEarly: Bool?     // answer shown before trying: never an independent success
    var userAccepted: Bool?      // "我的答案也可以"
    var firstOfDay: Bool?        // first answer of this card on this day
    var durationMs: Int?
    var scheduler: String?
    var retention: Double?
    var before: FSRSCard?
    var after: FSRSCard?
    var undoes: String?
    var evidence: String?        // recording file (Recordings/) or written text id
    var source: String?          // audio used: "clip" (original) or "tts" (system voice)

    init(kind: Kind, itemId: String, at: Date) {
        self.id = UUID().uuidString
        self.kind = kind
        self.itemId = itemId
        self.at = at
        self.tz = TimeZone.current.secondsFromGMT(for: at)
        self.day = DayKey.of(at)
    }

    /// A first answer without seeing the answer first, and not taken back.
    var isIndependent: Bool {
        kind == .review && revealedEarly != true
    }
}

struct VocabSettings: Codable, Equatable, Sendable {
    var retention = 0.9           // VOC-P01: 0.80–0.95
    var budgetMinutes = 10.0      // VOC-P02: 5–20, reviews and new tasks together
    var newPerDay = 5             // VOC-P03 / PLAN-P02: 0–15
    var listenGap = 3.0           // VOC-P06: 0–10 s
    var listenRate = 1.0          // VOC-P06: 0.75–1.25
    var listenMinutes = 10.0      // VOC-P07: 5–30; 0 = until stopped
    var listenEnglishOnly = false
    var listenRandom = false
    var preferOriginalAudio = true

    init() {}

    enum CodingKeys: String, CodingKey {
        case retention, budgetMinutes, newPerDay, listenGap, listenRate, listenMinutes
        case listenEnglishOnly, listenRandom, preferOriginalAudio
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        retention = min(0.95, max(0.80, (try? c.decodeIfPresent(Double.self, forKey: .retention)) ?? 0.9))
        budgetMinutes = min(20, max(5, (try? c.decodeIfPresent(Double.self, forKey: .budgetMinutes)) ?? 10))
        newPerDay = min(15, max(0, (try? c.decodeIfPresent(Int.self, forKey: .newPerDay)) ?? 5))
        listenGap = min(10, max(0, (try? c.decodeIfPresent(Double.self, forKey: .listenGap)) ?? 3))
        listenRate = min(1.25, max(0.75, (try? c.decodeIfPresent(Double.self, forKey: .listenRate)) ?? 1))
        listenMinutes = min(30, max(0, (try? c.decodeIfPresent(Double.self, forKey: .listenMinutes)) ?? 10))
        listenEnglishOnly = (try? c.decodeIfPresent(Bool.self, forKey: .listenEnglishOnly)) ?? false
        listenRandom = (try? c.decodeIfPresent(Bool.self, forKey: .listenRandom)) ?? false
        preferOriginalAudio = (try? c.decodeIfPresent(Bool.self, forKey: .preferOriginalAudio)) ?? true
    }
}

/// Load at the start of a study day, for the backlog rule (VOC-P04).
struct VocabDay: Codable, Equatable, Sendable {
    var dueAtStart: Int
    var estSeconds: Double
    var budgetSeconds: Double
    var studied: Bool

    var overBudget: Bool { estSeconds > budgetSeconds }
}

struct VocabState: Codable, Equatable {
    var schema = 1
    var items: [VocabItem] = []
    var cards: [VocabCard] = []
    var settings = VocabSettings()
    var days: [String: VocabDay] = [:]
    /// Day on which the learner chose to keep new tasks despite the backlog suggestion.
    var keepNewOn: String? = nil
    var migratedV02: Date? = nil

    init() {}

    enum CodingKeys: String, CodingKey {
        case schema, items, cards, settings, days, keepNewOn, migratedV02
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = (try? c.decodeIfPresent(Int.self, forKey: .schema)) ?? 1
        items = c.lossyArray(VocabItem.self, forKey: .items)
        cards = c.lossyArray(VocabCard.self, forKey: .cards)
        settings = (try? c.decodeIfPresent(VocabSettings.self, forKey: .settings)) ?? VocabSettings()
        days = (try? c.decodeIfPresent([String: VocabDay].self, forKey: .days)) ?? [:]
        keepNewOn = try? c.decodeIfPresent(String.self, forKey: .keepNewOn)
        migratedV02 = try? c.decodeIfPresent(Date.self, forKey: .migratedV02)
    }
}
