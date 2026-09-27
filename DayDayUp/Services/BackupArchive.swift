import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// Full backup: a ustar tar with user.json, practice.json and the recordings.
    /// Declared in Info.plist (UTExportedTypeDeclarations), extension .ddubackup.
    static let ddubackup = UTType(exportedAs: "com.daydayup.backup")
}

/// Minimal ustar writer, the counterpart of TarReader.
/// Names must be ASCII and at most 100 bytes.
enum TarWriter {
    static func archive(_ files: [(name: String, data: Data)], modified: Date = Date()) -> Data {
        var out = Data()
        let mtime = max(0, Int(modified.timeIntervalSince1970))
        for file in files {
            var header = [UInt8](repeating: 0, count: 512)
            put(&header, at: 0, length: 100, file.name)
            put(&header, at: 100, length: 8, "0000644")
            put(&header, at: 108, length: 8, "0000000")
            put(&header, at: 116, length: 8, "0000000")
            put(&header, at: 124, length: 12, octal(file.data.count, width: 11))
            put(&header, at: 136, length: 12, octal(mtime, width: 11))
            for i in 148..<156 { header[i] = 0x20 }        // checksum counts as spaces
            header[156] = 0x30                               // "0" = regular file
            put(&header, at: 257, length: 6, "ustar")        // "ustar\0"
            put(&header, at: 263, length: 2, "00")
            let sum = header.reduce(0) { $0 + Int($1) }
            put(&header, at: 148, length: 6, octal(sum, width: 6))
            header[154] = 0
            header[155] = 0x20
            out.append(contentsOf: header)
            out.append(file.data)
            let pad = (512 - file.data.count % 512) % 512
            if pad > 0 { out.append(Data(count: pad)) }
        }
        out.append(Data(count: 1024))                        // end-of-archive marker
        return out
    }

    static func octal(_ value: Int, width: Int) -> String {
        let digits = String(value, radix: 8)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }

    private static func put(_ header: inout [UInt8], at offset: Int, length: Int, _ text: String) {
        for (i, byte) in text.utf8.prefix(length).enumerated() {
            header[offset + i] = byte
        }
    }
}

struct BackupMeta: Codable {
    var format: Int
    var created: Date
    var app: String
    var starred: Int
    var known: Int
    var days: Int
    var shadow: Int
    var speaking: Int
    var writing: Int
    var recordings: Int
    // Format 2 (V0.3+): the vocabulary files and any other data files in the backup.
    var vocabItems: Int?
    var vocabCards: Int?
    var vocabEvents: Int?
    var dataFiles: [String]?
}

/// What a backup file contains, read back before anything is replaced.
struct BackupContents {
    var meta: BackupMeta?
    var user: UserState
    var practice: PracticeState?          // nil for an old V0.1 backup (user.json only)
    var recordings: [String: Data]
    var missingRecordings: Int
    var vocab: VocabState? = nil          // nil for backups made before V0.3
    var vocabEvents: [ReviewEvent] = []
    var badEventLines = 0
    /// Other data files by name (annotations, plans …), restored by their own stores.
    var files: [String: Data] = [:]

    var summary: String {
        var lines = ["生词 \(user.star.count) 个，认识的词 \(user.known.count) 个，听读记录 \(user.daily.count) 天。"]
        if let p = practice {
            let writingDone = p.writing.filter { !$0.isDraft }.count
            lines.append("跟读 \(p.shadow.count) 次，口语 \(p.speaking.count) 次，写作 \(writingDone) 篇，录音 \(recordings.count) 个。")
            if missingRecordings > 0 {
                lines.append("注意：有 \(missingRecordings) 个录音不在备份里，恢复后这些条目只有文字记录。")
            }
        } else {
            lines.append("这是 V0.1 的旧备份，只含单词和听读记录；恢复时现有的跟读和说写记录保持不变。")
        }
        if let v = vocab {
            lines.append("词汇：条目 \(v.items.count) 个，复习卡 \(v.cards.count) 张，作答记录 \(vocabEvents.count) 条。")
            if badEventLines > 0 {
                lines.append("注意：有 \(badEventLines) 行作答记录读不出来，会被跳过。")
            }
        } else {
            lines.append("这个备份比 V0.3 早，没有词汇复习记录；恢复时现有的词汇记录保持不变。")
        }
        return lines.joined(separator: "\n")
    }
}

enum BackupError: LocalizedError {
    case missingUserFile
    case missingPracticeFile

    var errorDescription: String? {
        switch self {
        case .missingUserFile: return "备份里没有 user.json"
        case .missingPracticeFile: return "备份里没有 practice.json，文件可能不完整"
        }
    }
}

enum BackupArchive {
    /// 1 = V0.2 (user, practice, recordings); 2 = V0.3+ (adds vocab.json, vocab-events.jsonl, other data files).
    static let format = 2

    /// Builds a full backup. Every .m4a in the Recordings folder is included.
    @MainActor
    static func make(user: UserStore, practice: PracticeStore,
                     extraFiles: [(name: String, data: Data)] = []) throws -> Data {
        var userState = user.state
        userState.lastBackup = Date()
        let userData = try UserStore.encoder.encode(userState)
        let practiceData = try UserStore.encoder.encode(practice.state)

        var recordings: [(name: String, data: Data)] = []
        let urls = (try? FileManager.default.contentsOfDirectory(at: practice.recordingsDir,
                                                                 includingPropertiesForKeys: nil)) ?? []
        let files = urls
            .filter { $0.pathExtension.lowercased() == "m4a" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in files {
            if let data = try? Data(contentsOf: url) {
                recordings.append((name: "recordings/" + url.lastPathComponent, data: data))
            } else {
                DiagLog.shared.log("backup", "could not read \(url.lastPathComponent)")
            }
        }

        let p = practice.state
        var meta = BackupMeta(format: format, created: Date(), app: appVersionText(),
                              starred: userState.star.count, known: userState.known.count,
                              days: userState.daily.count, shadow: p.shadow.count,
                              speaking: p.speaking.count, writing: p.writing.count,
                              recordings: recordings.count)
        meta.dataFiles = extraFiles.map(\.name)
        if let v = extraFiles.first(where: { $0.name == "vocab.json" }),
           let state = try? DataCoding.decoder.decode(VocabState.self, from: v.data) {
            meta.vocabItems = state.items.count
            meta.vocabCards = state.cards.count
        }
        if let e = extraFiles.first(where: { $0.name == "vocab-events.jsonl" }) {
            meta.vocabEvents = JSONLines<ReviewEvent>.decode(e.data).records.count
        }
        let metaData = try UserStore.encoder.encode(meta)
        let head: [(name: String, data: Data)] = [
            (name: "ddubackup.json", data: metaData),
            (name: "user.json", data: userData),
            (name: "practice.json", data: practiceData),
        ]
        return TarWriter.archive(head + extraFiles + recordings)
    }

    /// Reads a full backup (.ddubackup) or an old V0.1 backup (plain user.json).
    @MainActor
    static func read(_ data: Data) throws -> BackupContents {
        guard isTar(data) else {
            let user = try UserStore.decoder.decode(UserState.self, from: data)
            return BackupContents(meta: nil, user: user, practice: nil, recordings: [:], missingRecordings: 0)
        }
        let entries = try TarReader.entries(in: data)
        func body(_ name: String) -> Data? {
            guard let entry = entries.first(where: { $0.name == name }) else { return nil }
            return Data(data[entry.range])
        }
        guard let userData = body("user.json") else { throw BackupError.missingUserFile }
        let user = try UserStore.decoder.decode(UserState.self, from: userData)
        let meta = body("ddubackup.json").flatMap { try? UserStore.decoder.decode(BackupMeta.self, from: $0) }
        guard let practiceData = body("practice.json") else { throw BackupError.missingPracticeFile }
        let practice = try UserStore.decoder.decode(PracticeState.self, from: practiceData)

        var recordings: [String: Data] = [:]
        let prefix = "recordings/"
        for entry in entries where entry.name.hasPrefix(prefix) {
            let name = String(entry.name.dropFirst(prefix.count))
            guard !name.isEmpty, !name.contains("/") else { continue }
            recordings[name] = Data(data[entry.range])
        }
        var contents = BackupContents(meta: meta, user: user, practice: practice,
                                      recordings: recordings, missingRecordings: 0)
        if let v = body("vocab.json") {
            contents.vocab = try DataCoding.decoder.decode(VocabState.self, from: v)
            let events = JSONLines<ReviewEvent>.decode(body("vocab-events.jsonl") ?? Data())
            contents.vocabEvents = events.records
            contents.badEventLines = events.badLines
        }
        for entry in entries where !entry.name.hasPrefix(prefix) && !entry.name.contains("/") {
            let known = ["ddubackup.json", "user.json", "practice.json", "vocab.json", "vocab-events.jsonl"]
            if !known.contains(entry.name) {
                contents.files[entry.name] = Data(data[entry.range])
            }
        }
        var referenced = Set(practice.shadow.compactMap { $0.file } + practice.speaking.compactMap { $0.file })
        referenced.formUnion(practice.shadow.compactMap { $0.followFile })
        referenced.formUnion(contents.vocabEvents.compactMap { $0.evidence }.filter { $0.hasSuffix(".m4a") })
        contents.missingRecordings = referenced.subtracting(recordings.keys).count
        return contents
    }

    static func isTar(_ data: Data) -> Bool {
        guard data.count >= 512 else { return false }
        let start = data.startIndex + 257
        return Array(data[start..<(start + 5)]) == Array("ustar".utf8)
    }

    static func appVersionText() -> String {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info?["CFBundleVersion"] as? String) ?? "?"
        return "\(version)（build \(build)）"
    }
}
