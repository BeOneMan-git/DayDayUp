import Foundation

// 书架 data (PAGE-02, IMP-F06, IMP-F07): one entry per article with the facts the rows, the search and the
// filters need, and the grouped sections. Computed once per render, outside the view bodies.

/// 按刊期 / 按主题.
enum ShelfMode: String, CaseIterable, Identifiable {
    case issue, topic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .issue: return "按刊期"
        case .topic: return "按主题"
        }
    }
}

/// 听读进度 filter. "听读完成" = audio coverage ≥ 90 % (a completion definition, not "听懂").
enum ShelfProgress: String, CaseIterable, Identifiable {
    case all, unfinished, finished

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .unfinished: return "未完成"
        case .finished: return "听读完成"
        }
    }
}

/// Active filters (IMP-F07). In `difficulties`, 0 stands for 未评.
struct ShelfFilters: Equatable {
    var difficulties: Set<Int> = []
    var offline = false
    var calibration = false
    var favorites = false
    var progress: ShelfProgress = .all
    var topic: String? = nil

    var isActive: Bool {
        !difficulties.isEmpty || offline || calibration || favorites || progress != .all || topic != nil
    }
}

/// IMP-F06: the four kinds of state of one article.
struct ShelfStages: Equatable, Hashable {
    var contact = false     // 接触
    var listened = false    // 听读完成
    var shadowed = false    // 跟读练习
    var checked = false     // 独立复测
}

struct ShelfEntry: Identifiable, Equatable {
    var item: LibraryItem
    var difficulty: Int?          // the learner's own 1…5 rating; nil = 未评
    var listen: Double            // 0…1, full at 90 % coverage
    var read: Double              // 0…1, heard with the text on screen
    var stages: ShelfStages
    var offline: Bool             // text, audio and timing are all on this iPad
    var calibration: Bool         // the learner reported "音频对不上" (待校准)
    var quizAvailable: Bool
    var favorite: Bool

    var id: String { item.id }
    var ref: ArticleRef { item.ref }
}

struct ShelfSection: Identifiable {
    var id: String
    var title: String
    var entries: [ShelfEntry]
}

@MainActor
enum ShelfIndex {
    static let topicOrder = ["科技", "环境", "教育", "健康", "工作", "政府", "经济", "社会", "文化", "媒体", "国际", "交通"]
    static let untagged = "未分类"
    static let calibrationKind = "音频对不上"

    /// Every installed article, issues newest first, magazine order inside an issue.
    static func entries(packs: PackStore, user: UserStore, study: StudyStore, practice: PracticeStore) -> [ShelfEntry] {
        let shadowed = Set(practice.state.shadow.filter { !$0.silent }.map(\.article))
        let calibration = Set(practice.state.reports.filter { $0.kind == calibrationKind }.map(\.article))
        let quizzed = Set(study.state.quizResults.map(\.article))
        var seen = Set<String>()
        var out: [ShelfEntry] = []
        for group in packs.groups {
            for item in group.items {
                guard seen.insert(item.id).inserted else { continue }
                let key = item.ref.key
                let listen = user.state.listenProgress(key, duration: item.meta.dur)
                let read = user.state.readProgress(key, duration: item.meta.dur)
                let res = packs.resources(item.ref)
                var stages = ShelfStages()
                // Records older than V0.5 have no "opened" date: any listening also counts as 接触.
                stages.contact = study.state.articleOpened[key] != nil || listen > 0 || read > 0 || quizzed.contains(key)
                stages.listened = listen >= 1
                stages.shadowed = shadowed.contains(key)
                stages.checked = study.hasIndependentCheck(key)
                let offline = res.text == .available && res.audio == .available && res.timing == .available
                out.append(ShelfEntry(item: item, difficulty: study.difficulty(item.ref), listen: listen, read: read,
                                      stages: stages, offline: offline, calibration: calibration.contains(key),
                                      quizAvailable: res.quiz == .available,
                                      favorite: study.state.favorites[key] != nil))
            }
        }
        return out
    }

    /// The sections to show for a mode, a search text and the filters. Order is stable: issues newest first,
    /// topics in the usual order, "未分类" last; inside a section the magazine order is kept.
    static func sections(_ entries: [ShelfEntry], mode: ShelfMode, query: String, filters: ShelfFilters) -> [ShelfSection] {
        let terms = searchTerms(query)
        let shown = entries.filter { matches($0, terms: terms, filters: filters) }
        switch mode {
        case .issue:
            return issueSections(all: entries, shown: shown)
        case .topic:
            return topicSections(shown: shown, only: filters.topic)
        }
    }

    private static func issueSections(all: [ShelfEntry], shown: [ShelfEntry]) -> [ShelfSection] {
        var totals: [String: Int] = [:]
        for e in all { totals[e.ref.issue, default: 0] += 1 }
        var order: [String] = []
        var byIssue: [String: [ShelfEntry]] = [:]
        for e in shown {
            let issue = e.ref.issue
            if byIssue[issue] == nil { order.append(issue) }
            byIssue[issue, default: []].append(e)
        }
        return order.map { issue in
            let list = byIssue[issue] ?? []
            let total = totals[issue] ?? list.count
            let count = list.count == total ? "\(total) 篇" : "\(list.count) / \(total) 篇"
            return ShelfSection(id: "issue:" + issue, title: "\(issue) 期 · \(count)", entries: list)
        }
    }

    /// An article with several topics appears under each of them; one without topics under "未分类".
    private static func topicSections(shown: [ShelfEntry], only: String?) -> [ShelfSection] {
        var byTopic: [String: [ShelfEntry]] = [:]
        for e in shown {
            let topics = cleanTopics(e.item.meta.topics)
            for t in (topics.isEmpty ? [untagged] : topics) {
                if let only, only != t { continue }
                byTopic[t, default: []].append(e)
            }
        }
        return orderedTopics(Set(byTopic.keys)).map { t in
            let list = byTopic[t] ?? []
            return ShelfSection(id: "topic:" + t, title: "\(t) · \(list.count) 篇", entries: list)
        }
    }

    /// Topics present on the shelf, for the filter menu.
    static func topics(_ entries: [ShelfEntry]) -> [String] {
        var present = Set<String>()
        for e in entries {
            let topics = cleanTopics(e.item.meta.topics)
            if topics.isEmpty {
                present.insert(untagged)
            } else {
                present.formUnion(topics)
            }
        }
        return orderedTopics(present)
    }

    static func orderedTopics(_ present: Set<String>) -> [String] {
        let known = topicOrder.filter { present.contains($0) }
        let others = present.subtracting(topicOrder).subtracting([untagged]).sorted()
        let last = present.contains(untagged) ? [untagged] : []
        return known + others + last
    }

    /// Trimmed, non-empty, each topic once.
    static func cleanTopics(_ topics: [String]?) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for t in topics ?? [] {
            let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty && seen.insert(s).inserted { out.append(s) }
        }
        return out
    }

    /// Words of the search text (spaces at the ends are ignored; every word must match somewhere).
    static func searchTerms(_ query: String) -> [String] {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0) }
    }

    static func matches(_ e: ShelfEntry, terms: [String], filters: ShelfFilters) -> Bool {
        if !filters.difficulties.isEmpty && !filters.difficulties.contains(e.difficulty ?? 0) { return false }
        if filters.offline && !e.offline { return false }
        if filters.calibration && !e.calibration { return false }
        if filters.favorites && !e.favorite { return false }
        switch filters.progress {
        case .all:
            break
        case .unfinished:
            if e.listen >= 1 { return false }
        case .finished:
            if e.listen < 1 { return false }
        }
        if let topic = filters.topic {
            let topics = cleanTopics(e.item.meta.topics)
            let hit = topic == untagged ? topics.isEmpty : topics.contains(topic)
            if !hit { return false }
        }
        guard !terms.isEmpty else { return true }
        let fields = searchFields(e)
        return terms.allSatisfy { term in
            fields.contains { $0.localizedCaseInsensitiveContains(term) }
        }
    }

    /// Title, issue (also written 20260919 and 2026.09.19), section, fly title and topics.
    private static func searchFields(_ e: ShelfEntry) -> [String] {
        let meta = e.item.meta
        let issue = e.ref.issue
        var fields = [meta.title, issue, issue.replacingOccurrences(of: "-", with: ""),
                      issue.replacingOccurrences(of: "-", with: "."), meta.section]
        if let fly = meta.fly, !fly.isEmpty { fields.append(fly) }
        fields += cleanTopics(meta.topics)
        return fields
    }
}

/// The learner's own difficulty rating, in words (IMP-F07: unknown stays "未评").
enum ArticleDifficultyText {
    static let levels = [1, 2, 3, 4, 5]

    /// "难度 3/5" or "难度未评".
    static func label(_ value: Int?) -> String {
        guard let value else { return "难度未评" }
        return "难度 \(value)/5"
    }

    /// "3/5" or "未评".
    static func short(_ value: Int?) -> String {
        guard let value else { return "未评" }
        return "\(value)/5"
    }

    static func option(_ n: Int) -> String {
        switch n {
        case 1: return "1 · 很轻松"
        case 2: return "2 · 较轻松"
        case 3: return "3 · 适中"
        case 4: return "4 · 较难"
        default: return "5 · 很难"
        }
    }

    /// Filter menu entry: 0 = 未评.
    static func filterTitle(_ n: Int) -> String {
        n == 0 ? "未评" : "难度 \(n)"
    }
}
