import XCTest
#if SWIFT_PACKAGE
@testable import DDULogic
#endif

final class QueueTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_500_000)
    let today = "2026-09-27"

    func card(_ id: String, task: VocabTask = .recognize, new: Bool, dueOffset: TimeInterval = -60,
              state: FSRSCard.State = .review, created: TimeInterval = 0) -> VocabCard {
        var c = VocabCard(itemId: id, task: task, created: now.addingTimeInterval(-86_400 * 10 + created))
        if !new {
            c.fsrs.lastReview = now.addingTimeInterval(-86_400)
            c.fsrs.state = state
            c.fsrs.stability = 3
            c.fsrs.difficulty = 5
            c.fsrs.due = now.addingTimeInterval(dueOffset)
        }
        return c
    }

    func testDueFirstThenNewWithinBudget() {
        var cards = (0..<3).map { card("d\($0)", new: false, dueOffset: -600 + Double($0)) }
        cards += (0..<10).map { card("n\($0)", new: true, created: Double($0)) }
        var settings = VocabSettings()
        settings.budgetMinutes = 10
        settings.newPerDay = 5
        let q = VocabQueueBuilder.build(cards: cards, settings: settings, now: now, today: today, todayEvents: [],
                                        estimates: VocabQueueBuilder.estimates(from: []), days: [:], keepNewOn: nil)
        XCTAssertEqual(q.dueCount, 3)
        XCTAssertEqual(q.newAllowed, 5)
        XCTAssertEqual(q.entries.count, 8)
        XCTAssertEqual(q.entries.first?.card.itemId, "d0")
        if case .new(let rank) = q.entries.last!.reason { XCTAssertEqual(rank, 5) } else { XCTFail() }
        XCTAssertEqual(q.entries[3].card.itemId, "n0")
    }

    func testNoNewWhenDueFillsBudget() {
        let cards = (0..<60).map { card("d\($0)", new: false) } + [card("n", new: true)]
        let q = VocabQueueBuilder.build(cards: cards, settings: VocabSettings(), now: now, today: today, todayEvents: [],
                                        estimates: VocabQueueBuilder.estimates(from: []), days: [:], keepNewOn: nil)
        XCTAssertEqual(q.dueCount, 60)
        XCTAssertEqual(q.newAllowed, 0)
        XCTAssertEqual(q.entries.count, 60, "every due card stays in the queue")
        XCTAssertTrue(q.explanation.joined().contains("没有剩余时间"))
    }

    func testBacklogRuleNeedsTwoStudyDays() {
        let over = VocabDay(dueAtStart: 80, estSeconds: 1200, budgetSeconds: 600, studied: true)
        let fine = VocabDay(dueAtStart: 5, estSeconds: 60, budgetSeconds: 600, studied: true)
        let unstudied = VocabDay(dueAtStart: 80, estSeconds: 1200, budgetSeconds: 600, studied: false)
        var days = ["2026-09-25": over, "2026-09-27": over]
        XCTAssertTrue(VocabQueueBuilder.backlogSuggestion(days: days, today: today))
        days["2026-09-26"] = unstudied            // a day without study does not break or count
        XCTAssertTrue(VocabQueueBuilder.backlogSuggestion(days: days, today: today))
        days["2026-09-26"] = fine
        XCTAssertFalse(VocabQueueBuilder.backlogSuggestion(days: days, today: today))
        let cards = [card("n", new: true)]
        let q = VocabQueueBuilder.build(cards: cards, settings: VocabSettings(), now: now, today: today, todayEvents: [],
                                        estimates: VocabQueueBuilder.estimates(from: []),
                                        days: ["2026-09-25": over, "2026-09-27": over], keepNewOn: nil)
        XCTAssertTrue(q.backlogSuggestsZero)
        XCTAssertEqual(q.newAllowed, 0)
        let kept = VocabQueueBuilder.build(cards: cards, settings: VocabSettings(), now: now, today: today, todayEvents: [],
                                           estimates: VocabQueueBuilder.estimates(from: []),
                                           days: ["2026-09-25": over, "2026-09-27": over], keepNewOn: today)
        XCTAssertEqual(kept.newAllowed, 1)
    }

    func testUndoneReviewsDoNotCount() {
        var e1 = ReviewEvent(kind: .review, itemId: "a", at: now)
        e1.durationMs = 30_000
        e1.before = FSRSCard(due: now)
        var undo = ReviewEvent(kind: .undo, itemId: "a", at: now)
        undo.undoes = e1.id
        var e2 = ReviewEvent(kind: .review, itemId: "b", at: now)
        e2.durationMs = 12_000
        let active = VocabQueueBuilder.activeReviews([e1, undo, e2])
        XCTAssertEqual(active.map(\.itemId), ["b"])
        let q = VocabQueueBuilder.build(cards: [], settings: VocabSettings(), now: now, today: today, todayEvents: [e1, undo, e2],
                                        estimates: VocabQueueBuilder.estimates(from: []), days: [:], keepNewOn: nil)
        XCTAssertEqual(q.spentSeconds, 12, accuracy: 0.001)
        XCTAssertEqual(q.newDoneToday, 0)
    }

    func testPausedItemsStayOutOfTheQueue() {
        let cards = [card("a", new: false), card("b", new: false), card("c", new: true)]
        let q = VocabQueueBuilder.build(cards: cards, settings: VocabSettings(), now: now, today: today, todayEvents: [],
                                        estimates: VocabQueueBuilder.estimates(from: []), days: [:], keepNewOn: nil,
                                        archivedItems: ["b", "c"])
        XCTAssertEqual(q.entries.map(\.card.itemId), ["a"])
        XCTAssertEqual(q.newCount, 0)
    }

    func testEstimatesUseMedian() {
        var events: [ReviewEvent] = []
        for ms in [5000, 7000, 9000, 11000, 400_000] {
            var e = ReviewEvent(kind: .review, itemId: "x", at: now)
            e.task = .spell
            e.durationMs = ms
            events.append(e)
        }
        let est = VocabQueueBuilder.estimates(from: events)
        XCTAssertEqual(est[.spell] ?? 0, 9, accuracy: 0.001)
        XCTAssertEqual(est[.recognize] ?? 0, VocabTask.recognize.defaultSeconds, accuracy: 0.001)
    }
}

final class PackDiffTests: XCTestCase {
    func testUnchangedChangedMappedRemoved() {
        let ref = ArticleRef(issue: "2026-09-05", id: "pol")
        let old = [1: "aaa", 2: "bbb", 3: "ccc", 4: "ddd"]
        let new = [1: "aaa", 2: "bbX", 5: "ccc", 6: "new"]
        let d = PackDiffer.diff(article: ref, old: old, new: new, idMap: ["3": 5, "4": nil])
        XCTAssertEqual(d.unchanged, [1])
        XCTAssertEqual(d.mapped, [3: 5])
        XCTAssertEqual(d.unmapped, [2, 4])
        XCTAssertEqual(d.added, [2, 6])
        XCTAssertEqual(d.newSid(for: 1), 1)
        XCTAssertEqual(d.newSid(for: 3), 5)
        XCTAssertNil(d.newSid(for: 2))
    }
}

final class DataFileTests: XCTestCase {
    func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ddu-\(UUID().uuidString).jsonl")
    }

    func testJSONLinesAppendAndSkipDamagedLines() throws {
        let url = tempURL()
        let log = JSONLines<ReviewEvent>(url: url)
        let now = Date(timeIntervalSince1970: 1_790_500_000)
        try log.append([ReviewEvent(kind: .review, itemId: "a", at: now)])
        // Simulate a crash in the middle of a write: a partial line without newline.
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"id\":\"broken".utf8))
        try handle.close()
        try log.append([ReviewEvent(kind: .listen, itemId: "b", at: now)])
        let read = log.readAll()
        XCTAssertEqual(read.records.map(\.itemId), ["a", "b"])
        XCTAssertEqual(read.badLines, 1)
        try? FileManager.default.removeItem(at: url)
    }

    func testVocabStateSkipsBadItemsAndClampsSettings() throws {
        let json = """
        {"schema":1,"items":[{"id":"s:abandon#0","kind":"sense","key":"abandon","text":"abandon","gloss":"放弃"},
          {"kind":"sense"},
          {"id":"c:call for","kind":"chunk","text":"call for","gloss":"呼吁","sources":[{"issue":"2026-09-05","article":"pol","sid":7},{"bad":1}]}],
         "cards":[{"itemId":"s:abandon#0","task":"recognize"},{"itemId":"x","task":"unknown-task"}],
         "settings":{"retention":0.99,"newPerDay":40}}
        """
        let state = try DataCoding.decoder.decode(VocabState.self, from: Data(json.utf8))
        XCTAssertEqual(state.items.map(\.id), ["s:abandon#0", "c:call for"])
        XCTAssertEqual(state.items[1].sources.count, 1)
        XCTAssertEqual(state.cards.count, 1)
        XCTAssertEqual(state.cards[0].id, "s:abandon#0|recognize")
        XCTAssertTrue(state.cards[0].isNew)
        XCTAssertEqual(state.settings.retention, 0.95)
        XCTAssertEqual(state.settings.newPerDay, 15)
    }

    func testIDs() {
        XCTAssertEqual(VocabItem.senseID(key: "interest", senseIndex: 1), "s:interest#1")
        XCTAssertEqual(VocabItem.chunkID("  Called  FOR "), "c:called for")
        XCTAssertEqual(VocabCard.makeID(itemId: "s:a#0", task: .spell), "s:a#0|spell")
    }
}
