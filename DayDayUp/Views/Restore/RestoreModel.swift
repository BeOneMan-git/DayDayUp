import Foundation
import Observation

/// The restore flow: start → checking in a temporary library → report → switching → done (with 撤销).
@MainActor
@Observable
final class RestoreModel {
    struct Done {
        var outcome: RestoreOutcome
        /// The switch went back to a 恢复前 copy (撤销 or 回到这份数据).
        var wentBack: Bool
    }

    enum Phase {
        case start
        case checking(String)
        case report(RestoreReport)
        case switching(String)
        case done(Done)
    }

    private(set) var phase: Phase = .start
    private(set) var snapshots: [RestoreSnapshot] = []

    var isBusy: Bool {
        switch phase {
        case .checking, .switching: return true
        default: return false
        }
    }

    func refreshSnapshots() {
        snapshots = RestoreDrill.snapshots()
    }

    /// Unpacks and decodes the source in a temporary library, then shows the report. Nothing else changes.
    func check(_ source: RestoreSource, packs: PackStore, recordingsDir: URL) async {
        guard !isBusy else { return }
        discardLibrary()
        RestoreDrill.cleanLeftovers()
        phase = .checking(Self.name(of: source))
        let installed = RestoreDrill.installedArticles(packs.packs)
        let report = await Task.detached(priority: .userInitiated) {
            RestoreDrill.run(source, installed: installed, recordingsDir: recordingsDir)
        }.value
        phase = .report(report)
    }

    /// After the learner confirmed: keeps the current data in Backups/恢复前-…, then switches.
    func confirm(targets: RestoreTargets) async {
        guard case .report(let report) = phase, report.refusal == nil else { return }
        phase = .switching("正在恢复：先把现在的数据整份存一份，再换成备份里的记录。")
        let outcome = await RestoreDrill.switchTo(report, targets: targets)
        refreshSnapshots()
        phase = .done(Done(outcome: outcome, wentBack: report.isSnapshot))
    }

    /// 撤销这次恢复: the same path with the 恢复前 copy — check it, keep the current data, switch.
    func undo(_ snapshot: URL, targets: RestoreTargets) async {
        guard !isBusy else { return }
        discardLibrary()
        RestoreDrill.cleanLeftovers()
        phase = .checking(snapshot.lastPathComponent)
        let installed = RestoreDrill.installedArticles(targets.packs.packs)
        let recordingsDir = targets.practice.recordingsDir
        let report = await Task.detached(priority: .userInitiated) {
            RestoreDrill.run(.snapshot(snapshot), installed: installed, recordingsDir: recordingsDir)
        }.value
        guard report.refusal == nil else {
            phase = .report(report)
            return
        }
        phase = .switching("正在撤销：先把现在的数据整份存一份，再换回恢复前的数据。")
        let outcome = await RestoreDrill.switchTo(report, targets: targets)
        refreshSnapshots()
        phase = .done(Done(outcome: outcome, wentBack: true))
    }

    /// Back to the first page; the temporary library of a report is removed.
    func backToStart() {
        guard !isBusy else { return }
        discardLibrary()
        phase = .start
        refreshSnapshots()
    }

    /// Removes the temporary library of a report the learner did not use.
    func discardLibrary() {
        guard case .report(let report) = phase else { return }
        RestoreDrill.removeLibrary(report.library)
        phase = .start
    }

    private static func name(of source: RestoreSource) -> String {
        switch source {
        case .file(let url): return url.lastPathComponent
        case .snapshot(let url): return url.lastPathComponent
        }
    }
}
