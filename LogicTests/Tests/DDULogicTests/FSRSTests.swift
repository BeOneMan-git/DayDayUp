import XCTest
#if SWIFT_PACKAGE
@testable import DDULogic
#endif

/// The Swift port must give the same schedule as py-fsrs 6.3.2 (fixtures made by tools/gen_fsrs_fixtures.py).
final class FSRSTests: XCTestCase {
    struct Fixture: Decodable {
        struct Step: Decodable {
            var rating: Int
            var at: Double
            var state: Int
            var step: Int?
            var stability: Double
            var difficulty: Double
            var due: Double
        }
        struct Case: Decodable {
            var retention: Double
            var start: Double
            var steps: [Step]
        }
        struct Sample: Decodable {
            var at: Double
            var r: Double
        }
        struct Retr: Decodable {
            var lastReview: Double
            var stability: Double
            var difficulty: Double
            var samples: [Sample]
        }
        struct Interval: Decodable {
            var retention: Double
            var stability: Double
            var days: Int
        }
        var cases: [Case]
        var retrievability: Retr
        var intervals: [Interval]
    }

    func load() throws -> Fixture {
        let url = try TestFixtures.url(name: "fsrs_cases", ext: "json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    func testReviewSequencesMatchPyFSRS() throws {
        let f = try load()
        XCTAssertGreaterThan(f.cases.count, 10)
        for (n, c) in f.cases.enumerated() {
            let s = FSRSScheduler(desiredRetention: c.retention)
            var card = FSRSCard(due: Date(timeIntervalSince1970: c.start))
            for (k, step) in c.steps.enumerated() {
                let rating = try XCTUnwrap(FSRSRating(rawValue: step.rating))
                card = s.review(card, rating: rating, at: Date(timeIntervalSince1970: step.at))
                let label = "case \(n) step \(k) rating \(step.rating)"
                XCTAssertEqual(card.state.rawValue, step.state, "\(label): state")
                XCTAssertEqual(card.step, step.step, "\(label): step")
                XCTAssertEqual(card.stability ?? -1, step.stability, accuracy: 1e-6 * max(1, step.stability), "\(label): stability")
                XCTAssertEqual(card.difficulty ?? -1, step.difficulty, accuracy: 1e-6, "\(label): difficulty")
                XCTAssertEqual(card.due.timeIntervalSince1970, step.due, accuracy: 0.5, "\(label): due")
            }
        }
    }

    func testRetrievability() throws {
        let f = try load()
        let s = FSRSScheduler(desiredRetention: 0.9)
        var card = FSRSCard(due: Date(timeIntervalSince1970: f.retrievability.lastReview))
        card.state = .review
        card.step = nil
        card.stability = f.retrievability.stability
        card.difficulty = f.retrievability.difficulty
        card.lastReview = Date(timeIntervalSince1970: f.retrievability.lastReview)
        for sample in f.retrievability.samples {
            XCTAssertEqual(s.retrievability(card, at: Date(timeIntervalSince1970: sample.at)), sample.r, accuracy: 1e-9)
        }
    }

    func testIntervals() throws {
        let f = try load()
        for i in f.intervals {
            let s = FSRSScheduler(desiredRetention: i.retention)
            XCTAssertEqual(s.nextInterval(stability: i.stability), i.days, "retention \(i.retention) stability \(i.stability)")
        }
    }

    func testNewCardIsNewUntilReviewed() {
        let s = FSRSScheduler()
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let card = FSRSCard(due: now)
        XCTAssertTrue(card.isNew)
        let next = s.review(card, rating: .good, at: now)
        XCTAssertFalse(next.isNew)
        XCTAssertEqual(next.reps, 1)
        XCTAssertEqual(next.state, .learning)
        XCTAssertEqual(next.due.timeIntervalSince(now), 600, accuracy: 0.001)
    }

    func testCardDecodesWithMissingFields() throws {
        let json = #"{"due":"2026-09-27T08:00:00Z","state":2,"stability":3.5}"#
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        let card = try d.decode(FSRSCard.self, from: Data(json.utf8))
        XCTAssertEqual(card.state, .review)
        XCTAssertEqual(card.stability, 3.5)
        XCTAssertNil(card.difficulty)
        XCTAssertEqual(card.reps, 0)
    }
}
