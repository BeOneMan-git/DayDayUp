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

    let root: URL
    @ObservationIgnored private var lexiconTask: Task<Void, Never>?
    @ObservationIgnored private var isScanning = false
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

    // MARK: Import

    /// Imports one .ecopack. Returns a short message for the UI.
    @discardableResult
    func importPack(from url: URL, moveAfterImport: Bool = false) async -> String {
        isImporting = true
        defer { isImporting = false }
        let root = self.root
        do {
            let (manifest, changed, diffs) = try await Task.detached(priority: .userInitiated) {
                try PackStore.install(archive: url, into: root)
            }.value
            if moveAfterImport { PackStore.moveToImportedFolder(url) }
            if changed { reload() }
            if !diffs.isEmpty { onArticlesChanged?(diffs) }
            let part = manifest.parts > 1 ? "（第 \(manifest.part)/\(manifest.parts) 部分）" : ""
            let message = changed
                ? "已导入 \(manifest.issue) 期\(part)，\(manifest.articles.count) 篇"
                : "已是最新：\(manifest.issue) 期\(part)"
            lastMessage = message
            DiagLog.shared.log("pack", message)
            return message
        } catch {
            let message = "导入失败：\(url.lastPathComponent)。\(error.localizedDescription)"
            lastMessage = message
            DiagLog.shared.log("pack", message)
            return message
        }
    }

    /// Picks up .ecopack files copied into the app's Documents folder
    /// (Finder / iTunes file sharing, or Files app "On My iPad › DayDayUp").
    func scanInbox() async {
        // Launch triggers two scans (task + scene becoming active); run one at a time.
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var found: [URL] = []
        for dir in [docs, docs.appendingPathComponent("Inbox", isDirectory: true)] {
            let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            found += items.filter { $0.pathExtension.lowercased() == "ecopack" }
        }
        guard !found.isEmpty else { return }
        var messages: [String] = []
        for url in found.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            messages.append(await importPack(from: url, moveAfterImport: true))
        }
        lastMessage = messages.joined(separator: "\n")
    }

    func delete(_ pack: InstalledPack) {
        try? FileManager.default.removeItem(at: pack.folder)
        reload()
        lastMessage = "已删除 \(pack.manifest.issue) 期内容包。你的学习记录还在。"
    }

    // MARK: File work (runs off the main actor)

    nonisolated static func install(archive url: URL, into root: URL) throws -> (PackManifest, Bool, [ArticleDiff]) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let entries = try TarReader.entries(in: data)
        guard let manifestEntry = entries.first(where: { $0.name == "manifest.json" }) else {
            throw PackError.noManifest
        }
        let manifest = try JSONDecoder().decode(PackManifest.self, from: data[manifestEntry.range])
        guard manifest.format == 1 || manifest.format == 2 else { throw PackError.unsupportedFormat(manifest.format) }
        let missing = manifest.missingRequiredFields
        guard missing.isEmpty else { throw PackError.missingFields(missing) }

        // Paths must stay inside the pack folder, and each name may appear once (PKG-P02).
        var names = Set<String>()
        for entry in entries {
            let n = entry.name
            if n.hasPrefix("/") || n.contains("..") || n.contains("\\") || n.isEmpty {
                throw PackError.unsafePath(n)
            }
            if !names.insert(n).inserted { throw PackError.duplicateName(n) }
        }

        // Verify every listed file: size and SHA-256.
        for (name, info) in manifest.checks {
            guard let entry = entries.first(where: { $0.name == name }) else {
                throw PackError.missingFile(name)
            }
            guard entry.range.count == info.size, sha256(data[entry.range]) == info.sha256.lowercased() else {
                throw PackError.corrupt(name)
            }
        }
        // Every article's text and audio must be in the pack.
        for meta in manifest.articles {
            for name in ["articles/\(meta.id).json", meta.audio] where !names.contains(name) {
                throw PackError.missingFile(name)
            }
        }

        let fm = FileManager.default
        let dest = root.appendingPathComponent(safeName(manifest.packId), isDirectory: true)
        let oldManifestURL = dest.appendingPathComponent("manifest.json")
        let oldManifest = try? JSONDecoder().decode(PackManifest.self, from: Data(contentsOf: oldManifestURL))
        if let old = oldManifest, old.version == manifest.version {
            return (manifest, false, [])
        }

        // An update of an installed pack: compare sentences before the old files go away.
        var diffs: [ArticleDiff] = []
        if let old = oldManifest {
            let decoder = JSONDecoder()
            for meta in old.articles {
                let ref = ArticleRef(issue: old.issue, id: meta.id)
                guard let oldArticle = try? decoder.decode(Article.self, from: Data(contentsOf: dest.appendingPathComponent("articles/\(meta.id).json"))) else { continue }
                var newHashes: [Int: String] = [:]
                if let entry = entries.first(where: { $0.name == "articles/\(meta.id).json" }),
                   manifest.issue == old.issue,
                   let newArticle = try? decoder.decode(Article.self, from: data[entry.range]) {
                    newHashes = PackDiffer.hashes(newArticle)
                }
                let d = PackDiffer.diff(article: ref, old: PackDiffer.hashes(oldArticle), new: newHashes,
                                        idMap: manifest.idMap?[meta.id])
                if d.hasChanges { diffs.append(d) }
            }
        }

        let temp = root.appendingPathComponent(".tmp-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        do {
            for entry in entries {
                let out = temp.appendingPathComponent(entry.name)
                try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(data[entry.range]).write(to: out, options: .atomic)
            }
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
        // Swap folders so a failure never leaves the old pack half-deleted (ACC-08).
        let previous = root.appendingPathComponent(".old-\(UUID().uuidString)", isDirectory: true)
        let hadOld = fm.fileExists(atPath: dest.path)
        do {
            if hadOld { try fm.moveItem(at: dest, to: previous) }
            try fm.moveItem(at: temp, to: dest)
        } catch {
            if hadOld, !fm.fileExists(atPath: dest.path) { try? fm.moveItem(at: previous, to: dest) }
            try? fm.removeItem(at: temp)
            throw error
        }
        if hadOld { try? fm.removeItem(at: previous) }
        return (manifest, true, diffs)
    }

    /// After an automatic import, the file moves to Documents/已导入 so it is not imported again.
    nonisolated static func moveToImportedFolder(_ url: URL) {
        let fm = FileManager.default
        var base = url.deletingLastPathComponent()
        if base.lastPathComponent == "Inbox" {      // files that arrive through "Open in"
            base = base.deletingLastPathComponent()
        }
        let dir = base.appendingPathComponent("已导入", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent(url.lastPathComponent)
        try? fm.removeItem(at: target)
        try? fm.moveItem(at: url, to: target)
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
