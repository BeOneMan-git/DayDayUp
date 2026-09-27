import Foundation

/// Checks a typed answer for 听辨 / 拼写 / 语境填空 and explains the difference:
/// missing letters, extra letters, swapped letters, or another form of the same word.
enum AnswerCheck {
    enum Verdict: String, Equatable {
        case exact          // same word (case and outer punctuation ignored)
        case inflection     // another form of the same word (plural, past, -ing …)
        case close          // one or two letters off
        case wrong
        case empty
    }

    enum Mark: Equatable {
        case same(Character)
        case missing(Character)     // in the answer key, not typed
        case extra(Character)       // typed, not in the answer key
        case swapped(Character, Character)
    }

    struct Result: Equatable {
        var verdict: Verdict
        var matched: String?        // the accepted form that was closest
        var marks: [Mark]
        var note: String
    }

    static func clean(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?\"“”'‘’()[]"))
        return SentenceText.normalize(trimmed)
    }

    /// `accepted`: forms that count as exact (surface form first). `lemma`: base form, for 词形 notes.
    static func check(_ answer: String, accepted: [String], lemma: String?) -> Result {
        let a = clean(answer)
        let forms = accepted.map(clean).filter { !$0.isEmpty }
        guard !a.isEmpty else { return Result(verdict: .empty, matched: nil, marks: [], note: "还没有输入。") }
        guard let first = forms.first else { return Result(verdict: .wrong, matched: nil, marks: [], note: "") }
        if forms.contains(a) {
            return Result(verdict: .exact, matched: a, marks: Array(a).map { .same($0) }, note: "完全正确。")
        }
        let base = lemma.map(clean) ?? ""
        let family = (!base.isEmpty && (a == base || sameWordFamily(a, base)))
            || forms.contains(where: { sameWordFamily(a, $0) })
        if family {
            return Result(verdict: .inflection, matched: first, marks: diff(a, first),
                          note: "词形不同：你写的是 \(a)，原句里是 \(first)。")
        }
        var best = first
        var bestDistance = Int.max
        for f in forms {
            let d = distance(a, f)
            if d < bestDistance {
                bestDistance = d
                best = f
            }
        }
        let marks = diff(a, best)
        let limit = best.count >= 6 ? 2 : 1
        if bestDistance <= limit {
            return Result(verdict: .close, matched: best, marks: marks, note: describe(marks))
        }
        return Result(verdict: .wrong, matched: best, marks: marks, note: "正确答案：\(best)")
    }

    /// Plural, past, -ing, comparative and similar forms of one base word.
    static func sameWordFamily(_ a: String, _ b: String) -> Bool {
        guard a != b, !a.contains(" "), !b.contains(" ") else {
            return phraseFamily(a, b)
        }
        let suffixes = ["", "s", "es", "ed", "d", "ing", "er", "est", "ly", "ies", "ied", "ier", "iest"]
        func stems(_ w: String) -> Set<String> {
            var out: Set<String> = [w]
            for s in suffixes where !s.isEmpty && w.hasSuffix(s) && w.count - s.count >= 3 {
                let stem = String(w.dropLast(s.count))
                out.insert(stem)
                if s.hasPrefix("i") { out.insert(stem + "y") }
                let chars = Array(stem)
                if (s == "ed" || s == "ing"), chars.count >= 2, chars[chars.count - 1] == chars[chars.count - 2] {
                    out.insert(String(stem.dropLast()))          // stopped -> stop
                }
                if s == "ed" || s == "ing" || s == "er" || s == "est" { out.insert(stem + "e") }  // used -> use
            }
            return out
        }
        return !stems(a).isDisjoint(with: stems(b))
    }

    private static func phraseFamily(_ a: String, _ b: String) -> Bool {
        let wa = a.split(separator: " ").map(String.init)
        let wb = b.split(separator: " ").map(String.init)
        guard wa.count == wb.count, wa.count > 1, a != b else { return false }
        for (x, y) in zip(wa, wb) where x != y {
            if !sameWordFamily(x, y) { return false }
        }
        return true
    }

    /// Damerau–Levenshtein distance (adjacent swaps count as one edit).
    static func distance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var d = Array(repeating: Array(repeating: 0, count: y.count + 1), count: x.count + 1)
        for i in 0...x.count { d[i][0] = i }
        for j in 0...y.count { d[0][j] = j }
        for i in 1...x.count {
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, x[i - 1] == y[j - 2], x[i - 2] == y[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[x.count][y.count]
    }

    /// Letter-by-letter marks that turn `typed` into `target`.
    static func diff(_ typed: String, _ target: String) -> [Mark] {
        let x = Array(typed), y = Array(target)
        var d = Array(repeating: Array(repeating: 0, count: y.count + 1), count: x.count + 1)
        for i in 0...x.count { d[i][0] = i }
        for j in 0...y.count { d[0][j] = j }
        if !x.isEmpty && !y.isEmpty {
            for i in 1...x.count {
                for j in 1...y.count {
                    let cost = x[i - 1] == y[j - 1] ? 0 : 1
                    d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                    if i > 1, j > 1, x[i - 1] == y[j - 2], x[i - 2] == y[j - 1] {
                        d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                    }
                }
            }
        }
        var marks: [Mark] = []
        var i = x.count, j = y.count
        while i > 0 || j > 0 {
            if i > 1, j > 1, x[i - 1] == y[j - 2], x[i - 2] == y[j - 1], x[i - 1] != x[i - 2],
               d[i][j] == d[i - 2][j - 2] + 1 {
                marks.append(.swapped(y[j - 2], y[j - 1]))
                i -= 2
                j -= 2
            } else if i > 0, j > 0, x[i - 1] == y[j - 1], d[i][j] == d[i - 1][j - 1] {
                marks.append(.same(y[j - 1]))
                i -= 1
                j -= 1
            } else if i > 0, j > 0, d[i][j] == d[i - 1][j - 1] + 1 {
                marks.append(.missing(y[j - 1]))
                marks.append(.extra(x[i - 1]))
                i -= 1
                j -= 1
            } else if j > 0, d[i][j] == d[i][j - 1] + 1 {
                marks.append(.missing(y[j - 1]))
                j -= 1
            } else if i > 0 {
                marks.append(.extra(x[i - 1]))
                i -= 1
            } else {
                break
            }
        }
        return marks.reversed()
    }

    static func describe(_ marks: [Mark]) -> String {
        var missing: [Character] = []
        var extra: [Character] = []
        var swaps: [String] = []
        for m in marks {
            switch m {
            case .missing(let c): missing.append(c)
            case .extra(let c): extra.append(c)
            case .swapped(let a, let b): swaps.append("\(b)\(a)→\(a)\(b)")
            case .same: break
            }
        }
        var parts: [String] = []
        if !missing.isEmpty { parts.append("缺字 " + missing.map(String.init).joined(separator: "、")) }
        if !extra.isEmpty { parts.append("多写 " + extra.map(String.init).joined(separator: "、")) }
        if !swaps.isEmpty { parts.append("错序 " + swaps.joined(separator: "、")) }
        return parts.isEmpty ? "" : "差一点：" + parts.joined(separator: "；") + "。"
    }
}

/// How an answer turns into an FSRS rating. Independent success is never claimed
/// when the answer was shown first (VOC-F03, ACC-11).
enum RatingRule {
    static func objective(verdict: AnswerCheck.Verdict, hintUsed: Bool, revealedEarly: Bool,
                          userAccepted: Bool, task: VocabTask, easy: Bool) -> FSRSRating {
        if revealedEarly { return .again }
        switch verdict {
        case .exact:
            if hintUsed { return .hard }
            return easy ? .easy : .good
        case .inflection:
            // 拼写: right word, wrong form = partly known. 填空: the form is the point, so it is wrong.
            if task == .cloze { return userAccepted ? .hard : .again }
            return .hard
        case .close, .wrong, .empty:
            return userAccepted ? .hard : .again
        }
    }

    static func isCorrect(_ verdict: AnswerCheck.Verdict, userAccepted: Bool) -> Bool {
        verdict == .exact || userAccepted
    }
}
