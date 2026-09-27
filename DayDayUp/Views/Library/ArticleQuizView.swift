import SwiftUI

/// 理解题 (PLAN-P04, DIAG-01): comprehension questions from the content pack, one per screen. Shown in a sheet.
/// - "delayed" 隔日回忆: 3 questions from memory; no audio, no text.
/// - "weekly" 新材料复测 and "baseline" 短听读: a listening check. One short passage is played (one extra play is
///   allowed and counted), the learner says roughly how much was understood, then answers the questions that the
///   passage alone can answer.
/// - "practice": all questions; the passage can be played and the text can be read.
/// The result is saved once, on 提交 (`study.addQuizResult`), then `onDone` is called once. Closing earlier saves
/// nothing. Answers are described ("答对 3 / 5"), never turned into a score or a band.
struct ArticleQuizView: View {
    let ref: ArticleRef
    let purpose: String
    let onDone: ((QuizResult) -> Void)?

    init(ref: ArticleRef, purpose: String, onDone: ((QuizResult) -> Void)? = nil) {
        self.ref = ref
        self.purpose = purpose
        self.onDone = onDone
    }

    @Environment(PackStore.self) private var packs
    @Environment(StudyStore.self) private var study
    @Environment(Router.self) private var router
    @Environment(ReadingSession.self) private var session
    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    @State private var setup = Setup()
    @State private var stage: Stage = .intro
    @State private var index = 0
    @State private var answers: [Int?] = []
    @State private var showZh = true
    @State private var player = SegmentPlayer()
    @State private var segmentBusy = false
    @State private var stopRequested = false
    @State private var plays = 0
    @State private var playFailed = false
    @State private var understood: String?
    @State private var started: Date?
    @State private var result: QuizResult?
    @State private var confirmClose = false

    private enum Stage: Equatable {
        case intro, listen, selfReport, question, result
    }

    private enum Availability: Equatable {
        case loading, missing, empty, ready
    }

    private struct Segment: Equatable {
        var start: Double
        var end: Double
        var seconds: Int { Int((end - start).rounded()) }
    }

    /// What this run uses, decided once when the sheet opens.
    private struct Setup: Equatable {
        var availability: Availability = .loading
        var title = ""
        var questions: [QuizQuestion] = []
        var segment: Segment? = nil
        var audio: URL? = nil
        /// Listening check without a playable passage: why (shown in the intro and kept in the record).
        var noAudioReason: String? = nil
        var noAudioNote: String? = nil
    }

    private static let maxPlays = 2
    private static let understandingLevels = ["大部分", "一半左右", "很少"]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(purposeTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { close() }
                    }
                }
        }
        .interactiveDismissDisabled(hasUnsavedAnswers)
        .alert("现在关闭？", isPresented: $confirmClose) {
            Button("关闭，不保存", role: .destructive) {
                stopPlayback()
                dismiss()
            }
            Button("继续答题", role: .cancel) {}
        } message: {
            Text("已经答了 \(answeredCount) 题。现在关闭，这次答题不会保存。")
        }
        .task { load() }
        .onDisappear { player.stop() }
    }

    @ViewBuilder
    private var content: some View {
        switch setup.availability {
        case .loading:
            ProgressView()
        case .missing:
            missingView
        case .empty:
            emptyView
        case .ready:
            readyView
        }
    }

    private var readyView: some View {
        ScrollView {
            stageView
                .frame(maxWidth: 680, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if stage == .question {
                questionBar
            }
        }
    }

    @ViewBuilder
    private var stageView: some View {
        switch stage {
        case .intro:
            introView
        case .listen:
            listenView
        case .selfReport:
            selfReportView
        case .question:
            questionView
        case .result:
            resultView
        }
    }

    // MARK: Facts

    private var isListeningCheck: Bool { purpose == "weekly" || purpose == "baseline" }

    /// "看原句" after submitting: practice, next-day recall and the weekly check (not the baseline).
    private var allowsSource: Bool { purpose == "practice" || purpose == "delayed" || purpose == "weekly" }

    private var canPlaySegment: Bool { setup.segment != nil && setup.audio != nil }

    private var answeredCount: Int { answers.filter { $0 != nil }.count }

    private var hasUnsavedAnswers: Bool { result == nil && answeredCount > 0 }

    private var allAnswered: Bool { !answers.isEmpty && answers.allSatisfy { $0 != nil } }

    private var purposeTitle: String {
        switch purpose {
        case "delayed": return "隔日回忆"
        case "weekly": return "新材料复测"
        case "baseline": return "基线：短听读"
        default: return "理解题"
        }
    }

    // MARK: Loading

    private func load() {
        guard setup.availability == .loading else { return }
        let s = ArticleQuizView.makeSetup(ref: ref, purpose: purpose, packs: packs)
        answers = Array(repeating: nil, count: s.questions.count)
        setup = s
    }

    private static func makeSetup(ref: ArticleRef, purpose: String, packs: PackStore) -> Setup {
        var s = Setup()
        s.title = packs.item(ref)?.meta.title ?? ref.id
        let res = packs.resources(ref)
        guard res.quiz == .available, let file = packs.quizFile(ref) else {
            s.availability = .missing
            return s
        }
        // A question needs its right answer among the options; anything else is skipped, not shown broken.
        let usable = file.questions.filter { $0.options.count >= 2 && $0.options.indices.contains($0.answer) }
        var segment: Segment? = nil
        if let seg = file.segment, seg.count >= 2, seg[0] >= 0, seg[1] > seg[0] {
            segment = Segment(start: seg[0], end: seg[1])
        }
        let url: URL? = res.audio == .available ? packs.audioURL(ref) : nil
        let notWord = usable.filter { $0.kind != "word" }
        switch purpose {
        case "delayed":
            s.questions = recallQuestions(usable)
        case "weekly", "baseline":
            if let segment, let url {
                s.segment = segment
                s.audio = url
                let inSegment = usable.filter { $0.inSegment == true }
                s.questions = Array((inSegment.isEmpty ? notWord : inSegment).prefix(5))
            } else {
                if segment == nil {
                    s.noAudioReason = "这篇的题目没有标出可以单独听的一小段，所以这次不放音频。"
                    s.noAudioNote = "没有播放：题目里没有标出短段"
                } else {
                    s.noAudioReason = "这篇的原音文件缺失，放不了音频。"
                    s.noAudioNote = "没有播放：原音缺失"
                }
                s.questions = Array(notWord.prefix(5))
            }
        default:
            s.questions = usable
            if let segment, let url {
                s.segment = segment
                s.audio = url
            }
        }
        s.availability = s.questions.isEmpty ? .empty : .ready
        return s
    }

    /// Next-day recall: the first "main", "detail" and "inference" question; a missing kind is filled with
    /// another question that is not about a word. File order is kept.
    private static func recallQuestions(_ all: [QuizQuestion]) -> [QuizQuestion] {
        var picked: [Int] = []
        for kind in ["main", "detail", "inference"] {
            if let i = all.firstIndex(where: { $0.kind == kind }) { picked.append(i) }
        }
        for (i, q) in all.enumerated() {
            if picked.count >= 3 { break }
            if q.kind != "word" && !picked.contains(i) { picked.append(i) }
        }
        return picked.sorted().map { all[$0] }
    }

    // MARK: Intro

    private var introView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(setup.title)
                .font(Font.system(.title2, design: .serif).weight(.semibold))
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(introLines.enumerated()), id: \.offset) { _, line in
                    Label(line, systemImage: "info.circle")
                        .font(.body)
                }
            }
            Button {
                begin()
            } label: {
                Label("开始", systemImage: "play.fill")
                    .frame(minWidth: 120, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            if purpose == "practice" {
                textLink
            }
        }
    }

    private var introLines: [String] {
        let n = setup.questions.count
        let save = "答完点“提交”才保存；中途关闭不保存。"
        switch purpose {
        case "delayed":
            return ["凭记忆回答 \(n) 题。不重听，不看原文。", save]
        case "weekly", "baseline":
            if let seg = setup.segment, setup.audio != nil {
                return ["先只听一小段（约 \(seg.seconds) 秒），不看原文。听完再答题。",
                        "默认听 1 次；需要的话可以再听 1 次，次数会记下来。",
                        "然后说说大概听懂了多少，再答 \(n) 题。", save]
            }
            return [setup.noAudioReason ?? "这次不放音频。", "直接答 \(n) 题，结果只作参考。", save]
        default:
            var lines = ["共 \(n) 题。可以看原文。"]
            if canPlaySegment { lines.append("答题页有“听这一段”，可以反复听。") }
            lines.append("提交后显示正确答案和解释，还可以跳到原句。")
            lines.append(save)
            return lines
        }
    }

    private func begin() {
        started = Date()
        ActivityClock.shared.touch(.read, source: "quiz")
        // A check starts in silence: the reader's audio stops.
        if purpose != "practice" { engine.pause() }
        stage = isListeningCheck && canPlaySegment ? .listen : .question
    }

    // MARK: Listening check

    private var listenView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("听一小段")
                .font(.title2.weight(.semibold))
            Text("约 \(setup.segment?.seconds ?? 0) 秒。不看原文，只听。")
                .foregroundStyle(.secondary)
            listenControls
            Text(playsNote)
                .font(.callout)
                .foregroundStyle(.secondary)
            if playFailed {
                Label("音频没有放出来。可以再点一次“播放”。", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.warn)
            }
            if !segmentBusy && (plays > 0 || playFailed) {
                Button {
                    stage = .selfReport
                } label: {
                    Label("听完了，去答题", systemImage: "arrow.right")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private var listenControls: some View {
        if segmentBusy {
            HStack(spacing: 12) {
                Button {
                    stopPlayback()
                } label: {
                    Label("停止", systemImage: "stop.fill")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                Label("正在播放…", systemImage: "speaker.wave.2")
                    .foregroundStyle(.secondary)
            }
        } else if plays == 0 {
            Button {
                playSegment()
            } label: {
                Label("播放", systemImage: "play.fill")
                    .frame(minWidth: 120, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        } else if plays < ArticleQuizView.maxPlays {
            Button {
                playSegment()
            } label: {
                Label("再听一次", systemImage: "arrow.counterclockwise")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
    }

    private var playsNote: String {
        switch plays {
        case 0: return "默认听 1 次；需要的话可以再听 1 次。"
        case 1: return "已播放 1 次。还可以再听 1 次。"
        default: return "已播放 \(plays) 次。"
        }
    }

    private var selfReportView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("你大概听懂了多少？")
                .font(.title2.weight(.semibold))
            Text("凭感觉选一个。只作记录，不影响答题。")
                .foregroundStyle(.secondary)
            VStack(spacing: 10) {
                ForEach(ArticleQuizView.understandingLevels, id: \.self) { level in
                    choiceButton(level, selected: understood == level) {
                        understood = level
                        ActivityClock.shared.touch(.read, source: "quiz")
                    }
                }
            }
            Button {
                stage = .question
            } label: {
                Label("开始答题", systemImage: "arrow.right")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(understood == nil)
        }
    }

    // MARK: Audio

    private func playSegment() {
        guard !segmentBusy, let seg = setup.segment, let url = setup.audio else { return }
        if isListeningCheck && plays >= ArticleQuizView.maxPlays { return }
        segmentBusy = true
        stopRequested = false
        playFailed = false
        engine.pause()
        AudioSessionControl.usePlayback()
        let began = Date()
        ActivityClock.shared.touch(.read, source: "quiz")
        Task {
            let reached = await player.play(url, from: seg.start, to: seg.end, as: .original)
            ActivityClock.shared.touch(.read, from: began, source: "quiz")
            // A play that ended at once without a stop did not really play (file unreadable, interruption).
            if reached || stopRequested || Date().timeIntervalSince(began) >= 1.5 {
                plays += 1
            } else {
                playFailed = true
            }
            stopRequested = false
            segmentBusy = false
        }
    }

    private func stopPlayback() {
        if segmentBusy { stopRequested = true }
        player.stop()
    }

    // MARK: Questions

    @ViewBuilder
    private var questionView: some View {
        if setup.questions.indices.contains(index) {
            questionCard(setup.questions[index])
        }
    }

    private func questionCard(_ q: QuizQuestion) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                Text("第 \(index + 1) / \(setup.questions.count) 题")
                    .font(.headline)
                Spacer()
                zhButton
            }
            Text(q.q)
                .font(Font.system(.title3, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
            if showZh, let zh = q.zh, !zh.isEmpty {
                Text(zh)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 10) {
                ForEach(Array(q.options.enumerated()), id: \.offset) { i, option in
                    choiceButton(ArticleQuizView.letter(i) + ". " + option, selected: isChosen(i)) {
                        choose(i)
                    }
                }
            }
            if purpose == "practice" {
                practiceTools
            }
        }
    }

    private var zhButton: some View {
        Button {
            showZh.toggle()
        } label: {
            Label(showZh ? "中文：开" : "中文：关", systemImage: showZh ? "character.bubble.fill" : "character.bubble")
                .font(.callout)
                .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(showZh ? "中文提示已打开" : "中文提示已关闭")
        .accessibilityHint("点一下切换题目下面的中文")
    }

    @ViewBuilder
    private var practiceTools: some View {
        HStack(spacing: 12) {
            if canPlaySegment {
                if segmentBusy {
                    Button {
                        stopPlayback()
                    } label: {
                        Label("停止", systemImage: "stop.fill")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        playSegment()
                    } label: {
                        Label("听这一段", systemImage: "headphones")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
            }
            textLink
        }
    }

    private var textLink: some View {
        NavigationLink {
            QuizArticleTextView(ref: ref)
        } label: {
            Label("看原文", systemImage: "doc.text")
                .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
    }

    private var questionBar: some View {
        let last = index >= setup.questions.count - 1
        return HStack(spacing: 12) {
            if index > 0 {
                Button {
                    index -= 1
                } label: {
                    Label("上一题", systemImage: "chevron.left")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            if last {
                Button {
                    submit()
                } label: {
                    Label("提交", systemImage: "checkmark")
                        .frame(minWidth: 100, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!allAnswered)
            } else {
                Button {
                    index += 1
                } label: {
                    Label("下一题", systemImage: "chevron.right")
                        .frame(minWidth: 100, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isAnswered(index))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    /// A full-width answer button: selected = check symbol + "已选" + outline, never colour alone.
    private func choiceButton(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        let traits: AccessibilityTraits = selected ? .isSelected : []
        return Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Theme.accent : Color.secondary)
                Text(text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if selected {
                    Text("已选")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(choiceBackground(selected))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selected ? text + "，已选" : text)
        .accessibilityAddTraits(traits)
    }

    private func choiceBackground(_ selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(selected ? Theme.accent.opacity(0.12) : Theme.chip.opacity(0.6))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selected ? Theme.accent : Color.clear, lineWidth: 2))
    }

    private func isChosen(_ option: Int) -> Bool {
        answers.indices.contains(index) && answers[index] == option
    }

    private func isAnswered(_ i: Int) -> Bool {
        answers.indices.contains(i) && answers[i] != nil
    }

    private func choose(_ option: Int) {
        guard result == nil, answers.indices.contains(index) else { return }
        answers[index] = option
        ActivityClock.shared.touch(.read, source: "quiz")
    }

    private static func letter(_ i: Int) -> String {
        let letters = ["A", "B", "C", "D", "E", "F", "G", "H"]
        return letters.indices.contains(i) ? letters[i] : "\(i + 1)"
    }

    // MARK: Submit

    private var selfReportText: String? {
        guard isListeningCheck else { return nil }
        if let note = setup.noAudioNote { return note }
        return "播放 \(plays) 次；自评：\(understood ?? "没有选")"
    }

    private func submit() {
        guard result == nil, allAnswered else { return }
        stopPlayback()
        let chosen = answers.map { $0 ?? -1 }
        var correct = 0
        for (i, q) in setup.questions.enumerated() where chosen.indices.contains(i) && chosen[i] == q.answer {
            correct += 1
        }
        let begin = started ?? Date()
        let r = QuizResult(id: UUID().uuidString, article: ref.key, at: begin, day: DayKey.today, purpose: purpose,
                           answers: chosen, correct: correct, total: setup.questions.count,
                           seconds: max(0, Date().timeIntervalSince(begin)), selfReport: selfReportText,
                           usedText: purpose == "practice")
        result = r
        stage = .result
        ActivityClock.shared.touch(.read, source: "quiz")
        study.addQuizResult(r)
        onDone?(r)
    }

    // MARK: Result

    @ViewBuilder
    private var resultView: some View {
        if let r = result {
            VStack(alignment: .leading, spacing: 18) {
                summaryCard(r)
                HStack {
                    Text("逐题看")
                        .font(.headline)
                    Spacer()
                    zhButton
                }
                ForEach(Array(setup.questions.enumerated()), id: \.offset) { i, q in
                    resultCard(i, q)
                }
                Button {
                    dismiss()
                } label: {
                    Label("完成", systemImage: "checkmark")
                        .frame(minWidth: 120, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func summaryCard(_ r: QuizResult) -> some View {
        PracticeCard {
            Text("答对 \(r.correct) / \(r.total)")
                .font(.largeTitle.weight(.semibold))
            Text("用时 \(ArticleQuizView.durationText(r.seconds)) · 已保存")
                .foregroundStyle(.secondary)
            if let report = r.selfReport {
                Text(report)
            }
            Text(purposeNote)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("样本少：这一次只有 \(r.total) 题，结果只作参考，要看多次的记录。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var purposeNote: String {
        switch purpose {
        case "delayed": return "隔日回忆：没有重听、没有看原文，记作一次独立复测。"
        case "weekly": return "新材料复测：只听了一小段就作答，记作一次独立复测。"
        case "baseline": return "基线的一部分：只记录描述，不换算成分数。"
        default: return "练习：可以看原文，所以记作阅读理解，不算独立复测。"
        }
    }

    private func resultCard(_ i: Int, _ q: QuizQuestion) -> some View {
        let chosen: Int? = answers.indices.contains(i) ? answers[i] : nil
        let right = chosen == q.answer
        return PracticeCard {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("第 \(i + 1) 题 · \(ArticleQuizView.kindTitle(q.kind))")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Label(right ? "答对" : "答错", systemImage: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(right ? Theme.level5 : Theme.warn)
            }
            Text(q.q)
                .font(Font.system(.body, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
            if showZh, let zh = q.zh, !zh.isEmpty {
                Text(zh)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if right {
                answerLine("你的答案（正确答案）", ArticleQuizView.optionText(q, chosen), symbol: "checkmark")
            } else {
                answerLine("你的答案", ArticleQuizView.optionText(q, chosen), symbol: "xmark")
                answerLine("正确答案", ArticleQuizView.optionText(q, q.answer), symbol: "checkmark")
            }
            if let explain = q.explain, !explain.isEmpty {
                Text("解释：" + explain)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if allowsSource {
                Button {
                    openSource(q)
                } label: {
                    Label((q.sids ?? []).isEmpty ? "看原文" : "看原句", systemImage: "text.magnifyingglass")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("关闭理解题，打开这篇文章")
            }
        }
    }

    private func answerLine(_ title: String, _ text: String, symbol: String) -> some View {
        Label {
            Text(title + "：" + text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.callout)
    }

    /// Closes the check and opens the article, with the supporting sentence in the side panel.
    private func openSource(_ q: QuizQuestion) {
        stopPlayback()
        let sid = q.sids?.first
        dismiss()
        router.openArticle(ref)
        guard let sid else { return }
        // Open the article here so the sentence panel is ready when the reader appears.
        session.open(ref)
        if session.sentence(sid) != nil {
            session.showSentence(sid)
        }
    }

    private func close() {
        if hasUnsavedAnswers {
            confirmClose = true
        } else {
            stopPlayback()
            dismiss()
        }
    }

    // MARK: Text helpers

    private static func optionText(_ q: QuizQuestion, _ i: Int?) -> String {
        guard let i, q.options.indices.contains(i) else { return "没有作答" }
        return letter(i) + ". " + q.options[i]
    }

    private static func kindTitle(_ kind: String) -> String {
        switch kind {
        case "main": return "主旨"
        case "detail": return "细节"
        case "inference": return "推断"
        case "word": return "词义"
        default: return "理解"
        }
    }

    private static func durationText(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s < 60 { return "\(s) 秒" }
        return "\(s / 60) 分 \(s % 60) 秒"
    }

    // MARK: Missing

    private var missingView: some View {
        ContentUnavailableView {
            Label("还没有理解题", systemImage: "checklist")
        } description: {
            Text("这篇还没有理解题。导入新版内容包（格式 2）以后才有。")
        } actions: {
            Button("关闭") { dismiss() }
                .buttonStyle(.bordered)
        }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("没有可用的题", systemImage: "checklist")
        } description: {
            Text("这篇的题目文件里没有可以用的题。可以换一篇，或者重新导入内容包。")
        } actions: {
            Button("关闭") { dismiss() }
                .buttonStyle(.bordered)
        }
    }
}

/// 看原文 (practice only): the article as plain text.
private struct QuizArticleTextView: View {
    let ref: ArticleRef
    @Environment(PackStore.self) private var packs

    var body: some View {
        Group {
            if let art = packs.cachedArticle(ref) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        Text(art.title)
                            .font(Font.system(.title2, design: .serif).weight(.semibold))
                        ForEach(Array(art.paras.enumerated()), id: \.offset) { _, para in
                            paragraph(para)
                        }
                    }
                    .frame(maxWidth: 680, alignment: .leading)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }
            } else {
                ContentUnavailableView("打不开原文", systemImage: "doc.text",
                                       description: Text("这篇文章的正文文件读不出来。"))
            }
        }
        .navigationTitle("原文")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func paragraph(_ para: Para) -> some View {
        let text = para.sents.map { SentenceText.plain($0) }.joined(separator: " ")
        let base = Font.system(.body, design: .serif)
        return Text(text)
            .font(para.kind == "p" ? base : base.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}
