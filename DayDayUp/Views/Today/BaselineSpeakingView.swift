import SwiftUI
import UIKit

/// 基线 · 无准备录音: the prompt appears with a 3-2-1 countdown, then up to 60 seconds of recording
/// (owner "baseline"). The take is saved like every other take (a SpeakingWork, independent, no preparation);
/// the baseline part is saved only after the three yes/no self-descriptions.
struct BaselineSpeakingView: View {
    @Environment(PracticeStore.self) private var practice
    @Environment(StudyStore.self) private var study
    @Environment(RecorderService.self) private var recorder
    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case ready, countdown, recording, review, saved
    }

    @State private var phase: Phase = .ready
    @State private var prompt = BaselineContent.speakingPrompts[0]
    @State private var countdown = 3
    @State private var countdownTask: Task<Void, Never>?
    @State private var workId: String?
    @State private var answers: [Bool?] = [nil, nil, nil]
    @State private var savedSummary: String?
    @State private var message: String?
    @State private var confirmLeave = false
    @State private var player = SegmentPlayer()

    static let questions = ["说满了 45 秒", "中间没有很长的停顿", "大多是完整的句子"]

    private var inProgress: Bool {
        phase == .countdown || phase == .recording || phase == .review
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch phase {
                case .ready: readyCard
                case .countdown: countdownCard
                case .recording: recordingCard
                case .review: reviewSection
                case .saved: savedCard
                }
                if recorder.denied && (phase == .ready || phase == .review) {
                    MicrophoneDeniedCard {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    if phase == .ready {
                        Button {
                            skip()
                        } label: {
                            Label("先跳过这一项", systemImage: "forward")
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    }
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
        .navigationTitle("无准备录音")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(inProgress)
        .toolbar {
            if inProgress {
                ToolbarItem(placement: .topBarLeading) {
                    Button("离开") { confirmLeave = true }
                }
            }
        }
        .confirmationDialog("离开无准备录音？", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("离开", role: .destructive) { leave() }
            Button("继续做", role: .cancel) {}
        } message: {
            Text("录好的声音会保存在练习记录里，但这一项不会记为完成。")
        }
        .onAppear {
            recorder.refreshPermission()
            if phase == .ready {
                prompt = BaselineContent.nextSpeakingPrompt(practice: practice)
            }
        }
        .onDisappear {
            countdownTask?.cancel()
            countdownTask = nil
            if phase == .countdown { phase = .ready }
            player.stop()
            if recorder.owner == "baseline" { recorder.stop() }
            AudioSessionControl.usePlayback()
        }
    }

    // MARK: Phases

    private var readyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("不准备，直接说").font(.headline)
            Text("点“看题并开始”后，题目出现，倒数 3 秒就开始录音。最多 60 秒，说到 45 秒以上就可以停。说不下去也没关系，照实记录。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("录音只存在这台 iPad 上。结果只写成描述，不打分。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                startCountdown()
            } label: {
                Label("看题并开始", systemImage: "mic")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(recorder.isBusy)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(prompt.en)
                .font(Font.system(.title2, design: .serif).weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(prompt.zh)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }

    private var countdownCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            promptCard
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("准备开口")
                    .font(.headline)
                Text("\(countdown)")
                    .font(.system(size: 56, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel("还有 \(countdown) 秒开始录音")
            }
            Button {
                countdownTask?.cancel()
                countdownTask = nil
                phase = .ready
            } label: {
                Label("先不录", systemImage: "xmark")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
    }

    private var recordingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            promptCard
            RecordingMeter(elapsed: recorder.elapsed, level: recorder.level,
                           limit: BaselineContent.speakingLimit, target: BaselineContent.speakingTarget)
            Button {
                recorder.stop()
            } label: {
                Label("说完了", systemImage: "stop.circle.fill")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }

    @ViewBuilder
    private var reviewSection: some View {
        if let id = workId, let work = practice.speaking(id) {
            promptCard
            takeCard(work)
            if work.silent {
                Button {
                    retake()
                } label: {
                    Label("换一道题再录一次", systemImage: "arrow.counterclockwise")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            } else {
                selfCheckCard
            }
        } else {
            Text("这次的录音没有找到。可以再录一次。")
                .foregroundStyle(.secondary)
            Button {
                retake()
            } label: {
                Label("再录一次", systemImage: "arrow.counterclockwise")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
    }

    private func takeCard(_ work: SpeakingWork) -> some View {
        let playing = player.playing == .mine
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("这次说了 \(Int(work.speakSeconds.rounded())) 秒")
                    .font(.headline)
                if work.interrupted {
                    Badge(text: "被打断", color: Theme.warn, outlined: true)
                }
                Spacer()
                Button {
                    togglePlayback(work)
                } label: {
                    Label(playing ? "停止" : "回放", systemImage: playing ? "stop.fill" : "play.fill")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(practice.recordingURL(work.file) == nil)
            }
            if work.silent {
                Text("只录到静音。看看麦克风有没有被挡住，再录一次。")
                    .foregroundStyle(Theme.warn)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }

    private var selfCheckCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("回放一遍，照实回答").font(.headline)
            Text("只是描述这一次，不打分。")
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach(0..<BaselineSpeakingView.questions.count, id: \.self) { i in
                BaselineYesNoRow(question: BaselineSpeakingView.questions[i], value: answerBinding(i))
            }
            Button {
                saveResult()
            } label: {
                Label("完成这一项", systemImage: "checkmark.circle")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(answers.contains { $0 == nil })
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }

    private var savedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("已保存", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(Theme.level5)
            if let savedSummary {
                Text(savedSummary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    private func answerBinding(_ i: Int) -> Binding<Bool?> {
        Binding<Bool?>(
            get: { answers.indices.contains(i) ? answers[i] : nil },
            set: { value in
                guard answers.indices.contains(i) else { return }
                answers[i] = value
                ActivityClock.shared.touch(.output, source: "baseline")
            }
        )
    }

    // MARK: Actions

    private func startCountdown() {
        guard !recorder.isBusy else { return }
        message = nil
        prompt = BaselineContent.nextSpeakingPrompt(practice: practice)
        countdown = 3
        phase = .countdown
        countdownTask?.cancel()
        countdownTask = Task {
            for n in [3, 2, 1] {
                countdown = n
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
            }
            countdownTask = nil
            startRecording()
        }
    }

    private func startRecording() {
        guard !recorder.isBusy else { return }
        player.stop()
        engine.pause()
        let url = practice.newRecordingURL()
        let current = prompt
        let store = practice
        let studyStore = study
        Task {
            let ok = await recorder.start(into: url, owner: "baseline", maxDuration: BaselineContent.speakingLimit) { result in
                finishRecording(result, prompt: current, practice: store, study: studyStore)
            }
            if ok {
                if phase == .countdown { phase = .recording }
            } else if !recorder.isBusy {
                phase = .ready
                message = recorder.denied ? "没有麦克风权限，录不了音。" : "录音没有启动，请再试一次。"
            }
        }
    }

    /// Every take is kept, like in 口语. A baseline take never completes a retest started from 今日.
    private func finishRecording(_ result: RecordingResult, prompt: BaselinePrompt, practice: PracticeStore,
                                 study: StudyStore) {
        let work = SpeakingWork(id: UUID().uuidString, promptId: prompt.id, question: prompt.en, created: Date(),
                                prepSeconds: 0, speakSeconds: result.seconds, target: BaselineContent.speakingLimit,
                                file: result.file, peakDb: result.peakDb, silent: result.silent,
                                interrupted: result.interrupted, independent: true)
        let pendingRetest = study.activeRetest
        study.activeRetest = nil
        practice.addSpeaking(work)
        study.activeRetest = pendingRetest
        practice.saveNow()
        workId = work.id
        answers = [nil, nil, nil]
        phase = .review
        if result.interrupted {
            message = "录音被打断，已保存 \(Int(result.seconds.rounded())) 秒。"
        }
    }

    private func togglePlayback(_ work: SpeakingWork) {
        if player.playing == .mine {
            player.stop()
        } else if let url = practice.recordingURL(work.file) {
            engine.pause()
            ActivityClock.shared.touch(.output, source: "baseline")
            Task { await player.play(url, as: .mine) }
        }
    }

    private func retake() {
        player.stop()
        workId = nil
        answers = [nil, nil, nil]
        message = nil
        phase = .ready
    }

    private func saveResult() {
        guard let id = workId, let work = practice.speaking(id) else { return }
        let flags = answers.map { $0 ?? false }
        guard flags.count == 3 else { return }
        let phrases = [flags[0] ? "说满 45 秒" : "没说满 45 秒",
                       flags[1] ? "没有很长的停顿" : "有较长停顿",
                       flags[2] ? "大多是完整句子" : "完整句子不多"]
        let summary = "说了 \(Int(work.speakSeconds.rounded())) 秒；自评：" + phrases.joined(separator: "，")
        let numbers: [String: Double] = [
            "seconds": work.speakSeconds, "peakDb": work.peakDb,
            "full45": flags[0] ? 1 : 0, "noLongPause": flags[1] ? 1 : 0, "sentences": flags[2] ? 1 : 0,
        ]
        study.updateBaseline { b in
            b.speaking = BaselineResult(done: Date(), summary: summary, refId: id, numbers: numbers)
        }
        ActivityClock.shared.touch(.output, source: "baseline")
        player.stop()
        savedSummary = summary
        phase = .saved
    }

    private func skip() {
        study.updateBaseline { b in
            b.speaking = BaselineResult(done: Date(), summary: "跳过：没有麦克风权限", refId: nil, numbers: [:])
        }
        dismiss()
    }

    private func leave() {
        countdownTask?.cancel()
        countdownTask = nil
        player.stop()
        if recorder.owner == "baseline" { recorder.stop() }
        dismiss()
    }
}

/// A yes/no question; the choice shows as a symbol plus text, not colour alone.
struct BaselineYesNoRow: View {
    let question: String
    @Binding var value: Bool?

    var body: some View {
        HStack(spacing: 12) {
            Text(question)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            choice("是", true)
            choice("否", false)
        }
        .accessibilityElement(children: .contain)
    }

    private func choice(_ title: String, _ answer: Bool) -> some View {
        let selected = value == answer
        return Button {
            value = answer
        } label: {
            Label(title, systemImage: selected ? "checkmark.circle.fill" : "circle")
                .frame(minWidth: 64, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(selected ? Theme.accent : Color.secondary)
        .accessibilityLabel("\(question)：\(title)")
        .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }
}
