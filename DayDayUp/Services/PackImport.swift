import Foundation

// Content pack import in two steps (IMP-F04, IMP-P04, PKG-P05, ACC-04/05/06/08):
//   stage   – read the archive (memory-mapped), check everything and compare it with the installed pack.
//             Nothing is written. Every problem is collected, none stops the check.
//   commit  – only for files the learner confirmed: check the file again, then write it into a hidden
//             temporary folder and swap folders. A failure leaves the library exactly as it was.

/// How one archive relates to the library.
enum ImportKind: Equatable {
    /// Something is wrong with the file: nothing will be written (ACC-04).
    case invalid
    /// No pack with this packId is installed.
    case new
    /// Same version and the same files as the installed pack: importing it again changes nothing (ACC-05).
    case identical
    /// Same version number, different content: the installed pack stays unless the learner chooses (ACC-06).
    case conflict
    /// A different version of an installed pack. `older`: its revision number is lower than the installed one.
    case update(installed: String, older: Bool)
}

/// What the learner chose for one file in the preview.
enum ImportChoice: String, Identifiable {
    case skip        // 不导入 / 保留当前
    case install     // 导入 or 更新
    case replace     // 冲突：替换为这个文件
    case keepCopy    // 冲突：另存副本（不导入）

    var id: String { rawValue }
}

/// Sentence-level change of one article that both versions have.
struct ArticleChange: Identifiable {
    var id: String
    var title: String
    var textFileChanged = false
    var changed = 0          // same sentence id, different text
    var added = 0            // sentence ids only in the new version
    var removed = 0          // sentence ids only in the old version
    var unmapped = 0         // old sentences without a trusted successor: their records stay as they were
    var mapped = 0           // old sentences the pack maps to a new id
    var audioChanged = false

    var sentencesSame: Bool {
        changed == 0 && added == 0 && removed == 0 && unmapped == 0 && mapped == 0
    }
}

/// What differs between the installed pack and the incoming one (新版本 or 冲突).
struct PackChanges {
    var added: [String] = []             // article titles
    var removed: [String] = []
    var changed: [ArticleChange] = []
    var newResources: [String] = []      // e.g. "发音标注 12 篇"
    var updatedResources: [String] = []
    var droppedResources: [String] = []
    var otherFiles: [String] = []
    var manifestChanged = false
    /// What `onArticlesChanged` receives after the commit (PKG-P03), computed exactly like before.
    var diffs: [ArticleDiff] = []

    var articlesSame: Bool { added.isEmpty && removed.isEmpty && changed.isEmpty }

    /// "改动 3 篇、新增 1 篇" or "文章没有变化".
    var shortSummary: String {
        var parts: [String] = []
        if !changed.isEmpty { parts.append("改动 \(changed.count) 篇") }
        if !added.isEmpty { parts.append("新增 \(added.count) 篇") }
        if !removed.isEmpty { parts.append("删掉 \(removed.count) 篇") }
        return parts.isEmpty ? "文章没有变化" : parts.joined(separator: "、")
    }

    /// Old sentences that lose their link to the new text (their records stay with the old snapshot).
    var unmappedSentences: Int {
        diffs.reduce(0) { $0 + $1.unmapped.count }
    }
}

/// One file in the preview: what it is, what is wrong with it, and how it relates to the library.
struct ImportCandidate: Identifiable {
    let id: UUID
    let url: URL
    let fileName: String
    /// The file sits in the app's Documents (or Documents/Inbox): after a successful import it moves to 已导入.
    let fromInbox: Bool
    var archiveBytes = 0
    var unpackedBytes = 0
    var manifest: PackManifest?
    var kind: ImportKind = .invalid
    var problems: [String] = []
    var notices: [String] = []
    var contents: [String] = []
    var changes: PackChanges?
    var installedVersion: String?
    /// SHA-256 over every entry's name and hash: the commit refuses a file that changed after the preview.
    var fingerprint = ""

    init(url: URL, fromInbox: Bool) {
        id = UUID()
        self.url = url
        fileName = url.lastPathComponent
        self.fromInbox = fromInbox
    }

    /// IMP-P04: a notice only, never a limit.
    var isLarge: Bool { archiveBytes >= PackImporter.largeFileBytes }

    /// Unpacked size with a 20 % margin (PKG-P05).
    var neededBytes: Int {
        Int((Double(unpackedBytes) * PackImporter.spaceFactor).rounded(.up))
    }
}

/// The result of one file after the learner pressed 导入所选.
struct ImportOutcome: Identifiable {
    enum State {
        case installed      // written into the library
        case kept           // copied or moved to 冲突副本, not installed
        case unchanged      // already imported
        case skipped        // the learner did not choose it
        case failed         // nothing was written
    }

    let id: UUID
    let fileName: String
    let state: State
    let message: String
}

enum PackImportFailure: LocalizedError {
    case unreadable(String)
    case invalid([String])
    case changedSincePreview
    case libraryChanged
    case noSpace(needed: Int, free: Int64)
    case writeFailed(String)
    case notAllowed

    var errorDescription: String? {
        switch self {
        case .unreadable(let why):
            return "读不出这个文件（\(why)）"
        case .invalid(let problems):
            return "发现 \(problems.count) 个问题：" + problems.joined(separator: "；")
        case .changedSincePreview:
            return "文件在预览之后变了，请重新选择这个文件"
        case .libraryChanged:
            return "书架上的这个内容包在预览之后变了，请重新查看"
        case .noSpace(let needed, let free):
            let need = PackImporter.sizeText(Int64(needed))
            let have = PackImporter.sizeText(free)
            return "空间不够，没有导入；原来的书架照常可用（需要约 \(need)，可用 \(have)）"
        case .writeFailed(let why):
            return "写入时出错（\(why)）"
        case .notAllowed:
            return "这个选择不适用于这个文件"
        }
    }
}

/// An archive read into memory (mapped), with the SHA-256 of every entry and every problem found.
struct PackArchive {
    let data: Data
    var entries: [TarEntry] = []
    var byName: [String: TarEntry] = [:]
    var hashes: [String: String] = [:]
    var problems: [String] = []
    var manifest: PackManifest?
    /// Article texts of the new version by article id (decoded while checking).
    var articles: [String: Article] = [:]

    init(data: Data) {
        self.data = data
    }

    var unpackedBytes: Int {
        entries.reduce(0) { $0 + $1.range.count }
    }

    var fingerprint: String {
        let lines = hashes.keys.sorted().map { name in name + ":" + (hashes[name] ?? "") }
        return PackStore.sha256(Data(lines.joined(separator: "\n").utf8))
    }
}

/// File work of the import. Everything here runs off the main actor.
enum PackImporter {
    static let largeFileBytes = 100_000_000
    static let spaceFactor = 1.2
    static let conflictFolderName = "冲突副本"

    // MARK: Stage

    /// Reads and checks one archive and compares it with the library. Writes nothing.
    static func stage(_ url: URL, fromInbox: Bool, root: URL) -> ImportCandidate {
        var candidate = ImportCandidate(url: url, fromInbox: fromInbox)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            candidate.problems = ["读不出这个文件：\(error.localizedDescription)"]
            return candidate
        }
        var archive = PackArchive(data: data)
        check(&archive)
        candidate.archiveBytes = data.count
        candidate.unpackedBytes = archive.unpackedBytes
        candidate.manifest = archive.manifest
        candidate.problems = archive.problems
        candidate.contents = contentsSummary(archive)
        candidate.fingerprint = archive.fingerprint
        if candidate.isLarge {
            candidate.notices.append("文件较大（\(sizeText(Int64(data.count)))）。导入要多等一会儿，期间请不要切走或关掉 App。")
        }
        guard archive.problems.isEmpty, let manifest = archive.manifest else {
            candidate.kind = .invalid
            return candidate
        }
        let place = classify(archive, manifest: manifest, root: root)
        candidate.kind = place.kind
        candidate.changes = place.changes
        candidate.installedVersion = place.installedVersion
        candidate.notices += place.notices
        return candidate
    }

    /// Reads the entries and checks format, required fields, paths, names, sizes, hashes and article files.
    /// Every problem is listed (ACC-04).
    static func check(_ a: inout PackArchive) {
        let scan = scanTar(a.data)
        a.problems += scan.problems
        a.entries = scan.entries
        var reportedDuplicates = Set<String>()
        for entry in a.entries {
            if a.byName[entry.name] == nil {
                a.byName[entry.name] = entry
                a.hashes[entry.name] = PackStore.sha256(a.data[entry.range])
            } else if reportedDuplicates.insert(entry.name).inserted {
                a.problems.append("有重名的文件：\(entry.name)")
            }
        }
        guard !a.entries.isEmpty || scan.problems.isEmpty else { return }
        guard let manifestEntry = a.byName["manifest.json"] else {
            a.problems.append("不是 DayDayUp 内容包：包里没有 manifest.json")
            return
        }
        let manifest: PackManifest
        do {
            manifest = try JSONDecoder().decode(PackManifest.self, from: a.data[manifestEntry.range])
        } catch {
            a.problems.append("manifest.json 读不出来（\(describe(error))）")
            return
        }
        a.manifest = manifest
        checkManifest(manifest, into: &a)
        checkFiles(manifest, into: &a)
    }

    private static func checkManifest(_ m: PackManifest, into a: inout PackArchive) {
        if m.format > 2 {
            a.problems.append("内容包格式 \(m.format) 比这个 App 新，读不了。请先更新 App")
        } else if m.format < 1 {
            a.problems.append("内容包格式 \(m.format) 不认识")
        }
        let missing = m.missingRequiredFields
        if !missing.isEmpty {
            a.problems.append("内容包说明缺少必填字段：" + missing.joined(separator: "、"))
        }
        if m.packId.trimmingCharacters(in: .whitespaces).isEmpty {
            a.problems.append("内容包说明缺少 packId")
        }
        if m.issue.trimmingCharacters(in: .whitespaces).isEmpty {
            a.problems.append("内容包说明缺少期号（issue）")
        }
    }

    private static func checkFiles(_ m: PackManifest, into a: inout PackArchive) {
        let checks = m.checks
        var missingReported = Set<String>()
        for name in checks.keys.sorted() {
            guard let info = checks[name] else { continue }
            guard let entry = a.byName[name] else {
                a.problems.append("清单里有、包里缺少的文件：\(name)")
                missingReported.insert(name)
                continue
            }
            if entry.range.count != info.size {
                a.problems.append("文件大小不对：\(name)（清单写 \(info.size) 字节，实际 \(entry.range.count) 字节）")
            } else if a.hashes[name] != info.sha256.lowercased() {
                a.problems.append("文件校验不符（SHA-256 和清单不一致）：\(name)")
            }
        }
        var ids = Set<String>()
        let decoder = JSONDecoder()
        for meta in m.articles {
            if !ids.insert(meta.id).inserted {
                a.problems.append("文章编号重复：\(meta.id)")
            }
            let textName = "articles/\(meta.id).json"
            if let entry = a.byName[textName] {
                do {
                    a.articles[meta.id] = try decoder.decode(Article.self, from: a.data[entry.range])
                } catch {
                    a.problems.append("正文读不出来：\(textName)（\(describe(error))）")
                }
            } else if !missingReported.contains(textName) {
                a.problems.append("缺少正文：\(textName)（\(meta.title)）")
            }
            if a.byName[meta.audio] == nil && !missingReported.contains(meta.audio) {
                a.problems.append("缺少音频：\(meta.audio)（\(meta.title)）")
            }
        }
    }

    /// Like TarReader, but an unsafe name is recorded and skipped instead of ending the read,
    /// so all of them can be listed. A damaged header or a cut-off file still ends the read.
    static func scanTar(_ data: Data) -> (entries: [TarEntry], problems: [String]) {
        var entries: [TarEntry] = []
        var problems: [String] = []
        let end = data.endIndex
        var offset = data.startIndex
        guard data.count >= 512 else {
            return ([], ["不是内容包文件：文件太小（\(data.count) 字节）"])
        }
        while offset + 512 <= end {
            let header = data[offset..<(offset + 512)]
            if header.allSatisfy({ $0 == 0 }) { break }
            let name = field(header, 0, 100)
            let sizeText = field(header, 124, 12)
            let typeFlag = header[header.startIndex + 156]
            let magic = field(header, 257, 6)
            let prefix = magic.hasPrefix("ustar") ? field(header, 345, 155) : ""
            guard let size = Int(sizeText, radix: 8), size >= 0 else {
                if entries.isEmpty && problems.isEmpty {
                    problems.append("不是内容包文件：文件格式不对（不是 tar 包）")
                } else {
                    problems.append("文件头损坏（\(name.isEmpty ? "?" : name)），后面的内容读不出来")
                }
                return (entries, problems)
            }
            let bodyStart = offset + 512
            let bodyEnd = bodyStart + size
            guard bodyEnd <= end else {
                problems.append("文件不完整，可能没有传完（\(name) 被截断）")
                return (entries, problems)
            }
            let fullName = prefix.isEmpty ? name : prefix + "/" + name
            if typeFlag == 0x30 || typeFlag == 0 {
                if isSafe(fullName) {
                    entries.append(TarEntry(name: fullName, range: bodyStart..<bodyEnd))
                } else {
                    problems.append("不安全的文件路径：\(fullName.isEmpty ? "（空名字）" : fullName)")
                }
            }
            offset = bodyStart + ((size + 511) / 512) * 512
        }
        return (entries, problems)
    }

    /// NUL-terminated ASCII field of a tar header, trimmed.
    private static func field(_ header: Data, _ from: Int, _ length: Int) -> String {
        let lower = header.startIndex + from
        var bytes = header[lower..<(lower + length)]
        if let zero = bytes.firstIndex(of: 0) {
            bytes = bytes[bytes.startIndex..<zero]
        }
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }

    /// Paths must stay inside the pack folder (PKG-P02). Same rule as the import always used.
    static func isSafe(_ path: String) -> Bool {
        !(path.isEmpty || path.hasPrefix("/") || path.contains("\\") || path.contains(".."))
    }

    /// A short Chinese reason for a decoding error, with the field where it happened.
    static func describe(_ error: Error) -> String {
        guard let e = error as? DecodingError else { return error.localizedDescription }
        switch e {
        case .dataCorrupted(let context):
            return context.codingPath.isEmpty ? "不是完整的 JSON" : "\(path(context.codingPath)) 的内容不对"
        case .keyNotFound(let key, let context):
            let at = path(context.codingPath)
            return at.isEmpty ? "缺少字段 \(key.stringValue)" : "\(at) 缺少字段 \(key.stringValue)"
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            let at = path(context.codingPath)
            return at.isEmpty ? "类型不对" : "\(at) 的类型不对"
        @unknown default:
            return "格式不对"
        }
    }

    private static func path(_ keys: [CodingKey]) -> String {
        var out = ""
        for key in keys {
            if let i = key.intValue {
                out += "[\(i)]"
            } else {
                out += out.isEmpty ? key.stringValue : "." + key.stringValue
            }
        }
        return out
    }

    /// What the pack holds, e.g. ["文章 12 篇", "正文 12", "原音 12", "发音标注 12", "词库 ✓"].
    static func contentsSummary(_ a: PackArchive) -> [String] {
        guard let m = a.manifest else { return [] }
        let ids = m.articles.map(\.id)
        let text = ids.filter { a.byName["articles/\($0).json"] != nil }.count
        let audio = m.articles.filter { a.byName[$0.audio] != nil }.count
        let annotations = ids.filter { a.byName["annotations/\($0).json"] != nil }.count
        let quiz = ids.filter { a.byName["quiz/\($0).json"] != nil }.count
        var out = ["文章 \(m.articles.count) 篇", "正文 \(text)", "原音 \(audio)"]
        if annotations > 0 { out.append("发音标注 \(annotations)") }
        if quiz > 0 { out.append("理解题 \(quiz)") }
        out.append(a.byName["lexicon.json"] != nil ? "词库 ✓" : "没有词库")
        return out
    }

    // MARK: Compare with the library

    struct Placement {
        var kind: ImportKind
        var changes: PackChanges?
        var installedVersion: String?
        var notices: [String] = []
    }

    /// 新增 / 已导入 / 冲突 / 新版本, against the installed pack with the same packId.
    static func classify(_ a: PackArchive, manifest m: PackManifest, root: URL) -> Placement {
        let fm = FileManager.default
        let folder = root.appendingPathComponent(PackStore.safeName(m.packId), isDirectory: true)
        var notices = overlapNotices(m, root: root)
        let oldBlob = try? Data(contentsOf: folder.appendingPathComponent("manifest.json"))
        guard let oldData = oldBlob, let old = try? JSONDecoder().decode(PackManifest.self, from: oldData) else {
            if fm.fileExists(atPath: folder.path) {
                notices.append("书架上有一个同名但读不出来的内容包，导入后会被这个替换。")
            }
            return Placement(kind: .new, notices: notices)
        }
        let installed = versionText(old)
        if old.version != m.version {
            var older = false
            if let o = old.packageRevision, let n = m.packageRevision { older = n < o }
            if older {
                notices.append("这个文件比书架上的旧（书架上是 \(installed)）。一般不需要导入。")
            }
            let changes = compare(old: old, oldManifestData: oldData, folder: folder, new: m, archive: a)
            return Placement(kind: .update(installed: installed, older: older), changes: changes,
                             installedVersion: installed, notices: notices)
        }
        if sameFiles(a, folder: folder, installed: old, installedManifestData: oldData) {
            return Placement(kind: .identical, installedVersion: installed, notices: notices)
        }
        let changes = compare(old: old, oldManifestData: oldData, folder: folder, new: m, archive: a)
        return Placement(kind: .conflict, changes: changes, installedVersion: installed, notices: notices)
    }

    /// Another installed pack (different packId) already has some of these articles.
    private static func overlapNotices(_ m: PackManifest, root: URL) -> [String] {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let mine = Set(m.articles.map(\.id))
        var out: [String] = []
        let decoder = JSONDecoder()
        for dir in dirs where !dir.lastPathComponent.hasPrefix(".") {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
                  let other = try? decoder.decode(PackManifest.self, from: data),
                  other.packId != m.packId, other.issue == m.issue else { continue }
            let shared = mine.intersection(other.articles.map(\.id)).count
            if shared > 0 {
                out.append("有 \(shared) 篇文章已经在内容包 \(other.packId) 里。两个都留着的话，书架上会出现两次；可以在设置里删掉不要的那个。")
            }
        }
        return out
    }

    /// Same file names and the same bytes as the installed folder (ACC-05).
    private static func sameFiles(_ a: PackArchive, folder: URL, installed: PackManifest,
                                  installedManifestData: Data) -> Bool {
        guard installedFiles(folder) == Set(a.byName.keys) else { return false }
        let checks = installed.checks
        for (name, sha) in a.hashes {
            if name == "manifest.json" {
                if PackStore.sha256(installedManifestData) != sha { return false }
            } else if let known = checks[name]?.sha256.lowercased() {
                // Verified against this hash when it was installed.
                if known != sha { return false }
            } else if installedSha(folder.appendingPathComponent(name)) != sha {
                return false
            }
        }
        return true
    }

    /// Relative paths of the regular files in an installed pack folder.
    private static func installedFiles(_ folder: URL) -> Set<String> {
        let fm = FileManager.default
        let listed = (try? fm.subpathsOfDirectory(atPath: folder.path)) ?? []
        var out = Set<String>()
        for rel in listed {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: folder.appendingPathComponent(rel).path, isDirectory: &isDir), !isDir.boolValue {
                out.insert(rel)
            }
        }
        return out
    }

    private static func installedSha(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return PackStore.sha256(data)
    }

    /// Articles added / removed / changed (with the sentence diff), resources, other files,
    /// and the diffs for the learner's records.
    static func compare(old: PackManifest, oldManifestData: Data, folder: URL, new m: PackManifest,
                        archive a: PackArchive) -> PackChanges {
        var ch = PackChanges()
        let oldChecks = old.checks
        func oldSha(_ name: String) -> String? {
            if let s = oldChecks[name]?.sha256.lowercased() { return s }
            return installedSha(folder.appendingPathComponent(name))
        }
        let decoder = JSONDecoder()
        var oldIds = Set<String>()
        for meta in old.articles { oldIds.insert(meta.id) }
        var newIds = Set<String>()
        for meta in m.articles { newIds.insert(meta.id) }
        ch.added = m.articles.filter { !oldIds.contains($0.id) }.map(\.title)
        ch.removed = old.articles.filter { !newIds.contains($0.id) }.map(\.title)
        ch.manifestChanged = PackStore.sha256(oldManifestData) != a.hashes["manifest.json"]

        // The sentence diff of every old article (PKG-P03), exactly as the import always did it.
        var diffById: [String: ArticleDiff] = [:]
        var oldHashesById: [String: [Int: String]] = [:]
        var newHashesById: [String: [Int: String]] = [:]
        for meta in old.articles {
            let ref = ArticleRef(issue: old.issue, id: meta.id)
            let oldURL = folder.appendingPathComponent("articles/\(meta.id).json")
            guard let oldArticle = try? decoder.decode(Article.self, from: Data(contentsOf: oldURL)) else { continue }
            let oldHashes = PackDiffer.hashes(oldArticle)
            var newHashes: [Int: String] = [:]
            if m.issue == old.issue, let fresh = incomingArticle(meta.id, in: a, decoder: decoder) {
                newHashes = PackDiffer.hashes(fresh)
            }
            let d = PackDiffer.diff(article: ref, old: oldHashes, new: newHashes, idMap: m.idMap?[meta.id])
            diffById[meta.id] = d
            oldHashesById[meta.id] = oldHashes
            newHashesById[meta.id] = newHashes
            if d.hasChanges { ch.diffs.append(d) }
        }

        let oldById = Dictionary(old.articles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for meta in m.articles {
            guard let oldMeta = oldById[meta.id] else { continue }
            let textName = "articles/\(meta.id).json"
            let textChanged = oldSha(textName) != a.hashes[textName]
            let audioChanged = oldSha(oldMeta.audio) != a.hashes[meta.audio]
            guard textChanged || audioChanged else { continue }
            var change = ArticleChange(id: meta.id, title: meta.title)
            change.textFileChanged = textChanged
            change.audioChanged = audioChanged
            let oldHashes = oldHashesById[meta.id] ?? [:]
            let newHashes = newHashesById[meta.id] ?? [:]
            let oldKeys = Set(oldHashes.keys)
            let newKeys = Set(newHashes.keys)
            change.changed = oldKeys.intersection(newKeys).filter { oldHashes[$0] != newHashes[$0] }.count
            change.added = newKeys.subtracting(oldKeys).count
            change.removed = oldKeys.subtracting(newKeys).count
            if let d = diffById[meta.id] {
                change.unmapped = d.unmapped.count
                change.mapped = d.mapped.count
            }
            ch.changed.append(change)
        }

        compareResources(old: old, folder: folder, new: m, archive: a, oldSha: oldSha, into: &ch)
        return ch
    }

    private static func incomingArticle(_ id: String, in a: PackArchive, decoder: JSONDecoder) -> Article? {
        if let article = a.articles[id] { return article }
        guard let entry = a.byName["articles/\(id).json"] else { return nil }
        return try? decoder.decode(Article.self, from: a.data[entry.range])
    }

    /// 发音标注 / 理解题 / 词库 that arrive, change or disappear, and any other file that differs.
    private static func compareResources(old: PackManifest, folder: URL, new m: PackManifest, archive a: PackArchive,
                                         oldSha: (String) -> String?, into ch: inout PackChanges) {
        let oldFiles = installedFiles(folder)
        let newFiles = Set(a.byName.keys)
        let ids = m.articles.map(\.id)
        let kinds: [(folder: String, title: String)] = [("annotations", "发音标注"), ("quiz", "理解题")]
        for kind in kinds {
            var arrived = 0
            var updated = 0
            var dropped = 0
            for id in ids {
                let name = "\(kind.folder)/\(id).json"
                let inNew = newFiles.contains(name)
                let inOld = oldFiles.contains(name)
                if inNew && !inOld { arrived += 1 }
                if inNew && inOld && oldSha(name) != a.hashes[name] { updated += 1 }
                if !inNew && inOld { dropped += 1 }
            }
            if arrived > 0 { ch.newResources.append("\(kind.title) \(arrived) 篇") }
            if updated > 0 { ch.updatedResources.append("\(kind.title) \(updated) 篇") }
            if dropped > 0 { ch.droppedResources.append("\(kind.title) \(dropped) 篇") }
        }
        let lexicon = "lexicon.json"
        if newFiles.contains(lexicon) && !oldFiles.contains(lexicon) { ch.newResources.append("词库") }
        if newFiles.contains(lexicon) && oldFiles.contains(lexicon) && oldSha(lexicon) != a.hashes[lexicon] {
            ch.updatedResources.append("词库")
        }
        if !newFiles.contains(lexicon) && oldFiles.contains(lexicon) { ch.droppedResources.append("词库") }

        // Anything else that differs (article texts and audio are described above).
        var known: Set<String> = ["manifest.json", lexicon]
        for meta in old.articles { known.insert(meta.audio) }
        for meta in m.articles { known.insert(meta.audio) }
        let described = ["articles/", "annotations/", "quiz/"]
        for name in oldFiles.union(newFiles).sorted() {
            if known.contains(name) { continue }
            if described.contains(where: { name.hasPrefix($0) }) { continue }
            let inNew = newFiles.contains(name)
            let inOld = oldFiles.contains(name)
            if inNew != inOld || (inNew && oldSha(name) != a.hashes[name]) {
                ch.otherFiles.append(name)
            }
        }
    }

    // MARK: Commit

    struct Installed {
        var manifest: PackManifest
        var kind: ImportKind
        var diffs: [ArticleDiff]
        var changes: PackChanges?
    }

    /// Checks the file again (it must be the one that was previewed, and the library must be as it was),
    /// checks the space, then writes a temporary folder and swaps it in.
    static func commitInstall(_ expected: ImportCandidate, choice: ImportChoice, root: URL) throws -> Installed {
        let url = expected.url
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw PackImportFailure.unreadable(error.localizedDescription)
        }
        var archive = PackArchive(data: data)
        check(&archive)
        guard archive.problems.isEmpty, let manifest = archive.manifest else {
            throw PackImportFailure.invalid(archive.problems)
        }
        guard archive.fingerprint == expected.fingerprint else { throw PackImportFailure.changedSincePreview }
        let now = classify(archive, manifest: manifest, root: root)
        guard now.kind == expected.kind else { throw PackImportFailure.libraryChanged }
        switch (now.kind, choice) {
        case (.new, .install), (.update, .install), (.conflict, .replace):
            break
        default:
            throw PackImportFailure.notAllowed
        }
        let needed = Int((Double(archive.unpackedBytes) * spaceFactor).rounded(.up))
        if let free = freeSpace(at: root), Int64(needed) > free {
            throw PackImportFailure.noSpace(needed: needed, free: free)
        }
        try write(archive, packId: manifest.packId, root: root)
        return Installed(manifest: manifest, kind: now.kind, diffs: now.changes?.diffs ?? [], changes: now.changes)
    }

    /// Writes every entry into a hidden temporary folder, then swaps folders, so a failure never leaves
    /// a half-written or half-deleted pack (ACC-04, ACC-08).
    private static func write(_ a: PackArchive, packId: String, root: URL) throws {
        let fm = FileManager.default
        let dest = root.appendingPathComponent(PackStore.safeName(packId), isDirectory: true)
        let temp = root.appendingPathComponent(".tmp-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: temp, withIntermediateDirectories: true)
            for entry in a.entries {
                let out = temp.appendingPathComponent(entry.name)
                try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
                try a.data[entry.range].write(to: out, options: .atomic)
            }
        } catch {
            try? fm.removeItem(at: temp)
            throw PackImportFailure.writeFailed(error.localizedDescription)
        }
        let previous = root.appendingPathComponent(".old-\(UUID().uuidString)", isDirectory: true)
        let hadOld = fm.fileExists(atPath: dest.path)
        do {
            if hadOld { try fm.moveItem(at: dest, to: previous) }
            try fm.moveItem(at: temp, to: dest)
        } catch {
            if hadOld, !fm.fileExists(atPath: dest.path) { try? fm.moveItem(at: previous, to: dest) }
            try? fm.removeItem(at: temp)
            throw PackImportFailure.writeFailed(error.localizedDescription)
        }
        if hadOld { try? fm.removeItem(at: previous) }
    }

    /// 另存副本: the file goes untouched into Documents/冲突副本 (moved when it came from the app's folder,
    /// copied otherwise). Nothing is installed. Returns the place shown to the learner.
    static func keepCopy(_ c: ImportCandidate, documents: URL) throws -> String {
        let fm = FileManager.default
        let dir = documents.appendingPathComponent(conflictFolderName, isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw PackImportFailure.writeFailed(error.localizedDescription)
        }
        let target = uniqueURL(in: dir, name: c.fileName)
        if c.fromInbox {
            do {
                try fm.moveItem(at: c.url, to: target)
            } catch {
                throw PackImportFailure.writeFailed(error.localizedDescription)
            }
        } else {
            let scoped = c.url.startAccessingSecurityScopedResource()
            defer { if scoped { c.url.stopAccessingSecurityScopedResource() } }
            if let free = freeSpace(at: dir), Int64(c.archiveBytes) > free {
                throw PackImportFailure.noSpace(needed: c.archiveBytes, free: free)
            }
            let part = dir.appendingPathComponent(".\(UUID().uuidString)" + partialSuffix)
            do {
                try fm.copyItem(at: c.url, to: part)
                try fm.moveItem(at: part, to: target)
            } catch {
                try? fm.removeItem(at: part)
                throw PackImportFailure.writeFailed(error.localizedDescription)
            }
        }
        return conflictFolderName + "/" + target.lastPathComponent
    }

    static let partialSuffix = ".ecopack-part"

    /// Removes half-finished copies in Documents/冲突副本 (the app stopped during a copy).
    static func cleanPartialCopies(documents: URL) {
        let fm = FileManager.default
        let dir = documents.appendingPathComponent(conflictFolderName, isDirectory: true)
        let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for url in items where url.lastPathComponent.hasPrefix(".") && url.lastPathComponent.hasSuffix(partialSuffix) {
            try? fm.removeItem(at: url)
        }
    }

    /// "name.ecopack", "name (2).ecopack", …
    static func uniqueURL(in dir: URL, name: String) -> URL {
        let fm = FileManager.default
        var url = dir.appendingPathComponent(name)
        let plain = URL(fileURLWithPath: name)
        let base = plain.deletingPathExtension().lastPathComponent
        let ext = plain.pathExtension
        var n = 2
        while fm.fileExists(atPath: url.path) {
            let next = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            url = dir.appendingPathComponent(next)
            n += 1
        }
        return url
    }

    // MARK: Space and wording

    /// Free space of the volume that holds `url` (PKG-P05), nil when the system does not say.
    static func freeSpace(at url: URL) -> Int64? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 {
            return important
        }
        return values.volumeAvailableCapacity.map { Int64($0) }
    }

    static func sizeText(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_000_000
        if mb >= 1000 { return String(format: "%.1f GB", mb / 1000) }
        if mb >= 100 { return String(format: "%.0f MB", mb) }
        return String(format: "%.1f MB", mb)
    }

    static func issueText(_ m: PackManifest) -> String {
        m.parts > 1 ? "\(m.issue) 期（第 \(m.part)/\(m.parts) 部分）" : "\(m.issue) 期"
    }

    static func versionText(_ m: PackManifest) -> String {
        guard let revision = m.packageRevision else { return m.version }
        return "\(m.version)（第 \(revision) 版）"
    }

    /// "2026-09-05 期 · 12 篇 · 版本 …".
    static func packLine(_ m: PackManifest) -> String {
        "\(issueText(m)) · \(m.articles.count) 篇 · 版本 \(versionText(m))"
    }

    static func successMessage(_ done: Installed) -> String {
        let m = done.manifest
        let what = issueText(m)
        switch done.kind {
        case .update(let installed, _):
            var text = "已把 \(what) 从 \(installed) 更新到 \(versionText(m))"
            if let changes = done.changes { text += "：" + changes.shortSummary }
            let unmapped = done.diffs.reduce(0) { $0 + $1.unmapped.count }
            if unmapped > 0 { text += "；\(unmapped) 句无法对应，旧记录保留" }
            return text + "。"
        case .conflict:
            return "已用这个文件替换 \(what)（同一版本 \(versionText(m))）。"
        default:
            return "已导入 \(what)，\(m.articles.count) 篇。"
        }
    }
}
