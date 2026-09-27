import SwiftUI

/// 写作. One page for three kinds of task:
/// - 基础写作 (V0.2): 5–10 minutes, 3–5 sentences; the reference opens after the self-check.
/// - 写作 Task 1 / Task 2 (V0.4, IEL-P05/P06): at least 150 / 250 words, about 20 / 40 minutes
///   (no hard stop). Task 1 shows its chart beside the editor on a wide screen, above it otherwise.
///   There is no model essay: self-check first, then feedback from a teacher or Claude.
/// The draft saves itself; after "完成这一版" the version is read-only.
/// A rewrite becomes a new version and is marked as not independent.
struct WritingSessionView: View {
    private enum Source {
        case basic(WritingPrompt)
        case task1(Task1Prompt)
        case task2(Task2Prompt)
    }

    private let source: Source

    @Environment(PracticeStore.self) private var practice
    @Environment(\.scenePhase) private var scenePhase

    @State private var workId: String?
    @State private var text = ""
    @State private var elapsed: Double = 0
    @State private var ticker: Task<Void, Never>?
    @State private var check: SelfCheck
    @State private var showFeedback = false
    @State private var showHints = false
    @State private var message: String?
    @State private var loaded = false
    @State private var pendingSave: Task<Void, Never>?
    @State private var pageWidth: CGFloat = 0
    @State private var confirmShort = false
    @FocusState private var editorFocused: Bool

    /// 基础写作 (V0.2 behaviour).
    init(prompt: WritingPrompt) {
        source = .basic(prompt)
        _check = State(initialValue: SelfCheckTemplate.empty(SelfCheckTemplate.writing))
    }

    /// 写作 Task 1: describe a chart, table or process (IEL-P05).
    init(task1: Task1Prompt) {
        source = .task1(task1)
        _check = State(initialValue: SelfCheckTemplate.empty(SelfCheckTemplate.task1))
    }

    /// 写作 Task 2: an essay (IEL-P06).
    init(task2: Task2Prompt) {
        source = .task2(task2)
        _check = State(initialValue: SelfCheckTemplate.empty(SelfCheckTemplate.task2))
    }

    private var work: WritingWork? {
        guard let workId else { return nil }
        return practice.writing(workId)
    }

    // MARK: Task facts

    private var basicPrompt: WritingPrompt? {
        if case .basic(let p) = source { return p }
        return nil
    }

    private var isExam: Bool { basicPrompt == nil }

    private var promptId: String {
        switch source {
        case .basic(let p): return p.id
        case .task1(let p): return p.id
        case .task2(let p): return p.id
        }
    }

    private var taskText: String {
        switch source {
        case .basic(let p): return p.task
        case .task1(let p): return p.title
        case .task2(let p): return p.text
        }
    }

    private var dims: [CheckDimension] {
        switch source {
        case .basic: return SelfCheckTemplate.writing
        case .task1: return SelfCheckTemplate.task1
        case .task2: return SelfCheckTemplate.task2
        }
    }

    /// WritingWork.kind; basic works keep the V0.2 record (no kind).
    private var kindKey: String? {
        switch source {
        case .basic: return nil
        case .task1: return "task1"
        case .task2: return "task2"
        }
    }

    private var minWords: Int? {
        switch source {
        case .basic: return nil
        case .task1: return IELTSExamBank.timings.task1MinWords
        case .task2: return IELTSExamBank.timings.task2MinWords
        }
    }

    /// Suggested time in seconds; after it the timer turns orange but writing goes on.
    private var targetSeconds: Double {
        switch source {
        case .basic: return 600
        case .task1: return IELTSExamBank.timings.task1Minutes * 60
        case .task2: return IELTSExamBank.timings.task2Minutes * 60
        }
    }

    private var navTitle: String {
        switch source {
        case .basic: return "基础写作"
        case .task1: return "写作 Task 1"
        case .task2: return "写作 Task 2"
        }
    }

    /// Task 1 on a wide screen: the chart on the left, the writing on the right.
    private var sideBySide: Bool {
        if case .task1 = source { return pageWidth >= 900 }
        return false
    }

    var body: some View {
        ScrollView {
            Group {
                if sideBySide {
                    HStack(alignment: .top, spacing: 24) {
                        promptCard
                            .frame(width: max(360, min(520, (pageWidth - 72) * 0.45)))
                        VStack(alignment: .leading, spacing: 18) {
                            workSection
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: 1240, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        promptCard
                        workSection
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            pageWidth = width
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !loaded {
                loaded = true
                resumeLatest()
            } else if ticker == nil, work?.isDraft == true {
                startTicker()
            }
        }
        .onDisappear {
            pendingSave?.cancel()
            pendingSave = nil
            saveProgress()
            ticker?.cancel()
            ticker = nil
        }
        .onChange(of: text) { _, newValue in
            ActivityClock.shared.touch(.output, source: "writing")
            saveText(newValue)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Leaving the app does not call onDisappear: save the draft now.
            if newPhase != .active {
                pendingSave?.cancel()
                pendingSave = nil
                saveProgress()
                practice.saveNow()
            }
        }
        .sheet(isPresented: $showFeedback) {
            FeedbackSheet { feedback in
                if let id = workId {
                    practice.updateWriting(id) { $0.feedback.append(feedback) }
                }
            }
        }
        .alert("还不到 \(minWords ?? 0) 词", isPresented: $confirmShort) {
            Button("继续写", role: .cancel) {}
            Button("仍然完成") { finishVersion() }
        } message: {
            Text("考试要求至少 \(minWords ?? 0) 词，字数不够会影响任务完成。完成后这一版只读，会记下实际字数。")
        }
    }

    @ViewBuilder
    private var workSection: some View {
        if let work {
            content(work)
        } else {
            Button {
                startNew()
            } label: {
                Label("开始写", systemImage: "pencil")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        if let message {
            Label(message, systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        history
    }

    // MARK: Prompt

    @ViewBuilder
    private var promptCard: some View {
        switch source {
        case .basic(let prompt):
            basicPromptCard(prompt)
        case .task1(let p):
            task1PromptCard(p)
        case .task2(let p):
            task2PromptCard(p)
        }
    }

    private func basicPromptCard(_ prompt: WritingPrompt) -> some View {
        PracticeCard {
            HStack {
                Badge(text: prompt.topic)
                Badge(text: "5–10 分钟 · 3–5 句", outlined: true)
                Spacer()
                Toggle("提示", isOn: $showHints)
                    .toggleStyle(.button)
                    .controlSize(.small)
            }
            Text(prompt.task)
                .font(Font.system(.title3, design: .serif).weight(.semibold))
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

    private func task1PromptCard(_ p: Task1Prompt) -> some View {
        let t = IELTSExamBank.timings
        return PracticeCard {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                Badge(text: "考试题型", color: Theme.accent)
                Badge(text: "Task 1 · \(p.kind.title)")
                Badge(text: "至少 \(t.task1MinWords) 词 · 约 \(Int(t.task1Minutes)) 分钟", outlined: true)
            }
            Text(p.title)
                .font(Font.system(.title3, design: .serif).weight(.semibold))
                .textSelection(.enabled)
            Text(p.kind.note)
                .font(.callout)
                .foregroundStyle(.secondary)
            Task1ChartView(prompt: p)
            Text(WritingSessionView.examConditions)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private static let examConditions = "考试条件：不给提示，不给范文；到了建议时间不强制停止。题目和数据是 DayDayUp 原创，仅供练习。"

    private func task2PromptCard(_ p: Task2Prompt) -> some View {
        let t = IELTSExamBank.timings
        return PracticeCard {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                Badge(text: "考试题型", color: Theme.accent)
                Badge(text: "Task 2 · \(p.type.title)")
                Badge(text: p.topic)
                Badge(text: "至少 \(t.task2MinWords) 词 · 约 \(Int(t.task2Minutes)) 分钟", outlined: true)
            }
            Text(p.text)
                .font(Font.system(.title3, design: .serif).weight(.semibold))
                .textSelection(.enabled)
            Text(p.type.note)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(WritingSessionView.examConditions)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Work

    @ViewBuilder
    private func content(_ work: WritingWork) -> some View {
        let versions = work.versions
        if let latest = versions.last {
            if versions.count > 1 {
                ForEach(versions.dropLast()) { v in
                    DisclosureGroup("第 \(v.n) 版（\(versionLabel(v))，只读）") {
                        Text(v.text)
                            .font(Font.system(.body, design: .serif))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    }
                }
            }

            if latest.finished == nil {
                editor(latest)
            } else {
                PracticeCard {
                    HStack {
                        Text("第 \(latest.n) 版").font(.headline)
                        Badge(text: versionLabel(latest), outlined: true)
                        Spacer()
                        Text(statsLine(latest))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if isExam {
                        examConditionNotes(latest)
                    }
                    Text(latest.text)
                        .font(Font.system(.body, design: .serif))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }
                if let done = latest.check {
                    PracticeCard {
                        Text("我的自评").font(.headline)
                        SelfCheckSummary(dims: dims, check: done)
                    }
                    if let prompt = basicPrompt {
                        referenceCard(prompt)
                    } else {
                        noModelCard
                    }
                    actions(work, latest: latest)
                } else {
                    PracticeCard {
                        Text(isExam ? "先自评，再找反馈" : "先自评，再看参考").font(.headline)
                        Text("对照下面几项，逐项打勾，写下证据。这里不打分。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        SelfCheckForm(dims: dims, check: $check)
                        Button {
                            submitCheck(work)
                        } label: {
                            Label(isExam ? "提交自评" : "提交自评，看参考", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
            }
            FeedbackList(items: work.feedback)
        }
    }

    private func editor(_ version: WritingVersion) -> some View {
        let words = WritingStats.words(text)
        let sentences = WritingStats.sentences(text)
        return VStack(alignment: .leading, spacing: 10) {
            if let min = minWords {
                examMeter(words: words, minWords: min, version: version)
            } else {
                HStack(spacing: 16) {
                    Label(formatTime(elapsed), systemImage: "timer")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(elapsed > 600 ? Theme.warn : Theme.accent)
                    Text("\(words) 词")
                        .font(.callout.monospacedDigit())
                    Text("\(sentences) 句")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(sentences >= 3 && sentences <= 5 ? Color.primary : Theme.warn)
                    Spacer()
                    Text(version.n == 1 ? "第 1 版（初稿）" : "第 \(version.n) 版（改写）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            TextEditor(text: $text)
                .font(Font.system(.title3, design: .serif))
                .focused($editorFocused)
                .frame(minHeight: isExam ? 420 : 260)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.3)))
                .autocorrectionDisabled(false)
            Text(editorNote)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                finishTapped(words: words)
            } label: {
                Label("完成这一版", systemImage: "checkmark.seal")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(words == 0)
        }
    }

    /// Exam tasks: time against the suggestion and words against the minimum, in words and icons.
    private func examMeter(words: Int, minWords: Int, version: WritingVersion) -> some View {
        let over = elapsed > targetSeconds
        let enough = words >= minWords
        return VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 16, lineSpacing: 6) {
                Label("\(formatTime(elapsed)) / \(formatTime(targetSeconds))",
                      systemImage: over ? "exclamationmark.circle" : "timer")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(over ? Theme.warn : Theme.accent)
                Label(enough ? "已写 \(words) 词，已达到 \(minWords) 词" : "已写 \(words) 词，至少 \(minWords) 词",
                      systemImage: enough ? "checkmark.circle" : "text.alignleft")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(enough ? Color.primary : Theme.warn)
            }
            Text(version.n == 1 ? "第 1 版（初稿）" : "第 \(version.n) 版（改写）")
                .font(.caption)
                .foregroundStyle(.secondary)
            if over {
                Text("已超过建议的 \(Int(targetSeconds / 60)) 分钟。可以继续写，时间照实记录。")
                    .font(.caption)
                    .foregroundStyle(Theme.warn)
            }
        }
    }

    private var editorNote: String {
        switch source {
        case .basic:
            return "草稿会自动保存。建议 5–10 分钟，写 3–5 句。超时也可以继续写，时间照实记录。"
        case .task1:
            return "草稿会自动保存。建议约 20 分钟，至少 150 词。超时也可以继续写，时间照实记录。"
        case .task2:
            return "草稿会自动保存。建议约 40 分钟，至少 250 词。超时也可以继续写，时间照实记录。"
        }
    }

    private func statsLine(_ v: WritingVersion) -> String {
        let words = WritingStats.words(v.text)
        if isExam {
            return "\(words) 词 · \(formatTime(v.seconds))"
        }
        return "\(words) 词 · \(WritingStats.sentences(v.text)) 句 · \(formatTime(v.seconds))"
    }

    /// A finished exam version below the word minimum or over the suggested time says so.
    @ViewBuilder
    private func examConditionNotes(_ v: WritingVersion) -> some View {
        let words = WritingStats.words(v.text)
        if let min = minWords, words < min {
            Label("这一版 \(words) 词，不到 \(min) 词。", systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(Theme.warn)
        }
        if v.seconds > targetSeconds {
            Label("用时 \(formatTime(v.seconds))，超过建议的 \(Int(targetSeconds / 60)) 分钟。", systemImage: "clock")
                .font(.callout)
                .foregroundStyle(Theme.warn)
        }
    }

    private func versionLabel(_ v: WritingVersion) -> String {
        if !isExam { return v.independent ? "独立完成" : "看过参考后" }
        if v.independent { return "独立完成" }
        return v.n > 1 ? "改写" : "看过反馈后"
    }

    private func referenceCard(_ prompt: WritingPrompt) -> some View {
        PracticeCard {
            Text("参考段落").font(.headline)
            Text(prompt.model)
                .font(Font.system(.body, design: .serif))
                .lineSpacing(4)
                .textSelection(.enabled)
            Text("可以借用的句型").font(.subheadline.weight(.semibold))
            ForEach(prompt.phrases, id: \.self) { p in
                Label(p, systemImage: "text.quote")
                    .font(.callout)
            }
            Text("参考段落是 DayDayUp 原创的示范。改写时借结构和句型，不要照抄。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var noModelCard: some View {
        PracticeCard {
            Label("考试作文不给范文；先自评，再找老师或 Claude 反馈。", systemImage: "person.2")
                .font(.headline)
            Text("用“复制给 Claude”把题目和作文复制出去，或拿给老师看。收到意见后点“录入反馈”存下来，再改写成新版本。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func actions(_ work: WritingWork, latest: WritingVersion) -> some View {
        FlowLayout(spacing: 12, lineSpacing: 12) {
            Button {
                rewrite(work, from: latest)
            } label: {
                Label("改写成第 \(latest.n + 1) 版", systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderedProminent)
            Button {
                showFeedback = true
            } label: {
                Label("录入反馈", systemImage: "text.bubble")
            }
            .buttonStyle(.bordered)
            Button {
                Clipboard.copy(claudeText(latest))
                message = "已复制题目、你的第 \(latest.n) 版和反馈要求，可以直接发给 Claude。"
            } label: {
                Label("复制给 Claude", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            Button {
                startNew()
            } label: {
                Label("重新写一篇", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }

    private func claudeText(_ latest: WritingVersion) -> String {
        let words = WritingStats.words(latest.text)
        let minutes = Int((latest.seconds / 60).rounded())
        switch source {
        case .basic(let prompt):
            return "IELTS Writing (basic, 3–5 sentences)\nTask: \(prompt.task)\n\nMy answer (version \(latest.n)):\n\(latest.text)\n\nPlease give feedback on Task Response, Coherence & Cohesion, Lexical Resource and Grammatical Range & Accuracy. Quote my words as evidence and suggest one rewrite for each problem. No band score."
        case .task1(let p):
            return """
            IELTS Academic Writing Task 1 (practice; the data was made up for practice)
            Task: \(p.title)

            The figure: \(p.heading)
            \(p.dataText)

            My answer (version \(latest.n), \(words) words, about \(minutes) minutes):
            \(latest.text)

            Please give feedback on Task Achievement, Coherence & Cohesion, Lexical Resource and Grammatical Range & Accuracy. Check that my overview and the numbers I quote match the data. Quote my words as evidence and suggest one rewrite for each problem. No band score.
            """
        case .task2(let p):
            return """
            IELTS Academic Writing Task 2 (practice)
            Question: \(p.text)

            My essay (version \(latest.n), \(words) words, about \(minutes) minutes):
            \(latest.text)

            Please give feedback on Task Response, Coherence & Cohesion, Lexical Resource and Grammatical Range & Accuracy. Tell me whether I answered every part of the question and kept a clear position. Quote my words as evidence and suggest one rewrite for each problem. No band score.
            """
        }
    }

    // MARK: History

    @ViewBuilder
    private var history: some View {
        let others = practice.writingWorks(prompt: promptId).filter { $0.id != workId }
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("这道题以前写过（\(others.count)）").font(.headline)
                ForEach(others) { w in
                    Button {
                        open(w)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(w.created.formatted(date: .abbreviated, time: .shortened)).font(.callout)
                                Text(historyLine(w))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
    }

    private func historyLine(_ w: WritingWork) -> String {
        let base = "\(w.versions.count) 版 · \(w.isDraft ? "草稿" : "已完成") · 反馈 \(w.feedback.count) 条"
        guard isExam, let latest = w.versions.last else { return base }
        return base + " · \(WritingStats.words(latest.text)) 词"
    }

    // MARK: Actions

    private func resumeLatest() {
        if let latest = practice.writingWorks(prompt: promptId).first {
            open(latest)
        }
    }

    private func open(_ w: WritingWork) {
        pendingSave?.cancel()
        pendingSave = nil
        saveProgress()
        ticker?.cancel()
        ticker = nil
        workId = w.id
        check = SelfCheckTemplate.empty(dims)
        message = nil
        if let v = w.versions.last {
            text = v.text
            elapsed = v.seconds
            if v.finished == nil { startTicker() }
        }
    }

    /// Basic tasks: an earlier answer revealed the reference. Exam tasks (no reference):
    /// an earlier answer already has feedback.
    private var priorHelpSeen: Bool {
        let works = practice.writingWorks(prompt: promptId)
        if isExam { return works.contains { !$0.feedback.isEmpty } }
        return works.contains { $0.sawReference }
    }

    private func startNew() {
        pendingSave?.cancel()
        pendingSave = nil
        saveProgress()
        ticker?.cancel()
        let seen = priorHelpSeen
        let now = Date()
        let version = WritingVersion(id: UUID().uuidString, n: 1, text: "", started: now, finished: nil,
                                     seconds: 0, independent: !seen, check: nil)
        var w = WritingWork(id: UUID().uuidString, promptId: promptId, task: taskText, created: now, versions: [version])
        w.kind = kindKey
        w.minWords = minWords
        w.targetMinutes = isExam ? targetSeconds / 60 : nil
        practice.addWriting(w)
        workId = w.id
        text = ""
        elapsed = 0
        check = SelfCheckTemplate.empty(dims)
        if seen {
            message = isExam ? "这道题以前收到过反馈，这篇会记为“看过反馈后”。" : "你以前看过这道题的参考，这篇会记为“看过参考后”。"
        } else {
            message = nil
        }
        startTicker()
        editorFocused = true
    }

    private func rewrite(_ w: WritingWork, from latest: WritingVersion) {
        let version = WritingVersion(id: UUID().uuidString, n: latest.n + 1, text: latest.text, started: Date(),
                                     finished: nil, seconds: 0, independent: false, check: nil)
        practice.updateWriting(w.id) { $0.versions.append(version) }
        text = latest.text
        elapsed = 0
        check = SelfCheckTemplate.empty(dims)
        message = nil
        startTicker()
        editorFocused = true
    }

    private func finishTapped(words: Int) {
        if let min = minWords, words < min {
            confirmShort = true
        } else {
            finishVersion()
        }
    }

    private func finishVersion() {
        guard let id = workId else { return }
        pendingSave?.cancel()
        pendingSave = nil
        ticker?.cancel()
        ticker = nil
        let finalText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let seconds = elapsed
        practice.updateWriting(id) { w in
            guard !w.versions.isEmpty else { return }
            let last = w.versions.count - 1
            w.versions[last].text = finalText
            w.versions[last].seconds = seconds
            w.versions[last].finished = Date()
        }
        practice.saveNow()
        text = finalText
        editorFocused = false
        check = SelfCheckTemplate.empty(dims)
    }

    private func submitCheck(_ w: WritingWork) {
        var submitted = check
        submitted.created = Date()
        // Only basic tasks have a reference that opens now; exam tasks have none.
        let opensReference = !isExam
        practice.updateWriting(w.id) { work in
            guard !work.versions.isEmpty else { return }
            work.versions[work.versions.count - 1].check = submitted
            if opensReference { work.sawReference = true }
        }
    }

    /// Saves the draft text about one second after typing stops.
    private func saveText(_ value: String) {
        pendingSave?.cancel()
        guard let id = workId else { return }
        pendingSave = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return }
            pendingSave = nil
            guard let w = practice.writing(id), let last = w.versions.last,
                  last.finished == nil, last.text != value else { return }
            practice.updateWriting(id) { work in
                guard !work.versions.isEmpty else { return }
                work.versions[work.versions.count - 1].text = value
            }
        }
    }

    private func saveProgress() {
        guard let id = workId, let w = practice.writing(id), let last = w.versions.last, last.finished == nil else { return }
        let seconds = elapsed
        let value = text
        practice.updateWriting(id) { work in
            guard !work.versions.isEmpty else { return }
            let i = work.versions.count - 1
            work.versions[i].seconds = seconds
            work.versions[i].text = value
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task {
            var sinceSave = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                elapsed += 1
                sinceSave += 1
                if sinceSave >= 15 {
                    sinceSave = 0
                    saveProgress()
                }
            }
        }
    }
}
