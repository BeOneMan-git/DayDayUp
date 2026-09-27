import Foundation
import Observation

/// Owns practice.json and the Recordings folder. Changes go through `update`, which saves shortly after.
/// Recordings are never deleted automatically.
@MainActor
@Observable
final class PracticeStore {
    private(set) var state: PracticeState
    private(set) var saveError: String?

    let fileURL: URL
    let recordingsDir: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent("practice.json")
        recordingsDir = support.appendingPathComponent("Recordings", isDirectory: true)
        try? fm.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? UserStore.decoder.decode(PracticeState.self, from: data) {
            state = loaded
        } else {
            state = PracticeState()
            if fm.fileExists(atPath: fileURL.path) {
                // Keep the unreadable file so nothing is lost; start with an empty record.
                let copy = support.appendingPathComponent("practice-unreadable-\(Int(Date().timeIntervalSince1970)).json")
                try? fm.copyItem(at: fileURL, to: copy)
                DiagLog.shared.log("practice", "practice.json unreadable, copied to \(copy.lastPathComponent)")
            }
        }
    }

    func update(_ change: (inout PracticeState) -> Void) {
        var copy = state
        change(&copy)
        guard copy != state else { return }
        state = copy
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
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
            DiagLog.shared.log("practice", "save failed: \(error.localizedDescription)")
        }
    }

    // MARK: Recordings

    func newRecordingURL() -> URL {
        recordingsDir.appendingPathComponent(UUID().uuidString + ".m4a")
    }

    func recordingURL(_ file: String?) -> URL? {
        guard let file, !file.isEmpty else { return nil }
        let url = recordingsDir.appendingPathComponent(file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Number and total size of recording files on disk.
    func recordingsOnDisk() -> (count: Int, bytes: Int) {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: recordingsDir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        var bytes = 0
        var count = 0
        for url in files where url.pathExtension.lowercased() == "m4a" {
            count += 1
            bytes += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return (count, bytes)
    }

    // MARK: 跟读

    func attempts(article: String, sid: Int) -> [ShadowAttempt] {
        state.shadow
            .filter { $0.article == article && $0.sid == sid }
            .sorted { $0.created > $1.created }
    }

    func addShadow(_ attempt: ShadowAttempt) {
        update { $0.shadow.append(attempt) }
    }

    // MARK: 口语

    func speaking(_ id: String) -> SpeakingWork? {
        state.speaking.first { $0.id == id }
    }

    func speakingWorks(prompt: String) -> [SpeakingWork] {
        state.speaking.filter { $0.promptId == prompt }.sorted { $0.created > $1.created }
    }

    func addSpeaking(_ work: SpeakingWork) {
        update { $0.speaking.append(work) }
    }

    func updateSpeaking(_ id: String, _ change: (inout SpeakingWork) -> Void) {
        update { s in
            if let i = s.speaking.firstIndex(where: { $0.id == id }) {
                change(&s.speaking[i])
            }
        }
    }

    /// True when any earlier answer to this prompt has revealed the reference.
    func referenceSeen(speakingPrompt prompt: String) -> Bool {
        state.speaking.contains { $0.promptId == prompt && $0.sawReference }
    }

    // MARK: 写作

    func writing(_ id: String) -> WritingWork? {
        state.writing.first { $0.id == id }
    }

    func writingWorks(prompt: String) -> [WritingWork] {
        state.writing.filter { $0.promptId == prompt }.sorted { $0.created > $1.created }
    }

    func addWriting(_ work: WritingWork) {
        update { $0.writing.append(work) }
    }

    func updateWriting(_ id: String, _ change: (inout WritingWork) -> Void) {
        update { s in
            if let i = s.writing.firstIndex(where: { $0.id == id }) {
                change(&s.writing[i])
            }
        }
    }

    // MARK: 报错

    func addReport(_ report: ContentReport) {
        update { $0.reports.append(report) }
        saveNow()
    }

    // MARK: Today

    struct DaySummary {
        var shadowSentences = 0
        var shadowTakes = 0
        var speaking = 0
        var writing = 0
    }

    func summary(for day: String) -> DaySummary {
        var out = DaySummary()
        let takes = state.shadow.filter { DayKey.of($0.created) == day && !$0.silent }
        out.shadowTakes = takes.count
        out.shadowSentences = Set(takes.map { "\($0.article)#\($0.sid)" }).count
        out.speaking = state.speaking.filter { DayKey.of($0.created) == day && !$0.silent }.count
        out.writing = state.writing.filter { work in
            work.versions.contains { v in v.finished.map { DayKey.of($0) == day } ?? false }
        }.count
        return out
    }

    // MARK: Restore

    /// Replaces the practice record with the backup's. Audio is never deleted:
    /// the backup's recordings are added, and every recording already on the iPad stays.
    /// New files are written to a temporary folder first, so a failure leaves the current data untouched.
    func restore(_ restored: PracticeState, recordings: [String: Data]) throws {
        let fm = FileManager.default
        let support = recordingsDir.deletingLastPathComponent()
        let temp = support.appendingPathComponent("Recordings-restore-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        do {
            for (name, data) in recordings {
                try data.write(to: temp.appendingPathComponent(name), options: .atomic)
            }
            // Keep every recording that is already here (names are UUIDs, so nothing collides).
            let existing = (try? fm.contentsOfDirectory(at: recordingsDir, includingPropertiesForKeys: nil)) ?? []
            for url in existing where recordings[url.lastPathComponent] == nil {
                try fm.copyItem(at: url, to: temp.appendingPathComponent(url.lastPathComponent))
            }
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
        let old = support.appendingPathComponent("Recordings-old-\(UUID().uuidString)", isDirectory: true)
        do {
            if fm.fileExists(atPath: recordingsDir.path) {
                try fm.moveItem(at: recordingsDir, to: old)
            }
            try fm.moveItem(at: temp, to: recordingsDir)
        } catch {
            if !fm.fileExists(atPath: recordingsDir.path), fm.fileExists(atPath: old.path) {
                try? fm.moveItem(at: old, to: recordingsDir)
            }
            try? fm.removeItem(at: temp)
            throw error
        }
        // Everything in `old` was copied into the new folder above.
        try? fm.removeItem(at: old)
        state = restored
        saveNow()
    }
}
