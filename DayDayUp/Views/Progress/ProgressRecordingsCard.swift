import SwiftUI

/// MET-04 录音轨迹: the first speaking recording, the latest ones and the new-prompt retests, plus the
/// first and latest take of the most practised 跟读 sentences. Each row keeps its own mode, prompt and
/// conditions; there are no scores and nothing connects recordings made under different conditions.
struct ProgressRecordingsCard: View {
    let playback: ProgressPlayback
    @Environment(PracticeStore.self) private var practice
    @Environment(PackStore.self) private var packs

    var body: some View {
        let works = practice.state.speaking.filter { !$0.silent }.sorted { $0.created < $1.created }
        let groups = shadowGroups()
        ProgressCard("录音轨迹", symbol: "waveform",
                     footnote: "只列录音和录的时候的条件，不打分；模式或条件不同的录音分开放，不连成线。只录到静音的不列。") {
            if works.isEmpty && groups.isEmpty {
                Text("还没有口语或跟读录音。")
                    .foregroundStyle(.secondary)
            } else {
                speakingSection(works)
                shadowSection(groups)
            }
        }
    }

    // MARK: 口语

    @ViewBuilder
    private func speakingSection(_ works: [SpeakingWork]) -> some View {
        if let first = works.first {
            ProgressSubhead(text: "口语 · 第一次录音")
            ProgressRecordingRow(item: ProgressRecordingItem.speaking(first, role: "第一次"), playback: playback)
            let recent = Array(works.reversed().filter { $0.id != first.id }.prefix(3))
            if !recent.isEmpty {
                ProgressSubhead(text: "口语 · 最近 \(recent.count) 次")
                ForEach(recent) { w in
                    ProgressRecordingRow(item: ProgressRecordingItem.speaking(w, role: "最近"), playback: playback)
                }
            }
            let retests = Array(works.filter { $0.retestOf != nil }.reversed().prefix(5))
            if !retests.isEmpty {
                ProgressSubhead(text: "口语 · 新题复测")
                ForEach(retests) { w in
                    retestPair(w)
                }
            }
        }
    }

    @ViewBuilder
    private func retestPair(_ w: SpeakingWork) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressRecordingRow(item: ProgressRecordingItem.speaking(w, role: "新题"), playback: playback)
            if let source = w.retestOf.flatMap({ practice.speaking($0) }) {
                ProgressRecordingRow(item: ProgressRecordingItem.speaking(source, role: "原作品"), playback: playback)
                    .padding(.leading, 16)
            }
        }
    }

    // MARK: 跟读

    private struct ShadowGroup: Identifiable {
        let id: String
        let takes: [ShadowAttempt]     // oldest first
    }

    private func shadowGroups() -> [ShadowGroup] {
        let takes = practice.state.shadow.filter { !$0.silent }
        let grouped = Dictionary(grouping: takes) { "\($0.article)#\($0.sid)" }
        let groups = grouped.map { entry in
            ShadowGroup(id: entry.key, takes: entry.value.sorted { $0.created < $1.created })
        }
        let sorted = groups.sorted { a, b in
            if a.takes.count != b.takes.count { return a.takes.count > b.takes.count }
            return (a.takes.last?.created ?? .distantPast) > (b.takes.last?.created ?? .distantPast)
        }
        return Array(sorted.prefix(5))
    }

    @ViewBuilder
    private func shadowSection(_ groups: [ShadowGroup]) -> some View {
        if !groups.isEmpty {
            ProgressSubhead(text: "跟读 · 练得最多的 \(groups.count) 句")
            ForEach(groups) { g in
                shadowGroup(g)
            }
        }
    }

    @ViewBuilder
    private func shadowGroup(_ g: ShadowGroup) -> some View {
        if let first = g.takes.first, let last = g.takes.last {
            VStack(alignment: .leading, spacing: 4) {
                Text(groupTitle(g, sample: last))
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                ProgressRecordingRow(item: ProgressRecordingItem.shadow(first, role: "第一次"), playback: playback)
                if g.takes.count > 1 {
                    ProgressRecordingRow(item: ProgressRecordingItem.shadow(last, role: "最近一次"), playback: playback)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func groupTitle(_ g: ShadowGroup, sample: ShadowAttempt) -> String {
        var title = sample.article
        if let ref = ArticleRef(key: sample.article), let item = packs.item(ref) {
            title = item.meta.title
        }
        return "\(title) · 共 \(g.takes.count) 次"
    }
}

/// One recording as shown in the list: when, which mode, what was said, under which conditions.
struct ProgressRecordingItem: Identifiable {
    let id: String
    let date: Date
    let role: String
    let mode: String
    let text: String
    let conditions: String
    let flags: [String]
    let file: String?

    static func speaking(_ w: SpeakingWork, role: String) -> ProgressRecordingItem {
        var parts: [String] = []
        let prep = ProgressFormat.whole(w.prepSeconds)
        parts.append(prep > 0 ? "准备 \(prep) 秒" : "没有准备")
        parts.append("说了 \(ProgressFormat.whole(w.speakSeconds)) 秒")
        parts.append("目标 \(ProgressFormat.whole(w.target)) 秒")
        parts.append(w.independent ? "独立" : "看过参考后")
        var flags: [String] = []
        if w.interrupted { flags.append("被打断") }
        return ProgressRecordingItem(id: "sp:" + w.id, date: w.created, role: role, mode: speakingMode(w),
                                     text: w.question, conditions: parts.joined(separator: " · "),
                                     flags: flags, file: w.file)
    }

    static func shadow(_ a: ShadowAttempt, role: String) -> ProgressRecordingItem {
        let mode = ShadowMode(rawValue: a.mode)
        var parts = ["录了 " + String(format: "%.1f", a.seconds) + " 秒"]
        if mode == .repeatAfter || mode == .shadowing {
            parts.append("原音 " + rateText(a.rate))
        }
        if let out = a.output, !out.isEmpty {
            parts.append("输出：\(out)")
        }
        var flags: [String] = []
        if a.interrupted { flags.append("被打断") }
        if a.crosstalk == true { flags.append("可能串音") }
        if let hints = a.hints, !hints.isEmpty { flags.append("看了 \(hints.count) 个提示") }
        return ProgressRecordingItem(id: "sh:" + a.id, date: a.created, role: role,
                                     mode: "跟读 · " + (mode?.title ?? a.mode), text: a.text,
                                     conditions: parts.joined(separator: " · "), flags: flags, file: a.file)
    }

    /// 基础口语 / Part 2 / 完整模拟 · Part 1 …
    static func speakingMode(_ w: SpeakingWork) -> String {
        if w.promptId.hasPrefix("baseline") { return "基线录音" }
        let part: String
        switch w.part {
        case "p1": part = "Part 1"
        case "p2": part = "Part 2"
        case "p3": part = "Part 3"
        default: part = "基础口语"
        }
        return w.mockId == nil ? part : "完整模拟 · " + part
    }

    static func rateText(_ r: Double) -> String {
        abs(r - 1) < 0.001 ? "1.0×" : String(format: "%g×", r)
    }
}

struct ProgressRecordingRow: View {
    let item: ProgressRecordingItem
    let playback: ProgressPlayback

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.role + " · " + ProgressFormat.short(item.date) + " · " + item.mode)
                    .font(.subheadline.weight(.semibold))
                Text(item.text)
                    .font(.callout)
                    .lineLimit(2)
                Text(item.conditions)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !item.flags.isEmpty {
                    Label(item.flags.joined(separator: " · "), systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Theme.warn)
                }
            }
            Spacer(minLength: 8)
            RecordingPlayButton(id: item.id, file: item.file, playback: playback)
        }
        .padding(.vertical, 2)
    }
}
