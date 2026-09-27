import Foundation
import Observation
import CryptoKit
import UniformTypeIdentifiers

extension UTType {
    /// Declared in Info.plist (UTExportedTypeDeclarations).
    static let ecopack = UTType(exportedAs: "com.daydayup.ecopack")
}

struct InstalledPack: Identifiable, Hashable, Sendable {
    var manifest: PackManifest
    var folder: URL
    var id: String { manifest.packId }

    var sizeOnDisk: Int {
        (manifest.files ?? [:]).values.reduce(0) { $0 + $1.size }
    }
}

enum PackError: LocalizedError {
    case noManifest
    case unsupportedFormat(Int)
    case missingFile(String)
    case corrupt(String)
    case notInstalled
    case missingFields([String])
    case unsafePath(String)
    case duplicateName(String)

    var errorDescription: String? {
        switch self {
        case .noManifest: return "不是 DayDayUp 内容包（没有 manifest.json）"
        case .unsupportedFormat(let f): return "内容包格式 \(f) 太新，请先更新 App"
        case .missingFile(let n): return "内容包缺少文件 \(n)"
        case .corrupt(let n): return "文件校验失败：\(n)"
        case .notInstalled: return "这篇文章的内容包还没导入"
        case .missingFields(let names): return "内容包说明缺少必填字段：" + names.joined(separator: "、")
        case .unsafePath(let n): return "内容包里有不安全的文件路径：\(n)"
        case .duplicateName(let n): return "内容包里有重名文件：\(n)"
        }
    }
}

/// Installed content packs live in Application Support/Packs/<packId>/ (not visible in Files).
/// The lexicon of all packs is merged in the background: one card per word, contexts appended.
@MainActor
@Observable
final class PackStore {
    private(set) var packs: [InstalledPack] = []
    private(set) var lexicon: [String: LexEntry] = [:]
    private(set) var xent: [String: XEnt] = [:]
    private(set) var lexiconReady = false
    private(set) var isImporting = false
    var lastMessage: String?

    /// .ecopack files waiting in Documents (Finder / iTunes file sharing, the Files app) or Documents/Inbox
    /// ("Open in"). They are only found here; the learner imports them through the preview (IMP-F04).
    private(set) var pendingInbox: [URL] = []
    /// Files opened with the app from another place (opened in place, not copied in), until their preview closes.
    private(set) var openedFiles: [URL] = []

    let root: URL
    @ObservationIgnored private var lexiconTask: Task<Void, Never>?
    /// Called after an update changed sentences of articles that were already installed (PKG-P03).
    @ObservationIgnored var onArticlesChanged: (([ArticleDiff]) -> Void)?
    @ObservationIgnored private var articleCache: [String: Article] = [:]
    @ObservationIgnored private var cacheOrder: [String] = []
    @ObservationIgnored private var annotationCache: [String: AnnotationFile?] = [:]
    @ObservationIgnored private var resourceCache: [String: ArticleResources] = [:]

    init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = support.appendingPathComponent("Packs", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        PackStore.recoverInterruptedInstalls(in: root)
        reload()
    }

    /// An import that stopped half-way (app closed, crash) leaves hidden folders behind:
    /// put a moved-away old pack back if its place is empty, and remove unfinished copies (ACC-08).
    nonisolated static func recoverInterruptedInstalls(in root: URL) {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for dir in dirs where dir.lastPathComponent.hasPrefix(".old-") {
            if let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
               let m = try? JSONDecoder().decode(PackManifest.self, from: data) {
                let dest = root.appendingPathComponent(safeName(m.packId), isDirectory: true)
                if !fm.fileExists(atPath: dest.path) {
                    try? fm.moveItem(at: dir, to: dest)
                    DiagLog.shared.log("pack", "restored \(m.packId) after an interrupted import")
                    continue
                }
            }
            try? fm.removeItem(at: dir)
        }
        for dir in dirs where dir.lastPathComponent.hasPrefix(".tmp-") {
            try? fm.removeItem(at: dir)
        }
        // A copy into Documents/冲突副本 that stopped half-way.
        PackImporter.cleanPartialCopies(documents: documentsFolder)
        // A restore check (temporary library) or a 恢复前 copy that stopped half-way; nothing uses them at launch.
        RestoreDrill.cleanLeftovers()
    }

    // MARK: Listing

    func reload() {
        let fm = FileManager.default
        var list: [InstalledPack] = []
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        for dir in dirs where !dir.lastPathComponent.hasPrefix(".") {
            let url = dir.appendingPathComponent("manifest.json")
            if let data = try? Data(contentsOf: url),
               let manifest = try? decoder.decode(PackManifest.self, from: data) {
                list.append(InstalledPack(manifest: manifest, folder: dir))
            }
        }
        packs = list.sorted {
            ($0.manifest.issue, $0.manifest.part) < ($1.manifest.issue, $1.manifest.part)
        }
        articleCache = [:]
        cacheOrder = []
        annotationCache = [:]
        resourceCache = [:]
        loadLexicon()
    }

    /// Issues newest first; articles in magazine order.
    var groups: [IssueGroup] {
        var byIssue: [String: [LibraryItem]] = [:]
        for pack in packs {
            for meta in pack.manifest.articles {
                let item = LibraryItem(ref: ArticleRef(issue: pack.manifest.issue, id: meta.id),
                                       meta: meta, packId: pack.manifest.packId)
                byIssue[pack.manifest.issue, default: []].append(item)
            }
        }
        return byIssue.keys.sorted(by: >).map { IssueGroup(issue: $0, items: byIssue[$0] ?? []) }
    }

    var allItems: [LibraryItem] { groups.flatMap(\.items) }

    var articleCount: Int { packs.reduce(0) { $0 + $1.manifest.articles.count } }

    func item(_ ref: ArticleRef) -> LibraryItem? {
        for pack in packs where pack.manifest.issue == ref.issue {
            if let meta = pack.manifest.articles.first(where: { $0.id == ref.id }) {
                return LibraryItem(ref: ref, meta: meta, packId: pack.manifest.packId)
            }
        }
        return nil
    }

    private func locate(_ ref: ArticleRef) -> (folder: URL, meta: ArticleMeta)? {
        for installed in packs where installed.manifest.issue == ref.issue {
            if let meta = installed.manifest.articles.first(where: { $0.id == ref.id }) {
                return (installed.folder, meta)
            }
        }
        return nil
    }

    func loadArticle(_ ref: ArticleRef) throws -> Article {
        guard let found = locate(ref) else { throw PackError.notInstalled }
        let url = found.folder.appendingPathComponent("articles/\(ref.id).json")
        return try JSONDecoder().decode(Article.self, from: Data(contentsOf: url))
    }

    /// The publication the pack names (format 2 sourceInfo, or the format-1 title "X · issue"); "" if unknown.
    func publication(_ ref: ArticleRef) -> String {
        guard let m = pack(for: ref)?.manifest else { return "" }
        if let p = m.sourceInfo?["publication"], !p.isEmpty { return p }
        let parts = m.title.components(separatedBy: " · ")
        return parts.count > 1 ? parts[0] : ""
    }

    func audioURL(_ ref: ArticleRef) -> URL? {
        guard let found = locate(ref) else { return nil }
        return found.folder.appendingPathComponent(found.meta.audio)
    }

    /// SHA-256 of the article's audio file, from the manifest (binds clips to one audio version).
    func audioSha(_ ref: ArticleRef) -> String? {
        for installed in packs where installed.manifest.issue == ref.issue {
            if let meta = installed.manifest.articles.first(where: { $0.id == ref.id }) {
                return installed.manifest.checks[meta.audio]?.sha256.lowercased()
            }
        }
        return nil
    }

    func pack(for ref: ArticleRef) -> InstalledPack? {
        packs.first { p in p.manifest.issue == ref.issue && p.manifest.articles.contains { $0.id == ref.id } }
    }

    /// Article from a small in-memory cache (the reader, the review cards and the word list share it).
    func cachedArticle(_ ref: ArticleRef) -> Article? {
        if let a = articleCache[ref.key] { return a }
        guard let a = try? loadArticle(ref) else { return nil }
        articleCache[ref.key] = a
        cacheOrder.append(ref.key)
        if cacheOrder.count > 12 {
            articleCache[cacheOrder.removeFirst()] = nil
        }
        return a
    }

    /// Pronunciation annotations of an article (annotations/<id>.json), nil when the pack has none.
    func annotationFile(_ ref: ArticleRef) -> AnnotationFile? {
        if let cached = annotationCache[ref.key] { return cached }
        var file: AnnotationFile?
        if let pack = pack(for: ref) {
            let url = pack.folder.appendingPathComponent("annotations/\(ref.id).json")
            if let data = try? Data(contentsOf: url) {
                file = try? JSONDecoder().decode(AnnotationFile.self, from: data)
                if file == nil { DiagLog.shared.log("pack", "unreadable annotations for \(ref.key)") }
            }
        }
        annotationCache[ref.key] = .some(file)
        return file
    }

    /// Comprehension questions of an article (quiz/<id>.json), nil when the pack has none.
    func quizFile(_ ref: ArticleRef) -> QuizFile? {
        guard let pack = pack(for: ref) else { return nil }
        let url = pack.folder.appendingPathComponent("quiz/\(ref.id).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(QuizFile.self, from: data)
    }

    /// What this article can offer offline (PKG-P04): each resource is available, missing or not required.
    func resources(_ ref: ArticleRef) -> ArticleResources {
        if let cached = resourceCache[ref.key] { return cached }
        var r = ArticleResources()
        guard let pack = pack(for: ref), let meta = pack.manifest.articles.first(where: { $0.id == ref.id }) else {
            r.text = .missing
            r.audio = .missing
            r.timing = .missing
            r.senses = .missing
            return r
        }
        let fm = FileManager.default
        func exists(_ name: String) -> Bool { fm.fileExists(atPath: pack.folder.appendingPathComponent(name).path) }
        let deps = meta.deps ?? [:]
        func state(_ key: String, file: String?) -> ResourceState {
            if let file { return exists(file) ? .available : (deps[key] == "not-required" ? .notRequired : .missing) }
            return ResourceState(rawValue: deps[key] ?? "") ?? .available
        }
        r.text = state("text", file: "articles/\(ref.id).json")
        r.audio = state("audio", file: meta.audio)
        r.timing = r.audio == .available ? state("timing", file: nil) : .missing
        // Word sounds are cut from the original audio when there is a time line; otherwise the system voice is used.
        r.wordAudio = r.timing == .available ? .available : (ResourceState(rawValue: deps["wordAudio"] ?? "") ?? .notRequired)
        r.senses = state("senses", file: "lexicon.json")
        r.annotations = state("annotations", file: "annotations/\(ref.id).json")
        r.quiz = state("quiz", file: "quiz/\(ref.id).json")
        r.pdf = ResourceState(rawValue: deps["pdf"] ?? "") ?? .notRequired
        resourceCache[ref.key] = r
        return r
    }

    func sentence(_ ref: ArticleRef, sid: Int) -> Sent? {
        cachedArticle(ref)?.paras.lazy.flatMap(\.sents).first { $0.id == sid }
    }

    /// Occurrence for a lexicon context "articleId:sentenceId" (V0.1 cards), at the first token with this key.
    func occurrence(forContext sid: String, key: String, cache: inout [String: Article]) -> Occurrence? {
        let parts = sid.split(separator: ":").map(String.init)
        guard parts.count == 2, let n = Int(parts[1]) else { return nil }
        guard let item = allItems.first(where: { $0.ref.id == parts[0] }) else { return nil }
        let article: Article
        if let a = cache[item.ref.key] {
            article = a
        } else if let a = cachedArticle(item.ref) {
            cache[item.ref.key] = a
            article = a
        } else {
            return nil
        }
        guard let s = article.paras.lazy.flatMap(\.sents).first(where: { $0.id == n }) else { return nil }
        let tok = s.toks.first { $0.k == key } ?? s.toks.first { $0.w.lowercased() == key.lowercased() }
        guard let tok else {
            var o = Occurrence(issue: item.ref.issue, article: item.ref.id, sid: n)
            let plain = SentenceText.plain(s)
            o.sentence = plain
            o.textHash = SentenceText.hash(plain)
            return o
        }
        return OccurrenceBuilder.make(ref: item.ref, sentence: s, first: tok.i, last: tok.i, audioSha: audioSha(item.ref))
    }

    // MARK: Lexicon

    func entry(_ key: String?) -> LexEntry? {
        guard let key else { return nil }
        return lexicon[key]
    }

    private func loadLexicon() {
        lexiconTask?.cancel()
        lexiconReady = false
        let folders = packs.map(\.folder)
        lexiconTask = Task {
            let merged = await Task.detached(priority: .userInitiated) { () -> ([String: LexEntry], [String: XEnt]) in
                var entries: [String: LexEntry] = [:]
                var names: [String: XEnt] = [:]
                let decoder = JSONDecoder()
                for folder in folders {
                    guard let data = try? Data(contentsOf: folder.appendingPathComponent("lexicon.json")),
                          let file = try? decoder.decode(LexFile.self, from: data) else { continue }
                    for (key, value) in file.entries {
                        if var old = entries[key] {
                            old.mergeContexts(from: value)
                            entries[key] = old
                        } else {
                            entries[key] = value
                        }
                    }
                    for (key, value) in file.xent ?? [:] where names[key] == nil {
                        names[key] = value
                    }
                }
                return (entries, names)
            }.value
            if Task.isCancelled { return }
            self.lexicon = merged.0
            self.xent = merged.1
            self.lexiconReady = true
        }
    }

    // MARK: Import (IMP-F04, IMP-P04, PKG-P05, ACC-04/05/06/08)
    //
    // Nothing is installed without a preview: files are read and checked first (PackImporter.stage),
    // the learner confirms per file, and each confirmed file is checked again and committed with a folder swap.

    /// Everything that waits for a preview: files in the app's folder first, then files opened from elsewhere.
    var waitingFiles: [URL] {
        var out = pendingInbox
        var seen = Set(out.map { PackStore.pathKey($0) })
        for url in openedFiles where seen.insert(PackStore.pathKey(url)).inserted {
            out.append(url)
        }
        return out
    }

    /// Finds .ecopack files in Documents and Documents/Inbox. It never installs anything.
    func scanInbox() async {
        let found = PackStore.inboxFiles()
        if found != pendingInbox { pendingInbox = found }
    }

    /// A file arrived through "Open in" / AirDrop / the Files app (onOpenURL).
    func noteOpened(_ url: URL) {
        guard url.isFileURL else { return }
        if PackStore.isInInbox(url) {
            pendingInbox = PackStore.inboxFiles()
        } else if !openedFiles.contains(where: { PackStore.pathKey($0) == PackStore.pathKey(url) }) {
            openedFiles.append(url)
        }
    }

    /// The preview of these files was closed: files opened from elsewhere stop waiting.
    func forgetOpened(_ urls: [URL]) {
        let keys = Set(urls.map { PackStore.pathKey($0) })
        openedFiles.removeAll { keys.contains(PackStore.pathKey($0)) }
    }

    /// Reads and checks the files off the main actor; nothing is written. `progress` gets (done, total, file name).
    func stageImport(_ urls: [URL], progress: (Int, Int, String) -> Void) async -> [ImportCandidate] {
        let root = self.root
        var out: [ImportCandidate] = []
        for (i, url) in urls.enumerated() {
            if Task.isCancelled { break }
            progress(i, urls.count, url.lastPathComponent)
            let inbox = PackStore.isInInbox(url)
            let candidate = await Task.detached(priority: .userInitiated) {
                PackImporter.stage(url, fromInbox: inbox, root: root)
            }.value
            out.append(candidate)
        }
        progress(urls.count, urls.count, "")
        return out
    }

    /// Free space where packs are installed (nil when the system does not say).
    func freeSpace() -> Int64? {
        PackImporter.freeSpace(at: root)
    }

    /// Carries out one confirmed choice. The library changes only when the whole file checks out again;
    /// afterwards the list is reloaded and changed sentences go to `onArticlesChanged`, as before.
    func commitImport(_ c: ImportCandidate, choice: ImportChoice) async -> ImportOutcome {
        switch choice {
        case .skip:
            return skipOutcome(c)
        case .keepCopy:
            isImporting = true
            defer { isImporting = false }
            let docs = PackStore.documentsFolder
            do {
                let place = try await Task.detached(priority: .userInitiated) {
                    try PackImporter.keepCopy(c, documents: docs)
                }.value
                let message = "没有导入，书架不变。文件原样存到了“文件 › 我的 iPad › DayDayUp › \(place)”。"
                DiagLog.shared.log("pack", "\(c.fileName): kept a copy in \(place)")
                pendingInbox = PackStore.inboxFiles()
                return ImportOutcome(id: c.id, fileName: c.fileName, state: .kept, message: message)
            } catch {
                return failedOutcome(c, error)
            }
        case .install, .replace:
            isImporting = true
            defer { isImporting = false }
            let root = self.root
            do {
                let done = try await Task.detached(priority: .userInitiated) {
                    try PackImporter.commitInstall(c, choice: choice, root: root)
                }.value
                var message = PackImporter.successMessage(done)
                if c.fromInbox {
                    message += PackStore.moveToImportedFolder(c.url)
                        ? "文件移到了“已导入”文件夹。"
                        : "文件没能移到“已导入”文件夹，还在原处。"
                }
                reload()
                if !done.diffs.isEmpty { onArticlesChanged?(done.diffs) }
                pendingInbox = PackStore.inboxFiles()
                DiagLog.shared.log("pack", "\(c.fileName): \(message)")
                return ImportOutcome(id: c.id, fileName: c.fileName, state: .installed, message: message)
            } catch {
                return failedOutcome(c, error)
            }
        }
    }

    private func skipOutcome(_ c: ImportCandidate) -> ImportOutcome {
        switch c.kind {
        case .identical:
            var message = "已经导入过，不会重复导入。"
            if c.fromInbox {
                message += PackStore.moveToImportedFolder(c.url)
                    ? "文件移到了“已导入”文件夹。"
                    : "文件没能移到“已导入”文件夹，还在原处。"
                pendingInbox = PackStore.inboxFiles()
            }
            return ImportOutcome(id: c.id, fileName: c.fileName, state: .unchanged, message: message)
        case .invalid:
            let message = "没有导入：发现 \(c.problems.count) 个问题。原来的书架没有改动。"
            DiagLog.shared.log("pack", "\(c.fileName): refused, " + c.problems.joined(separator: "; "))
            return ImportOutcome(id: c.id, fileName: c.fileName, state: .failed, message: message)
        case .conflict:
            return ImportOutcome(id: c.id, fileName: c.fileName, state: .skipped, message: "保留当前版本，没有导入。")
        case .new, .update:
            return ImportOutcome(id: c.id, fileName: c.fileName, state: .skipped, message: "没有选，没有导入。")
        }
    }

    private func failedOutcome(_ c: ImportCandidate, _ error: Error) -> ImportOutcome {
        let reason = error.localizedDescription
        let message: String
        if let failure = error as? PackImportFailure, case .noSpace = failure {
            message = reason + "。"
        } else {
            message = "没有导入：\(reason)。原来的书架没有改动。"
        }
        DiagLog.shared.log("pack", "\(c.fileName): \(message)")
        return ImportOutcome(id: c.id, fileName: c.fileName, state: .failed, message: message)
    }

    /// After the learner's batch: one truthful line per file for 设置 and the diagnostics.
    func finishImport(_ outcomes: [ImportOutcome]) {
        guard !outcomes.isEmpty else { return }
        lastMessage = outcomes.map { "\($0.fileName)：\($0.message)" }.joined(separator: "\n")
        pendingInbox = PackStore.inboxFiles()
    }

    /// Imports one .ecopack without a preview, with the safe defaults of the preview: a new pack or a newer
    /// version is installed; an identical one is left alone; a conflict keeps the installed version.
    /// Returns a short message for the UI.
    @discardableResult
    func importPack(from url: URL, moveAfterImport: Bool = false) async -> String {
        let staged = await stageImport([url]) { _, _, _ in }
        guard let c = staged.first else { return "" }
        let choice: ImportChoice
        switch c.kind {
        case .new, .update(_, false):
            choice = .install
        default:
            choice = .skip
        }
        let outcome = await commitImport(c, choice: choice)
        var message = "\(c.fileName)：\(outcome.message)"
        if c.kind == .conflict {
            message = "\(c.fileName)：和书架上同一版本的内容不同，没有导入。请用“导入内容包”查看并选择。"
        } else if c.kind == .invalid {
            message = "导入失败：\(c.fileName)。" + c.problems.joined(separator: "；")
        }
        lastMessage = message
        return message
    }

    func delete(_ pack: InstalledPack) {
        try? FileManager.default.removeItem(at: pack.folder)
        reload()
        lastMessage = "已删除 \(pack.manifest.issue) 期内容包。你的学习记录还在。"
    }

    // MARK: File helpers (nonisolated)

    nonisolated static var documentsFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// .ecopack files in Documents and Documents/Inbox, by name.
    nonisolated static func inboxFiles() -> [URL] {
        let fm = FileManager.default
        let docs = documentsFolder
        var found: [URL] = []
        for dir in [docs, docs.appendingPathComponent("Inbox", isDirectory: true)] {
            let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            found += items.filter { $0.pathExtension.lowercased() == "ecopack" }
        }
        return found.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// True for a file directly in Documents or Documents/Inbox.
    nonisolated static func isInInbox(_ url: URL) -> Bool {
        let docs = pathKey(documentsFolder)
        let parent = pathKey(url.deletingLastPathComponent())
        return parent == docs || parent == docs + "/Inbox"
    }

    /// A path for comparing file URLs (symlinks such as /private resolved the same way on both sides).
    nonisolated static func pathKey(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// After an import from the app's folder, the file moves to Documents/已导入 so it does not wait again.
    /// Returns false when the move failed (the file is still where it was).
    @discardableResult
    nonisolated static func moveToImportedFolder(_ url: URL) -> Bool {
        let fm = FileManager.default
        var base = url.deletingLastPathComponent()
        if base.lastPathComponent == "Inbox" {      // files that arrive through "Open in"
            base = base.deletingLastPathComponent()
        }
        let dir = base.appendingPathComponent("已导入", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent(url.lastPathComponent)
        try? fm.removeItem(at: target)
        do {
            try fm.moveItem(at: url, to: target)
            return true
        } catch {
            DiagLog.shared.log("pack", "could not move \(url.lastPathComponent) to 已导入: \(error.localizedDescription)")
            return false
        }
    }

    nonisolated static func sha256<D: DataProtocol>(_ data: D) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func safeName(_ s: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        let cleaned = String(s.map { allowed.contains($0) ? $0 : "_" })
        return cleaned.isEmpty || cleaned.hasPrefix(".") ? "pack_" + cleaned : cleaned
    }
}

/// PKG-P04: what an article offers.
enum ResourceState: String, Sendable {
    case available
    case missing
    case notRequired = "not-required"

    var mark: String {
        switch self {
        case .available: return "✓"
        case .missing: return "缺"
        case .notRequired: return "不需要"
        }
    }
}

struct ArticleResources: Equatable, Sendable {
    var text: ResourceState = .available
    var audio: ResourceState = .available
    var timing: ResourceState = .available
    var wordAudio: ResourceState = .notRequired
    var senses: ResourceState = .available
    var annotations: ResourceState = .missing
    var quiz: ResourceState = .missing
    var pdf: ResourceState = .notRequired

    /// (label, state) in display order.
    var list: [(String, ResourceState)] {
        [("正文", text), ("原音", audio), ("时间轴", timing), ("词音", wordAudio), ("词义", senses),
         ("标注", annotations), ("题目", quiz), ("PDF", pdf)]
    }
}
