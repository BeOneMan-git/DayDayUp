import SwiftUI

/// Right-hand inspector (landscape) or bottom sheet (narrow window):
/// word card, sentence analysis, and the article's word list.
struct InspectorPanel: View {
    @Environment(ReadingSession.self) private var session

    var body: some View {
        VStack(spacing: 0) {
            Picker("面板", selection: Bindable(session).inspectorTab) {
                ForEach(InspectorTab.allCases, id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(12)
            Divider()
            ScrollView {
                Group {
                    switch session.inspectorTab {
                    case .card: WordCardView()
                    case .sentence: SentencePanel()
                    case .list: VocabListPanel()
                    }
                }
                .padding(16)
            }
        }
    }
}

// MARK: - Word card

struct WordCardView: View {
    @Environment(ReadingSession.self) private var session
    @Environment(PackStore.self) private var packs
    @Environment(UserStore.self) private var user
    @Environment(VocabStore.self) private var vocab
    @Environment(PlaybackEngine.self) private var engine
    @State private var senseTarget: SenseTarget?

    var body: some View {
        if let i = session.selectedTok, let info = session.info(i) {
            content(info)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("点任意单词").font(.headline)
                Text("这里会显示释义。带下划线的是雅思 5 级以上的词，有详解卡。点段落前的 ▷，从这一段开始播放。")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func content(_ info: TokInfo) -> some View {
        let _ = session.marksVersion
        let t = info.tok
        let entry = packs.entry(t.k)
        let card = entry?.card
        let band = session.band(ofToken: t.i)
        let lemma = displayLemma(t.k)
        let isNameOrNumber = entry?.pn == true || entry?.num == true || t.k == nil
        let ctx = session.context(card, sid: info.sid)
        let accent = user.settings.accent

        VStack(alignment: .leading, spacing: 14) {
            // Headword and actions
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card != nil && !lemma.isEmpty ? lemma : t.w)
                        .font(Font.system(.largeTitle, design: .serif).weight(.semibold))
                    if card != nil, !lemma.isEmpty, lemma.lowercased() != t.w.lowercased() {
                        Text("文中词形：\(t.w)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let key = t.k, entry?.num != true {
                    wordActions(key, info: info)
                }
            }

            // Badges
            FlowLayout(spacing: 6, lineSpacing: 6) {
                if band > 0 { Badge(text: "\(band) 级", color: Theme.level(band)) }
                if band > 0, let cefr = entry?.cefr { Badge(text: "CEFR \(cefr)") }
                if band == 8 && entry?.cefr == nil { Badge(text: "词表外") }
                if let awl = entry?.awl { Badge(text: "AWL 第 \(awl) 组") }
                if band == 0 && !isNameOrNumber { Badge(text: "基础词") }
                if entry?.pn == true { Badge(text: "专有名词") }
                if entry?.num == true || t.k == nil { Badge(text: "数字") }
                if ctx?.t != nil || session.isTrap(t.i) { Badge(text: "熟词僻义", color: Theme.warn, outlined: true) }
                if let pos = card?.pos { Badge(text: pos) }
            }

            // Pronunciation
            FlowLayout(spacing: 8, lineSpacing: 8) {
                if let ipa = card?.ipa {
                    if let br = ipa.br {
                        pronButton("英", br, ai: ipa.ai == true) { Speaker.shared.speak(lemma, language: "en-GB") }
                    }
                    if let am = ipa.am {
                        pronButton("美", am, ai: ipa.ai == true) { Speaker.shared.speak(lemma, language: "en-US") }
                    }
                } else if let ph = entry?.ph, !isNameOrNumber {
                    pronButton("音标", "/\(ph)/", ai: false) { Speaker.shared.speak(t.w, language: accent) }
                } else if entry?.num != true && t.k != nil {
                    pronButton("朗读", nil, ai: false) { Speaker.shared.speak(t.w, language: accent) }
                }
                if let s = t.s {
                    pronButton("原声", "本文读音", ai: false) { engine.playClip(from: s, to: t.e ?? s + 0.5) }
                }
            }

            if let ctx, let m = ctx.m, !m.isEmpty {
                NoteBox(label: "本文语境义") {
                    Text(m).font(.body.weight(.medium))
                }
            }

            if entry?.pn == true, !hasEntityNote(info), let ent = session.entity(for: t.w) {
                NoteBox(label: "专有名词", tint: Theme.level6) {
                    Text("\(ent.text)　\(ent.zh ?? "")").font(.body.weight(.medium))
                    if let bg = ent.bg { Text(bg).font(.callout).foregroundStyle(.secondary) }
                }
            }

            AnnotationNotes(sid: info.sid, tokenIndex: t.i)

            if let card {
                LexCardSections(card: card, trapNote: ctx?.t, accent: accent)
            } else if let zh = entry?.zh, entry?.num != true {
                CardSection(title: "词典释义") {
                    Text(zh).textSelection(.enabled)
                }
            }

            SentenceBox(sid: info.sid, markToken: t.i)
        }
        .sheet(item: $senseTarget) { target in
            NavigationStack {
                SaveSenseSheet(target: target)
            }
        }
    }

    private func displayLemma(_ key: String?) -> String {
        guard var k = key else { return "" }
        if k.hasPrefix("#") { k.removeFirst() }
        return k
    }

    private func hasEntityNote(_ info: TokInfo) -> Bool {
        let anns = session.sentence(info.sid)?.ann ?? []
        return anns.contains { $0.t == "e" && $0.covers(info.tok.i) }
    }

    private func wordActions(_ key: String, info: TokInfo) -> some View {
        let saved = vocab.items(forKey: key)
        return VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    if let ref = session.ref {
                        senseTarget = SenseTarget(ref: ref, sid: info.sid, tokIndex: info.tok.i, key: key, word: info.tok.w)
                    }
                } label: {
                    Label(saved.isEmpty ? "收藏这个义项" : "已收藏 \(saved.count) 个义项",
                          systemImage: saved.isEmpty ? "bookmark" : "bookmark.fill")
                }
                .buttonStyle(.bordered)
                .tint(saved.isEmpty ? Color.secondary : Theme.level5)
                Button {
                    session.toggleKnown(key)
                } label: {
                    Label("认识", systemImage: user.isKnown(key) ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .buttonStyle(.bordered)
                .tint(user.isKnown(key) ? Color.green : Color.secondary)
                .help("只作标记，不排复习")
            }
            Button {
                session.startChunkSelection(from: info.tok.i)
            } label: {
                Label("从这个词开始选词群", systemImage: "text.badge.plus")
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .controlSize(.regular)
    }

    private func pronButton(_ label: String, _ text: String?, ai: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if let text { Text(text).font(.callout) }
                if ai { Text("补注").font(.caption2).foregroundStyle(Theme.warn) }
                Image(systemName: "speaker.wave.2").font(.caption)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 36)
            .background(Theme.chip, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) \(text ?? "")")
    }
}

/// Phrase / entity / number / rare-sense notes of the sentence that cover one token.
struct AnnotationNotes: View {
    @Environment(ReadingSession.self) private var session
    @Environment(VocabStore.self) private var vocab
    @State private var chunkTarget: ChunkTarget?
    let sid: Int
    let tokenIndex: Int

    var body: some View {
        let anns = (session.sentence(sid)?.ann ?? []).filter { $0.covers(tokenIndex) }
        VStack(alignment: .leading, spacing: 14) {
        ForEach(Array(anns.enumerated()), id: \.offset) { _, a in
            switch a.t {
            case "p":
                NoteBox(label: "所在短语" + ((a.type ?? "").isEmpty ? "" : " · \(a.type ?? "")"), tint: Theme.level5) {
                    Text("\(a.text ?? "")　\(a.zh ?? "")").font(.body.weight(.medium))
                    if let note = a.note { Text(note).font(.callout).foregroundStyle(.secondary) }
                    if a.r.count == 2, let ref = session.ref {
                        let saved = vocab.chunk(text: a.text ?? "") != nil
                        Button {
                            chunkTarget = ChunkTarget(ref: ref, sid: sid, first: a.r[0], last: a.r[1],
                                                      gloss: a.zh, note: a.note, origin: .annotation)
                        } label: {
                            Label(saved ? "已在词群库（再加一句语境）" : "收藏为词群",
                                  systemImage: saved ? "checkmark.circle" : "plus.circle")
                        }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                    }
                }
            case "e":
                NoteBox(label: "专有名词", tint: Theme.level6) {
                    Text("\(a.text ?? "")　\(a.zh ?? "")").font(.body.weight(.medium))
                    if let bg = a.bg { Text(bg).font(.callout).foregroundStyle(.secondary) }
                }
            case "n":
                NoteBox(label: "数字读法", tint: Theme.level7) {
                    Text("\(a.text ?? "")　\(a.zh ?? "")").font(.body.weight(.medium))
                    if let read = a.read {
                        Text("读作：\(read)").font(Font.system(.callout, design: .serif))
                    }
                }
            case "s":
                NoteBox(label: "熟词僻义", tint: Theme.warn) {
                    Text("\(a.text ?? "")　本句：\(a.m ?? "")").font(.body.weight(.medium))
                    Text("常见义：\(a.common ?? "")" + ((a.note ?? "").isEmpty ? "" : "。\(a.note ?? "")"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            default:
                EmptyView()
            }
        }
        }
        .sheet(item: $chunkTarget) { target in
            NavigationStack {
                SaveChunkSheet(target: target)
            }
        }
    }
}

/// The sentence around a word, with its translation and play / loop buttons.
struct SentenceBox: View {
    @Environment(ReadingSession.self) private var session
    let sid: Int
    var markToken: Int? = nil

    var body: some View {
        if let s = session.sentence(sid) {
            CardSection(title: "所在句") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(sentenceText(s))
                        .font(Font.system(.body, design: .serif))
                    if let zh = s.zh {
                        Text(zh).font(.callout).foregroundStyle(.secondary)
                    }
                    SentenceButtons(sid: sid, showAnalysis: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func sentenceText(_ s: Sent) -> AttributedString {
        var out = AttributedString()
        let last = s.toks.count - 1
        for (k, t) in s.toks.enumerated() {
            out += AttributedString(t.a ?? "")
            var w = AttributedString(t.w)
            if t.i == markToken {
                w.backgroundColor = Theme.currentWord
            }
            out += w
            out += AttributedString(t.z ?? "")
            if k < last {
                switch t.j {
                case "-": out += AttributedString("-")
                case "_": break
                default: out += AttributedString(" ")
                }
            }
        }
        return out
    }
}

struct SentenceButtons: View {
    @Environment(ReadingSession.self) private var session
    @Environment(Router.self) private var router
    let sid: Int
    var showAnalysis = false

    var body: some View {
        let timed = session.sentence(sid)?.isTimed ?? false
        HStack(spacing: 8) {
            if timed {
                Button {
                    session.playSentence(sid)
                } label: {
                    Label("从本句播放", systemImage: "play.fill")
                }
                Button {
                    session.loopSentence(sid)
                } label: {
                    Label("循环本句", systemImage: "repeat.1")
                }
                Button {
                    if let ref = session.ref {
                        session.engine.pause()
                        router.openShadow(ref, sid: sid)
                    }
                } label: {
                    Label("跟读", systemImage: "waveform")
                }
            }
            if showAnalysis {
                Button {
                    session.showSentence(sid)
                } label: {
                    Label("句子解析", systemImage: "text.magnifyingglass")
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

// MARK: - Sentence analysis

struct SentencePanel: View {
    @Environment(ReadingSession.self) private var session
    @Environment(PackStore.self) private var packs
    @Environment(PracticeStore.self) private var practice
    @State private var reportSid: Int?

    var body: some View {
        let sid = session.sentenceInPanel ?? session.curSent ?? session.order.first?.id
        if let sid, let s = session.sentence(sid) {
            content(s)
        } else {
            Text("还没有句子。").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func content(_ s: Sent) -> some View {
        let _ = session.marksVersion
        VStack(alignment: .leading, spacing: 16) {
            if let start = s.s, let end = s.e {
                Badge(text: "第 \(session.position(of: s.id)) / \(session.sentenceCount) 句 · \(formatTime(start))–\(formatTime(end))")
            } else {
                Badge(text: "小标题（音频未朗读）")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(ReadingSession.plainText(s))
                    .font(Font.system(.title3, design: .serif))
                    .textSelection(.enabled)
                if let zh = s.zh {
                    Text(zh).foregroundStyle(.secondary).textSelection(.enabled)
                }
                SentenceButtons(sid: s.id)
                Button {
                    reportSid = s.id
                } label: {
                    Label("报错", systemImage: "exclamationmark.bubble")
                }
                .buttonStyle(.borderless)
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            .sheet(isPresented: Binding(get: { reportSid != nil }, set: { if !$0 { reportSid = nil } })) {
                if let rs = reportSid, let sent = session.sentence(rs), let ref = session.ref {
                    ReportSheet(articleKey: ref.key, sid: rs, sentence: ReadingSession.plainText(sent)) {
                        session.showToast("已记下，导出诊断日志时会一起带上")
                    }
                    .environment(practice)
                }
            }

            if let allu = s.allu, !allu.isEmpty {
                CardSection(title: "标题典故") { Text(allu) }
            }
            if let gram = s.gram, !gram.isEmpty {
                CardSection(title: "长难句拆解") {
                    ForEach(Array(grammarLines(gram).enumerated()), id: \.offset) { _, line in
                        if let head = line.head {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(head).font(.callout.weight(.semibold))
                                Text(line.body).font(.callout)
                            }
                        } else {
                            Text(line.body).font(.callout)
                        }
                    }
                }
            }
            annotationGroup(s, "p", "短语与搭配")
            annotationGroup(s, "s", "熟词僻义")
            annotationGroup(s, "e", "专有名词")
            annotationGroup(s, "n", "数字读法")

            let words = levelWords(s)
            if !words.isEmpty {
                CardSection(title: "本句 5 级+ 词") {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(words, id: \.key) { w in
                            Button {
                                session.reveal(w.tokIndex)
                            } label: {
                                HStack(spacing: 6) {
                                    Circle().fill(Theme.level(w.band)).frame(width: 8, height: 8)
                                    Text(w.key).bold()
                                    Text(w.meaning).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .font(.callout)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func annotationGroup(_ s: Sent, _ kind: String, _ title: String) -> some View {
        let items = (s.ann ?? []).filter { $0.t == kind }
        if !items.isEmpty {
            CardSection(title: title) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, a in
                    Button {
                        if a.r.count == 2 { session.reveal(a.r[0]) }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(a.text ?? "")　\(a.zh ?? a.m ?? "")").font(.body.weight(.medium))
                            if kind == "n", let read = a.read {
                                Text("读作：\(read)").font(Font.system(.callout, design: .serif))
                            }
                            if let note = a.note, !note.isEmpty {
                                Text(note).font(.callout).foregroundStyle(.secondary)
                            }
                            if let bg = a.bg, !bg.isEmpty {
                                Text(bg).font(.callout).foregroundStyle(.secondary)
                            }
                            if kind == "s", let common = a.common {
                                Text("常见义：\(common)").font(.callout).foregroundStyle(.secondary)
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

    private struct GrammarLine {
        let head: String?
        let body: String
    }

    /// "主干：…｜从句：…" → labelled lines.
    private func grammarLines(_ text: String) -> [GrammarLine] {
        text.split(separator: "｜").map { part in
            let line = String(part)
            if let colon = line.firstIndex(where: { $0 == "：" || $0 == ":" }) {
                let head = String(line[line.startIndex..<colon])
                if !head.isEmpty && head.count <= 6 {
                    return GrammarLine(head: head + "：", body: String(line[line.index(after: colon)...]))
                }
            }
            return GrammarLine(head: nil, body: line)
        }
    }

    private struct LevelWord {
        let key: String
        let band: Int
        let tokIndex: Int
        let meaning: String
    }

    private func levelWords(_ s: Sent) -> [LevelWord] {
        var seen = Set<String>()
        var out: [LevelWord] = []
        for t in s.toks {
            let band = session.band(ofToken: t.i)
            guard band > 0, let k = t.k, !seen.contains(k) else { continue }
            seen.insert(k)
            let card = packs.entry(k)?.card
            let m = session.context(card, sid: s.id)?.m ?? card?.senses?.first?.zh ?? ""
            out.append(LevelWord(key: k, band: band, tokIndex: t.i, meaning: String(m.prefix(18))))
        }
        return out
    }
}

// MARK: - Word list of the article

struct VocabListPanel: View {
    @Environment(ReadingSession.self) private var session
    @Environment(PackStore.self) private var packs
    @Environment(UserStore.self) private var user
    @State private var filter = "all"
    @State private var byLevel = false

    private let filters: [(String, String)] = [
        ("all", "全部"), ("5", "5级"), ("6", "6级"), ("7", "7级"), ("8", "8级"), ("star", "已收藏"), ("trap", "易错义"),
    ]

    var body: some View {
        let _ = session.marksVersion
        let rows = session.vocabRows()
        let counts = count(rows)
        let shown = sorted(rows.filter { matches($0) })

        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(filters, id: \.0) { key, label in
                        Button {
                            filter = key
                        } label: {
                            Text("\(label) \(counts[key] ?? 0)")
                                .font(.callout)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(filter == key ? Theme.accent.opacity(0.18) : Theme.chip,
                                            in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Text("本文 5 级+ 词 \(rows.count) 个 · 已认识 \(counts["known"] ?? 0)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(byLevel ? "按等级" : "按出现顺序") { byLevel.toggle() }
                    .font(.footnote)
            }
            if shown.isEmpty {
                Text("这个筛选下没有词。").foregroundStyle(.secondary)
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(shown) { row in
                    Button {
                        session.reveal(row.tokIndex)
                    } label: {
                        HStack(spacing: 10) {
                            Circle().fill(Theme.level(row.band)).frame(width: 9, height: 9)
                            Text(row.key + (session.isSaved(row.key) ? " ★" : ""))
                                .font(.body.weight(.semibold))
                            Text(meaning(row))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)
                        .opacity(user.isKnown(row.key) ? 0.45 : 1)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
    }

    private func isTrap(_ row: VocabRow) -> Bool {
        session.context(packs.entry(row.key)?.card, sid: row.sid)?.t != nil
    }

    private func matches(_ row: VocabRow) -> Bool {
        switch filter {
        case "all": return true
        case "star": return session.isSaved(row.key)
        case "trap": return isTrap(row)
        default: return String(row.band) == filter
        }
    }

    private func sorted(_ rows: [VocabRow]) -> [VocabRow] {
        byLevel ? rows.sorted { ($0.band, $1.tokIndex) > ($1.band, $0.tokIndex) } : rows
    }

    private func count(_ rows: [VocabRow]) -> [String: Int] {
        var c: [String: Int] = ["all": rows.count]
        for r in rows {
            c[String(r.band), default: 0] += 1
            if session.isSaved(r.key) { c["star", default: 0] += 1 }
            if user.isKnown(r.key) { c["known", default: 0] += 1 }
            if isTrap(r) { c["trap", default: 0] += 1 }
        }
        return c
    }

    private func meaning(_ row: VocabRow) -> String {
        let card = packs.entry(row.key)?.card
        return session.context(card, sid: row.sid)?.m ?? card?.senses?.first?.zh ?? ""
    }
}
