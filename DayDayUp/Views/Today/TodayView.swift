import SwiftUI

/// 今日 (PAGE-01, UI-02, PLAN-P01…P04, ACC-12, ACC-30): the day's time budget and stage, today's plan with the
/// reason for every task, how much was really practised today, and recent weak points. It shows tasks, never a
/// score promise; when material is missing it says so instead of inventing tasks.
/// The plan is made once a day by TodayPlanner (it changes the store), so it is made in onAppear / when the app
/// becomes active, never inside `body`.
struct TodayView: View {
    @Environment(PackStore.self) private var packs
    @Environment(UserStore.self) private var user
    @Environment(PracticeStore.self) private var practice
    @Environment(VocabStore.self) private var vocab
    @Environment(StudyStore.self) private var study
    @Environment(Router.self) private var router
    @Environment(ReadingSession.self) private var session
    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.scenePhase) private var scenePhase

    @State private var route: TodayRoute?
    @State private var quiz: TodayQuiz?
    @State private var notice: TodayNotice?
    /// Articles swapped away today with 换一篇, so the next swap does not bring them back.
    @State private var swappedAway: [ArticleRef] = []
    /// Tasks the learner reopened: automatic completion leaves them open.
    @State private var reopened: Set<String> = []
    /// Article count when an empty plan was last rebuilt (after a content pack arrived).
    @State private var materialCheckedCount: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                banners
                planSection
                weakPointsCard
                continueRow
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("今日")
        .navigationDestination(item: $route) { r in
            destination(r)
        }
        .sheet(item: $quiz, onDismiss: { refreshEvidence() }) { q in
            ArticleQuizView(ref: q.ref, purpose: q.purpose, onDone: { _ in
                study.markDone(day: q.day, taskId: q.taskId)
            })
        }
        .onAppear { refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
        .onChange(of: router.tab) { _, tab in
            if tab == .today { refresh() }
        }
        .onChange(of: route) { _, newValue in
            ActivityClock.shared.currentCategory = TodayView.clockCategory(for: newValue, tab: router.tab)
            if newValue == nil { refreshEvidence() }
        }
        .onChange(of: packs.articleCount) { _, _ in
            rebuildIfNoMaterial()
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            if AppFlavor.isTest {
                Label("测试版：数据和正式版分开，随便测", systemImage: "wrench.and.screwdriver")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.warn)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(Theme.warn, lineWidth: 1))
            }
            Text(Date().formatted(date: .complete, time: .omitted))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            budgetControl
            HStack(spacing: 12) {
                Label("阶段：\(study.settings.stage.title)", systemImage: "flag")
                    .font(.callout)
                Button {
                    route = .studySettings(customBudget: false)
                } label: {
                    Label("计划设置", systemImage: "slider.horizontal.3")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var budgetControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            ChoicePicker("每天学习时间", selection: budgetChoice) {
                Text("60 分钟").tag(TodayBudgetChoice.sixty)
                Text("90 分钟").tag(TodayBudgetChoice.ninety)
                Text(customBudgetTitle).tag(TodayBudgetChoice.custom)
            }
            .controlSize(.large)
            .frame(maxWidth: 440)
            Text("改了以后，今天的计划会重新排；已完成的任务保留。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var customBudgetTitle: String {
        let b = study.settings.budgetMinutes
        return (b == 60 || b == 90) ? "自定义" : "自定义 \(b) 分钟"
    }

    private var budgetChoice: Binding<TodayBudgetChoice> {
        Binding<TodayBudgetChoice>(
            get: {
                switch study.settings.budgetMinutes {
                case 60: return .sixty
                case 90: return .ninety
                default: return .custom
                }
            },
            set: { choice in
                switch choice {
                case .sixty: setBudget(60)
                case .ninety: setBudget(90)
                case .custom: route = .studySettings(customBudget: true)
                }
            }
        )
    }

    // MARK: Banners

    @ViewBuilder
    private var banners: some View {
        if user.backupOverdue {
            backupBanner
        }
        if engine.hasAudio, let art = session.article {
            nowPlaying(art)
        }
        if let week = reportWeek {
            weeklyCard(week)
        }
    }

    private var backupBanner: some View {
        AdaptiveStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.title2)
                .foregroundStyle(Theme.warn)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.daysSinceBackup.map { "已经 \($0) 天没有备份" } ?? "还没有备份过学习记录")
                    .font(.headline)
                Text("学习记录只存在这台 iPad 上。每周备份一次，最稳妥。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                router.tab = .settings
            } label: {
                Text("去备份")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(Theme.warn.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }

    private func nowPlaying(_ art: Article) -> some View {
        AdaptiveStack(spacing: 14) {
            Button {
                session.togglePlay()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.accent)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(engine.isPlaying ? "暂停" : "播放")
            VStack(alignment: .leading, spacing: 2) {
                Text(engine.isPlaying ? "正在播放" : "已暂停")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(art.title)
                    .font(Font.system(.headline, design: .serif))
                Text("\(formatTime(engine.time)) / \(formatTime(engine.duration))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let ref = session.ref {
                Button {
                    router.openArticle(ref)
                } label: {
                    Text("回到原文")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }

    /// Last week's report, once there is any record from before this week (a new learner gets none).
    private var reportWeek: String? {
        guard let week = study.weekDueForReport() else { return nil }
        let thisMonday = DayKey.weekStart(DayKey.today)
        if study.state.plans.keys.contains(where: { $0 < thisMonday }) { return week }
        if user.state.daily.keys.contains(where: { $0 < thisMonday }) { return week }
        if study.activity.contains(where: { $0.day < thisMonday }) { return week }
        if vocab.events.contains(where: { $0.day < thisMonday }) { return week }
        return nil
    }

    private func weeklyCard(_ week: String) -> some View {
        let range = BaselineContent.shortDay(week) + "–" + BaselineContent.shortDay(DayKey.adding(6, to: week))
        return AdaptiveStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("上周（\(range)）的周报已准备好")
                    .font(.headline)
                Text("只列事实：投入的时间、复习、答题和说写记录，外加下周最多 3 个重点。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                route = .weekly(week)
            } label: {
                Text("查看周报")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Plan

    @ViewBuilder
    private var planSection: some View {
        if let plan = study.plan(for: DayKey.today) {
            VStack(alignment: .leading, spacing: 14) {
                planHeader(plan)
                if let notice {
                    noticeCard(notice)
                }
                if packs.packs.isEmpty {
                    importHint
                }
                ForEach(plan.tasks) { task in
                    taskCard(task, day: plan.day)
                }
                ForEach(plan.notes, id: \.self) { note in
                    Label(note, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            ProgressView("正在排今天的计划…")
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear { refresh() }
        }
    }

    private func planHeader(_ plan: PlanSnapshot) -> some View {
        let practised = study.minutes(days: [plan.day]).first?.total ?? 0
        let done = plan.tasks.filter { $0.state == .done }.count
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("今日计划")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("完成 \(done)/\(plan.tasks.count) 项")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text("计划 \(plan.budget) 分钟 · 今天有效练习 \(Int(practised.rounded())) 分钟")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("有效练习只算真实的学习操作：播放、答题、录音、打字等。只开着页面和后台播放都不算。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func taskCard(_ task: PlanTask, day: String) -> some View {
        TodayTaskCard(task: task,
                      startTitle: startTitle(task),
                      blocked: blockedReason(task),
                      canSwap: canSwap(task),
                      onStart: { start(task, day: day) },
                      onSwap: { swapReading(task, day: day) },
                      onDefer: { deferTask(task, day: day) },
                      onMarkDone: { markDone(task, day: day) },
                      onReopen: { reopen(task, day: day) })
    }

    private func noticeCard(_ n: TodayNotice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(n.text, systemImage: "info.circle")
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if let taskId = n.taskId {
                    Button {
                        study.markDone(day: n.day, taskId: taskId)
                        reopened.remove(taskId)
                        notice = nil
                    } label: {
                        Label("标记完成", systemImage: "checkmark.circle")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button {
                    notice = nil
                } label: {
                    Text("知道了")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warn.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private var importHint: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("还没有文章", systemImage: "books.vertical")
                .font(.headline)
            Text("听读、跟读和理解题都要用内容包里的文章。先在书架导入内容包，回到这里时，今天的计划会补上这些任务。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                router.tab = .library
            } label: {
                Label("打开书架", systemImage: "books.vertical")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Weak points and 继续听读

    @ViewBuilder
    private var weakPointsCard: some View {
        let since = Date().addingTimeInterval(-14 * 86_400)
        let issues = Metrics.issues(practice: practice.state, since: since,
                                    retracted: Set(study.state.retractedIssues))
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("最近薄弱点").font(.headline)
                    Text("来自近 14 天你自己的自评")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                ForEach(Array(issues.prefix(2))) { st in
                    Label(issueLine(st), systemImage: "exclamationmark.circle")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    router.tab = .progress
                } label: {
                    Label("在“进度”里看全部", systemImage: "chart.line.uptrend.xyaxis")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func issueLine(_ st: Metrics.IssueStat) -> String {
        let title = IssueText.dimTitle(kind: st.kind, dim: st.dim)
        let text = IssueText.text(kind: st.kind, dim: st.dim, question: st.question)
        var line = "\(title) · \(text)：\(st.checks) 次自评里 \(st.misses) 次没勾"
        if st.checks < Metrics.smallSample {
            line += "（样本少）"
        }
        return line
    }

    @ViewBuilder
    private var continueRow: some View {
        if let key = user.state.lastArticle, let ref = ArticleRef(key: key), let item = packs.item(ref) {
            AdaptiveStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("继续听读")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.meta.title)
                        .font(Font.system(.headline, design: .serif))
                    if let pos = user.state.positions[key], pos > 1 {
                        Text("上次停在 \(formatTime(pos)) / \(formatTime(item.meta.dur))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                ProgressRing(label: "听", value: user.state.listenProgress(key, duration: item.meta.dur))
                ProgressRing(label: "读", value: user.state.readProgress(key, duration: item.meta.dur), tint: Theme.level5)
                Button {
                    router.openArticle(ref)
                } label: {
                    Label("继续", systemImage: "play.fill")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
            .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: Task facts

    private func startTitle(_ task: PlanTask) -> String? {
        switch task.state {
        case .deferred:
            return nil
        case .done:
            return reopensMaterial(task) ? "再打开" : nil
        case .todo:
            break
        }
        switch task.target {
        case .vocabReview:
            return VocabQueueBuilder.activeReviews(vocab.todayEvents()).isEmpty ? "开始" : "继续"
        case .article(let issue, let id):
            let ref = ArticleRef(issue: issue, id: id)
            guard let item = packs.item(ref) else { return "开始" }
            return user.state.listenProgress(ref.key, duration: item.meta.dur) > 0 ? "继续" : "开始"
        case .shadow(let issue, let id, _):
            let key = ArticleRef(issue: issue, id: id).key
            let today = DayKey.today
            let started = practice.state.shadow.contains { $0.article == key && $0.dayKey == today }
            return started ? "继续" : "开始"
        case .writing(let promptId):
            return practice.state.writing.contains { $0.promptId == promptId && $0.isDraft } ? "继续" : "开始"
        case .retest(let id):
            return study.retest(id)?.promptId != nil ? "继续" : "开始"
        case .baseline:
            return study.state.baseline.doneCount > 0 ? "继续" : "开始"
        case .speaking, .articleCheck:
            return "开始"
        }
    }

    /// A done task can open its material again; a check or a retest is not done twice from here.
    private func reopensMaterial(_ task: PlanTask) -> Bool {
        switch task.target {
        case .retest, .articleCheck: return false
        default: return true
        }
    }

    private func blockedReason(_ task: PlanTask) -> String? {
        guard task.state != .deferred else { return nil }
        switch task.target {
        case .article(let issue, let id), .shadow(let issue, let id, _), .articleCheck(let issue, let id, _):
            guard packs.item(ArticleRef(issue: issue, id: id)) == nil else { return nil }
            if canSwap(task) {
                return "这篇文章的内容包不在 iPad 上了。可以换一篇，或者重新导入内容包。"
            }
            return "这篇文章的内容包不在 iPad 上了。可以重新导入内容包，或者点“暂缓”。"
        default:
            return nil
        }
    }

    private func canSwap(_ task: PlanTask) -> Bool {
        guard task.state == .todo, task.id.hasSuffix("-read") else { return false }
        if case .article = task.target { return true }
        return false
    }

    /// A 口语 / 写作 page pushed from 今日 counts taps as 说写 practice, like on the 雅思 tab.
    /// 今日 itself counts nothing (RootView.category(for:)).
    private static func clockCategory(for route: TodayRoute?, tab: AppTab) -> StudyCategory? {
        switch route {
        case .some(.speaking), .some(.writing):
            return .output
        default:
            return RootView.category(for: tab)
        }
    }

    static func hasMaterial(_ plan: PlanSnapshot) -> Bool {
        plan.tasks.contains { t in
            switch t.target {
            case .article, .shadow, .articleCheck: return true
            default: return false
            }
        }
    }

    // MARK: Actions

    private func refresh() {
        TodayPlanner.today(packs: packs, user: user, practice: practice, vocab: vocab, study: study)
        rebuildIfNoMaterial()
        refreshEvidence()
    }

    /// Marks open tasks done when the records show them done (ACC-30: never counted twice).
    private func refreshEvidence() {
        TodayPlanner.applyEvidence(skipping: reopened, packs: packs, user: user, practice: practice,
                                   vocab: vocab, study: study)
    }

    /// A plan made before any content pack was there gets its reading tasks once packs arrive
    /// (done tasks are kept). Tried once per article count, so a day with all material finished is left alone.
    private func rebuildIfNoMaterial() {
        let count = packs.articleCount
        guard count > 0, materialCheckedCount != count, let plan = study.plan(for: DayKey.today),
              !TodayView.hasMaterial(plan) else { return }
        materialCheckedCount = count
        TodayPlanner.rebuild(packs: packs, user: user, practice: practice, vocab: vocab, study: study)
    }

    private func setBudget(_ minutes: Int) {
        guard study.settings.budgetMinutes != minutes else { return }
        study.updateSettings { $0.budgetMinutes = minutes }
        TodayPlanner.rebuild(packs: packs, user: user, practice: practice, vocab: vocab, study: study)
        refreshEvidence()
    }

    private func start(_ task: PlanTask, day: String) {
        notice = nil
        switch task.target {
        case .vocabReview:
            router.openVocabReview()
        case .article(let issue, let id):
            router.openArticle(ArticleRef(issue: issue, id: id))
        case .shadow(let issue, let id, let sid):
            router.openShadow(ArticleRef(issue: issue, id: id), sid: sid)
        case .speaking(let promptId):
            route = .speaking(promptId)
        case .writing(let promptId):
            route = .writing(promptId)
        case .retest(let id):
            startRetest(id, task: task, day: day)
        case .baseline:
            route = .baseline
        case .articleCheck(let issue, let id, let purpose):
            quiz = TodayQuiz(ref: ArticleRef(issue: issue, id: id), purpose: purpose, day: day, taskId: task.id)
        }
    }

    /// PLAN-P04 / IEL-F04: a new prompt of the same kind. The next new work of that kind completes the retest
    /// (practice.onNewWork in DayDayUpApp).
    private func startRetest(_ id: String, task: PlanTask, day: String) {
        guard let r = study.retest(id) else {
            notice = TodayNotice(text: "这个复测的记录找不到了。今天可以直接标记完成。", day: day, taskId: task.id)
            return
        }
        guard r.kind == "speaking" || r.kind == "writing",
              let promptId = r.promptId ?? TodayPlanner.retestPrompt(for: r, practice: practice) else {
            notice = TodayNotice(text: "同类新题已经用完。今天可以直接标记完成。", day: day, taskId: task.id)
            return
        }
        study.setRetestPrompt(r.id, promptId: promptId)
        study.activeRetest = r.id
        route = r.kind == "speaking" ? TodayRoute.speaking(promptId) : TodayRoute.writing(promptId)
    }

    private func swapReading(_ task: PlanTask, day: String) {
        guard case .article(let issue, let id) = task.target else { return }
        let old = ArticleRef(issue: issue, id: id)
        let swapped = TodayPlanner.applySwap(readTaskId: task.id, day: day, current: old, alsoSkip: swappedAway,
                                             packs: packs, user: user, practice: practice, vocab: vocab,
                                             study: study)
        if swapped {
            swappedAway.append(old)
            notice = nil
        } else {
            swappedAway = []
            notice = TodayNotice(text: "没有别的材料可以换了。可以先做这一篇，或者点“暂缓”。", day: day, taskId: nil)
        }
    }

    private func deferTask(_ task: PlanTask, day: String) {
        study.deferTask(day: day, taskId: task.id)
        reopened.remove(task.id)
    }

    private func markDone(_ task: PlanTask, day: String) {
        study.markDone(day: day, taskId: task.id)
        reopened.remove(task.id)
    }

    private func reopen(_ task: PlanTask, day: String) {
        study.reopen(day: day, taskId: task.id)
        reopened.insert(task.id)
    }

    // MARK: Destinations

    @ViewBuilder
    private func destination(_ r: TodayRoute) -> some View {
        switch r {
        case .speaking(let id):
            speakingDestination(id)
        case .writing(let id):
            writingDestination(id)
        case .baseline:
            BaselineView()
        case .studySettings(let customBudget):
            StudySettingsView(customBudgetFirst: customBudget)
        case .weekly(let week):
            WeeklyReportView(week: week)
        }
    }

    @ViewBuilder
    private func speakingDestination(_ id: String) -> some View {
        if let p = IELTSBank.speaking(id) {
            SpeakingSessionView(prompt: p)
        } else if let card = IELTSExamBank.cueCard(id) {
            Part2SessionView(card: card)
        } else {
            missingPrompt
        }
    }

    @ViewBuilder
    private func writingDestination(_ id: String) -> some View {
        if let p = IELTSBank.writing(id) {
            WritingSessionView(prompt: p)
        } else if let t1 = IELTSExamBank.task1(id) {
            WritingSessionView(task1: t1)
        } else if let t2 = IELTSExamBank.task2(id) {
            WritingSessionView(task2: t2)
        } else {
            missingPrompt
        }
    }

    private var missingPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("这道题在当前版本里找不到了", systemImage: "questionmark.folder")
                .font(.headline)
            Text("回到今日，可以把这一项标记完成，或者去“雅思”页另选一题。")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Pages 今日 pushes inside its own navigation stack.
private enum TodayRoute: Hashable {
    case speaking(String)       // prompt id: basic speaking or a Part 2 cue card
    case writing(String)        // prompt id: basic writing, Task 1 or Task 2
    case baseline
    case studySettings(customBudget: Bool)
    case weekly(String)         // Monday of the week
}

private enum TodayBudgetChoice: Hashable {
    case sixty, ninety, custom
}

/// A comprehension check started from a plan task.
private struct TodayQuiz: Identifiable {
    var ref: ArticleRef
    var purpose: String
    var day: String
    var taskId: String
    var id: String { taskId + "|" + ref.key + "|" + purpose }
}

/// A short message above the plan; `taskId` offers 标记完成 for that task.
private struct TodayNotice {
    var text: String
    var day: String
    var taskId: String?
}
