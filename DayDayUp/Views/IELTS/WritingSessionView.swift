import SwiftUI

/// 基础写作: 5–10 minutes, 3–5 sentences. The draft saves itself; after "完成这一版"
/// the version is read-only. Self-assess first, then the reference opens.
/// A rewrite becomes a new version and is marked as written after seeing the reference.
struct WritingSessionView: View {
    let prompt: WritingPrompt

    @Environment(PracticeStore.self) private var practice
    @Environment(\.scenePhase) private var scenePhase

    @State private var workId: String?
    @State private var text = ""
    @State private var elapsed: Double = 0
    @State private var ticker: Task<Void, Never>?
    @State private var check = SelfCheckTemplate.empty(SelfCheckTemplate.writing)
    @State private var showFeedback = false
    @State private var showHints = false
    @State private var message: String?
    @State private var loaded = false
    @State private var pendingSave: Task<Void, Never>?
    @FocusState private var editorFocused: Bool

    private var work: WritingWork? {
        guard let workId else { return nil }
        return practice.writing(workId)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                promptCard
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
            .frame(maxWidth: 760, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("基础写作")
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
    }

    // MARK: Prompt

    private var promptCard: some View {
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

    // MARK: Work

    @ViewBuilder
    private func content(_ work: WritingWork) -> some View {
        let versions = work.versions
        if let latest = versions.last {
            if versions.count > 1 {
                ForEach(versions.dropLast()) { v in
                    DisclosureGroup("第 \(v.n) 版（\(v.independent ? "独立完成" : "看过参考后")，只读）") {
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
                        Badge(text: latest.independent ? "独立完成" : "看过参考后", outlined: true)
                        Spacer()
                        Text("\(WritingStats.words(latest.text)) 词 · \(WritingStats.sentences(latest.text)) 句 · \(formatTime(latest.seconds))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(latest.text)
                        .font(Font.system(.body, design: .serif))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }
                if let done = latest.check {
                    PracticeCard {
                        Text("我的自评").font(.headline)
                        SelfCheckSummary(dims: SelfCheckTemplate.writing, check: done)
                    }
                    referenceCard
                    actions(work, latest: latest)
                } else {
                    PracticeCard {
                        Text("先自评，再看参考").font(.headline)
                        Text("对照下面几项，逐项打勾，写下证据。这里不打分。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        SelfCheckForm(dims: SelfCheckTemplate.writing, check: $check)
                        Button {
                            submitCheck(work)
                        } label: {
                            Label("提交自评，看参考", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.borderedProminent)
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
            TextEditor(text: $text)
                .font(Font.system(.title3, design: .serif))
                .focused($editorFocused)
                .frame(minHeight: 260)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.3)))
                .autocorrectionDisabled(false)
            Text("草稿会自动保存。建议 5–10 分钟，写 3–5 句。超时也可以继续写，时间照实记录。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                finishVersion()
            } label: {
                Label("完成这一版", systemImage: "checkmark.seal")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(words == 0)
        }
    }

    private var referenceCard: some View {
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

    private func actions(_ work: WritingWork, latest: WritingVersion) -> some View {
        HStack(spacing: 12) {
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
                Clipboard.copy("IELTS Writing (basic, 3–5 sentences)\nTask: \(prompt.task)\n\nMy answer (version \(latest.n)):\n\(latest.text)\n\nPlease give feedback on Task Response, Coherence & Cohesion, Lexical Resource and Grammatical Range & Accuracy. Quote my words as evidence and suggest one rewrite for each problem. No band score.")
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
    }

    // MARK: History

    @ViewBuilder
    private var history: some View {
        let others = practice.writingWorks(prompt: prompt.id).filter { $0.id != workId }
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
                                Text("\(w.versions.count) 版 · \(w.isDraft ? "草稿" : "已完成") · 反馈 \(w.feedback.count) 条")
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

    // MARK: Actions

    private func resumeLatest() {
        if let latest = practice.writingWorks(prompt: prompt.id).first {
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
        check = SelfCheckTemplate.empty(SelfCheckTemplate.writing)
        message = nil
        if let v = w.versions.last {
            text = v.text
            elapsed = v.seconds
            if v.finished == nil { startTicker() }
        }
    }

    private func startNew() {
        pendingSave?.cancel()
        pendingSave = nil
        saveProgress()
        ticker?.cancel()
        let seen = practice.writingWorks(prompt: prompt.id).contains { $0.sawReference }
        let now = Date()
        let version = WritingVersion(id: UUID().uuidString, n: 1, text: "", started: now, finished: nil,
                                     seconds: 0, independent: !seen, check: nil)
        let w = WritingWork(id: UUID().uuidString, promptId: prompt.id, task: prompt.task, created: now, versions: [version])
        practice.addWriting(w)
        workId = w.id
        text = ""
        elapsed = 0
        check = SelfCheckTemplate.empty(SelfCheckTemplate.writing)
        message = seen ? "你以前看过这道题的参考，这篇会记为“看过参考后”。" : nil
        startTicker()
        editorFocused = true
    }

    private func rewrite(_ w: WritingWork, from latest: WritingVersion) {
        let version = WritingVersion(id: UUID().uuidString, n: latest.n + 1, text: latest.text, started: Date(),
                                     finished: nil, seconds: 0, independent: false, check: nil)
        practice.updateWriting(w.id) { $0.versions.append(version) }
        text = latest.text
        elapsed = 0
        check = SelfCheckTemplate.empty(SelfCheckTemplate.writing)
        message = nil
        startTicker()
        editorFocused = true
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
        check = SelfCheckTemplate.empty(SelfCheckTemplate.writing)
    }

    private func submitCheck(_ w: WritingWork) {
        var submitted = check
        submitted.created = Date()
        practice.updateWriting(w.id) { work in
            guard !work.versions.isEmpty else { return }
            work.versions[work.versions.count - 1].check = submitted
            work.sawReference = true
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
