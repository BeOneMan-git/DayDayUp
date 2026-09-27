import SwiftUI
import UniformTypeIdentifiers

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, unfinished, finished
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "全部"
        case .unfinished: return "未听完"
        case .finished: return "已听完"
        }
    }
}

/// 书架: issues newest first, each article with 听 / 读 / 跟 rings.
struct LibraryView: View {
    @Environment(PackStore.self) private var packs
    @Environment(UserStore.self) private var user
    @State private var filter: LibraryFilter = .all
    @State private var topic: String?
    @State private var showImporter = false
    @State private var showMessage = false

    private static let topicOrder = ["科技", "环境", "教育", "健康", "工作", "政府", "经济", "社会", "文化", "媒体", "国际", "交通"]

    var body: some View {
        List {
            if packs.packs.isEmpty {
                emptyState
            }
            ForEach(packs.groups) { group in
                let items = group.items.filter(matches)
                if !items.isEmpty {
                    Section {
                        ForEach(items) { item in
                            NavigationLink(value: item.ref) {
                                ArticleRow(item: item)
                            }
                        }
                    } header: {
                        Text("\(group.issue) 期 · \(group.items.count) 篇")
                    }
                }
            }
        }
        .navigationTitle("书架")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Picker("进度", selection: $filter) {
                        ForEach(LibraryFilter.allCases) { f in
                            Text(f.title).tag(f)
                        }
                    }
                    Picker("雅思话题", selection: $topic) {
                        Text("全部话题").tag(String?.none)
                        ForEach(availableTopics, id: \.self) { t in
                            Text(t).tag(String?.some(t))
                        }
                    }
                } label: {
                    Label("筛选", systemImage: filter == .all && topic == nil
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                }
                Button {
                    showImporter = true
                } label: {
                    Label("导入内容包", systemImage: "square.and.arrow.down")
                }
            }
        }
        .overlay {
            if packs.isImporting {
                ProgressView("正在导入…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.ecopack, .data],
                      allowsMultipleSelection: true) { result in
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
        .alert("内容包", isPresented: $showMessage) {
            Button("好") {}
        } message: {
            Text(packs.lastMessage ?? "")
        }
    }

    private var availableTopics: [String] {
        let present = Set(packs.allItems.flatMap { $0.meta.topics ?? [] })
        return LibraryView.topicOrder.filter { present.contains($0) }
            + present.subtracting(LibraryView.topicOrder).sorted()
    }

    private func matches(_ item: LibraryItem) -> Bool {
        if let topic, !(item.meta.topics ?? []).contains(topic) { return false }
        let listened = user.state.listenProgress(item.ref.key, duration: item.meta.dur)
        switch filter {
        case .all: return true
        case .unfinished: return listened < 1
        case .finished: return listened >= 1
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
}

struct ArticleRow: View {
    @Environment(UserStore.self) private var user
    let item: LibraryItem

    var body: some View {
        let key = item.ref.key
        let meta = item.meta
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text([meta.section, meta.fly ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(meta.title)
                    .font(Font.system(.title3, design: .serif).weight(.semibold))
                HStack(spacing: 10) {
                    Text(formatTime(meta.dur))
                    if let nw = meta.nw { Text("\(nw) 词") }
                    if let n5 = meta.n5 { Text("5 级+ \(n5) 个") }
                    ForEach(meta.topics ?? [], id: \.self) { t in
                        Text(t)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Theme.chip, in: Capsule())
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ResourceChips(ref: item.ref)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                ProgressRing(label: "听", value: user.state.listenProgress(key, duration: meta.dur))
                ProgressRing(label: "读", value: user.state.readProgress(key, duration: meta.dur), tint: Theme.level5)
                ProgressRing(label: "跟", value: 0, disabled: true)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
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

