import SwiftUI

/// 资源清单 (OFF-01, PKG-P04): every content pack with its version, format, date and provenance, and every article
/// with what it has on this iPad. Each state is a symbol plus a word, never colour alone.
struct ResourceListView: View {
    @Environment(PackStore.self) private var packs

    var body: some View {
        List {
            if packs.packs.isEmpty {
                ContentUnavailableView("还没有内容包", systemImage: "shippingbox",
                                       description: Text("在“设置 › 资源与能力”里点“导入内容包”，或者在书架右上角导入。"))
            } else {
                overviewSection
                ForEach(packs.packs) { pack in
                    packSection(pack)
                }
            }
        }
        .navigationTitle("资源清单")
    }

    // MARK: Sections

    private var overviewSection: some View {
        let states = packs.allItems.map { packs.resources($0.ref) }
        let listen = states.filter { PackLabels.canListenOffline($0) }.count
        let quiz = states.filter { $0.quiz == .available }.count
        let marks = states.filter { $0.annotations == .available }.count
        let gaps = states.filter { !PackLabels.missingLabels($0).isEmpty }.count
        return Section {
            LabeledContent("内容包", value: "\(packs.packs.count) 个")
            LabeledContent("文章", value: "\(states.count) 篇")
            LabeledContent("可以断网听读", value: "\(listen) 篇")
            LabeledContent("有理解题", value: "\(quiz) 篇")
            LabeledContent("有发音标注", value: "\(marks) 篇")
            LabeledContent("缺某种资源", value: "\(gaps) 篇")
        } header: {
            Text("总览")
        } footer: {
            Text("“可以断网听读”：正文、原音、时间轴都在这台 iPad 上。点一篇文章，看它缺什么、断网能做什么。")
        }
    }

    private func packSection(_ pack: InstalledPack) -> some View {
        let m = pack.manifest
        return Section {
            LabeledContent("版本", value: PackLabels.version(m))
            LabeledContent("格式", value: "格式 \(m.format)")
            LabeledContent("生成日期", value: PackLabels.created(m))
            if let producer = m.producer, !producer.isEmpty {
                LabeledContent("制作工具", value: producer)
            }
            provenanceRows(m)
            LabeledContent("大小", value: SettingsFormat.megabytes(PackLabels.bytes(m)))
            ForEach(m.articles) { meta in
                articleLink(ArticleRef(issue: m.issue, id: meta.id), meta: meta, pack: pack)
            }
        } header: {
            Text(PackLabels.title(m))
        } footer: {
            Text("内容包 \(m.packId)")
        }
    }

    @ViewBuilder
    private func provenanceRows(_ m: PackManifest) -> some View {
        let kinds = (m.provenance ?? [:]).keys.sorted()
        if kinds.isEmpty {
            LabeledContent("来源说明", value: PackLabels.provenanceState(nil))
        } else {
            ForEach(kinds, id: \.self) { kind in
                LabeledContent(PackLabels.provenanceTitle(kind), value: PackLabels.provenanceState(m.provenance?[kind]))
            }
        }
    }

    private func articleLink(_ ref: ArticleRef, meta: ArticleMeta, pack: InstalledPack) -> some View {
        let missing = PackLabels.missingLabels(packs.resources(ref))
        let summary = missing.isEmpty ? "资源齐全" : "缺：" + missing.joined(separator: "、")
        return NavigationLink {
            ArticleResourceView(ref: ref, meta: meta, pack: pack)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(meta.title)
                    .font(Font.system(.body, design: .serif))
                Label(summary, systemImage: missing.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(missing.isEmpty ? Color.secondary : Theme.warn)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// One article: what it can do offline on this iPad, each resource with its state, and its pack version.
struct ArticleResourceView: View {
    let ref: ArticleRef
    let meta: ArticleMeta
    let pack: InstalledPack

    @Environment(PackStore.self) private var packs

    var body: some View {
        let res = packs.resources(ref)
        Form {
            articleSection
            abilitySection(res)
            resourceSection(res)
            versionSection
        }
        .navigationTitle("文章资源")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var articleSection: some View {
        Section("文章") {
            Text(meta.title)
                .font(Font.system(.headline, design: .serif))
            LabeledContent("期号", value: ref.issue)
            LabeledContent("栏目", value: meta.section)
            LabeledContent("时长", value: formatTime(meta.dur))
        }
    }

    private func abilitySection(_ r: ArticleResources) -> some View {
        Section {
            ForEach(PackLabels.abilities(r)) { a in
                abilityRow(a)
            }
        } header: {
            Text("断网能做什么")
        } footer: {
            Text("按下面的资源推出来的。缺的资源，重新导入完整的内容包可以补上；理解题和发音标注要新版内容包（格式 2）。")
        }
    }

    private func abilityRow(_ a: ArticleAbility) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: a.available ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(a.available ? Theme.level5 : Theme.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.title)
                Text(a.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(a.available ? "可以" : "不能")
                .foregroundStyle(a.available ? Color.secondary : Theme.warn)
        }
        .accessibilityElement(children: .combine)
    }

    private func resourceSection(_ r: ArticleResources) -> some View {
        Section {
            ForEach(PackLabels.rows(r)) { row in
                resourceRow(row)
            }
        } header: {
            Text("资源")
        } footer: {
            Text("有 = 在 iPad 上；缺 = 应该有但没有；不需要 = 这篇文章用不到。")
        }
    }

    private func resourceRow(_ row: ResourceRowItem) -> some View {
        let file = row.state == .missing ? PackLabels.file(for: row.label, ref: ref, meta: meta) : nil
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: PackLabels.stateSymbol(row.state))
                .foregroundStyle(row.state == .missing ? Theme.warn : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                Text(PackLabels.purpose(row.label))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let file {
                    Text("缺文件：\(file)")
                        .font(.caption)
                        .foregroundStyle(Theme.warn)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 8)
            Text(PackLabels.stateText(row.state))
                .foregroundStyle(row.state == .missing ? Theme.warn : Color.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var versionSection: some View {
        let m = pack.manifest
        return Section("内容版本") {
            LabeledContent("内容包", value: m.packId)
            LabeledContent("版本", value: PackLabels.version(m))
            LabeledContent("格式", value: "格式 \(m.format)")
            LabeledContent("生成日期", value: PackLabels.created(m))
            if let rev = meta.contentRevision {
                LabeledContent("本文修订", value: "第 \(rev) 版")
            }
        }
    }
}

/// One resource of an article with its state.
struct ResourceRowItem: Identifiable {
    let label: String
    let state: ResourceState
    var id: String { label }
}

/// Something the learner can or cannot do with an article offline, and why.
struct ArticleAbility: Identifiable {
    let title: String
    let available: Bool
    let note: String
    var id: String { title }
}

/// Words for packs and resources, shared by the 资源清单 pages and the 设置 pack list.
enum PackLabels {
    static func title(_ m: PackManifest) -> String {
        m.parts > 1 ? "\(m.issue) 期 · 第 \(m.part)/\(m.parts) 部分" : "\(m.issue) 期"
    }

    static func version(_ m: PackManifest) -> String {
        m.packageRevision.map { "第 \($0) 版" } ?? m.version
    }

    static func created(_ m: PackManifest) -> String {
        let made = m.createdAt ?? m.created ?? ""
        return made.isEmpty ? "没有写" : made
    }

    /// Size of the pack's files, from the manifest (format 1 `files` or format 2 `assets`).
    static func bytes(_ m: PackManifest) -> Int {
        m.checks.values.reduce(0) { $0 + $1.size }
    }

    // IMP-F05: how the content was made.
    static func provenanceTitle(_ kind: String) -> String {
        switch kind {
        case "cards": return "词卡"
        case "translation": return "翻译"
        case "grammar": return "句子解析"
        case "notes": return "短语与注释"
        case "annotations": return "发音标注"
        default: return kind
        }
    }

    static func provenanceState(_ value: String?) -> String {
        switch value {
        case "checked": return "已人工核对"
        case "partly": return "部分人工核对"
        case "rule": return "规则生成，待核对"
        default: return "程序生成，未经人工核对"
        }
    }

    static func stateText(_ s: ResourceState) -> String {
        switch s {
        case .available: return "有"
        case .missing: return "缺"
        case .notRequired: return "不需要"
        }
    }

    static func stateSymbol(_ s: ResourceState) -> String {
        switch s {
        case .available: return "checkmark.circle.fill"
        case .missing: return "exclamationmark.triangle.fill"
        case .notRequired: return "minus.circle"
        }
    }

    static func rows(_ r: ArticleResources) -> [ResourceRowItem] {
        r.list.map { pair in ResourceRowItem(label: pair.0, state: pair.1) }
    }

    static func missingLabels(_ r: ArticleResources) -> [String] {
        r.list.filter { $0.1 == .missing }.map { $0.0 }
    }

    /// Text, audio and timing are all here: the article can be listened to and read offline (like 书架's 可离线).
    static func canListenOffline(_ r: ArticleResources) -> Bool {
        r.text == .available && r.audio == .available && r.timing == .available
    }

    /// What each resource is for, in plain words.
    static func purpose(_ label: String) -> String {
        switch label {
        case "正文": return "英文原文和段落。"
        case "原音": return "文章的朗读音频。"
        case "时间轴": return "每个词、每一句的时间：逐词高亮、点句播放和跟读都靠它。"
        case "词音": return "单词的原声，从原音里切出来；没有时用合成音。"
        case "词义": return "单词卡的释义（词库）。"
        case "标注": return "跟读用的发音标注。"
        case "题目": return "理解题。"
        case "PDF": return "原版版面文件；App 现在不用。"
        default: return ""
        }
    }

    /// The file inside the pack that a resource comes from (nil when it has no file of its own).
    static func file(for label: String, ref: ArticleRef, meta: ArticleMeta) -> String? {
        switch label {
        case "正文": return "articles/\(ref.id).json"
        case "原音": return meta.audio
        case "词义": return "lexicon.json"
        case "标注": return "annotations/\(ref.id).json"
        case "题目": return "quiz/\(ref.id).json"
        default: return nil
        }
    }

    /// PKG-P04: what the article really offers offline; a missing resource is never shown as usable.
    static func abilities(_ r: ArticleResources) -> [ArticleAbility] {
        let text = r.text == .available
        let audio = r.audio == .available
        let timing = r.timing == .available
        var out: [ArticleAbility] = []
        out.append(ArticleAbility(title: "看英文原文", available: text, note: text ? "正文在 iPad 上。" : "缺正文。"))
        out.append(ArticleAbility(title: "听原声", available: audio, note: audio ? "原音在 iPad 上。" : "缺原音。"))
        out.append(ArticleAbility(title: "逐词高亮、点句播放", available: audio && timing,
                                  note: audio && timing ? "有时间轴。" : "缺原音或时间轴。"))
        out.append(ArticleAbility(title: "跟读（四种模式和 A/B 对照）", available: text && audio && timing,
                                  note: text && audio && timing ? "按句子时间切分原音。" : "要正文、原音和时间轴都在。"))
        out.append(ArticleAbility(title: "点词看单词卡", available: text && r.senses == .available,
                                  note: r.senses == .available ? "词库在 iPad 上。" : "缺词义（词库）。"))
        out.append(ArticleAbility(title: "单词原声", available: r.wordAudio == .available,
                                  note: r.wordAudio == .available ? "从原音里切出单词。" : "没有单词原声，用合成音读，并标着“合成音”。"))
        out.append(ArticleAbility(title: "发音标注", available: r.annotations == .available,
                                  note: r.annotations == .available ? "跟读页可以打开七层标注。" : "这篇没有发音标注。"))
        out.append(ArticleAbility(title: "理解题", available: r.quiz == .available,
                                  note: r.quiz == .available ? "可以做理解题、隔日回忆和新材料复测。" : "这篇没有理解题。"))
        return out
    }
}
