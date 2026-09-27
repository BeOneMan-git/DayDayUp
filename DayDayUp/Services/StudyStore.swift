import Foundation
import Observation
import UserNotifications

/// Measures practice time from real learning actions (MET-01, ACC-30): a play, a recording, an answer,
/// a tap or typing extends the current stretch by up to one minute. Idle screen time is never counted;
/// audio that keeps playing while the app is off screen is recorded separately as background time.
@MainActor
final class ActivityClock {
    static let shared = ActivityClock()

    /// Set by the app from the selected tab; used when a caller does not name a category.
    /// nil on pages that are not practice (今日, 进展, 设置): their taps are not counted.
    var currentCategory: StudyCategory?
    /// Set by the app from the scene phase.
    var appActive = true
    /// Receives finished stretches (the StudyStore appends them to activity.jsonl).
    var sink: ((ActivityRecord) -> Void)?

    private struct Stretch {
        var cat: StudyCategory
        var start: Date
        var last: Date
        var background: Bool
        var source: String?
    }

    private var foreground: Stretch?
    private var background: Stretch?
    let window: TimeInterval = 60

    /// A learning action happened now (or over [from, now] for something that took time, like an answer).
    func touch(_ cat: StudyCategory? = nil, from: Date? = nil, source: String? = nil, at now: Date = Date()) {
        guard let category = cat ?? currentCategory else { return }
        let bg = !appActive
        let start = min(from ?? now, now)
        var slot = bg ? background : foreground
        if let s = slot, s.cat == category, start.timeIntervalSince(s.last) <= window {
            slot?.last = max(s.last, now)
        } else {
            if let s = slot { emit(s, at: start) }
            slot = Stretch(cat: category, start: start, last: now, background: bg, source: source)
        }
        if bg { background = slot } else { foreground = slot }
    }

    /// Ends open stretches (the app went to the background, or a day/tab change).
    func flush(at now: Date = Date()) {
        if let s = foreground { emit(s, at: now) }
        if let s = background, !appActive { emit(s, at: now) }
        foreground = nil
        if !appActive { background = nil }
    }

    /// Called when the app becomes active again: close what ran in the background.
    func flushBackground(at now: Date = Date()) {
        if let s = background { emit(s, at: now) }
        background = nil
    }

    private func emit(_ s: Stretch, at now: Date) {
        let end = min(now, s.last.addingTimeInterval(s.background ? 5 : window))
        guard end.timeIntervalSince(s.start) >= 3 else { return }
        sink?(ActivityRecord(cat: s.cat, start: s.start, end: end, background: s.background, source: s.source))
    }
}

/// Owns study.json (settings, daily plans, baseline, retests, quiz results) and activity.jsonl.
@MainActor
@Observable
final class StudyStore {
    private(set) var state: StudyState
    private(set) var activity: [ActivityRecord]
    private(set) var saveError: String?
    private(set) var reminderStatus: String?

    let fileURL: URL
    let activityURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent("study.json")
        activityURL = support.appendingPathComponent("activity.jsonl")
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? DataCoding.decoder.decode(StudyState.self, from: data) {
            state = loaded
        } else {
            state = StudyState()
            if fm.fileExists(atPath: fileURL.path) {
                let copy = support.appendingPathComponent("study-unreadable-\(Int(Date().timeIntervalSince1970)).json")
                try? fm.copyItem(at: fileURL, to: copy)
                DiagLog.shared.log("study", "study.json unreadable, copied to \(copy.lastPathComponent)")
            }
        }
        activity = JSONLines<ActivityRecord>(url: activityURL).readAll().records
        ActivityClock.shared.sink = { [weak self] record in self?.log(record) }
    }

    var settings: StudySettings { state.settings }

    // MARK: Saving

    func update(_ change: (inout StudyState) -> Void) {
        var copy = state
        change(&copy)
        guard copy != state else { return }
        state = copy
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            self?.saveNow()
        }
    }

    func updateSettings(_ change: (inout StudySettings) -> Void) {
        update { change(&$0.settings) }
    }

    func saveNow() {
        saveTask?.cancel()
        do {
            let data = try DataCoding.encoder.encode(state)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            saveError = nil
        } catch {
            saveError = error.localizedDescription
            DiagLog.shared.log("study", "save failed: \(error.localizedDescription)")
        }
    }

    // MARK: Activity (MET-01, DATA-11)

    func log(_ record: ActivityRecord) {
        do {
            try JSONLines<ActivityRecord>(url: activityURL).append([record])
        } catch {
            DiagLog.shared.log("study", "activity append failed: \(error.localizedDescription)")
        }
        activity.append(record)
    }

    func minutes(days: [String]) -> [Metrics.DayMinutes] {
        Metrics.minutes(activity, days: days)
    }

    // MARK: Plans (PAGE-01, DATA-11)

    func plan(for day: String) -> PlanSnapshot? { state.plans[day] }

    /// Stores today's plan the first time it is made; later calls keep the stored snapshot.
    @discardableResult
    func ensurePlan(_ make: () -> PlanSnapshot) -> PlanSnapshot {
        let today = DayKey.today
        if let p = state.plans[today] { return p }
        let p = make()
        update { $0.plans[today] = p }
        saveNow()
        return p
    }

    /// Replaces one task of today's plan (换一篇, or a rebuilt task).
    func replaceTask(day: String, _ task: PlanTask) {
        update { s in
            guard var p = s.plans[day], let i = p.tasks.firstIndex(where: { $0.id == task.id }) else { return }
            p.tasks[i] = task
            s.plans[day] = p
        }
    }

    /// Marks a task done once; tapping again does not count twice (ACC-30).
    func markDone(day: String, taskId: String, at date: Date = Date()) {
        update { s in
            guard var p = s.plans[day], let i = p.tasks.firstIndex(where: { $0.id == taskId }) else { return }
            guard p.tasks[i].state != .done else { return }
            p.tasks[i].state = .done
            p.tasks[i].doneAt = date
            s.plans[day] = p
        }
    }

    /// 暂缓: the task moves to tomorrow once; the day after it is not doubled.
    func deferTask(day: String, taskId: String) {
        let tomorrow = DayKey.adding(1, to: day)
        update { s in
            guard var p = s.plans[day], let i = p.tasks.firstIndex(where: { $0.id == taskId }) else { return }
            p.tasks[i].state = .deferred
            p.tasks[i].deferredTo = tomorrow
            s.plans[day] = p
        }
    }

    func reopen(day: String, taskId: String) {
        update { s in
            guard var p = s.plans[day], let i = p.tasks.firstIndex(where: { $0.id == taskId }) else { return }
            p.tasks[i].state = .todo
            p.tasks[i].doneAt = nil
            p.tasks[i].deferredTo = nil
            s.plans[day] = p
        }
    }

    /// Tasks put off to `day` from the day before.
    func deferred(to day: String) -> [PlanTask] {
        let yesterday = DayKey.adding(-1, to: day)
        return (state.plans[yesterday]?.tasks ?? []).filter { $0.state == .deferred && $0.deferredTo == day }
    }

    /// Drops today's stored plan so it is made again (after a budget change).
    func resetPlan(day: String) {
        update { $0.plans[day] = nil }
    }

    // MARK: Baseline (DIAG-01)

    func updateBaseline(_ change: (inout BaselineState) -> Void) {
        update { s in
            change(&s.baseline)
            if s.baseline.started == nil { s.baseline.started = Date() }
            let today = DayKey.today
            if !s.baseline.sittings.contains(where: { DayKey.of($0) == today }) {
                s.baseline.sittings.append(Date())
            }
            if s.baseline.isDone && s.baseline.finished == nil { s.baseline.finished = Date() }
        }
        saveNow()
    }

    // MARK: Retests (IEL-F04, IEL-P07, PLAN-P04)

    /// Schedules one new-prompt retest for a work that got feedback or a rewrite (3–7 days later).
    func scheduleRetest(kind: String, sourceId: String, afterDays: Int = 4) {
        guard !state.retests.contains(where: { $0.sourceId == sourceId && $0.done == nil }) else { return }
        let r = Retest(id: UUID().uuidString, kind: kind, sourceId: sourceId,
                       due: DayKey.adding(min(7, max(3, afterDays)), to: DayKey.today), created: Date(),
                       promptId: nil, done: nil, resultId: nil)
        update { $0.retests.append(r) }
        saveNow()
    }

    func dueRetests(on day: String = DayKey.today) -> [Retest] {
        state.retests.filter { $0.done == nil && $0.due <= day }.sorted { $0.due < $1.due }
    }

    func retest(_ id: String) -> Retest? { state.retests.first { $0.id == id } }

    func setRetestPrompt(_ id: String, promptId: String) {
        update { s in
            if let i = s.retests.firstIndex(where: { $0.id == id }) { s.retests[i].promptId = promptId }
        }
    }

    func completeRetest(_ id: String, resultId: String) {
        update { s in
            guard let i = s.retests.firstIndex(where: { $0.id == id }), s.retests[i].done == nil else { return }
            s.retests[i].done = Date()
            s.retests[i].resultId = resultId
        }
        saveNow()
    }

    // MARK: Articles and quizzes

    func noteOpened(_ ref: ArticleRef) {
        guard state.articleOpened[ref.key] == nil else { return }
        update { $0.articleOpened[ref.key] = Date() }
    }

    func noteFinished(_ ref: ArticleRef) {
        guard state.articleFinished[ref.key] == nil else { return }
        update { $0.articleFinished[ref.key] = Date() }
    }

    /// A retest the learner started from 今日; the next new work of that kind completes it.
    @ObservationIgnored var activeRetest: String?

    func difficulty(_ ref: ArticleRef) -> Int? { state.articleDifficulty[ref.key] }

    func setDifficulty(_ ref: ArticleRef, _ value: Int?) {
        update { $0.articleDifficulty[ref.key] = value.map { min(5, max(1, $0)) } }
    }

    func addQuizResult(_ r: QuizResult) {
        update { $0.quizResults.append(r) }
        saveNow()
    }

    func quizResults(article key: String) -> [QuizResult] {
        state.quizResults.filter { $0.article == key }.sorted { $0.at > $1.at }
    }

    /// Delayed or weekly checks done for this article (IMP-F06 "独立复测").
    func hasIndependentCheck(_ key: String) -> Bool {
        state.quizResults.contains { $0.article == key && ($0.purpose == "delayed" || $0.purpose == "weekly") }
    }

    var lastWeeklyCheck: String? {
        state.quizResults.filter { $0.purpose == "weekly" }.map(\.day).max()
    }

    // MARK: Weekly report (MET-P03)

    /// On a Monday (or later in the week, if missed), last week's report is due once.
    func weekDueForReport(today: String = DayKey.today) -> String? {
        let thisMonday = DayKey.weekStart(today)
        let lastMonday = DayKey.adding(-7, to: thisMonday)
        return state.weeklyReports[lastMonday] == nil ? lastMonday : nil
    }

    func markReportPrepared(_ week: String) {
        update { $0.weeklyReports[week] = Date() }
    }

    func retractIssue(_ id: String, _ retract: Bool) {
        update { s in
            if retract {
                if !s.retractedIssues.contains(id) { s.retractedIssues.append(id) }
            } else {
                s.retractedIssues.removeAll { $0 == id }
            }
        }
    }

    // MARK: Reminders (PLAN-P06)

    /// Applies the reminder setting: off by default; at most one reminder a day; none inside quiet hours.
    func applyReminder() async {
        let s = state.settings
        let center = UNUserNotificationCenter.current()
        let id = "ddu.daily"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard s.reminderOn else {
            reminderStatus = "提醒已关闭。"
            return
        }
        if let qs = s.quietStartHour, let qe = s.quietEndHour, QuietHours.contains(hour: s.reminderHour, start: qs, end: qe) {
            reminderStatus = "提醒时间在静默时段里，所以没有设置。请换一个时间。"
            return
        }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else {
            reminderStatus = "系统没有允许通知。可以在“设置 › 通知 › DayDayUp”里打开。"
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "DayDayUp"
        content.body = "今天的学习计划在“今日”页。"
        content.sound = .default
        var comps = DateComponents()
        comps.hour = s.reminderHour
        comps.minute = s.reminderMinute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        do {
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            reminderStatus = String(format: "每天 %02d:%02d 提醒一次。", s.reminderHour, s.reminderMinute)
        } catch {
            reminderStatus = "提醒没有设置成功：\(error.localizedDescription)"
        }
    }

    // MARK: Backup

    func backupFiles() throws -> [(name: String, data: Data)] {
        [(name: "study.json", data: try DataCoding.encoder.encode(state)),
         (name: "activity.jsonl", data: try JSONLines<ActivityRecord>.encode(activity))]
    }

    func restore(study: Data?, activity activityData: Data?) throws {
        if let study {
            let restored = try DataCoding.decoder.decode(StudyState.self, from: study)
            try study.write(to: fileURL, options: .atomic)
            state = restored
        }
        if let activityData {
            let records = JSONLines<ActivityRecord>.decode(activityData).records
            try activityData.write(to: activityURL, options: .atomic)
            activity = records
        }
    }
}
