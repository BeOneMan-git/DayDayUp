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
    /// Old text size step (V0.1–V0.5: 0 body, 1 title3, 2 title2, 3 title). Still decoded and saved so old
    /// files and backups open; views use `fontSize`.
    var fontStep: Int = 1
    /// English reading text in pt (UI-P01: 24 pt, 18…34 pt). Dynamic Type scales it further
    /// (Theme.readingPointSize).
    var fontSize: Double = ReaderSettings.defaultFontSize
    /// 主题 (UI-P04): "system" / "light" / "dark".
    var appearance: String = "system"
    var threshold: Int = 6         // underline IELTS level >= threshold; 0 = off
    var showTrap: Bool = true      // 熟词僻义 dotted underline
    var showPhrase: Bool = false   // phrase dashed underline
    var pauseOnTap: Bool = true
    var follow: Bool = true
    var showZh: Bool = false
    var accent: String = "en-GB"   // TTS voice
    var rate: Double = 1.0
    var loopGap: Double = 1.0      // pause between loop repeats (s), 0...5
    var shadowRate: Double = 0.85  // speed of the original in 跟读
    var abGap: Double = 0.5        // SHD-P05: pause between original and recording in A/B (s), 0...2
    var retellSeconds: Double = 60 // SHD-P06: 脱稿复述 time, 30...120
    var shadowMode: String = "repeat"   // last 跟读 mode (ShadowMode raw value)

    init() {}

    enum CodingKeys: String, CodingKey {
        case fontStep, fontSize, appearance, threshold, showTrap, showPhrase, pauseOnTap, follow, showZh, accent, rate
        case loopGap, shadowRate, abGap, retellSeconds, shadowMode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fontStep = (try? c.decodeIfPresent(Int.self, forKey: .fontStep)) ?? 1
        // A file from before V1.0 has no fontSize: take it from the old step (0 → 20, 1 → 24, 2 → 28, 3 → 32).
        if let size = try? c.decodeIfPresent(Double.self, forKey: .fontSize) {
            fontSize = ReaderSettings.clampedFontSize(size)
        } else {
            fontSize = ReaderSettings.fontSize(fromStep: fontStep)
        }
        let look = (try? c.decodeIfPresent(String.self, forKey: .appearance)) ?? "system"
        appearance = ReaderSettings.appearances.contains(look) ? look : "system"
        threshold = try c.decodeIfPresent(Int.self, forKey: .threshold) ?? 6
        showTrap = try c.decodeIfPresent(Bool.self, forKey: .showTrap) ?? true
        showPhrase = try c.decodeIfPresent(Bool.self, forKey: .showPhrase) ?? false
        pauseOnTap = try c.decodeIfPresent(Bool.self, forKey: .pauseOnTap) ?? true
        follow = try c.decodeIfPresent(Bool.self, forKey: .follow) ?? true
        showZh = try c.decodeIfPresent(Bool.self, forKey: .showZh) ?? false
        accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? "en-GB"
        rate = try c.decodeIfPresent(Double.self, forKey: .rate) ?? 1.0
        loopGap = try c.decodeIfPresent(Double.self, forKey: .loopGap) ?? 1.0
        shadowRate = try c.decodeIfPresent(Double.self, forKey: .shadowRate) ?? 0.85
        abGap = min(2, max(0, (try? c.decodeIfPresent(Double.self, forKey: .abGap)) ?? 0.5))
        retellSeconds = min(120, max(30, (try? c.decodeIfPresent(Double.self, forKey: .retellSeconds)) ?? 60))
        shadowMode = (try? c.decodeIfPresent(String.self, forKey: .shadowMode)) ?? "repeat"
    }

    static let defaultFontSize: Double = 24
    static let fontSizeRange: ClosedRange<Double> = 18...34
    static let appearances = ["system", "light", "dark"]

    /// Whole points inside 18…34; anything unreadable becomes the default 24.
    static func clampedFontSize(_ value: Double) -> Double {
        guard value.isFinite else { return defaultFontSize }
        return min(fontSizeRange.upperBound, max(fontSizeRange.lowerBound, value.rounded()))
    }

    /// The V0.x text size steps in pt.
    static func fontSize(fromStep step: Int) -> Double {
        switch step {
        case 0: return 20
        case 2: return 28
        case 3: return 32
        default: return 24
        }
    }

    static let rates: [Double] = [0.5, 0.6, 0.75, 0.85, 1.0, 1.1, 1.25, 1.5]
    static let loopGaps: [Double] = [0, 0.5, 1, 2, 3, 5]
    static let shadowRates: [Double] = [0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9, 0.95, 1.0, 1.05, 1.1, 1.15, 1.2, 1.25]
    static let abGaps: [Double] = [0, 0.25, 0.5, 1, 1.5, 2]
    static let retellTimes: [Double] = [30, 45, 60, 90, 120]
}
