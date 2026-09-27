import Foundation

// Everything produced in 跟读 and 雅思 practice. Saved as practice.json in
// Application Support; recordings are separate .m4a files in Recordings/.
// Decoding is tolerant like user.json: a missing field falls back to a default,
// and one damaged item is skipped instead of losing the whole file.

struct PracticeState: Codable, Equatable {
    var schema: Int = 1
    var shadow: [ShadowAttempt] = []
    var speaking: [SpeakingWork] = []
    var writing: [WritingWork] = []
    var reports: [ContentReport] = []
    var mocks: [MockSession] = []          // V0.4: full speaking mocks (IEL-P03)

    init() {}

    enum CodingKeys: String, CodingKey {
        case schema, shadow, speaking, writing, reports, mocks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = (try? c.decodeIfPresent(Int.self, forKey: .schema)) ?? 1
        shadow = c.lossyArray(ShadowAttempt.self, forKey: .shadow)
        speaking = c.lossyArray(SpeakingWork.self, forKey: .speaking)
        writing = c.lossyArray(WritingWork.self, forKey: .writing)
        reports = c.lossyArray(ContentReport.self, forKey: .reports)
        mocks = c.lossyArray(MockSession.self, forKey: .mocks)
    }
}

/// One take in 跟读 (V0.2: 听后模仿, one sentence).
struct ShadowAttempt: Codable, Equatable, Identifiable {
    var id: String
    var article: String          // ArticleRef.key
    var sid: Int
    var text: String             // the sentence when it was practised
    var created: Date
    var file: String?            // recording in Recordings/; nil if nothing was saved
    var seconds: Double
    var peakDb: Double
    var silent: Bool
    var interrupted: Bool
    var rate: Double             // speed of the original when it was played
    var mode: String             // ShadowMode raw value: "repeat", "shadow", "read", "retell"
    // V0.4
    var endSid: Int? = nil           // last sentence when the segment is longer than one sentence
    var crosstalk: Bool? = nil       // recorded through the speaker while the original played (ACC-17)
    var echoCancel: Bool? = nil      // echo-cancelled input was requested
    var output: String? = nil        // where the sound went: 耳机 / 扬声器 …
    var hints: [String]? = nil       // 脱稿复述: keywords the learner opened
    var followUp: String? = nil      // 脱稿复述: the follow-up question
    var followFile: String? = nil    // 脱稿复述: the recorded answer to it
    var followSeconds: Double? = nil
    var selfNote: String? = nil      // what the learner noticed afterwards
}

/// One spoken answer to a speaking prompt.
struct SpeakingWork: Codable, Equatable, Identifiable {
    var id: String
    var promptId: String
    var question: String
    var created: Date
    var prepSeconds: Double
    var speakSeconds: Double
    var target: Double
    var file: String?
    var peakDb: Double
    var silent: Bool
    var interrupted: Bool
    /// false = the learner had already seen the reference for this prompt (not independent).
    var independent: Bool
    var check: SelfCheck?
    var sawReference: Bool
    var feedback: [Feedback]
    // V0.4: exam part, mock membership, preparation notes, whether it was a first try at a new prompt.
    var part: String? = nil          // "basic", "p1", "p2", "p3"
    var mockId: String? = nil
    var notes: String? = nil
    var retestOf: String? = nil      // V0.5: a new-prompt retest of this earlier work (IEL-F04)

    enum CodingKeys: String, CodingKey {
        case id, promptId, question, created, prepSeconds, speakSeconds, target, file
        case peakDb, silent, interrupted, independent, check, sawReference, feedback
        case part, mockId, notes, retestOf
    }

    init(id: String, promptId: String, question: String, created: Date, prepSeconds: Double,
         speakSeconds: Double, target: Double, file: String?, peakDb: Double, silent: Bool,
         interrupted: Bool, independent: Bool) {
        self.id = id
        self.promptId = promptId
        self.question = question
        self.created = created
        self.prepSeconds = prepSeconds
        self.speakSeconds = speakSeconds
        self.target = target
        self.file = file
        self.peakDb = peakDb
        self.silent = silent
        self.interrupted = interrupted
        self.independent = independent
        self.check = nil
        self.sawReference = false
        self.feedback = []
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        promptId = try c.decodeIfPresent(String.self, forKey: .promptId) ?? ""
        question = try c.decodeIfPresent(String.self, forKey: .question) ?? ""
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date(timeIntervalSince1970: 0)
        prepSeconds = try c.decodeIfPresent(Double.self, forKey: .prepSeconds) ?? 0
        speakSeconds = try c.decodeIfPresent(Double.self, forKey: .speakSeconds) ?? 0
        target = try c.decodeIfPresent(Double.self, forKey: .target) ?? 45
        file = try c.decodeIfPresent(String.self, forKey: .file)
        peakDb = try c.decodeIfPresent(Double.self, forKey: .peakDb) ?? -160
        silent = try c.decodeIfPresent(Bool.self, forKey: .silent) ?? false
        interrupted = try c.decodeIfPresent(Bool.self, forKey: .interrupted) ?? false
        independent = try c.decodeIfPresent(Bool.self, forKey: .independent) ?? true
        check = try? c.decodeIfPresent(SelfCheck.self, forKey: .check)
        sawReference = try c.decodeIfPresent(Bool.self, forKey: .sawReference) ?? false
        feedback = c.lossyArray(Feedback.self, forKey: .feedback)
        part = try? c.decodeIfPresent(String.self, forKey: .part)
        mockId = try? c.decodeIfPresent(String.self, forKey: .mockId)
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
        retestOf = try? c.decodeIfPresent(String.self, forKey: .retestOf)
    }
}

/// One writing task. Version 1 is the first draft; later versions are rewrites.
/// A finished version is read-only.
struct WritingWork: Codable, Equatable, Identifiable {
    var id: String
    var promptId: String
    var task: String
    var created: Date
    var versions: [WritingVersion]
    var feedback: [Feedback]
    var sawReference: Bool
    // V0.4: task type and its conditions (IEL-P05/P06).
    var kind: String? = nil          // "basic", "task1", "task2"
    var minWords: Int? = nil
    var targetMinutes: Double? = nil
    var retestOf: String? = nil      // V0.5: a new-prompt retest of this earlier work (IEL-F04)

    enum CodingKeys: String, CodingKey {
        case id, promptId, task, created, versions, feedback, sawReference
        case kind, minWords, targetMinutes, retestOf
    }

    init(id: String, promptId: String, task: String, created: Date, versions: [WritingVersion]) {
        self.id = id
        self.promptId = promptId
        self.task = task
        self.created = created
        self.versions = versions
        self.feedback = []
        self.sawReference = false
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        promptId = try c.decodeIfPresent(String.self, forKey: .promptId) ?? ""
        task = try c.decodeIfPresent(String.self, forKey: .task) ?? ""
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date(timeIntervalSince1970: 0)
        versions = c.lossyArray(WritingVersion.self, forKey: .versions)
        feedback = c.lossyArray(Feedback.self, forKey: .feedback)
        sawReference = try c.decodeIfPresent(Bool.self, forKey: .sawReference) ?? false
        kind = try? c.decodeIfPresent(String.self, forKey: .kind)
        minWords = try? c.decodeIfPresent(Int.self, forKey: .minWords)
        targetMinutes = try? c.decodeIfPresent(Double.self, forKey: .targetMinutes)
        retestOf = try? c.decodeIfPresent(String.self, forKey: .retestOf)
    }

    var latest: WritingVersion? { versions.last }
    var isDraft: Bool { versions.last?.finished == nil }
}

struct WritingVersion: Codable, Equatable, Identifiable {
    var id: String
    var n: Int
    var text: String
    var started: Date
    var finished: Date?
    var seconds: Double
    /// false = written after seeing the reference or feedback.
    var independent: Bool
    var check: SelfCheck?
}

/// One full speaking mock (IEL-P03): Part 1, Part 2 and Part 3 answers in order.
/// An interruption means it does not count as a complete mock.
struct MockSession: Codable, Equatable, Identifiable {
    var id: String
    var created: Date
    var finished: Date?
    var interrupted: Bool
    var answers: [String]            // SpeakingWork ids, in order
    var seconds: Double              // total time from start to end
    var check: SelfCheck?
    var feedback: [Feedback]

    init(id: String, created: Date) {
        self.id = id
        self.created = created
        self.finished = nil
        self.interrupted = false
        self.answers = []
        self.seconds = 0
        self.check = nil
        self.feedback = []
    }

    enum CodingKeys: String, CodingKey {
        case id, created, finished, interrupted, answers, seconds, check, feedback
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        created = (try? c.decodeIfPresent(Date.self, forKey: .created)) ?? Date(timeIntervalSince1970: 0)
        finished = try? c.decodeIfPresent(Date.self, forKey: .finished)
        interrupted = (try? c.decodeIfPresent(Bool.self, forKey: .interrupted)) ?? false
        answers = (try? c.decodeIfPresent([String].self, forKey: .answers)) ?? []
        seconds = (try? c.decodeIfPresent(Double.self, forKey: .seconds)) ?? 0
        check = try? c.decodeIfPresent(SelfCheck.self, forKey: .check)
        feedback = c.lossyArray(Feedback.self, forKey: .feedback)
    }

    var isComplete: Bool { finished != nil && !interrupted }
}

/// Self-assessment on the four IELTS criteria: ticks and evidence, no score.
struct SelfCheck: Codable, Equatable {
    var created: Date
    var dims: [DimCheck]
}

struct DimCheck: Codable, Equatable, Identifiable {
    var id: String
    var answers: [Bool]
    var note: String
}

/// Feedback typed in by the learner, with its source (teacher, Claude, other).
struct Feedback: Codable, Equatable, Identifiable {
    var id: String
    var created: Date
    var source: String
    var text: String
}

/// "报错" from the reader: something in a content pack looks wrong.
struct ContentReport: Codable, Equatable, Identifiable {
    var id: String
    var created: Date
    var article: String
    var sid: Int
    var kind: String
    var note: String
    var text: String
}

enum WritingStats {
    static func words(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace })
            .filter { part in part.contains(where: { $0.isLetter || $0.isNumber }) }
            .count
    }

    static func sentences(_ text: String) -> Int {
        var count = 0
        var hasContent = false
        for ch in text {
            if ".!?。！？".contains(ch) {
                if hasContent {
                    count += 1
                    hasContent = false
                }
            } else if ch.isLetter || ch.isNumber {
                hasContent = true
            }
        }
        if hasContent { count += 1 }
        return count
    }
}
