import SwiftUI

/// One file in the preview: state (symbol + words), what the pack is, sizes, every problem one by one,
/// what differs from the installed version, and the choice for this file.
struct ImportCandidateSection: View {
    let candidate: ImportCandidate
    let model: PackImportModel

    private var blocked: Bool { model.isBlocked(candidate) }

    var body: some View {
        Section {
            statusRow
            ImportFactsView(candidate: candidate)
            messages
            changesRow
            choiceRows
        } header: {
            Text(candidate.fileName)
                .textCase(nil)
        }
    }

    // MARK: State

    private var statusRow: some View {
        let style = ImportStatusStyle(candidate: candidate, blocked: blocked)
        return Label {
            Text(style.text)
                .font(.headline)
        } icon: {
            Image(systemName: style.symbol)
        }
        .foregroundStyle(style.color)
        .accessibilityElement(children: .combine)
    }

    // MARK: Problems and notices

    @ViewBuilder
    private var messages: some View {
        if candidate.kind == .invalid {
            problemList
        }
        if candidate.kind == .identical {
            Text(identicalText)
                .font(.callout)
        }
        if blocked && candidate.kind != .invalid && candidate.kind != .identical {
            Label(blockedText, systemImage: "externaldrive.badge.xmark")
                .font(.callout)
                .foregroundStyle(.red)
        }
        if let packId = candidate.manifest?.packId, model.repeatedPackIds.contains(packId) {
            Label("这批文件里还有同一个内容包（\(packId)）的另一个文件，一次只能导入其中一个。",
                  systemImage: "square.on.square")
                .font(.callout)
                .foregroundStyle(Theme.warn)
        }
        ForEach(Array(candidate.notices.enumerated()), id: \.offset) { item in
            Label(item.element, systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var problemList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(candidate.problems.enumerated()), id: \.offset) { item in
                Label(item.element, systemImage: "xmark.circle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            Text("这个文件不会导入；原来的书架不受影响。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var identicalText: String {
        var text = "已经导入过，不会重复导入。"
        if candidate.fromInbox {
            text += "确认后，这个文件会移到“已导入”文件夹。"
        }
        return text
    }

    private var blockedText: String {
        let need = PackImporter.sizeText(Int64(candidate.neededBytes))
        let free = model.freeBytes.map { PackImporter.sizeText($0) } ?? "?"
        return "空间不够：需要约 \(need)，现在可用 \(free)。这个文件不能导入；原来的书架照常可用。"
    }

    // MARK: Changes

    @ViewBuilder
    private var changesRow: some View {
        if let changes = candidate.changes {
            DisclosureGroup(changesTitle(changes)) {
                PackChangesView(changes: changes)
            }
        }
    }

    private func changesTitle(_ changes: PackChanges) -> String {
        var title = "变化明细：" + changes.shortSummary
        let unmapped = changes.unmappedSentences
        if unmapped > 0 { title += "；\(unmapped) 句无法对应" }
        return title
    }

    // MARK: Choice

    @ViewBuilder
    private var choiceRows: some View {
        switch candidate.kind {
        case .new:
            Toggle("导入这个内容包", isOn: installBinding)
                .disabled(blocked)
        case .update(_, let older):
            Toggle(updateToggleTitle(older: older), isOn: installBinding)
                .disabled(blocked)
        case .conflict:
            conflictChoices
        case .identical, .invalid:
            EmptyView()
        }
    }

    private func updateToggleTitle(older: Bool) -> String {
        older ? "改用这个旧版本" : "更新到这个版本"
    }

    private var installBinding: Binding<Bool> {
        let c = candidate
        let m = model
        return Binding(
            get: { m.choice(for: c) == .install },
            set: { on in m.setChoice(on ? .install : .skip, for: c) }
        )
    }

    @ViewBuilder
    private var conflictChoices: some View {
        let current = model.choice(for: candidate)
        ImportChoiceRow(title: "保留当前（不导入）",
                        detail: "书架上的版本不变。默认选这个。",
                        selected: current == .skip,
                        enabled: true) {
            model.setChoice(.skip, for: candidate)
        }
        ImportChoiceRow(title: "替换为这个文件",
                        detail: "用这个文件换掉书架上的同版本内容。句子改了的学习记录标为“无法对应”，旧记录保留。",
                        selected: current == .replace,
                        enabled: !blocked) {
            model.setChoice(.replace, for: candidate)
        }
        ImportChoiceRow(title: "另存副本（不导入）",
                        detail: "把这个文件原样放进“文件 › 我的 iPad › DayDayUp › 冲突副本”，书架不变。",
                        selected: current == .keepCopy,
                        enabled: true) {
            model.setChoice(.keepCopy, for: candidate)
        }
    }
}

/// Status symbol, words and colour of one file in the preview.
struct ImportStatusStyle {
    let symbol: String
    let text: String
    let color: Color

    init(candidate c: ImportCandidate, blocked: Bool) {
        switch c.kind {
        case .invalid:
            symbol = "xmark.octagon.fill"
            text = "不能导入：发现 \(c.problems.count) 个问题"
            color = Color.red
        case .identical:
            symbol = "checkmark.circle"
            text = "已导入：和书架上的完全一样"
            color = Color.secondary
        case .conflict:
            symbol = "exclamationmark.triangle.fill"
            text = "冲突：版本号相同，内容不同"
            color = Theme.warn
        case .new:
            symbol = blocked ? "externaldrive.badge.xmark" : "plus.circle.fill"
            text = blocked ? "新增，但空间不够" : "新增"
            color = blocked ? Color.red : Theme.accent
        case .update(_, let older):
            if blocked {
                symbol = "externaldrive.badge.xmark"
                text = older ? "旧版本，但空间不够" : "新版本，但空间不够"
                color = Color.red
            } else if older {
                symbol = "arrow.uturn.backward.circle"
                text = "旧版本：比书架上的早"
                color = Theme.warn
            } else {
                symbol = "arrow.triangle.2.circlepath"
                text = "新版本"
                color = Theme.accent
            }
        }
    }
}

/// What the pack is and how much space it takes (PKG-P05: 原文件、解包后、需要的空间).
struct ImportFactsView: View {
    let candidate: ImportCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let m = candidate.manifest {
                Text(PackImporter.packLine(m))
            }
            if let installed = candidate.installedVersion, candidate.kind != .identical {
                Text("书架上现在是：\(installed)")
            }
            if candidate.archiveBytes > 0 {
                Text(sizeLine)
            }
            if !candidate.contents.isEmpty {
                Text("包含：" + candidate.contents.joined(separator: " · "))
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private var sizeLine: String {
        let archive = PackImporter.sizeText(Int64(candidate.archiveBytes))
        let unpacked = PackImporter.sizeText(Int64(candidate.unpackedBytes))
        let needed = PackImporter.sizeText(Int64(candidate.neededBytes))
        return "原文件 \(archive) · 解包后约 \(unpacked) · 导入需要约 \(needed)"
    }
}

/// 新版本 / 冲突: articles added, removed and changed (sentence counts from PackDiffer), and resources.
struct PackChangesView: View {
    let changes: PackChanges

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if changes.articlesSame {
                Text("文章的正文和原音都没有变化。")
            }
            if !changes.added.isEmpty {
                titledList("新增文章 \(changes.added.count) 篇", changes.added)
            }
            if !changes.removed.isEmpty {
                titledList("去掉的文章 \(changes.removed.count) 篇（学习记录保留，书架上不再显示）", changes.removed)
            }
            ForEach(changes.changed) { change in
                ArticleChangeView(change: change)
            }
            resourceLines
            if !changes.otherFiles.isEmpty {
                Text("其他不同的文件：" + changes.otherFiles.joined(separator: "、"))
            }
            if changes.manifestChanged && changes.articlesSame && changes.otherFiles.isEmpty {
                Text("内容包说明（manifest.json）不同。")
            }
        }
        .font(.callout)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var resourceLines: some View {
        if !changes.newResources.isEmpty {
            Text("新增资源：" + changes.newResources.joined(separator: "、"))
        }
        if !changes.updatedResources.isEmpty {
            Text("更新的资源：" + changes.updatedResources.joined(separator: "、"))
        }
        if !changes.droppedResources.isEmpty {
            Text("这个文件里没有的资源：" + changes.droppedResources.joined(separator: "、"))
                .foregroundStyle(Theme.warn)
        }
    }

    private func titledList(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.callout.weight(.semibold))
            ForEach(Array(items.enumerated()), id: \.offset) { item in
                Text("· " + item.element)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// One changed article: sentence counts, and what happens to the learner's records.
struct ArticleChangeView: View {
    let change: ArticleChange

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(change.title)
                .font(.callout.weight(.semibold))
            Text(detail)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts: [String] = []
        if change.sentencesSame {
            if change.textFileChanged {
                parts.append("句子文字没变（时间轴、翻译或注释有更新）")
            }
        } else {
            parts.append("改 \(change.changed) 句")
            parts.append("增 \(change.added) 句")
            parts.append("删 \(change.removed) 句")
            parts.append("无法对应、旧记录保留 \(change.unmapped) 句")
            if change.mapped > 0 {
                parts.append("按包里的对应表转到新句 \(change.mapped) 句")
            }
        }
        if change.audioChanged {
            parts.append("原音换了新文件")
        }
        return parts.joined(separator: " · ")
    }
}

/// A radio-style row: filled circle = chosen (shape, not only colour), at least 44 pt high.
struct ImportChoiceRow: View {
    let title: String
    let detail: String
    let selected: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Theme.accent : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(selected ? Font.body.weight(.semibold) : Font.body)
                        .foregroundStyle(enabled ? Color.primary : Color.secondary)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }
}
