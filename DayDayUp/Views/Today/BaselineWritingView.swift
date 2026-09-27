import SwiftUI

/// 基线 · 独立短文: one original prompt, 10 minutes on a visible timer (the learner can stop early),
/// live word and sentence count, no hints and no reference. Saved as a WritingWork (kind "basic",
/// one finished, independent version) and as the baseline part, only when finished.
struct BaselineWritingView: View {
    @Environment(PracticeStore.self) private var practice
    @Environment(StudyStore.self) private var study
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case ready, writing, saved
    }

    @State private var phase: Phase = .ready
    @State private var text = ""
    @State private var elapsed: Double = 0
    @State private var startedAt = Date()
    @State private var ticker: Task<Void, Never>?
    @State private var sceneActive = true
    @State private var lastTouch = Date.distantPast
    @State private var savedSummary: String?
    @State private var message: String?
    @State private var confirmLeave = false
    @FocusState private var editorFocused: Bool

    private var prompt: BaselinePrompt { BaselineContent.writingPrompt }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                promptCard
                switch phase {
                case .ready: readyCard
                case .writing: editorCard
                case .saved: savedCard
                }
                if let message {
                    Label(message, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("独立短文")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(phase == .writing)
        .toolbar {
            if phase == .writing {
                ToolbarItem(placement: .topBarLeading) {
                    Button("离开") { confirmLeave = true }
                }
            }
        }
        .confirmationDialog("离开独立短文？", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("离开，不保存", role: .destructive) { leave() }
            Button("继续写", role: .cancel) {}
        } message: {
            Text("中途离开，这次写的内容不会保存，这一项也不会记为完成。")
        }
        .onChange(of: text) { _, _ in
            touchWhileTyping()
        }
        .onChange(of: scenePhase) { _, newPhase in
            sceneActive = newPhase == .active
        }
        .onDisappear {
            ticker?.cancel()
            ticker = nil
        }
    }

    // MARK: Cards

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Badge(text: "10 分钟", outlined: true)
                Badge(text: "不给提示和参考", outlined: true)
            }
            Text(prompt.en)
                .font(Font.system(.title3, design: .serif).weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(prompt.zh)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }

    private var readyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("写一段话，想到什么写什么。计时 10 分钟，时间到自动保存；写完了也可以提前结束。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                startWriting()
            } label: {
                Label("开始写", systemImage: "pencil")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var editorCard: some View {
        let words = WritingStats.words(text)
        let sentences = WritingStats.sentences(text)
        let left = max(0, BaselineContent.writingLimit - elapsed)
        return VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 16, lineSpacing: 6) {
                Label("还剩 \(formatTime(left))", systemImage: "timer")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(left <= 60 ? Theme.warn : Theme.accent)
                Text("\(words) 词 · \(sentences) 句")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            TextEditor(text: $text)
                .font(Font.system(.title3, design: .serif))
                .focused($editorFocused)
                .frame(minHeight: 260)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.3)))
                .accessibilityLabel("短文")
            Button {
                finish()
            } label: {
                Label("写完了", systemImage: "checkmark.seal")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(words == 0)
        }
    }

    private var savedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("已保存", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(Theme.level5)
            if let savedSummary {
                Text(savedSummary)
            }
            Text(text)
                .font(Font.system(.body, design: .serif))
                .lineSpacing(4)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text("原稿只读，已存进练习记录。以后可以拿它和新写的短文对照。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                dismiss()
            } label: {
                Label("回到基线", systemImage: "chevron.backward")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Actions

    private func startWriting() {
        text = ""
        elapsed = 0
        message = nil
        startedAt = Date()
        phase = .writing
        editorFocused = true
        ActivityClock.shared.touch(.output, source: "baseline")
        ticker?.cancel()
        ticker = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                guard phase == .writing else { return }
                if sceneActive { elapsed += 1 }
                if elapsed >= BaselineContent.writingLimit {
                    timeUp()
                    return
                }
            }
        }
    }

    /// Typing is practice time; one touch every few seconds is enough for the 60-second window.
    private func touchWhileTyping() {
        guard phase == .writing else { return }
        let now = Date()
        guard now.timeIntervalSince(lastTouch) >= 5 else { return }
        lastTouch = now
        ActivityClock.shared.touch(.output, source: "baseline")
    }

    private func timeUp() {
        if WritingStats.words(text) == 0 {
            ticker?.cancel()
            ticker = nil
            phase = .ready
            message = "10 分钟到了，还没有写字，所以没有保存。准备好了可以再开始。"
            return
        }
        finish()
    }

    private func finish() {
        guard phase == .writing else { return }
        ticker?.cancel()
        ticker = nil
        editorFocused = false
        let finalText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = WritingStats.words(finalText)
        let sentences = WritingStats.sentences(finalText)
        let seconds = min(elapsed, BaselineContent.writingLimit)
        let now = Date()
        let version = WritingVersion(id: UUID().uuidString, n: 1, text: finalText, started: startedAt, finished: now,
                                     seconds: seconds, independent: true, check: nil)
        var work = WritingWork(id: UUID().uuidString, promptId: prompt.id, task: prompt.en, created: startedAt,
                               versions: [version])
        work.kind = "basic"
        work.targetMinutes = BaselineContent.writingLimit / 60
        // A baseline text never completes a retest started from 今日.
        let pendingRetest = study.activeRetest
        study.activeRetest = nil
        practice.addWriting(work)
        study.activeRetest = pendingRetest
        practice.saveNow()

        let timeText = seconds < 60 ? "用时 \(Int(seconds)) 秒" : "用时 \(Int((seconds / 60).rounded())) 分钟"
        let summary = "写了 \(words) 词、\(sentences) 句，\(timeText)"
        let numbers: [String: Double] = ["words": Double(words), "sentences": Double(sentences), "seconds": seconds]
        let workId = work.id
        study.updateBaseline { b in
            b.writing = BaselineResult(done: now, summary: summary, refId: workId, numbers: numbers)
        }
        ActivityClock.shared.touch(.output, source: "baseline")
        text = finalText
        savedSummary = summary
        phase = .saved
    }

    private func leave() {
        ticker?.cancel()
        ticker = nil
        dismiss()
    }
}
