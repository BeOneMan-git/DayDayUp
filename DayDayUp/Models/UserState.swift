import Foundation

/// Everything the learner produces lives in one JSON file (user.json).
/// A backup is simply a copy of this file.
/// Decoding is tolerant: a missing field falls back to its default,
/// so an older backup still opens in a newer app version.
struct UserState: Codable, Equatable {
    var schema: Int = 1
    var known: [String: Date] = [:]          // lexicon key -> marked "认识"
    var star: [String: Date] = [:]           // lexicon key -> added to 生词本
    var lookups: [String: Int] = [:]         // lexicon key -> times looked up
    var positions: [String: Double] = [:]    // article key -> last position (s)
    var heard: [String: [Int]] = [:]         // article key -> 10 s buckets heard (any mode)
    var heardText: [String: [Int]] = [:]     // article key -> 10 s buckets heard with the text on screen
    var daily: [String: Double] = [:]        // "yyyy-MM-dd" -> seconds of listening
    var lastArticle: String? = nil           // article key
    var lastBackup: Date? = nil
    var settings = ReaderSettings()

    init() {}

    enum CodingKeys: String, CodingKey {
        case schema, known, star, lookups, positions, heard, heardText, daily, lastArticle, lastBackup, settings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(Int.self, forKey: .schema) ?? 1
        known = try c.decodeIfPresent([String: Date].self, forKey: .known) ?? [:]
        star = try c.decodeIfPresent([String: Date].self, forKey: .star) ?? [:]
        lookups = try c.decodeIfPresent([String: Int].self, forKey: .lookups) ?? [:]
        positions = try c.decodeIfPresent([String: Double].self, forKey: .positions) ?? [:]
        heard = try c.decodeIfPresent([String: [Int]].self, forKey: .heard) ?? [:]
        heardText = try c.decodeIfPresent([String: [Int]].self, forKey: .heardText) ?? [:]
        daily = try c.decodeIfPresent([String: Double].self, forKey: .daily) ?? [:]
        lastArticle = try c.decodeIfPresent(String.self, forKey: .lastArticle)
        lastBackup = try c.decodeIfPresent(Date.self, forKey: .lastBackup)
        settings = try c.decodeIfPresent(ReaderSettings.self, forKey: .settings) ?? ReaderSettings()
    }

    // MARK: Progress helpers

    static let bucketSeconds = 10.0

    static func bucketCount(duration: Double) -> Int {
        max(1, Int((duration / bucketSeconds).rounded(.up)))
    }

    /// 0...1, full at 90 % coverage (the 听 ring)
    func listenProgress(_ key: String, duration: Double) -> Double {
        ring(heard[key]?.count ?? 0, duration)
    }

    /// 0...1, full at 90 % coverage with text visible (the 读 ring)
    func readProgress(_ key: String, duration: Double) -> Double {
        ring(heardText[key]?.count ?? 0, duration)
    }

    private func ring(_ n: Int, _ duration: Double) -> Double {
        let total = Double(UserState.bucketCount(duration: duration))
        return min(1, Double(n) / (total * 0.9))
    }

    func minutes(on day: String) -> Double {
        (daily[day] ?? 0) / 60
    }
}

struct ReaderSettings: Codable, Equatable {
    var fontStep: Int = 1          // 0 body, 1 title3, 2 title2, 3 title
    var threshold: Int = 6         // underline IELTS level >= threshold; 0 = off
    var showTrap: Bool = true      // 熟词僻义 dotted underline
    var showPhrase: Bool = false   // phrase dashed underline
    var pauseOnTap: Bool = true
    var follow: Bool = true
    var showZh: Bool = false
    var accent: String = "en-GB"   // TTS voice
    var rate: Double = 1.0

    init() {}

    enum CodingKeys: String, CodingKey {
        case fontStep, threshold, showTrap, showPhrase, pauseOnTap, follow, showZh, accent, rate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fontStep = try c.decodeIfPresent(Int.self, forKey: .fontStep) ?? 1
        threshold = try c.decodeIfPresent(Int.self, forKey: .threshold) ?? 6
        showTrap = try c.decodeIfPresent(Bool.self, forKey: .showTrap) ?? true
        showPhrase = try c.decodeIfPresent(Bool.self, forKey: .showPhrase) ?? false
        pauseOnTap = try c.decodeIfPresent(Bool.self, forKey: .pauseOnTap) ?? true
        follow = try c.decodeIfPresent(Bool.self, forKey: .follow) ?? true
        showZh = try c.decodeIfPresent(Bool.self, forKey: .showZh) ?? false
        accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? "en-GB"
        rate = try c.decodeIfPresent(Double.self, forKey: .rate) ?? 1.0
    }

    static let rates: [Double] = [0.75, 0.85, 1.0, 1.1, 1.25]
}

enum DayKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func of(_ date: Date) -> String { formatter.string(from: date) }
    static var today: String { of(Date()) }

    /// Keys for the last n days, oldest first.
    static func lastDays(_ n: Int) -> [String] {
        let cal = Calendar.current
        let now = Date()
        return (0..<n).reversed().compactMap { back in
            cal.date(byAdding: .day, value: -back, to: now).map(of)
        }
    }
}
