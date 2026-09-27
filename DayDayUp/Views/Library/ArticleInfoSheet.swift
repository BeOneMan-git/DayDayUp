import SwiftUI

/// 资源与版本 (PAGE-02, PKG-P04, IMP-F05): what this article has on the iPad, the exact file of anything that is
/// missing, and which content pack version it comes from.
struct ArticleInfoSheet: View {
    let item: LibraryItem

    @Environment(PackStore.self) private var packs
    @Environment(\.dismiss) private var dismiss

    private struct ResourceRow: Identifiable {
        var id: String { label }
        var label: String
        var state: ResourceState
        var file: String?
    }

    var body: some View {
        NavigationStack {
            Form {
                articleSection
                resourceSection
                versionSection
            }
            .navigationTitle("资源与版本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    // MARK: Sections

    private var articleSection: some View {
        let meta = item.meta
        return Section("文章") {
            LabeledContent("标题", value: meta.title)
            LabeledContent("期号", value: item.ref.issue)
            LabeledContent("栏目", value: meta.section)
            LabeledContent("时长", value: formatTime(meta.dur))
            if let nw = meta.nw {
                LabeledContent("词数", value: "\(nw)")
            }
        }
    }

    private var resourceSection: some View {
        Section {
            ForEach(resourceRows) { row in
                resourceLine(row)
            }
        } header: {
            Text("离线资源")
        } footer: {
            Text("缺的资源写出了具体文件。重新导入完整的内容包可以补上；理解题需要新版内容包（格式 2）。")
        }
    }

    private var versionSection: some View {
        Section {
            if let pack = packs.pack(for: item.ref) {
                versionLines(pack.manifest)
            } else {
                Text("找不到这篇文章的内容包。")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("内容版本")
        } footer: {
            Text("程序生成的内容没有经过人工核对。发现错误可以在听读页的句子面板点“报错”。")
        }
    }

    @ViewBuilder
    private func versionLines(_ m: PackManifest) -> some View {
        LabeledContent("内容包", value: m.packId)
        LabeledContent("版本", value: m.packageRevision.map { "第 \($0) 版" } ?? m.version)
        LabeledContent("格式", value: "\(m.format)")
        if let made = m.createdAt ?? m.created, !made.isEmpty {
            LabeledContent("生成日期", value: made)
        }
        if let rev = item.meta.contentRevision {
            LabeledContent("本文修订", value: "第 \(rev) 版")
        }
        let kinds = (m.provenance ?? [:]).keys.sorted()
        if kinds.isEmpty {
            LabeledContent("来源说明", value: ProvenanceNote.state(nil))
        } else {
            ForEach(kinds, id: \.self) { kind in
                LabeledContent(ProvenanceNote.title(kind), value: ProvenanceNote.state(m.provenance?[kind]))
            }
        }
    }

    // MARK: Resources

    private var resourceRows: [ResourceRow] {
        packs.resources(item.ref).list.map { pair in
            ResourceRow(label: pair.0, state: pair.1, file: pair.1 == .missing ? missingFile(pair.0) : nil)
        }
    }

    /// The file inside the pack that a resource comes from (nil when it has no file of its own).
    private func missingFile(_ label: String) -> String? {
        let id = item.ref.id
        switch label {
        case "正文": return "articles/\(id).json"
        case "原音": return item.meta.audio
        case "词义": return "lexicon.json"
        case "标注": return "annotations/\(id).json"
        case "题目": return "quiz/\(id).json"
        default: return nil
        }
    }

    private func resourceLine(_ row: ResourceRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol(row.state))
                .foregroundStyle(row.state == .missing ? Theme.warn : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                if let file = row.file {
                    Text("缺文件：\(file)")
                        .font(.caption)
                        .foregroundStyle(Theme.warn)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 8)
            Text(stateText(row.state))
                .foregroundStyle(row.state == .missing ? Theme.warn : Color.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func symbol(_ s: ResourceState) -> String {
        switch s {
        case .available: return "checkmark.circle.fill"
        case .missing: return "exclamationmark.triangle.fill"
        case .notRequired: return "minus.circle"
        }
    }

    private func stateText(_ s: ResourceState) -> String {
        switch s {
        case .available: return "有"
        case .missing: return "缺"
        case .notRequired: return "不需要"
        }
    }
}
