import Foundation

// 首次基线 (DIAG-01, PLAN-P05, BASE-03): the four parts, their original prompts, the word list for the
// vocabulary self-test and the stage suggestion. Results are descriptions only, never a band score.

/// The four parts of the baseline, in display order. Any order can be done.
enum BaselinePart: String, CaseIterable, Identifiable {
    case listening, speaking, writing, vocab

    var id: String { rawValue }

    var title: String {
        switch self {
        case .listening: return "短听读"
        case .speaking: return "无准备录音"
        case .writing: return "独立短文"
        case .vocab: return "词汇自测"
        }
    }

    var symbol: String {
        switch self {
        case .listening: return "headphones"
        case .speaking: return "mic"
        case .writing: return "pencil.line"
        case .vocab: return "character.book.closed"
        }
    }

    /// How hard the task is set, in plain words.
    var difficulty: String {
        switch self {
        case .listening: return "内容包里一篇没学过的文章，只听一小段（约 1 分钟），不看原文。"
        case .speaking: return "日常话题。看到题目倒数 3 秒就开始说，不准备，最多 60 秒。"
        case .writing: return "日常话题，10 分钟，不给提示，也不给参考。"
        case .vocab: return "5、6、7、8 级词各 6 个，共 24 个。"
        }
    }

    /// When the part counts as done.
    var condition: String {
        switch self {
        case .listening: return "听完这一段，答完理解题。"
        case .speaking: return "录完一段，回答 3 个是 / 否问题。"
        case .writing: return "点“写完了”，或 10 分钟到。"
        case .vocab: return "24 个词都答完。"
        }
    }

    func result(in b: BaselineState) -> BaselineResult? {
        switch self {
        case .listening: return b.listening
        case .speaking: return b.speaking
        case .writing: return b.writing
        case .vocab: return b.vocab
        }
    }
}

/// An original prompt written for DayDayUp (public repository: no test material).
struct BaselinePrompt: Equatable {
    let id: String
    let en: String
    let zh: String
}

/// One word of the vocabulary self-test with its four meaning options.
struct BaselineWord: Identifiable, Equatable {
    var id: String          // lexicon key, shown as the word
    var band: Int           // 5…8
    var gloss: String       // the right meaning (first sense)
    var options: [String]   // 4 meanings, the right one among them
    var answer: Int
}

enum BaselineContent {
    /// 无准备录音: the first prompt not answered yet is used.
    static let speakingPrompts: [BaselinePrompt] = [
        BaselinePrompt(id: "baseline-sp-1",
                       en: "Describe a normal weekday morning for you. What do you usually do before you start work or study?",
                       zh: "说说你平常工作日的早上：开始工作或学习以前，一般会做些什么？"),
        BaselinePrompt(id: "baseline-sp-2",
                       en: "Talk about a place near your home that you like to go to. Why do you like it?",
                       zh: "说说你家附近一个你喜欢去的地方。为什么喜欢？"),
        BaselinePrompt(id: "baseline-sp-3",
                       en: "What did you do last weekend? Talk about one thing you enjoyed.",
                       zh: "上个周末你做了什么？说一件你喜欢的事。"),
    ]

    /// 独立短文.
    static let writingPrompt = BaselinePrompt(
        id: "baseline-wr-1",
        en: "Write about a skill you would like to learn. What is it, and why do you want to learn it?",
        zh: "写一项你想学的技能：它是什么？你为什么想学？")

    static let speakingLimit: Double = 60
    static let speakingTarget: Double = 45
    static let writingLimit: Double = 600
    static let wordsPerBand = 6

    @MainActor
    static func nextSpeakingPrompt(practice: PracticeStore) -> BaselinePrompt {
        let used = Set(practice.state.speaking.map(\.promptId))
        return speakingPrompts.first { !used.contains($0.id) } ?? speakingPrompts[speakingPrompts.count - 1]
    }

    /// 短听读: an article with comprehension questions, material the learner has not met first
    /// (never opened, nothing heard, no quiz answered, not tried in `avoiding`), shortest first.
    @MainActor
    static func listeningPick(packs: PackStore, user: UserStore, study: StudyStore,
                              avoiding: Set<String> = []) -> ArticleRef? {
        let withQuiz = packs.allItems.filter { packs.resources($0.ref).quiz == .available }
        let quizzed = Set(study.state.quizResults.map(\.article))
        let unseen = withQuiz.filter { item in
            study.state.articleOpened[item.ref.key] == nil
                && !quizzed.contains(item.ref.key)
                && !avoiding.contains(item.ref.key)
                && user.state.listenProgress(item.ref.key, duration: item.meta.dur) == 0
        }
        let pool = unseen.isEmpty ? withQuiz : unseen
        return pool.min { $0.meta.dur < $1.meta.dur }?.ref
    }

    // MARK: 词汇自测

    /// A lexicon key that reads as one plain word.
    static func isPlainWord(_ key: String) -> Bool {
        guard key.count >= 2, key.count <= 24, let first = key.first, first.isLetter else { return false }
        return key.allSatisfy { $0.isLetter || $0 == "-" || $0 == "'" }
    }

    /// First sense of a dictionary gloss such as "n. 报告, 解释, 估价\nvt. 认为": "报告，解释".
    static func shortGloss(_ zh: String) -> String? {
        guard let firstLine = zh.split(whereSeparator: \.isNewline).first else { return nil }
        var line = String(firstLine).trimmingCharacters(in: .whitespaces)
        // Drop a leading part-of-speech tag ("n.", "vt.", "adv.") or a field tag ("[医]").
        if let space = line.firstIndex(of: " ") {
            let head = line[..<space]
            if head.hasSuffix(".") || head.hasPrefix("[") {
                line = String(line[space...]).trimmingCharacters(in: .whitespaces)
            }
        }
        let parts = line.split(whereSeparator: { ",，;；".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = parts.first else { return nil }
        if parts.count > 1, first.count + parts[1].count <= 9 {
            return first + "，" + parts[1]
        }
        return first
    }

    /// True when the word list can make a test (at least 4 usable words, for four meaning options).
    static func hasEnoughWords(_ lexicon: [String: LexEntry]) -> Bool {
        var found = 0
        for (key, entry) in lexicon {
            guard let band = entry.b, (5...8).contains(band), entry.pn != true, entry.num != true,
                  isPlainWord(key), let zh = entry.zh, shortGloss(zh) != nil else { continue }
            found += 1
            if found >= 4 { return true }
        }
        return false
    }

    /// 24 words (6 per band 5…8, fewer when a band has fewer), each with the right meaning and three meanings
    /// of other words of the same band. Proper nouns, numbers and entries without a Chinese gloss are skipped.
    /// Order: band 5 first; random inside a band. The list is made once when the test starts.
    static func vocabWords(from lexicon: [String: LexEntry]) -> [BaselineWord] {
        var byBand: [Int: [(key: String, gloss: String)]] = [:]
        for (key, entry) in lexicon {
            guard let band = entry.b, (5...8).contains(band), entry.pn != true, entry.num != true,
                  isPlainWord(key), let zh = entry.zh, let gloss = shortGloss(zh) else { continue }
            byBand[band, default: []].append((key: key, gloss: gloss))
        }
        let allGlosses = Array(Set(byBand.values.flatMap { list in list.map { $0.gloss } })).sorted()
        var rng = SystemRandomNumberGenerator()
        var out: [BaselineWord] = []
        for band in 5...8 {
            let pool = (byBand[band] ?? []).sorted { $0.key < $1.key }
            let bandGlosses = Array(Set(pool.map { $0.gloss })).sorted()
            let picked = pool.shuffled(using: &rng).prefix(wordsPerBand)
            for word in picked {
                var others = bandGlosses.filter { $0 != word.gloss }.shuffled(using: &rng)
                if others.count < 3 {
                    let extra = allGlosses.filter { $0 != word.gloss && !others.contains($0) }.shuffled(using: &rng)
                    others += extra
                }
                guard others.count >= 3 else { continue }
                var options = Array(others.prefix(3)) + [word.gloss]
                options.shuffle(using: &rng)
                let answer = options.firstIndex(of: word.gloss) ?? 0
                out.append(BaselineWord(id: word.key, band: band, gloss: word.gloss, options: options, answer: answer))
            }
        }
        return out
    }

    // MARK: Dates

    /// "2026-09-27" -> "9/27".
    static func shortDay(_ key: String) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return key }
        return "\(parts[1])/\(parts[2])"
    }

    static func shortDate(_ date: Date) -> String {
        shortDay(DayKey.of(date))
    }
}

/// BASE-03 "先补基础，再冲 7 分": a suggested stage with a one-line reason, from the four descriptions.
/// Never switches by itself; the learner decides.
enum BaselineAdvice {
    struct Suggestion: Equatable {
        var stage: StudyStage
        var reason: String
    }

    static func suggest(_ b: BaselineState) -> Suggestion {
        var low: [String] = []       // clearly below the basic level
        var middle: [String] = []    // not weak, not yet steady
        var steady: [String] = []
        var skipped: [String] = []

        if let r = b.listening, let total = r.numbers["total"], total > 0 {
            let correct = r.numbers["correct"] ?? 0
            let fact = "理解题答对 \(Int(correct))/\(Int(total))"
            if correct * 2 <= total {
                low.append(fact)
            } else if correct * 5 >= total * 4 {
                steady.append(fact)
            } else {
                middle.append(fact)
            }
        } else {
            skipped.append(BaselinePart.listening.title)
        }

        if let r = b.speaking, let seconds = r.numbers["seconds"] {
            let fact = "录音说了 \(Int(seconds.rounded())) 秒"
            let smooth = (r.numbers["noLongPause"] ?? 0) >= 1 && (r.numbers["sentences"] ?? 0) >= 1
            if seconds < 30 {
                low.append(fact)
            } else if seconds >= 45 && smooth {
                steady.append(fact)
            } else {
                middle.append(fact)
            }
        } else {
            skipped.append(BaselinePart.speaking.title)
        }

        if let r = b.writing, let words = r.numbers["words"] {
            let fact = "10 分钟写了 \(Int(words)) 词"
            if words < 50 {
                low.append(fact)
            } else if words >= 100 {
                steady.append(fact)
            } else {
                middle.append(fact)
            }
        } else {
            skipped.append(BaselinePart.writing.title)
        }

        if let r = b.vocab, !r.numbers.isEmpty {
            let t6 = r.numbers["b6_total"] ?? 0
            let t7 = r.numbers["b7_total"] ?? 0
            let c6 = r.numbers["b6_correct"] ?? 0
            let c7 = r.numbers["b7_correct"] ?? 0
            if t6 > 0 && c6 * 2 < t6 {
                low.append("6 级词含义选对 \(Int(c6))/\(Int(t6))")
            } else if t7 > 0 && c7 * 3 >= t7 * 2 {
                steady.append("7 级词含义选对 \(Int(c7))/\(Int(t7))")
            } else if t7 > 0 {
                middle.append("7 级词含义选对 \(Int(c7))/\(Int(t7))")
            } else {
                middle.append("词汇自测的词太少，样本少")
            }
        } else {
            skipped.append(BaselinePart.vocab.title)
        }

        if !low.isEmpty {
            return Suggestion(stage: .basic,
                              reason: low.prefix(2).joined(separator: "，") + "。先补基础，再冲 7 分：从基础表达开始。")
        }
        if !skipped.isEmpty {
            return Suggestion(stage: .basic,
                              reason: "跳过了" + skipped.joined(separator: "、") + "，证据不够。先从基础表达开始。")
        }
        if middle.isEmpty {
            return Suggestion(stage: .developing,
                              reason: steady.joined(separator: "，") + "。四项都比较稳，可以进入表达发展。")
        }
        return Suggestion(stage: .basic,
                          reason: "没有明显的短板，但" + middle.prefix(2).joined(separator: "，") + "。先在基础表达多练一段。")
    }
}
