import SwiftUI
import UIKit

/// 基础口语: prepare 30 s (can skip), speak about 45 s (can go on longer, the real time is kept),
/// then self-assess on the four criteria before the reference is shown.
struct SpeakingSessionView: View {
    let prompt: SpeakingPrompt

    @Environment(PracticeStore.self) private var practice
    @Environment(RecorderService.self) private var recorder
    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.openURL) private var openURL

    enum Phase {
        case ready, preparing, speaking, review
    }

    @State private var phase: Phase = .ready
    @State private var showHints = false
    @State private var prepLeft: Double = 30
    @State private var prepUsed: Double = 0
    @State private var prepTask: Task<Void, Never>?
    @State private var workId: String?
    @State private var check = SelfCheckTemplate.empty(SelfCheckTemplate.speaking)
    @State private var showFeedback = false
    @State private var message: String?
    @State private var player = SegmentPlayer()

    static let prepSeconds: Double = 30
    static let target: Double = 45
    static let limit: Double = 180

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                promptCard
                switch phase {
                case .ready: readyCard
                case .preparing: preparingCard
                case .speaking: speakingCard
                case .review: reviewSection
                }
                if recorder.denied {
                    MicrophoneDeniedCard {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                if let message {
                    Label(message, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                history
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("基础口语")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showFeedback) {
            FeedbackSheet { feedback in
                if let id = workId {
                    practice.updateSpeaking(id) { $0.feedback.append(feedback) }
                }
            }
        }
        .onDisappear {
            prepTask?.cancel()
            prepTask = nil
            if phase == .preparing { phase = .ready }
            player.stop()
            if recorder.owner == "speaking" { recorder.stop() }
            AudioSessionControl.usePlayback()
        }
    }

    // MARK: Prompt

    private var promptCard: some View {
        PracticeCard {
            HStack {
                Badge(text: prompt.topic)
                Badge(text: "准备 30 秒 · 说 45 秒", outlined: true)
                Spacer()
                Toggle("提示", isOn: $showHints)
                    .toggleStyle(.button)
                    .controlSize(.small)
            }
            Text(prompt.question)
                .font(Font.system(.title2, design: .serif).weight(.semibold))
                .textSelection(.enabled)
            Text(prompt.zh)
                .foregroundStyle(.secondary)
            if showHints {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(prompt.hints, id: \.self) { hint in
                        Label(hint, systemImage: "lightbulb")
                            .font(.callout)
                    }
                }
            }
        }
    }

    // MARK: Phases

    private var readyCard: some View {
        HStack(spacing: 12) {
            Button {
                startPreparing()
            } label: {
                Label("开始准备（30 秒）", systemImage: "timer")
            }
            .buttonStyle(.borderedProminent)
            Button {
                prepUsed = 0
                startSpeaking()
            } label: {
                Label("直接开始说", systemImage: "mic")
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }

    private var preparingCard: some View {
        PracticeCard {
            HStack(alignment: .firstTextBaseline) {
                Text("准备")
                    .font(.headline)
                Text(formatTime(prepLeft.rounded(.up)))
                    .font(.system(size: 44, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.accent)
                Spacer()
            }
            Text("想好三件事：回答是什么，为什么，举一个例子。")
                .foregroundStyle(.secondary)
            Button {
                prepTask?.cancel()
                prepUsed = SpeakingSessionView.prepSeconds - prepLeft
                startSpeaking()
            } label: {
                Label("准备好了，开始说", systemImage: "mic.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var speakingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            RecordingMeter(elapsed: recorder.elapsed, level: recorder.level,
                           limit: SpeakingSessionView.limit, target: SpeakingSessionView.target)
            Button {
                recorder.stop()
            } label: {
                Label("说完了", systemImage: "stop.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private var reviewSection: some View {
        if let id = workId, let work = practice.speaking(id) {
            PracticeCard {
                HStack {
                    Text("这次：\(String(format: "%.0f", work.speakSeconds)) 秒")
                        .font(.headline)
                    if !work.independent { Badge(text: "看过参考后", color: Theme.warn, outlined: true) }
                    if work.interrupted { Badge(text: "被打断", color: Theme.warn, outlined: true) }
                    Spacer()
                    Button {
                        if player.playing == .mine {
                            player.stop()
                        } else if let url = practice.recordingURL(work.file) {
                            engine.pause()
                            Task { await player.play(url, as: .mine) }
                        }
                    } label: {
                        Label(player.playing == .mine ? "停止" : "回放", systemImage: player.playing == .mine ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(practice.recordingURL(work.file) == nil)
                }
                if work.silent {
                    Text("只录到静音。看看麦克风有没有被挡住，再说一次。")
                        .foregroundStyle(Theme.warn)
                }
            }

            if let done = work.check {
                PracticeCard {
                    Text("我的自评").font(.headline)
                    SelfCheckSummary(dims: SelfCheckTemplate.speaking, check: done)
                }
                referenceCard
            } else if !work.silent {
                PracticeCard {
                    Text("先自评，再看参考").font(.headline)
                    Text("回放一遍自己的录音，逐项打勾，写下证据。这里不打分。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    SelfCheckForm(dims: SelfCheckTemplate.speaking, check: $check)
                    Button {
                        var submitted = check
                        submitted.created = Date()
                        practice.updateSpeaking(id) {
                            $0.check = submitted
                            $0.sawReference = true
                        }
                    } label: {
                        Label("提交自评，看参考", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            FeedbackList(items: work.feedback)

            HStack(spacing: 12) {
                Button {
                    resetForRetake()
                } label: {
                    Label("再说一次", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                Button {
                    showFeedback = true
                } label: {
                    Label("录入反馈", systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered)
                Button {
                    Clipboard.copy("IELTS Speaking (basic, about 45 seconds)\nQuestion: \(prompt.question)\n\nMy answer (typed from my recording):\n\nPlease give feedback on Fluency & Coherence, Lexical Resource, Grammatical Range & Accuracy and Pronunciation, with examples from my answer. No band score.")
                    message = "已复制题目和反馈要求。把你的回答打成文字贴在后面，再发给 Claude。"
                } label: {
                    Label("复制给 Claude", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var referenceCard: some View {
        PracticeCard {
            HStack {
                Text("参考思路").font(.headline)
                Spacer()
                Button {
                    Speaker.shared.speak(prompt.model, language: "en-GB")
                } label: {
                    Label("听参考（合成音）", systemImage: "speaker.wave.2")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            ForEach(prompt.outline, id: \.self) { line in
                Label(line, systemImage: "arrow.right.circle")
                    .font(.callout)
            }
            Text(prompt.model)
                .font(Font.system(.body, design: .serif))
                .lineSpacing(4)
                .textSelection(.enabled)
            Text("参考答案是 DayDayUp 原创的示范，只看结构和表达，不用背。再说一次时，会记为“看过参考后”。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: History

    @ViewBuilder
    private var history: some View {
        let works = practice.speakingWorks(prompt: prompt.id).filter { $0.id != workId }
        if !works.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("以前的回答（\(works.count)）").font(.headline)
                ForEach(works) { w in
                    HStack(spacing: 12) {
                        Button {
                            if let url = practice.recordingURL(w.file) {
                                engine.pause()
                                Task { await player.play(url, as: .mine) }
                            }
                        } label: {
                            Image(systemName: "play.circle")
                                .font(.title2)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .disabled(practice.recordingURL(w.file) == nil)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(w.created.formatted(date: .abbreviated, time: .shortened)).font(.callout)
                            Text("\(String(format: "%.0f", w.speakSeconds)) 秒 · \(w.independent ? "独立完成" : "看过参考后") · 反馈 \(w.feedback.count) 条")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if w.check != nil { Badge(text: "已自评", outlined: true) }
                    }
                    Divider()
                }
            }
        }
    }

    // MARK: Actions

    private func startPreparing() {
        message = nil
        prepLeft = SpeakingSessionView.prepSeconds
        phase = .preparing
        prepTask?.cancel()
        prepTask = Task {
            let started = Date()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if Task.isCancelled { return }
                let left = SpeakingSessionView.prepSeconds - Date().timeIntervalSince(started)
                prepLeft = max(0, left)
                if left <= 0 {
                    prepUsed = SpeakingSessionView.prepSeconds
                    startSpeaking()
                    return
                }
            }
        }
    }

    private func startSpeaking() {
        guard !recorder.isBusy else { return }
        player.stop()
        engine.pause()
        message = nil
        let url = practice.newRecordingURL()
        let prep = prepUsed
        let independent = !practice.referenceSeen(speakingPrompt: prompt.id)
        Task {
            let ok = await recorder.start(into: url, owner: "speaking", maxDuration: SpeakingSessionView.limit) { result in
                finishSpeaking(result, prep: prep, independent: independent)
            }
            if ok {
                phase = .speaking
            } else if !recorder.isBusy {
                phase = .ready
                message = recorder.denied ? "没有麦克风权限，录不了音。" : "录音没有启动，请再试一次。"
            }
        }
    }

    private func finishSpeaking(_ result: RecordingResult, prep: Double, independent: Bool) {
        let work = SpeakingWork(id: UUID().uuidString, promptId: prompt.id, question: prompt.question,
                                created: Date(), prepSeconds: prep, speakSeconds: result.seconds,
                                target: SpeakingSessionView.target, file: result.file, peakDb: result.peakDb,
                                silent: result.silent, interrupted: result.interrupted, independent: independent)
        practice.addSpeaking(work)
        workId = work.id
        check = SelfCheckTemplate.empty(SelfCheckTemplate.speaking)
        phase = .review
        if result.interrupted {
            message = "录音被打断，已保存 \(String(format: "%.0f", result.seconds)) 秒。"
        }
    }

    private func resetForRetake() {
        player.stop()
        workId = nil
        check = SelfCheckTemplate.empty(SelfCheckTemplate.speaking)
        message = nil
        prepUsed = 0
        phase = .ready
    }
}
