import SwiftUI
import UniformTypeIdentifiers

/// 从备份恢复 (DATA-RS, ACC-26, ACC-27), in its own NavigationStack with 关闭:
/// 选择备份文件 → 在临时库解开并检查 → 报告（记录数、缺的内容包和录音、迁移说明、损坏时拒绝）→ 恢复 / 取消
/// → 结果和“撤销这次恢复”.
struct RestoreFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PackStore.self) private var packs
    @Environment(UserStore.self) private var user
    @Environment(PracticeStore.self) private var practice
    @Environment(VocabStore.self) private var vocab
    @Environment(AnnotationStore.self) private var annotations
    @Environment(StudyStore.self) private var study
    @Environment(ReadingSession.self) private var session

    @State private var model = RestoreModel()
    @State private var showPicker = false
    @State private var confirmSwitch = false
    @State private var undoTarget: URL?

    init() {}

    var body: some View {
        NavigationStack {
            List {
                content
            }
            .navigationTitle("从备份恢复")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .disabled(model.isBusy)
                }
            }
            .fileImporter(isPresented: $showPicker, allowedContentTypes: [.ddubackup, .json],
                          allowsMultipleSelection: false) { result in
                picked(result)
            }
            .confirmationDialog(switchQuestion, isPresented: $confirmSwitch, titleVisibility: .visible) {
                Button(switchButtonTitle, role: .destructive) {
                    startSwitch()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("先把现在的数据整份存到 Backups/恢复前-时间，再替换。之后可以撤销。")
            }
            .confirmationDialog("撤销这次恢复？", isPresented: undoBinding, titleVisibility: .visible) {
                Button("撤销", role: .destructive) {
                    startUndo()
                }
                Button("取消", role: .cancel) { undoTarget = nil }
            } message: {
                Text("会换回恢复前的数据。换之前，现在的数据也先整份存一份。")
            }
        }
        .interactiveDismissDisabled(model.isBusy)
        .onAppear { model.refreshSnapshots() }
        .onDisappear { model.discardLibrary() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .start:
            startSections
        case .checking(let name):
            busySection(title: "正在临时库里解开并检查：\(name)",
                        detail: "逐个文件解码、数记录、找缺的内容包和录音。这一步不改动现在的记录。")
        case .report(let report):
            RestoreReportSections(report: report)
            reportActions(report)
        case .switching(let text):
            busySection(title: text, detail: "请不要切走或关掉 App。")
        case .done(let done):
            RestoreDoneSections(done: done,
                                undo: { snapshot in undoTarget = snapshot },
                                close: { dismiss() },
                                again: { model.backToStart() })
        }
    }

    private var targets: RestoreTargets {
        RestoreTargets(packs: packs, user: user, practice: practice, vocab: vocab,
                       annotations: annotations, study: study, session: session)
    }

    private var undoBinding: Binding<Bool> {
        Binding(
            get: { undoTarget != nil },
            set: { shown in if !shown { undoTarget = nil } }
        )
    }

    // MARK: Start

    @ViewBuilder
    private var startSections: some View {
        Section {
            Text("1. 选一个备份文件：.ddubackup 完整备份，或者 V0.1 的 user.json。")
            Text("2. App 先在临时库里解开，逐个文件检查，告诉你有多少条记录、缺哪些内容包和录音。")
            Text("3. 你确认后才替换现在的记录。替换前，现在的数据整份存到 Backups/恢复前-时间，可以撤销。")
            Button {
                showPicker = true
            } label: {
                Label("选择备份文件", systemImage: "folder")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        } header: {
            Text("怎么恢复")
        } footer: {
            Text("损坏的备份会被拒绝，不会替换一半。")
        }
        if !model.snapshots.isEmpty {
            snapshotSection
        }
    }

    private var snapshotSection: some View {
        Section {
            ForEach(model.snapshots) { snapshot in
                Button {
                    check(.snapshot(snapshot.url))
                } label: {
                    RestoreSnapshotRow(snapshot: snapshot)
                }
            }
        } header: {
            Text("恢复前留下的数据")
        } footer: {
            Text("每次恢复前自动留下的一份。选一份，先看检查结果，确认后回到那时的数据。这些数据存在 App 内部，不会自动删除。")
        }
    }

    // MARK: Report

    @ViewBuilder
    private func reportActions(_ report: RestoreReport) -> some View {
        if report.refusal == nil {
            Section {
                Button(role: .destructive) {
                    confirmSwitch = true
                } label: {
                    Label(replaceTitle(report), systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                Button {
                    model.backToStart()
                } label: {
                    Text("取消，不恢复")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            } footer: {
                Text("替换前，现在的数据会整份存到 Backups/恢复前-时间；恢复后可以撤销。")
            }
        } else {
            Section {
                Button {
                    showPicker = true
                } label: {
                    Label("换一个备份文件", systemImage: "folder")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                Button {
                    model.backToStart()
                } label: {
                    Text("回到开始")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
        }
    }

    private func replaceTitle(_ report: RestoreReport) -> String {
        report.isSnapshot ? "回到这份数据" : "用这个备份替换现在的记录"
    }

    private var switchQuestion: String {
        if case .report(let report) = model.phase, report.isSnapshot {
            return "回到这份恢复前的数据？"
        }
        return "用备份替换现在的学习记录？"
    }

    private var switchButtonTitle: String {
        if case .report(let report) = model.phase, report.isSnapshot {
            return "回到这份数据"
        }
        return "替换"
    }

    private func busySection(title: String, detail: String) -> some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                Text(title)
            }
            .frame(minHeight: 44)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Actions

    private func picked(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        check(.file(url))
    }

    private func check(_ source: RestoreSource) {
        let dir = practice.recordingsDir
        Task { await model.check(source, packs: packs, recordingsDir: dir) }
    }

    private func startSwitch() {
        let t = targets
        Task { await model.confirm(targets: t) }
    }

    private func startUndo() {
        guard let snapshot = undoTarget else { return }
        undoTarget = nil
        let t = targets
        Task { await model.undo(snapshot, targets: t) }
    }
}

/// One Backups/恢复前-… folder in the list.
struct RestoreSnapshotRow: View {
    let snapshot: RestoreSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: "clock.arrow.circlepath")
                .foregroundStyle(Color.primary)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        guard let info = snapshot.info else { return snapshot.name }
        return info.created.formatted(date: .abbreviated, time: .standard)
    }

    private var detail: String {
        guard let info = snapshot.info else { return "Backups/\(snapshot.name)" }
        return "\(info.note) · Backups/\(snapshot.name)"
    }
}

/// The result of a switch: what happened, where the earlier data is, and 撤销这次恢复.
struct RestoreDoneSections: View {
    let done: RestoreModel.Done
    let undo: (URL) -> Void
    let close: () -> Void
    let again: () -> Void

    var body: some View {
        switch done.outcome {
        case .restored(let snapshot, let warning):
            restoredSections(snapshot: snapshot, warning: warning)
        case .notStarted(let text):
            messageSection(title: "没有恢复", symbol: "xmark.octagon.fill", color: Color.red, text: text)
            buttons(undoFrom: nil, undoTitle: "")
        case .rolledBack(let reason, let snapshot):
            let text = "恢复没有完成：\(reason)。已经换回恢复前的数据（Backups/\(snapshot.lastPathComponent)）。"
            messageSection(title: "恢复没有完成，已退回", symbol: "arrow.uturn.backward.circle.fill",
                           color: Theme.warn, text: text)
            buttons(undoFrom: nil, undoTitle: "")
        case .partly(let reason, let snapshot):
            let text = "恢复只做了一部分：\(reason)。换回也没有成功。恢复前的数据完整地留在 Backups/\(snapshot.lastPathComponent)，可以点下面的按钮再试一次换回。"
            messageSection(title: "恢复只做了一部分", symbol: "exclamationmark.triangle.fill",
                           color: Color.red, text: text)
            buttons(undoFrom: snapshot, undoTitle: "再试一次换回恢复前的数据")
        }
    }

    @ViewBuilder
    private func restoredSections(snapshot: URL, warning: String?) -> some View {
        let text = done.wentBack
            ? "已换回。换之前的数据也留了一份在 Backups/\(snapshot.lastPathComponent)。"
            : "已恢复。恢复前的数据留在 Backups/\(snapshot.lastPathComponent)。"
        messageSection(title: done.wentBack ? "已换回" : "已恢复", symbol: "checkmark.circle.fill",
                       color: Theme.accent, text: text)
        if let warning {
            Section {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.warn)
            }
        }
        buttons(undoFrom: done.wentBack ? nil : snapshot, undoTitle: "撤销这次恢复")
    }

    private func messageSection(title: String, symbol: String, color: Color, text: String) -> some View {
        Section {
            Label {
                Text(title)
                    .font(.headline)
            } icon: {
                Image(systemName: symbol)
            }
            .foregroundStyle(color)
            Text(text)
        }
    }

    private func buttons(undoFrom snapshot: URL?, undoTitle: String) -> some View {
        Section {
            if let snapshot {
                Button {
                    undo(snapshot)
                } label: {
                    Label(undoTitle, systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
            Button {
                again()
            } label: {
                Text("回到开始")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            Button {
                close()
            } label: {
                Text("完成")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        } footer: {
            Text("撤销也走同样的步骤：先检查恢复前的数据，把现在的数据存一份，再换回去。")
        }
    }
}
