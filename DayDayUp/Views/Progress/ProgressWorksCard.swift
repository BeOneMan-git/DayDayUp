import SwiftUI

/// MET-05 说写作品 / ACC-23: works that got feedback, a rewrite or a new-prompt retest, as a chain
/// 题目 → 原稿 → 反馈 → 同题重写 → 新题. Improvement on the same prompt and results on new prompts are two
/// separate lines. Works made after seeing a reference are marked and listed apart; rewrites after
/// feedback are never shown as independent work.
struct ProgressWorksCard: View {
    let playback: ProgressPlayback
    @Environment(PracticeStore.self) private var practice
    @Environment(StudyStore.self) private var study
    @State private var showAll = false

    private static let pageSize = 5

    var body: some View {
        let chains = buildChains()
        let independent = chains.filter { $0.independent }
        let assisted = chains.filter { !$0.independent }
        let mocks = practice.state.mocks.filter { !$0.feedback.isEmpty }.sorted { $0.created > $1.created }
        let shown = showAll ? independent : Array(independent.prefix(ProgressWorksCard.pageSize))
        ProgressCard("说写作品", symbol: "text.bubble",
                     footnote: "同题重写看的是改进，新题表现看的是能不能用到新题上，两者分开看；同一题改好了，不代表稳定的雅思能力。自评是你自己打的勾，反馈来源照你录入的写。") {
            if chains.isEmpty && mocks.isEmpty {
                Text("还没有收到反馈、重写过或做过新题复测的作品。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(shown) { chain in
                    ProgressChainView(chain: chain, playback: playback)
                }
                if independent.count > ProgressWorksCard.pageSize {
                    moreButton(total: independent.count)
                }
                if !assisted.isEmpty {
                    ProgressSubhead(text: "看过参考后完成的作品（单列，不算独立作答）")
                    ForEach(assisted) { chain in
                        ProgressChainView(chain: chain, playback: playback)
                    }
                }
                if !mocks.isEmpty {
                    ProgressSubhead(text: "口语完整模拟（有反馈的）")
                    ForEach(mocks) { mock in
                        mockRow(mock)
                    }
                }
            }
        }
    }

    private func moreButton(total: Int) -> some View {
        let title = showAll ? "只看最近 \(ProgressWorksCard.pageSize) 个" : "显示全部（\(total) 个）"
        return Button {
            showAll.toggle()
        } label: {
            Label(title, systemImage: showAll ? "chevron.up" : "chevron.down")
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    private func mockRow(_ mock: MockSession) -> some View {
        let parts: [String] = [ProgressFormat.short(mock.created),
                               mock.isComplete ? "完整模拟" : "不完整的模拟",
                               "\(mock.answers.count) 个回答"]
        return VStack(alignment: .leading, spacing: 2) {
            Text(parts.joined(separator: " · "))
                .font(.callout)
            Text("反馈：" + ProgressWorkText.feedback(mock.feedback))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: Chains

    private func buildChains() -> [ProgressChain] {
        var out = speakingChains()
        out.append(contentsOf: writingChains())
        return out.sorted { $0.latest > $1.latest }
    }

    /// Speaking has no versions: answering the same prompt again is the "rewrite".
    private func speakingChains() -> [ProgressChain] {
        let speaking = practice.state.speaking.filter { $0.mockId == nil && !$0.silent }
        let byPrompt = Dictionary(grouping: speaking) { $0.promptId }
        var out: [ProgressChain] = []
        for (promptId, list) in byPrompt {
            let works = list.sorted { $0.created < $1.created }
            guard let first = works.first else { continue }
            let ids = Set(works.map { $0.id })
            let retests = speaking
                .filter { w in w.retestOf.map { ids.contains($0) } ?? false }
                .sorted { $0.created < $1.created }
            let hasFeedback = works.contains { !$0.feedback.isEmpty }
            guard works.count > 1 || hasFeedback || !retests.isEmpty else { continue }
            let pending = study.state.retests.first { $0.done == nil && ids.contains($0.sourceId) }
            var dates: [Date] = works.map { $0.created }
            dates += retests.map { $0.created }
            for w in works {
                dates += w.feedback.map { $0.created }
            }
            out.append(ProgressChain(id: "sp:" + promptId, kind: .speaking, prompt: first.question,
                                     mode: ProgressWorkText.speakingTitle(first),
                                     independent: first.independent, latest: dates.max() ?? first.created,
                                     speaking: works, writing: nil, speakingRetests: retests,
                                     writingRetests: [], pending: pending))
        }
        return out
    }

    private func writingChains() -> [ProgressChain] {
        var out: [ProgressChain] = []
        for w in practice.state.writing {
            let finished = w.versions.filter { $0.finished != nil }
            let retests = practice.state.writing.filter { $0.retestOf == w.id }.sorted { $0.created < $1.created }
            guard finished.count > 1 || !w.feedback.isEmpty || !retests.isEmpty else { continue }
            let pending = study.state.retests.first { $0.done == nil && $0.sourceId == w.id }
            var dates: [Date] = [w.created]
            dates += w.versions.compactMap { $0.finished }
            dates += w.feedback.map { $0.created }
            dates += retests.map { $0.created }
            out.append(ProgressChain(id: "wr:" + w.id, kind: .writing, prompt: w.task,
                                     mode: ProgressWorkText.writingMode(w),
                                     independent: w.versions.first?.independent ?? true,
                                     latest: dates.max() ?? w.created, speaking: [], writing: w,
                                     speakingRetests: [], writingRetests: retests, pending: pending))
        }
        return out
    }
}

/// One work (speaking: all answers to one prompt) with its feedback, rewrites and new-prompt retests.
struct ProgressChain: Identifiable {
    enum Kind { case speaking, writing }

    let id: String
    let kind: Kind
    let prompt: String
    let mode: String
    let independent: Bool
    let latest: Date
    let speaking: [SpeakingWork]          // same prompt, oldest first
    let writing: WritingWork?
    let speakingRetests: [SpeakingWork]   // later works on NEW prompts whose retestOf points here
    let writingRetests: [WritingWork]
    let pending: Retest?                  // a retest that is scheduled and not done yet
}

/// Text pieces shared by the chain rows.
enum ProgressWorkText {
    /// "2 条（老师、Claude）" — sources shown as the learner typed them.
    static func feedback(_ list: [Feedback]) -> String {
        guard !list.isEmpty else { return "还没有反馈" }
        var sources: [String] = []
        for f in list where !sources.contains(f.source) {
            sources.append(f.source)
        }
        return "\(list.count) 条（" + sources.joined(separator: "、") + "）"
    }

    /// "自评做到 6/8 项" — the learner's own ticks, not a score.
    static func check(_ c: SelfCheck?) -> String? {
        guard let c else { return nil }
        let answers = c.dims.flatMap { $0.answers }
        guard !answers.isEmpty else { return nil }
        return "自评做到 \(answers.filter { $0 }.count)/\(answers.count) 项"
    }

    /// "基础口语" / "口语 Part 2" / "基线录音".
    static func speakingTitle(_ w: SpeakingWork) -> String {
        let mode = ProgressRecordingItem.speakingMode(w)
        return mode.hasPrefix("Part") ? "口语 " + mode : mode
    }

    static func writingMode(_ w: WritingWork) -> String {
        if w.promptId.hasPrefix("baseline") { return "基线短文" }
        switch w.kind {
        case "task1": return "写作 Task 1"
        case "task2": return "写作 Task 2"
        default: return "基础写作"
        }
    }

    static func speaking(_ w: SpeakingWork) -> String {
        var parts = [ProgressFormat.short(w.created), "说了 \(ProgressFormat.whole(w.speakSeconds)) 秒",
                     w.independent ? "独立" : "看过参考后"]
        if w.interrupted { parts.append("被打断") }
        if let c = check(w.check) { parts.append(c) }
        return parts.joined(separator: " · ")
    }

    static func version(_ v: WritingVersion) -> String {
        var parts = ["第 \(v.n) 版", "\(WritingStats.words(v.text)) 词"]
        if let done = v.finished {
            parts.append(ProgressFormat.short(done))
        } else {
            parts.append("还没写完")
        }
        parts.append(v.independent ? "独立完成" : "看过参考或反馈后")
        return parts.joined(separator: " · ")
    }
}

struct ProgressChainView: View {
    let chain: ProgressChain
    let playback: ProgressPlayback

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(chain.mode)
                .font(.subheadline.weight(.semibold))
            line("题目", chain.prompt, limit: 2)
            switch chain.kind {
            case .speaking:
                speakingLines
            case .writing:
                writingLines
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Speaking

    @ViewBuilder
    private var speakingLines: some View {
        if let first = chain.speaking.first {
            line("原稿", ProgressWorkText.speaking(first), playID: "sp:" + first.id, file: first.file)
        }
        line("反馈", ProgressWorkText.feedback(chain.speaking.flatMap { $0.feedback }))
        let again = Array(chain.speaking.dropFirst())
        if let last = again.last {
            line("同题重说", "又说了 \(again.count) 次；最近：" + ProgressWorkText.speaking(last),
                 playID: "sp:" + last.id, file: last.file)
        } else {
            line("同题重说", "没有")
        }
        if chain.speakingRetests.isEmpty {
            line("新题表现", pendingText)
        } else {
            ForEach(chain.speakingRetests) { r in
                line("新题表现", ProgressWorkText.speaking(r) + " · " + r.question,
                     playID: "sp:" + r.id, file: r.file, limit: 3)
            }
        }
    }

    // MARK: Writing

    @ViewBuilder
    private var writingLines: some View {
        if let w = chain.writing {
            line("原稿", w.versions.first.map { ProgressWorkText.version($0) } ?? "还没有原稿")
            line("反馈", ProgressWorkText.feedback(w.feedback))
            line("同题重写", rewriteText(w))
            if chain.writingRetests.isEmpty {
                line("新题表现", pendingText)
            } else {
                ForEach(chain.writingRetests) { r in
                    line("新题表现", retestText(r), limit: 3)
                }
            }
            ProgressDisclosure("回看各版原文（\(w.versions.count) 版）") {
                ForEach(w.versions) { v in
                    versionText(v)
                }
            }
        }
    }

    private func rewriteText(_ w: WritingWork) -> String {
        let rewrites = w.versions.dropFirst().filter { $0.finished != nil }
        guard !rewrites.isEmpty else { return "还没有重写" }
        return rewrites.map { ProgressWorkText.version($0) }.joined(separator: " → ")
    }

    private func retestText(_ r: WritingWork) -> String {
        var parts: [String] = [ProgressWorkText.writingMode(r)]
        if let first = r.versions.first {
            parts.append(ProgressWorkText.version(first))
            if let c = ProgressWorkText.check(first.check) { parts.append(c) }
        }
        parts.append(r.task)
        return parts.joined(separator: " · ")
    }

    private var pendingText: String {
        if let p = chain.pending {
            return "新题复测安排在 \(ProgressFormat.short(p.due))，还没做"
        }
        return "还没有新题复测"
    }

    private func versionText(_ v: WritingVersion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ProgressWorkText.version(v))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(v.text.isEmpty ? "（空）" : v.text)
                .font(Font.system(.body, design: .serif))
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }

    private func line(_ label: String, _ text: String, playID: String? = nil, file: String? = nil,
                      limit: Int? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label + "：")
                .font(.callout.weight(.semibold))
                .fixedSize()
            Text(text)
                .font(.callout)
                .lineLimit(limit)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let playID {
                RecordingPlayButton(id: playID, file: file, playback: playback)
            }
        }
    }
}
