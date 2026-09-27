import SwiftUI
import UIKit

/// 口语 Part 2 单题 (IEL-P04): 1 minute to prepare with notes, then a 1–2 minute talk.
/// The learner may start early. After 1 minute the page says it is fine to go on to 2 minutes;
/// after 2 minutes the meter turns orange but the take goes on (the real time is kept, at most
/// 3 minutes). The rounding-off question can be answered in the same recording or skipped.
/// Saved as a SpeakingWork with part "p2" and the notes. No model answer: self-check, then feedback.
struct Part2SessionView: View {
    let card: CueCard

    @Environment(PracticeStore.self) private var practice
    @Environment(RecorderService.self) private var recorder
    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    private enum Phase {
        case ready, preparing, speaking, review
    }

    @State private var phase: Phase = .ready
    @State private var prepLeft: Double = IELTSExamBank.timings.part2Prep
    @State private var prepUsed: Double = 0
    @State private var prepTask: Task<Void, Never>?
    @State private var notes = ""
    @State private var roundingAt: Double?       // talk time when the rounding-off question appeared
    @State private var talkSeconds: Double?      // the talk before the rounding-off question
    @State private var workId: String?
    @State private var check = SelfCheckTemplate.empty(SelfCheckTemplate.part2)
    @State private var showFeedback = false
    @State private var message: String?
    @State private var player = SegmentPlayer()
    @State private var playingId: String?
    @State private var visible = false

    private static let owner = "part2"

    init(card: CueCard) {
        self.card = card
    }

    private var timings: IELTSExamTimings { IELTSExamBank.timings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                CueCardPanel(card: card)
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
        .navigationTitle("口语 Part 2")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showFeedback) {
            FeedbackSheet { feedback in
                if let id = workId {
                    practice.updateSpeaking(id) { $0.feedback.append(feedback) }
                }
            }
        }
        .onAppear {
            visible = true
            recorder.refreshPermission()
        }
        .onChange(of: recorder.elapsed) { _, value in
            // At 2 minutes the examiner would stop the talk: show the rounding-off question.
            guard phase == .speaking, recorder.owner == Part2SessionView.owner,
                  roundingAt == nil, value >= timings.part2TalkMax else { return }
            showRounding(at: value)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // A countdown cannot go on in the background; the notes stay.
            if newPhase == .background, phase == .preparing {
                prepTask?.cancel()
                prepTask = nil
                phase = .ready
                message = "准备被打断了，笔记还在。可以重新开始准备。"
            }
        }
        .onDisappear {
            visible = false
            prepTask?.cancel()
            prepTask = nil
            if phase == .preparing { phase = .ready }
            player.stop()
            playingId = nil
            if recorder.owner == Part2SessionView.owner { recorder.stop() }
            AudioSessionControl.usePlayback()
        }
    }

    // MARK: Header

    private var header: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            Badge(text: "考试题型", color: Theme.accent)
            Badge(text: "Part 2 单题")
            Badge(text: "准备 1 分钟 · 陈述 1–2 分钟", outlined: true)
        }
    }

    // MARK: Phases

    private var readyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("点“开始准备”后计时 1 分钟，可以在笔记里写关键词。准备好了可以提前开始说。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                startPreparing()
            } label: {
                Label("开始准备（1 分钟）", systemImage: "timer")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
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
            .accessibilityElement(children: .combine)
            Part2NotesEditor(notes: $notes)
            Text("笔记只写关键词。说的时候可以看笔记。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                beginTalkEarly()
            } label: {
                Label("准备好了，开始说", systemImage: "mic.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var speakingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Part2NotesView(notes: notes)
            RecordingMeter(elapsed: recorder.elapsed, level: recorder.level,
                           limit: timings.part2Limit, target: timings.part2TalkMax)
            if roundingAt == nil {
                Part2TalkStatus(elapsed: recorder.elapsed)
                FlowLayout(spacing: 12, lineSpacing: 12) {
                    Button {
                        showRounding(at: recorder.elapsed)
                    } label: {
                        Label("陈述说完了", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        recorder.stop()
                    } label: {
                        Label("结束录音", systemImage: "stop.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .controlSize(.large)
            } else {
                Part2RoundingCard(question: card.rounding)
                Button {
                    recorder.stop()
                } label: {
                    Label("结束录音", systemImage: "stop.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            }
        }
    }

    @ViewBuilder
    private var reviewSection: some View {
        if let id = workId, let work = practice.speaking(id) {
            PracticeCard {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    Text(timeLine(work))
                        .font(.headline.monospacedDigit())
                    if work.interrupted { Badge(text: "被打断", color: Theme.warn, outlined: true) }
                    playButton(work)
                }
                if let talk = talkSeconds, talk < timings.part2TalkMin, !work.silent {
                    Label("这次陈述不到 1 分钟。考试要求说 1–2 分钟。", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(Theme.warn)
                }
                if work.silent {
                    Text("只录到静音。看看麦克风有没有被挡住，再说一次。")
                        .foregroundStyle(Theme.warn)
                }
            }

            if let savedNotes = work.notes, !savedNotes.isEmpty {
                PracticeCard {
                    Text("准备笔记").font(.headline)
                    Text(savedNotes)
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }

            if let done = work.check {
                PracticeCard {
                    Text("我的自评").font(.headline)
                    SelfCheckSummary(dims: SelfCheckTemplate.part2, check: done)
                }
            } else if !work.silent {
                PracticeCard {
                    Text("先自评").font(.headline)
                    Text("回放一遍自己的录音，逐项打勾，写下证据。这里不打分。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    SelfCheckForm(dims: SelfCheckTemplate.part2, check: $check)
                    Button {
                        var submitted = check
                        submitted.created = Date()
                        practice.updateSpeaking(id) { $0.check = submitted }
                    } label: {
                        Label("提交自评", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }

            Label("Part 2 不给范文，先自评，再找老师或 Claude 反馈。", systemImage: "person.2")
                .font(.callout)
                .foregroundStyle(.secondary)

            FeedbackList(items: work.feedback)

            FlowLayout(spacing: 12, lineSpacing: 12) {
                Button {
                    resetForRetake()
                } label: {
                    Label("再说一次", systemImage: "arrow.counterclockwise")
                }
                Button {
                    showFeedback = true
                } label: {
                    Label("录入反馈", systemImage: "square.and.pencil")
                }
                Button {
                    Clipboard.copy(claudeText(work))
                    message = "已复制题卡和反馈要求。把你的回答打成文字贴在后面，再发给 Claude。"
                } label: {
                    Label("复制给 Claude", systemImage: "doc.on.doc")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private func playButton(_ work: SpeakingWork) -> some View {
        let playingThis = playingId == work.id && player.playing == .mine
        return Button {
            togglePlay(work)
        } label: {
            Label(playingThis ? "停止" : "回放", systemImage: playingThis ? "stop.fill" : "play.fill")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(practice.recordingURL(work.file) == nil || recorder.isRecording)
    }

    private func timeLine(_ work: SpeakingWork) -> String {
        if let talk = talkSeconds, talk < work.speakSeconds - 1 {
            return "陈述 \(formatTime(talk)) · 录音共 \(formatTime(work.speakSeconds))"
        }
        return "录音 \(formatTime(work.speakSeconds))"
    }

    // MARK: History

    @ViewBuilder
    private var history: some View {
        let works = practice.speakingWorks(prompt: card.id).filter { $0.id != workId }
        if !works.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("这张题卡以前的回答（\(works.count)）").font(.headline)
                ForEach(works) { w in
                    historyRow(w)
                    Divider()
                }
            }
        }
    }

    private func historyRow(_ w: SpeakingWork) -> some View {
        let playingThis = playingId == w.id && player.playing == .mine
        return HStack(alignment: .top, spacing: 12) {
            Button {
                togglePlay(w)
            } label: {
                Image(systemName: playingThis ? "stop.circle" : "play.circle")
                    .font(.title2)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(practice.recordingURL(w.file) == nil || recorder.isRecording)
            .accessibilityLabel(playingThis ? "停止回放" : "回放这次录音")
            VStack(alignment: .leading, spacing: 4) {
                Text(w.created.formatted(date: .abbreviated, time: .shortened)).font(.callout)
                Text("准备 \(formatTime(w.prepSeconds)) · 录音 \(formatTime(w.speakSeconds)) · \(w.independent ? "独立完成" : "看过反馈后") · 反馈 \(w.feedback.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                RecordingGoneBadge(file: w.file)
                if let n = w.notes, !n.isEmpty {
                    DisclosureGroup {
                        Text(n)
                            .font(.caption)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Text("准备笔记")
                            .frame(minHeight: 44)
                    }
                    .font(.caption)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if w.mockId != nil { Badge(text: "模拟中", outlined: true) }
                if w.check != nil { Badge(text: "已自评", outlined: true) }
                if w.interrupted { Badge(text: "被打断", color: Theme.warn, outlined: true) }
            }
        }
    }

    // MARK: Actions

    private func startPreparing() {
        message = nil
        stopPlayback()
        prepUsed = 0
        prepLeft = timings.part2Prep
        roundingAt = nil
        talkSeconds = nil
        phase = .preparing
        prepTask?.cancel()
        let total = timings.part2Prep
        prepTask = Task {
            let started = Date()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if Task.isCancelled { return }
                let left = total - Date().timeIntervalSince(started)
                prepLeft = max(0, left)
                if left <= 0 {
                    prepUsed = total
                    prepTask = nil
                    startSpeaking()
                    return
                }
            }
        }
    }

    private func beginTalkEarly() {
        prepTask?.cancel()
        prepTask = nil
        prepUsed = max(0, timings.part2Prep - prepLeft)
        startSpeaking()
    }

    private func startSpeaking() {
        guard !recorder.isBusy else { return }
        stopPlayback()
        engine.pause()
        message = nil
        roundingAt = nil
        talkSeconds = nil
        let url = practice.newRecordingURL()
        let prep = prepUsed
        let independent = examIndependent
        Task {
            let ok = await recorder.start(into: url, owner: Part2SessionView.owner, maxDuration: timings.part2Limit) { result in
                finishSpeaking(result, prep: prep, independent: independent)
            }
            if ok {
                if visible {
                    phase = .speaking
                } else {
                    recorder.stop()      // the page closed while the microphone was starting
                }
            } else if !recorder.isBusy {
                phase = .ready
                message = recorder.denied ? "没有麦克风权限，录不了音。" : "录音没有启动，请再试一次。"
            }
        }
    }

    private func showRounding(at seconds: Double) {
        roundingAt = seconds
    }

    private func finishSpeaking(_ result: RecordingResult, prep: Double, independent: Bool) {
        var work = SpeakingWork(id: UUID().uuidString, promptId: card.id, question: card.title,
                                created: Date(), prepSeconds: prep, speakSeconds: result.seconds,
                                target: timings.part2TalkMax, file: result.file, peakDb: result.peakDb,
                                silent: result.silent, interrupted: result.interrupted, independent: independent)
        work.part = "p2"
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        work.notes = cleanNotes.isEmpty ? nil : cleanNotes
        practice.addSpeaking(work)
        workId = work.id
        talkSeconds = min(roundingAt ?? result.seconds, result.seconds)
        check = SelfCheckTemplate.empty(SelfCheckTemplate.part2)
        phase = .review
        if result.interrupted {
            message = "录音被打断，已保存 \(formatTime(result.seconds))。"
        }
    }

    private func resetForRetake() {
        stopPlayback()
        workId = nil
        check = SelfCheckTemplate.empty(SelfCheckTemplate.part2)
        message = nil
        prepUsed = 0
        prepLeft = timings.part2Prep
        notes = ""
        roundingAt = nil
        talkSeconds = nil
        phase = .ready
    }

    private func togglePlay(_ w: SpeakingWork) {
        if playingId == w.id, player.playing == .mine {
            stopPlayback()
            return
        }
        guard !recorder.isRecording, let url = practice.recordingURL(w.file) else { return }
        engine.pause()
        playingId = w.id
        let id = w.id
        Task {
            await player.play(url, as: .mine)
            if playingId == id { playingId = nil }
        }
    }

    private func stopPlayback() {
        player.stop()
        playingId = nil
    }

    /// No reference answer exists for Part 2; a take counts as independent until the learner
    /// has had feedback on this card.
    private var examIndependent: Bool {
        !practice.speakingWorks(prompt: card.id).contains { $0.sawReference || !$0.feedback.isEmpty }
    }

    private func claudeText(_ work: SpeakingWork) -> String {
        var lines = ["IELTS Speaking Part 2 (practice)",
                     "Cue card: \(card.title)",
                     "You should say:"]
        lines += card.bullets.map { "- \($0)" }
        lines.append("Rounding-off question: \(card.rounding)")
        lines.append("")
        lines.append("Preparation: \(formatTime(work.prepSeconds)). Recording: \(formatTime(work.speakSeconds)) (the talk should last 1–2 minutes).")
        if let n = work.notes, !n.isEmpty {
            lines.append("My notes: \(n)")
        }
        lines.append("")
        lines.append("My answer (typed from my recording):")
        lines.append("")
        lines.append("")
        lines.append("Please give feedback on Fluency & Coherence, Lexical Resource, Grammatical Range & Accuracy and Pronunciation, with examples from my answer. Tell me whether I covered every point on the card. No band score.")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Shared with the speaking mock

/// The cue card: topic, "Describe …" and the "You should say:" points.
struct CueCardPanel: View {
    let card: CueCard

    var body: some View {
        PracticeCard {
            HStack(spacing: 8) {
                Badge(text: card.topic)
                Spacer()
            }
            Text(card.title)
                .font(Font.system(.title2, design: .serif).weight(.semibold))
                .textSelection(.enabled)
            Text("You should say:")
                .font(Font.system(.body, design: .serif).italic())
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(card.bullets.enumerated()), id: \.offset) { _, bullet in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .accessibilityHidden(true)
                        Text(bullet)
                            .textSelection(.enabled)
                    }
                    .font(Font.system(.body, design: .serif))
                }
            }
        }
    }
}

/// Notes during the 1-minute preparation.
struct Part2NotesEditor: View {
    @Binding var notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("笔记")
                .font(.subheadline.weight(.semibold))
            TextEditor(text: $notes)
                .font(.body)
                .frame(minHeight: 140)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.3)))
                .accessibilityLabel("准备笔记")
        }
    }
}

/// The notes, read-only, while the learner talks.
struct Part2NotesView: View {
    let notes: String

    var body: some View {
        let clean = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("我的笔记")
                    .font(.subheadline.weight(.semibold))
                Text(clean)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

/// What to do now in a 1–2 minute talk: icon and words, not colour alone.
struct Part2TalkStatus: View {
    let elapsed: Double

    var body: some View {
        let t = IELTSExamBank.timings
        Group {
            if elapsed >= t.part2TalkMax {
                Label("已到 2 分钟。考试时考官会在这里请你停下；说完这句就可以停。", systemImage: "exclamationmark.circle")
                    .foregroundStyle(Theme.warn)
            } else if elapsed >= t.part2TalkMin {
                Label("已过 1 分钟，可以继续到 2 分钟。", systemImage: "checkmark.circle")
            } else {
                Label("先说满 1 分钟。", systemImage: "hourglass")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }
}

/// The rounding-off question, answered in the same recording or skipped.
struct Part2RoundingCard: View {
    let question: String

    var body: some View {
        PracticeCard {
            Label("考官追问（可答可跳过）", systemImage: "questionmark.bubble")
                .font(.headline)
            Text(question)
                .font(Font.system(.title3, design: .serif).weight(.semibold))
                .textSelection(.enabled)
            Text("在这段录音里直接回答一两句，再点“结束录音”。不想答，直接点“结束录音”。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
