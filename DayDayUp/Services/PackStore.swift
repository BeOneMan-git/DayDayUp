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

    var errorDescription: String? {
        switch self {
        case .noManifest: return "不是 DayDayUp 内容包（没有 manifest.json）"
        case .unsupportedFormat(let f): return "内容包格式 \(f) 太新，请先更新 App"
        case .missingFile(let n): return "内容包缺少文件 \(n)"
        case .corrupt(let n): return "文件校验失败：\(n)"
        case .notInstalled: return "这篇文章的内容包还没导入"
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

    init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = support.appendingPathComponent("Packs", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
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
            let (manifest, changed) = try await Task.detached(priority: .userInitiated) {
                try PackStore.install(archive: url, into: root)
            }.value
            if moveAfterImport { PackStore.moveToImportedFolder(url) }
            if changed { reload() }
            let part = manifest.parts > 1 ? "（第 \(manifest.part)/\(manifest.parts) 部分）" : ""
            let message = changed
                ? "已导入 \(manifest.issue) 期\(part)，\(manifest.articles.count) 篇"
                : "已是最新：\(manifest.issue) 期\(part)"
            lastMessage = message
            return message
        } catch {
            let message = "导入失败：\(url.lastPathComponent)。\(error.localizedDescription)"
            lastMessage = message
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

    nonisolated static func install(archive url: URL, into root: URL) throws -> (PackManifest, Bool) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let entries = try TarReader.entries(in: data)
        guard let manifestEntry = entries.first(where: { $0.name == "manifest.json" }) else {
            throw PackError.noManifest
        }
        let manifest = try JSONDecoder().decode(PackManifest.self, from: data[manifestEntry.range])
        guard manifest.format == 1 else { throw PackError.unsupportedFormat(manifest.format) }

        // Verify every listed file: size and SHA-256.
        if let files = manifest.files {
            for (name, info) in files {
                guard let entry = entries.first(where: { $0.name == name }) else {
                    throw PackError.missingFile(name)
                }
                guard entry.range.count == info.size, sha256(data[entry.range]) == info.sha256.lowercased() else {
                    throw PackError.corrupt(name)
                }
            }
        }

        let fm = FileManager.default
        let dest = root.appendingPathComponent(safeName(manifest.packId), isDirectory: true)
        let oldManifestURL = dest.appendingPathComponent("manifest.json")
        if let old = try? JSONDecoder().decode(PackManifest.self, from: Data(contentsOf: oldManifestURL)),
           old.version == manifest.version {
            return (manifest, false)
        }

        let temp = root.appendingPathComponent(".tmp-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        do {
            for entry in entries {
                let out = temp.appendingPathComponent(entry.name)
                try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(data[entry.range]).write(to: out, options: .atomic)
            }
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.moveItem(at: temp, to: dest)
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
        return (manifest, true)
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
