import Foundation

/// Today's plan (PAGE-01, PLAN-P01…P05, ACC-12). Pure rules: the same inputs give the same plan,
/// and every task carries the reason it was chosen.
struct ReadingCandidate: Equatable, Sendable {
    var ref: ArticleRef
    var title: String
    var minutes: Double            // audio length
    var listened: Double           // 0…1 (去重播放覆盖, 90 % = 1)
    var lastOpened: Date?
    var difficulty: Int?           // the learner's own 1…5 rating; nil = unknown
    var firstUnpractisedSid: Int?  // first timed sentence without a 跟读 take
    var hasQuiz: Bool
    var readDay: String?           // day it was finished (for the next-day recall check)
    var checked: Bool              // a delayed / weekly check was already done
}

struct PlanInputs: Sendable {
    var day: String
    var now: Date
    var settings: StudySettings
    // 词汇
    var vocabBudgetMinutes: Double
    var vocabDue: Int
    var vocabEstSeconds: Double
    var vocabNewAllowed: Int
    var vocabBacklog: Bool
    var vocabItems: Int
    // 基线
    var baseline: BaselineState
    // 听读 / 跟读
    var reading: [ReadingCandidate]
    // 说写
    var dueRetests: [Retest]
    var nextSpeaking: (id: String, text: String)?
    var nextWriting: (id: String, text: String)?
    var outputDoneRecently: [String]         // day keys with independent speaking/writing work
    // 暂缓到今天的任务
    var deferred: [PlanTask]
    var lastWeeklyCheck: String?             // day of the last weekly new-material check
}

enum PlanEngine {
    /// PLAN-P01 split: 60 = 10/20/15/15, 90 = 10/30/15/35; other budgets keep 说写 first.
    static func split(budget: Int, vocabMinutes: Double) -> [StudyCategory: Int] {
        let vocab = Int(vocabMinutes.rounded())
        switch budget {
        case 60: return [.vocab: vocab, .read: 20 + (10 - vocab), .shadow: 15, .output: 15]
        case 90: return [.vocab: vocab, .read: 30 + (10 - vocab), .shadow: 15, .output: 35]
        default:
            let b = max(30, min(120, budget))
            let output = b >= 75 ? max(15, Int(Double(b) * 0.35)) : 15
            let shadow = b >= 45 ? 15 : 10
            let read = max(5, b - vocab - shadow - output)
            return [.vocab: vocab, .read: read, .shadow: shadow, .output: output]
        }
    }

    static func build(_ i: PlanInputs) -> PlanSnapshot {
        var notes: [String] = []
        var minutes = split(budget: i.settings.budgetMinutes, vocabMinutes: i.vocabBudgetMinutes)
        var tasks: [PlanTask] = []

        // 首次基线 takes part of today's time, never extra time (PLAN-P05).
        if !i.baseline.isDone {
            var take = min(20, max(0, (minutes[.read] ?? 0) - 5))
            minutes[.read, default: 0] -= take
            if take < 15 {
                // A small budget: the baseline also borrows from 跟读 so it gets at least 15 minutes.
                let borrow = min(minutes[.shadow] ?? 0, 15 - take)
                minutes[.shadow, default: 0] -= borrow
                take += borrow
            }
            tasks.append(PlanTask(id: "\(i.day)-baseline", cat: .read, minutes: take,
                                  title: "建立基线（第 \(i.baseline.sittings.count + 1) 次）",
                                  reason: "还没有基线：先做 \(4 - i.baseline.doneCount) 个小任务，看清现在的水平。每次 15–20 分钟，可以分 2–3 次做完；只给描述，不给雅思分。",
                                  target: .baseline))
            notes.append("基线占用今天的听读时间，不额外加时。")
        }

        // 说写先保留 (design: 先保留独立说写任务).
        if let retest = i.dueRetests.first {
            let what = retest.kind == "speaking" ? "口语" : (retest.kind == "writing" ? "写作" : "文章")
            tasks.append(PlanTask(id: "\(i.day)-output", cat: .output, minutes: minutes[.output] ?? 15,
                                  title: "\(what)新题复测",
                                  reason: "\(DayKey.distance(from: DayKey.of(retest.created), to: i.day)) 天前的作品有了反馈或重写。今天换一道同类新题，看改进能不能迁移；和同题重写分开记录。",
                                  target: .retest(id: retest.id)))
        } else if let deferredTask = i.deferred.first(where: { slot($0) == "output" }) {
            tasks.append(carry(deferredTask, day: i.day))
        } else {
            let speakingDay = (DayKey.distance(from: "2026-01-01", to: i.day) % 2 == 0)
            if speakingDay, let p = i.nextSpeaking {
                tasks.append(PlanTask(id: "\(i.day)-output", cat: .output, minutes: minutes[.output] ?? 15,
                                      title: "独立口语：\(p.text)",
                                      reason: "每天留一个独立作答的样本。今天轮到口语（隔天换写作）；先独立说，再自评，最后才看参考。",
                                      target: .speaking(promptId: p.id)))
            } else if let p = i.nextWriting {
                tasks.append(PlanTask(id: "\(i.day)-output", cat: .output, minutes: minutes[.output] ?? 15,
                                      title: "独立写作：\(p.text)",
                                      reason: "每天留一个独立作答的样本。今天轮到写作（隔天换口语）；原稿保存后只读，改写成新版本。",
                                      target: .writing(promptId: p.id)))
            } else if let p = i.nextSpeaking {
                tasks.append(PlanTask(id: "\(i.day)-output", cat: .output, minutes: minutes[.output] ?? 15,
                                      title: "独立口语：\(p.text)",
                                      reason: "每天留一个独立作答的样本。",
                                      target: .speaking(promptId: p.id)))
            }
        }

        // 词汇: due first; the queue itself holds the budget and the backlog rule.
        if i.vocabItems > 0 || i.vocabDue > 0 {
            var reason = i.vocabDue > 0
                ? "到期 \(i.vocabDue) 张，估计 \(max(1, Int((i.vocabEstSeconds / 60).rounded()))) 分钟；到期的先做。"
                : "今天没有到期的卡。"
            if i.vocabBacklog {
                reason += "最近两个学习日到期量都超过预算，今天建议不加新词，也不会把明天翻倍。"
                notes.append("积压：今天不加新词（可以在词汇页改）。")
            } else if i.vocabNewAllowed > 0 {
                reason += "预算里还能放 \(i.vocabNewAllowed) 个新任务。"
            }
            tasks.append(PlanTask(id: "\(i.day)-vocab", cat: .vocab, minutes: minutes[.vocab] ?? 10,
                                  title: i.vocabDue > 0 ? "词汇复习 \(i.vocabDue) 张" : "词汇：新任务",
                                  reason: reason, target: .vocabReview))
        }

        // 听读: unfinished short material first; a hard one can be swapped.
        let readMinutes = minutes[.read] ?? 20
        var shadowRef: ReadingCandidate?
        if let deferredTask = i.deferred.first(where: { slot($0) == "read" }) {
            tasks.append(carry(deferredTask, day: i.day))
        } else if let pick = pickReading(i.reading) {
            shadowRef = pick
            let left = max(1, pick.minutes * (1 - min(1, pick.listened)))
            var reason: String
            if pick.listened > 0.05 && pick.listened < 1 {
                reason = "上次听到 \(Int(pick.listened * 100))%，还剩约 \(Int(left.rounded())) 分钟。先继续没做完的材料。"
            } else {
                reason = "新材料，全长约 \(Int(pick.minutes.rounded())) 分钟"
                reason += pick.difficulty.map { "，你给的难度 \($0)/5。" } ?? "，难度还没评。"
            }
            if left > Double(readMinutes) {
                reason += "时间不够，今天只听前 \(readMinutes) 分钟，不延长学习。"
            }
            if let d = pick.difficulty, d >= 4 {
                reason += "如果太难，可以点“换一篇”。"
            }
            tasks.append(PlanTask(id: "\(i.day)-read", cat: .read, minutes: readMinutes, title: "听读：\(pick.title)",
                                  reason: reason, target: .article(issue: pick.ref.issue, id: pick.ref.id)))
        }

        // 延迟复测 (PLAN-P04): the day after finishing an article, recall it; once a week, new material.
        if let recall = i.reading.first(where: { $0.readDay != nil && !$0.checked && $0.hasQuiz &&
                                                  DayKey.distance(from: $0.readDay!, to: i.day) >= 1 }) {
            tasks.append(PlanTask(id: "\(i.day)-recall", cat: .read, minutes: 5, title: "隔日回忆：\(recall.title)",
                                  reason: "昨天或更早听完了这篇。隔一天再答 3 题，检查记住了多少；不重新听。",
                                  target: .articleCheck(issue: recall.ref.issue, id: recall.ref.id, purpose: "delayed")))
        }
        let weekDue = i.lastWeeklyCheck.map { DayKey.distance(from: $0, to: i.day) >= 7 } ?? true
        if weekDue, i.baseline.isDone,
           let fresh = i.reading.first(where: { $0.listened == 0 && $0.hasQuiz && $0.lastOpened == nil }) {
            tasks.append(PlanTask(id: "\(i.day)-weekly", cat: .read, minutes: 10, title: "本周新材料复测：\(fresh.title)",
                                  reason: "每周一篇没学过的同级材料：先只听一小段，再答题。看的是迁移，不是熟悉材料的记忆。",
                                  target: .articleCheck(issue: fresh.ref.issue, id: fresh.ref.id, purpose: "weekly")))
        }

        // 跟读: 1–2 short sentences from today's material (PLAN-P03).
        if let deferredTask = i.deferred.first(where: { slot($0) == "shadow" }) {
            tasks.append(carry(deferredTask, day: i.day))
        } else if let r = shadowRef ?? i.reading.first(where: { $0.firstUnpractisedSid != nil }) {
            tasks.append(PlanTask(id: "\(i.day)-shadow", cat: .shadow, minutes: minutes[.shadow] ?? 15,
                                  title: "跟读 1–2 个短句：\(r.title)",
                                  reason: "短句优先，每句 5–15 秒。练满 15 分钟就停，不反复刷同一句。",
                                  target: .shadow(issue: r.ref.issue, id: r.ref.id, sid: r.firstUnpractisedSid)))
        }

        if tasks.isEmpty {
            notes.append("还没有材料。先在书架导入内容包。")
        }
        return PlanSnapshot(day: i.day, tz: TimeZone.current.secondsFromGMT(for: i.now), created: i.now,
                            budget: i.settings.budgetMinutes, stage: i.settings.stage, tasks: order(tasks),
                            notes: notes, rulesVersion: PlanSnapshot.currentRules)
    }

    /// Unfinished and recently opened first, then new material that is not rated hard, shortest first.
    static func pickReading(_ list: [ReadingCandidate]) -> ReadingCandidate? {
        let unfinished = list.filter { $0.listened > 0.05 && $0.listened < 1 }
            .sorted { ($0.lastOpened ?? .distantPast) > ($1.lastOpened ?? .distantPast) }
        if let first = unfinished.first { return first }
        let fresh = list.filter { $0.listened <= 0.05 }
            .sorted { a, b in
                let da = a.difficulty ?? 3, db = b.difficulty ?? 3
                if da != db { return da < db }
                return a.minutes < b.minutes
            }
        return fresh.first
    }

    /// A task put off yesterday comes back once, with its own reason; the day's total stays the same.
    /// Only 听读, 跟读 and 说写 are carried; 基线, 回忆 and 每周复测 are planned again from the records.
    static func carry(_ t: PlanTask, day: String) -> PlanTask {
        var c = t
        c.id = "\(day)-\(slot(t))"
        c.state = .todo
        c.doneAt = nil
        c.deferredTo = nil
        c.reason = "昨天暂缓的任务。" + t.reason
        return c
    }

    /// The part of a task id after its day key: "2026-09-27-read" -> "read".
    static func slot(_ t: PlanTask) -> String {
        let parts = t.id.split(separator: "-", maxSplits: 3)
        return parts.count == 4 ? String(parts[3]) : t.cat.rawValue
    }

    /// Display order: 基线, 词汇, 听读, 跟读, 说写 (the plan keeps 说写 even when time is short).
    static func order(_ tasks: [PlanTask]) -> [PlanTask] {
        func rank(_ t: PlanTask) -> Int {
            if t.target == .baseline { return 0 }
            switch t.cat {
            case .vocab: return 1
            case .read: return 2
            case .shadow: return 3
            case .output: return 4
            }
        }
        return tasks.enumerated().sorted { a, b in
            let ra = rank(a.element), rb = rank(b.element)
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }
}
