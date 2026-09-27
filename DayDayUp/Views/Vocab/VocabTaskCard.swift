import SwiftUI
import UIKit

/// One vocabulary task (VOC-T01…T06). Think first, then reveal, then rate (VOC-F03, ACC-11).
/// The answer is recorded with `vocab.answer`, then `onAnswered` runs.
/// "跳过这张" and a missing item call `onAnswered` without recording anything, so the card stays due.
struct VocabTaskCard: View {
    let card: VocabCard
    let onAnswered: () -> Void

    @Environment(VocabStore.self) private var vocab
    @Environment(PackStore.self) private var packs
    @Environment(UserStore.self) private var user
    @Environment(PracticeStore.self) private var practice
    @Environment(RecorderService.self) private var recorder
    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize

    // Time on this card; paused while it is off screen or the app is not active.
    @State private var shownAt = Date()
    @State private var clockStarted = false
    @State private var visible = false
    @State private var pausedMs = 0
    @State private var pausedSince: Date? = nil

    // Answer
    @State private var revealed = false
    @State private var revealedEarly = false
    @State private var selfRecall = false
    @State private var hint = 0
    @State private var typed = ""
    @State private var result: AnswerCheck.Result? = nil
    @State private var userAccepted = false
    @State private var written = ""
    @State private var wroteDone = false
    @State private var submitted = false
    @State private var skipNotice = false
    @State private var showWhy = false
    @FocusState private var inputFocused: Bool

    // Audio
    @State private var player = SegmentPlayer()
    @State private var useOriginal: Bool? = nil
    @State private var audioBusy = false
    @State private var speaking = false
    @State private var audioToken = 0
    @State private var heardSource: String? = nil

    // 例句朗读
    @State private var takeFile: String? = nil
    @State private var takeMessage: String? = nil

    init(card: VocabCard, onAnswered: @escaping () -> Void) {
        self.card = card
        self.onAnswered = onAnswered
    }

    var body: some View {
        let item = vocab.item(card.itemId)
        VStack(alignment: .leading, spacing: 16) {
            header(item)
            if let item {
                taskContent(item)
                if skipNotice {
                    skipBox
                } else {
                    ratingSection
                }
            } else {
                missingItem
            }
            whyNow
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
        .onAppear { appeared(item) }
        .onDisappear { disappeared() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if visible { resumeClock() }
            } else {
                pauseClock()
            }
        }
    }

    // MARK: Header

    /// Never shows the word itself: 听辨, 拼写 and 填空 must not give the answer away.
    private func header(_ item: VocabItem?) -> some View {
        let reason = VocabTaskCard.reasonBadge(liveFSRS, now: Date())
        return VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 8, lineSpacing: 6) {
                Badge(text: card.task.title, color: Theme.accent)
                if item?.kind == .chunk {
                    Badge(text: "词群", outlined: true)
                }
                Badge(text: reason, outlined: true)
            }
            Text(card.task.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Tasks

    @ViewBuilder
    private func taskContent(_ item: VocabItem) -> some View {
        switch card.task {
        case .recognize: recognizeView(item)
        case .listen: listenView(item)
        case .spell: spellView(item)
        case .cloze: clozeView(item)
        case .readAloud: readAloudView(item)
        case .produce: produceView(item)
        }
    }

    /// T01 认义: the word in its sentence. Think of the meaning, then reveal.
    @ViewBuilder
    private func recognizeView(_ item: VocabItem) -> some View {
        headword(item)
        audioRow(title: "听这个词", source: wordSource(item))
        contextBlock(item.firstSource)
        if revealed {
            meaningBlock(item)
        } else {
            Button {
                revealed = true
            } label: {
                Label("想好了，揭晓", systemImage: "eye")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    /// T02 听辨: sound only. Type the word, or recall it without typing.
    @ViewBuilder
    private func listenView(_ item: VocabItem) -> some View {
        let source = wordSource(item)
        let canSwitch = ItemAudio.word(item, occurrence: item.firstSource, packs: packs, preferOriginal: true).isOriginal
        FlowLayout(spacing: 10, lineSpacing: 10) {
            Button {
                if audioBusy { stopAudio() } else { play(source) }
            } label: {
                Label(audioBusy ? "停止" : "再听一次", systemImage: audioBusy ? "stop.fill" : "speaker.wave.2.fill")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(recorder.isRecording || !VocabTaskCard.hasSound(source))
            if canSwitch {
                Button {
                    switchVoice(item)
                } label: {
                    Label("换一种声音", systemImage: "arrow.left.arrow.right")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(recorder.isRecording)
            }
            Badge(text: "声音：" + source.label, outlined: true)
        }
        if revealed {
            answerReveal(item, withAudio: false, withGloss: true)
            if let result {
                checkResult(result, item)
            }
        } else {
            Text("文字先藏起来。听一听，写出这个词；也可以只在心里想。")
                .font(.callout)
                .foregroundStyle(.secondary)
            hintLines(item)
            answerField("写出你听到的词", item)
            objectiveButtons(item)
        }
    }

    /// T03 拼写: Chinese meaning, sound and the sentence with a blank. Type the word.
    @ViewBuilder
    private func spellView(_ item: VocabItem) -> some View {
        NoteBox(label: "中文义") {
            Text(glossText(item))
                .font(.title3.weight(.semibold))
            if let pos = posText(item) {
                Text(pos)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        if revealed {
            answerReveal(item, withAudio: true, withGloss: false)
            if let result {
                checkResult(result, item)
            }
        } else {
            audioRow(title: "听发音", source: wordSource(item))
            if let occ = item.firstSource, let blank = occ.blanked() {
                blankBlock(blank, unmapped: occ.unmapped == true)
            }
            hintLines(item)
            answerField("写出这个词", item)
            objectiveButtons(item)
        }
    }

    /// T04 语境填空: the original sentence with a blank; no first letter unless asked for.
    @ViewBuilder
    private func clozeView(_ item: VocabItem) -> some View {
        let occ = item.firstSource
        if revealed {
            answerReveal(item, withAudio: true, withGloss: true)
            if let result {
                checkResult(result, item)
            }
        } else {
            if let blank = clozeSentence(occ, item) {
                blankBlock(blank, unmapped: occ?.unmapped == true)
            } else {
                // No saved sentence: the meaning is the only cue.
                Text("这个词没有保存原句，按中文义填写。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                NoteBox(label: "中文义") {
                    Text(glossText(item))
                }
            }
            hintLines(item)
            answerField("填出空里的词", item)
            objectiveButtons(item)
        }
    }

    /// T05 例句朗读: listen, record, compare, then rate. Evidence only; no pronunciation score.
    @ViewBuilder
    private func readAloudView(_ item: VocabItem) -> some View {
        let occ = item.firstSource
        let hasSentence = !(occ?.sentence ?? "").isEmpty
        let source = hasSentence
            ? ItemAudio.sentence(occ, packs: packs, preferOriginal: vocab.settings.preferOriginalAudio)
            : wordSource(item)
        AdaptiveStack(spacing: 10, rowAlignment: .firstTextBaseline) {
            Text(item.text)
                .font(Font.system(.title2, design: .serif).weight(.semibold))
            Text(glossText(item))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        if hasSentence {
            contextBlock(occ)
        } else {
            Text("没有保存原句，读这个词。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        Label("只记朗读证据，不打发音分", systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(.secondary)
        readAloudControls(source)
        TakeMeter()
        if recorder.denied {
            MicrophoneDeniedCard { openSettings() }
        }
        if let takeMessage {
            Label(takeMessage, systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        if !skipNotice && !submitted {
            Button {
                skip()
            } label: {
                Label("跳过这张", systemImage: "forward")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
    }

    private func readAloudControls(_ source: ItemAudioSource) -> some View {
        let recording = recorder.isRecording && recorder.owner == "vocab"
        let otherBusy = recorder.isBusy && !recording
        let mine = practice.recordingURL(takeFile)
        let playing = audioBusy || player.playing != SegmentPlayer.Source.none
        let recordTitle = recording ? "停止录音" : (takeFile == nil ? "录音" : "再录一次")
        return VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 10, lineSpacing: 10) {
                Button {
                    if playing { stopAudio() } else { play(source) }
                } label: {
                    Label(playing ? "停止" : "听原句", systemImage: playing ? "stop.fill" : "play.fill")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(recorder.isRecording || !VocabTaskCard.hasSound(source))

                Badge(text: source.label, outlined: true)

                Button {
                    toggleRecord()
                } label: {
                    Label(recordTitle, systemImage: recording ? "stop.circle.fill" : "record.circle")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(recording ? Color.red : Theme.accent)
                .disabled(otherBusy || submitted)

                Button {
                    playMine()
                } label: {
                    Label("听我的", systemImage: "person.wave.2")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(mine == nil || recorder.isRecording)

                Button {
                    playAB(source)
                } label: {
                    Label("A/B 对照", systemImage: "arrow.left.arrow.right")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(mine == nil || !source.isOriginal || recorder.isRecording)
            }
            if mine != nil && !source.isOriginal {
                Text("A/B 对照要用原声；这句现在只有合成音。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// T06 主动表达: use the word in a new sentence on a given topic (独立造句, kept apart from 原句模仿).
    @ViewBuilder
    private func produceView(_ item: VocabItem) -> some View {
        let topic = VocabTaskCard.topic(for: card)
        let locked = wroteDone || revealedEarly
        AdaptiveStack(spacing: 10, rowAlignment: .firstTextBaseline) {
            Text(item.text)
                .font(Font.system(.title2, design: .serif).weight(.semibold))
            if let pos = posText(item) {
                Text(pos)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        Text("意思：" + glossText(item))
            .font(.callout)
            .foregroundStyle(.secondary)
        if let function = item.function, !function.isEmpty {
            Text("用法：" + function)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        Text("用「\(item.text)」写一句话，说说\(topic)。")
            .font(.title3.weight(.semibold))
        Label("独立造句：和“例句朗读”（原句模仿）分开记录。", systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(.secondary)
        TextEditor(text: $written)
            .font(Font.system(.title3, design: .serif))
            .focused($inputFocused)
            .autocorrectionDisabled()
            .frame(minHeight: 110, maxHeight: 200)
            .padding(8)
            .scrollContentBackground(.hidden)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.3))
            }
            .disabled(locked)
            .accessibilityLabel("你的句子")
        if revealedEarly {
            referenceBlock(item)
        } else if wroteDone {
            // Self-rating first, then the reference (IEL-F03 order: 先自评，再看参考).
            if submitted {
                referenceBlock(item)
                Button {
                    onAnswered()
                } label: {
                    Label("下一张", systemImage: "arrow.right")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("先按自己写的句子自评，评完再看参考例句。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            FlowLayout(spacing: 10, lineSpacing: 10) {
                Button {
                    finishWriting()
                } label: {
                    Label("写好了", systemImage: "checkmark")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(written.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button {
                    giveUpWriting()
                } label: {
                    Label("写不出来，先看参考", systemImage: "eye")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            Text("先看参考会记为忘记，不算独立完成。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func referenceBlock(_ item: VocabItem) -> some View {
        if let example = packs.entry(item.key)?.card?.ielts, let en = example.en, !en.isEmpty {
            CardSection(title: "参考例句（看完不算独立完成）") {
                Text(en)
                    .font(Font.system(.body, design: .serif))
                    .textSelection(.enabled)
                if let zh = example.zh, !zh.isEmpty {
                    Text(zh)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("词库里没有这个词的参考例句。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Shared blocks

    private func headword(_ item: VocabItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.text)
                .font(Font.system(.largeTitle, design: .serif).weight(.semibold))
                .textSelection(.enabled)
            if let pos = posText(item) {
                Text(pos)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// What 听辨 / 拼写 / 填空 show once the answer is out.
    @ViewBuilder
    private func answerReveal(_ item: VocabItem, withAudio: Bool, withGloss: Bool) -> some View {
        headword(item)
        if withAudio {
            audioRow(title: "听这个词", source: wordSource(item))
        }
        if withGloss {
            NoteBox(label: "意思") {
                Text(glossText(item))
            }
        }
        contextBlock(item.firstSource)
    }

    /// 认义 after "揭晓": saved meaning, meaning in this sentence, dictionary senses.
    @ViewBuilder
    private func meaningBlock(_ item: VocabItem) -> some View {
        let entry = packs.entry(item.key)
        NoteBox(label: "你保存的意思") {
            Text(glossText(item))
                .font(.title3.weight(.semibold))
        }
        if let meaning = contextMeaning(item) {
            NoteBox(label: "这句里的意思", tint: Theme.level5) {
                Text(meaning)
                    .font(.body.weight(.medium))
            }
        }
        if let function = item.function, !function.isEmpty {
            CardSection(title: "用法") {
                Text(function)
            }
        }
        if let note = item.note, !note.isEmpty {
            CardSection(title: "笔记") {
                Text(note)
            }
        }
        if let senses = entry?.card?.senses, !senses.isEmpty {
            CardSection(title: "词典义项") {
                ForEach(Array(senses.enumerated()), id: \.offset) { index, sense in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(sense.pos ?? "")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(minWidth: 34, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sense.zh ?? "")
                            if let en = sense.en, !en.isEmpty {
                                Text(en)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        if index == item.senseIndex {
                            Badge(text: "本条", outlined: true)
                        }
                    }
                }
            }
        } else if let zh = entry?.zh, !zh.isEmpty {
            CardSection(title: "词典释义") {
                Text(zh)
            }
        }
    }

    @ViewBuilder
    private func contextBlock(_ occ: Occurrence?) -> some View {
        if let occ, let text = VocabTaskCard.highlighted(occ) {
            sentenceBox(unmapped: occ.unmapped == true) {
                Text(text)
                    .font(readingFont)
                    .lineSpacing(5)
                    .textSelection(.enabled)
            }
        }
    }

    private func blankBlock(_ blank: String, unmapped: Bool) -> some View {
        sentenceBox(unmapped: unmapped) {
            Text(blank)
                .font(readingFont)
                .lineSpacing(5)
                .accessibilityLabel(blank.replacingOccurrences(of: "＿＿＿", with: "（空）"))
        }
    }

    /// The learner's English reading size (18…34 pt), following Dynamic Type (UI-P01).
    private var readingFont: Font {
        Theme.readingFont(size: Theme.readingPointSize(user.settings.fontSize, typeSize: typeSize))
    }

    private func sentenceBox<Content: View>(unmapped: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
            if unmapped {
                Label("原句已更新，这里显示保存时的句子", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 10))
    }

    private func audioRow(title: String, source: ItemAudioSource) -> some View {
        HStack(spacing: 10) {
            Button {
                if audioBusy { stopAudio() } else { play(source) }
            } label: {
                Label(audioBusy ? "停止" : title, systemImage: audioBusy ? "stop.fill" : "speaker.wave.2.fill")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(recorder.isRecording || !VocabTaskCard.hasSound(source))
            Badge(text: source.label, outlined: true)
        }
    }

    // MARK: Typed answers (听辨 / 拼写 / 填空)

    private func answerField(_ prompt: String, _ item: VocabItem) -> some View {
        let empty = typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return AdaptiveStack(spacing: 10) {
            TextField(prompt, text: $typed)
                .font(Font.system(.title3, design: .serif))
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .focused($inputFocused)
                .onSubmit { check(item) }
                .padding(10)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.3))
                }
            Button {
                check(item)
            } label: {
                Label("检查", systemImage: "checkmark")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(empty)
        }
    }

    private func objectiveButtons(_ item: VocabItem) -> some View {
        let next = nextHint(item)
        return VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 10, lineSpacing: 10) {
                if card.task == .listen {
                    Button {
                        recallWithoutTyping()
                    } label: {
                        Label("我想出来了（不打字）", systemImage: "brain.head.profile")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    if let next { hint = next }
                } label: {
                    Label(VocabTaskCard.hintTitle(next), systemImage: "lightbulb")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(next == nil)
                Button {
                    revealEarly()
                } label: {
                    Label("直接看答案", systemImage: "eye")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            Text("用了提示，答对记为困难；直接看答案记为忘记。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func hintLines(_ item: VocabItem) -> some View {
        let target = expected(item)
        if hint >= 1 {
            Label(VocabTaskCard.firstLetterHint(target, withLength: meaningVisible(item)), systemImage: "lightbulb")
                .font(.callout)
        }
        if hint == 2 {
            Label("中文义：" + glossText(item), systemImage: "lightbulb")
                .font(.callout)
        }
        if hint >= 3 {
            Label("开头几个字母：" + VocabTaskCard.prefixLetters(target) + "…", systemImage: "lightbulb")
                .font(.callout)
        }
    }

    private func checkResult(_ result: AnswerCheck.Result, _ item: VocabItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(VocabTaskCard.verdictTitle(result.verdict), systemImage: VocabTaskCard.verdictSymbol(result.verdict))
                .font(.headline)
            infoRow("你写的", typed.trimmingCharacters(in: .whitespacesAndNewlines))
            infoRow("答案", expected(item))
            if result.verdict != .exact && !result.marks.isEmpty {
                AnswerMarks(marks: result.marks)
            }
            if !result.note.isEmpty {
                Text(result.note)
                    .font(.callout)
            }
            if card.task == .cloze && result.verdict != .exact {
                acceptButton
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 10))
    }

    /// 填空: "我的答案也可以" is recorded as userAccepted and shown apart later.
    private var acceptButton: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                userAccepted.toggle()
            } label: {
                Label(userAccepted ? "已选：我的答案也可以（再点一次取消）" : "我的答案也可以",
                      systemImage: userAccepted ? "checkmark.square" : "square")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(submitted)
            Text("词表答案不等于唯一正确的英语，这一条会单独标出。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Rating

    @ViewBuilder
    private var ratingSection: some View {
        switch card.task {
        case .recognize:
            if revealed {
                ratingPicker(FSRSRating.allCases, note: "对照意思，按刚才想的情况自评。")
            }
        case .listen, .spell, .cloze:
            if revealedEarly {
                forcedRating(.again, note: "先看答案不算独立回忆，这张记为忘记。")
            } else if selfRecall {
                if hint > 0 {
                    ratingPicker([.again, .hard], note: "用了提示：想对了记为困难，想错了记为忘记。")
                } else {
                    ratingPicker(FSRSRating.allCases, note: "对照答案，按刚才想的情况自评。")
                }
            } else if let result {
                objectiveRating(result)
            }
        case .readAloud:
            if takeFile != nil && !recorder.isRecording {
                ratingPicker(FSRSRating.allCases, note: "听自己的录音，对照原句自评：读得顺不顺，这个词读得对不对。")
            }
        case .produce:
            if revealedEarly {
                forcedRating(.again, note: "先看参考不算独立完成，这张记为忘记。")
            } else if wroteDone {
                ratingPicker(FSRSRating.allCases, note: "按你写的句子自评：意思对不对，用法自然不自然。")
            }
        }
    }

    @ViewBuilder
    private func objectiveRating(_ result: AnswerCheck.Result) -> some View {
        if result.verdict == .exact && hint == 0 {
            ratingPicker([.good, .easy], note: "完全正确。选“记得”；写得毫不费力就选“轻松”。")
        } else {
            let rating = RatingRule.objective(verdict: result.verdict, hintUsed: hint > 0,
                                              revealedEarly: revealedEarly, userAccepted: userAccepted,
                                              task: card.task, easy: false)
            forcedRating(rating, note: ruleNote(result.verdict))
        }
    }

    private func ruleNote(_ verdict: AnswerCheck.Verdict) -> String {
        if verdict == .exact { return "用了提示答对：记为困难（有提示成功）。" }
        if userAccepted { return "你认为自己的答案也可以：记为困难，这一条会单独标出。" }
        if verdict == .inflection {
            return card.task == .cloze ? "填空要填原句里的词形：记为忘记。" : "词形不同：记为困难。"
        }
        return "没写对：记为忘记。"
    }

    private func ratingPicker(_ ratings: [FSRSRating], note: String) -> some View {
        let now = Date()
        return VStack(alignment: .leading, spacing: 8) {
            Text(note)
                .font(.callout)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                ForEach(ratings, id: \.self) { rating in
                    ratingButton(rating, now: now)
                }
            }
        }
    }

    private func ratingButton(_ rating: FSRSRating, now: Date) -> some View {
        let seconds = previewSeconds(rating, now: now)
        let interval = VocabTaskCard.intervalText(seconds)
        let long = seconds >= Double(VocabStore.longIntervalDays) * 86_400
        var spoken = "\(rating.title)，下次 \(interval)后"
        if long { spoken += "，较长复习间隔" }
        return Button {
            submit(rating)
        } label: {
            VStack(spacing: 2) {
                Text(rating.title)
                    .font(.headline)
                Text(interval)
                    .font(.caption)
                if long {
                    Text("较长复习间隔")
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.bordered)
        .disabled(submitted)
        .accessibilityLabel(spoken)
    }

    /// One rating decided by the rules (提前揭晓, 提示, 答错); the learner confirms it.
    private func forcedRating(_ rating: FSRSRating, note: String) -> some View {
        let interval = VocabTaskCard.intervalText(previewSeconds(rating, now: Date()))
        return VStack(alignment: .leading, spacing: 8) {
            Label(note, systemImage: "info.circle")
                .font(.callout)
            Button {
                submit(rating)
            } label: {
                VStack(spacing: 2) {
                    Text("确定：\(rating.title)")
                        .font(.headline)
                    Text("下次 \(interval)后")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .disabled(submitted)
        }
    }

    private func previewSeconds(_ rating: FSRSRating, now: Date) -> TimeInterval {
        vocab.scheduler.review(liveFSRS, rating: rating, at: now).due.timeIntervalSince(now)
    }

    /// The card as stored now (the value passed in is a snapshot from the queue).
    private var liveFSRS: FSRSCard {
        vocab.card(card.id)?.fsrs ?? card.fsrs
    }

    // MARK: Why now

    @ViewBuilder
    private var whyNow: some View {
        Divider()
        Button {
            showWhy.toggle()
        } label: {
            HStack {
                Label("为什么现在复习？", systemImage: "questionmark.circle")
                Spacer()
                Image(systemName: showWhy ? "chevron.up" : "chevron.down")
                    .accessibilityHidden(true)
            }
            .font(.callout)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(showWhy ? "已展开" : "已收起")
        if showWhy {
            let rows = whyRows(liveFSRS, now: Date())
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    infoRow(row.0, row.1)
                }
                Text("排期用 FSRS-6，不加随机抖动：到期日由上面这些数字算出。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func whyRows(_ f: FSRSCard, now: Date) -> [(String, String)] {
        let scheduler = vocab.scheduler
        var rows: [(String, String)] = []
        rows.append(("原因", reasonLine(f, now: now)))
        rows.append(("状态", VocabTaskCard.stateName(f)))
        rows.append(("稳定性", f.stability.map { String(format: "%.1f 天", $0) } ?? "还没有"))
        rows.append(("难度", f.difficulty.map { String(format: "%.1f（1–10，越大越难）", $0) } ?? "还没有"))
        if f.isNew {
            rows.append(("现在的记住概率", "还没有复习记录"))
        } else {
            let r = scheduler.retrievability(f, at: now)
            rows.append(("现在的记住概率", r.isFinite ? "\(Int((r * 100).rounded()))%" : "算不出来"))
        }
        rows.append(("目标保留率", "\(Int((scheduler.desiredRetention * 100).rounded()))%"))
        rows.append(("上次复习", f.lastReview.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "还没有"))
        rows.append(("上次评分", lastRatingTitle() ?? "还没有"))
        rows.append(("到期时间", f.isNew ? "新任务，排进今天就能学" : f.due.formatted(date: .abbreviated, time: .shortened)))
        if let days = VocabTaskCard.currentIntervalDays(f) {
            let long = days >= VocabStore.longIntervalDays
            rows.append(("当前间隔", long ? "\(days) 天（较长复习间隔）" : "\(days) 天"))
        }
        rows.append(("作答次数", "\(f.reps) 次，其中忘记 \(f.lapses) 次"))
        return rows
    }

    private func reasonLine(_ f: FSRSCard, now: Date) -> String {
        if f.isNew { return "新任务：今天的新任务名额里有它。" }
        switch f.state {
        case .learning:
            return "学习步：刚学过，1 或 10 分钟后再练一次。"
        case .relearning:
            return "重学步：上次忘记了，10 分钟后再练一次。"
        case .review:
            let overdue = max(0, FSRSScheduler.wholeDays(from: f.due, to: now))
            if overdue > 0 {
                return "已过期 \(overdue) 天。到期的卡片一直保持到期，不会被顺延。"
            }
            return "到期了：按记忆模型，现在的记住概率已经降到目标保留率附近。"
        }
    }

    private func lastRatingTitle() -> String? {
        let reviews = VocabQueueBuilder.activeReviews(vocab.events(for: card.itemId))
        guard let last = reviews.last(where: { $0.cardId == card.id }),
              let raw = last.rating, let rating = FSRSRating(rawValue: raw) else { return nil }
        return rating.title
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        AdaptiveStack(spacing: 10, rowAlignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(minWidth: 110, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.callout)
    }

    // MARK: Skip and missing item

    private var skipBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("这张没有记录作答，仍然到期，下次复习还会出现。", systemImage: "info.circle")
                .font(.callout)
            Button {
                onAnswered()
            } label: {
                Label("好，下一张", systemImage: "arrow.right")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 10))
    }

    private var missingItem: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("找不到这个词条，可能已经删除。这张先跳过，不记录作答。", systemImage: "exclamationmark.triangle")
                .font(.callout)
            Button {
                onAnswered()
            } label: {
                Label("跳过", systemImage: "forward")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: Actions

    private func check(_ item: VocabItem) {
        let answer = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty, !revealed else { return }
        result = AnswerCheck.check(answer, accepted: acceptedForms(item), lemma: item.key)
        revealed = true
        inputFocused = false
        stopAudio()
    }

    private func recallWithoutTyping() {
        selfRecall = true
        revealed = true
        inputFocused = false
        stopAudio()
    }

    private func revealEarly() {
        revealedEarly = true
        revealed = true
        inputFocused = false
        stopAudio()
    }

    private func finishWriting() {
        guard !written.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        wroteDone = true
        revealed = true
        inputFocused = false
    }

    private func giveUpWriting() {
        revealedEarly = true
        revealed = true
        inputFocused = false
    }

    private func skip() {
        stopAudio()
        if recorder.owner == "vocab" { recorder.stop() }
        skipNotice = true
    }

    private func submit(_ rating: FSRSRating) {
        guard !submitted, let item = vocab.item(card.itemId) else { return }
        submitted = true
        stopAudio()
        var details = AnswerDetails()
        details.durationMs = activeMs()
        details.hint = hint
        details.revealedEarly = revealedEarly
        details.userAccepted = userAccepted
        details.source = heardSource
        let answer = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        switch card.task {
        case .recognize:
            details.expected = item.gloss.isEmpty ? nil : item.gloss
        case .listen, .spell, .cloze:
            details.expected = expected(item)
            if let result, !selfRecall, !revealedEarly {
                details.correct = RatingRule.isCorrect(result.verdict, userAccepted: userAccepted)
                details.answer = answer
            } else if revealedEarly {
                details.correct = false
                details.answer = answer.isEmpty ? nil : answer
            }
        case .readAloud:
            details.evidence = takeFile
            details.expected = item.firstSource?.sentence ?? item.text
        case .produce:
            let sentence = written.trimmingCharacters(in: .whitespacesAndNewlines)
            details.answer = sentence.isEmpty ? nil : sentence
        }
        vocab.answer(cardId: card.id, rating: rating, details: details)
        if card.task == .produce && wroteDone && !revealedEarly {
            return      // the reference shows now; 下一张 moves on
        }
        onAnswered()
    }

    // MARK: Audio

    private func wordSource(_ item: VocabItem) -> ItemAudioSource {
        ItemAudio.word(item, occurrence: item.firstSource, packs: packs,
                       preferOriginal: useOriginal ?? vocab.settings.preferOriginalAudio)
    }

    private func play(_ source: ItemAudioSource) {
        guard !recorder.isRecording, VocabTaskCard.hasSound(source) else { return }
        stopAudio()
        engine.pause()
        audioToken += 1
        let token = audioToken
        audioBusy = true
        switch source {
        case .clip:
            heardSource = "clip"
        case .tts:
            heardSource = "tts"
            speaking = true
        case .none:
            break
        }
        let language = user.settings.accent
        Task {
            await ItemAudio.play(source, player: player, language: language)
            if token == audioToken {
                audioBusy = false
                speaking = false
            }
        }
    }

    /// Stops this card's sound. The shared system voice is stopped only if this card started it,
    /// so a card that is leaving never cuts off the next card's first word.
    private func stopAudio() {
        audioToken += 1
        if speaking { SpeechQueue.shared.stop() }
        player.stop()
        audioBusy = false
        speaking = false
    }

    /// 听辨: 原声 ↔ 合成音.
    private func switchVoice(_ item: VocabItem) {
        let nowOriginal = wordSource(item).isOriginal
        useOriginal = !nowOriginal
        play(ItemAudio.word(item, occurrence: item.firstSource, packs: packs, preferOriginal: !nowOriginal))
    }

    private func toggleRecord() {
        if recorder.isRecording {
            if recorder.owner == "vocab" { recorder.stop() }
            return
        }
        guard !recorder.isBusy else { return }
        stopAudio()
        engine.pause()
        takeMessage = nil
        let url = practice.newRecordingURL()
        Task {
            let ok = await recorder.start(into: url, owner: "vocab", maxDuration: 60) { take in
                finishTake(take)
            }
            if !ok && !recorder.isBusy {
                takeMessage = recorder.denied ? "没有麦克风权限，录不了音。" : "录音没有启动，请再试一次。"
            }
        }
    }

    private func finishTake(_ take: RecordingResult) {
        if take.silent {
            takeMessage = "只录到静音。看看麦克风有没有被挡住，再录一次。"
            return
        }
        takeFile = take.file
        if take.interrupted {
            takeMessage = "录音被打断，已保存 \(String(format: "%.1f", take.seconds)) 秒。"
        } else {
            takeMessage = "已录好。可以“听我的”或“A/B 对照”，然后自评。"
        }
    }

    private func playMine() {
        guard !recorder.isRecording, let url = practice.recordingURL(takeFile) else { return }
        stopAudio()
        engine.pause()
        Task { await player.play(url, as: .mine) }
    }

    private func playAB(_ source: ItemAudioSource) {
        guard !recorder.isRecording, case .clip(let original, let start, let end) = source,
              let mine = practice.recordingURL(takeFile) else { return }
        stopAudio()
        engine.pause()
        heardSource = "clip"
        player.playAB(original: original, from: start, to: end, rate: 1.0, mine: mine)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    // MARK: Appear, disappear, clock

    private func appeared(_ item: VocabItem?) {
        visible = true
        if clockStarted {
            resumeClock()
            return
        }
        clockStarted = true
        shownAt = Date()
        if card.task == .readAloud {
            recorder.refreshPermission()
        }
        // 听辨 plays the word once. A short wait lets the previous card finish stopping its sound.
        if card.task == .listen, let item {
            let source = wordSource(item)
            let token = audioToken
            Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard visible, !revealed, token == audioToken else { return }
                play(source)
            }
        }
    }

    private func disappeared() {
        visible = false
        pauseClock()
        stopAudio()
        if recorder.owner == "vocab" { recorder.stop() }
        AudioSessionControl.usePlayback()
    }

    private func pauseClock() {
        if pausedSince == nil { pausedSince = Date() }
    }

    private func resumeClock() {
        guard let since = pausedSince else { return }
        pausedMs += Int(Date().timeIntervalSince(since) * 1000)
        pausedSince = nil
    }

    private func activeMs() -> Int {
        let now = Date()
        var ms = Int(now.timeIntervalSince(shownAt) * 1000) - pausedMs
        if let since = pausedSince {
            ms -= Int(now.timeIntervalSince(since) * 1000)
        }
        return max(0, ms)
    }

    // MARK: Item helpers

    /// The form the learner met: the word as printed in the sentence, else the headword.
    private func expected(_ item: VocabItem) -> String {
        if let surface = item.firstSource?.surface, !surface.isEmpty { return surface }
        return item.text
    }

    private func acceptedForms(_ item: VocabItem) -> [String] {
        let target = expected(item)
        if card.task == .listen {
            return [target, item.text, item.key ?? ""]
        }
        return [target]
    }

    private func glossText(_ item: VocabItem) -> String {
        item.gloss.isEmpty ? "（没有写意思）" : item.gloss
    }

    private func posText(_ item: VocabItem) -> String? {
        if let pos = item.pos, !pos.isEmpty { return pos }
        if let pos = packs.entry(item.key)?.card?.pos, !pos.isEmpty { return pos }
        return nil
    }

    /// Lexicon meaning for this very sentence. Not used when the sentence changed without a mapping,
    /// so an old context is never attached to a new sentence (ACC-07).
    private func contextMeaning(_ item: VocabItem) -> String? {
        guard let occ = item.firstSource, occ.unmapped != true else { return nil }
        let sid = "\(occ.article):\(occ.sid)"
        guard let meaning = packs.entry(item.key)?.card?.ctx?.first(where: { $0.sid == sid })?.m,
              !meaning.isEmpty else { return nil }
        return meaning
    }

    /// 拼写 always shows the meaning, and so does 填空 without a sentence;
    /// there the second hint gives more letters instead.
    private func meaningVisible(_ item: VocabItem) -> Bool {
        card.task == .spell || (card.task == .cloze && item.firstSource?.blanked() == nil)
    }

    /// Hint levels as stored in the event: 1 first letter, 2 meaning, 3 more letters.
    private func nextHint(_ item: VocabItem) -> Int? {
        switch hint {
        case 0: return 1
        case 1: return meaningVisible(item) ? 3 : 2
        default: return nil
        }
    }

    /// 填空 with the first-letter hint shows the letter inside the blank.
    private func clozeSentence(_ occ: Occurrence?, _ item: VocabItem) -> String? {
        guard let occ else { return nil }
        if hint >= 1, let first = expected(item).first {
            return occ.blanked("\(first)＿＿＿")
        }
        return occ.blanked()
    }

    // MARK: Static helpers

    private static func hasSound(_ source: ItemAudioSource) -> Bool {
        switch source {
        case .clip, .tts: return true
        case .none: return false
        }
    }

    /// The sentence snapshot with the saved word in bold.
    private static func highlighted(_ occ: Occurrence) -> AttributedString? {
        guard let sentence = occ.sentence, !sentence.isEmpty else { return nil }
        guard let surface = occ.surface, !surface.isEmpty,
              let range = SentenceText.range(of: surface, in: sentence, near: occ.start ?? 0) else {
            return AttributedString(sentence)
        }
        var out = AttributedString(String(sentence[sentence.startIndex..<range.lowerBound]))
        var word = AttributedString(String(sentence[range]))
        word.inlinePresentationIntent = .stronglyEmphasized
        out.append(word)
        out.append(AttributedString(String(sentence[range.upperBound..<sentence.endIndex])))
        return out
    }

    /// A topic for 主动表达 that stays the same between launches (unlike `hashValue`)
    /// and changes after each answer.
    private static func topic(for card: VocabCard) -> String {
        let topics = ["工作", "学习", "科技", "健康", "环境", "城市生活", "旅行", "媒体"]
        let sum = card.id.unicodeScalars.reduce(0) { $0 + Int($1.value) } + card.fsrs.reps
        let index = ((sum % topics.count) + topics.count) % topics.count
        return topics[index]
    }

    /// "1 分钟", "5.5 分钟", "10 分钟", "3 天" …
    private static func intervalText(_ seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        if s < 3_600 {
            let minutes = (s / 30).rounded() / 2
            if minutes < 1 { return "1 分钟" }
            return minutes == minutes.rounded() ? "\(Int(minutes)) 分钟" : String(format: "%.1f 分钟", minutes)
        }
        if s < 86_400 {
            let hours = (s / 360).rounded() / 10
            return hours == hours.rounded() ? "\(Int(hours)) 小时" : String(format: "%.1f 小时", hours)
        }
        let days = Int((s / 86_400).rounded())
        if days >= 365 {
            return "\(days) 天（约 \(String(format: "%.1f", Double(days) / 365)) 年）"
        }
        return "\(days) 天"
    }

    private static func currentIntervalDays(_ f: FSRSCard) -> Int? {
        guard f.state == .review, let last = f.lastReview else { return nil }
        return Int((f.due.timeIntervalSince(last) / 86_400).rounded())
    }

    private static func reasonBadge(_ f: FSRSCard, now: Date) -> String {
        if f.isNew { return "新任务" }
        switch f.state {
        case .learning: return "学习步"
        case .relearning: return "重学步"
        case .review:
            let overdue = max(0, FSRSScheduler.wholeDays(from: f.due, to: now))
            return overdue > 0 ? "过期 \(overdue) 天" : "到期"
        }
    }

    private static func stateName(_ f: FSRSCard) -> String {
        if f.isNew { return "新（还没复习过）" }
        switch f.state {
        case .learning: return "学习中"
        case .review: return "复习"
        case .relearning: return "重学"
        }
    }

    private static func hintTitle(_ level: Int?) -> String {
        switch level {
        case 1?: return "提示：首字母"
        case 2?: return "再提示：中文义"
        case 3?: return "再提示：多给几个字母"
        default: return "提示已用完"
        }
    }

    private static func firstLetterHint(_ target: String, withLength: Bool) -> String {
        let first = target.first.map { String($0) } ?? ""
        guard withLength else { return "首字母：\(first)" }
        let words = target.split(separator: " ").count
        if words > 1 { return "首字母：\(first)，共 \(words) 个词" }
        return "首字母：\(first)，共 \(target.count) 个字母"
    }

    private static func prefixLetters(_ target: String) -> String {
        String(target.prefix(max(2, (target.count + 1) / 2)))
    }

    private static func verdictTitle(_ verdict: AnswerCheck.Verdict) -> String {
        switch verdict {
        case .exact: return "完全正确"
        case .inflection: return "词形不同"
        case .close: return "差一点"
        case .wrong: return "不对"
        case .empty: return "没有输入"
        }
    }

    private static func verdictSymbol(_ verdict: AnswerCheck.Verdict) -> String {
        switch verdict {
        case .exact: return "checkmark.circle.fill"
        case .inflection: return "textformat.alt"
        case .close: return "exclamationmark.circle"
        case .wrong: return "xmark.circle"
        case .empty: return "circle"
        }
    }
}

extension VocabTaskCard {
    /// Letter-by-letter comparison. Every changed letter carries a text label (缺字 / 多写 / 错序),
    /// so the marks never rely on colour alone.
    fileprivate struct AnswerMarks: View {
        let marks: [AnswerCheck.Mark]

        private enum Kind {
            case same, missing, extra, swapped
        }

        var body: some View {
            FlowLayout(spacing: 3, lineSpacing: 6) {
                ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                    chip(mark)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
        }

        private var spoken: String {
            let text = AnswerCheck.describe(marks)
            return text.isEmpty ? "字母完全一致" : "对照：" + text
        }

        @ViewBuilder
        private func chip(_ mark: AnswerCheck.Mark) -> some View {
            switch mark {
            case .same(let c):
                cell(String(c), caption: " ", kind: .same)
            case .missing(let c):
                cell(String(c), caption: "缺字", kind: .missing)
            case .extra(let c):
                cell(String(c), caption: "多写", kind: .extra)
            case .swapped(let a, let b):
                cell(String(a) + String(b), caption: "错序", kind: .swapped)
            }
        }

        private func cell(_ letters: String, caption: String, kind: Kind) -> some View {
            VStack(spacing: 1) {
                Text(letters)
                    .font(Font.system(.title3, design: .monospaced).weight(kind == .same ? .regular : .bold))
                    .strikethrough(kind == .extra)
                    .underline(kind == .missing)
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(chipColor(kind), in: RoundedRectangle(cornerRadius: 5))
        }

        private func chipColor(_ kind: Kind) -> Color {
            switch kind {
            case .same: return Color.secondary.opacity(0.08)
            case .missing: return Theme.warn.opacity(0.25)
            case .extra: return Color.red.opacity(0.15)
            case .swapped: return Theme.level7.opacity(0.2)
            }
        }
    }

    /// Live meter for a 例句朗读 take. Kept apart so the card does not redraw ten times a second.
    fileprivate struct TakeMeter: View {
        @Environment(RecorderService.self) private var recorder

        var body: some View {
            if recorder.isRecording && recorder.owner == "vocab" {
                RecordingMeter(elapsed: recorder.elapsed, level: recorder.level, limit: 60, target: nil)
            }
        }
    }
}
