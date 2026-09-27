import Foundation

// V0.5 plan, baseline, retests and activity (DATA-11). Saved as study.json; practice time is appended to
// activity.jsonl. Plans are snapshots with their reasons, so a later rule change never rewrites old days.

enum StudyCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case read, vocab, shadow, output

    var id: String { rawValue }

    var title: String {
        switch self {
        case .read: return "听读"
        case .vocab: return "词汇"
        case .shadow: return "跟读"
        case .output: return "说写"
        }
    }

    var symbol: String {
        switch self {
        case .read: return "headphones"
        case .vocab: return "character.book.closed"
        case .shadow: return "waveform"
        case .output: return "text.bubble"
        }
    }
}

/// One stretch of practice (MET-01). `background` = audio played while the app was not on screen:
/// kept apart and never counted as effective practice.
struct ActivityRecord: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var cat: StudyCategory
    var start: Date
    var end: Date
    var background: Bool
    var source: String?
    var day: String
    var tz: Int

    init(cat: StudyCategory, start: Date, end: Date, background: Bool, source: String?) {
        self.id = UUID().uuidString
        self.cat = cat
        self.start = start
        self.end = max(start, end)
        self.background = background
        self.source = source
        self.day = DayKey.of(start)
        self.tz = TimeZone.current.secondsFromGMT(for: start)
    }

    var seconds: Double { max(0, end.timeIntervalSince(start)) }
}

/// BASE-03: 先补基础，再冲 7 分.
enum StudyStage: String, Codable, CaseIterable, Identifiable, Sendable {
    case basic, developing, exam

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basic: return "基础表达"
        case .developing: return "表达发展"
        case .exam: return "雅思备考"
        }
    }

    var detail: String {
        switch self {
        case .basic: return "短材料、完整句、3–5 句短段；基础口语 45 秒。"
        case .developing: return "60–120 秒陈述、复述后追问、段落组织和改写。"
        case .exam: return "Part 1/2/3、Task 1/2、限时训练和完整模拟。"
        }
    }
}

struct StudySettings: Codable, Equatable, Sendable {
    var budgetMinutes = 60          // PLAN-P01: 60 or 90; custom 30–120
    var stage: StudyStage = .basic  // BASE-03
    var examType = "Academic"       // BASE-06 (DEC-06 default)
    var examDate: Date? = nil       // optional; no countdown is shown (D4)
    var reminderOn = false          // PLAN-P06: off by default
    var reminderHour = 20
    var reminderMinute = 0
    var quietStartHour: Int? = nil  // no reminder inside the quiet hours
    var quietEndHour: Int? = nil
    var windowDays = 7              // MET-P01: 7 or 30

    init() {}

    enum CodingKeys: String, CodingKey {
        case budgetMinutes, stage, examType, examDate, reminderOn, reminderHour, reminderMinute
        case quietStartHour, quietEndHour, windowDays
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        budgetMinutes = min(120, max(30, (try? c.decodeIfPresent(Int.self, forKey: .budgetMinutes)) ?? 60))
        stage = (try? c.decodeIfPresent(StudyStage.self, forKey: .stage)) ?? .basic
        examType = (try? c.decodeIfPresent(String.self, forKey: .examType)) ?? "Academic"
        examDate = try? c.decodeIfPresent(Date.self, forKey: .examDate)
        reminderOn = (try? c.decodeIfPresent(Bool.self, forKey: .reminderOn)) ?? false
        reminderHour = min(23, max(0, (try? c.decodeIfPresent(Int.self, forKey: .reminderHour)) ?? 20))
        reminderMinute = min(59, max(0, (try? c.decodeIfPresent(Int.self, forKey: .reminderMinute)) ?? 0))
        quietStartHour = try? c.decodeIfPresent(Int.self, forKey: .quietStartHour)
        quietEndHour = try? c.decodeIfPresent(Int.self, forKey: .quietEndHour)
        windowDays = (try? c.decodeIfPresent(Int.self, forKey: .windowDays)) == 30 ? 30 : 7
    }
}

/// Where a plan task's "开始" leads.
enum PlanTarget: Codable, Equatable, Hashable, Sendable {
    case vocabReview
    case article(issue: String, id: String)
    case shadow(issue: String, id: String, sid: Int?)
    case speaking(promptId: String)
    case writing(promptId: String)
    case retest(id: String)
    case baseline
    case articleCheck(issue: String, id: String, purpose: String)   // quiz: "delayed" / "weekly" / "baseline"
}

struct PlanTask: Codable, Identifiable, Equatable, Sendable {
    enum State: String, Codable, Sendable { case todo, done, deferred }

    var id: String
    var cat: StudyCategory
    var minutes: Int
    var title: String
    var reason: String
    var target: PlanTarget
    var state: State = .todo
    var doneAt: Date? = nil
    var deferredTo: String? = nil
}

/// One day's plan as it was made (DATA-11), with the rules version used.
struct PlanSnapshot: Codable, Equatable, Sendable {
    var day: String
    var tz: Int
    var created: Date
    var budget: Int
    var stage: StudyStage
    var tasks: [PlanTask]
    var notes: [String]
    var rulesVersion: Int

    static let currentRules = 1
}

struct BaselineResult: Codable, Equatable, Sendable {
    var done: Date
    var summary: String
    var refId: String?
    var numbers: [String: Double]
}

/// DIAG-01 / PLAN-P05: four short tasks, in 2–3 sittings. Descriptions only, never a band.
struct BaselineState: Codable, Equatable, Sendable {
    var started: Date? = nil
    var sittings: [Date] = []
    var listening: BaselineResult? = nil
    var speaking: BaselineResult? = nil
    var writing: BaselineResult? = nil
    var vocab: BaselineResult? = nil
    var finished: Date? = nil

    var doneCount: Int { [listening, speaking, writing, vocab].compactMap { $0 }.count }
    var isDone: Bool { doneCount == 4 }
}

/// IEL-F04 / IEL-P07 / PLAN-P04: a later check on new material, not the same prompt again.
struct Retest: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var kind: String          // "speaking" / "writing" / "article"
    var sourceId: String      // earlier work id, or article key
    var due: String           // day key
    var created: Date
    var promptId: String?     // the new prompt, chosen when it is started
    var done: Date?
    var resultId: String?     // new work id or quiz result id
}

/// quiz/<articleId>.json inside a content pack (comprehension questions; private content).
struct QuizFile: Codable, Sendable {
    var articleId: String
    var segment: [Double]?     // [start, end] seconds of the short listening passage
    var questions: [QuizQuestion]

    enum CodingKeys: String, CodingKey { case articleId, segment, questions }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        articleId = (try? c.decodeIfPresent(String.self, forKey: .articleId)) ?? ""
        segment = try? c.decodeIfPresent([Double].self, forKey: .segment)
        questions = c.lossyArray(QuizQuestion.self, forKey: .questions)
    }
}

struct QuizQuestion: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var kind: String           // main / detail / inference / word
    var q: String
    var zh: String?
    var options: [String]
    var answer: Int
    var explain: String?
    var inSegment: Bool?       // answerable from the short passage alone
}

struct QuizResult: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var article: String        // ArticleRef.key
    var at: Date
    var day: String
    var purpose: String        // "baseline" / "delayed" / "weekly" / "practice"
    var answers: [Int]
    var correct: Int
    var total: Int
    var seconds: Double
    var selfReport: String?
    var usedText: Bool         // the text was visible (a reading check, not a listening check)
}

struct StudyState: Codable, Equatable {
    var schema = 1
    var settings = StudySettings()
    var plans: [String: PlanSnapshot] = [:]
    var baseline = BaselineState()
    var retests: [Retest] = []
    var quizResults: [QuizResult] = []
    var articleDifficulty: [String: Int] = [:]      // article key -> 1…5, the learner's own rating
    var articleOpened: [String: Date] = [:]         // first time an article was opened (接触)
    var weeklyReports: [String: Date] = [:]         // week key (Monday) -> prepared
    var retractedIssues: [String] = []              // MET-06: issues the learner withdrew
    var lastPlanNote: String? = nil

    init() {}

    enum CodingKeys: String, CodingKey {
        case schema, settings, plans, baseline, retests, quizResults, articleDifficulty, articleOpened
        case weeklyReports, retractedIssues, lastPlanNote
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = (try? c.decodeIfPresent(Int.self, forKey: .schema)) ?? 1
        settings = (try? c.decodeIfPresent(StudySettings.self, forKey: .settings)) ?? StudySettings()
        plans = (try? c.decodeIfPresent([String: PlanSnapshot].self, forKey: .plans)) ?? [:]
        baseline = (try? c.decodeIfPresent(BaselineState.self, forKey: .baseline)) ?? BaselineState()
        retests = c.lossyArray(Retest.self, forKey: .retests)
        quizResults = c.lossyArray(QuizResult.self, forKey: .quizResults)
        articleDifficulty = (try? c.decodeIfPresent([String: Int].self, forKey: .articleDifficulty)) ?? [:]
        articleOpened = (try? c.decodeIfPresent([String: Date].self, forKey: .articleOpened)) ?? [:]
        weeklyReports = (try? c.decodeIfPresent([String: Date].self, forKey: .weeklyReports)) ?? [:]
        retractedIssues = (try? c.decodeIfPresent([String].self, forKey: .retractedIssues)) ?? []
        lastPlanNote = try? c.decodeIfPresent(String.self, forKey: .lastPlanNote)
    }
}

extension DayKey {
    /// Day key `n` days after `day` (negative = before), in the current calendar.
    static func adding(_ n: Int, to day: String) -> String {
        guard let date = DayKey.date(day), let moved = Calendar.current.date(byAdding: .day, value: n, to: date) else {
            return day
        }
        return of(moved)
    }

    /// Noon of that day (safe against DST edges).
    static func date(_ day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        comps.hour = 12
        return Calendar.current.date(from: comps)
    }

    /// Monday of the week that contains `day` (ISO weeks start on Monday).
    static func weekStart(_ day: String) -> String {
        guard let date = DayKey.date(day) else { return day }
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let weekday = cal.component(.weekday, from: date)      // 1 = Sunday
        let back = (weekday + 5) % 7                            // days since Monday
        return adding(-back, to: day)
    }

    /// Whole days from a to b (b later = positive).
    static func distance(from a: String, to b: String) -> Int {
        guard let da = DayKey.date(a), let db = DayKey.date(b) else { return 0 }
        return Int((db.timeIntervalSince(da) / 86_400).rounded())
    }
}

/// PLAN-P06 quiet hours, e.g. 22–7 wraps past midnight.
enum QuietHours {
    static func contains(hour: Int, start: Int, end: Int) -> Bool {
        if start == end { return false }
        return start < end ? (hour >= start && hour < end) : (hour >= start || hour < end)
    }
}
