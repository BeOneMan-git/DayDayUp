import Foundation

// REC-KEEP 录音保留与清理: "默认不自动删；设置页显示占用；清理先预览（保留首次、最近 3 次、收藏、复测和作品关联的
// 录音），确认后才删；删文件不删记录（标“录音已清理”）."
//
// Where recording file names are stored (all in Application Support/Recordings/):
// - practice.json: ShadowAttempt.file and .followFile (跟读, 脱稿复述 follow-up), SpeakingWork.file (口语, Part 2,
//   完整模拟, 基线). MockSession.answers, SpeakingWork.retestOf / .mockId / .feedback say which works matter.
// - vocab-events.jsonl: ReviewEvent.evidence (例句朗读 takes; a written answer id never matches a file).
// - study.json: BaselineState.speaking.refId and Retest.sourceId / .resultId point at SpeakingWork ids.
// Nothing here changes a record. Missing files are shown by the pages that play them.

/// Why a recording file is kept. One file can have several reasons.
enum RecordingKeepReason: String, CaseIterable, Identifiable {
    case first, recent, favorite, retest, feedback, mock, baseline, vocab

    var id: String { rawValue }

    var title: String {
        switch self {
        case .first: return "首次"
        case .recent: return "最近 3 次"
        case .favorite: return "收藏"
        case .retest: return "复测"
        case .feedback: return "作品有反馈"
        case .mock: return "模拟考试"
        case .baseline: return "基线"
        case .vocab: return "词汇证据"
        }
    }

    var detail: String {
        switch self {
        case .first: return "同一句（同一种跟读方式）或同一道口语题，第一次录到声音的那个。"
        case .recent: return "同一句或同一道口语题，最近录到声音的 3 个。"
        case .favorite: return "在书架上收藏的文章，它的跟读录音全部保留。"
        case .retest: return "新题复测的作品，和拿来对照的原作品。"
        case .feedback: return "录入过老师或 Claude 反馈的口语作品。"
        case .mock: return "口语完整模拟里的每一题。"
        case .baseline: return "首次基线的无准备录音。"
        case .vocab: return "词汇“例句朗读”作答时保存的录音。"
        }
    }

    var symbol: String {
        switch self {
        case .first: return "1.circle"
        case .recent: return "clock.arrow.circlepath"
        case .favorite: return "star"
        case .retest: return "arrow.triangle.2.circlepath"
        case .feedback: return "text.bubble"
        case .mock: return "list.number"
        case .baseline: return "list.bullet.clipboard"
        case .vocab: return "character.book.closed"
        }
    }
}

/// One .m4a file in the Recordings folder.
struct RecordingFileInfo: Identifiable, Hashable {
    let name: String
    let bytes: Int
    let modified: Date?

    var id: String { name }

    static func totalBytes(_ files: [RecordingFileInfo]) -> Int {
        files.reduce(0) { $0 + $1.bytes }
    }
}

/// One group the "首次 / 最近 3 次" rule works on: a 跟读 sentence (or segment) in one mode, or one 口语 prompt.
struct RecordingCleanupGroup: Identifiable {
    enum Kind: Equatable {
        case shadow, speaking
    }

    let id: String
    let kind: Kind
    /// 跟读: the article (ArticleRef.key), so the page can show its title.
    let articleKey: String?
    /// 跟读 mode or 口语 part, in Chinese.
    let label: String
    /// 跟读: the sentence as it was practised; 口语: the question.
    let text: String
    let kept: [RecordingFileInfo]
    let candidates: [RecordingFileInfo]

    var candidateBytes: Int { RecordingFileInfo.totalBytes(candidates) }
}

/// The preview: what stays, what would be deleted, and files no record points at.
struct CleanupPlan {
    let made: Date
    /// Every recording file on the iPad.
    let onDisk: [RecordingFileInfo]
    let kept: [RecordingFileInfo]
    /// Kept file name -> why it is kept.
    let reasons: [String: Set<RecordingKeepReason>]
    /// Files a record points at, that no rule keeps. Only these are deleted (plus unlinked files, if chosen).
    let candidates: [RecordingFileInfo]
    /// Files in the folder that no record points at (the app cannot play them anywhere).
    let unlinked: [RecordingFileInfo]
    /// Unlinked files written in the last minutes: may still be in use, never touched.
    let recentUnlinked: Int
    /// References in the records whose file is not on the iPad (cleaned earlier, or not restored).
    let missingFiles: Int
    /// Groups where something would be deleted, the most first.
    let groups: [RecordingCleanupGroup]

    var totalBytes: Int { RecordingFileInfo.totalBytes(onDisk) }
    var keptBytes: Int { RecordingFileInfo.totalBytes(kept) }
    var candidateBytes: Int { RecordingFileInfo.totalBytes(candidates) }
    var unlinkedBytes: Int { RecordingFileInfo.totalBytes(unlinked) }

    /// Kept files that have this reason (a file with several reasons counts for each).
    func keptCount(_ reason: RecordingKeepReason) -> Int {
        reasons.values.filter { $0.contains(reason) }.count
    }
}

/// Builds the cleanup preview and deletes only what the learner confirmed. Never called automatically.
@MainActor
enum RecordingCleanup {
    /// "最近 3 次".
    static let recentCount = 3
    /// A file no record points at yet may be a take that is still being recorded or saved.
    static let unlinkedGrace: TimeInterval = 10 * 60

    /// The preview. Reads the Recordings folder and the records; changes nothing.
    static func plan(practice: PracticeStore, vocab: VocabStore, study: StudyStore, now: Date = Date()) -> CleanupPlan {
        let files = listFiles(in: practice.recordingsDir)
        let evidence = Set(vocab.events.compactMap { $0.evidence }.filter { !$0.isEmpty })
        return make(practice: practice.state, vocabEvidence: evidence, study: study.state, files: files, now: now)
    }

    /// Deletes the plan's candidate files (and its unlinked files when `includeUnlinked`), never a record.
    /// The rules run again first: a file that became protected since the preview (or is no longer a candidate)
    /// is skipped.
    @discardableResult
    static func apply(_ plan: CleanupPlan, practice: PracticeStore, vocab: VocabStore, study: StudyStore,
                      includeUnlinked: Bool) -> (deleted: Int, bytes: Int) {
        let fresh = RecordingCleanup.plan(practice: practice, vocab: vocab, study: study)
        var allowed = Set(plan.candidates.map(\.name)).intersection(fresh.candidates.map(\.name))
        if includeUnlinked {
            let unlinked = Set(plan.unlinked.map(\.name)).intersection(fresh.unlinked.map(\.name))
            allowed.formUnion(unlinked)
        }
        let fm = FileManager.default
        var deleted = 0
        var bytes = 0
        for name in allowed.sorted() where isRecordingName(name) {
            let url = practice.recordingsDir.appendingPathComponent(name)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            do {
                try fm.removeItem(at: url)
                deleted += 1
                bytes += size
            } catch {
                DiagLog.shared.log("recordings", "cleanup could not delete \(name): \(error.localizedDescription)")
            }
        }
        DiagLog.shared.log("recordings", "cleanup deleted \(deleted) files, \(bytes) bytes, unlinked included: \(includeUnlinked)")
        return (deleted, bytes)
    }

    /// A plain recording file name inside the folder (no path parts).
    static func isRecordingName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.hasPrefix(".") && name.lowercased().hasSuffix(".m4a")
    }

    /// .m4a files in the folder, by name.
    static func listFiles(in dir: URL) -> [String: RecordingFileInfo] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys,
                                                                   options: [.skipsHiddenFiles])) ?? []
        var out: [String: RecordingFileInfo] = [:]
        for url in urls where url.pathExtension.lowercased() == "m4a" {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let name = url.lastPathComponent
            out[name] = RecordingFileInfo(name: name, bytes: values?.fileSize ?? 0,
                                          modified: values?.contentModificationDate)
        }
        return out
    }

    // MARK: Rules

    /// The rules on plain values: who points at which file, and which files stay.
    static func make(practice p: PracticeState, vocabEvidence: Set<String>, study s: StudyState,
                     files: [String: RecordingFileInfo], now: Date) -> CleanupPlan {
        var collector = CleanupCollector(files: files)
        collectShadow(p.shadow, favorites: Set(s.favorites.keys), into: &collector)
        collectSpeaking(p, study: s, into: &collector)

        var reasons: [String: Set<RecordingKeepReason>] = [:]
        for name in vocabEvidence {
            if files[name] != nil {
                collector.referenced.insert(name)
                reasons[name, default: []].insert(.vocab)
            } else if name.lowercased().hasSuffix(".m4a") {
                collector.missing += 1
            }
        }
        applyGroupRules(collector, into: &reasons)

        var kept: [RecordingFileInfo] = []
        var keptReasons: [String: Set<RecordingKeepReason>] = [:]
        var candidates: [RecordingFileInfo] = []
        var unlinked: [RecordingFileInfo] = []
        var recentUnlinked = 0
        let onDisk = files.values.sorted { $0.name < $1.name }
        for info in onDisk {
            if let why = reasons[info.name] {
                if why.isEmpty {
                    candidates.append(info)
                } else {
                    kept.append(info)
                    keptReasons[info.name] = why
                }
            } else if collector.referenced.contains(info.name) {
                kept.append(info)       // a record points at it but no rule looked at it: keep, to be safe
            } else if let modified = info.modified, now.timeIntervalSince(modified) < unlinkedGrace {
                recentUnlinked += 1
            } else {
                unlinked.append(info)
            }
        }
        return CleanupPlan(made: now, onDisk: onDisk, kept: kept, reasons: keptReasons, candidates: candidates,
                           unlinked: unlinked, recentUnlinked: recentUnlinked, missingFiles: collector.missing,
                           groups: summarize(collector, reasons: reasons))
    }

    /// 跟读: one group per sentence (or segment) and mode. A 脱稿复述 follow-up answer goes with its take.
    private static func collectShadow(_ list: [ShadowAttempt], favorites: Set<String>,
                                      into collector: inout CleanupCollector) {
        for a in list {
            let names = collector.present([a.file, a.followFile])
            guard !names.isEmpty else { continue }
            var why = Set<RecordingKeepReason>()
            if favorites.contains(a.article) { why.insert(.favorite) }
            let end = a.endSid ?? a.sid
            let group = "sh|\(a.article)#\(a.sid)-\(end)|\(a.mode)"
            let take = CleanupTake(files: names, created: a.created, voiced: !a.silent, reasons: why)
            let info = CleanupGroupInfo(kind: .shadow, articleKey: a.article, label: shadowLabel(a), text: a.text)
            collector.add(take, group: group, info: info)
        }
    }

    /// 口语: one group per prompt. Mock answers, retests (and their sources), works with feedback and the
    /// baseline recording are always kept.
    private static func collectSpeaking(_ p: PracticeState, study s: StudyState, into collector: inout CleanupCollector) {
        let mockAnswers = Set(p.mocks.flatMap { $0.answers })
        var retestWorks = Set<String>()
        for r in s.retests {
            retestWorks.insert(r.sourceId)
            if let result = r.resultId { retestWorks.insert(result) }
        }
        for w in p.speaking {
            if let source = w.retestOf {
                retestWorks.insert(source)
                retestWorks.insert(w.id)
            }
        }
        let baselineWork = s.baseline.speaking?.refId
        for w in p.speaking {
            let names = collector.present([w.file])
            guard !names.isEmpty else { continue }
            var why = Set<RecordingKeepReason>()
            if w.mockId != nil || mockAnswers.contains(w.id) { why.insert(.mock) }
            if retestWorks.contains(w.id) { why.insert(.retest) }
            if !w.feedback.isEmpty { why.insert(.feedback) }
            if w.id == baselineWork || w.promptId.hasPrefix("baseline") { why.insert(.baseline) }
            let take = CleanupTake(files: names, created: w.created, voiced: !w.silent, reasons: why)
            let info = CleanupGroupInfo(kind: .speaking, articleKey: nil, label: speakingLabel(w), text: w.question)
            collector.add(take, group: "sp|" + w.promptId, info: info)
        }
    }

    /// 首次 = the earliest take with voice; 最近 3 次 = the newest 3 with voice. Takes that only caught silence
    /// count only when a group has nothing else. Only takes whose files are still on the iPad are looked at.
    private static func applyGroupRules(_ collector: CleanupCollector,
                                        into reasons: inout [String: Set<RecordingKeepReason>]) {
        for list in collector.takes.values {
            let sorted = list.sorted { $0.created < $1.created }
            let voiced = sorted.indices.filter { sorted[$0].voiced }
            let pool: [Int] = voiced.isEmpty ? Array(sorted.indices) : voiced
            var extra: [Int: Set<RecordingKeepReason>] = [:]
            if let first = pool.first {
                extra[first, default: []].insert(.first)
            }
            for i in pool.suffix(recentCount) {
                extra[i, default: []].insert(.recent)
            }
            for (i, take) in sorted.enumerated() {
                let why = take.reasons.union(extra[i] ?? [])
                for name in take.files {
                    reasons[name, default: []].formUnion(why)
                }
            }
        }
    }

    private static func summarize(_ collector: CleanupCollector,
                                  reasons: [String: Set<RecordingKeepReason>]) -> [RecordingCleanupGroup] {
        var out: [RecordingCleanupGroup] = []
        for (key, list) in collector.takes {
            guard let info = collector.info[key] else { continue }
            let names = Set(list.flatMap { $0.files })
            var kept: [RecordingFileInfo] = []
            var candidates: [RecordingFileInfo] = []
            for name in names.sorted() {
                guard let file = collector.files[name] else { continue }
                let why = reasons[name] ?? []
                if why.isEmpty {
                    candidates.append(file)
                } else {
                    kept.append(file)
                }
            }
            guard !candidates.isEmpty else { continue }
            out.append(RecordingCleanupGroup(id: key, kind: info.kind, articleKey: info.articleKey, label: info.label,
                                             text: info.text, kept: kept, candidates: candidates))
        }
        return out.sorted { a, b in
            if a.candidates.count != b.candidates.count { return a.candidates.count > b.candidates.count }
            return a.id < b.id
        }
    }

    private static func shadowLabel(_ a: ShadowAttempt) -> String {
        let mode = ShadowMode(rawValue: a.mode)?.title ?? a.mode
        if let end = a.endSid, end != a.sid {
            return mode + " · 一段"
        }
        return mode
    }

    private static func speakingLabel(_ w: SpeakingWork) -> String {
        if w.promptId.hasPrefix("baseline") { return "基线录音" }
        let part: String
        switch w.part {
        case "p1": part = "Part 1"
        case "p2": part = "Part 2"
        case "p3": part = "Part 3"
        default: part = "基础口语"
        }
        return w.mockId == nil ? part : "完整模拟 · " + part
    }
}

// MARK: Working values

/// One take (or one spoken answer) with the files of it that are on the iPad.
private struct CleanupTake {
    let files: [String]
    let created: Date
    let voiced: Bool
    /// Reasons that come from the record itself (收藏, 复测, 反馈, 模拟, 基线).
    let reasons: Set<RecordingKeepReason>
}

private struct CleanupGroupInfo {
    let kind: RecordingCleanupGroup.Kind
    let articleKey: String?
    let label: String
    let text: String
}

private struct CleanupCollector {
    let files: [String: RecordingFileInfo]
    var referenced = Set<String>()
    var missing = 0
    var takes: [String: [CleanupTake]] = [:]
    var info: [String: CleanupGroupInfo] = [:]

    init(files: [String: RecordingFileInfo]) {
        self.files = files
    }

    /// Notes the file names a record points at; returns the ones that are on the iPad.
    mutating func present(_ names: [String?]) -> [String] {
        var out: [String] = []
        for item in names {
            guard let name = item, !name.isEmpty else { continue }
            referenced.insert(name)
            if files[name] == nil {
                missing += 1
            } else {
                out.append(name)
            }
        }
        return out
    }

    mutating func add(_ take: CleanupTake, group: String, info groupInfo: CleanupGroupInfo) {
        takes[group, default: []].append(take)
        if info[group] == nil {
            info[group] = groupInfo
        }
    }
}
