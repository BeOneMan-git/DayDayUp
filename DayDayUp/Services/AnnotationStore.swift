import Foundation
import Observation

/// Practice modes that remember their own set of annotation layers (UI-P05).
enum ShadowMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case repeatAfter = "repeat"   // 听后模仿 (SHD-F01)
    case shadowing = "shadow"     // 影子跟读 (SHD-F02)
    case readAloud = "read"       // 独立朗读 (SHD-F03)
    case retell = "retell"        // 脱稿复述 (SHD-F04)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .repeatAfter: return "听后模仿"
        case .shadowing: return "影子跟读"
        case .readAloud: return "独立朗读"
        case .retell: return "脱稿复述"
        }
    }

    var english: String {
        switch self {
        case .repeatAfter: return "Listen & Repeat"
        case .shadowing: return "Shadowing"
        case .readAloud: return "Read Aloud"
        case .retell: return "Retelling"
        }
    }

    var detail: String {
        switch self {
        case .repeatAfter: return "听一句 → 停 → 录音模仿 → A/B 对照。更像原声，不等于能即兴表达。"
        case .shadowing: return "跟着原音同时念，练节奏。建议戴耳机；可以先不录音。"
        case .readAloud: return "关掉原音，看着文字读一句或一段。只反映朗读。"
        case .retell: return "收起原文，讲主旨和要点，再答一个追问。允许改写和压缩。"
        }
    }
}

/// Owns annotations-user.json: the learner's status changes, hidden marks, notes and reports on
/// pronunciation annotations, and which layers each practice mode shows.
@MainActor
@Observable
final class AnnotationStore {
    private(set) var state: AnnotationUserFile
    private(set) var saveError: String?
    let fileURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent("annotations-user.json")
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? DataCoding.decoder.decode(AnnotationUserFile.self, from: data) {
            state = loaded
        } else {
            state = AnnotationUserFile()
            if fm.fileExists(atPath: fileURL.path) {
                let copy = support.appendingPathComponent("annotations-user-unreadable-\(Int(Date().timeIntervalSince1970)).json")
                try? fm.copyItem(at: fileURL, to: copy)
                DiagLog.shared.log("annotations", "annotations-user.json unreadable, copied to \(copy.lastPathComponent)")
            }
        }
    }

    // MARK: Saving

    private func update(_ change: (inout AnnotationUserFile) -> Void) {
        var copy = state
        change(&copy)
        guard copy != state else { return }
        state = copy
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        do {
            let data = try DataCoding.encoder.encode(state)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            saveError = nil
        } catch {
            saveError = error.localizedDescription
            DiagLog.shared.log("annotations", "save failed: \(error.localizedDescription)")
        }
    }

    // MARK: Layers per mode (UI-P05)

    func layers(for mode: ShadowMode) -> Set<AnnLayer> {
        if let raw = state.layers[mode.rawValue] {
            return Set(raw.compactMap(AnnLayer.init(rawValue:)))
        }
        return Set(AnnLayer.allCases.filter(\.defaultOn))
    }

    func setLayer(_ layer: AnnLayer, on: Bool, for mode: ShadowMode) {
        var set = layers(for: mode)
        if on { set.insert(layer) } else { set.remove(layer) }
        let ordered = AnnLayer.allCases.filter { set.contains($0) }.map(\.rawValue)
        update { $0.layers[mode.rawValue] = ordered }
    }

    /// 入门预设: 意群 + 重音 + 连读.
    func applyBeginnerPreset(for mode: ShadowMode) {
        update { $0.layers[mode.rawValue] = [AnnLayer.thought, .stress, .linking].map(\.rawValue) }
    }

    func resetLayers(for mode: ShadowMode) {
        update { $0.layers[mode.rawValue] = nil }
    }

    // MARK: The learner's changes (SHD-AS)

    /// Annotations of one sentence with the learner's changes applied. `stale` = the sentence text changed
    /// since the annotations were made, so none are shown (ACC-22).
    func resolved(file: AnnotationFile?, ref: ArticleRef, sentence: Sent) -> (items: [EffectiveAnnotation], stale: Bool) {
        AnnotationResolver.resolve(file: file, ref: ref, sentence: sentence, user: state)
    }

    private func edit(ref: ArticleRef, sentence: Sent, id: String, _ change: (inout AnnUserState) -> Void) {
        let key = AnnotationResolver.key(ref: ref, id: id)
        let hash = SentenceText.hash(SentenceText.plain(sentence))
        update { s in
            var entry = s.entries[key] ?? AnnUserState(sentenceHash: hash, updated: Date())
            if entry.sentenceHash != hash {
                // Made on an older text: start over for the current text.
                entry = AnnUserState(sentenceHash: hash, updated: Date())
            }
            change(&entry)
            entry.updated = Date()
            s.entries[key] = entry
        }
    }

    func setStatus(_ status: AnnStatus?, ref: ArticleRef, sentence: Sent, id: String) {
        edit(ref: ref, sentence: sentence, id: id) { $0.status = status }
    }

    func setHidden(_ hidden: Bool, ref: ArticleRef, sentence: Sent, id: String) {
        edit(ref: ref, sentence: sentence, id: id) { $0.hidden = hidden }
    }

    func setNote(_ note: String?, ref: ArticleRef, sentence: Sent, id: String) {
        let clean = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        edit(ref: ref, sentence: sentence, id: id) { $0.note = (clean?.isEmpty ?? true) ? nil : clean }
    }

    /// 报错: records the report and hides the mark until the learner shows it again.
    func report(kind: String, note: String, ref: ArticleRef, sentence: Sent, id: String) {
        edit(ref: ref, sentence: sentence, id: id) {
            $0.reports.append(AnnReport(at: Date(), kind: kind, note: note))
            $0.hidden = true
        }
        DiagLog.shared.log("annotations", "report \(kind) \(ref.key)#\(id)")
    }

    /// Number of reported annotations (for the diagnostics export).
    var reportCount: Int {
        state.entries.values.reduce(0) { $0 + $1.reports.count }
    }

    // MARK: Backup

    func backupFile() throws -> (name: String, data: Data) {
        (name: "annotations-user.json", data: try DataCoding.encoder.encode(state))
    }

    func restore(_ data: Data) throws {
        let restored = try DataCoding.decoder.decode(AnnotationUserFile.self, from: data)
        try data.write(to: fileURL, options: .atomic)
        state = restored
    }
}
