import SwiftUI

/// 词汇 (V0.1): the 生词本 and the words marked 认识. FSRS review arrives in V0.2.
struct VocabView: View {
    @Environment(PackStore.self) private var packs
    @Environment(UserStore.self) private var user
    @State private var list: WordList = .starred
    @State private var openWord: WordKey?

    enum WordList: String, CaseIterable, Identifiable {
        case starred, known
        var id: String { rawValue }
        var title: String { self == .starred ? "生词本" : "认识的词" }
    }

    struct WordKey: Identifiable {
        let id: String
    }

    var body: some View {
        let dates = list == .starred ? user.state.star : user.state.known
        let keys = dates.keys.sorted { (dates[$0] ?? .distantPast) > (dates[$1] ?? .distantPast) }
        List {
            Section {
                Picker("列表", selection: $list) {
                    ForEach(WordList.allCases) { l in
                        Text("\(l.title) \(l == .starred ? user.state.star.count : user.state.known.count)").tag(l)
                    }
                }
                .pickerStyle(.segmented)
                Label("间隔重复复习（FSRS）V0.2 上线：生词本里的词会自动排进复习队列。", systemImage: "calendar.badge.clock")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if !packs.lexiconReady {
                ProgressView("正在载入词库…")
            } else if keys.isEmpty {
                Text(list == .starred ? "生词本是空的。在听读页点单词，再点“生词”。" : "还没有标成“认识”的词。")
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    ForEach(keys, id: \.self) { key in
                        Button {
                            openWord = WordKey(id: key)
                        } label: {
                            row(key, date: dates[key])
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("词汇")
        .sheet(item: $openWord) { w in
            NavigationStack {
                WordSheet(key: w.id)
            }
        }
    }

    private func row(_ key: String, date: Date?) -> some View {
        let entry = packs.entry(key)
        let band = entry?.b ?? 0
        let meaning = entry?.card?.senses?.first?.zh ?? entry?.zh?.components(separatedBy: "\n").first ?? ""
        return HStack(spacing: 12) {
            Circle().fill(band >= 5 ? Theme.level(band) : Color.secondary.opacity(0.4)).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(key).font(.body.weight(.semibold))
                Text(meaning).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let date {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

/// A word card outside the reader: card sections plus the sentences where the word appeared.
struct WordSheet: View {
    @Environment(PackStore.self) private var packs
    @Environment(UserStore.self) private var user
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    let key: String

    var body: some View {
        let entry = packs.entry(key)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(key)
                        .font(Font.system(.largeTitle, design: .serif).weight(.semibold))
                    Spacer()
                    Button {
                        user.toggleStar(key)
                    } label: {
                        Label("生词", systemImage: user.isStarred(key) ? "star.fill" : "star")
                    }
                    .buttonStyle(.bordered)
                    Button {
                        user.toggleKnown(key)
                    } label: {
                        Label("认识", systemImage: user.isKnown(key) ? "checkmark.circle.fill" : "checkmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
                HStack(spacing: 8) {
                    if let b = entry?.b, b >= 5 { Badge(text: "\(b) 级", color: Theme.level(b)) }
                    if let cefr = entry?.cefr { Badge(text: "CEFR \(cefr)") }
                    if let pos = entry?.card?.pos { Badge(text: pos) }
                    if let ipa = entry?.card?.ipa {
                        if let br = ipa.br {
                            Button("英 \(br)") { Speaker.shared.speak(key, language: "en-GB") }
                                .buttonStyle(.bordered)
                        }
                        if let am = ipa.am {
                            Button("美 \(am)") { Speaker.shared.speak(key, language: "en-US") }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                if let card = entry?.card {
                    LexCardSections(card: card, accent: user.settings.accent)
                    contexts(card)
                } else if let zh = entry?.zh {
                    CardSection(title: "词典释义") { Text(zh) }
                } else {
                    Text("词库里没有这个词。可能它所在的内容包被删除了。")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private func contexts(_ card: Card) -> some View {
        let items = card.ctx ?? []
        if !items.isEmpty {
            CardSection(title: "在文章里的意思") {
                ForEach(items, id: \.sid) { c in
                    let articleID = String(c.sid.split(separator: ":").first ?? "")
                    let item = packs.allItems.first { $0.ref.id == articleID }
                    Button {
                        if let item {
                            dismiss()
                            router.openArticle(item.ref)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.m ?? "").font(.body.weight(.medium))
                            if let item {
                                Text("\(item.ref.issue) · \(item.meta.title)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
