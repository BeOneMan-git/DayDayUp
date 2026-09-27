import SwiftUI

// 证据 cards: 词汇回忆 (MET-02, VOC-P05), 文章理解 (PAGE-07), 词项状态 (MET-03).

/// MET-02 / VOC-P05: delayed recall per task in a fixed 28-day window, counts first; a rate only from 30.
struct ProgressRecallCard: View {
    @Environment(VocabStore.self) private var vocab

    var body: some View {
        let stats = Metrics.recall(events: vocab.events, now: Date(), windowDays: 28)
            .filter { $0.attempts > 0 || $0.sameDayRetries > 0 }
        ProgressCard("词汇回忆（近 28 天）", symbol: "character.book.closed",
                     footnote: "只算距离上次复习至少 24 小时的当天第一次作答；先看答案的不算。FSRS（安排复习时间的算法）的预测不是实测。") {
            if stats.isEmpty {
                Text("近 28 天还没有隔天的词汇复习。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(stats, id: \.task) { stat in
                    ProgressRecallRow(stat: stat)
                    if stat.task != stats.last?.task {
                        Divider()
                    }
                }
            }
        }
    }
}

private struct ProgressRecallRow: View {
    let stat: Metrics.RecallStat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(stat.task.title)
                    .font(.body.weight(.semibold))
                Spacer(minLength: 12)
                Text(countText)
                    .monospacedDigit()
            }
            if stat.attempts >= Metrics.recallMinimum {
                Label(rateText, systemImage: "checkmark.circle")
                    .font(.callout)
            } else {
                SmallSampleTag("证据不足（\(stat.successes)/\(stat.attempts)）")
            }
            ForEach(extraLines, id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var countText: String {
        "成功 \(stat.successes) / 尝试 \(stat.attempts)"
    }

    private var rateText: String {
        "成功率 " + String(ProgressFormat.percent(stat.successes, stat.attempts)) + "%（\(stat.attempts) 次）"
    }

    private var extraLines: [String] {
        var out: [String] = []
        if stat.attempts == 0 {
            out.append("还没有隔天的复习。")
        }
        if stat.objective && stat.withHint > 0 {
            out.append("看提示后答对 \(stat.withHint) 次（不算成功）")
        }
        if stat.sameDayRetries > 0 {
            out.append("同日重试 \(stat.sameDayRetries) 次（不计入）")
        }
        return out
    }
}

// MARK: 文章理解

/// Comprehension checks in the window: 隔日回忆 and 新材料复测 apart; baseline and practice collapsed.
struct ProgressComprehensionCard: View {
    let window: Int
    @Environment(StudyStore.self) private var study
    @Environment(PackStore.self) private var packs

    var body: some View {
        let from = DayKey.adding(-(window - 1), to: DayKey.today)
        let results = study.state.quizResults.filter { $0.day >= from }.sorted { $0.at > $1.at }
        let titles = ProgressTitles.map(packs)
        let delayed = results.filter { $0.purpose == "delayed" }
        let weekly = results.filter { $0.purpose == "weekly" }
        let other = results.filter { $0.purpose != "delayed" && $0.purpose != "weekly" }
        ProgressCard("文章理解（最近 \(window) 天）", symbol: "doc.text.magnifyingglass",
                     footnote: "隔日回忆：听完第二天凭记忆答题，不重听。新材料复测：没学过的材料，只听一小段再答。只数题目，不换算成分数。") {
            ProgressQuizGroup(title: "隔日回忆", results: delayed, titles: titles,
                              empty: "这段时间没有隔日回忆。")
            Divider()
            ProgressQuizGroup(title: "新材料复测", results: weekly, titles: titles,
                              empty: "这段时间没有新材料复测。")
            if !other.isEmpty {
                Divider()
                ProgressDisclosure("其他（基线、练习）\(other.count) 次") {
                    ProgressQuizRows(results: other, titles: titles)
                }
            }
        }
    }
}

/// Article key → title, from the installed packs.
enum ProgressTitles {
    @MainActor
    static func map(_ packs: PackStore) -> [String: String] {
        var out: [String: String] = [:]
        for item in packs.allItems where out[item.ref.key] == nil {
            out[item.ref.key] = item.meta.title
        }
        return out
    }
}

private struct ProgressQuizGroup: View {
    let title: String
    let results: [QuizResult]
    let titles: [String: String]
    let empty: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            if results.isEmpty {
                Text(empty)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                if results.count < Metrics.smallSample {
                    SmallSampleTag("样本少（\(results.count) 次）")
                }
                ProgressQuizRows(results: results, titles: titles)
            }
        }
    }

    private var summary: String {
        guard !results.isEmpty else { return "" }
        let right = results.reduce(0) { $0 + $1.correct }
        let total = results.reduce(0) { $0 + $1.total }
        return "\(results.count) 次 · 共答对 \(right) / \(total) 题"
    }
}

private struct ProgressQuizRows: View {
    let results: [QuizResult]
    let titles: [String: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(results) { r in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(ProgressFormat.short(r.day) + " · " + (titles[r.article] ?? r.article))
                        Spacer(minLength: 12)
                        Text("\(r.correct)/\(r.total)")
                            .monospacedDigit()
                    }
                    if let detail = detail(r) {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func detail(_ r: QuizResult) -> String? {
        var parts: [String] = []
        switch r.purpose {
        case "baseline": parts.append("基线")
        case "practice": parts.append("练习")
        default: break
        }
        if r.usedText { parts.append("看着原文") }
        if let note = r.selfReport, !note.isEmpty { parts.append(note) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: 词项状态

/// MET-03: each ability on its own row; one item with several cards is still one item.
struct ProgressVocabStateCard: View {
    @Environment(VocabStore.self) private var vocab

    var body: some View {
        let counts = Metrics.abilityCounts(items: vocab.state.items, cards: vocab.state.cards)
        let items = vocab.activeItems.count
        ProgressCard("词项状态", symbol: "square.grid.3x3",
                     footnote: "同一个词的多张卡只算一个词项；不推算总词汇量。“较长复习间隔”只说明下次复习在 21 天以后。") {
            if items == 0 {
                Text("词汇本里还没有词项。")
                    .foregroundStyle(.secondary)
            } else {
                Text("词汇本里有 \(items) 个词项（不含已归档）。")
                    .font(.callout)
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        headerCell("能力")
                        headerCell("未开启")
                        headerCell("新")
                        headerCell("学习中")
                        headerCell("较长复习间隔（≥21 天）")
                    }
                    Divider()
                    ForEach(counts, id: \.ability.rawValue) { c in
                        GridRow {
                            Text(c.ability.title)
                            numberCell(c.off)
                            numberCell(c.new)
                            numberCell(c.learning)
                            numberCell(c.longInterval)
                        }
                    }
                }
            }
        }
    }

    private func headerCell(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func numberCell(_ n: Int) -> some View {
        Text("\(n)")
            .monospacedDigit()
    }
}
