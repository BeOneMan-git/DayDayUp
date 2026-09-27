import SwiftUI
import UIKit

/// 口语完整模拟 (IEL-P03): Part 1 (8 questions from two topics), Part 2 (one cue card, 1 minute
/// to prepare) and Part 3 (5 discussion questions on the card's theme).
/// Each answer is its own recording (owner "mock"), saved as a SpeakingWork with part p1/p2/p3
/// and the mock id; the MockSession keeps the answer ids in order and the total time.
/// A recording interruption, leaving this page or sending the app to the background marks the
/// mock as interrupted: the answers stay saved, but it does not count as a complete mock.
/// The questions are a fixed offline bank; this is not the same as a live examiner.
struct MockTestView: View {
    @Environment(PracticeStore.self) private var practice
    @Environment(RecorderService.self) private var recorder
    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    private enum Stage {
        case intro, running, review
    }

    /// Where the current question is: shown, preparing (Part 2 only) or being answered.
    private enum Step {
        case question, preparing, recording
    }

    @State private var stage: Stage = .intro
    @State private var plan: MockTestPlan?
    @State private var index = 0
    @State private var step: Step = .question
    @State private var mockId: String?
    @State private var startedAt = Date()
    @State private var partStart: [String: Date] = [:]
    @State private var partEnd: [String: Date] = [:]
    @State private var interrupted = false
    @State private var prepLeft: Double = IELTSExamBank.timings.part2Prep
    @State private var prepUsed: Double = 0
    @State private var prepTask: Task<Void, Never>?
    @State private var notes = ""
    @State private var roundingShown = false
    @State private var lastSaved: String?
    @State private var reviewId: String?
    @State private var check = SelfCheckTemplate.empty(SelfCheckTemplate.mock)
    @State private var showFeedback = false
    @State private var confirmEnd = false
    @State private var message: String?
    @State private var player = SegmentPlayer()
    @State private var playingId: String?
    @State private var examinerSpeaking = false
    @State private var examinerToken = 0
    @State private var visible = false

    private static let owner = "mock"
    private static let parts = ["p1", "p2", "p3"]

    init() {}

    private var timings: IELTSExamTimings { IELTSExamBank.timings }

    private var currentItem: MockTestItem? {
        guard let plan, plan.items.indices.contains(index) else { return nil }
        return plan.items[index]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch stage {
                case .intro:
                    introSection
                case .running:
                    runningSection
                case .review:
                    reviewSection
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
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("口语完整模拟")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showFeedback) {
            FeedbackSheet { feedback in
                if let id = reviewId {
                    practice.updateMock(id) { $0.feedback.append(feedback) }
                }
            }
        }
        .alert("结束这次模拟？", isPresented: $confirmEnd) {
            Button("结束", role: .destructive) { endEarly() }
            Button("继续答题", role: .cancel) {}
        } message: {
            Text("已录的回答会保留，这次不算完整模拟。")
        }
        .onAppear {
            visible = true
            recorder.refreshPermission()
        }
        .onChange(of: recorder.elapsed) { _, value in
            // Part 2: at 2 minutes the examiner would stop the talk and ask the rounding-off question.
            guard stage == .running, step == .recording, recorder.owner == MockTestView.owner,
                  currentItem?.part == "p2", !roundingShown, value >= timings.part2TalkMax else { return }
            roundingShown = true
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && stage == .running {
                markInterrupted()
            }
        }
        .onDisappear {
            leave()
        }
    }

    // MARK: Intro

    @ViewBuilder
    private var introSection: some View {
        PracticeCard {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                Badge(text: "考试题型", color: Theme.accent)
                Badge(text: "口语完整模拟")
                Badge(text: "全程\(IELTSExamBank.minutesText(timings.mockMinutes))", outlined: true)
            }
            Label("离线固定题库，不能等同真人考官互动。", systemImage: "exclamationmark.bubble")
                .font(.callout.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                partLine("p1", "两个日常话题，共 8 题")
                partLine("p2", "一张题卡：准备 1 分钟，陈述 1–2 分钟")
                partLine("p3", "和题卡相关的讨论，共 5 题")
            }
            Text("每题单独录音。中途录音被打断、离开这一页或切到后台，这次就不算完整模拟；已录的回答都会保留。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("题目可以用系统合成音朗读（不是真人考官）。不给范文：做完先自评，再找老师或 Claude 反馈。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                start()
            } label: {
                Label("开始模拟", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        historySection
    }

    private func partLine(_ part: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(IELTSExamBank.partTitle(part))
                .font(.headline)
                .frame(width: 64, alignment: .leading)
            Text(detail)
            Spacer(minLength: 8)
            Text(IELTSExamBank.partGuide(part))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var historySection: some View {
        let mocks = practice.state.mocks.sorted { $0.created > $1.created }
        if !mocks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("以前的模拟（\(mocks.count)）").font(.headline)
                ForEach(mocks) { m in
                    historyRow(m)
                    Divider()
                }
            }
        }
    }

    private func historyRow(_ m: MockSession) -> some View {
        Button {
            openReview(m.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: m.isComplete ? "checkmark.seal" : "exclamationmark.triangle")
                    .font(.title3)
                    .foregroundStyle(m.isComplete ? Theme.accent : Theme.warn)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(m.created.formatted(date: .abbreviated, time: .shortened))
                            .font(.callout)
                        Badge(text: m.isComplete ? "完整" : "不完整",
                              color: m.isComplete ? Theme.accent : Theme.warn, outlined: true)
                    }
                    Text("回答 \(m.answers.count) 题 · 全程 \(formatTime(m.seconds)) · \(m.check == nil ? "未自评" : "已自评") · 反馈 \(m.feedback.count) 条")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Running

    @ViewBuilder
    private var runningSection: some View {
        if let plan {
            partTimeline(plan)
            if interrupted {
                interruptedBanner
            }
            if let item = currentItem {
                if item.part == "p2" {
                    part2Step(plan.card)
                } else {
                    questionStep(item, plan: plan)
                }
            }
            if let lastSaved {
                Label(lastSaved, systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button(role: .destructive) {
                confirmEnd = true
            } label: {
                Label("结束这次模拟", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    /// Time used in each part against the official guide, updated every second.
    private func partTimeline(_ plan: MockTestPlan) -> some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(MockTestView.parts, id: \.self) { part in
                        partChip(part, now: context.date)
                    }
                }
                Text("全程 \(formatTime(context.date.timeIntervalSince(startedAt)))（官方\(IELTSExamBank.minutesText(timings.mockMinutes))）")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func partChip(_ part: String, now: Date) -> some View {
        let isCurrent = currentItem?.part == part
        let state: String
        let icon: String
        if let s = partStart[part], let e = partEnd[part] {
            state = "已完成 \(formatTime(e.timeIntervalSince(s)))"
            icon = "checkmark.circle"
        } else if let s = partStart[part], isCurrent {
            state = "进行中 \(formatTime(now.timeIntervalSince(s)))"
            icon = "record.circle"
        } else {
            state = "未开始"
            icon = "circle"
        }
        return VStack(alignment: .leading, spacing: 2) {
            Label(IELTSExamBank.partTitle(part), systemImage: icon)
                .font(.subheadline.weight(.semibold))
            Text(state)
                .font(.callout.monospacedDigit())
            Text("官方\(IELTSExamBank.partGuide(part))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isCurrent ? Theme.accent.opacity(0.14) : Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isCurrent ? Theme.accent : Color.clear, lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }

    private var interruptedBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(Theme.warn)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("这次模拟被打断，不算完整模拟")
                    .font(.headline)
                Text("已录的回答都保存了。可以接着答完剩下的题（仍不算完整模拟），也可以结束这次模拟。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warn.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    /// Part 1 and Part 3: one question, the examiner's voice on request, one recording.
    private func questionStep(_ item: MockTestItem, plan: MockTestPlan) -> some View {
        let total = plan.items.filter { $0.part == item.part }.count
        let recording = step == .recording
        return VStack(alignment: .leading, spacing: 12) {
            PracticeCard {
                HStack(spacing: 8) {
                    Badge(text: IELTSExamBank.partTitle(item.part), color: Theme.accent)
                    Text("第 \(item.number)/\(total) 题")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                if item.number == 1 {
                    Text(item.part == "p1"
                         ? "Part 1：关于你自己和日常生活的短问题。每题说 2–3 句。"
                         : "Part 3：和刚才题卡“\(plan.card.topic)”相关的讨论。给观点、理由和例子。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text(item.question)
                    .font(Font.system(.title2, design: .serif).weight(.semibold))
                    .textSelection(.enabled)
                Button {
                    toggleExaminer(item.question)
                } label: {
                    Label(examinerSpeaking ? "停止朗读" : "考官提问（合成音）",
                          systemImage: examinerSpeaking ? "stop.fill" : "speaker.wave.2")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(recording)
            }
            if recording {
                RecordingMeter(elapsed: recorder.elapsed, level: recorder.level,
                               limit: limit(item), target: target(item))
                Button {
                    recorder.stop()
                } label: {
                    Label("答完了", systemImage: "stop.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            } else {
                Button {
                    record(item, prep: 0)
                } label: {
                    Label("开始回答", systemImage: "mic.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(recorder.isBusy)
                Text(item.part == "p1" ? "建议每题约 20–30 秒。" : "建议每题约 40–60 秒。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Part 2: the cue card, 1 minute to prepare with notes, then the talk.
    @ViewBuilder
    private func part2Step(_ card: CueCard) -> some View {
        HStack(spacing: 8) {
            Badge(text: "Part 2", color: Theme.accent)
            Text("准备 1 分钟 · 陈述 1–2 分钟")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        CueCardPanel(card: card)
        switch step {
        case .question:
            Text("点“开始准备”后计时 1 分钟，可以记笔记。准备好了可以提前开始说。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                startPrep()
            } label: {
                Label("开始准备（1 分钟）", systemImage: "timer")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(recorder.isBusy)
        case .preparing:
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
                Button {
                    beginTalkEarly()
                } label: {
                    Label("准备好了，开始说", systemImage: "mic.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        case .recording:
            Part2NotesView(notes: notes)
            RecordingMeter(elapsed: recorder.elapsed, level: recorder.level,
                           limit: timings.part2Limit, target: timings.part2TalkMax)
            if roundingShown {
                Part2RoundingCard(question: card.rounding)
                Button {
                    recorder.stop()
                } label: {
                    Label("结束录音", systemImage: "stop.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            } else {
                Part2TalkStatus(elapsed: recorder.elapsed)
                HStack(spacing: 12) {
                    Button {
                        roundingShown = true
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
            }
        }
    }

    // MARK: Review

    @ViewBuilder
    private var reviewSection: some View {
        if let id = reviewId, let mock = practice.mock(id) {
            let works = mock.answers.compactMap { practice.speaking($0) }
            summaryCard(mock, works: works)
            answersCard(works)
            checkCard(mock)
            Label("口语模拟不给范文。先自评，再找老师或 Claude 反馈。", systemImage: "person.2")
                .font(.callout)
                .foregroundStyle(.secondary)
            FeedbackList(items: mock.feedback)
            FlowLayout(spacing: 12, lineSpacing: 12) {
                Button {
                    showFeedback = true
                } label: {
                    Label("录入反馈", systemImage: "square.and.pencil")
                }
                Button {
                    Clipboard.copy(claudeText(mock, works: works))
                    message = "已复制全部题目和反馈要求。把每题的回答打成文字填进去，再发给 Claude。"
                } label: {
                    Label("复制给 Claude", systemImage: "doc.on.doc")
                }
                Button {
                    backToIntro()
                } label: {
                    Label("回到模拟首页", systemImage: "chevron.backward")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        } else {
            Text("找不到这次模拟的记录。")
                .foregroundStyle(.secondary)
            Button {
                backToIntro()
            } label: {
                Label("回到模拟首页", systemImage: "chevron.backward")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private func summaryCard(_ mock: MockSession, works: [SpeakingWork]) -> some View {
        PracticeCard {
            HStack(spacing: 8) {
                Label(mock.isComplete ? "完整模拟" : "不完整的模拟",
                      systemImage: mock.isComplete ? "checkmark.seal" : "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundStyle(mock.isComplete ? Theme.accent : Theme.warn)
                Spacer()
                Text(mock.created.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if mock.interrupted {
                Text("这次模拟被打断，不算完整模拟。录下的回答都保留了。")
                    .font(.callout)
            } else if mock.finished == nil {
                Text("这次模拟没有做完，不算完整模拟。录下的回答都保留了。")
                    .font(.callout)
            }
            Text("全程 \(formatTime(mock.seconds))（官方\(IELTSExamBank.minutesText(timings.mockMinutes))）· 回答 \(works.count) 题")
                .font(.callout.monospacedDigit())
            ForEach(MockTestView.parts, id: \.self) { part in
                partSummary(part, works: works)
            }
            Text("离线固定题库，不能等同真人考官互动。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func partSummary(_ part: String, works: [SpeakingWork]) -> some View {
        let answers = works.filter { $0.part == part }
        if !answers.isEmpty {
            let seconds = answers.reduce(0.0) { $0 + $1.prepSeconds + $1.speakSeconds }
            Text("\(IELTSExamBank.partTitle(part))：\(answers.count) 题 · 准备和回答共 \(formatTime(seconds)) · 官方\(IELTSExamBank.partGuide(part))")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func answersCard(_ works: [SpeakingWork]) -> some View {
        PracticeCard {
            Text("每题录音（\(works.count)）").font(.headline)
            if works.isEmpty {
                Text("这次没有录下回答。")
                    .foregroundStyle(.secondary)
            }
            ForEach(works) { w in
                answerRow(w)
                Divider()
            }
        }
    }

    private func answerRow(_ w: SpeakingWork) -> some View {
        let playingThis = playingId == w.id && player.playing == .mine
        return HStack(alignment: .top, spacing: 12) {
            Button {
                togglePlay(w)
            } label: {
                Image(systemName: playingThis ? "stop.circle" : "play.circle")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(practice.recordingURL(w.file) == nil || recorder.isRecording)
            .accessibilityLabel(playingThis ? "停止回放" : "回放这一题的录音")
            VStack(alignment: .leading, spacing: 4) {
                Text(w.question)
                    .font(Font.system(.body, design: .serif))
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    Text("\(IELTSExamBank.partTitle(w.part ?? "")) · \(formatTime(w.speakSeconds))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if w.interrupted { Badge(text: "被打断", color: Theme.warn, outlined: true) }
                    if w.silent { Badge(text: "只录到静音", color: Theme.warn, outlined: true) }
                }
                if let n = w.notes, !n.isEmpty {
                    Text("笔记：\(n)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func checkCard(_ mock: MockSession) -> some View {
        if let done = mock.check {
            PracticeCard {
                Text("我的自评").font(.headline)
                SelfCheckSummary(dims: SelfCheckTemplate.mock, check: done)
            }
        } else {
            PracticeCard {
                Text("整场自评").font(.headline)
                Text("回放几题录音，逐项打勾，写下证据。这里不打分。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                SelfCheckForm(dims: SelfCheckTemplate.mock, check: $check)
                Button {
                    var submitted = check
                    submitted.created = Date()
                    practice.updateMock(mock.id) { $0.check = submitted }
                } label: {
                    Label("提交自评", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    // MARK: Flow

    private func start() {
        guard !recorder.isBusy else {
            message = "录音正在进行，先结束那边的录音。"
            return
        }
        // Topics and cards already used in earlier mocks come last.
        let used = Set(practice.state.speaking.compactMap { w -> String? in
            guard w.mockId != nil else { return nil }
            return w.promptId.components(separatedBy: "#").first ?? w.promptId
        })
        guard let newPlan = MockTestPlan.make(used: used) else {
            message = "题库不完整，没法开始模拟。"
            return
        }
        stopPlayback()
        stopExaminer()
        let now = Date()
        plan = newPlan
        index = 0
        step = .question
        mockId = nil
        interrupted = false
        notes = ""
        prepUsed = 0
        prepLeft = timings.part2Prep
        roundingShown = false
        lastSaved = nil
        message = nil
        startedAt = now
        partStart = ["p1": now]
        partEnd = [:]
        stage = .running
    }

    private func startPrep() {
        guard let item = currentItem, item.part == "p2", !recorder.isBusy else { return }
        stopExaminer()
        stopPlayback()
        message = nil
        let total = timings.part2Prep
        prepLeft = total
        prepUsed = 0
        step = .preparing
        prepTask?.cancel()
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
                    record(item, prep: total)
                    return
                }
            }
        }
    }

    private func beginTalkEarly() {
        guard let item = currentItem else { return }
        prepTask?.cancel()
        prepTask = nil
        prepUsed = max(0, timings.part2Prep - prepLeft)
        record(item, prep: prepUsed)
    }

    private func record(_ item: MockTestItem, prep: Double) {
        guard !recorder.isBusy else { return }
        stopExaminer()
        stopPlayback()
        engine.pause()
        message = nil
        roundingShown = false
        let url = practice.newRecordingURL()
        let independent = examIndependent(item.id)
        Task {
            let ok = await recorder.start(into: url, owner: MockTestView.owner, maxDuration: limit(item)) { result in
                finishAnswer(result, item: item, prep: prep, independent: independent)
            }
            if ok {
                if visible && stage == .running {
                    step = .recording
                } else {
                    recorder.stop()      // the page closed while the microphone was starting
                }
            } else if !recorder.isBusy {
                step = .question
                message = recorder.denied ? "没有麦克风权限，录不了音。" : "录音没有启动，请再试一次。"
            }
        }
    }

    private func finishAnswer(_ result: RecordingResult, item: MockTestItem, prep: Double, independent: Bool) {
        let id = ensureMock()
        var work = SpeakingWork(id: UUID().uuidString, promptId: item.id, question: item.question,
                                created: Date(), prepSeconds: prep, speakSeconds: result.seconds,
                                target: target(item), file: result.file, peakDb: result.peakDb,
                                silent: result.silent, interrupted: result.interrupted, independent: independent)
        work.part = item.part
        work.mockId = id
        if item.part == "p2" {
            let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            work.notes = cleanNotes.isEmpty ? nil : cleanNotes
        }
        practice.addSpeaking(work)
        let workId = work.id
        let total = Date().timeIntervalSince(startedAt)
        practice.updateMock(id) { m in
            m.answers.append(workId)
            m.seconds = total
        }
        step = .question
        roundingShown = false
        var saved = "\(IELTSExamBank.partTitle(item.part)) 第 \(item.number) 题已保存（\(formatTime(result.seconds))）。"
        if result.silent {
            saved += "这一题只录到静音，看看麦克风有没有被挡住。"
        }
        lastSaved = saved
        if result.interrupted {
            markInterrupted()
        }
        advance(from: item)
    }

    /// Next question; moving into a new part closes the old one's clock.
    private func advance(from item: MockTestItem) {
        guard let plan else { return }
        let now = Date()
        let next = index + 1
        if plan.items.indices.contains(next) {
            let nextPart = plan.items[next].part
            if nextPart != item.part {
                partEnd[item.part] = now
                partStart[nextPart] = now
                if nextPart == "p3" { notes = "" }
            }
            index = next
        } else {
            partEnd[item.part] = now
            index = next
            finishMock(early: false)
        }
    }

    /// The MockSession is created with the first saved answer, so an empty start leaves nothing behind.
    private func ensureMock() -> String {
        if let mockId { return mockId }
        var m = MockSession(id: UUID().uuidString, created: startedAt)
        m.interrupted = interrupted
        practice.addMock(m)
        mockId = m.id
        return m.id
    }

    private func markInterrupted() {
        guard stage == .running else { return }
        interrupted = true
        if let id = mockId {
            practice.updateMock(id) { $0.interrupted = true }
        }
        if step == .preparing {
            // The Part 2 countdown cannot go on; the notes stay.
            prepTask?.cancel()
            prepTask = nil
            prepLeft = timings.part2Prep
            step = .question
        }
    }

    private func endEarly() {
        // Saves the answer in progress; on the last question that also finishes the mock.
        if recorder.owner == MockTestView.owner { recorder.stop() }
        guard stage == .running else { return }
        finishMock(early: true)
    }

    private func finishMock(early: Bool) {
        prepTask?.cancel()
        prepTask = nil
        stopExaminer()
        guard let id = mockId else {
            stage = .intro
            plan = nil
            message = "这次没有录下回答，没有保存。"
            return
        }
        let total = Date().timeIntervalSince(startedAt)
        let broken = interrupted
        practice.updateMock(id) { m in
            m.seconds = total
            if broken { m.interrupted = true }
            if !early { m.finished = Date() }
        }
        practice.saveNow()
        plan = nil
        openReview(id)
    }

    private func openReview(_ id: String) {
        stopPlayback()
        stopExaminer()
        reviewId = id
        check = SelfCheckTemplate.empty(SelfCheckTemplate.mock)
        message = nil
        stage = .review
    }

    private func backToIntro() {
        stopPlayback()
        reviewId = nil
        plan = nil
        message = nil
        stage = .intro
    }

    /// Leaving the page stops everything; a mock in progress no longer counts as complete.
    private func leave() {
        visible = false
        let wasRunning = stage == .running
        prepTask?.cancel()
        prepTask = nil
        stopPlayback()
        stopExaminer()
        // Saves the answer in progress (on the last question this also finishes the mock).
        if recorder.owner == MockTestView.owner { recorder.stop() }
        if wasRunning {
            if stage == .running {
                markInterrupted()
            } else if let id = mockId {
                // The last answer was cut short by leaving the page.
                interrupted = true
                practice.updateMock(id) { $0.interrupted = true }
            }
        }
        AudioSessionControl.usePlayback()
    }

    // MARK: Audio

    private func toggleExaminer(_ text: String) {
        if examinerSpeaking {
            stopExaminer()
            return
        }
        guard !recorder.isRecording else { return }
        stopPlayback()
        engine.pause()
        examinerToken += 1
        let token = examinerToken
        examinerSpeaking = true
        Task {
            await SpeechQueue.shared.speak(text, language: "en-GB")
            if token == examinerToken { examinerSpeaking = false }
        }
    }

    /// Stops the system voice only if this page started it.
    private func stopExaminer() {
        guard examinerSpeaking else { return }
        examinerToken += 1
        examinerSpeaking = false
        SpeechQueue.shared.stop()
    }

    private func togglePlay(_ w: SpeakingWork) {
        if playingId == w.id, player.playing == .mine {
            stopPlayback()
            return
        }
        guard !recorder.isRecording, let url = practice.recordingURL(w.file) else { return }
        stopExaminer()
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

    // MARK: Helpers

    private func target(_ item: MockTestItem) -> Double {
        switch item.part {
        case "p2": return timings.part2TalkMax
        case "p3": return timings.part3AnswerTarget
        default: return timings.part1AnswerTarget
        }
    }

    private func limit(_ item: MockTestItem) -> Double {
        switch item.part {
        case "p2": return timings.part2Limit
        case "p3": return timings.part3AnswerLimit
        default: return timings.part1AnswerLimit
        }
    }

    /// There is no reference answer; an answer counts as independent until this question
    /// has had feedback.
    private func examIndependent(_ promptId: String) -> Bool {
        !practice.speakingWorks(prompt: promptId).contains { $0.sawReference || !$0.feedback.isEmpty }
    }

    private func claudeText(_ mock: MockSession, works: [SpeakingWork]) -> String {
        var lines = ["IELTS Speaking mock test (offline practice with fixed questions, not a live examiner)"]
        lines.append(mock.isComplete ? "Status: complete" : "Status: not complete (interrupted or ended early)")
        lines.append("Total time: \(formatTime(mock.seconds))")
        for part in MockTestView.parts {
            let answers = works.filter { $0.part == part }
            guard !answers.isEmpty else { continue }
            lines.append("")
            lines.append(IELTSExamBank.partTitle(part))
            for (i, w) in answers.enumerated() {
                lines.append("\(i + 1). \(w.question) [\(formatTime(w.speakSeconds))]")
                if part == "p2", let card = IELTSExamBank.cueCard(w.promptId) {
                    lines.append("   You should say: " + card.bullets.joined(separator: "; "))
                    if let n = w.notes, !n.isEmpty {
                        lines.append("   My notes: \(n)")
                    }
                }
                lines.append("   My answer (typed from my recording): ")
            }
        }
        lines.append("")
        lines.append("Please give feedback on Fluency & Coherence, Lexical Resource, Grammatical Range & Accuracy and Pronunciation, with examples from my answers. Name the three most important problems and how to fix them. No band score.")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Plan

/// One question in a mock.
private struct MockTestItem: Identifiable, Equatable {
    let id: String          // SpeakingWork.promptId: "p1-home#2", the cue card id, "p3-skill#4"
    let part: String        // "p1", "p2", "p3"
    let question: String
    let number: Int         // 1-based within its part
}

/// The questions of one mock, fixed when it starts.
private struct MockTestPlan {
    let card: CueCard
    let items: [MockTestItem]

    /// Two Part 1 topics, one cue card and its Part 3 questions.
    /// Topics and cards not used in earlier mocks are picked first.
    static func make(used: Set<String>) -> MockTestPlan? {
        let sets = IELTSExamBank.part1Sets
        let freshSets = sets.filter { !used.contains($0.id) }
        let part1 = Array((freshSets.count >= 2 ? freshSets : sets).shuffled().prefix(2))
        let cards = IELTSExamBank.cueCards.filter { IELTSExamBank.part3(for: $0.id) != nil }
        let freshCards = cards.filter { !used.contains($0.id) }
        guard part1.count == 2,
              let card = (freshCards.isEmpty ? cards : freshCards).randomElement(),
              let part3 = IELTSExamBank.part3(for: card.id) else { return nil }
        var items: [MockTestItem] = []
        var number = 0
        for topicSet in part1 {
            for (i, question) in topicSet.questions.enumerated() {
                number += 1
                items.append(MockTestItem(id: topicSet.questionId(i), part: "p1", question: question, number: number))
            }
        }
        items.append(MockTestItem(id: card.id, part: "p2", question: card.title, number: 1))
        for (i, question) in part3.questions.enumerated() {
            items.append(MockTestItem(id: part3.questionId(i), part: "p3", question: question, number: i + 1))
        }
        return MockTestPlan(card: card, items: items)
    }
}
