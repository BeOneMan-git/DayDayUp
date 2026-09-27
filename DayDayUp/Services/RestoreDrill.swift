import Foundation

// Restore drill (DATA-RS, ACC-26, ACC-27):
// 选备份 → 在临时库解开并逐个文件解码 → 显示记录数和缺失依赖（缺哪些内容包、缺哪些录音）→ 确认后切换；
// 切换前的数据整份留在 Backups/恢复前-<时间>/；损坏的备份拒绝；旧版备份说明迁移了什么。
// The drill only writes into Application Support/.restore-drill-<uuid>/. The switch goes through the stores'
// own restore methods, in the order the app has always used.

/// Where the data to restore comes from.
enum RestoreSource {
    /// A .ddubackup (tar, V0.2 and later) or an old V0.1 user.json that the learner picked.
    case file(URL)
    /// A folder Backups/恢复前-… kept by an earlier restore (撤销 uses it).
    case snapshot(URL)
}

/// snapshot.json inside Backups/恢复前-….
struct RestoreSnapshotInfo: Codable {
    var created: Date
    var app: String
    var note: String
}

/// One Backups/恢复前-… folder.
struct RestoreSnapshot: Identifiable {
    var url: URL
    var info: RestoreSnapshotInfo?
    var id: String { url.lastPathComponent }
    var name: String { url.lastPathComponent }
}

/// One data file of the backup and what it holds.
struct RestoreFileLine: Identifiable {
    var name: String
    var title: String
    var detail: String
    var id: String { name }
}

/// ACC-26: the count written into the backup when it was made, against the count decoded now.
struct RestoreCountCheck: Identifiable {
    var label: String
    var listed: Int
    var found: Int
    var id: String { label }
    var matches: Bool { listed == found }
}

/// Content packs that the records refer to but that are not on the iPad.
struct RestoreMissingIssue: Identifiable {
    var issue: String
    var articles: Int
    var wholeIssue: Bool
    var id: String { issue }

    var text: String {
        if wholeIssue {
            return "缺 \(issue) 期内容包（记录里有 \(articles) 篇文章）：记录会保留，听读和原句回放要先导入这一期。"
        }
        return "\(issue) 期还缺 \(articles) 篇文章（可能在这一期的另一部分内容包里）：记录会保留，导入后才能听读。"
    }
}

/// The decoded data a switch writes through the stores.
struct RestorePayload {
    var user: UserState
    var practice: PracticeState?
    var vocab: VocabState?
    var vocabEvents: [ReviewEvent] = []
    var annotations: Data?
    var study: Data?
    var activity: Data?
    /// Recording files inside the temporary library.
    var recordings: [URL] = []
    var recordingBytes = 0
    /// No vocab.json in an old backup: the 生词本 words are turned into items after the switch.
    var turnWordListIntoItems = false
}

/// Everything the learner sees before deciding, and what the switch needs.
struct RestoreReport {
    var sourceName: String
    var isSnapshot = false
    var kindText = ""
    var appVersion: String?
    var created: Date?
    var backupBytes = 0
    /// Non-nil: the backup is refused and nothing will change.
    var refusal: String?
    var files: [RestoreFileLine] = []
    var checks: [RestoreCountCheck] = []
    var missingIssues: [RestoreMissingIssue] = []
    var missingRecordings: [String] = []
    var missingRecordingCount = 0
    var recordingsOnlyOnDevice = 0
    var migration: [String] = []
    var keptAsIs: [String] = []
    var warnings: [String] = []
    /// The temporary library (removed after the switch, or when the learner cancels).
    var library: URL?
    var payload: RestorePayload?

    init(sourceName: String) {
        self.sourceName = sourceName
    }
}

/// A backup file that cannot be restored, with the reason in plain words.
struct RestoreRefusal: Error {
    let text: String
}

/// How a switch ended.
enum RestoreOutcome {
    /// Done. `snapshot` holds the data from before; `warning` notes a save problem after the switch.
    case restored(snapshot: URL, warning: String?)
    /// Nothing was changed.
    case notStarted(String)
    /// It stopped half-way; the data from before was put back from `snapshot`.
    case rolledBack(String, snapshot: URL)
    /// It stopped half-way and putting the data back also failed; `snapshot` still holds it.
    case partly(String, snapshot: URL)
}

/// The stores a switch writes through.
@MainActor
struct RestoreTargets {
    let packs: PackStore
    let user: UserStore
    let practice: PracticeStore
    let vocab: VocabStore
    let annotations: AnnotationStore
    let study: StudyStore
    let session: ReadingSession

    /// The data files, in the order of RestoreDrill.dataFiles.
    var dataFileURLs: [URL] {
        [user.fileURL, practice.fileURL, vocab.fileURL, vocab.eventsURL, annotations.fileURL,
         study.fileURL, study.activityURL]
    }
}

enum RestoreDrill {
    static let dataFiles = ["user.json", "practice.json", "vocab.json", "vocab-events.jsonl",
                            "annotations-user.json", "study.json", "activity.jsonl"]
    static let metaFile = "ddubackup.json"
    static let snapshotPrefix = "恢复前-"

    static var supportFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var backupsFolder: URL {
        supportFolder.appendingPathComponent("Backups", isDirectory: true)
    }

    // MARK: Drill (off the main actor)

    /// Unpacks the source into a temporary library, decodes every file there and describes what a restore would
    /// do. Nothing outside the temporary library is touched. `installed`: issue → article ids on the iPad.
    static func run(_ source: RestoreSource, installed: [String: Set<String>], recordingsDir: URL) -> RestoreReport {
        let fm = FileManager.default
        var report = RestoreReport(sourceName: sourceName(source))
        let library = supportFolder.appendingPathComponent(".restore-drill-\(UUID().uuidString)", isDirectory: true)
        do {
            do {
                try fm.createDirectory(at: library.appendingPathComponent("Recordings", isDirectory: true),
                                       withIntermediateDirectories: true)
            } catch {
                throw RestoreRefusal(text: "没能建立临时库：\(error.localizedDescription)")
            }
            var isOldUserFile = false
            switch source {
            case .file(let url):
                isOldUserFile = try unpackFile(url, into: library, report: &report)
            case .snapshot(let url):
                try copySnapshot(url, into: library, report: &report)
            }
            try decode(library: library, isOldUserFile: isOldUserFile, installed: installed,
                       recordingsDir: recordingsDir, report: &report)
            report.library = library
        } catch {
            if let refusal = error as? RestoreRefusal {
                report.refusal = refusal.text
            } else {
                report.refusal = "检查时出错：\(error.localizedDescription)"
            }
            report.payload = nil
            try? fm.removeItem(at: library)
        }
        return report
    }

    private static func sourceName(_ source: RestoreSource) -> String {
        switch source {
        case .file(let url): return url.lastPathComponent
        case .snapshot(let url): return url.lastPathComponent
        }
    }

    /// Writes the backup's files into the library. Returns true for an old V0.1 user.json.
    private static func unpackFile(_ url: URL, into library: URL, report: inout RestoreReport) throws -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw RestoreRefusal(text: "读不出这个文件：\(error.localizedDescription)")
        }
        report.backupBytes = data.count
        let needed = Int64(Double(data.count) * 1.1)
        if let free = PackImporter.freeSpace(at: supportFolder), needed > free {
            let need = PackImporter.sizeText(needed)
            let have = PackImporter.sizeText(free)
            throw RestoreRefusal(text: "空间不够，没法先在临时库里解开这个备份（需要约 \(need)，可用 \(have)）。")
        }
        guard BackupArchive.isTar(data) else {
            guard looksLikeUserFile(data) else {
                throw RestoreRefusal(text: "这个文件不是 DayDayUp 备份：既不是 .ddubackup，也不是 V0.1 的 user.json。")
            }
            try write(data, to: library.appendingPathComponent("user.json"))
            report.kindText = "V0.1 旧备份（只有 user.json）"
            return true
        }
        let entries: [TarEntry]
        do {
            entries = try TarReader.entries(in: data)
        } catch {
            throw RestoreRefusal(text: "备份文件坏了：\(error.localizedDescription)。")
        }
        var seen = Set<String>()
        var unknown: [String] = []
        let prefix = "recordings/"
        for entry in entries {
            guard seen.insert(entry.name).inserted else {
                throw RestoreRefusal(text: "备份里有重名的文件：\(entry.name)。备份可能坏了。")
            }
            if entry.name.hasPrefix(prefix) {
                let name = String(entry.name.dropFirst(prefix.count))
                guard !name.isEmpty, !name.contains("/") else {
                    unknown.append(entry.name)
                    continue
                }
                try write(data[entry.range], to: library.appendingPathComponent("Recordings/" + name))
            } else if dataFiles.contains(entry.name) || entry.name == metaFile {
                try write(data[entry.range], to: library.appendingPathComponent(entry.name))
            } else {
                unknown.append(entry.name)
            }
        }
        if !unknown.isEmpty {
            let shown = unknown.prefix(5).joined(separator: "、")
            report.warnings.append("备份里有 \(unknown.count) 个不认识的文件，不会恢复：\(shown)")
        }
        return false
    }

    /// Copies an earlier 恢复前 folder into the library.
    private static func copySnapshot(_ folder: URL, into library: URL, report: inout RestoreReport) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.appendingPathComponent("user.json").path) else {
            throw RestoreRefusal(text: "这份恢复前的数据不完整：里面没有 user.json。")
        }
        do {
            for name in dataFiles {
                let source = folder.appendingPathComponent(name)
                if fm.fileExists(atPath: source.path) {
                    try fm.copyItem(at: source, to: library.appendingPathComponent(name))
                }
            }
            let recordings = folder.appendingPathComponent("Recordings", isDirectory: true)
            let files = (try? fm.contentsOfDirectory(at: recordings, includingPropertiesForKeys: nil)) ?? []
            for url in files where url.pathExtension.lowercased() == "m4a" {
                try fm.copyItem(at: url, to: library.appendingPathComponent("Recordings/" + url.lastPathComponent))
            }
        } catch {
            throw RestoreRefusal(text: "没能把恢复前的数据复制到临时库：\(error.localizedDescription)")
        }
        report.isSnapshot = true
        report.kindText = "恢复前留下的数据"
        if let info = snapshotInfo(folder) {
            report.created = info.created
            report.appVersion = info.app
        }
    }

    private static func write(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url)
        } catch {
            throw RestoreRefusal(text: "写临时库时出错（\(error.localizedDescription)），可能是空间不够。")
        }
    }

    /// A V0.1 backup is a user.json: a JSON object with at least one of its keys.
    private static func looksLikeUserFile(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else { return false }
        let keys: Set<String> = ["schema", "known", "star", "lookups", "positions", "heard", "heardText",
                                 "daily", "lastArticle", "lastBackup", "settings"]
        return !keys.isDisjoint(with: dict.keys)
    }

    // MARK: Decode and describe

    /// Decodes every file of the library with the types the stores use; a file that fails refuses the backup.
    private static func decode(library: URL, isOldUserFile: Bool, installed: [String: Set<String>],
                               recordingsDir: URL, report: inout RestoreReport) throws {
        let fm = FileManager.default
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        func load(_ name: String) throws -> Data? {
            let url = library.appendingPathComponent(name)
            guard fm.fileExists(atPath: url.path) else { return nil }
            do {
                return try Data(contentsOf: url)
            } catch {
                throw RestoreRefusal(text: "\(name) 读不出来：\(error.localizedDescription)")
            }
        }
        func decodeData<T: Decodable>(_ type: T.Type, _ data: Data, _ name: String) throws -> T {
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw RestoreRefusal(text: "\(name) 读不出来（\(PackImporter.describe(error))）。这个备份可能坏了，为了安全不恢复。")
            }
        }

        // ddubackup.json: format, app version, date and the counts written at backup time.
        var meta: BackupMeta?
        if let data = try load(metaFile) {
            meta = try decodeData(BackupMeta.self, data, metaFile)
        }
        if let meta, meta.format > BackupArchive.format {
            throw RestoreRefusal(text: "这个备份来自更新版本的 App（备份格式 \(meta.format)），这个版本读不全。请先更新 App 再恢复。")
        }
        if !report.isSnapshot && !isOldUserFile {
            report.kindText = kindText(meta)
            report.appVersion = meta?.app
            report.created = meta?.created
        }

        guard let userData = try load("user.json") else {
            throw RestoreRefusal(text: "备份里没有 user.json，不是完整的 DayDayUp 备份。")
        }
        let user = try decodeData(UserState.self, userData, "user.json")
        var practice: PracticeState?
        if let data = try load("practice.json") {
            practice = try decodeData(PracticeState.self, data, "practice.json")
        } else if !isOldUserFile {
            throw RestoreRefusal(text: "备份里没有 practice.json，文件可能不完整。")
        }
        var vocab: VocabState?
        if let data = try load("vocab.json") {
            vocab = try decodeData(VocabState.self, data, "vocab.json")
        }
        let eventsData = try load("vocab-events.jsonl")
        var events: [ReviewEvent] = []
        var badEvents = 0
        if let eventsData {
            let read = JSONLines<ReviewEvent>.decode(eventsData)
            if read.records.isEmpty && read.badLines > 0 {
                throw RestoreRefusal(text: "vocab-events.jsonl 一行也读不出来（\(read.badLines) 行）。这个备份可能坏了，为了安全不恢复。")
            }
            events = read.records
            badEvents = read.badLines
        }
        let annotationsData = try load("annotations-user.json")
        var annotations: AnnotationUserFile?
        if let annotationsData {
            annotations = try decodeData(AnnotationUserFile.self, annotationsData, "annotations-user.json")
        }
        let studyData = try load("study.json")
        var study: StudyState?
        if let studyData {
            study = try decodeData(StudyState.self, studyData, "study.json")
        }
        let activityData = try load("activity.jsonl")
        var activityCount = 0
        var badActivity = 0
        if let activityData {
            let read = JSONLines<ActivityRecord>.decode(activityData)
            if read.records.isEmpty && read.badLines > 0 {
                throw RestoreRefusal(text: "activity.jsonl 一行也读不出来（\(read.badLines) 行）。这个备份可能坏了，为了安全不恢复。")
            }
            activityCount = read.records.count
            badActivity = read.badLines
        }
        if let meta {
            for name in meta.dataFiles ?? [] where !fm.fileExists(atPath: library.appendingPathComponent(name).path) {
                throw RestoreRefusal(text: "备份清单里有 \(name)，备份里却没有这个文件：备份不完整。")
            }
        }
        // Like the restore always did: review events are restored together with vocab.json only.
        if vocab == nil && !events.isEmpty {
            report.warnings.append("备份里有复习事件，但没有 vocab.json：这些事件不会恢复。")
            events = []
        }
        if vocab != nil && eventsData == nil {
            report.warnings.append("备份里没有 vocab-events.jsonl：恢复后没有复习事件记录。")
        }

        // Recordings.
        let recordingFolder = library.appendingPathComponent("Recordings", isDirectory: true)
        let listed = (try? fm.contentsOfDirectory(at: recordingFolder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let recordings = listed.filter { $0.pathExtension.lowercased() == "m4a" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var recordingBytes = 0
        var emptyRecordings = 0
        for url in recordings {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            recordingBytes += size
            if size == 0 { emptyRecordings += 1 }
        }
        if emptyRecordings > 0 {
            report.warnings.append("有 \(emptyRecordings) 个录音文件是空的，恢复后放不出声音。")
        }

        report.files = fileLines(user: user, practice: practice, vocab: vocab, eventsFound: eventsData != nil,
                                 events: events.count, badEvents: badEvents, annotations: annotations,
                                 study: study, activityFound: activityData != nil, activity: activityCount,
                                 badActivity: badActivity, recordings: recordings.count, recordingBytes: recordingBytes)
        if let meta {
            report.checks = countChecks(meta, user: user, practice: practice, vocab: vocab, events: events.count,
                                        recordings: recordings.count)
            let off = report.checks.filter { !$0.matches }.count
            if off > 0 {
                report.warnings.append("有 \(off) 项数量和备份清单不一致（见“清单核对”）：恢复后以解开的数量为准，差的那些读不出来。")
            }
        }

        describeMissingRecordings(practice: practice, events: events, inBackup: recordings,
                                  recordingsDir: recordingsDir, report: &report)
        let keys = articleKeys(user: user, practice: practice, vocab: vocab, study: study, annotations: annotations)
        report.missingIssues = missingIssues(keys, installed: installed)

        let turnWordList = vocab == nil && !report.isSnapshot
        describeMigration(meta: meta, isOldUserFile: isOldUserFile, hasPractice: practice != nil,
                          hasVocab: vocab != nil, hasAnnotations: annotationsData != nil,
                          hasStudy: studyData != nil, hasActivity: activityData != nil, report: &report)

        var payload = RestorePayload(user: user)
        payload.practice = practice
        payload.vocab = vocab
        payload.vocabEvents = vocab == nil ? [] : events
        payload.annotations = annotationsData
        payload.study = studyData
        payload.activity = activityData
        payload.recordings = recordings
        payload.recordingBytes = recordingBytes
        payload.turnWordListIntoItems = turnWordList
        report.payload = payload
    }

    private static func kindText(_ meta: BackupMeta?) -> String {
        guard let meta else { return "完整备份（没有说明文件，版本不明）" }
        switch meta.format {
        case 1: return "V0.2 的完整备份（格式 1）"
        case 2: return "V0.3 以后的完整备份（格式 2）"
        default: return "完整备份（格式 \(meta.format)）"
        }
    }

    private static func fileLines(user: UserState, practice: PracticeState?, vocab: VocabState?,
                                  eventsFound: Bool, events: Int, badEvents: Int, annotations: AnnotationUserFile?,
                                  study: StudyState?, activityFound: Bool, activity: Int, badActivity: Int,
                                  recordings: Int, recordingBytes: Int) -> [RestoreFileLine] {
        var lines: [RestoreFileLine] = []
        var articles = Set(user.heard.keys)
        articles.formUnion(user.heardText.keys)
        articles.formUnion(user.positions.keys)
        lines.append(RestoreFileLine(name: "user.json", title: "生词与听读",
                                     detail: "生词 \(user.star.count) 个 · 认识 \(user.known.count) 个 · 听读进度 \(articles.count) 篇文章 · 听读记录 \(user.daily.count) 天"))
        if let p = practice {
            let drafts = p.writing.filter { $0.isDraft }.count
            lines.append(RestoreFileLine(name: "practice.json", title: "跟读与说写",
                                         detail: "跟读 \(p.shadow.count) 次 · 口语 \(p.speaking.count) 次 · 写作 \(p.writing.count) 篇（草稿 \(drafts)）· 模拟 \(p.mocks.count) 次"))
        }
        if let v = vocab {
            lines.append(RestoreFileLine(name: "vocab.json", title: "词汇",
                                         detail: "词项 \(v.items.count) 个 · 卡片 \(v.cards.count) 张"))
        }
        if eventsFound {
            let bad = badEvents > 0 ? "（坏行 \(badEvents)，会跳过）" : "（坏行 0）"
            lines.append(RestoreFileLine(name: "vocab-events.jsonl", title: "复习事件", detail: "\(events) 条" + bad))
        }
        if let a = annotations {
            lines.append(RestoreFileLine(name: "annotations-user.json", title: "发音标注的改动",
                                         detail: "\(a.entries.count) 条"))
        }
        if let s = study {
            lines.append(RestoreFileLine(name: "study.json", title: "计划与复测",
                                         detail: "计划 \(s.plans.count) 天 · 理解题 \(s.quizResults.count) 次 · 复测 \(s.retests.count) 个 · 基线 \(s.baseline.doneCount)/4"))
        }
        if activityFound {
            let bad = badActivity > 0 ? "（坏行 \(badActivity)，会跳过）" : ""
            lines.append(RestoreFileLine(name: "activity.jsonl", title: "练习时段", detail: "\(activity) 段" + bad))
        }
        let size = PackImporter.sizeText(Int64(recordingBytes))
        lines.append(RestoreFileLine(name: "Recordings", title: "录音", detail: "\(recordings) 个，\(size)"))
        return lines
    }

    private static func countChecks(_ meta: BackupMeta, user: UserState, practice: PracticeState?,
                                    vocab: VocabState?, events: Int, recordings: Int) -> [RestoreCountCheck] {
        var out = [
            RestoreCountCheck(label: "生词", listed: meta.starred, found: user.star.count),
            RestoreCountCheck(label: "认识的词", listed: meta.known, found: user.known.count),
            RestoreCountCheck(label: "听读记录（天）", listed: meta.days, found: user.daily.count),
            RestoreCountCheck(label: "跟读", listed: meta.shadow, found: practice?.shadow.count ?? 0),
            RestoreCountCheck(label: "口语", listed: meta.speaking, found: practice?.speaking.count ?? 0),
            RestoreCountCheck(label: "写作", listed: meta.writing, found: practice?.writing.count ?? 0),
            RestoreCountCheck(label: "录音", listed: meta.recordings, found: recordings),
        ]
        if let n = meta.vocabItems {
            out.append(RestoreCountCheck(label: "词项", listed: n, found: vocab?.items.count ?? 0))
        }
        if let n = meta.vocabCards {
            out.append(RestoreCountCheck(label: "卡片", listed: n, found: vocab?.cards.count ?? 0))
        }
        if let n = meta.vocabEvents {
            out.append(RestoreCountCheck(label: "复习事件", listed: n, found: events))
        }
        return out
    }

    /// Recordings the records refer to that are not in the backup; those also missing on this iPad are listed.
    private static func describeMissingRecordings(practice: PracticeState?, events: [ReviewEvent], inBackup: [URL],
                                                  recordingsDir: URL, report: inout RestoreReport) {
        var refs: [String: String] = [:]
        for s in practice?.shadow ?? [] {
            if let f = s.file, !f.isEmpty { refs[f] = "跟读 · \(DayKey.of(s.created)) · \(s.article) 第 \(s.sid) 句" }
            if let f = s.followFile, !f.isEmpty { refs[f] = "复述追问 · \(DayKey.of(s.created)) · \(s.article)" }
        }
        for w in practice?.speaking ?? [] {
            if let f = w.file, !f.isEmpty { refs[f] = "口语 · \(DayKey.of(w.created)) · " + String(w.question.prefix(30)) }
        }
        for e in events {
            if let f = e.evidence, f.hasSuffix(".m4a") { refs[f] = "词汇朗读 · \(e.day)" }
        }
        let backupNames = Set(inBackup.map(\.lastPathComponent))
        let fm = FileManager.default
        let deviceFiles = (try? fm.contentsOfDirectory(at: recordingsDir, includingPropertiesForKeys: nil)) ?? []
        let deviceNames = Set(deviceFiles.map(\.lastPathComponent))
        let notInBackup = refs.keys.filter { !backupNames.contains($0) }
        let missing = notInBackup.filter { !deviceNames.contains($0) }.sorted()
        report.recordingsOnlyOnDevice = notInBackup.count - missing.count
        report.missingRecordingCount = missing.count
        report.missingRecordings = missing.prefix(8).compactMap { refs[$0] }
    }

    /// Every article the records refer to ("issue/id").
    private static func articleKeys(user: UserState, practice: PracticeState?, vocab: VocabState?,
                                    study: StudyState?, annotations: AnnotationUserFile?) -> Set<String> {
        var keys = Set(user.positions.keys)
        keys.formUnion(user.heard.keys)
        keys.formUnion(user.heardText.keys)
        if let k = user.lastArticle { keys.insert(k) }
        for s in practice?.shadow ?? [] { keys.insert(s.article) }
        for item in vocab?.items ?? [] {
            for o in item.sources { keys.insert(o.ref.key) }
        }
        if let s = study {
            keys.formUnion(s.articleOpened.keys)
            keys.formUnion(s.articleFinished.keys)
            keys.formUnion(s.articleDifficulty.keys)
            keys.formUnion(s.favorites.keys)
            for q in s.quizResults { keys.insert(q.article) }
            for plan in s.plans.values {
                for task in plan.tasks {
                    if let k = articleKey(task.target) { keys.insert(k) }
                }
            }
        }
        if let entries = annotations?.entries {
            // "<issue>/<article>#<annotationId>"
            for key in entries.keys {
                if let hash = key.firstIndex(of: "#") { keys.insert(String(key[..<hash])) }
            }
        }
        return keys
    }

    private static func articleKey(_ target: PlanTarget) -> String? {
        switch target {
        case .article(let issue, let id):
            return ArticleRef(issue: issue, id: id).key
        case .shadow(let issue, let id, _):
            return ArticleRef(issue: issue, id: id).key
        case .articleCheck(let issue, let id, _):
            return ArticleRef(issue: issue, id: id).key
        default:
            return nil
        }
    }

    private static func missingIssues(_ keys: Set<String>, installed: [String: Set<String>]) -> [RestoreMissingIssue] {
        var byIssue: [String: Set<String>] = [:]
        for key in keys {
            guard let ref = ArticleRef(key: key), !ref.issue.isEmpty, !ref.id.isEmpty else { continue }
            byIssue[ref.issue, default: []].insert(ref.id)
        }
        var out: [RestoreMissingIssue] = []
        for issue in byIssue.keys.sorted() {
            let wanted = byIssue[issue] ?? []
            let have = installed[issue] ?? []
            let missing = wanted.subtracting(have)
            if !missing.isEmpty {
                out.append(RestoreMissingIssue(issue: issue, articles: missing.count, wholeIssue: have.isEmpty))
            }
        }
        return out
    }

    /// What an older backup does not have, and what is changed on the way in (VocabStore.migrateFromV02IfNeeded).
    private static func describeMigration(meta: BackupMeta?, isOldUserFile: Bool, hasPractice: Bool, hasVocab: Bool,
                                          hasAnnotations: Bool, hasStudy: Bool, hasActivity: Bool,
                                          report: inout RestoreReport) {
        if report.isSnapshot {
            report.migration = ["这是一次恢复之前自动留下的数据，恢复它就回到那时的样子。"]
            return
        }
        let wordList = "生词本里的词会转成词项（只开“认义”任务）；已经有词项的词不会重复加，暂停复习的同一个词会重新打开。"
        if isOldUserFile {
            report.migration = ["这是 V0.1 的旧备份：只有生词本和听读进度。", wordList]
        } else if meta?.format == 1 {
            report.migration = ["这是 V0.2 的备份：有生词本、听读、跟读、口语、写作和录音。旧记录里没有的新字段用默认值补上（比如模拟考试为空）。"]
        }
        if !hasPractice { report.keptAsIs.append("跟读、口语、写作和录音") }
        if !hasVocab {
            report.keptAsIs.append("词汇复习（词项、卡片、复习事件）")
            if !isOldUserFile { report.migration.append(wordList) }
        }
        if !hasAnnotations { report.keptAsIs.append("发音标注的改动") }
        if !hasStudy { report.keptAsIs.append("学习计划、基线、复测和理解题") }
        if !hasActivity { report.keptAsIs.append("练习时段") }
    }

    // MARK: Snapshots

    static func snapshotInfo(_ folder: URL) -> RestoreSnapshotInfo? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("snapshot.json")) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RestoreSnapshotInfo.self, from: data)
    }

    /// Backups/恢复前-… folders, newest first.
    static func snapshots() -> [RestoreSnapshot] {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: backupsFolder, includingPropertiesForKeys: nil)) ?? []
        return dirs.filter { $0.lastPathComponent.hasPrefix(snapshotPrefix) }
            .map { RestoreSnapshot(url: $0, info: snapshotInfo($0)) }
            .sorted { $0.name > $1.name }
    }

    /// Copies all current data files and the Recordings folder into Backups/恢复前-yyyyMMdd-HHmmss/.
    /// The folder appears only when the copy is complete.
    static func makeSnapshot(dataFiles files: [URL], recordingsDir: URL, note: String) throws -> URL {
        let fm = FileManager.default
        let root = backupsFolder
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let base = snapshotPrefix + stamp(Date())
        var dest = root.appendingPathComponent(base, isDirectory: true)
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = root.appendingPathComponent("\(base)-\(n)", isDirectory: true)
            n += 1
        }
        let temp = root.appendingPathComponent(".partial-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: temp, withIntermediateDirectories: true)
            for url in files {
                let target = temp.appendingPathComponent(url.lastPathComponent)
                if fm.fileExists(atPath: url.path) {
                    try fm.copyItem(at: url, to: target)
                } else if url.pathExtension == "jsonl" {
                    // No log file yet means an empty log: undoing puts back an empty one.
                    try Data().write(to: target)
                }
            }
            let recordings = temp.appendingPathComponent("Recordings", isDirectory: true)
            if fm.fileExists(atPath: recordingsDir.path) {
                try fm.copyItem(at: recordingsDir, to: recordings)
            } else {
                try fm.createDirectory(at: recordings, withIntermediateDirectories: true)
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let info = RestoreSnapshotInfo(created: Date(), app: BackupArchive.appVersionText(), note: note)
            try encoder.encode(info).write(to: temp.appendingPathComponent("snapshot.json"))
            try fm.moveItem(at: temp, to: dest)
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
        return dest
    }

    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }

    /// Removes temporary libraries and unfinished snapshot copies left by an earlier run.
    static func cleanLeftovers() {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: supportFolder, includingPropertiesForKeys: nil)) ?? []
        for url in items where url.lastPathComponent.hasPrefix(".restore-drill-") {
            try? fm.removeItem(at: url)
        }
        let partial = (try? fm.contentsOfDirectory(at: backupsFolder, includingPropertiesForKeys: nil)) ?? []
        for url in partial where url.lastPathComponent.hasPrefix(".partial-") {
            try? fm.removeItem(at: url)
        }
    }

    static func removeLibrary(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func loadRecordings(_ urls: [URL]) throws -> [String: Data] {
        var out: [String: Data] = [:]
        for url in urls {
            out[url.lastPathComponent] = try Data(contentsOf: url, options: .mappedIfSafe)
        }
        return out
    }

    static func installedArticles(_ packs: [InstalledPack]) -> [String: Set<String>] {
        var out: [String: Set<String>] = [:]
        for pack in packs {
            out[pack.manifest.issue, default: []].formUnion(pack.manifest.articles.map(\.id))
        }
        return out
    }
}

// MARK: - Switch (main actor)

extension RestoreDrill {
    /// Saves the current data, keeps a whole copy in Backups/恢复前-…, then restores through the stores in the
    /// order the app has always used. If a store fails half-way, the copy is put back the same way.
    @MainActor
    static func switchTo(_ report: RestoreReport, targets t: RestoreTargets) async -> RestoreOutcome {
        guard report.refusal == nil, let payload = report.payload else {
            removeLibrary(report.library)
            return .notStarted(report.refusal ?? "没有可以恢复的内容。现在的记录没有改动。")
        }
        guard let library = report.library, FileManager.default.fileExists(atPath: library.path) else {
            return .notStarted("临时库已经清理掉了，请重新选择备份文件。现在的记录没有改动。")
        }
        // 1. What is in memory goes to disk first, so the copy below is the real current state.
        ActivityClock.shared.flush()
        t.session.flushProgress()
        t.user.saveNow()
        t.practice.saveNow()
        t.vocab.saveNow()
        t.annotations.saveNow()
        t.study.saveNow()
        let saveErrors = [t.user.saveError, t.practice.saveError, t.vocab.saveError,
                          t.annotations.saveError, t.study.saveError].compactMap { $0 }
        if let first = saveErrors.first {
            removeLibrary(report.library)
            return .notStarted("现在的记录没能先保存（\(first)），为了安全没有恢复。现在的记录没有改动。")
        }
        let needed = Int64(Double(payload.recordingBytes) * 1.1)
        if let free = PackImporter.freeSpace(at: supportFolder), needed > free {
            removeLibrary(report.library)
            let need = PackImporter.sizeText(needed)
            let have = PackImporter.sizeText(free)
            return .notStarted("空间不够：写回录音需要约 \(need)，可用 \(have)。现在的记录没有改动。")
        }

        // 2. The whole current data stays in Backups/恢复前-… (stop if this copy fails).
        let files = t.dataFileURLs
        let recordingsDir = t.practice.recordingsDir
        let note = report.isSnapshot ? "回到 \(report.sourceName) 之前" : "恢复 \(report.sourceName) 之前"
        let snapshot: URL
        do {
            snapshot = try await Task.detached(priority: .userInitiated) {
                try RestoreDrill.makeSnapshot(dataFiles: files, recordingsDir: recordingsDir, note: note)
            }.value
        } catch {
            removeLibrary(report.library)
            return .notStarted("没能先把现在的数据整份存一份（\(error.localizedDescription)），所以没有恢复。现在的记录没有改动。")
        }

        // 3. Restore through the stores; the temporary library goes away afterwards.
        let recordingURLs = payload.recordings
        let recordings: [String: Data]
        do {
            recordings = try await Task.detached(priority: .userInitiated) {
                try RestoreDrill.loadRecordings(recordingURLs)
            }.value
        } catch {
            removeLibrary(report.library)
            return .notStarted("读不出临时库里的录音（\(error.localizedDescription)），所以没有恢复。现在的记录没有改动。")
        }
        do {
            try apply(payload, recordings: recordings, to: t)
        } catch {
            let reason = error.localizedDescription
            DiagLog.shared.log("backup", "restore failed half-way: \(reason); putting back \(snapshot.lastPathComponent)")
            removeLibrary(report.library)
            return await rollBack(reason: reason, snapshot: snapshot, targets: t)
        }
        removeLibrary(report.library)
        var warning: String?
        if let err = t.user.saveError {
            warning = "user.json 保存时出错（\(err)），App 会在下次改动时再保存。"
        }
        DiagLog.shared.log("backup", "restored \(report.sourceName); before-copy \(snapshot.lastPathComponent)")
        return .restored(snapshot: snapshot, warning: warning)
    }

    /// Puts the copy made before the switch back, through the same store methods.
    @MainActor
    private static func rollBack(reason: String, snapshot: URL, targets t: RestoreTargets) async -> RestoreOutcome {
        let recordingsDir = t.practice.recordingsDir
        let back = await Task.detached(priority: .userInitiated) {
            RestoreDrill.run(.snapshot(snapshot), installed: [:], recordingsDir: recordingsDir)
        }.value
        guard back.refusal == nil, let payload = back.payload else {
            removeLibrary(back.library)
            return .partly(reason, snapshot: snapshot)
        }
        let recordingURLs = payload.recordings
        do {
            let recordings = try await Task.detached(priority: .userInitiated) {
                try RestoreDrill.loadRecordings(recordingURLs)
            }.value
            try apply(payload, recordings: recordings, to: t)
            removeLibrary(back.library)
            DiagLog.shared.log("backup", "put back \(snapshot.lastPathComponent) after a failed restore")
            return .rolledBack(reason, snapshot: snapshot)
        } catch {
            removeLibrary(back.library)
            DiagLog.shared.log("backup", "putting back failed: \(error.localizedDescription)")
            return .partly(reason, snapshot: snapshot)
        }
    }

    /// The stores' own restore methods, in the order the app has always used.
    @MainActor
    private static func apply(_ p: RestorePayload, recordings: [String: Data], to t: RestoreTargets) throws {
        if let practice = p.practice {
            try t.practice.restore(practice, recordings: recordings)
        }
        if let vocab = p.vocab {
            try t.vocab.restore(vocab, events: p.vocabEvents)
        }
        if let data = p.annotations {
            try t.annotations.restore(data)
        }
        if p.study != nil || p.activity != nil {
            try t.study.restore(study: p.study, activity: p.activity)
        }
        t.user.restore(p.user)
        if p.turnWordListIntoItems {
            // An old backup has no vocab.json: its 生词本 words become items (runs now if the lexicon is loaded,
            // otherwise as soon as it is).
            t.vocab.update { $0.migratedV02 = nil }
            t.vocab.saveNow()
            t.vocab.migrateFromV02IfNeeded(user: t.user, packs: t.packs)
        }
        t.session.refreshMarks()
    }
}
