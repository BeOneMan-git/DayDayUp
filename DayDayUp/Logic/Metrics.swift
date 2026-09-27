import Foundation

/// Evidence for the 进展 page and the weekly report (MET-01…06, VOC-P05, RPT-01).
/// Practice time and evidence of ability are kept apart; every rate comes with its sample size.
enum Metrics {
    // MARK: MET-01 有效练习时间

    struct DayMinutes: Equatable {
        var day: String
        var byCat: [StudyCategory: Double]   // minutes
        var total: Double                     // union of all foreground time: overlaps count once
        var background: Double                // audio while the app was not on screen (kept apart)
    }

    /// Merges overlapping intervals and returns the covered seconds.
    static func coveredSeconds(_ intervals: [(Date, Date)]) -> Double {
        let sorted = intervals.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        var total: Double = 0
        var cur: (Date, Date)?
        for iv in sorted {
            if let c = cur, iv.0 <= c.1 {
                cur = (c.0, max(c.1, iv.1))
            } else {
                if let c = cur { total += c.1.timeIntervalSince(c.0) }
                cur = iv
            }
        }
        if let c = cur { total += c.1.timeIntervalSince(c.0) }
        return total
    }

    static func minutes(_ records: [ActivityRecord], days: [String]) -> [DayMinutes] {
        days.map { day in
            let mine = records.filter { $0.day == day }
            let fg = mine.filter { !$0.background }
            var by: [StudyCategory: Double] = [:]
            for cat in StudyCategory.allCases {
                by[cat] = coveredSeconds(fg.filter { $0.cat == cat }.map { ($0.start, $0.end) }) / 60
            }
            let total = coveredSeconds(fg.map { ($0.start, $0.end) }) / 60
            let bg = coveredSeconds(mine.filter { $0.background }.map { ($0.start, $0.end) }) / 60
            return DayMinutes(day: day, byCat: by, total: total, background: bg)
        }
    }

    // MARK: MET-02 / VOC-P05 回忆表现

    struct RecallStat: Equatable {
        var task: VocabTask
        var successes = 0
        var attempts = 0
        var withHint = 0          // objective answers that were right only after a hint
        var sameDayRetries = 0    // shown separately, never mixed into the rate
        var objective: Bool { task.isObjective }
    }

    /// VOC-P05: below this many eligible answers the rate is "证据不足".
    static let recallMinimum = 30
    /// MET-P02: below this many records of one kind, a result is marked "样本少".
    static let smallSample = 20

    /// Eligible = a first answer of the day, at least 24 h after the previous review, answer not shown first,
    /// not taken back, inside the window.
    static func recall(events: [ReviewEvent], now: Date, windowDays: Int) -> [RecallStat] {
        let undone = Set(events.filter { $0.kind == .undo }.compactMap { $0.undoes })
        let from = now.addingTimeInterval(-Double(windowDays) * 86_400)
        var out: [VocabTask: RecallStat] = [:]
        for e in events where e.kind == .review && !undone.contains(e.id) && e.at >= from && e.at <= now {
            guard let task = e.task else { continue }
            var st = out[task] ?? RecallStat(task: task)
            if e.firstOfDay != true {
                st.sameDayRetries += 1
                out[task] = st
                continue
            }
            guard e.revealedEarly != true, let last = e.before?.lastReview,
                  e.at.timeIntervalSince(last) >= 86_400 else {
                out[task] = st
                continue
            }
            st.attempts += 1
            if task.isObjective {
                if e.correct == true {
                    if (e.hint ?? 0) > 0 { st.withHint += 1 } else { st.successes += 1 }
                }
            } else if (e.rating ?? 1) >= 3 {
                st.successes += 1
            }
            out[task] = st
        }
        return VocabTask.allCases.compactMap { out[$0] }
    }

    // MARK: MET-03 词项状态

    struct AbilityCounts: Equatable {
        var ability: VocabAbility
        var off = 0            // no task for this ability yet
        var new = 0
        var learning = 0
        var longInterval = 0   // interval of 21 days or more ("较长复习间隔", not "掌握")
    }

    static func abilityCounts(items: [VocabItem], cards: [VocabCard], longDays: Int = 21) -> [AbilityCounts] {
        let active = items.filter { !$0.archived }
        let byItem = Dictionary(grouping: cards.filter { !$0.suspended }, by: \.itemId)
        return VocabAbility.allCases.map { ability in
            var c = AbilityCounts(ability: ability)
            for item in active {
                let mine = (byItem[item.id] ?? []).filter { $0.task.ability == ability }
                if mine.isEmpty {
                    c.off += 1
                } else if mine.allSatisfy(\.isNew) {
                    c.new += 1
                } else if mine.contains(where: { card in
                    guard card.fsrs.state == .review, let last = card.fsrs.lastReview else { return false }
                    return card.fsrs.due.timeIntervalSince(last) >= Double(longDays) * 86_400
                }) {
                    c.longInterval += 1
                } else {
                    c.learning += 1
                }
            }
            return c
        }
    }

    // MARK: MET-06 问题复发

    struct IssueStat: Equatable, Identifiable {
        var id: String            // "<kind>:<dim>#<question>"
        var kind: String          // "speaking" / "writing"
        var dim: String
        var question: Int
        var misses: Int           // self-checks where this point was not ticked
        var checks: Int           // self-checks that asked it (the denominator)
        var samples: [String]     // work ids, newest first
    }

    /// Points the learner did not tick in their own self-checks. A point needs at least 2 misses to be listed,
    /// so a single slip is not reported as a pattern.
    static func issues(practice: PracticeState, since: Date?, retracted: Set<String>) -> [IssueStat] {
        var stats: [String: IssueStat] = [:]
        func count(_ check: SelfCheck?, kind: String, id: String, at: Date) {
            guard let check, since.map({ at >= $0 }) ?? true else { return }
            for dim in check.dims {
                for (q, ok) in dim.answers.enumerated() {
                    let key = "\(kind):\(dim.id)#\(q)"
                    var s = stats[key] ?? IssueStat(id: key, kind: kind, dim: dim.id, question: q, misses: 0, checks: 0, samples: [])
                    s.checks += 1
                    if !ok {
                        s.misses += 1
                        s.samples.insert(id, at: 0)
                    }
                    stats[key] = s
                }
            }
        }
        for w in practice.speaking {
            count(w.check, kind: "speaking", id: w.id, at: w.created)
        }
        for w in practice.writing {
            for v in w.versions {
                count(v.check, kind: "writing", id: w.id, at: v.finished ?? v.started)
            }
        }
        return stats.values
            .filter { $0.misses >= 2 && !retracted.contains($0.id) }
            .sorted { Double($0.misses) / Double(max(1, $0.checks)) > Double($1.misses) / Double(max(1, $1.checks)) }
    }

    // MARK: RPT-01 周报

    struct WeeklyReport: Codable, Equatable {
        var week: String                        // Monday
        var generated: Date
        var plannedMinutes: Int
        var actualMinutes: [String: Double]     // category raw value -> minutes
        var totalMinutes: Double
        var backgroundMinutes: Double
        var studyDays: Int
        var vocabDueAtStart: Int
        var vocabReviews: Int
        var delayedRecall: [String: [Int]]      // task raw value -> [successes, attempts]
        var quizzes: [String]                   // "标题：3/4（隔日回忆）"
        var speakingWorks: Int
        var writingWorks: Int
        var independentWorks: Int
        var issues: [String]                    // "发音：重音和语调听起来自然（5 次里 3 次没勾）"
        var focuses: [String]                   // at most three
        var notes: [String]
    }

    static func weekDays(_ monday: String) -> [String] {
        (0..<7).map { DayKey.adding($0, to: monday) }
    }

    struct WeeklyInputs {
        var monday: String
        var now: Date
        var plans: [String: PlanSnapshot]
        var activity: [ActivityRecord]
        var vocabDays: [String: VocabDay]
        var vocabEvents: [ReviewEvent]
        var quizzes: [QuizResult]
        var titles: [String: String]            // article key -> title
        var practice: PracticeState
        var retracted: Set<String>
        var questionText: (String, String, Int) -> String   // kind, dim, question index -> text
    }

    /// The facts of one week (Monday to Sunday) and at most three focus points for the next week.
    /// Facts only: when no rule applies, no advice is invented.
    static func weekly(_ i: WeeklyInputs) -> WeeklyReport {
        let days = weekDays(i.monday)
        let daySet = Set(days)
        let mins = minutes(i.activity, days: days)
        var byCat: [String: Double] = [:]
        for d in mins {
            for (cat, m) in d.byCat { byCat[cat.rawValue, default: 0] += m }
        }
        let total = mins.reduce(0) { $0 + $1.total }
        let planned = days.compactMap { i.plans[$0]?.budget }.reduce(0, +)
        let studyDays = mins.filter { $0.total >= 1 }.count
        let weekEvents = i.vocabEvents.filter { daySet.contains($0.day) }
        let end = DayKey.date(DayKey.adding(1, to: days[6])) ?? i.now
        let recallStats = recall(events: i.vocabEvents.filter { $0.at <= end }, now: min(end, i.now), windowDays: 7)
        var recallOut: [String: [Int]] = [:]
        for r in recallStats where r.attempts > 0 { recallOut[r.task.rawValue] = [r.successes, r.attempts] }
        let quizLines = i.quizzes.filter { daySet.contains($0.day) }.map { q -> String in
            let purpose = ["delayed": "隔日回忆", "weekly": "新材料复测", "baseline": "基线", "practice": "练习"][q.purpose] ?? q.purpose
            return "\(i.titles[q.article] ?? q.article)：\(q.correct)/\(q.total)（\(purpose)）"
        }
        let speaking = i.practice.speaking.filter { daySet.contains(DayKey.of($0.created)) && !$0.silent }
        let writing = i.practice.writing.filter { w in
            w.versions.contains { v in v.finished.map { daySet.contains(DayKey.of($0)) } ?? false }
        }
        let independent = speaking.filter { $0.independent }.count
            + writing.filter { $0.versions.first?.independent ?? false }.count
        let monday = DayKey.date(i.monday)
        let issueStats = issues(practice: i.practice, since: monday.map { $0.addingTimeInterval(-86_400 * 21) },
                                retracted: i.retracted)
        let issueLines = issueStats.prefix(3).map { st in
            "\(i.questionText(st.kind, st.dim, st.question))（自评 \(st.checks) 次里 \(st.misses) 次没勾上）"
        }

        var focuses: [String] = []
        if planned > 0, total < Double(planned) * 0.6 {
            focuses.append("时间：实际投入约为计划的 \(Int((total / Double(planned) * 100).rounded()))%。下周先把每日预算定在做得到的水平。")
        }
        if let weak = recallStats.filter({ $0.attempts >= 10 }).min(by: {
            Double($0.successes) / Double($0.attempts) < Double($1.successes) / Double($1.attempts)
        }), Double(weak.successes) / Double(weak.attempts) < 0.7 {
            focuses.append("词汇：\(weak.task.title)的延迟回忆成功 \(weak.successes)/\(weak.attempts)。先少加新词，把到期的做完。")
        }
        if independent < 3 {
            focuses.append("说写：本周独立作品 \(independent) 个。下周至少每两天留一个独立样本。")
        }
        if let top = issueStats.first, focuses.count < 3 {
            focuses.append("专项：\(i.questionText(top.kind, top.dim, top.question))。")
        }
        var notes: [String] = []
        if total == 0 { notes.append("这周没有练习记录。") }
        let sameDay = recallStats.reduce(0) { $0 + $1.sameDayRetries }
        if sameDay > 0 { notes.append("同日重试 \(sameDay) 次，单独记，不算进回忆率。") }
        return WeeklyReport(week: i.monday, generated: i.now, plannedMinutes: planned, actualMinutes: byCat,
                            totalMinutes: total, backgroundMinutes: mins.reduce(0) { $0 + $1.background },
                            studyDays: studyDays,
                            vocabDueAtStart: days.compactMap { i.vocabDays[$0]?.dueAtStart }.reduce(0, +),
                            vocabReviews: VocabQueueBuilder.activeReviews(weekEvents).count,
                            delayedRecall: recallOut, quizzes: quizLines,
                            speakingWorks: speaking.count, writingWorks: writing.count,
                            independentWorks: independent, issues: Array(issueLines),
                            focuses: Array(focuses.prefix(3)), notes: notes)
    }
}
