import Foundation

/// Today's review queue under a time budget (VOC-P02/P03/P04, PLAN-P02).
/// Due cards come first and stay due until answered; new tasks only fill time that is left.
struct VocabQueue: Equatable {
    struct Entry: Identifiable, Equatable {
        enum Reason: Equatable {
            case learning               // a short learning step (1 or 10 minutes) is due
            case due(overdueDays: Int)  // a review is due
            case new(rank: Int)         // a new task, n-th of today
        }

        var card: VocabCard
        var reason: Reason
        var id: String { card.id }
    }

    var entries: [Entry] = []
    var dueCount = 0
    var laterToday = 0              // learning steps that come back later today
    var newCount = 0
    var estDueSeconds: Double = 0
    var estNewSeconds: Double = 0
    var budgetSeconds: Double = 600
    var spentSeconds: Double = 0
    var newLimit = 5
    var newDoneToday = 0
    var newAllowed = 0
    var backlogSuggestsZero = false
    var backlogOverridden = false
    var explanation: [String] = []

    var overBudget: Bool { spentSeconds >= budgetSeconds }
}

enum VocabQueueBuilder {
    /// Median seconds per task over the last 50 answers (3–300 s); default when there are fewer than 5.
    static func estimates(from events: [ReviewEvent]) -> [VocabTask: Double] {
        var out: [VocabTask: Double] = [:]
        for task in VocabTask.allCases {
            let values = events
                .filter { $0.kind == .review && $0.task == task }
                .suffix(50)
                .compactMap { $0.durationMs }
                .map { min(300, max(3, Double($0) / 1000)) }
                .sorted()
            if values.count >= 5 {
                let mid = values.count / 2
                out[task] = values.count % 2 == 1 ? values[mid] : (values[mid - 1] + values[mid]) / 2
            } else {
                out[task] = task.defaultSeconds
            }
        }
        return out
    }

    /// Reviews of today that were not taken back.
    static func activeReviews(_ events: [ReviewEvent]) -> [ReviewEvent] {
        let undone = Set(events.filter { $0.kind == .undo }.compactMap { $0.undoes })
        return events.filter { $0.kind == .review && !undone.contains($0.id) }
    }

    /// VOC-P04: today and the previous study day both started over budget.
    static func backlogSuggestion(days: [String: VocabDay], today: String) -> Bool {
        guard let now = days[today], now.overBudget else { return false }
        let previous = days.keys.filter { $0 < today && days[$0]?.studied == true }.max()
        guard let previous, let day = days[previous] else { return false }
        return day.overBudget
    }

    static func build(cards: [VocabCard],
                      settings: VocabSettings,
                      now: Date,
                      today: String,
                      todayEvents: [ReviewEvent],
                      estimates: [VocabTask: Double],
                      days: [String: VocabDay],
                      keepNewOn: String?,
                      calendar: Calendar = .current) -> VocabQueue {
        var q = VocabQueue()
        q.budgetSeconds = settings.budgetMinutes * 60
        q.newLimit = settings.newPerDay

        let reviews = activeReviews(todayEvents)
        q.spentSeconds = reviews.compactMap { $0.durationMs }.reduce(0) { $0 + Double($1) / 1000 }
        q.newDoneToday = reviews.filter { $0.before?.isNew == true }.count

        let active = cards.filter { !$0.suspended }
        let endOfDay = calendar.startOfDay(for: now).addingTimeInterval(86_400)

        // Due now: learning steps first (they are short), then reviews, oldest due first.
        let dueNow = active.filter { !$0.isNew && $0.fsrs.due <= now }
        let learning = dueNow.filter { $0.fsrs.state != .review }.sorted { $0.fsrs.due < $1.fsrs.due }
        let review = dueNow.filter { $0.fsrs.state == .review }.sorted { $0.fsrs.due < $1.fsrs.due }
        for card in learning {
            q.entries.append(.init(card: card, reason: .learning))
        }
        for card in review {
            let overdue = max(0, FSRSScheduler.wholeDays(from: card.fsrs.due, to: now))
            q.entries.append(.init(card: card, reason: .due(overdueDays: overdue)))
        }
        q.dueCount = dueNow.count
        q.laterToday = active.filter { !$0.isNew && $0.fsrs.due > now && $0.fsrs.due < endOfDay }.count
        q.estDueSeconds = dueNow.reduce(0) { $0 + (estimates[$1.task] ?? $1.task.defaultSeconds) }

        // New tasks: only what fits in the budget, only up to today's limit.
        let newCards = active.filter { $0.isNew }.sorted {
            if $0.created != $1.created { return $0.created < $1.created }
            return VocabTask.allCases.firstIndex(of: $0.task)! < VocabTask.allCases.firstIndex(of: $1.task)!
        }
        q.backlogSuggestsZero = backlogSuggestion(days: days, today: today)
        q.backlogOverridden = q.backlogSuggestsZero && keepNewOn == today
        var allowed = max(0, settings.newPerDay - q.newDoneToday)
        if q.backlogSuggestsZero && !q.backlogOverridden {
            allowed = 0
        }
        let left = q.budgetSeconds - q.spentSeconds - q.estDueSeconds
        var picked: [VocabCard] = []
        var used: Double = 0
        for card in newCards where picked.count < allowed {
            let cost = estimates[card.task] ?? card.task.defaultSeconds
            if used + cost > left { break }
            picked.append(card)
            used += cost
        }
        q.newAllowed = picked.count
        q.newCount = newCards.count
        q.estNewSeconds = used
        for (n, card) in picked.enumerated() {
            q.entries.append(.init(card: card, reason: .new(rank: q.newDoneToday + n + 1)))
        }

        q.explanation = explain(q)
        return q
    }

    static func explain(_ q: VocabQueue) -> [String] {
        func minutes(_ s: Double) -> String {
            s < 60 ? "不到 1 分钟" : "约 \(Int((s / 60).rounded())) 分钟"
        }
        var lines: [String] = []
        lines.append("今天已用 \(minutes(q.spentSeconds))，预算 \(Int(q.budgetSeconds / 60)) 分钟（复习和新任务一起算）。")
        if q.dueCount > 0 {
            lines.append("到期 \(q.dueCount) 张，估计\(minutes(q.estDueSeconds))。到期的先做；没做完的明天还在，不会顺延。")
        } else {
            lines.append("今日暂无到期。")
        }
        if q.laterToday > 0 {
            lines.append("还有 \(q.laterToday) 张在学习步里（1 或 10 分钟后再出现）。")
        }
        if q.backlogSuggestsZero && !q.backlogOverridden {
            lines.append("最近两个学习日，开始时的到期量都超过预算，所以建议今天不加新任务。你可以改。")
        } else if q.newAllowed > 0 {
            lines.append("新任务：今天还放 \(q.newAllowed) 个（上限 \(q.newLimit)，已学 \(q.newDoneToday)）。一个义项或词群的一种题型算 1 个。")
        } else if q.newCount > 0 && q.newDoneToday >= q.newLimit {
            lines.append("新任务：今天的 \(q.newLimit) 个已经学完。")
        } else if q.newCount > 0 {
            lines.append("新任务：预算里没有剩余时间，今天先不加。")
        }
        return lines
    }
}
