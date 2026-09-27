import SwiftUI

/// 听词 (VOC-F04, VOC-P06/P07): hands-free listening through saved words and chunks.
/// Each item plays word → a pause to recall → Chinese meaning → the sentence it came from.
/// Only listening records are written (ReviewEvent kind .listen): no review, no schedule change.
struct VocabListenView: View {
    @Environment(VocabStore.self) private var vocab
    @Environment(PackStore.self) private var packs
    @Environment(PlaybackEngine.self) private var engine
    @Environment(RecorderService.self) private var recorder
    @Environment(UserStore.self) private var user
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Which items a round plays.
    private enum ListSource: String, CaseIterable, Identifiable {
        case due, all, starred, recent

        var id: String { rawValue }

        var title: String {
            switch self {
            case .due: return "今日到期"
            case .all: return "全部条目"
            case .starred: return "只看收藏"
            case .recent: return "最近添加"
            }
        }

        var emptyText: String {
            switch self {
            case .due: return "今日暂无到期。可以换成“全部条目”或“最近添加”。"
            case .starred: return "还没有收藏的条目。在“浏览”里点星标就能收藏。"
            case .all, .recent: return "还没有条目。"
            }
        }
    }

    private enum Phase {
        case setup, playing, summary
    }

    /// Where the player is inside one item.
    private enum Stage {
        case word, wait, gloss, sentence

        var title: String {
            switch self {
            case .word: return "听单词"
            case .wait: return "想一想意思"
            case .gloss: return "中文义"
            case .sentence: return "听原句"
            }
        }

        var symbol: String {
            switch self {
            case .word: return "ear"
            case .wait: return "hourglass"
            case .gloss: return "text.bubble"
            case .sentence: return "text.quote"
            }
        }
    }

    /// How one item ended.
    private enum ItemEnd {
        case done, cancelled, interrupted
    }

    private static let recentLimit = 20
    private static let previewLimit = 60
    /// A word without sound stays on screen this long before the pause starts.
    private static let silentWordSeconds = 1.5

    // Setup
    @State private var source: ListSource = .due
    @State private var choseSource = false
    @State private var dueOrder: [String] = []
    @State private var hasEnglishVoice = true
    @State private var hasChineseVoice = true

    // Round
    @State private var phase: Phase = .setup
    @State private var player = SegmentPlayer()
    @State private var loopTask: Task<Void, Never>?
    @State private var playlist: [VocabItem] = []
    @State private var index = 0
    @State private var pass = 1
    @State private var running = false
    @State private var stage: Stage = .word
    @State private var showGloss = false
    @State private var showSentence = false
    @State private var waitEnds = Date()
    @State private var banked: Double = 0          // seconds listened before the current run
    @State private var runStart: Date?             // start of the current run; nil while paused
    @State private var heard: [VocabItem] = []     // finished this round, in first-heard order
    @State private var heardTimes: [String: Int] = [:]
    @State private var picked: Set<String> = []
    @State private var endedByTime = false
    @State private var message: String?

    @ScaledMetric(relativeTo: .largeTitle) private var wordSize: CGFloat = 52

    var body: some View {
        Group {
            if vocab.activeItems.isEmpty && phase == .setup {
                ContentUnavailableView("听词列表是空的", systemImage: "headphones",
                                       description: Text("还没有收藏的词。在听读页点单词，再点“收藏这个义项”。"))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch phase {
                        case .setup: setupSection
                        case .playing: playerSection
                        case .summary: summarySection
                        }
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear {
            refreshVoices()
            loadDue()
            if !choseSource {
                choseSource = true
                if dueOrder.isEmpty { source = .all }
            }
        }
        .onChange(of: recorder.isRecording) { _, recording in
            if recording && running {
                pauseRound(note: "开始录音了，听词已暂停。")
            }
        }
        .onDisappear {
            // Leaving the page stops all sound; the round stays, paused.
            if running || loopTask != nil {
                pauseRound(note: nil)
            }
        }
    }

    // MARK: Setup

    @ViewBuilder
    private var setupSection: some View {
        let list = items(for: source)
        let sounds = list.map { wordSound($0) }
        sourceCard(list, sounds: sounds)
        howCard
        startBlock(count: list.count)
        soundCard
        previewList(list, sounds: sounds)
    }

    private func sourceCard(_ list: [VocabItem], sounds: [ItemAudioSource]) -> some View {
        PracticeCard {
            Text("听哪些词").font(.headline)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(ListSource.allCases) { s in
                    choice("\(s.title) \(items(for: s).count)", selected: source == s) {
                        source = s
                        if s == .due { loadDue() }
                    }
                }
            }
            if list.isEmpty {
                Label(source.emptyText, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text(soundSummary(sounds))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var howCard: some View {
        let s = vocab.settings
        return PracticeCard {
            Text("怎么听").font(.headline)
            modeRow(s)
            orderRow(s)
            gapRow(s)
            rateRow(s)
            roundRow(s)
            Text(s.listenMinutes > 0 ? "时间到了会停下，列出这一轮听过的词。" : "点“停止”结束，再列出这一轮听过的词。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func startBlock(count: Int) -> some View {
        let title = count > 0 ? "开始听词（\(count) 个）" : "开始听词"
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                startRound()
            } label: {
                Label(title, systemImage: "play.fill")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(count == 0 || recorder.isRecording)
            if recorder.isRecording {
                Label("正在录音。录完再开始听词。", systemImage: "record.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let message {
                Label(message, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text("听词只记听过的记录，不算复习，也不改排期。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var soundCard: some View {
        PracticeCard {
            Text("声音").font(.headline)
            Label("原声：从文章朗读里剪出的片段。合成音：iPad 的系统语音。", systemImage: "waveform")
            Label("都能离线听：原声在已导入的内容包里，合成音用这台 iPad 上装好的系统语音。", systemImage: "wifi.slash")
            if !vocab.settings.preferOriginalAudio {
                Label("现在设为不用原声，全部用合成音。", systemImage: "speaker.wave.2")
                    .foregroundStyle(.secondary)
            }
            voiceNotes
        }
        .font(.callout)
    }

    @ViewBuilder
    private var voiceNotes: some View {
        if !hasEnglishVoice {
            Label("这台 iPad 没有英语系统语音，没有原声的词会跳过声音。", systemImage: "speaker.slash")
                .foregroundStyle(Theme.warn)
        }
        if !hasChineseVoice {
            Label("没有中文语音，释义只显示文字。", systemImage: "text.alignleft")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func previewList(_ list: [VocabItem], sounds: [ItemAudioSource]) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(vocab.settings.listenRandom ? "这一轮的词（随机播放）" : "这一轮的词")
                    .font(.headline)
                ForEach(Array(list.prefix(Self.previewLimit).enumerated()), id: \.element.id) { n, item in
                    itemRow(item, sound: n < sounds.count ? sounds[n] : wordSound(item))
                    Divider()
                }
                if list.count > Self.previewLimit {
                    Text("还有 \(list.count - Self.previewLimit) 个，没有列出。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func itemRow(_ item: VocabItem, sound: ItemAudioSource) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                    .font(Font.system(.body, design: .serif).weight(.semibold))
                if !item.gloss.isEmpty {
                    Text(item.gloss)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            soundBadge(sound)
        }
        .padding(.vertical, 2)
    }

    // MARK: Settings rows

    private func modeRow(_ s: VocabSettings) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("模式").font(.subheadline).foregroundStyle(.secondary)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                choice("完整", selected: !s.listenEnglishOnly) {
                    vocab.updateSettings { $0.listenEnglishOnly = false }
                }
                choice("只听英文", selected: s.listenEnglishOnly) {
                    vocab.updateSettings { $0.listenEnglishOnly = true }
                }
            }
            Text(sequenceText(s))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func orderRow(_ s: VocabSettings) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("播放顺序").font(.subheadline).foregroundStyle(.secondary)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                choice("顺序", selected: !s.listenRandom) {
                    vocab.updateSettings { $0.listenRandom = false }
                }
                choice("随机", selected: s.listenRandom) {
                    vocab.updateSettings { $0.listenRandom = true }
                }
            }
        }
    }

    private func gapRow(_ s: VocabSettings) -> some View {
        stepRow("等待", value: "\(number(s.listenGap)) 秒", downLabel: "少等 1 秒", upLabel: "多等 1 秒",
                canDown: s.listenGap > 0, canUp: s.listenGap < 10,
                down: { vocab.updateSettings { $0.listenGap = max(0, ceil($0.listenGap) - 1) } },
                up: { vocab.updateSettings { $0.listenGap = min(10, floor($0.listenGap) + 1) } })
    }

    private func rateRow(_ s: VocabSettings) -> some View {
        stepRow("速度", value: rateText(s.listenRate), downLabel: "放慢一点", upLabel: "加快一点",
                canDown: s.listenRate > 0.751, canUp: s.listenRate < 1.249,
                down: { vocab.updateSettings { $0.listenRate = Self.steppedRate($0.listenRate, by: -0.05) } },
                up: { vocab.updateSettings { $0.listenRate = Self.steppedRate($0.listenRate, by: 0.05) } })
    }

    private func roundRow(_ s: VocabSettings) -> some View {
        let shorter = Self.shorterRound(s.listenMinutes)
        let longer = Self.longerRound(s.listenMinutes)
        return stepRow("一轮", value: roundText(s.listenMinutes), downLabel: "一轮短一点", upLabel: "一轮长一点",
                       canDown: shorter != nil, canUp: longer != nil,
                       down: {
                           if let m = shorter { vocab.updateSettings { $0.listenMinutes = m } }
                       },
                       up: {
                           if let m = longer { vocab.updateSettings { $0.listenMinutes = m } }
                       })
    }

    /// Title, minus, value, plus. Each button is 44 × 44 pt.
    private func stepRow(_ title: String, value: String, downLabel: String, upLabel: String,
                         canDown: Bool, canUp: Bool,
                         down: @escaping () -> Void, up: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            Button(action: down) {
                Image(systemName: "minus")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Theme.paper, in: Circle())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!canDown)
            .accessibilityLabel(downLabel)
            Text(value)
                .font(.body.monospacedDigit())
                .frame(minWidth: 88)
            Button(action: up) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Theme.paper, in: Circle())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!canUp)
            .accessibilityLabel(upLabel)
        }
    }

    /// A choice button. The chosen one has a check mark and a frame, not only a colour.
    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: selected ? "checkmark.circle.fill" : "circle")
                .font(.callout.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(selected ? Theme.accent.opacity(0.14) : Theme.paper,
                            in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(selected ? Theme.accent : Color.secondary.opacity(0.3),
                                      lineWidth: selected ? 2 : 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Player

    @ViewBuilder
    private var playerSection: some View {
        if playlist.indices.contains(index) {
            let item = playlist[index]
            nowCard(item)
            controls(item)
            if let message {
                Label(message, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            roundSettingsCard
            voiceNotes
                .font(.callout)
            Text("听词只记听过的记录，不算复习，也不改排期。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Button {
                backToSetup()
            } label: {
                Label("回到设置", systemImage: "slider.horizontal.3")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private func nowCard(_ item: VocabItem) -> some View {
        let s = vocab.settings
        let word = wordSound(item)
        let sentence = ItemAudio.sentence(item.firstSource, packs: packs, preferOriginal: s.preferOriginalAudio)
        let text = sentenceText(item)
        return PracticeCard {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                stageLabel
                Spacer()
                Text(progressText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(item.text)
                .font(.system(size: wordSize, weight: .semibold, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let pos = item.pos, !pos.isEmpty {
                Text(pos)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            FlowLayout(spacing: 6, lineSpacing: 6) {
                soundBadge(word, prefix: "单词 · ")
                if !s.listenEnglishOnly && !item.gloss.isEmpty {
                    Badge(text: hasChineseVoice ? "中文义 · 合成音" : "中文义 · 只显示文字", outlined: true)
                }
                if text != nil || canPlay(sentence) {
                    soundBadge(sentence, prefix: "原句 · ")
                }
            }
            glossArea(item, englishOnly: s.listenEnglishOnly)
            if showSentence, let text {
                Text(markedSentence(text, occurrence: item.firstSource))
                    .font(Theme.readingFont(size: Theme.readingPointSize(user.settings.fontSize, typeSize: typeSize)))
                    .lineSpacing(6)
                    .textSelection(.enabled)
            }
        }
    }

    /// Current step, with the seconds left while waiting.
    private var stageLabel: some View {
        TimelineView(.periodic(from: Date(), by: 0.5)) { context in
            if running {
                Label(stageText(at: context.date), systemImage: stage.symbol)
                    .font(.headline)
            } else {
                Label("已暂停", systemImage: "pause.circle")
                    .font(.headline)
            }
        }
    }

    @ViewBuilder
    private func glossArea(_ item: VocabItem, englishOnly: Bool) -> some View {
        if englishOnly {
            Text("只听英文：不读中文义。")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if item.gloss.isEmpty {
            EmptyView()
        } else if showGloss {
            Text(item.gloss)
                .font(.title2)
                .textSelection(.enabled)
        } else {
            Text(running && stage == .gloss ? "正在读中文义……" : "先想一想意思，中文义稍后出现。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func controls(_ item: VocabItem) -> some View {
        let queued = vocab.isTaskEnabled(.listen, for: item.id)
        return VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 10, lineSpacing: 10) {
                Button {
                    if running {
                        pauseRound(note: nil)
                    } else {
                        resumeRound()
                    }
                } label: {
                    Label(running ? "暂停" : "继续", systemImage: running ? "pause.fill" : "play.fill")
                        .frame(minWidth: 88, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!running && recorder.isRecording)

                Button {
                    skipItem()
                } label: {
                    Label("跳过", systemImage: "forward.fill")
                        .frame(minHeight: 44)
                }

                Button {
                    finishRound(timeUp: false)
                } label: {
                    Label("停止", systemImage: "stop.fill")
                        .frame(minHeight: 44)
                }

                Button {
                    addToPractice(item)
                } label: {
                    Label(queued ? "已在待练" : "加入待练", systemImage: queued ? "checkmark.circle.fill" : "plus.circle")
                        .frame(minHeight: 44)
                }
                .disabled(queued)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            TimelineView(.periodic(from: Date(), by: 0.5)) { context in
                Text(clockText(at: context.date))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Settings that can change during a round; list and order wait for the next round.
    private var roundSettingsCard: some View {
        let s = vocab.settings
        return PracticeCard {
            Text("边听边调").font(.headline)
            modeRow(s)
            gapRow(s)
            rateRow(s)
            roundRow(s)
            Text("改动从下一步开始生效。列表和顺序在下一轮再改。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Summary

    @ViewBuilder
    private var summarySection: some View {
        let times = heard.reduce(0) { $0 + (heardTimes[$1.id] ?? 1) }
        let convertTitle = picked.isEmpty ? "把勾选的转成主动回忆" : "把勾选的转成主动回忆（\(picked.count) 个）"
        PracticeCard {
            Label(endedByTime ? "本轮时间到" : "这一轮结束了", systemImage: "checkmark.circle")
                .font(.headline)
            Text("听了 \(heard.count) 个词，共 \(times) 遍，用时 \(formatTime(banked))。")
            Text("听词只记听过的记录，不算复习，也不改排期。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("想记牢的，勾几个转成主动回忆（认义和听辨）。挑少量就好。")
                .font(.callout)
        }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(heard) { item in
                checkRow(item)
                Divider()
            }
        }
        FlowLayout(spacing: 10, lineSpacing: 10) {
            Button {
                convertPicked()
            } label: {
                Label(convertTitle, systemImage: "brain.head.profile")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(picked.isEmpty)

            Button {
                startRound()
            } label: {
                Label("再听一轮", systemImage: "arrow.counterclockwise")
                    .frame(minHeight: 44)
            }
            .disabled(recorder.isRecording)

            Button {
                backToSetup()
            } label: {
                Label("回到设置", systemImage: "slider.horizontal.3")
                    .frame(minHeight: 44)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        if let message {
            Label(message, systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// One heard item with a check box (symbol plus spoken value, not only a colour).
    private func checkRow(_ item: VocabItem) -> some View {
        let on = picked.contains(item.id)
        let times = heardTimes[item.id] ?? 1
        let open = [VocabTask.recognize, .listen].filter { vocab.isTaskEnabled($0, for: item.id) }.map(\.title)
        var detail = open.isEmpty ? "还没有复习任务" : "已开：" + open.joined(separator: "、")
        if times > 1 { detail = "听了 \(times) 遍 · " + detail }
        return Button {
            if on {
                _ = picked.remove(item.id)
            } else {
                _ = picked.insert(item.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.title2)
                    .foregroundStyle(on ? Theme.accent : Color.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.text)
                        .font(Font.system(.body, design: .serif).weight(.semibold))
                    if !item.gloss.isEmpty {
                        Text(item.gloss)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(on ? "已勾选" : "未勾选")
    }

    // MARK: Round

    private func startRound() {
        guard !recorder.isRecording else {
            message = "正在录音。录完再开始听词。"
            return
        }
        refreshVoices()
        loadDue()
        let list = items(for: source)
        guard !list.isEmpty else {
            phase = .setup
            message = source.emptyText
            return
        }
        loopTask?.cancel()
        loopTask = nil
        ItemAudio.stop(player: player)
        playlist = vocab.settings.listenRandom ? list.shuffled() : list
        index = 0
        pass = 1
        heard = []
        heardTimes = [:]
        picked = []
        banked = 0
        runStart = nil
        running = false
        endedByTime = false
        stage = .word
        showGloss = false
        showSentence = false
        message = nil
        phase = .playing
        resumeRound()
    }

    private func resumeRound() {
        guard phase == .playing, !running, !playlist.isEmpty else { return }
        guard !recorder.isRecording else {
            message = "正在录音。录完再听。"
            return
        }
        engine.pause()
        message = nil
        running = true
        runStart = Date()
        runLoop()
    }

    /// Stops the sound and the round clock. The current item starts again on 继续.
    private func pauseRound(note: String?) {
        loopTask?.cancel()
        loopTask = nil
        ItemAudio.stop(player: player)
        if let start = runStart {
            banked += Date().timeIntervalSince(start)
        }
        runStart = nil
        running = false
        if let note { message = note }
    }

    private func finishRound(timeUp: Bool) {
        pauseRound(note: nil)
        endedByTime = timeUp
        if heard.isEmpty {
            phase = .setup
            message = timeUp ? "本轮时间到了，还没有听完一个词。" : nil
            loadDue()
        } else {
            message = nil
            phase = .summary
        }
    }

    private func skipItem() {
        let wasRunning = running
        loopTask?.cancel()
        loopTask = nil
        ItemAudio.stop(player: player)
        advance()
        stage = .word
        showGloss = false
        showSentence = false
        if wasRunning { runLoop() }
    }

    /// Next item; after the last one the list starts again (a new shuffle in 随机).
    private func advance() {
        guard !playlist.isEmpty else { return }
        if index + 1 < playlist.count {
            index += 1
            return
        }
        if vocab.settings.listenRandom && playlist.count > 1 {
            let lastId = playlist[playlist.count - 1].id
            var next = playlist.shuffled()
            if next.first?.id == lastId {
                next.swapAt(0, next.count - 1)
            }
            playlist = next
        }
        index = 0
        pass += 1
    }

    /// Plays items until the round time is up, or until pause / skip / stop cancels the task.
    /// The round time is checked between items, so an item is never cut off.
    private func runLoop() {
        loopTask?.cancel()
        let player = self.player
        loopTask = Task {
            while !Task.isCancelled {
                if timeIsUp(at: Date()) {
                    finishRound(timeUp: true)
                    return
                }
                guard playlist.indices.contains(index) else {
                    finishRound(timeUp: false)
                    return
                }
                let item = playlist[index]
                let end = await playItem(item, player: player)
                if Task.isCancelled { return }
                switch end {
                case .done:
                    advance()
                case .interrupted:
                    pauseRound(note: "声音停了，可能被别的声音打断。已暂停：点“继续”重听这个词，或点“跳过”。")
                    return
                case .cancelled:
                    return
                }
            }
        }
    }

    /// One item: word → pause → meaning (完整 only) → sentence, then a listening record.
    /// Settings are read at each step, so changes made during a round apply from the next step.
    /// Every await is followed by a cancellation check before any state changes.
    private func playItem(_ item: VocabItem, player: SegmentPlayer) async -> ItemEnd {
        stage = .word
        showGloss = false
        showSentence = false
        var soundUsed: String?      // "clip" or "tts": the first English sound heard, normally the word

        // The word or chunk.
        let word = wordSound(item)
        if canPlay(word) {
            let ok = await ItemAudio.play(word, player: player, language: "en-GB", rate: vocab.settings.listenRate)
            if Task.isCancelled { return .cancelled }
            if !ok { return .interrupted }
            soundUsed = word.isOriginal ? "clip" : "tts"
        } else {
            guard await hold(Self.silentWordSeconds) else { return .cancelled }
        }

        // Time to recall the meaning.
        let gap = min(10, max(0, vocab.settings.listenGap))
        if gap > 0 {
            waitEnds = Date().addingTimeInterval(gap)
            stage = .wait
            guard await hold(gap) else { return .cancelled }
        }

        // The Chinese meaning. Without a Chinese voice it is shown as text only.
        let gloss = item.gloss.trimmingCharacters(in: .whitespacesAndNewlines)
        if !vocab.settings.listenEnglishOnly && !gloss.isEmpty {
            stage = .gloss
            if hasChineseVoice {
                AudioSessionControl.usePlayback()
                let ok = await SpeechQueue.shared.speak(gloss, language: "zh-CN")
                if Task.isCancelled { return .cancelled }
                if !ok { return .interrupted }
                showGloss = true
                guard await hold(0.6) else { return .cancelled }
            } else {
                showGloss = true
                guard await hold(gap) else { return .cancelled }
            }
        }

        // The sentence the item was met in.
        let sentence = ItemAudio.sentence(item.firstSource, packs: packs,
                                          preferOriginal: vocab.settings.preferOriginalAudio)
        let text = sentenceText(item)
        if canPlay(sentence) {
            stage = .sentence
            showSentence = true
            let ok = await ItemAudio.play(sentence, player: player, language: "en-GB", rate: vocab.settings.listenRate)
            if Task.isCancelled { return .cancelled }
            if !ok { return .interrupted }
            if soundUsed == nil { soundUsed = sentence.isOriginal ? "clip" : "tts" }
        } else if let text {
            stage = .sentence
            showSentence = true
            guard await hold(Self.readingSeconds(text)) else { return .cancelled }
        }

        // A listening record only: not a review, no schedule change.
        // Nothing is recorded when no English sound could be played at all.
        if let soundUsed {
            vocab.recordListen(itemId: item.id, source: soundUsed)
            noteHeard(item)
        }
        guard await hold(0.8) else { return .cancelled }
        return .done
    }

    /// Waits; false when the round was paused, skipped or stopped meanwhile.
    private func hold(_ seconds: Double) async -> Bool {
        if seconds > 0, seconds.isFinite {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
        return !Task.isCancelled
    }

    private func noteHeard(_ item: VocabItem) {
        if heardTimes[item.id] == nil {
            heard.append(item)
        }
        heardTimes[item.id, default: 0] += 1
    }

    /// 加入待练: opens the 听辨 task (VOC-T02) for this item.
    private func addToPractice(_ item: VocabItem) {
        vocab.ensureCards(itemId: item.id, tasks: [.listen])
        message = "已加入待练：“\(item.text)”打开了听辨任务。"
    }

    private func convertPicked() {
        let ids = heard.map(\.id).filter { picked.contains($0) }
        guard !ids.isEmpty else { return }
        for id in ids {
            vocab.ensureCards(itemId: id, tasks: [.recognize, .listen])
        }
        picked = []
        message = "已转成主动回忆：\(ids.count) 个（打开了认义和听辨），会排进复习。"
    }

    private func backToSetup() {
        phase = .setup
        message = nil
        loadDue()
    }

    // MARK: Data

    private func items(for kind: ListSource) -> [VocabItem] {
        let active = vocab.activeItems
        switch kind {
        case .due:
            var byId: [String: VocabItem] = [:]
            for item in active { byId[item.id] = item }
            return dueOrder.compactMap { byId[$0] }
        case .all:
            return active
        case .starred:
            return active.filter { $0.starred }
        case .recent:
            return Array(active.sorted { $0.created > $1.created }.prefix(Self.recentLimit))
        }
    }

    /// Items with a card in today's queue, in queue order. Called from actions only:
    /// the first queue of a day records the day's load.
    private func loadDue() {
        var seen = Set<String>()
        var order: [String] = []
        for entry in vocab.queue().entries {
            let id = entry.card.itemId
            if seen.insert(id).inserted {
                order.append(id)
            }
        }
        dueOrder = order
    }

    private func refreshVoices() {
        hasEnglishVoice = SpeechQueue.hasVoice("en-GB")
        hasChineseVoice = SpeechQueue.hasVoice("zh-CN")
    }

    private func wordSound(_ item: VocabItem) -> ItemAudioSource {
        ItemAudio.word(item, occurrence: nil, packs: packs, preferOriginal: vocab.settings.preferOriginalAudio)
    }

    /// Synthesised English needs an English voice; without one that sound is skipped.
    private func canPlay(_ sound: ItemAudioSource) -> Bool {
        switch sound {
        case .clip: return true
        case .tts: return hasEnglishVoice
        case .none: return false
        }
    }

    /// The sentence as saved with the item; the pack's text only when no snapshot was kept.
    private func sentenceText(_ item: VocabItem) -> String? {
        guard let o = item.firstSource else { return nil }
        if let saved = o.sentence, !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return saved
        }
        guard o.unmapped != true, let s = packs.sentence(o.ref, sid: o.sid) else { return nil }
        let plain = SentenceText.plain(s)
        return plain.isEmpty ? nil : plain
    }

    private func listened(at now: Date) -> Double {
        banked + (runStart.map { now.timeIntervalSince($0) } ?? 0)
    }

    private func timeIsUp(at now: Date) -> Bool {
        let limit = vocab.settings.listenMinutes * 60
        return limit > 0 && listened(at: now) >= limit
    }

    // MARK: Text

    private var progressText: String {
        var text = "第 \(index + 1) / \(playlist.count) 个"
        if pass > 1 { text += " · 第 \(pass) 遍" }
        return text
    }

    private func stageText(at now: Date) -> String {
        guard stage == .wait else { return stage.title }
        let left = Int(max(0, waitEnds.timeIntervalSince(now)).rounded(.up))
        return left > 0 ? "\(stage.title) · \(left) 秒" : stage.title
    }

    private func clockText(at now: Date) -> String {
        let spent = listened(at: now)
        let limit = vocab.settings.listenMinutes * 60
        var parts: [String] = []
        if limit > 0 {
            let left = limit - spent
            if left > 0 {
                parts.append("本轮还剩 \(formatTime(left.rounded(.up)))")
            } else {
                parts.append(running ? "时间到，放完这个词就停" : "时间到")
            }
        } else {
            parts.append("已听 \(formatTime(spent)) · 手动结束")
        }
        if !running { parts.append("已暂停") }
        return parts.joined(separator: " · ")
    }

    private func sequenceText(_ s: VocabSettings) -> String {
        var steps = ["单词"]
        if s.listenGap > 0 { steps.append("等 \(number(s.listenGap)) 秒") }
        if !s.listenEnglishOnly { steps.append("中文义") }
        steps.append("原句")
        return (s.listenEnglishOnly ? "只听英文：" : "完整：") + steps.joined(separator: " → ")
    }

    private func soundLabel(_ sound: ItemAudioSource) -> String {
        if case .tts = sound, !hasEnglishVoice { return "没有声音" }
        return sound.label
    }

    private func soundBadge(_ sound: ItemAudioSource, prefix: String = "") -> some View {
        Badge(text: prefix + soundLabel(sound), color: sound.isOriginal ? Theme.level5 : nil, outlined: true)
    }

    private func soundSummary(_ sounds: [ItemAudioSource]) -> String {
        let clips = sounds.filter { $0.isOriginal }.count
        let silent = sounds.filter { !canPlay($0) }.count
        var parts = ["共 \(sounds.count) 个", "原声 \(clips) 个", "合成音 \(sounds.count - clips - silent) 个"]
        if silent > 0 { parts.append("没有声音 \(silent) 个") }
        return parts.joined(separator: " · ")
    }

    /// The sentence with the item marked by background and underline.
    private func markedSentence(_ text: String, occurrence: Occurrence?) -> AttributedString {
        guard let o = occurrence, let surface = o.surface, !surface.isEmpty,
              let r = SentenceText.range(of: surface, in: text, near: o.start ?? 0) else {
            return AttributedString(text)
        }
        var out = AttributedString(String(text[..<r.lowerBound]))
        var hit = AttributedString(String(text[r]))
        hit.backgroundColor = Theme.currentWord
        hit.underlineStyle = Text.LineStyle(pattern: .solid, color: Theme.accent)
        out += hit
        out += AttributedString(String(text[r.upperBound...]))
        return out
    }

    private func number(_ x: Double) -> String {
        String(format: "%g", x)
    }

    private func rateText(_ r: Double) -> String {
        abs(r - 1) < 0.001 ? "1.0×" : String(format: "%g×", r)
    }

    private func roundText(_ m: Double) -> String {
        m > 0 ? "\(number(m)) 分钟" : "手动结束"
    }

    /// Time to read a sentence that has no sound.
    private static func readingSeconds(_ text: String) -> Double {
        min(10, max(2.5, Double(text.count) / 15))
    }

    private static func steppedRate(_ r: Double, by step: Double) -> Double {
        min(1.25, max(0.75, ((r + step) * 100).rounded() / 100))
    }

    /// Round lengths go 5, 10 … 30 minutes, then 手动结束 (0).
    private static func longerRound(_ m: Double) -> Double? {
        if m <= 0 { return nil }
        if m >= 30 { return 0 }
        return min(30, (floor(m / 5) + 1) * 5)
    }

    private static func shorterRound(_ m: Double) -> Double? {
        if m <= 0 { return 30 }
        if m <= 5 { return nil }
        return max(5, (ceil(m / 5) - 1) * 5)
    }
}
