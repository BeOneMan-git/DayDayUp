import SwiftUI

/// 首次基线 (DIAG-01, PLAN-P05, BASE-03): four small tasks — 短听读, 无准备录音, 独立短文, 词汇自测 —
/// in 2–3 sittings of 15–20 minutes. Any order; a part is saved only when it is finished.
/// Results are descriptions, never an IELTS band. When all four are done, a stage is suggested;
/// the learner decides whether to take it.
struct BaselineView: View {
    @Environment(StudyStore.self) private var study
    @Environment(PackStore.self) private var packs
    @Environment(UserStore.self) private var user
    @Environment(PracticeStore.self) private var practice
    @Environment(VocabStore.self) private var vocab

    private enum Step: Hashable {
        case speaking, writing, vocab
    }

    private struct QuizTarget: Identifiable {
        var ref: ArticleRef
        var id: String { ref.key }
    }

    @State private var step: Step?
    @State private var quiz: QuizTarget?
    @State private var listeningRef: ArticleRef?
    /// Passages opened in this visit: heard once already, so not fresh for another try.
    @State private var triedKeys: Set<String> = []
    @State private var redoPart: BaselinePart?
    @State private var stageMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                introCard
                ForEach(BaselinePart.allCases) { part in
                    partCard(part)
                }
                if study.state.baseline.isDone {
                    summaryCard
                    stageCard
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("建立基线")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $step) { s in
            destination(s)
        }
        .sheet(item: $quiz, onDismiss: { refreshPick() }) { target in
            ArticleQuizView(ref: target.ref, purpose: "baseline", onDone: { result in
                saveListening(result)
            })
        }
        .confirmationDialog("重做这一项？", isPresented: redoBinding, titleVisibility: .visible,
                            presenting: redoPart) { part in
            Button("重做") { startLater(part) }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("做完以后，新结果替换旧结果；中途离开不会改动。")
        }
        .onAppear { refreshPick() }
        .onChange(of: packs.articleCount) { _, _ in refreshPick() }
    }

    // MARK: Cards

    private var introCard: some View {
        let b = study.state.baseline
        return VStack(alignment: .leading, spacing: 8) {
            Text("4 个小任务，可以分 2–3 次做完，每次 15–20 分钟，随时可以停。结果只写成描述，不给雅思分。")
                .fixedSize(horizontal: false, vertical: true)
            Text(sittingsText(b))
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("顺序随意。每一项做完才保存，中途离开不保存。基线占用当天的学习时间，不另外加时。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }

    private func sittingsText(_ b: BaselineState) -> String {
        if b.sittings.isEmpty { return "还没开始。" }
        return "已经做了 \(b.sittings.count) 次，完成 \(b.doneCount)/4 项。"
    }

    private func partCard(_ part: BaselinePart) -> some View {
        let result = part.result(in: study.state.baseline)
        return VStack(alignment: .leading, spacing: 8) {
            AdaptiveStack(spacing: 10, rowAlignment: .firstTextBaseline) {
                Label(part.title, systemImage: part.symbol)
                    .font(.headline)
                Spacer(minLength: 8)
                statusLabel(result)
            }
            Text("难度：" + part.difficulty)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("完成条件：" + part.condition)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let result {
                Text(result.summary)
                    .font(.callout.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if part == .listening {
                listeningNote
            }
            partButton(part, done: result != nil)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func statusLabel(_ result: BaselineResult?) -> some View {
        if let result {
            Label("已完成（\(BaselineContent.shortDate(result.done))）", systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(Theme.level5)
        } else {
            Label("未做", systemImage: "circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var listeningNote: some View {
        if let ref = listeningRef {
            if let item = packs.item(ref) {
                Text("这次用：\(item.meta.title)（全文约 \(max(1, Int((item.meta.dur / 60).rounded()))) 分钟，只听其中一段）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Label("需要新版内容包（含理解题）。现在导入的内容包里没有理解题，可以先跳过这一项。", systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(Theme.warn)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func partButton(_ part: BaselinePart, done: Bool) -> some View {
        if part == .listening && listeningRef == nil {
            if !done {
                Button {
                    skipListening()
                } label: {
                    Label("先跳过这一项", systemImage: "forward")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        } else if done {
            Button {
                redoPart = part
            } label: {
                Label("重做", systemImage: "arrow.counterclockwise")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
        } else {
            Button {
                start(part)
            } label: {
                Label("开始", systemImage: "play.fill")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var summaryCard: some View {
        let b = study.state.baseline
        return VStack(alignment: .leading, spacing: 8) {
            Text("基线小结").font(.headline)
            ForEach(BaselinePart.allCases) { part in
                if let r = part.result(in: b) {
                    Text("\(part.title)：\(r.summary)")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let finished = b.finished {
                Text("完成于 \(BaselineContent.shortDate(finished))，共 \(b.sittings.count) 次。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("这些是描述，不是分数，也不换算成雅思分。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }

    private var stageCard: some View {
        let suggestion = BaselineAdvice.suggest(study.state.baseline)
        let current = study.settings.stage
        return VStack(alignment: .leading, spacing: 10) {
            Text("建议阶段：\(suggestion.stage.title)").font(.headline)
            Text(suggestion.reason)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text(suggestion.stage.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if current == suggestion.stage {
                Label("现在就是这个阶段。", systemImage: "checkmark.circle")
                    .font(.callout)
            } else {
                Text("现在的阶段：\(current.title)。阶段不会自动改，由你决定。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    adopt(suggestion.stage)
                } label: {
                    Label("采用这个阶段", systemImage: "checkmark")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            }
            if let stageMessage {
                Text(stageMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Navigation

    @ViewBuilder
    private func destination(_ s: Step) -> some View {
        switch s {
        case .speaking: BaselineSpeakingView()
        case .writing: BaselineWritingView()
        case .vocab: BaselineVocabView()
        }
    }

    private var redoBinding: Binding<Bool> {
        Binding<Bool>(get: { redoPart != nil }, set: { if !$0 { redoPart = nil } })
    }

    // MARK: Actions

    private func start(_ part: BaselinePart) {
        switch part {
        case .listening:
            refreshPick()
            if let ref = listeningRef {
                triedKeys.insert(ref.key)
                quiz = QuizTarget(ref: ref)
            }
        case .speaking:
            step = .speaking
        case .writing:
            step = .writing
        case .vocab:
            step = .vocab
        }
    }

    /// From the confirmation dialog: wait until it has gone before presenting the next page.
    private func startLater(_ part: BaselinePart) {
        Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            start(part)
        }
    }

    private func refreshPick() {
        listeningRef = BaselineContent.listeningPick(packs: packs, user: user, study: study, avoiding: triedKeys)
    }

    private func saveListening(_ result: QuizResult) {
        var summary = "理解题 \(result.correct)/\(result.total)"
        if let report = result.selfReport, !report.isEmpty {
            summary += "；" + report
        }
        let numbers: [String: Double] = ["correct": Double(result.correct), "total": Double(result.total),
                                         "seconds": result.seconds]
        study.updateBaseline { b in
            b.listening = BaselineResult(done: Date(), summary: summary, refId: result.id, numbers: numbers)
        }
        refreshPick()
    }

    private func skipListening() {
        study.updateBaseline { b in
            b.listening = BaselineResult(done: Date(), summary: "跳过：没有理解题", refId: nil, numbers: [:])
        }
    }

    private func adopt(_ stage: StudyStage) {
        study.updateSettings { $0.stage = stage }
        TodayPlanner.rebuild(packs: packs, user: user, practice: practice, vocab: vocab, study: study)
        stageMessage = "已改为“\(stage.title)”。今天的计划重新排了，已完成的任务保留。"
    }
}
