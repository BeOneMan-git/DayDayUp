import SwiftUI

/// 导入预览 (IMP-F04, IMP-P04, PKG-P05, ACC-04/05/06/08): one section per file with its state, sizes and
/// problems; per-file choices; one "导入所选" button. Nothing is written before that button.
struct PackImportSheet: View {
    @Environment(PackStore.self) private var packs
    @Environment(\.dismiss) private var dismiss
    @State private var model: PackImportModel
    private let onClose: (Bool) -> Void

    /// `onClose` gets true when something was written into the library.
    init(urls: [URL], onClose: @escaping (Bool) -> Void = { _ in }) {
        _model = State(initialValue: PackImportModel(urls: urls))
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            List {
                content
            }
            .navigationTitle("导入内容包")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .interactiveDismissDisabled(model.phase == .committing)
        .task { await model.start(packs: packs) }
        .onDisappear { onClose(model.installedAny) }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .checking:
            checkingSection
        case .review:
            reviewSections
        case .committing:
            committingSections
        case .finished:
            finishedSections
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if model.phase != .finished {
                Button("取消") { dismiss() }
                    .disabled(model.phase == .committing)
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            if model.phase == .finished {
                Button("完成") { dismiss() }
            }
        }
    }

    // MARK: Checking

    private var checkingSection: some View {
        Section {
            ProgressView(checkingTitle, value: Double(model.progressDone), total: Double(max(1, model.progressTotal)))
            Text("先把文件读一遍，逐个核对大小和 SHA-256 校验值，再和书架上的版本比较。这一步不写入书架。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var checkingTitle: String {
        let n = min(model.progressDone + 1, max(1, model.progressTotal))
        return "正在检查 \(n)/\(model.progressTotal)：\(model.progressName)"
    }

    // MARK: Review

    @ViewBuilder
    private var reviewSections: some View {
        spaceSection
        ForEach(model.candidates) { c in
            ImportCandidateSection(candidate: c, model: model)
        }
        commitSection
    }

    private var spaceSection: some View {
        Section {
            LabeledContent("可用空间", value: freeText)
            LabeledContent("所选文件需要", value: PackImporter.sizeText(Int64(model.neededBytes)))
            if model.spaceShort {
                Label("空间不够：请少选几个，或者先在 iPad 上腾出空间。原来的书架照常可用。",
                      systemImage: "externaldrive.badge.xmark")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("空间")
        } footer: {
            Text("需要的空间 = 解包后的大小 × 1.2（留一点余量）；App 不另建索引文件。单个文件 100 MB 以上会提醒，但不设上限。")
        }
    }

    private var freeText: String {
        guard let free = model.freeBytes else { return "查不到" }
        return PackImporter.sizeText(free)
    }

    private var commitSection: some View {
        Section {
            Button {
                Task { await model.commit(packs: packs) }
            } label: {
                Label(commitTitle, systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canCommit)
            .listRowBackground(Color.clear)
        } footer: {
            Text(commitFooter)
        }
    }

    private var commitTitle: String {
        if model.actionCount > 0 { return "导入所选（\(model.actionCount) 个）" }
        if model.tidyCount > 0 { return "把已导入过的文件移到“已导入”" }
        return "没有要导入的文件"
    }

    private var commitFooter: String {
        var text = "没选的文件留在原处，不会改动。每个文件先写进临时文件夹，全部写好才换掉旧的；中途失败，书架保持原样。"
        if model.tidyCount > 0 {
            text += "App 文件夹里已导入过的文件，会一起移到“已导入”文件夹。"
        }
        return text
    }

    // MARK: Committing and results

    @ViewBuilder
    private var committingSections: some View {
        Section {
            ProgressView(committingTitle, value: Double(model.progressDone), total: Double(max(1, model.progressTotal)))
            Text("请不要切走或关掉 App。万一中断，书架保持导入前的样子。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if !model.outcomes.isEmpty {
            outcomeSection
        }
    }

    private var committingTitle: String {
        let n = min(model.progressDone + 1, max(1, model.progressTotal))
        return "正在处理 \(n)/\(model.progressTotal)：\(model.progressName)"
    }

    @ViewBuilder
    private var finishedSections: some View {
        outcomeSection
        Section {
            Button {
                dismiss()
            } label: {
                Text("完成")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .listRowBackground(Color.clear)
        } footer: {
            Text(finishedFooter)
        }
    }

    private var finishedFooter: String {
        model.installedAny
            ? "新内容已经在书架上。句子有改动的文章，学习记录按“无法对应、旧记录保留”处理。"
            : "书架没有改动。"
    }

    private var outcomeSection: some View {
        Section("结果") {
            ForEach(model.outcomes) { outcome in
                ImportOutcomeRow(outcome: outcome)
            }
        }
    }
}

/// One file's result: symbol + words, never colour alone.
struct ImportOutcomeRow: View {
    let outcome: ImportOutcome

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(stateText)
                    .font(.headline)
            } icon: {
                Image(systemName: symbol)
            }
            .foregroundStyle(color)
            Text(outcome.fileName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(outcome.message)
                .font(.callout)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch outcome.state {
        case .installed: return "checkmark.circle.fill"
        case .kept: return "doc.on.doc"
        case .unchanged: return "equal.circle"
        case .skipped: return "minus.circle"
        case .failed: return "xmark.octagon.fill"
        }
    }

    private var stateText: String {
        switch outcome.state {
        case .installed: return "已写入书架"
        case .kept: return "已另存副本"
        case .unchanged: return "没有变化"
        case .skipped: return "没有导入"
        case .failed: return "没有导入"
        }
    }

    private var color: Color {
        switch outcome.state {
        case .installed: return Theme.accent
        case .failed: return Color.red
        case .kept, .unchanged, .skipped: return Color.secondary
        }
    }
}
