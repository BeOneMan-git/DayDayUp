import SwiftUI

/// A word in the open article that the learner wants to keep (one sense of it).
struct SenseTarget: Identifiable {
    let id = UUID()
    let ref: ArticleRef
    let sid: Int
    let tokIndex: Int
    let key: String
    let word: String
}

/// A range of words in one sentence, to keep as a lexical chunk (词群).
struct ChunkTarget: Identifiable {
    let id = UUID()
    let ref: ArticleRef
    let sid: Int
    let first: Int
    let last: Int
    let gloss: String?
    let note: String?
    let origin: VocabItem.Origin
}

/// 收藏这个义项 (READ-F04, VOC-F02): pick the sense that fits this sentence, edit the meaning, save.
/// Different senses of one word become different items and are reviewed separately.
struct SaveSenseSheet: View {
    let target: SenseTarget

    @Environment(VocabStore.self) private var vocab
    @Environment(PackStore.self) private var packs
    @Environment(ReadingSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var choice: Int?
    @State private var gloss = ""
    @State private var didSetup = false

    private var entry: LexEntry? { packs.entry(target.key) }
    private var senses: [Sense] { entry?.card?.senses ?? [] }
    private var contextMeaning: String? { session.context(entry?.card, sid: target.sid)?.m }
    private var headword: String {
        var k = target.key
        if k.hasPrefix("#") { k.removeFirst() }
        return entry?.card != nil ? k : target.word
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(headword)
                            .font(Font.system(.title, design: .serif).weight(.semibold))
                        if let pos = entry?.card?.pos { Badge(text: pos) }
                    }
                    if let s = sentenceText {
                        Text(s)
                            .font(Font.system(.body, design: .serif))
                            .foregroundStyle(.secondary)
                    }
                    if let m = contextMeaning, !m.isEmpty {
                        Text("本文语境义：\(m)").font(.callout)
                    }
                }
                .padding(.vertical, 4)
            }

            if senses.isEmpty {
                Section {
                    Text("词库里没有分好的义项。你可以直接写下这一句里的意思。")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("选一个义项") {
                    ForEach(Array(senses.enumerated()), id: \.offset) { i, sense in
                        Button {
                            choice = i
                            gloss = sense.zh ?? gloss
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: choice == i ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(choice == i ? Theme.accent : Color.secondary)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text([sense.pos, sense.zh].compactMap { $0 }.joined(separator: " "))
                                        .font(.body.weight(.medium))
                                    if let en = sense.en {
                                        Text(en).font(.callout).foregroundStyle(.secondary)
                                    }
                                    if savedIndexes.contains(i) {
                                        Text("这个义项已经收藏").font(.caption).foregroundStyle(Theme.level5)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(choice == i ? .isSelected : [])
                    }
                }
            }

            Section("中文释义（可以改）") {
                TextField("这个义项的中文意思", text: $gloss, axis: .vertical)
                    .autocorrectionDisabled()
            }

            let existing = vocab.items(forKey: target.key)
            if !existing.isEmpty {
                Section("已经收藏的义项") {
                    ForEach(existing) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.gloss.isEmpty ? "（没有写释义）" : item.gloss)
                            Text("语境 \(item.sources.count) 句").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let choice, savedIndexes.contains(choice) {
                        Text("选的是已收藏的义项：保存只会加上这一句语境，不会多出一张卡。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Text("同一个词的不同义项分开学。新收藏默认只开“认义”，听辨、拼写等题型在词汇页里再打开。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("收藏这个义项")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(gloss.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear(perform: setup)
    }

    private var savedIndexes: Set<Int> {
        Set(vocab.items(forKey: target.key).compactMap { $0.senseIndex })
    }

    private var sentenceText: String? {
        session.sentence(target.sid).map { SentenceText.plain($0) }
    }

    private func setup() {
        guard !didSetup else { return }
        didSetup = true
        choice = OccurrenceBuilder.bestSense(senses, contextMeaning: contextMeaning)
        if let c = choice, c < senses.count {
            gloss = senses[c].zh ?? ""
        } else {
            gloss = contextMeaning ?? entry?.zh?.components(separatedBy: "\n").first ?? ""
        }
    }

    private func save() {
        let clean = gloss.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var occurrence: Occurrence?
        if let s = session.sentence(target.sid) ?? packs.sentence(target.ref, sid: target.sid) {
            occurrence = OccurrenceBuilder.make(ref: target.ref, sentence: s, first: target.tokIndex,
                                                last: target.tokIndex, audioSha: packs.audioSha(target.ref))
        }
        let pos = choice.flatMap { $0 < senses.count ? senses[$0].pos : nil } ?? entry?.card?.pos
        vocab.saveSense(key: target.key, text: headword, pos: pos, gloss: clean, senseIndex: choice,
                        occurrence: occurrence, origin: .reader)
        session.refreshUserMarks()
        session.showToast("已收藏：\(headword)（\(clean)）")
        dismiss()
    }
}

/// 收藏词群 (READ-F04, DATA-06). Only expressions that can move to new sentences belong here;
/// thought groups (意群) are pauses of one sentence and stay in 跟读 annotations.
struct SaveChunkSheet: View {
    let target: ChunkTarget

    @Environment(VocabStore.self) private var vocab
    @Environment(PackStore.self) private var packs
    @Environment(ReadingSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var gloss = ""
    @State private var note = ""
    @State private var variants = ""
    @State private var function = ""
    @State private var didSetup = false

    private var sentence: Sent? {
        session.sentence(target.sid) ?? packs.sentence(target.ref, sid: target.sid)
    }

    private var span: String {
        guard let s = sentence else { return "" }
        return SentenceText.span(s.toks, first: target.first, last: target.last)
    }

    var body: some View {
        Form {
            Section("原句里的样子") {
                Text(span.isEmpty ? "（没找到这几个词）" : span)
                    .font(Font.system(.title3, design: .serif).weight(.semibold))
                if let s = sentence {
                    Text(SentenceText.plain(s))
                        .font(Font.system(.callout, design: .serif))
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                TextField("词群", text: $text)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Text("可以改成原形，比如 called for 改成 call for。复习时的填空仍用原句里的样子。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("收进词群库的写法")
            }
            Section("中文意思") {
                TextField("这个表达的意思", text: $gloss, axis: .vertical)
            }
            Section("可选") {
                TextField("备注", text: $note, axis: .vertical)
                TextField("其他形式（用逗号分开）", text: $variants)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("用法和限制（比如：多用于正式书面语）", text: $function, axis: .vertical)
            }
            if let existing = vocab.chunk(text: text) {
                Section {
                    Text("词群库里已经有“\(existing.text)”。保存只会加上这一句语境。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Label("意群不是词群：意群是一句话里的停顿分组，在跟读标注里；这里只收能搬到新句子里用的表达。",
                      systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("收藏词群")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear(perform: setup)
    }

    private func setup() {
        guard !didSetup else { return }
        didSetup = true
        text = span
        gloss = target.gloss ?? phraseGloss() ?? ""
        note = target.note ?? ""
    }

    /// The pack's own phrase note when it covers exactly this range.
    private func phraseGloss() -> String? {
        sentence?.ann?.first { $0.t == "p" && $0.r == [target.first, target.last] }?.zh
    }

    private func save() {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var occurrence: Occurrence?
        if let s = sentence {
            occurrence = OccurrenceBuilder.make(ref: target.ref, sentence: s, first: target.first, last: target.last,
                                                audioSha: packs.audioSha(target.ref))
        }
        let list = variants.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFunction = function.trimmingCharacters(in: .whitespacesAndNewlines)
        vocab.saveChunk(text: clean, gloss: gloss.trimmingCharacters(in: .whitespacesAndNewlines),
                        note: trimmedNote.isEmpty ? nil : trimmedNote,
                        variants: list.isEmpty ? nil : list,
                        function: trimmedFunction.isEmpty ? nil : trimmedFunction,
                        occurrence: occurrence, origin: target.origin)
        session.showToast("已收进词群库：\(clean)")
        dismiss()
    }
}

/// Shown above the player while the learner picks the first and last word of a chunk.
struct ChunkSelectionBar: View {
    @Environment(ReadingSession.self) private var session

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.badge.plus")
                .foregroundStyle(Theme.level5)
                .accessibilityHidden(true)
            Text(session.chunkAnchor == nil ? "自选词群：点第一个词" : "再点最后一个词（同一句里）")
                .font(.callout.weight(.medium))
            Spacer()
            Button("取消") { session.cancelChunkSelection() }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Theme.chunkSelection)
    }
}
