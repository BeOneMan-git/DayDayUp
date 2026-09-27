import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Owns user.json. All changes go through `update`, which saves shortly after.
@MainActor
@Observable
final class UserStore {
    private(set) var state: UserState
    private(set) var saveError: String?

    let fileURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent("user.json")
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? UserStore.decoder.decode(UserState.self, from: data) {
            state = loaded
        } else {
            state = UserState()
        }
    }

    var settings: ReaderSettings { state.settings }

    func update(_ change: (inout UserState) -> Void) {
        var copy = state
        change(&copy)
        guard copy != state else { return }
        state = copy
        scheduleSave()
    }

    func updateSettings(_ change: (inout ReaderSettings) -> Void) {
        update { change(&$0.settings) }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            if Task.isCancelled { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        do {
            let data = try UserStore.encoder.encode(state)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: Words

    func isKnown(_ key: String) -> Bool { state.known[key] != nil }
    func isStarred(_ key: String) -> Bool { state.star[key] != nil }

    func toggleKnown(_ key: String) {
        update { s in
            if s.known[key] != nil { s.known[key] = nil } else { s.known[key] = Date() }
        }
    }

    func toggleStar(_ key: String) {
        update { s in
            if s.star[key] != nil { s.star[key] = nil } else { s.star[key] = Date() }
        }
    }

    // MARK: Backup

    var backupOverdue: Bool {
        guard let last = state.lastBackup else { return hasActivity }
        return Date().timeIntervalSince(last) > 7 * 24 * 3600
    }

    var daysSinceBackup: Int? {
        guard let last = state.lastBackup else { return nil }
        return Int(Date().timeIntervalSince(last) / 86_400)
    }

    private var hasActivity: Bool {
        !state.daily.isEmpty || !state.star.isEmpty || !state.known.isEmpty
    }

    func backupDocument() -> BackupDocument {
        var copy = state
        copy.lastBackup = Date()
        let data = (try? UserStore.encoder.encode(copy)) ?? Data()
        return BackupDocument(data: data)
    }

    var backupFileName: String {
        "DayDayUp-备份-\(DayKey.today)"
    }

    func markBackedUp() {
        update { $0.lastBackup = Date() }
    }

    /// Reads a backup file. Throws if it is not a DayDayUp backup.
    func readBackup(at url: URL) throws -> UserState {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        return try UserStore.decoder.decode(UserState.self, from: data)
    }

    func restore(_ restored: UserState) {
        state = restored
        saveNow()
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
