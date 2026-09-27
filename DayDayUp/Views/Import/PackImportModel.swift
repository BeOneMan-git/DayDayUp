import Foundation
import Observation

/// One preview sheet: checking → review (per-file choices) → committing → finished.
@MainActor
@Observable
final class PackImportModel {
    enum Phase {
        case checking, review, committing, finished
    }

    let urls: [URL]
    private(set) var phase: Phase = .checking
    private(set) var progressDone = 0
    private(set) var progressTotal = 0
    private(set) var progressName = ""
    private(set) var candidates: [ImportCandidate] = []
    private(set) var choices: [UUID: ImportChoice] = [:]
    private(set) var outcomes: [ImportOutcome] = []
    private(set) var freeBytes: Int64?
    @ObservationIgnored private var started = false

    init(urls: [URL]) {
        self.urls = urls
        progressTotal = urls.count
    }

    /// Something was written into the library.
    var installedAny: Bool {
        outcomes.contains { $0.state == .installed }
    }

    // MARK: Checking

    func start(packs: PackStore) async {
        guard !started else { return }
        started = true
        let staged = await packs.stageImport(urls) { done, total, name in
            self.progressDone = done
            self.progressTotal = total
            self.progressName = name
        }
        freeBytes = packs.freeSpace()
        candidates = staged
        choices = defaultChoices(staged)
        phase = .review
    }

    /// New packs and newer versions are selected; conflicts keep the installed version (ACC-06);
    /// older versions, identical and damaged files are not selected. One file per packId.
    private func defaultChoices(_ list: [ImportCandidate]) -> [UUID: ImportChoice] {
        var out: [UUID: ImportChoice] = [:]
        var taken = Set<String>()
        for c in list {
            var choice = ImportChoice.skip
            if !isBlocked(c) {
                switch c.kind {
                case .new:
                    choice = .install
                case .update(_, let older):
                    choice = older ? .skip : .install
                default:
                    choice = .skip
                }
            }
            if choice == .install, let packId = c.manifest?.packId {
                if taken.contains(packId) {
                    choice = .skip
                } else {
                    taken.insert(packId)
                }
            }
            out[c.id] = choice
        }
        return out
    }

    // MARK: Choices

    func choice(for c: ImportCandidate) -> ImportChoice {
        choices[c.id] ?? .skip
    }

    /// Only one file per packId can be written in one go: choosing one clears the others.
    func setChoice(_ choice: ImportChoice, for c: ImportCandidate) {
        guard phase == .review else { return }
        choices[c.id] = choice
        guard choice == .install || choice == .replace, let packId = c.manifest?.packId else { return }
        for other in candidates where other.id != c.id && other.manifest?.packId == packId {
            let current = choices[other.id] ?? .skip
            if current == .install || current == .replace {
                choices[other.id] = .skip
            }
        }
    }

    /// packIds that appear in more than one readable file of this batch.
    var repeatedPackIds: Set<String> {
        var seen = Set<String>()
        var repeated = Set<String>()
        for c in candidates where c.kind != .invalid {
            guard let packId = c.manifest?.packId else { continue }
            if !seen.insert(packId).inserted { repeated.insert(packId) }
        }
        return repeated
    }

    // MARK: Space (PKG-P05)

    /// Unpacked size × 1.2 is more than the free space: this file cannot be installed.
    func isBlocked(_ c: ImportCandidate) -> Bool {
        guard let free = freeBytes else { return false }
        return Int64(c.neededBytes) > free
    }

    /// Space the chosen files need: unpacked × 1.2 for installs, the file size for copies made from elsewhere.
    var neededBytes: Int {
        var total = 0
        for c in candidates {
            switch choice(for: c) {
            case .install, .replace:
                total += c.neededBytes
            case .keepCopy:
                total += c.fromInbox ? 0 : c.archiveBytes
            case .skip:
                break
            }
        }
        return total
    }

    var spaceShort: Bool {
        guard let free = freeBytes else { return false }
        return Int64(neededBytes) > free
    }

    // MARK: Commit

    /// Files that will be written, copied or moved.
    var actionCount: Int {
        candidates.filter { choice(for: $0) != .skip }.count
    }

    /// Already-imported files in the app's folder: they move to 已导入 when the learner confirms.
    var tidyCount: Int {
        candidates.filter { $0.kind == .identical && $0.fromInbox }.count
    }

    var canCommit: Bool {
        phase == .review && !spaceShort && (actionCount > 0 || tidyCount > 0)
    }

    private func isUpdate(_ kind: ImportKind) -> Bool {
        if case .update = kind { return true }
        return false
    }

    func commit(packs: PackStore) async {
        guard canCommit else { return }
        phase = .committing
        let jobs = candidates
        progressTotal = jobs.count
        var results: [ImportOutcome] = []
        for (i, c) in jobs.enumerated() {
            progressDone = i
            progressName = c.fileName
            let chosen = choice(for: c)
            let outcome: ImportOutcome
            if chosen == .skip && isBlocked(c) && (c.kind == .new || isUpdate(c.kind)) {
                outcome = ImportOutcome(id: c.id, fileName: c.fileName, state: .failed,
                                        message: "空间不够，没有导入；原来的书架照常可用。")
            } else {
                outcome = await packs.commitImport(c, choice: chosen)
            }
            results.append(outcome)
            outcomes = results
        }
        progressDone = jobs.count
        packs.finishImport(results)
        phase = .finished
    }
}
