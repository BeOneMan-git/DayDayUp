import SwiftUI
import Foundation

/// One sentence in 跟读 with its pronunciation marks (SHD-A01…A07, SHD-AS, ACC-22).
///
/// Only layers in `layers` are drawn, and only marks the learner has not hidden:
/// 意群 " / " after the group, 重音 bold with a small dot above, 连读 "‿" to the next word,
/// 弱读 the weak form under the word, 省音 the sound in brackets inside the word ("nex(t)", never struck
/// through), 同化 a small tag under the words, 语调 the arrow after the group.
/// Marks that nobody has checked (待核对) are drawn lighter, with a hollow dot or a dashed frame; marks in
/// dispute carry a "?"; a legend line under the sentence counts the marks per status, so the status never
/// rests on colour alone. Tap or long-press a marked word to read what its marks mean and to check,
/// dispute, hide, note or report them.
struct AnnotatedSentenceView: View {
    let ref: ArticleRef
    let sentence: Sent
    let layers: Set<AnnLayer>
    let fontSize: CGFloat
    let mode: ShadowMode
    /// Shows "这篇还没有发音标注" under this sentence. A segment of several sentences shows it once.
    let showsArticleNote: Bool

    @Environment(PackStore.self) private var packs
    @Environment(AnnotationStore.self) private var annotations
    @State private var openToken: Int?          // position in sentence.toks whose marks are open
    @State private var showHidden = false

    init(ref: ArticleRef, sentence: Sent, layers: Set<AnnLayer>, fontSize: CGFloat, mode: ShadowMode,
         showsArticleNote: Bool = true) {
        self.ref = ref
        self.sentence = sentence
        self.layers = layers
        self.fontSize = fontSize
        self.mode = mode
        self.showsArticleNote = showsArticleNote
    }

    var body: some View {
        let file = packs.annotationFile(ref)
        let resolved = annotations.resolved(file: file, ref: ref, sentence: sentence)
        let inLayers: [EffectiveAnnotation] = resolved.stale ? [] : resolved.items.filter { layers.contains($0.ann.layer) }
        let marks = PronSentenceMarks(toks: sentence.toks, items: inLayers)
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: wordGap, lineSpacing: lineGap) {
                ForEach(marks.runs) { run in
                    runView(run, marks: marks)
                }
            }
            notes(hasFile: file != nil, stale: resolved.stale, total: resolved.items.count,
                  inLayers: inLayers, marks: marks)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Sizes

    private var wordGap: CGFloat { max(5, (fontSize * 0.28).rounded()) }
    private var lineGap: CGFloat { max(4, (fontSize * 0.2).rounded()) }
    private var topHeight: CGFloat { max(8, (fontSize * 0.36).rounded()) }
    private var bottomHeight: CGFloat { max(14, (fontSize * 0.62).rounded()) }
    private var markSize: CGFloat { max(11, (fontSize * 0.5).rounded()) }
    private var dotSize: CGFloat { max(5, (fontSize * 0.24).rounded()) }

    private func wordFont(bold: Bool) -> Font {
        let weight: Font.Weight = bold ? .bold : .regular
        return Font.system(size: fontSize, weight: weight, design: .serif)
    }

    // MARK: Words

    /// Words that belong together on one line: hyphenated or joined words, and a short 同化 span.
    private func runView(_ run: PronTokenRun, marks: PronSentenceMarks) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(run.positions, id: \.self) { p in
                    cell(p, marks: marks)
                    if p != run.positions.last {
                        joiner(after: p, marks: marks)
                    }
                }
            }
            if !run.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(run.tags) { tag in
                        tagView(tag)
                    }
                }
                .accessibilityHidden(true)      // the words' own labels say "同化"
            }
        }
    }

    @ViewBuilder
    private func joiner(after p: Int, marks: PronSentenceMarks) -> some View {
        let j = sentence.toks.indices.contains(p) ? sentence.toks[p].j : nil
        if j == "-" {
            Text("-")
                .font(wordFont(bold: false))
                .padding(.top, marks.needTop ? topHeight : 0)
                .accessibilityHidden(true)
        } else if j == "_" {
            EmptyView()
        } else {
            Color.clear
                .frame(width: wordGap, height: 1)
                .accessibilityHidden(true)
        }
    }

    /// One token: its word row, the room above for the stress dot and below for the weak form.
    /// A marked word is a tap target of at least 44 × 44 pt.
    private func cell(_ p: Int, marks: PronSentenceMarks) -> some View {
        let t = sentence.toks[p]
        let m = marks.cells[p]
        return VStack(spacing: 0) {
            if marks.needTop {
                Color.clear.frame(width: 1, height: topHeight)
            }
            wordRow(t, m)
            if marks.needBottom {
                weakRow(m.weak)
                    .frame(minHeight: bottomHeight, alignment: .top)
            }
        }
        .padding(.horizontal, m.tappable ? 2 : 0)
        .frame(minWidth: m.tappable ? 44 : nil, minHeight: 44, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(openToken == p ? Theme.selectedWord : Color.clear)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            open(p, m)
        }
        // SYS-P02: a finger that moves more than 8 pt is a scroll, never a long press.
        .onLongPressGesture(minimumDuration: 0.4, maximumDistance: 8, perform: {
            open(p, m)
        })
        .popover(isPresented: popoverBinding(p)) {
            PronAnnotationPanel(ref: ref, sentence: sentence, word: t.w, ids: m.shown + m.hidden)
                .environment(packs)
                .environment(annotations)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(marks.spokenLabel(p, word: t.w))
        .accessibilityHint(m.tappable ? "点两下，看这个词的标注" : "")
        .accessibilityAddTraits(m.tappable ? AccessibilityTraits.isButton : AccessibilityTraits())
        .accessibilityAction {
            open(p, m)
        }
    }

    private func wordRow(_ t: Tok, _ m: PronTokenMarks) -> some View {
        let bold = m.stress != nil || t.B == 1
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            if let a = t.a, !a.isEmpty {
                Text(a)
            }
            wordText(t.w, elision: m.elision, bold: bold)
                .overlay(alignment: .top) {
                    if let s = m.stress {
                        stressDot(s)
                            .offset(y: -(topHeight + dotSize) / 2)
                    }
                }
            if let z = t.z, !z.isEmpty {
                Text(z)
            }
            if let link = m.link {
                markText("‿", link)
                    .font(.system(size: max(markSize, fontSize * 0.85)))
            }
            if let arrow = m.arrow {
                markText(" " + PronFormat.arrow(arrow.value), arrow)
                    .font(.system(size: max(markSize, fontSize * 0.8)))
            }
            if let slash = m.slash {
                markText(" /", slash)
                    .fontWeight(.ultraLight)
            }
        }
        .font(wordFont(bold: false))
        .italic(t.I == 1)
    }

    /// The word itself. 省音 puts the sound in brackets inside the word (nex(t)); nothing is struck through.
    @ViewBuilder
    private func wordText(_ word: String, elision: PronMark?, bold: Bool) -> some View {
        if let e = elision, let parts = PronFormat.elided(word, sound: e.value) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(parts.head)
                markText(PronFormat.bracketed(parts.sound, e.status), e, question: false)
                if !parts.tail.isEmpty {
                    Text(parts.tail)
                }
            }
            .font(wordFont(bold: bold))
        } else if let e = elision {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(word)
                markText(PronFormat.bracketed(PronFormat.cleanSound(e.value), e.status), e, question: false)
                    .font(.system(size: markSize))
            }
            .font(wordFont(bold: bold))
        } else {
            Text(word)
                .font(wordFont(bold: bold))
        }
    }

    @ViewBuilder
    private func weakRow(_ mark: PronMark?) -> some View {
        if let mark {
            markText(mark.value ?? "弱读", mark)
                .font(.system(size: markSize))
                .fixedSize()
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }

    @ViewBuilder
    private func stressDot(_ mark: PronMark) -> some View {
        let color = PronFormat.color(mark.status)
        HStack(spacing: 1) {
            if mark.status == .pending {
                Circle()
                    .strokeBorder(color, lineWidth: 1.2)
                    .frame(width: dotSize + 1, height: dotSize + 1)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: dotSize, height: dotSize)
            }
            if mark.status == .disputed {
                Text("?")
                    .font(.system(size: max(9, markSize * 0.8), weight: .bold))
                    .foregroundStyle(color)
            }
        }
        .opacity(PronFormat.opacity(mark.status))
        .fixedSize()
    }

    private func tagView(_ tag: PronSpanTag) -> some View {
        let color = PronFormat.color(tag.status)
        return Text(tag.status == .disputed ? tag.value + "?" : tag.value)
            .font(.system(size: markSize))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .overlay {
                Capsule()
                    .strokeBorder(color, style: StrokeStyle(lineWidth: 1, dash: tag.status == .pending ? [3, 2] : []))
            }
            .opacity(PronFormat.opacity(tag.status))
            .fixedSize()
    }

    /// A mark in its status style: 待核对 lighter, 有争议 with "?".
    private func markText(_ text: String, _ mark: PronMark, question: Bool = true) -> some View {
        Text(question && mark.status == .disputed ? text + "?" : text)
            .foregroundStyle(PronFormat.color(mark.status))
            .opacity(PronFormat.opacity(mark.status))
    }

    private func popoverBinding(_ p: Int) -> Binding<Bool> {
        Binding(get: { openToken == p }, set: { shown in
            if !shown && openToken == p { openToken = nil }
        })
    }

    private func open(_ p: Int, _ m: PronTokenMarks) {
        guard m.tappable else { return }
        openToken = p
    }

    // MARK: Notes under the sentence

    @ViewBuilder
    private func notes(hasFile: Bool, stale: Bool, total: Int, inLayers: [EffectiveAnnotation],
                       marks: PronSentenceMarks) -> some View {
        if !hasFile {
            if showsArticleNote {
                noteLine("这篇还没有发音标注", systemImage: "info.circle")
            }
        } else if stale {
            noteLine("这句的文字在内容包更新后变了，旧标注不再套用。", systemImage: "exclamationmark.triangle")
        } else if layers.isEmpty {
            noteLine("“\(mode.title)”的标注层都关着。", systemImage: "eye.slash")
        } else if total == 0 {
            noteLine("这句没有发音标注。", systemImage: "info.circle")
        } else if inLayers.isEmpty {
            noteLine("开着的标注层在这句没有标注。", systemImage: "info.circle")
        } else {
            if !marks.drawn.isEmpty {
                legend(marks.drawn)
            }
            hiddenSection(inLayers.filter { $0.hidden })
        }
    }

    private func noteLine(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// "标注：待核对 5（浅色）· 教学建议 2 …" for the marks drawn on this sentence.
    private func legend(_ drawn: [EffectiveAnnotation]) -> some View {
        let order: [AnnStatus] = [.pending, .suggestion, .verified, .disputed]
        var parts: [String] = []
        for status in order {
            let n = drawn.filter { $0.status == status }.count
            guard n > 0 else { continue }
            switch status {
            case .pending: parts.append("待核对 \(n)（浅色）")
            case .disputed: parts.append("有争议 \(n)（带 ?）")
            default: parts.append("\(status.title) \(n)")
            }
        }
        return Label("标注：" + parts.joined(separator: " · "), systemImage: "tag")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func hiddenSection(_ hidden: [EffectiveAnnotation]) -> some View {
        if !hidden.isEmpty {
            Button {
                showHidden.toggle()
            } label: {
                Label(showHidden ? "收起被隐藏的标注" : "显示被隐藏的 \(hidden.count) 条",
                      systemImage: showHidden ? "chevron.up" : "eye")
                    .font(.caption)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            if showHidden {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(hidden) { e in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(e.ann.layer.title) · \(PronFormat.span(e.ann, toks: sentence.toks))\(PronFormat.valueSuffix(e.ann.v))")
                                    .font(.callout)
                                Text(e.reports > 0 ? "\(e.status.title) · 已报错 \(e.reports) 次" : e.status.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Button("显示") {
                                annotations.setHidden(false, ref: ref, sentence: sentence, id: e.id)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .accessibilityLabel("显示这条\(e.ann.layer.title)标注")
                        }
                    }
                    if hidden.count > 1 {
                        Button("全部显示") {
                            for e in hidden {
                                annotations.setHidden(false, ref: ref, sentence: sentence, id: e.id)
                            }
                            showHidden = false
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.chip.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

// MARK: - The marks of one sentence

private struct PronMark: Equatable {
    var value: String?
    var status: AnnStatus
}

/// A 同化 tag drawn under its words.
private struct PronSpanTag: Identifiable {
    var id: String
    var value: String
    var status: AnnStatus
}

/// Consecutive tokens drawn as one unit (no line break inside).
private struct PronTokenRun: Identifiable {
    var id: Int
    var positions: [Int]
    var tags: [PronSpanTag] = []
}

/// What is drawn on one token, and which annotations a tap on it opens.
private struct PronTokenMarks {
    var stress: PronMark?
    var weak: PronMark?
    var elision: PronMark?
    var link: PronMark?
    var arrow: PronMark?
    var slash: PronMark?
    var assimilation: [PronMark] = []
    var assimilationSpan = false
    var shown: [String] = []      // visible annotations anchored here
    var hidden: [String] = []     // hidden annotations anchored here
    var tappable: Bool { !shown.isEmpty }
}

private struct PronSentenceMarks {
    var cells: [PronTokenMarks]
    var runs: [PronTokenRun]
    /// Visible annotations that found their words (the legend counts these).
    var drawn: [EffectiveAnnotation]
    var needTop: Bool
    var needBottom: Bool

    init(toks: [Tok], items: [EffectiveAnnotation]) {
        var position: [Int: Int] = [:]
        for (p, t) in toks.enumerated() where position[t.i] == nil {
            position[t.i] = p
        }
        var cells = Array(repeating: PronTokenMarks(), count: toks.count)
        var drawn: [EffectiveAnnotation] = []
        var spans: [(lo: Int, hi: Int, tag: PronSpanTag)] = []
        for e in items {
            let a = e.ann
            let at = PronSentenceMarks.anchors(a, toks: toks, position: position)
            guard let first = at.first, let last = at.last else { continue }
            if e.hidden {
                for p in at { cells[p].hidden.append(e.id) }
                continue
            }
            drawn.append(e)
            let mark = PronMark(value: a.v, status: e.status)
            for p in at { cells[p].shown.append(e.id) }
            switch a.layer {
            case .thought:
                cells[last].slash = mark
            case .intonation:
                cells[last].arrow = mark
            case .linking:
                cells[first].link = mark
            case .stress:
                for p in at { cells[p].stress = mark }
            case .weak:
                cells[first].weak = mark
            case .elision:
                cells[first].elision = mark
            case .assimilation:
                for p in at {
                    cells[p].assimilation.append(mark)
                    if at.count > 1 { cells[p].assimilationSpan = true }
                }
                let tag = PronSpanTag(id: e.id, value: PronFormat.cleanValue(a.v) ?? "同化", status: e.status)
                spans.append((lo: first, hi: last, tag: tag))
            }
        }

        // Runs: a hyphen or "no space" joiner keeps words together, and so does a short 同化 span.
        var runs: [PronTokenRun] = []
        for p in toks.indices {
            var joins = false
            if p > 0 {
                let j: String = toks[p - 1].j ?? ""
                let noSpace: Bool = j == "-" || j == "_"
                let inSpan: Bool = spans.contains(where: { span in
                    span.lo < p && p <= span.hi && span.hi - span.lo <= 3
                })
                joins = noSpace || inSpan
            }
            if joins, !runs.isEmpty {
                runs[runs.count - 1].positions.append(p)
            } else {
                runs.append(PronTokenRun(id: p, positions: [p]))
            }
        }
        for span in spans {
            if let r = runs.firstIndex(where: { $0.positions.contains(span.lo) }) {
                runs[r].tags.append(span.tag)
            }
        }

        self.cells = cells
        self.runs = runs
        self.drawn = drawn
        self.needTop = drawn.contains { $0.ann.layer == .stress }
        self.needBottom = drawn.contains { $0.ann.layer == .weak }
    }

    /// Positions (in toks) where an annotation is drawn and can be tapped.
    static func anchors(_ a: PronAnnotation, toks: [Tok], position: [Int: Int]) -> [Int] {
        switch a.layer {
        case .thought, .intonation:
            return position[a.last].map { [$0] } ?? []
        case .linking:
            return position[a.first].map { [$0] } ?? []
        case .stress, .weak, .elision, .assimilation:
            let lo = min(a.first, a.last)
            let hi = max(a.first, a.last)
            return toks.indices.filter { toks[$0].i >= lo && toks[$0].i <= hi }
        }
    }

    /// VoiceOver label: the word, then its marks in words, e.g. "want，重读，连读到下一个词".
    func spokenLabel(_ p: Int, word: String) -> String {
        guard cells.indices.contains(p) else { return word }
        let c = cells[p]
        var parts: [String] = [word]
        if let m = c.stress {
            parts.append("重读\(PronFormat.statusSuffix(m.status))")
        }
        if let m = c.weak {
            parts.append("弱读\(PronFormat.valueSuffix(m.value))\(PronFormat.statusSuffix(m.status))")
        }
        if let m = c.elision {
            let sound = PronFormat.cleanSound(m.value)
            let what = sound.isEmpty ? "有个音" : "\(sound) 音"
            parts.append("\(what)可能省掉\(PronFormat.statusSuffix(m.status))")
        }
        for m in c.assimilation {
            let what = c.assimilationSpan ? "和相邻的词同化" : "同化"
            parts.append("\(what)\(PronFormat.valueSuffix(m.value))\(PronFormat.statusSuffix(m.status))")
        }
        if let m = c.link {
            parts.append("连读到下一个词\(PronFormat.statusSuffix(m.status))")
        }
        if let m = c.arrow {
            parts.append("语调\(PronFormat.intonationWords(m.value))\(PronFormat.statusSuffix(m.status))")
        }
        if let m = c.slash {
            parts.append("意群在这里结束\(PronFormat.statusSuffix(m.status))")
        }
        return parts.joined(separator: "，")
    }
}

// MARK: - Wording and styles

private enum PronFormat {
    static func color(_ status: AnnStatus) -> Color {
        switch status {
        case .pending: return .secondary
        case .suggestion: return Theme.accent
        case .verified: return Theme.level5
        case .disputed: return Theme.warn
        }
    }

    static func opacity(_ status: AnnStatus) -> Double {
        status == .pending ? 0.72 : 1
    }

    static func statusSuffix(_ status: AnnStatus) -> String {
        switch status {
        case .pending: return "（待核对）"
        case .disputed: return "（有争议）"
        case .verified: return "（原声已核对）"
        case .suggestion: return ""
        }
    }

    static func statusMeaning(_ status: AnnStatus) -> String {
        switch status {
        case .pending: return "待核对：机器按规则生成，还没人对着原声核对。"
        case .suggestion: return "教学建议：一般的读法建议，不代表主播一定这样读。"
        case .verified: return "原声已核对：对着原声听过，确认是这样。"
        case .disputed: return "有争议：可能有别的合理读法。"
        }
    }

    static func sourceTitle(_ src: String?) -> String {
        let s = (src ?? "").trimmingCharacters(in: .whitespaces)
        switch s.lowercased() {
        case "rule": return "规则"
        case "dict": return "词典"
        case "audio": return "原声"
        case "": return "未注明"
        default: return s
        }
    }

    static func cleanValue(_ value: String?) -> String? {
        let v = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    static func valueSuffix(_ value: String?) -> String {
        cleanValue(value).map { " \($0)" } ?? ""
    }

    /// The elided sound without slashes or brackets: "/t/" → "t".
    static func cleanSound(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: CharacterSet(charactersIn: " /()[]"))
    }

    static func arrow(_ value: String?) -> String {
        cleanValue(value) ?? "↘"
    }

    /// "(t)" for an elided sound; "(t?)" when the mark is in dispute.
    static func bracketed(_ sound: String, _ status: AnnStatus) -> String {
        let question = status == .disputed ? "?" : ""
        return "(\(sound)\(question))"
    }

    static func intonationWords(_ value: String?) -> String {
        let v = (value ?? "").trimmingCharacters(in: .whitespaces)
        switch v {
        case "↘": return "下降"
        case "↗": return "上升"
        case "↘↗": return "降升"
        case "↗↘": return "升降"
        case "→": return "平"
        default: return v
        }
    }

    /// Splits "next" with sound "t" into ("nex", "t", ""). The sound must be inside the word, not its start.
    static func elided(_ word: String, sound: String?) -> (head: String, sound: String, tail: String)? {
        let s = cleanSound(sound)
        guard !s.isEmpty, word.count > s.count else { return nil }
        if let r = word.range(of: s, options: [.caseInsensitive, .backwards, .anchored]), r.lowerBound > word.startIndex {
            return (head: String(word[..<r.lowerBound]), sound: String(word[r]), tail: "")
        }
        if let r = word.range(of: s, options: [.caseInsensitive, .backwards]), r.lowerBound > word.startIndex {
            return (head: String(word[..<r.lowerBound]), sound: String(word[r]), tail: String(word[r.upperBound...]))
        }
        return nil
    }

    /// The words an annotation covers, as printed. 连读 shows the two words joined: "want‿to".
    static func span(_ a: PronAnnotation, toks: [Tok]) -> String {
        if a.layer == .linking, let p = toks.firstIndex(where: { $0.i == a.first }), p + 1 < toks.count {
            return toks[p].w + "‿" + toks[p + 1].w
        }
        let text = SentenceText.span(toks, first: min(a.first, a.last), last: max(a.first, a.last))
        return text.isEmpty ? "（找不到对应的词）" : text
    }

    /// One line on what the mark says, e.g. "弱读：to → /tə/".
    static func valueLine(_ a: PronAnnotation, toks: [Tok]) -> String {
        let words = span(a, toks: toks)
        let v = cleanValue(a.v)
        switch a.layer {
        case .thought:
            return "意群：\(words) /"
        case .stress:
            return v.map { "重读：\(words)，词典重音 \($0)" } ?? "重读：\(words)"
        case .linking:
            return "连读：\(words)"
        case .weak:
            return v.map { "弱读：\(words) → \($0)" } ?? "弱读：\(words)"
        case .elision:
            let sound = cleanSound(a.v)
            return sound.isEmpty ? "省音：\(words)" : "省音：\(words)，快读时 \(sound) 可能省掉"
        case .assimilation:
            return v.map { "同化：\(words)，\($0)" } ?? "同化：\(words)"
        case .intonation:
            return v.map { "语调：\(words) \($0)（\(intonationWords($0))）" } ?? "语调：\(words)"
        }
    }
}

// MARK: - Detail popover

private enum PronPanelPage: Equatable {
    case list
    case note(String)
    case report(String)
}

/// Everything about the annotations on one word, with the learner's actions (SHD-AS).
private struct PronAnnotationPanel: View {
    let ref: ArticleRef
    let sentence: Sent
    let word: String
    let ids: [String]

    @Environment(PackStore.self) private var packs
    @Environment(AnnotationStore.self) private var annotations
    @Environment(\.dismiss) private var dismiss
    @State private var page: PronPanelPage = .list
    @State private var draft = ""
    @State private var reportKind = "标错了"
    @State private var reportNote = ""
    @State private var notice: String?

    static let reportKinds = ["标错了", "位置不对", "读法不对", "其他"]

    var body: some View {
        let all = annotations.resolved(file: packs.annotationFile(ref), ref: ref, sentence: sentence).items
        let items = ids.compactMap { id in all.first(where: { $0.id == id }) }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let notice {
                    Label(notice, systemImage: "checkmark.circle")
                        .font(.callout)
                }
                switch page {
                case .list:
                    if items.isEmpty {
                        Text("这里没有可显示的标注。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(items) { item in
                        card(item)
                    }
                case .note(let id):
                    if let item = items.first(where: { $0.id == id }) {
                        noteEditor(item)
                    }
                case .report(let id):
                    if let item = items.first(where: { $0.id == id }) {
                        reportEditor(item)
                    }
                }
            }
            .padding(18)
        }
        .frame(minWidth: 320, idealWidth: 400, maxWidth: 480, minHeight: 280, idealHeight: 500, maxHeight: 700)
        .presentationDetents([.medium, .large])
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(word)
                .font(Font.system(.title3, design: .serif).weight(.semibold))
            Text("的发音标注")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button {
                dismiss()
            } label: {
                Text("完成")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
    }

    private func card(_ e: EffectiveAnnotation) -> some View {
        let a = e.ann
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(a.layer.title)
                    .font(.headline)
                Text(a.layer.code)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Badge(text: e.status.title, color: e.status == .pending ? nil : PronFormat.color(e.status),
                      outlined: e.status == .pending)
                if e.hidden {
                    Badge(text: "已隐藏", outlined: true)
                }
            }
            Text(PronFormat.valueLine(a, toks: sentence.toks))
                .font(.body)
            Text(a.layer.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("来源：\(PronFormat.sourceTitle(a.src))")
                Text("证据：\(PronFormat.cleanValue(a.ev) ?? "没有记录")")
                Text("状态：\(PronFormat.statusMeaning(e.status))")
                if let note = e.note {
                    Text("我的备注：\(note)")
                }
                if e.reports > 0 {
                    Text("报错：已报 \(e.reports) 次")
                }
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                Button {
                    setStatus(.verified, e)
                } label: {
                    Label("标为原声已核对", systemImage: "checkmark.seal")
                }
                .disabled(e.status == .verified)
                Button {
                    setStatus(.disputed, e)
                } label: {
                    Label("标为有争议", systemImage: "questionmark.circle")
                }
                .disabled(e.status == .disputed)
                Button {
                    setStatus(nil, e)
                } label: {
                    Label("恢复原状态", systemImage: "arrow.uturn.backward")
                }
                .disabled(e.status == a.st)
                Button {
                    setHidden(!e.hidden, e)
                } label: {
                    Label(e.hidden ? "显示" : "隐藏", systemImage: e.hidden ? "eye" : "eye.slash")
                }
                Button {
                    draft = e.note ?? ""
                    notice = nil
                    page = .note(e.id)
                } label: {
                    Label("备注…", systemImage: "square.and.pencil")
                }
                Button {
                    reportKind = PronAnnotationPanel.reportKinds.first ?? "其他"
                    reportNote = ""
                    notice = nil
                    page = .report(e.id)
                } label: {
                    Label("报错…", systemImage: "exclamationmark.bubble")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }

    private func noteEditor(_ e: EffectiveAnnotation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("备注：\(e.ann.layer.title)")
                .font(.headline)
            Text(PronFormat.valueLine(e.ann, toks: sentence.toks))
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("写下你听到的，比如：主播这里没有停顿", text: $draft, axis: .vertical)
                .lineLimit(2...6)
                .textFieldStyle(.roundedBorder)
            Text("清空后保存，就删掉备注。备注只存在这台 iPad 上。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Button("取消") {
                    page = .list
                }
                Spacer()
                Button("保存备注") {
                    annotations.setNote(draft, ref: ref, sentence: sentence, id: e.id)
                    let empty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    notice = empty ? "备注已删掉" : "备注已保存"
                    page = .list
                }
                .buttonStyle(.borderedProminent)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private func reportEditor(_ e: EffectiveAnnotation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("报错：\(e.ann.layer.title)")
                .font(.headline)
            Text(PronFormat.valueLine(e.ann, toks: sentence.toks))
                .font(.callout)
                .foregroundStyle(.secondary)
            ChoicePicker("哪里不对", selection: $reportKind) {
                ForEach(PronAnnotationPanel.reportKinds, id: \.self) { kind in
                    Text(kind).tag(kind)
                }
            }
            TextField("说明（可以不写）", text: $reportNote, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
            Text("提交后这条先隐藏，可以在句子下方“显示被隐藏的”里找回。报错只存在这台 iPad 上，导出诊断日志时会一起带上。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Button("取消") {
                    page = .list
                }
                Spacer()
                Button("提交报错") {
                    annotations.report(kind: reportKind,
                                       note: reportNote.trimmingCharacters(in: .whitespacesAndNewlines),
                                       ref: ref, sentence: sentence, id: e.id)
                    notice = "已报错，这条先隐藏了"
                    page = .list
                }
                .buttonStyle(.borderedProminent)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private func setStatus(_ status: AnnStatus?, _ e: EffectiveAnnotation) {
        annotations.setStatus(status, ref: ref, sentence: sentence, id: e.id)
        if let status {
            notice = "已标为“\(status.title)”"
        } else {
            notice = "已恢复原状态：\(e.ann.st.title)"
        }
    }

    private func setHidden(_ hidden: Bool, _ e: EffectiveAnnotation) {
        annotations.setHidden(hidden, ref: ref, sentence: sentence, id: e.id)
        notice = hidden ? "这条已隐藏，可以在句子下方“显示被隐藏的”里找回。" : "这条已重新显示。"
    }
}
