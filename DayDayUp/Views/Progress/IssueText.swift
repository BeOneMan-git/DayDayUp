import Foundation

/// Human text for one self-check point (MET-06). Issue ids look like "speaking:pr#1":
/// kind, dimension id, question index. The basic and exam templates share dimension ids,
/// so the templates of the matching kind are searched first, then all the others.
enum IssueText {
    /// The question text, e.g. "重音和语调听起来自然". Unknown → "第 n 条".
    static func text(kind: String, dim: String, question: Int) -> String {
        for list in searchOrder(kind) {
            if let d = list.first(where: { $0.id == dim }), d.questions.indices.contains(question) {
                return d.questions[question]
            }
        }
        return "第 \(question + 1) 条"
    }

    /// The dimension title, e.g. "发音".
    static func dimTitle(kind: String, dim: String) -> String {
        for list in searchOrder(kind) {
            if let d = list.first(where: { $0.id == dim }) {
                return d.title
            }
        }
        return "自评项目"
    }

    /// "发音：重音和语调听起来自然" — one line for the weekly report.
    static func line(kind: String, dim: String, question: Int) -> String {
        dimTitle(kind: kind, dim: dim) + "：" + text(kind: kind, dim: dim, question: question)
    }

    /// "口语" / "写作".
    static func kindTitle(_ kind: String) -> String {
        kind == "writing" ? "写作" : "口语"
    }

    /// "口语 · 发音 · 重音和语调听起来自然" — speaking and writing share some dimension titles (词汇、语法).
    static func title(kind: String, dim: String, question: Int) -> String {
        let parts = [kindTitle(kind), dimTitle(kind: kind, dim: dim), text(kind: kind, dim: dim, question: question)]
        return parts.joined(separator: " · ")
    }

    /// Splits "speaking:pr#1" into its parts; nil when the id has another shape.
    static func parse(_ id: String) -> (kind: String, dim: String, question: Int)? {
        guard let colon = id.firstIndex(of: ":"), let hash = id.lastIndex(of: "#"), colon < hash else {
            return nil
        }
        guard let question = Int(id[id.index(after: hash)...]) else { return nil }
        let kind = String(id[..<colon])
        let dim = String(id[id.index(after: colon)..<hash])
        return (kind, dim, question)
    }

    // MARK: Templates

    /// Which self-check template a work used: "speaking" / "part2" (speaking), "writing" / "task1" / "task2".
    static func template(speaking w: SpeakingWork) -> String {
        w.part == "p2" ? "part2" : "speaking"
    }

    static func template(writing w: WritingWork) -> String {
        switch w.kind {
        case "task1": return "task1"
        case "task2": return "task2"
        default: return "writing"
        }
    }

    /// Short name of a template, for "同一项在 Part 2 题卡里是：…".
    static func templateName(_ template: String) -> String {
        switch template {
        case "part2": return "Part 2 题卡"
        case "mock": return "完整模拟"
        case "writing": return "基础写作"
        case "task1": return "Task 1"
        case "task2": return "Task 2"
        default: return "基础口语"
        }
    }

    /// This template's own wording of the point, if it has one.
    static func wording(template: String, dim: String, question: Int) -> String? {
        guard let d = dims(template).first(where: { $0.id == dim }), d.questions.indices.contains(question) else {
            return nil
        }
        return d.questions[question]
    }

    private static func dims(_ template: String) -> [CheckDimension] {
        switch template {
        case "part2": return SelfCheckTemplate.part2
        case "mock": return SelfCheckTemplate.mock
        case "writing": return SelfCheckTemplate.writing
        case "task1": return SelfCheckTemplate.task1
        case "task2": return SelfCheckTemplate.task2
        default: return SelfCheckTemplate.speaking
        }
    }

    private static func searchOrder(_ kind: String) -> [[CheckDimension]] {
        let speaking = [SelfCheckTemplate.speaking, SelfCheckTemplate.part2, SelfCheckTemplate.mock]
        let writing = [SelfCheckTemplate.writing, SelfCheckTemplate.task1, SelfCheckTemplate.task2]
        return kind == "writing" ? writing + speaking : speaking + writing
    }
}
