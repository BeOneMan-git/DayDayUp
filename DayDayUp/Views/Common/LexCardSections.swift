import SwiftUI

/// Section with a small grey heading, used across the word card and sentence panel.
struct CardSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Tinted note box (context meaning, traps, annotations).
struct NoteBox<Content: View>: View {
    var label: String? = nil
    var tint: Color = Theme.accent
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .leading) {
            Rectangle().fill(tint).frame(width: 3).clipShape(RoundedRectangle(cornerRadius: 1.5))
        }
    }
}

/// The detailed card of an IELTS 5+ word: senses, usage, collocations, IELTS example,
/// roots and affixes, word family, and near-synonym notes.
struct LexCardSections: View {
    let card: Card
    var trapNote: String? = nil
    var accent: String = "en-GB"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let trapNote, !trapNote.isEmpty {
                NoteBox(label: "易错提示", tint: Theme.warn) {
                    Text(trapNote)
                }
            }
            if let senses = card.senses, !senses.isEmpty {
                CardSection(title: "常用释义") {
                    ForEach(Array(senses.enumerated()), id: \.offset) { _, s in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(s.pos ?? "")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(minWidth: 34, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.zh ?? "")
                                if let en = s.en, !en.isEmpty {
                                    Text(en)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            if let scene = card.scene, !scene.isEmpty {
                CardSection(title: "使用场景") {
                    Text(scene)
                }
            }
            if let colloc = card.colloc, !colloc.isEmpty {
                CardSection(title: "常用搭配") {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(Array(colloc.enumerated()), id: \.offset) { _, c in
                            HStack(spacing: 6) {
                                Text(c.en ?? "").bold()
                                Text(c.zh ?? "").foregroundStyle(.secondary)
                            }
                                .font(.callout)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            if let ex = card.ielts, let en = ex.en, !en.isEmpty {
                CardSection(title: "雅思迁移") {
                    VStack(alignment: .leading, spacing: 6) {
                        if let use = ex.use, !use.isEmpty {
                            Text(use)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        Text(en)
                            .font(Font.system(.body, design: .serif))
                        if let zh = ex.zh {
                            Text(zh)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            Speaker.shared.speak(en, language: accent)
                        } label: {
                            Label("朗读例句", systemImage: "speaker.wave.2")
                                .font(.callout)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            if hasRoots {
                CardSection(title: "词根词缀") {
                    if let roots = card.roots, !roots.isEmpty {
                        FlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(Array(roots.enumerated()), id: \.offset) { n, r in
                                HStack(spacing: 6) {
                                    if n > 0 {
                                        Text("+").foregroundStyle(.secondary)
                                    }
                                    VStack(spacing: 2) {
                                        Text(r.count > 0 ? r[0] : "")
                                            .font(.callout.weight(.bold))
                                        Text(r.count > 1 ? r[1] : "")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(rootColor(r.count > 2 ? r[2] : "").opacity(0.12),
                                                in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                    if let memo = card.memo, !memo.isEmpty {
                        Text(memo)
                    }
                    if let family = card.family, !family.isEmpty {
                        FlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(Array(family.enumerated()), id: \.offset) { _, f in
                                HStack(spacing: 6) {
                                    Text(f.w ?? "").bold()
                                    Text("\(f.pos ?? "") \(f.zh ?? "")").foregroundStyle(.secondary)
                                }
                                    .font(.callout)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Theme.chip, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
            if let diff = card.diff, !diff.isEmpty {
                CardSection(title: "近义辨析") {
                    Text(diff)
                }
            }
        }
    }

    private var hasRoots: Bool {
        !(card.roots ?? []).isEmpty || !(card.memo ?? "").isEmpty || !(card.family ?? []).isEmpty
    }

    private func rootColor(_ kind: String) -> Color {
        switch kind {
        case "prefix": return Theme.level6
        case "suffix": return Theme.level7
        default: return Theme.level5
        }
    }
}
