import SwiftUI

// 词汇 › 词群 (DATA-06, ACC-10). The chunk library holds expressions that can move to new sentences.
// Thought groups (意群) belong to one sentence's 跟读 annotations and never come here.

/// The chunk library: search, sort, open a chunk's detail, or add one by hand.
struct VocabChunkLibraryView: View {
    @Environment(VocabStore.self) private var vocab

    @State private var query = ""
    @State private var sort: ChunkLibrarySort = .recent
    @State private var showAdd = false

    var body: some View {
        let chunks = vocab.state.items.filter { $0.kind == .chunk }
        let needle = SentenceText.normalize(query)
        let shown = ordered(chunks.filter { matches($0, needle: needle) })
        let countText: String = needle.isEmpty ? "共 \(chunks.count) 个" : "找到 \(shown.count) 个（共 \(chunks.count) 个）"
        List {
            Section {
                Text("词群是可以搬到新句子里用的表达，比如 be responsible for。意群是一句话里的停顿分组，放在跟读标注里，不进词群库。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                searchField
                ChoicePicker("排序", selection: $sort) {
                    ForEach(ChunkLibrarySort.allCases) { s in
                        Text(s.title).tag(s)
                    }
                }
            }
            Section {
                if chunks.isEmpty {
                    emptyState
                } else if shown.isEmpty {
                    Text("没有找到。换个写法或中文义试试。")
                        .foregroundStyle(.secondary)
                }
                ForEach(shown) { item in
                    NavigationLink {
                        VocabItemDetailView(itemId: item.id)
                    } label: {
                        ChunkLibraryRow(item: item)
                    }
                }
            } header: {
                Text(countText)
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAdd = true
                } label: {
                    Label("添加词群", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            ChunkLibraryAddSheet()
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("搜索词群、中文义、备注", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("清空搜索")
            }
        }
        .frame(minHeight: 44)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("还没有词群", systemImage: "text.quote")
                .font(.headline)
            Text("在听读页选中几个连着的词，可以存成词群。也可以点“添加词群”，自己输入。")
                .foregroundStyle(.secondary)
            Button {
                showAdd = true
            } label: {
                Label("添加词群", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(.vertical, 8)
    }

    /// Case-, accent- and width-insensitive; curly quotes and dashes count as straight ones.
    private func matches(_ item: VocabItem, needle: String) -> Bool {
        guard !needle.isEmpty else { return true }
        var fields = [item.text, item.gloss]
        if let note = item.note { fields.append(note) }
        if let usage = item.function { fields.append(usage) }
        fields += item.variants ?? []
        let fold = needle.contains("'") || needle.contains("\"") || needle.contains("-")
        return fields.contains { field in
            let hay = fold ? SentenceText.normalize(field) : field
            return hay.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil
        }
    }

    private func ordered(_ items: [VocabItem]) -> [VocabItem] {
        switch sort {
        case .recent:
            return items.sorted { $0.created > $1.created }
        case .alpha:
            return items.sorted { a, b in
                let c = a.text.localizedStandardCompare(b.text)
                return c == .orderedSame ? a.created > b.created : c == .orderedAscending
            }
        }
    }
}

private enum ChunkLibrarySort: String, CaseIterable, Identifiable {
    case recent, alpha
    var id: String { rawValue }
    var title: String { self == .recent ? "最近添加" : "A–Z" }
}

private struct ChunkLibraryRow: View {
    let item: VocabItem

    /// Other forms and how many contexts, on one line.
    private var extra: String {
        var parts: [String] = []
        if let variants = item.variants, !variants.isEmpty {
            parts.append("其他形式：" + variants.joined(separator: "、"))
        }
        if !item.sources.isEmpty {
            parts.append("\(item.sources.count) 个语境")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.text)
                    .font(Font.system(.title3, design: .serif).weight(.semibold))
                if item.starred {
                    Image(systemName: "star.fill")
                        .foregroundStyle(Theme.warn)
                        .accessibilityLabel("已收藏")
                }
                if item.archived {
                    Badge(text: "已暂停", outlined: true)
                }
            }
            Text(item.gloss.isEmpty ? "还没有中文义" : item.gloss)
                .font(.callout)
                .foregroundStyle(.secondary)
            if !extra.isEmpty {
                Text(extra)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Adds a chunk by hand (origin: manual, no context). It starts with the 认义 task only.
private struct ChunkLibraryAddSheet: View {
    @Environment(VocabStore.self) private var vocab
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var gloss = ""
    @State private var note = ""
    @State private var variants = ""
    @State private var usage = ""

    var body: some View {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = clean.isEmpty ? nil : vocab.chunk(text: clean)
        NavigationStack {
            Form {
                Section {
                    TextField("比如 be responsible for", text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("词群")
                } footer: {
                    if let existing {
                        Text("词群库里已经有“\(existing.text)”。保存会让它回到复习里；它原来空着的释义、备注、其他形式和用法，会用这次填的补上。")
                    } else if !clean.isEmpty && !clean.contains(" ") {
                        Text("词群一般有两个词以上。单个词请在听读页点词，收藏它的义项。")
                    } else if clean.count > 60 {
                        Text("有点长。词群通常是 2 到 6 个词，整句话不适合当词群。")
                    }
                }
                Section("中文义") {
                    TextField("这个表达的中文意思", text: $gloss, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section("备注") {
                    TextField("可以不写", text: $note, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section {
                    TextField("用逗号分开，比如 take responsibility for", text: $variants, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(1...4)
                } header: {
                    Text("其他形式")
                }
                Section {
                    TextField("什么时候用、常跟什么搭配、不能怎么用", text: $usage, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("用法和限制")
                } footer: {
                    Text("保存后先开“认义”任务。其他题型在词条详情里按需打开。手动添加的词群没有原文语境。")
                }
            }
            .navigationTitle("添加词群")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                        dismiss()
                    }
                    .disabled(clean.isEmpty)
                }
            }
        }
    }

    private func save() {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let existed = vocab.chunk(text: clean) != nil
        let newGloss = gloss.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsage = usage.trimmingCharacters(in: .whitespacesAndNewlines)
        let newNote: String? = trimmedNote.isEmpty ? nil : trimmedNote
        let newUsage: String? = trimmedUsage.isEmpty ? nil : trimmedUsage
        let list = ChunkLibraryAddSheet.splitList(variants)
        let newVariants: [String]? = list.isEmpty ? nil : list
        let saved = vocab.saveChunk(text: clean, gloss: newGloss, note: newNote, variants: newVariants,
                                    function: newUsage, occurrence: nil, origin: .manual)
        // saveChunk keeps an existing chunk's note, forms and usage; fill only the empty ones.
        if existed {
            vocab.editItem(saved.id) { it in
                if (it.note ?? "").isEmpty, let newNote { it.note = newNote }
                if (it.variants ?? []).isEmpty, let newVariants { it.variants = newVariants }
                if (it.function ?? "").isEmpty, let newUsage { it.function = newUsage }
            }
        }
    }

    /// Other forms typed as one line: commas (either width), semicolons, 、 or new lines.
    private static func splitList(_ text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for part in text.split(whereSeparator: { ",，;；、\n".contains($0) }) {
            let t = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, seen.insert(t.lowercased()).inserted {
                out.append(t)
            }
        }
        return out
    }
}
