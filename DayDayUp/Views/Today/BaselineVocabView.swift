import SwiftUI

/// 基线 · 词汇自测: 24 words from the content packs' word list (bands 5–8, 6 each). For each word:
/// 认识 / 不确定 / 不认识; after 认识, pick its meaning from four. The result is described per band
/// ("6 级：6 个里说认识 5 个，含义选对 4 个"), saved only when all words are answered.
struct BaselineVocabView: View {
    @Environment(PackStore.self) private var packs
    @Environment(StudyStore.self) private var study
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case ready, testing, saved
    }

    @State private var phase: Phase = .ready
    @State private var words: [BaselineWord] = []
    @State private var answers: [BaselineVocabAnswer] = []
    @State private var checkingMeaning = false
    @State private var bandLines: [String] = []
    @State private var confirmLeave = false

    private var current: BaselineWord? {
        answers.count < words.count ? words[answers.count] : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch phase {
                case .ready: readyCard
                case .testing: testingCard
                case .saved: savedCard
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("词汇自测")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(phase == .testing)
        .toolbar {
            if phase == .testing {
                ToolbarItem(placement: .topBarLeading) {
                    Button("离开") { confirmLeave = true }
                }
            }
        }
        .confirmationDialog("离开词汇自测？", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("离开，不保存", role: .destructive) { dismiss() }
            Button("继续做", role: .cancel) {}
        } message: {
            Text("中途离开，这一项不会记为完成。")
        }
    }

    // MARK: Ready

    @ViewBuilder
    private var readyCard: some View {
        if !packs.lexiconReady {
            ProgressView("正在载入词库…")
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if !BaselineContent.hasEnoughWords(packs.lexicon) {
            emptyLexiconCard
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("24 个词，5、6、7、8 级各 6 个，从内容包的词表里随机取。")
                    .fixedSize(horizontal: false, vertical: true)
                Text("每个词选“认识”“不确定”或“不认识”。选“认识”的，再从 4 个意思里选一个。凭第一感觉，不查词典。大约 5 分钟。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    startTest()
                } label: {
                    Label("开始", systemImage: "play.fill")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var emptyLexiconCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("词库里还没有可用的词", systemImage: "info.circle")
                .font(.headline)
            Text("词汇自测用内容包里的词表（带 5–8 级和中文释义的词）。先在书架导入内容包，或者先跳过这一项，以后再做。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                skip()
            } label: {
                Label("先跳过这一项", systemImage: "forward")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warn.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Testing

    @ViewBuilder
    private var testingCard: some View {
        if let word = current {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("第 \(answers.count + 1) / \(words.count) 个")
                        .font(.callout.monospacedDigit())
                    Badge(text: "\(word.band) 级", color: Theme.level(word.band))
                    Spacer()
                }
                .foregroundStyle(.secondary)
                Text(word.id)
                    .font(Font.system(.largeTitle, design: .serif).weight(.semibold))
                if checkingMeaning {
                    meaningChoices(word)
                } else {
                    claimButtons
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var claimButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            claimButton("认识", symbol: "checkmark.circle", claim: .known)
            claimButton("不确定", symbol: "questionmark.circle", claim: .unsure)
            claimButton("不认识", symbol: "xmark.circle", claim: .unknown)
        }
    }

    private func claimButton(_ title: String, symbol: String, claim: BaselineVocabClaim) -> some View {
        Button {
            choose(claim)
        } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.bordered)
    }

    private func meaningChoices(_ word: BaselineWord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("它的意思是：")
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach(Array(word.options.enumerated()), id: \.offset) { index, option in
                Button {
                    pickMeaning(index, of: word)
                } label: {
                    Text(option)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: Saved

    private var savedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("已保存", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(Theme.level5)
            ForEach(bandLines, id: \.self) { line in
                Text(line)
            }
            Text("“认识”是你自己的判断；“含义选对”是四选一的结果。只是描述，不推算总词汇量。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            missedList
            Button {
                dismiss()
            } label: {
                Label("回到基线", systemImage: "chevron.backward")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }

    /// Words marked 认识 whose meaning was picked wrong, with the right meaning.
    @ViewBuilder
    private var missedList: some View {
        let missed = zip(words, answers).filter { $0.1.correct == false }.map { $0.0 }
        if !missed.isEmpty {
            DisclosureGroup("说认识但意思选错的词（\(missed.count) 个）") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(missed) { word in
                        Text("\(word.id)：\(word.gloss)")
                            .font(.callout)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            }
        }
    }

    // MARK: Actions

    private func startTest() {
        words = BaselineContent.vocabWords(from: packs.lexicon)
        answers = []
        checkingMeaning = false
        bandLines = []
        phase = words.isEmpty ? .ready : .testing
    }

    private func choose(_ claim: BaselineVocabClaim) {
        ActivityClock.shared.touch(.vocab, source: "baseline")
        if claim == .known {
            checkingMeaning = true
        } else {
            record(BaselineVocabAnswer(claim: claim, chosen: nil, correct: nil))
        }
    }

    private func pickMeaning(_ index: Int, of word: BaselineWord) {
        ActivityClock.shared.touch(.vocab, source: "baseline")
        record(BaselineVocabAnswer(claim: .known, chosen: index, correct: index == word.answer))
    }

    private func record(_ answer: BaselineVocabAnswer) {
        checkingMeaning = false
        answers.append(answer)
        if answers.count >= words.count {
            save()
        }
    }

    private func save() {
        var lines: [String] = []
        var numbers: [String: Double] = [:]
        for band in 5...8 {
            let pairs = zip(words, answers).filter { $0.0.band == band }
            guard !pairs.isEmpty else { continue }
            let known = pairs.filter { $0.1.claim == .known }.count
            let unsure = pairs.filter { $0.1.claim == .unsure }.count
            let correct = pairs.filter { $0.1.correct == true }.count
            lines.append("\(band) 级：\(pairs.count) 个里说认识 \(known) 个，含义选对 \(correct) 个")
            numbers["b\(band)_total"] = Double(pairs.count)
            numbers["b\(band)_known"] = Double(known)
            numbers["b\(band)_unsure"] = Double(unsure)
            numbers["b\(band)_correct"] = Double(correct)
        }
        let summary = lines.joined(separator: "；")
        study.updateBaseline { b in
            b.vocab = BaselineResult(done: Date(), summary: summary, refId: nil, numbers: numbers)
        }
        bandLines = lines
        phase = .saved
    }

    private func skip() {
        study.updateBaseline { b in
            b.vocab = BaselineResult(done: Date(), summary: "跳过：词库为空", refId: nil, numbers: [:])
        }
        dismiss()
    }
}

private enum BaselineVocabClaim {
    case known, unsure, unknown
}

private struct BaselineVocabAnswer {
    var claim: BaselineVocabClaim
    var chosen: Int?
    var correct: Bool?
}
