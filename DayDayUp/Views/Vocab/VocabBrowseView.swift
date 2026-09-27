import SwiftUI

// 词汇 › 浏览 (VOC-F01, VOC-F02, VOC-F06) and the item detail page.
// Looking at an item never counts as a review: nothing here writes an answer event or moves a
// schedule. Only the explicit controls change data (star, edit, pause, task switches, new senses).

// MARK: - Browse

/// Every saved sense and chunk, with search, filters and sorting. Tap a row for its detail.
struct VocabBrowseView: View {
    @Environment(VocabStore.self) private var vocab
    @Environment(PackStore.self) private var packs
    @Environment(UserStore.self) private var user

    @State private var query = ""
    @State private var kind: VocabBrowseKind = .all
    @State private var status: VocabBrowseStatus = .all
    @State private var ability: VocabAbility? = nil
    @State private var origin: VocabItem.Origin? = nil
    @State private var topic: String? = nil
    @State private var starredOnly = false
    @State private var sort: VocabBrowseSort = .recent

    var body: some View {
        let rows = buildRows()
        let needle = SentenceText.normalize(query)
        let shown = ordered(rows.filter { matches($0, needle: needle) })
        let countText: String = filtersActive ? "找到 \(shown.count) 条（共 \(rows.count) 条）" : "共 \(rows.count) 条"
        VStack(spacing: 0) {
            filterBar(topics: topicList(rows))
            Divider()
            List {
                Section {
                    if rows.isEmpty {
                        emptyState
                    } else if shown.isEmpty {
                        Text("这个筛选下没有词条。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(shown) { row in
                        NavigationLink {
                            VocabItemDetailView(itemId: row.item.id)
                        } label: {
                            VocabBrowseRow(row: row) {
                                vocab.toggleStar(row.item.id)
                            }
                        }
                    }
                } header: {
                    Text(countText)
                } footer: {
                    if status != .all || ability != nil {
                        Text("一个词条的几种题型分开排期。状态和能力按“有一种题型符合”来筛。")
                    }
                }
                knownSection
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    // MARK: Filter bar

    private func filterBar(topics: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            searchField
            FlowLayout(spacing: 8, lineSpacing: 8) {
                Menu {
                    Picker("类型", selection: $kind) {
                        ForEach(VocabBrowseKind.allCases) { k in
                            Text(k.title).tag(k)
                        }
                    }
                } label: {
                    VocabFilterChip(text: "类型：" + kind.title, active: kind != .all)
                }
                Menu {
                    Picker("状态", selection: $status) {
                        ForEach(VocabBrowseStatus.allCases) { s in
                            Text(s.title).tag(s)
                        }
                    }
                } label: {
                    VocabFilterChip(text: "状态：" + status.title, active: status != .all)
                }
                Menu {
                    Picker("能力", selection: $ability) {
                        Text("全部").tag(VocabAbility?.none)
                        ForEach(VocabAbility.allCases) { a in
                            Text(a.title).tag(Optional(a))
                        }
                    }
                } label: {
                    VocabFilterChip(text: "能力：" + (ability?.title ?? "全部"), active: ability != nil)
                }
                Menu {
                    Picker("来源", selection: $origin) {
                        Text("全部").tag(VocabItem.Origin?.none)
                        ForEach(VocabBrowseText.origins, id: \.self) { o in
                            Text(VocabBrowseText.origin(o)).tag(Optional(o))
                        }
                    }
                } label: {
                    VocabFilterChip(text: "来源：" + (origin.map { VocabBrowseText.origin($0) } ?? "全部"),
                                    active: origin != nil)
                }
                if !topics.isEmpty || topic != nil {
                    Menu {
                        Picker("主题", selection: $topic) {
                            Text("全部").tag(String?.none)
                            ForEach(topics, id: \.self) { t in
                                Text(t).tag(Optional(t))
                            }
                        }
                    } label: {
                        VocabFilterChip(text: "主题：" + (topic ?? "全部"), active: topic != nil)
                    }
                }
                Button {
                    starredOnly.toggle()
                } label: {
                    VocabFilterChip(text: "只看收藏", systemImage: starredOnly ? "star.fill" : "star", active: starredOnly)
                }
                .buttonStyle(.plain)
                .accessibilityValue(starredOnly ? "开" : "关")
                Menu {
                    Picker("排序", selection: $sort) {
                        ForEach(VocabBrowseSort.allCases) { s in
                            Text(s.title).tag(s)
                        }
                    }
                } label: {
                    VocabFilterChip(text: "排序：" + sort.title, systemImage: "arrow.up.arrow.down")
                }
                if filtersActive {
                    Button {
                        resetFilters()
                    } label: {
                        VocabFilterChip(text: "清除筛选", systemImage: "xmark")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("搜索词、中文义、备注、文章标题或主题", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空搜索")
            }
        }
        .padding(.leading, 12)
        .frame(minHeight: 44)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 10))
    }

    private var filtersActive: Bool {
        kind != .all || status != .all || ability != nil || origin != nil || topic != nil || starredOnly
            || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func resetFilters() {
        query = ""
        kind = .all
        status = .all
        ability = nil
        origin = nil
        topic = nil
        starredOnly = false
    }

    // MARK: Sections

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("还没有词条", systemImage: "character.book.closed")
                .font(.headline)
            Text("在听读页点词，可以收藏这个义项；选中几个连着的词，可以存成词群。也可以在“词群”页手动添加，或者在词汇设置里从 CSV 导入旧生词。")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var knownSection: some View {
        Section {
            NavigationLink {
                VocabKnownHistoryView()
            } label: {
                LabeledContent("标成“认识”的词", value: "\(user.state.known.count) 个")
            }
        } header: {
            Text("认识的词（历史标记）")
        } footer: {
            Text("只作历史记录，不排复习。")
        }
    }

    // MARK: Data

    /// One pass over items and cards per render: facts from the cards, titles and topics of the source articles.
    private func buildRows() -> [VocabBrowseRowData] {
        var articles: [ArticleRef: ArticleMeta] = [:]
        for entry in packs.allItems where articles[entry.ref] == nil {
            articles[entry.ref] = entry.meta
        }
        let cardsByItem = Dictionary(grouping: vocab.state.cards, by: { $0.itemId })
        let endOfToday = VocabBrowseView.endOfToday()
        return vocab.state.items.map { (item: VocabItem) -> VocabBrowseRowData in
            var titles: [String] = []
            var topics: [String] = []
            var seen = Set<ArticleRef>()
            for occ in item.sources {
                guard seen.insert(occ.ref).inserted, let meta = articles[occ.ref] else { continue }
                titles.append(meta.title)
                for t in meta.topics ?? [] where !topics.contains(t) {
                    topics.append(t)
                }
            }
            return VocabBrowseRowData(item: item, facts: facts(cardsByItem[item.id] ?? [], endOfToday: endOfToday),
                                      titles: titles, topics: topics)
        }
    }

    /// Status of the item's switched-on cards. Each task has its own schedule, so several can be true.
    private func facts(_ cards: [VocabCard], endOfToday: Date) -> VocabBrowseFacts {
        var f = VocabBrowseFacts()
        let longSpan = Double(VocabStore.longIntervalDays) * 86_400
        for card in cards where !card.suspended {
            f.enabled += 1
            f.abilities.insert(card.task.ability)
            if card.isNew {
                f.hasNew = true
                continue
            }
            if card.fsrs.due < endOfToday {
                f.dueToday = true
            }
            if card.fsrs.state == .review, let last = card.fsrs.lastReview,
               card.fsrs.due.timeIntervalSince(last) >= longSpan {
                f.longInterval = true
            } else {
                f.inProgress = true
            }
        }
        return f
    }

    private static func endOfToday() -> Date {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        return cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }

    private func matches(_ row: VocabBrowseRowData, needle: String) -> Bool {
        let item = row.item
        switch kind {
        case .all: break
        case .sense: if item.kind != .sense { return false }
        case .chunk: if item.kind != .chunk { return false }
        }
        switch status {
        case .all: break
        case .fresh: if item.archived || !row.facts.hasNew { return false }
        case .learning: if item.archived || !row.facts.inProgress { return false }
        case .due: if item.archived || !row.facts.dueToday { return false }
        case .long: if item.archived || !row.facts.longInterval { return false }
        case .paused: if !item.archived { return false }
        }
        if let ability, !row.facts.abilities.contains(ability) { return false }
        if starredOnly && !item.starred { return false }
        if let origin, item.origin != origin { return false }
        if let topic, !row.topics.contains(topic) { return false }
        guard !needle.isEmpty else { return true }

        var fields = [item.text, item.gloss]
        if let key = item.key { fields.append(key) }
        if let note = item.note { fields.append(note) }
        if let usage = item.function { fields.append(usage) }
        fields += item.variants ?? []
        fields += row.titles
        fields += row.topics
        return VocabBrowseText.contains(fields, needle)
    }

    private func ordered(_ rows: [VocabBrowseRowData]) -> [VocabBrowseRowData] {
        switch sort {
        case .recent:
            return rows.sorted { $0.item.created > $1.item.created }
        case .alpha:
            return rows.sorted { a, b in
                let c = a.item.text.localizedStandardCompare(b.item.text)
                return c == .orderedSame ? a.item.created > b.item.created : c == .orderedAscending
            }
        }
    }

    private func topicList(_ rows: [VocabBrowseRowData]) -> [String] {
        var all = Set<String>()
        for row in rows {
            all.formUnion(row.topics)
        }
        if let topic { all.insert(topic) }
        return all.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

// MARK: - Browse helpers

private enum VocabBrowseKind: String, CaseIterable, Identifiable {
    case all, sense, chunk
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "全部"
        case .sense: return "义项"
        case .chunk: return "词群"
        }
    }
}

private enum VocabBrowseStatus: String, CaseIterable, Identifiable {
    case all, fresh, learning, due, long, paused
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "全部"
        case .fresh: return "新任务"
        case .learning: return "学习中"
        case .due: return "今天到期"
        case .long: return "较长复习间隔"
        case .paused: return "已暂停"
        }
    }
}

private enum VocabBrowseSort: String, CaseIterable, Identifiable {
    case recent, alpha
    var id: String { rawValue }
    var title: String { self == .recent ? "最近添加" : "字母" }
}

private struct VocabBrowseFacts {
    var enabled = 0                 // switched-on task cards
    var hasNew = false              // a task never answered yet
    var inProgress = false          // answered, interval under 21 days
    var dueToday = false            // a review due before the end of today
    var longInterval = false        // interval of 21 days or more ("较长复习间隔", not "掌握")
    var abilities = Set<VocabAbility>()
}

private struct VocabBrowseRowData: Identifiable {
    let item: VocabItem
    let facts: VocabBrowseFacts
    let titles: [String]            // source article titles
    let topics: [String]            // topics of the source articles
    var id: String { item.id }
}

/// Labels and text matching shared by the browse list and the detail page.
private enum VocabBrowseText {
    static let origins: [VocabItem.Origin] = [.reader, .annotation, .legacyStar, .csv, .manual, .family]

    static func origin(_ o: VocabItem.Origin) -> String {
        switch o {
        case .reader: return "听读页"
        case .annotation: return "短语标注"
        case .legacyStar: return "旧生词本"
        case .csv: return "CSV"
        case .manual: return "手动"
        case .family: return "词族"
        }
    }

    /// Case-, accent- and width-insensitive. Curly quotes and dashes count as straight ones
    /// (`needle` is already SentenceText-normalised).
    static func contains(_ fields: [String], _ needle: String) -> Bool {
        let fold = needle.contains("'") || needle.contains("\"") || needle.contains("-")
        return fields.contains { field in
            let hay = fold ? SentenceText.normalize(field) : field
            return hay.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil
        }
    }

    /// Other forms typed as one line: commas (either width), semicolons, 、 or new lines.
    static func splitList(_ text: String) -> [String] {
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

/// A filter as a rounded chip. The current value is always spelled out, so colour is never the only cue.
private struct VocabFilterChip: View {
    let text: String
    var systemImage = "chevron.down"
    var active = false

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
        }
        .font(.callout)
        .foregroundStyle(active ? Theme.accent : Color.primary)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(active ? Theme.accent.opacity(0.15) : Theme.chip, in: Capsule())
        .overlay {
            Capsule().strokeBorder(active ? Theme.accent : Color.clear, lineWidth: 1)
        }
        .contentShape(Capsule())
    }
}

private struct VocabBrowseRow: View {
    let row: VocabBrowseRowData
    let toggleStar: () -> Void

    var body: some View {
        let item = row.item
        let f = row.facts
        let hasBadges = item.archived || f.dueToday || f.hasNew || f.longInterval || f.enabled == 0
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.text)
                        .font(Font.system(.title3, design: .serif).weight(.semibold))
                    if let pos = item.pos, !pos.isEmpty {
                        Text(pos)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    if item.kind == .chunk {
                        Badge(text: "词群", outlined: true)
                    }
                }
                Text(item.gloss.isEmpty ? "还没有中文义" : item.gloss)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if hasBadges {
                    HStack(spacing: 6) {
                        if item.archived {
                            Badge(text: "已暂停", outlined: true)
                        } else {
                            if f.dueToday { Badge(text: "到期", color: Theme.level8) }
                            if f.hasNew { Badge(text: "新", color: Theme.level5) }
                            if f.longInterval { Badge(text: "较长间隔", color: Theme.level6) }
                            if f.enabled == 0 { Badge(text: "没开任务", outlined: true) }
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            Button(action: toggleStar) {
                Image(systemName: item.starred ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundStyle(item.starred ? Theme.warn : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(item.starred ? "取消收藏" : "收藏")
        }
        .padding(.vertical, 4)
    }
}

/// The old "认识" marks, read-only. They never schedule a review.
private struct VocabKnownHistoryView: View {
    @Environment(UserStore.self) private var user
    @Environment(PackStore.self) private var packs

    var body: some View {
        let known = user.state.known
        let keys = known.keys.sorted { (known[$0] ?? .distantPast) > (known[$1] ?? .distantPast) }
        List {
            Section {
                Label("只作历史记录，不排复习。", systemImage: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
            }
            Section {
                if keys.isEmpty {
                    Text("还没有标成“认识”的词。")
                        .foregroundStyle(.secondary)
                }
                ForEach(keys, id: \.self) { key in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key)
                                .font(.body.weight(.semibold))
                            let meaning = gloss(key)
                            if !meaning.isEmpty {
                                Text(meaning)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        if let date = known[key] {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("\(keys.count) 个")
            }
        }
        .navigationTitle("认识的词")
    }

    private func gloss(_ key: String) -> String {
        let entry = packs.entry(key)
        return entry?.card?.senses?.first?.zh ?? entry?.zh?.components(separatedBy: "\n").first ?? ""
    }
}

// MARK: - Item detail

/// One item: meaning, evidence per ability, task switches with their schedules, senses, contexts,
/// word family and roots, and the latest answers. Opening it is not a review.
struct VocabItemDetailView: View {
    let itemId: String

    @Environment(VocabStore.self) private var vocab
    @Environment(PackStore.self) private var packs
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false

    init(itemId: String) {
        self.itemId = itemId
    }

    var body: some View {
        Group {
            if let item = vocab.item(itemId) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header(item)
                        abilitySection(item)
                        taskSection(item)
                        if item.kind == .sense, let key = item.key {
                            senseSection(item, key: key)
                        }
                        contextSection(item)
                        if item.kind == .sense {
                            familySection(item)
                        }
                        historySection(item)
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(20)
                    .frame(maxWidth: .infinity)
                }
                .sheet(isPresented: $editing) {
                    VocabDetailEditSheet(item: item)
                }
            } else {
                ContentUnavailableView("找不到这个词条", systemImage: "questionmark.circle",
                                       description: Text("它可能已经被删掉，或者恢复备份后不在了。"))
            }
        }
        .navigationTitle(vocab.item(itemId)?.text ?? "词条")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header

    private func header(_ item: VocabItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(item.text)
                    .font(Font.system(.largeTitle, design: .serif).weight(.semibold))
                    .textSelection(.enabled)
                if let pos = item.pos, !pos.isEmpty {
                    Text(pos)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            Text(item.gloss.isEmpty ? "还没有中文义。点“编辑”补上。" : item.gloss)
                .font(.title3)
                .foregroundStyle(item.gloss.isEmpty ? Color.secondary : Color.primary)
            if item.kind == .chunk {
                if let variants = item.variants, !variants.isEmpty {
                    detailLine("其他形式", variants.joined(separator: "、"))
                }
                if let usage = item.function, !usage.isEmpty {
                    detailLine("用法和限制", usage)
                }
            }
            if let note = item.note, !note.isEmpty {
                detailLine("备注", note)
            }
            FlowLayout(spacing: 6, lineSpacing: 6) {
                Badge(text: item.kind == .chunk ? "词群" : "义项", outlined: true)
                Badge(text: "来源：" + VocabBrowseText.origin(item.origin), outlined: true)
                Badge(text: "加入于 " + item.created.formatted(date: .abbreviated, time: .omitted), outlined: true)
                if item.archived {
                    Badge(text: "已暂停复习", color: Theme.warn)
                }
                if item.legacyKnown != nil {
                    Badge(text: "旧标记：认识（只作历史）", outlined: true)
                }
            }
            HStack(spacing: 10) {
                Button {
                    editing = true
                } label: {
                    Label("编辑", systemImage: "square.and.pencil")
                }
                Button {
                    vocab.toggleStar(item.id)
                } label: {
                    Label(item.starred ? "已收藏" : "收藏", systemImage: item.starred ? "star.fill" : "star")
                }
                Button {
                    vocab.setArchived(item.id, !item.archived)
                } label: {
                    Label(item.archived ? "恢复复习" : "暂停复习",
                          systemImage: item.archived ? "play.circle" : "pause.circle")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            Text(item.archived
                 ? "已暂停：不会出现在复习里。作答记录都还在，随时可以恢复。"
                 : "暂停后不会出现在复习里；作答记录会保留，随时可以恢复。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func detailLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }

    // MARK: Evidence

    private func abilitySection(_ item: VocabItem) -> some View {
        let status = vocab.abilities(for: item.id)
        return CardSection(title: "能力证据") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                ForEach(VocabAbility.allCases) { a in
                    let st = status[a] ?? AbilityStatus()
                    GridRow {
                        Text(a.title)
                            .font(.body.weight(.semibold))
                        Text(st.label)
                        Text(abilityDetail(st))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text("“较长复习间隔”只说明下次复习隔得久（21 天以上），不等于掌握。几种能力分开记，不合成一个分数。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func abilityDetail(_ st: AbilityStatus) -> String {
        var parts: [String] = []
        if st.reviews > 0 {
            parts.append("答过 \(st.reviews) 次")
        }
        if let due = st.due {
            parts.append("下次 " + due.formatted(date: .abbreviated, time: .shortened))
        }
        if !st.enabled && st.reviews > 0 {
            parts.append("题型已关")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Tasks

    private func taskSection(_ item: VocabItem) -> some View {
        let byTask = Dictionary(vocab.cards(for: item.id).map { ($0.task, $0) }, uniquingKeysWith: { first, _ in first })
        return CardSection(title: "学习任务") {
            if item.archived {
                Text("这个词条已暂停。恢复复习后才能开关题型。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(VocabTask.allCases) { task in
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: taskBinding(task, itemId: item.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                    .font(.body.weight(.semibold))
                                Text(task.detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(item.archived)
                        if let card = byTask[task] {
                            VocabCardScheduleView(card: card)
                        }
                    }
                    .padding(.vertical, 10)
                    if task != VocabTask.allCases.last {
                        Divider()
                    }
                }
            }
            Text("新词默认只开“认义”。关掉一种题型只是暂停它，记录和排期都还在。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func taskBinding(_ task: VocabTask, itemId: String) -> Binding<Bool> {
        Binding(
            get: { vocab.isTaskEnabled(task, for: itemId) },
            set: { vocab.setTask(task, enabled: $0, for: itemId) }
        )
    }

    // MARK: Senses (VOC-F02)

    private func senseSection(_ item: VocabItem, key: String) -> some View {
        let senses = packs.entry(key)?.card?.senses ?? []
        let undecided = vocab.items(forKey: key).filter { $0.id != item.id && $0.senseIndex == nil }
        return CardSection(title: "义项") {
            if !packs.lexiconReady {
                ProgressView("正在载入词库…")
            } else if senses.isEmpty {
                Text("词库里没有这个词的义项列表。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(senses.enumerated()), id: \.offset) { i, sense in
                    senseRow(item, key: key, index: i, sense: sense)
                    if i < senses.count - 1 {
                        Divider()
                    }
                }
                if let chosen = item.senseIndex, chosen >= senses.count {
                    Text("收藏时选的是第 \(chosen + 1) 个义项，词库更新后对不上了。可以点“编辑”改中文义。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if !undecided.isEmpty {
                Text("同一个词还有义项未定的词条：")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(undecided) { other in
                    NavigationLink {
                        VocabItemDetailView(itemId: other.id)
                    } label: {
                        Text(other.gloss.isEmpty ? other.text : "\(other.text) · \(other.gloss)")
                            .frame(minHeight: 44)
                    }
                }
            }
            Text("同一个词的不同义项分开学，各有各的排期；认识一个义项，不影响另一个。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func senseRow(_ item: VocabItem, key: String, index i: Int, sense: Sense) -> some View {
        let other = vocab.item(VocabItem.senseID(key: key, senseIndex: i))
        let isThis = item.senseIndex == i
        return HStack(alignment: .center, spacing: 10) {
            Text("\(i + 1)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 20, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let pos = sense.pos, !pos.isEmpty {
                        Text(pos)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    Text(sense.zh ?? "")
                }
                if let en = sense.en, !en.isEmpty {
                    Text(en)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if isThis {
                Badge(text: "正在学", color: Theme.level5)
            } else if let other, other.archived {
                Button("恢复这个义项") {
                    vocab.setArchived(other.id, false)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else if let other {
                NavigationLink {
                    VocabItemDetailView(itemId: other.id)
                } label: {
                    Label("已单独学", systemImage: "checkmark.circle")
                        .frame(minHeight: 44)
                }
            } else {
                Button("单独学这个义项") {
                    _ = vocab.saveSense(key: key, text: key, pos: sense.pos ?? packs.entry(key)?.card?.pos,
                                        gloss: sense.zh ?? "", senseIndex: i, occurrence: nil, origin: .manual)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Contexts

    private func contextSection(_ item: VocabItem) -> some View {
        CardSection(title: "语境") {
            if item.sources.isEmpty {
                Text(item.origin == .csv ? "从 CSV 导入，没有原文语境。" : "还没有保存语境。")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(item.sources.enumerated()), id: \.offset) { _, occ in
                contextCard(occ)
            }
        }
    }

    private func contextCard(_ occ: Occurrence) -> some View {
        let article = packs.item(occ.ref)
        let caption: String = article.map { "\($0.meta.title) · \(occ.issue) 期" }
            ?? "\(occ.issue) 期 · 这期内容包不在这台 iPad 上"
        return VStack(alignment: .leading, spacing: 8) {
            VocabItemDetailView.sentenceText(occ)
                .font(Font.system(.body, design: .serif))
                .textSelection(.enabled)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if occ.unmapped == true {
                    Badge(text: "原句已更新", color: Theme.warn)
                }
            }
            if occ.unmapped == true {
                Text("内容包更新后这一句变了。这里显示的是收藏时的原句。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                dismiss()
                router.openArticle(occ.ref)
            } label: {
                Label("回到原文", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(article == nil)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }

    /// The saved sentence with the word(s) in bold, at the saved position when there is one.
    private static func sentenceText(_ occ: Occurrence) -> Text {
        guard let sentence = occ.sentence, !sentence.isEmpty else {
            return Text(occ.surface ?? "（没有保存原句）")
        }
        guard let surface = occ.surface, !surface.isEmpty else {
            return Text(sentence)
        }
        let near = occ.start.flatMap { SentenceText.range(of: surface, in: sentence, near: $0) }
        guard let range = near ?? sentence.range(of: surface) else {
            return Text(sentence)
        }
        var out = AttributedString(String(sentence[..<range.lowerBound]))
        var word = AttributedString(String(sentence[range]))
        word.inlinePresentationIntent = .stronglyEmphasized
        out.append(word)
        out.append(AttributedString(String(sentence[range.upperBound...])))
        return Text(out)
    }

    // MARK: Word family and roots (VOC-F06)

    @ViewBuilder
    private func familySection(_ item: VocabItem) -> some View {
        let card = packs.entry(item.key)?.card
        let roots = (card?.roots ?? []).filter { !($0.first ?? "").isEmpty }
        let core = card?.core ?? ""
        let memo = card?.memo ?? ""
        let family = (card?.family ?? []).filter { !($0.w ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
        CardSection(title: "词族与词根") {
            if roots.isEmpty && core.isEmpty && memo.isEmpty && family.isEmpty {
                Text(packs.lexiconReady ? "暂无词根资料" : "正在载入词库…")
                    .foregroundStyle(.secondary)
            } else {
                if !roots.isEmpty {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(Array(roots.enumerated()), id: \.offset) { _, r in
                            rootChip(r)
                        }
                    }
                }
                if !core.isEmpty {
                    detailLine("核心义", core)
                }
                if !memo.isEmpty {
                    Text(memo)
                }
                if !family.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(family.enumerated()), id: \.offset) { n, f in
                            familyRow(f)
                            if n < family.count - 1 {
                                Divider()
                            }
                        }
                    }
                    Text("词族里的词要分别建学习任务；记住词根或学会一个词，不等于整个词族都会了。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func rootChip(_ r: [String]) -> some View {
        let part = r.count > 0 ? r[0] : ""
        let meaning = r.count > 1 ? r[1] : ""
        let kind = VocabItemDetailView.rootKind(r.count > 2 ? r[2] : "")
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(part)
                    .font(.callout.weight(.bold))
                if !kind.isEmpty {
                    Text(kind)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if !meaning.isEmpty {
                Text(meaning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    /// Kind of a root part in words, so it is not shown by colour only.
    private static func rootKind(_ kind: String) -> String {
        switch kind.lowercased() {
        case "prefix": return "前缀"
        case "suffix": return "后缀"
        case "root": return "词根"
        default: return kind
        }
    }

    private func familyRow(_ f: Family) -> some View {
        let word = (f.w ?? "").trimmingCharacters(in: .whitespaces)
        let key = lexiconKey(word)
        let entry = packs.entry(key)
        let existing = key.map { vocab.items(forKey: $0) } ?? []
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(word)
                        .font(.body.weight(.semibold))
                    if let pos = f.pos, !pos.isEmpty {
                        Text(pos)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                if let zh = f.zh, !zh.isEmpty {
                    Text(zh)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let key, let entry {
                if let first = existing.first {
                    NavigationLink {
                        VocabItemDetailView(itemId: first.id)
                    } label: {
                        Label("已在学", systemImage: "checkmark.circle")
                            .frame(minHeight: 44)
                    }
                } else {
                    Button("建学习任务") {
                        addFamilyWord(key: key, entry: entry, family: f)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            } else {
                Text(packs.lexiconReady ? "词库里没有，只能浏览" : "正在载入词库…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    /// The lexicon key of a family word, as written or in lower case.
    private func lexiconKey(_ word: String) -> String? {
        guard !word.isEmpty else { return nil }
        if packs.lexicon[word] != nil { return word }
        let lower = word.lowercased()
        return packs.lexicon[lower] != nil ? lower : nil
    }

    private func addFamilyWord(key: String, entry: LexEntry, family f: Family) {
        let senses = entry.card?.senses ?? []
        let first = senses.first
        let dictionaryGloss = entry.zh?.components(separatedBy: "\n").first
        let gloss = first?.zh ?? f.zh ?? dictionaryGloss ?? ""
        let pos = first?.pos ?? f.pos ?? entry.card?.pos
        vocab.saveSense(key: key, text: key, pos: pos, gloss: gloss, senseIndex: senses.isEmpty ? nil : 0,
                        occurrence: nil, origin: .family)
    }

    // MARK: Latest answers

    private func historySection(_ item: VocabItem) -> some View {
        let events = vocab.events(for: item.id)
        let undone = Set(events.compactMap { $0.kind == .undo ? $0.undoes : nil })
        let recent = Array(events.filter { $0.kind == .review || $0.kind == .undo }.suffix(10).reversed())
        return CardSection(title: "最近作答") {
            if recent.isEmpty {
                Text("还没有作答记录。")
                    .foregroundStyle(.secondary)
            }
            ForEach(recent) { e in
                eventRow(e, undone: undone.contains(e.id))
            }
            Text("只看词条、听词，都不算复习。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func eventRow(_ e: ReviewEvent, undone: Bool) -> some View {
        let when = e.day + " " + e.at.formatted(date: .omitted, time: .shortened)
        let task = e.task?.title ?? "—"
        var parts: [String] = []
        if e.kind == .undo {
            parts.append("撤销了一次作答")
        } else {
            if let rating = e.rating.flatMap({ FSRSRating(rawValue: $0) }) {
                parts.append(rating.title)
            }
            if let correct = e.correct {
                parts.append(correct ? "对" : "错")
            }
            if e.revealedEarly == true {
                parts.append("提前看答案")
            }
            if (e.hint ?? 0) > 0 {
                parts.append("用了提示")
            }
            if e.userAccepted == true {
                parts.append("我的答案也可以")
            }
        }
        let summary = parts.joined(separator: " · ")
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(when)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 130, alignment: .leading)
            Text(task)
                .font(.callout.weight(.semibold))
            Text(summary)
                .font(.callout)
            Spacer(minLength: 0)
            if undone {
                Badge(text: "已撤销", outlined: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Schedule of one card

/// Why a card is due when it is (VOC-P01): the numbers FSRS used. No random fuzz is added,
/// so every date can be explained from these values.
struct VocabCardScheduleView: View {
    let card: VocabCard

    @Environment(VocabStore.self) private var vocab

    init(card: VocabCard) {
        self.card = card
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if card.isNew {
                Text(card.suspended ? "新任务（这种题型已关）" : "新任务：还没做过。每天的预算有空时会排进来。")
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 14, lineSpacing: 6) {
                    fact("状态", stateTitle)
                    fact("到期", card.fsrs.due.formatted(date: .abbreviated, time: .shortened))
                    fact("间隔", intervalText)
                    fact("稳定性", card.fsrs.stability.map { String(format: "%.1f 天", $0) } ?? "—")
                    fact("难度", card.fsrs.difficulty.map { String(format: "%.1f（1–10）", $0) } ?? "—")
                    fact("现在记住的概率", recallText)
                    fact("上次复习", card.fsrs.lastReview.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
                    fact("复习", "\(card.fsrs.reps) 次")
                    fact("忘记", "\(card.fsrs.lapses) 次")
                }
                Text(explanation)
                    .foregroundStyle(.secondary)
                if card.suspended {
                    Text("这种题型已关，排期停在这里。")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.caption)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
                .fontWeight(.semibold)
        }
    }

    private var stateTitle: String {
        switch card.fsrs.state {
        case .learning: return "学习中"
        case .review: return "复习"
        case .relearning: return "重学"
        }
    }

    private var intervalText: String {
        guard let last = card.fsrs.lastReview else { return "—" }
        if card.fsrs.state != .review {
            let minutes = max(1, Int((card.fsrs.due.timeIntervalSince(last) / 60).rounded()))
            return "\(minutes) 分钟（学习步）"
        }
        return "\(FSRSScheduler.wholeDays(from: last, to: card.fsrs.due)) 天"
    }

    /// FSRS prediction for now; it counts whole days since the last review, so it is 100% on that day.
    private var recallText: String {
        let r = vocab.scheduler.retrievability(card.fsrs, at: Date())
        return "\(Int((r * 100).rounded()))%"
    }

    private var explanation: String {
        switch card.fsrs.state {
        case .review:
            let target = Int((vocab.settings.retention * 100).rounded())
            return "到期日 = 上次复习 + 间隔。间隔由稳定性和目标保留率（现在设为 \(target)%）算出，不加随机抖动。"
        case .learning, .relearning:
            return "还在短学习步里：几分钟后再出现，答对后转入按天复习。"
        }
    }
}

// MARK: - Edit sheet

private struct VocabDetailEditSheet: View {
    let item: VocabItem

    @Environment(VocabStore.self) private var vocab
    @Environment(\.dismiss) private var dismiss
    @State private var gloss: String
    @State private var note: String
    @State private var variants: String
    @State private var usage: String

    init(item: VocabItem) {
        self.item = item
        _gloss = State(initialValue: item.gloss)
        _note = State(initialValue: item.note ?? "")
        _variants = State(initialValue: (item.variants ?? []).joined(separator: ", "))
        _usage = State(initialValue: item.function ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(item.text)
                        .font(Font.system(.title2, design: .serif).weight(.semibold))
                } footer: {
                    Text(item.kind == .chunk
                         ? "词群的写法就是它的身份，这里不能改。要换写法，请另外添加一个词群。"
                         : "词形跟着词库，这里不能改。")
                }
                Section("中文义") {
                    TextField("这个意思的中文", text: $gloss, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section("备注") {
                    TextField("可以不写", text: $note, axis: .vertical)
                        .lineLimit(2...6)
                }
                if item.kind == .chunk {
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
                    }
                }
            }
            .navigationTitle("编辑词条")
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
                }
            }
        }
    }

    private func save() {
        let newGloss = gloss.trimmingCharacters(in: .whitespacesAndNewlines)
        let newNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let newVariants = VocabBrowseText.splitList(variants)
        let newUsage = usage.trimmingCharacters(in: .whitespacesAndNewlines)
        let isChunk = item.kind == .chunk
        vocab.editItem(item.id) { it in
            it.gloss = newGloss
            it.note = newNote.isEmpty ? nil : newNote
            if isChunk {
                it.variants = newVariants.isEmpty ? nil : newVariants
                it.function = newUsage.isEmpty ? nil : newUsage
            }
        }
    }
}
