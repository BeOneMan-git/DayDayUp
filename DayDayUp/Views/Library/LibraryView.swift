import SwiftUI
import UniformTypeIdentifiers

/// 书架 (PAGE-02, IMP-F06, IMP-F07): issues newest first (or by topic), search, filters, and for each article
/// the four kinds of state: 接触 / 听读完成 / 跟读练习 / 独立复测.
struct LibraryView: View {
    @Environment(PackStore.self) private var packs
    @Environment(UserStore.self) private var user
    @Environment(StudyStore.self) private var study
    @Environment(PracticeStore.self) private var practice
    @State private var mode: ShelfMode = .issue
    @State private var query = ""
    @State private var filters = ShelfFilters()
    @State private var sheet: ShelfSheet?
    @State private var showImporter = false
    @State private var showMessage = false

    /// Sheets opened from a row's context menu.
    enum ShelfSheet: Identifiable {
        case quiz(LibraryItem)
        case info(LibraryItem)

        var id: String {
            switch self {
            case .quiz(let item): return "quiz:" + item.id
            case .info(let item): return "info:" + item.id
            }
        }
    }

    var body: some View {
        let entries = ShelfIndex.entries(packs: packs, user: user, study: study, practice: practice)
        let sections = ShelfIndex.sections(entries, mode: mode, query: query, filters: filters)
        shelfList(entries: entries, sections: sections)
            .navigationTitle("书架")
            .searchable(text: $query, prompt: "搜索标题、期号、栏目、主题")
            .toolbar { toolbarContent(topics: ShelfIndex.topics(entries)) }
            .overlay { importOverlay }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.ecopack, .data],
                          allowsMultipleSelection: true) { result in
                importPicked(result)
            }
            .alert("内容包", isPresented: $showMessage) {
                Button("好") {}
            } message: {
                Text(packs.lastMessage ?? "")
            }
            .sheet(item: $sheet) { s in
                sheetContent(s)
            }
    }

    private var isSearching: Bool {
        !ShelfIndex.searchTerms(query).isEmpty
    }

    // MARK: List

    private func shelfList(entries: [ShelfEntry], sections: [ShelfSection]) -> some View {
        List {
            if packs.packs.isEmpty {
                emptyState
            } else {
                controlsSection
                if !filters.isActive && !isSearching, let last = continueEntry(entries) {
                    continueSection(last)
                }
                if sections.isEmpty {
                    noMatchSection
                }
                ForEach(sections) { section in
                    Section {
                        ForEach(section.entries) { entry in
                            row(entry)
                        }
                    } header: {
                        Text(section.title)
                    }
                }
                footnoteSection
            }
        }
    }

    private var controlsSection: some View {
        Section {
            Picker("分组方式", selection: $mode) {
                ForEach(ShelfMode.allCases) { m in
                    Text(m.title).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .listRowBackground(Color.clear)
            if filters.isActive {
                filterChips
                    .listRowBackground(Color.clear)
            }
        }
    }

    private func row(_ entry: ShelfEntry) -> some View {
        NavigationLink(value: entry.ref) {
            ShelfRow(entry: entry)
        }
        .contextMenu {
            rowMenu(entry)
        }
    }

    @ViewBuilder
    private func rowMenu(_ entry: ShelfEntry) -> some View {
        Menu {
            ArticleDifficultyMenu(ref: entry.ref)
        } label: {
            Label("我的难度（\(ArticleDifficultyText.short(entry.difficulty))）", systemImage: "chart.bar")
        }
        if entry.quizAvailable {
            Button {
                sheet = .quiz(entry.item)
            } label: {
                Label("做理解题", systemImage: "checklist")
            }
        }
        Button {
            sheet = .info(entry.item)
        } label: {
            Label("资源与版本", systemImage: "info.circle")
        }
    }

    @ViewBuilder
    private func sheetContent(_ s: ShelfSheet) -> some View {
        switch s {
        case .quiz(let item):
            ArticleQuizView(ref: item.ref, purpose: "practice")
        case .info(let item):
            ArticleInfoSheet(item: item)
        }
    }

    // MARK: 继续

    private func continueEntry(_ entries: [ShelfEntry]) -> ShelfEntry? {
        guard let key = user.state.lastArticle else { return nil }
        return entries.first { $0.id == key }
    }

    private func continueSection(_ entry: ShelfEntry) -> some View {
        Section {
            NavigationLink(value: entry.ref) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.item.meta.title)
                            .font(Font.system(.body, design: .serif).weight(.semibold))
                        Text(continueDetail(entry))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "play.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("继续听读")
        }
    }

    private func continueDetail(_ entry: ShelfEntry) -> String {
        var parts = ["\(entry.ref.issue) 期", entry.item.meta.section]
        if let pos = user.state.positions[entry.id], pos > 1 {
            parts.append("上次停在 \(formatTime(pos)) / \(formatTime(entry.item.meta.dur))")
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: Filters

    @ToolbarContentBuilder
    private func toolbarContent(topics: [String]) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            filterMenu(topics: topics)
            Button {
                showImporter = true
            } label: {
                Label("导入内容包", systemImage: "square.and.arrow.down")
            }
        }
    }

    private func filterMenu(topics: [String]) -> some View {
        Menu {
            Section("个人难度（可多选）") {
                ForEach([0, 1, 2, 3, 4, 5], id: \.self) { n in
                    Toggle(ArticleDifficultyText.filterTitle(n), isOn: difficultyBinding(n))
                        .menuActionDismissBehavior(.disabled)
                }
            }
            Section("资源与校准") {
                Toggle("可离线（正文、原音、时间轴都在）", isOn: $filters.offline)
                Toggle("待校准（报过“音频对不上”）", isOn: $filters.calibration)
            }
            Picker("听读进度", selection: $filters.progress) {
                ForEach(ShelfProgress.allCases) { p in
                    Text(p.title).tag(p)
                }
            }
            Picker("主题", selection: $filters.topic) {
                Text("全部主题").tag(String?.none)
                ForEach(topics, id: \.self) { t in
                    Text(t).tag(String?.some(t))
                }
            }
            if filters.isActive {
                Button {
                    filters = ShelfFilters()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
                }
            }
        } label: {
            Label("筛选", systemImage: filters.isActive
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel(filters.isActive ? "筛选（已开启）" : "筛选")
    }

    private func difficultyBinding(_ n: Int) -> Binding<Bool> {
        Binding(
            get: { filters.difficulties.contains(n) },
            set: { on in
                if on {
                    filters.difficulties.insert(n)
                } else {
                    filters.difficulties.remove(n)
                }
            }
        )
    }

    /// Active filters as removable chips, plus 清除筛选.
    private var filterChips: some View {
        FlowLayout(spacing: 8, lineSpacing: 4) {
            ForEach(filters.difficulties.sorted(), id: \.self) { n in
                chip(n == 0 ? "难度未评" : "难度 \(n)/5") { _ = filters.difficulties.remove(n) }
            }
            if filters.offline {
                chip("可离线") { filters.offline = false }
            }
            if filters.calibration {
                chip("待校准") { filters.calibration = false }
            }
            if filters.progress != .all {
                chip(filters.progress.title) { filters.progress = .all }
            }
            if let topic = filters.topic {
                chip("主题：\(topic)") { filters.topic = nil }
            }
            Button {
                filters = ShelfFilters()
            } label: {
                Text("清除筛选")
                    .font(.callout)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
    }

    private func chip(_ title: String, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.chip, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("去掉筛选条件：\(title)")
    }

    private func clearAll() {
        filters = ShelfFilters()
        query = ""
    }

    // MARK: Messages

    private var noMatchSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("没有符合条件的文章", systemImage: "magnifyingglass")
                    .font(.headline)
                Text(noMatchDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button {
                    clearAll()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 8)
        }
    }

    private var noMatchDetail: String {
        if isSearching && filters.isActive { return "搜索词和筛选条件一起用时，没有文章同时符合。" }
        if isSearching { return "标题、期号、栏目和主题里都没有找到“\(query.trimmingCharacters(in: .whitespacesAndNewlines))”。" }
        return "当前的筛选条件下没有文章。"
    }

    private var footnoteSection: some View {
        Section {
            Text("听读完成 = 音频去重覆盖 ≥90%，不等于听懂。独立复测 = 隔日回忆或新材料复测。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("还没有内容包", systemImage: "books.vertical")
                .font(.headline)
            Text("点右上角的“导入内容包”，选 .ecopack 文件。也可以在“文件”App 里点一下内容包，或者把它放进“我的 iPad › DayDayUp”文件夹，打开 App 时会自动导入。")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    // MARK: Import

    @ViewBuilder
    private var importOverlay: some View {
        if packs.isImporting {
            ProgressView("正在导入…")
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func importPicked(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        Task {
            var messages: [String] = []
            for url in urls {
                messages.append(await packs.importPack(from: url))
            }
            packs.lastMessage = messages.joined(separator: "\n")
            showMessage = true
        }
    }
}

/// One article on the shelf: title, section · issue · duration, the learner's difficulty, the four states,
/// and what the article offers offline.
struct ShelfRow: View {
    let entry: ShelfEntry

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.item.meta.title)
                    .font(Font.system(.title3, design: .serif).weight(.semibold))
                Text(metaLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                tagLine
                ShelfStageStrip(stages: entry.stages)
                ResourceChips(ref: entry.ref)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                ProgressRing(label: "听", value: entry.listen)
                ProgressRing(label: "读", value: entry.read, tint: Theme.level5)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    /// Section · fly title · issue · duration · words.
    private var metaLine: String {
        let meta = entry.item.meta
        var parts = [meta.section]
        if let fly = meta.fly { parts.append(fly) }
        parts.append("\(entry.ref.issue) 期")
        parts.append(formatTime(meta.dur))
        if let nw = meta.nw { parts.append("\(nw) 词") }
        if let n5 = meta.n5 { parts.append("5 级+ \(n5) 个") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var tagLine: some View {
        FlowLayout(spacing: 6, lineSpacing: 4) {
            Text(ArticleDifficultyText.label(entry.difficulty))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1))
            if entry.calibration {
                Label("待校准：音频对不上", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.warn)
            }
            ForEach(ShelfIndex.cleanTopics(entry.item.meta.topics), id: \.self) { t in
                Text(t)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Theme.chip, in: Capsule())
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// IMP-F06: 接触 / 听读完成 / 跟读练习 / 独立复测 as symbol + text. Reached = filled check; not reached = empty
/// circle in secondary colour. Never colour alone.
struct ShelfStageStrip: View {
    let stages: ShelfStages

    var body: some View {
        FlowLayout(spacing: 12, lineSpacing: 4) {
            stage("接触", stages.contact)
            stage("听读完成", stages.listened)
            stage("跟读练习", stages.shadowed)
            stage("独立复测", stages.checked)
        }
        .font(.caption)
    }

    private func stage(_ title: String, _ reached: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: reached ? "checkmark.circle.fill" : "circle")
            Text(title)
        }
        .foregroundStyle(reached ? Theme.accent : Color.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)：\(reached ? "已达到" : "未达到")")
    }
}

/// PKG-P04: what this article offers offline. Missing resources are named; nothing pretends to be there.
struct ResourceChips: View {
    @Environment(PackStore.self) private var packs
    let ref: ArticleRef

    var body: some View {
        let list = packs.resources(ref).list
        let have = list.filter { $0.1 == .available }.map(\.0)
        let missing = list.filter { $0.1 == .missing }.map(\.0)
        HStack(spacing: 6) {
            if !have.isEmpty {
                Text("有：" + have.joined(separator: "·"))
                    .foregroundStyle(.secondary)
            }
            if !missing.isEmpty {
                Text("缺：" + missing.joined(separator: "、"))
                    .foregroundStyle(Theme.warn)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .overlay(Capsule().strokeBorder(Theme.warn.opacity(0.6), lineWidth: 1))
            }
        }
        .font(.caption2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("资源：有 \(have.joined(separator: "、"))" + (missing.isEmpty ? "" : "；缺 \(missing.joined(separator: "、"))"))
    }
}
