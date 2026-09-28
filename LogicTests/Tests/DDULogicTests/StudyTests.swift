import XCTest
#if SWIFT_PACKAGE
@testable import DDULogic
#endif

final class PlanEngineTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_500_000)   // 2026-09-27

    func inputs(budget: Int = 60, baselineDone: Bool = true) -> PlanInputs {
        var settings = StudySettings()
        settings.budgetMinutes = budget
        var baseline = BaselineState()
        if baselineDone {
            let r = BaselineResult(done: now, summary: "", refId: nil, numbers: [:])
            baseline.listening = r
            baseline.speaking = r
            baseline.writing = r
            baseline.vocab = r
        }
        let a = ReadingCandidate(ref: ArticleRef(issue: "2026-09-19", id: "sleep"), title: "Sleep", minutes: 6,
                                 listened: 0.4, lastOpened: now.addingTimeInterval(-3600), difficulty: 3,
                                 firstUnpractisedSid: 4, hasQuiz: true, readDay: nil, checked: false)
        let b = ReadingCandidate(ref: ArticleRef(issue: "2026-09-26", id: "gig"), title: "Gig", minutes: 4,
                                 listened: 0, lastOpened: nil, difficulty: nil, firstUnpractisedSid: 1,
                                 hasQuiz: true, readDay: nil, checked: false)
        return PlanInputs(day: "2026-09-27", now: now, settings: settings, vocabBudgetMinutes: 10, vocabDue: 12,
                          vocabEstSeconds: 200, vocabNewAllowed: 3, vocabBacklog: false, vocabItems: 40,
                          baseline: baseline, reading: [a, b], dueRetests: [],
                          nextSpeaking: (id: "sp-1", text: "Describe your job"), nextWriting: (id: "wr-1", text: "Cities"),
                          outputDoneRecently: [], deferred: [], lastWeeklyCheck: "2026-09-25")
    }

    func testSplitMatchesPlanP01() {
        XCTAssertEqual(PlanEngine.split(budget: 60, vocabMinutes: 10), [.vocab: 10, .read: 20, .shadow: 15, .output: 15])
        XCTAssertEqual(PlanEngine.split(budget: 90, vocabMinutes: 10), [.vocab: 10, .read: 30, .shadow: 15, .output: 35])
        let custom = PlanEngine.split(budget: 45, vocabMinutes: 10)
        XCTAssertEqual(custom.values.reduce(0, +), 45)
        XCTAssertEqual(custom[.output], 15)
    }

    func testPlanKeepsOutputAndExplainsEachTask() {
        let p = PlanEngine.build(inputs())
        XCTAssertEqual(p.tasks.map(\.cat), [.vocab, .read, .shadow, .output])
        XCTAssertTrue(p.tasks.allSatisfy { !$0.reason.isEmpty })
        XCTAssertEqual(p.tasks.first { $0.cat == .read }?.target, .article(issue: "2026-09-19", id: "sleep"),
                       "unfinished material first")
        XCTAssertEqual(p.tasks.first { $0.cat == .shadow }?.target, .shadow(issue: "2026-09-19", id: "sleep", sid: 4))
        XCTAssertEqual(p.budget, 60)
        XCTAssertEqual(p.rulesVersion, PlanSnapshot.currentRules)
    }

    func testBaselineComesFirstAndUsesTodaysTime() {
        let p = PlanEngine.build(inputs(baselineDone: false))
        XCTAssertEqual(p.tasks.first?.target, .baseline)
        let total = p.tasks.filter { $0.target != .articleCheck(issue: "2026-09-26", id: "gig", purpose: "weekly") }
            .reduce(0) { $0 + $1.minutes }
        XCTAssertLessThanOrEqual(total, 60)
        XCTAssertGreaterThanOrEqual(p.tasks.first?.minutes ?? 0, 15)
    }

    func testBacklogNoteAndRetestFirst() {
        var i = inputs()
        i.vocabBacklog = true
        i.dueRetests = [Retest(id: "r1", kind: "speaking", sourceId: "w1", due: "2026-09-26",
                               created: now.addingTimeInterval(-86_400 * 4), promptId: nil, done: nil, resultId: nil)]
        let p = PlanEngine.build(i)
        XCTAssertTrue(p.notes.joined().contains("积压"))
        XCTAssertEqual(p.tasks.first { $0.cat == .output }?.target, .retest(id: "r1"))
    }

    func testDeferredTaskComesBackOnce() {
        var i = inputs()
        let t = PlanTask(id: "2026-09-26-shadow", cat: .shadow, minutes: 15, title: "跟读", reason: "短句。",
                         target: .shadow(issue: "x", id: "y", sid: nil), state: .deferred, doneAt: nil, deferredTo: "2026-09-27")
        i.deferred = [t]
        let p = PlanEngine.build(i)
        let shadow = p.tasks.filter { $0.cat == .shadow }
        XCTAssertEqual(shadow.count, 1)
        XCTAssertEqual(shadow.first?.id, "2026-09-27-shadow")
        XCTAssertTrue(shadow.first?.reason.hasPrefix("昨天暂缓") ?? false)
        XCTAssertEqual(shadow.first?.minutes, 15, "not doubled")
    }

    func testDeferredRecallIsNotCarriedAsReading() {
        var i = inputs()
        let recall = PlanTask(id: "2026-09-26-recall", cat: .read, minutes: 5, title: "隔日回忆", reason: "",
                              target: .articleCheck(issue: "x", id: "y", purpose: "delayed"), state: .deferred,
                              doneAt: nil, deferredTo: "2026-09-27")
        i.deferred = [recall]
        let p = PlanEngine.build(i)
        XCTAssertEqual(p.tasks.first { $0.id == "2026-09-27-read" }?.target, .article(issue: "2026-09-19", id: "sleep"))
        XCTAssertEqual(PlanEngine.slot(recall), "recall")
        XCTAssertEqual(Set(p.tasks.map(\.id)).count, p.tasks.count, "task ids stay unique")
    }

    func testWeeklyCheckOncePerWeek() {
        var i = inputs()
        i.lastWeeklyCheck = "2026-09-25"
        XCTAssertFalse(PlanEngine.build(i).tasks.contains { $0.id.hasSuffix("-weekly") })
        i.lastWeeklyCheck = "2026-09-18"
        XCTAssertTrue(PlanEngine.build(i).tasks.contains { $0.id.hasSuffix("-weekly") })
    }
}

final class MetricsTests: XCTestCase {
    let base = Date(timeIntervalSince1970: 1_790_500_000)

    func rec(_ cat: StudyCategory, _ from: Double, _ to: Double, bg: Bool = false) -> ActivityRecord {
        var r = ActivityRecord(cat: cat, start: base.addingTimeInterval(from), end: base.addingTimeInterval(to),
                               background: bg, source: nil)
        r.day = "2026-09-27"
        return r
    }

    func testOverlapsCountOnce() {
        let records = [rec(.read, 0, 600), rec(.read, 300, 900), rec(.vocab, 800, 1000), rec(.read, 5000, 5060, bg: true)]
        let d = Metrics.minutes(records, days: ["2026-09-27"])[0]
        XCTAssertEqual(d.byCat[.read] ?? 0, 15, accuracy: 0.001)
        XCTAssertEqual(d.byCat[.vocab] ?? 0, 200.0 / 60, accuracy: 0.001)
        XCTAssertEqual(d.total, 1000.0 / 60, accuracy: 0.001, "read and vocab overlap 100 s: counted once")
        XCTAssertEqual(d.background, 1, accuracy: 0.001)
    }

    func review(_ task: VocabTask, at: TimeInterval, last: TimeInterval?, rating: Int, first: Bool = true,
                early: Bool = false, correct: Bool? = nil, hint: Int = 0) -> ReviewEvent {
        var e = ReviewEvent(kind: .review, itemId: "i", at: base.addingTimeInterval(at))
        e.task = task
        e.rating = rating
        e.firstOfDay = first
        e.revealedEarly = early
        e.correct = correct
        e.hint = hint
        var before = FSRSCard(due: base)
        before.lastReview = last.map { base.addingTimeInterval($0) }
        e.before = before
        return e
    }

    func testRecallEligibility() {
        let day: TimeInterval = 86_400
        var events = [
            review(.recognize, at: 3 * day, last: 1 * day, rating: 3),                 // counts, success
            review(.recognize, at: 3 * day, last: 2.5 * day, rating: 3),               // < 24 h: not eligible
            review(.recognize, at: 3 * day, last: 1 * day, rating: 1),                 // counts, failure
            review(.recognize, at: 3 * day, last: 1 * day, rating: 3, first: false),   // same-day retry
            review(.recognize, at: 3 * day, last: 1 * day, rating: 3, early: true),    // answer shown first
            review(.spell, at: 3 * day, last: 1 * day, rating: 2, correct: true, hint: 1),
            review(.spell, at: 3 * day, last: 1 * day, rating: 3, correct: true),
        ]
        var undone = review(.recognize, at: 3 * day, last: 1 * day, rating: 4)
        undone.id = "undone"
        events.append(undone)
        var u = ReviewEvent(kind: .undo, itemId: "i", at: base.addingTimeInterval(3 * day))
        u.undoes = "undone"
        events.append(u)
        let stats = Metrics.recall(events: events, now: base.addingTimeInterval(4 * day), windowDays: 28)
        let rec = stats.first { $0.task == .recognize }
        XCTAssertEqual(rec?.attempts, 2, "answer shown first, under 24 h and taken-back answers are not candidates")
        XCTAssertEqual(rec?.successes, 1)
        XCTAssertEqual(rec?.sameDayRetries, 1)
        let sp = stats.first { $0.task == .spell }
        XCTAssertEqual(sp?.attempts, 2)
        XCTAssertEqual(sp?.successes, 1)
        XCTAssertEqual(sp?.withHint, 1)
    }

    func testAbilityCounts() {
        var a = VocabItem(id: "a", kind: .sense, key: "a", text: "a", gloss: "", created: base, origin: .reader)
        a.archived = false
        let b = VocabItem(id: "b", kind: .sense, key: "b", text: "b", gloss: "", created: base, origin: .reader)
        var long = VocabCard(itemId: "a", task: .recognize, created: base)
        long.fsrs.state = .review
        long.fsrs.lastReview = base
        long.fsrs.due = base.addingTimeInterval(86_400 * 30)
        let fresh = VocabCard(itemId: "b", task: .recognize, created: base)
        let listen = VocabCard(itemId: "a", task: .listen, created: base)
        let counts = Metrics.abilityCounts(items: [a, b], cards: [long, fresh, listen])
        let meaning = counts.first { $0.ability == .meaning }
        XCTAssertEqual(meaning?.longInterval, 1)
        XCTAssertEqual(meaning?.new, 1)
        let listening = counts.first { $0.ability == .listening }
        XCTAssertEqual(listening?.new, 1)
        XCTAssertEqual(listening?.off, 1)
    }

    func testIssuesNeedTwoMissesAndShowDenominator() {
        var p = PracticeState()
        for n in 0..<3 {
            var w = SpeakingWork(id: "w\(n)", promptId: "p", question: "q", created: base.addingTimeInterval(Double(n)),
                                 prepSeconds: 0, speakSeconds: 40, target: 45, file: nil, peakDb: -10, silent: false,
                                 interrupted: false, independent: true)
            w.check = SelfCheck(created: base, dims: [DimCheck(id: "pr", answers: [n == 0, false], note: "")])
            p.speaking.append(w)
        }
        let list = Metrics.issues(practice: p, since: nil, retracted: [])
        XCTAssertEqual(list.map(\.id).sorted(), ["speaking:pr#0", "speaking:pr#1"])
        let second = list.first { $0.id == "speaking:pr#1" }
        XCTAssertEqual(second?.misses, 3)
        XCTAssertEqual(second?.checks, 3)
        XCTAssertEqual(Metrics.issues(practice: p, since: nil, retracted: ["speaking:pr#1"]).count, 1)
    }

    func testStoredDayKeyWins() throws {
        var w = SpeakingWork(id: "w", promptId: "p", question: "q", created: base, prepSeconds: 0, speakSeconds: 40,
                             target: 45, file: nil, peakDb: -10, silent: false, interrupted: false, independent: true)
        XCTAssertEqual(w.dayKey, DayKey.of(base), "records from before V1.0 fall back to their time")
        w.day = "2000-01-01"
        XCTAssertEqual(w.dayKey, "2000-01-01", "ACC-13: a later time-zone change never moves a record")
        let back = try JSONDecoder().decode(SpeakingWork.self, from: JSONEncoder().encode(w))
        XCTAssertEqual(back.day, "2000-01-01")
        let old = try JSONDecoder().decode(ShadowAttempt.self, from: Data("""
        {"id":"a","article":"x/y","sid":1,"text":"t","created":0,"seconds":2,"peakDb":-9,"silent":false,
         "interrupted":false,"rate":1,"mode":"repeat"}
        """.utf8))
        XCTAssertNil(old.day)
        XCTAssertEqual(old.dayKey, DayKey.of(Date(timeIntervalSinceReferenceDate: 0)))
    }

    func testDayKeysAndQuietHours() {
        XCTAssertEqual(DayKey.weekStart("2026-09-27"), "2026-09-21")
        XCTAssertEqual(DayKey.weekStart("2026-09-28"), "2026-09-28")
        XCTAssertEqual(DayKey.adding(1, to: "2026-12-31"), "2027-01-01")
        XCTAssertEqual(DayKey.distance(from: "2026-09-27", to: "2026-10-04"), 7)
        XCTAssertTrue(QuietHours.contains(hour: 23, start: 22, end: 7))
        XCTAssertTrue(QuietHours.contains(hour: 3, start: 22, end: 7))
        XCTAssertFalse(QuietHours.contains(hour: 20, start: 22, end: 7))
    }
}
