import SwiftUI

struct ParagraphStyle: Equatable {
    var fontStep: Int
    var threshold: Int
    var showTrap: Bool
    var showPhrase: Bool
    var showZh: Bool
    var marksVersion: Int
}

/// Only the values that fall inside this paragraph; everything else is nil,
/// so a paragraph redraws only when its own highlight changes.
struct ParagraphHighlight: Equatable {
    var curTok: Int?
    var curSent: Int?
    var selTok: Int?
    var loopSid: Int?
}

/// One paragraph rendered as a single native Text.
/// Every word is a link (ddu://t/<index>); the reader handles taps through the openURL action.
struct ParagraphView: View, Equatable {
    let para: Para
    let index: Int
    let highlight: ParagraphHighlight
    let style: ParagraphStyle
    let session: ReadingSession      // used for word marks only (not observed here)
    @State private var zhOpen = false  // this paragraph's translation, when 中文 is off

    static func == (a: ParagraphView, b: ParagraphView) -> Bool {
        a.index == b.index && a.highlight == b.highlight && a.style == b.style
    }

    var body: some View {
        switch para.kind {
        case "h":
            Text(attributed(font: Font.system(Theme.bodyStyle(style.fontStep), design: .serif).weight(.bold)))
                .tint(Color.primary)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
        case "rub":
            VStack(alignment: .leading, spacing: 6) {
                Text(attributed(font: Theme.readingFont(style.fontStep).italic()))
                    .lineSpacing(5)
                    .tint(Color.secondary)
                translation
            }
        default:
            HStack(alignment: .top, spacing: 6) {
                playButton
                VStack(alignment: .leading, spacing: 8) {
                    Text(attributed(font: Theme.readingFont(style.fontStep)))
                        .lineSpacing(7)
                        .tint(Color.primary)
                    translation
                }
            }
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private var playButton: some View {
        if let first = para.sents.first(where: { $0.isTimed }) {
            Button {
                session.playSentence(first.id)
            } label: {
                Image(systemName: "play.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(y: -9)
            .accessibilityLabel("从本段播放")
        } else {
            Color.clear.frame(width: 44, height: 1)
        }
    }

    @ViewBuilder
    private var translation: some View {
        if style.showZh || zhOpen {
            Text(translationText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .textSelection(.enabled)
        }
        if !style.showZh && hasTranslation {
            Button {
                zhOpen.toggle()
            } label: {
                Label(zhOpen ? "收起译文" : "译文", systemImage: "character.bubble")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel(zhOpen ? "收起本段译文" : "展开本段译文")
        }
    }

    private var hasTranslation: Bool {
        para.sents.contains { !($0.zh ?? "").isEmpty }
    }

    private var translationText: AttributedString {
        var out = AttributedString()
        for s in para.sents {
            var piece = AttributedString(s.zh ?? "")
            if highlight.curSent == s.id {
                piece.backgroundColor = Theme.sentence
            }
            out += piece
        }
        return out
    }

    // MARK: Attributed text

    private func attributed(font: Font) -> AttributedString {
        var out = AttributedString()
        for (n, s) in para.sents.enumerated() {
            var base = AttributeContainer()
            base.font = font
            if highlight.curSent == s.id {
                base.backgroundColor = Theme.sentence
            }
            if n > 0 {
                var gap = AttributeContainer()
                gap.font = font
                out += AttributedString(" ", attributes: gap)
            }
            let last = s.toks.count - 1
            for (k, t) in s.toks.enumerated() {
                if let a = t.a, !a.isEmpty {
                    out += AttributedString(a, attributes: base)
                }
                out += word(t, base: base, font: font)
                if let z = t.z, !z.isEmpty {
                    out += AttributedString(z, attributes: base)
                }
                if k < last {
                    switch t.j {
                    case "-": out += AttributedString("-", attributes: base)
                    case "_": break
                    default: out += AttributedString(" ", attributes: base)
                    }
                }
            }
        }
        return out
    }

    private func word(_ t: Tok, base: AttributeContainer, font: Font) -> AttributedString {
        var c = base
        var f = font
        if t.B != nil { f = f.bold() }
        if t.I != nil { f = f.italic() }
        if t.S != nil { f = f.smallCaps() }
        c.font = f
        c.link = URL(string: "ddu://t/\(t.i)")

        let m = session.mark(for: t)
        if style.showTrap && m.trap && !m.known {
            c.underlineStyle = Text.LineStyle(pattern: .dot, color: Theme.warn)
        } else if style.threshold > 0 && m.band >= style.threshold && !m.known {
            c.underlineStyle = Text.LineStyle(pattern: .solid, color: Theme.level(m.band))
        } else if style.showPhrase && m.phrase {
            c.underlineStyle = Text.LineStyle(pattern: .dash, color: Color.secondary)
        }
        if m.star {
            c.backgroundColor = Theme.starred
        }
        if highlight.selTok == t.i {
            c.backgroundColor = Theme.selectedWord
        }
        if highlight.curTok == t.i {
            c.backgroundColor = Theme.currentWord
        }
        return AttributedString(t.w, attributes: c)
    }
}

struct ArticleHeader: View {
    let article: Article
    let meta: ArticleMeta?
    let titleOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The Economist · \(article.issue) · \(article.section)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let fly = article.fly, !fly.isEmpty {
                Text(fly)
                    .font(Font.system(.headline, design: .serif).smallCaps())
                    .foregroundStyle(Theme.accent)
            }
            Text(article.title)
                .font(Font.system(.largeTitle, design: .serif).weight(.bold))
                .padding(.horizontal, titleOn ? 6 : 0)
                .background(titleOn ? Theme.sentence : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 16) {
                Label(formatTime(article.dur), systemImage: "headphones")
                if let nw = meta?.nw { Text("\(nw) 词") }
                if let ns = meta?.ns { Text("\(ns) 句") }
                if let n5 = meta?.n5 { Text("5 级+ 词 \(n5) 个") }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            if let topics = meta?.topics, !topics.isEmpty {
                HStack(spacing: 6) {
                    ForEach(topics, id: \.self) { Badge(text: $0) }
                }
            }
        }
        .padding(.bottom, 8)
    }
}

/// 盲听: the text is hidden so the learner listens first.
struct BlindListeningView: View {
    let position: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "ear")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text("盲听中")
                .font(.title2.weight(.semibold))
            Text("先只听，不看文字。听完一遍，再点右上角的眼睛，看着原文再听一遍。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            Text(position)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
}
