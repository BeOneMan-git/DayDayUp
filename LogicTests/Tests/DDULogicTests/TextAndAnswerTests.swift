import XCTest
#if SWIFT_PACKAGE
@testable import DDULogic
#endif

final class SentenceTextTests: XCTestCase {
    struct HashSample: Decodable {
        var text: String
        var norm: String
        var hash: String
    }

    func testHashMatchesPipeline() throws {
        let url = try TestFixtures.url(name: "text_hash", ext: "json")
        let samples = try JSONDecoder().decode([HashSample].self, from: Data(contentsOf: url))
        for s in samples {
            XCTAssertEqual(SentenceText.normalize(s.text), s.norm)
            XCTAssertEqual(SentenceText.hash(s.text), s.hash)
        }
    }

    func toks() -> [Tok] {
        [Tok(i: 10, w: "It", a: "“", z: nil, j: nil, k: "it", s: nil, e: nil, B: nil, I: nil, S: nil),
         Tok(i: 11, w: "well", a: nil, z: nil, j: "-", k: "well", s: nil, e: nil, B: nil, I: nil, S: nil),
         Tok(i: 12, w: "known", a: nil, z: ",", j: nil, k: "known", s: nil, e: nil, B: nil, I: nil, S: nil),
         Tok(i: 13, w: "firms", a: nil, z: nil, j: nil, k: "firm", s: nil, e: nil, B: nil, I: nil, S: nil),
         Tok(i: 14, w: "abandoned", a: nil, z: nil, j: nil, k: "abandon", s: nil, e: nil, B: nil, I: nil, S: nil),
         Tok(i: 15, w: "plans", a: nil, z: ".”", j: nil, k: "plan", s: nil, e: nil, B: nil, I: nil, S: nil)]
    }

    func testPlainTextAndOffsets() {
        let t = toks()
        let plain = SentenceText.plain(t)
        XCTAssertEqual(plain, "“It well-known, firms abandoned plans.”")
        XCTAssertEqual(SentenceText.span(t, first: 11, last: 12), "well-known")
        XCTAssertEqual(SentenceText.span(t, first: 14, last: 15), "abandoned plans")
        let off = SentenceText.offset(ofToken: 14, in: t)
        XCTAssertEqual(off, 22)
        var occ = Occurrence(issue: "2026-09-05", article: "x", sid: 1)
        occ.sentence = plain
        occ.surface = "abandoned"
        occ.start = off
        XCTAssertEqual(occ.blanked("___"), "“It well-known, firms ___ plans.”")
    }

    func testRangeNearOffsetPicksClosest() {
        let text = "the cat and the dog"
        let r = SentenceText.range(of: "the", in: text, near: 11)
        XCTAssertEqual(r.map { text.distance(from: text.startIndex, to: $0.lowerBound) }, 12)
    }
}

final class AnswerCheckTests: XCTestCase {
    func testExactIgnoresCaseAndPunctuation() {
        let r = AnswerCheck.check("  Abandoned. ", accepted: ["abandoned"], lemma: "abandon")
        XCTAssertEqual(r.verdict, .exact)
    }

    func testInflection() {
        let r = AnswerCheck.check("abandon", accepted: ["abandoned"], lemma: "abandon")
        XCTAssertEqual(r.verdict, .inflection)
        let r2 = AnswerCheck.check("studies", accepted: ["study"], lemma: "study")
        XCTAssertEqual(r2.verdict, .inflection)
        let r3 = AnswerCheck.check("stopped", accepted: ["stop"], lemma: nil)
        XCTAssertEqual(r3.verdict, .inflection)
    }

    func testSwapAndMissingLetters() {
        let swap = AnswerCheck.check("recieve", accepted: ["receive"], lemma: nil)
        XCTAssertEqual(swap.verdict, .close)
        XCTAssertTrue(swap.marks.contains { if case .swapped = $0 { return true } else { return false } })
        XCTAssertTrue(swap.note.contains("错序"))
        let missing = AnswerCheck.check("enviroment", accepted: ["environment"], lemma: nil)
        XCTAssertEqual(missing.verdict, .close)
        XCTAssertTrue(missing.note.contains("缺字 n"))
        let wrong = AnswerCheck.check("house", accepted: ["apparatus"], lemma: nil)
        XCTAssertEqual(wrong.verdict, .wrong)
        XCTAssertEqual(AnswerCheck.check(" ", accepted: ["a"], lemma: nil).verdict, .empty)
    }

    func testPhrases() {
        XCTAssertEqual(AnswerCheck.check("call for", accepted: ["called for"], lemma: "call for").verdict, .inflection)
        XCTAssertEqual(AnswerCheck.check("Called  for", accepted: ["called for"], lemma: nil).verdict, .exact)
    }

    func testRatingRules() {
        XCTAssertEqual(RatingRule.objective(verdict: .exact, hintUsed: false, revealedEarly: false, userAccepted: false, task: .spell, easy: false), .good)
        XCTAssertEqual(RatingRule.objective(verdict: .exact, hintUsed: false, revealedEarly: false, userAccepted: false, task: .spell, easy: true), .easy)
        XCTAssertEqual(RatingRule.objective(verdict: .exact, hintUsed: true, revealedEarly: false, userAccepted: false, task: .listen, easy: true), .hard)
        XCTAssertEqual(RatingRule.objective(verdict: .exact, hintUsed: false, revealedEarly: true, userAccepted: false, task: .listen, easy: true), .again)
        XCTAssertEqual(RatingRule.objective(verdict: .inflection, hintUsed: false, revealedEarly: false, userAccepted: false, task: .cloze, easy: false), .again)
        XCTAssertEqual(RatingRule.objective(verdict: .inflection, hintUsed: false, revealedEarly: false, userAccepted: false, task: .spell, easy: false), .hard)
        XCTAssertEqual(RatingRule.objective(verdict: .wrong, hintUsed: false, revealedEarly: false, userAccepted: true, task: .cloze, easy: false), .hard)
        XCTAssertFalse(RatingRule.isCorrect(.close, userAccepted: false))
        XCTAssertTrue(RatingRule.isCorrect(.wrong, userAccepted: true))
    }
}

final class CSVTests: XCTestCase {
    func testQuotesAndHeader() {
        let raw = "\u{FEFF}word,meaning,sentence,known\r\nabandon,\"放弃, 抛弃\",\"He said \"\"no\"\".\",1\r\ncanal,运河,,0\r\n\r\n,空行,,\r\nabandon,重复,,\r\n"
        let t = CSVTable.parse(raw)
        XCTAssertEqual(t.header, ["word", "meaning", "sentence", "known"])
        XCTAssertEqual(t.rows.count, 4)
        XCTAssertEqual(t.rows[0][1], "放弃, 抛弃")
        XCTAssertEqual(t.rows[0][2], "He said \"no\".")
        let m = CSVImportPlan.Mapping(word: t.guessColumn(["word"]), meaning: t.guessColumn(["meaning"]),
                                      sentence: t.guessColumn(["sentence"]), known: t.guessColumn(["known"]))
        let c = CSVImportPlan.candidates(t, mapping: m, existing: ["canal"])
        XCTAssertEqual(c[0].status, .ok)
        XCTAssertTrue(c[0].known)
        XCTAssertEqual(c[1].status, .alreadySaved)
        XCTAssertEqual(c[2].status, .emptyWord)
        XCTAssertEqual(c[3].status, .duplicateInFile(firstRow: 1))
    }

    func testSemicolonNoHeader() {
        let t = CSVTable.parse("mate;配偶\nmate;伙伴\n")
        XCTAssertEqual(t.delimiter, ";")
        XCTAssertEqual(t.header, ["第 1 列", "第 2 列"])
        XCTAssertEqual(t.rows.count, 2)
    }
}
