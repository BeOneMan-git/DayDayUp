import SwiftUI
import UIKit
import AVFoundation

/// 跟读工作台 (PAGE-04, UI-01). Four modes with different goals (SHD-F01…F04):
/// 听后模仿 one sentence: listen → record → A/B; 影子跟读 speak along with the original;
/// 独立朗读 read a sentence or a paragraph without hearing it first; 脱稿复述 hide the text, retell,
/// answer one follow-up question, then compare with the text.
/// Pronunciation layers are drawn on the text (SHD-A01…A07). Every take is kept as a practice record;
/// nothing is scored.
struct ShadowView: View {
    @Environment(PackStore.self) private var packs
    @Environment(UserStore.self) private var user
    @Environment(PracticeStore.self) private var practice
    @Environment(AnnotationStore.self) private var annotations
    @Environment(RecorderService.self) private var recorder
    @Environment(PlaybackEngine.self) private var engine
    @Environment(Router.self) private var router
    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo: .title2) private var baseFontSize: CGFloat = 24

    @State private var ref: ArticleRef?
    @State private var article: Article?
    @State private var sentences: [Sent] = []
    @State private var paraOf: [Int] = []           // paragraph number (0-based) of each sentence
    @State private var index = 0
    @State private var player = SegmentPlayer()
    @State private var showZh = false
    @State private var message: String?
    @State private var showPicker = false
    @State private var loadError: String?
    @State private var showLayerGuide = false

    // Segment choices per mode
    @State private var shadowLength = 1             // 影子跟读: 1–3 sentences
    @State private var readWhole = false            // 独立朗读: false = 这一句, true = 这一段
    @State private var retellSpan = 0               // 脱稿复述: 0 = 这一段, 1–3 = sentences

    // Takes
    @State private var allModes = false
    @State private var lastTakeId: String?          // the take of this visit, for 本次录音状态
    @State private var playingKey: String?          // take id (or "follow:<id>") being played back
    @State private var recLimit: Double = 60
    @State private var recTarget: Double?
    @State private var recWhat = ""
    @State private var shadowRun: Task<Void, Never>?

    // Where the sound goes (ACC-17)
    @State private var speakerOut = false
    @State private var outputName = ""

    // 脱稿复述
    @State private var retellStep: ShadowRetellStep = .prepare
    @State private var retellTakeId: String?
    @State private var hintsShown: [String] = []
    @State private var noteDraft = ""
    @State private var noteSaved = false

    var body: some View {
        Group {
            if let article, let ref, !sentences.isEmpty {
                workbench(article, ref)
            } else if article != nil {
                ContentUnavailableView("这篇还不能跟读", systemImage: "waveform.slash",
                                       description: Text("内容包里没有这篇的句子时间轴。换一篇试试。"))
            } else if let loadError {
                ContentUnavailableView("打不开这篇文章", systemImage: "exclamationmark.triangle",
                                       description: Text(loadError))
            } else {
                ArticlePickerList { picked in load(picked, sid: nil) }
            }
        }
        .navigationTitle("跟读")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showPicker = true
                } label: {
                    Label("换一篇", systemImage: "books.vertical")
                }
                .disabled(recordingHere)
            }
        }
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                ArticlePickerList { picked in
                    load(picked, sid: nil)
                    showPicker = false
                }
                .navigationTitle("选一篇文章")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showPicker = false }
                    }
                }
            }
            .environment(packs)
            .environment(practice)
        }
        .onAppear {
            recorder.refreshPermission()
            refreshRoute()
            if router.shadowTarget != nil {
                consumeTarget()
            } else if ref == nil {
                loadDefault()
            }
        }
        .onChange(of: router.shadowRequestID) { _, _ in consumeTarget() }
        .onChange(of: shadowLength) { _, _ in segmentChanged() }
        .onChange(of: readWhole) { _, _ in segmentChanged() }
        .onChange(of: retellSpan) { _, _ in segmentChanged() }
        .task { await watchRoute() }
        .onDisappear {
            shadowRun?.cancel()
            shadowRun = nil
            player.stop()
            playingKey = nil
            if recorder.owner == "shadow" { recorder.stop() }
            AudioSessionControl.endShadowing()
            AudioSessionControl.usePlayback()
        }
    }

    // MARK: Layout (UI-01)

    /// Wide (≥ 1000 pt): text and controls on the left, 本次录音状态 / takes / notes on the right.
    /// Narrower: one column with the controls pinned to the bottom.
    @ViewBuilder
    private func workbench(_ art: Article, _ ref: ArticleRef) -> some View {
        let seg = segment()
        GeometryReader { geo in
            if geo.size.width >= 1000 {
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                header(art, ref, seg)
                                segmentCard(ref, seg)
                                modePanel(seg)
                            }
                            .padding(24)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        controlsBar(seg)
                    }
                    .frame(maxWidth: .infinity)
                    Divider()
                    ScrollView {
                        sideColumn(seg)
                            .padding(16)
                    }
                    .frame(width: 320)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(art, ref, seg)
                        segmentCard(ref, seg)
                        statusCard(seg)
                        modePanel(seg)
                        takesList(seg)
                        notesCard
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    controlsBar(seg)
                }
            }
        }
    }

    private func sideColumn(_ seg: ShadowSegment) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            statusCard(seg)
            takesList(seg)
            notesCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Header: title, mode, range, layers

    private func header(_ art: Article, _ ref: ArticleRef, _ seg: ShadowSegment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(art.issue) · \(art.section)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(art.title)
                        .font(Font.system(.title3, design: .serif).weight(.semibold))
                }
                Spacer(minLength: 8)
                Button {
                    router.openArticle(ref)
                } label: {
                    Label("回到原文", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(recordingHere)
            }
            Picker("练习模式", selection: modeBinding) {
                ForEach(ShadowMode.allCases) { m in
                    Text(m.title).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .disabled(recorder.isBusy)
            Text("\(mode.english)：\(mode.detail)")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Label(rangeText(seg), systemImage: "text.alignleft")
                if let d = seg.duration {
                    Text("· 原音 \(String(format: "%.1f", d)) 秒")
                }
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            layerBar(ref)
        }
    }

    /// Seven layer switches, remembered per mode (UI-P05).
    @ViewBuilder
    private func layerBar(_ ref: ArticleRef) -> some View {
        let available = packs.resources(ref).annotations == .available
        let on = annotations.layers(for: mode)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text("发音标注")
                    .font(.subheadline.weight(.semibold))
                Text("每个模式分别记住")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button {
                    showLayerGuide = true
                } label: {
                    Label("标注说明", systemImage: "questionmark.circle")
                        .font(.callout)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $showLayerGuide) {
                    ShadowLayerGuide()
                }
            }
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(AnnLayer.allCases) { layer in
                    Toggle(isOn: layerBinding(layer)) {
                        Label(layer.title, systemImage: on.contains(layer) ? "checkmark.circle.fill" : "circle")
                    }
                    .toggleStyle(.button)
                    .accessibilityHint(layer.detail)
                }
                Button("入门预设") {
                    annotations.applyBeginnerPreset(for: mode)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("打开意群、重音、连读")
                Button("默认") {
                    annotations.resetLayers(for: mode)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("回到默认：只开意群和重音")
            }
            .controlSize(.large)
            .disabled(!available)
            if available {
                Text("点带记号的词，看说明，也可以核对、隐藏或报错。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("这篇没有发音标注，开关先不能用。", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func layerBinding(_ layer: AnnLayer) -> Binding<Bool> {
        Binding(get: { annotations.layers(for: mode).contains(layer) },
                set: { annotations.setLayer(layer, on: $0, for: mode) })
    }

    // MARK: The text

    @ViewBuilder
    private func segmentCard(_ ref: ArticleRef, _ seg: ShadowSegment) -> some View {
        let textHidden = mode == .retell && (retellStep == .speaking || retellStep == .answering)
        let layers = annotations.layers(for: mode)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(seg.isLong ? "这一段" : "这一句")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !textHidden {
                    Button {
                        showZh.toggle()
                    } label: {
                        Text(showZh ? "收起译文" : "译文")
                            .font(.callout)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                }
            }
            if textHidden {
                VStack(alignment: .leading, spacing: 8) {
                    Label("原文已收起", systemImage: "eye.slash")
                        .font(.headline)
                    Text("用自己的话讲主旨和要点，可以改写、压缩。讲完再对照原文。")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            } else {
                ForEach(Array(seg.sents.enumerated()), id: \.element.id) { n, s in
                    VStack(alignment: .leading, spacing: 6) {
                        AnnotatedSentenceView(ref: ref, sentence: s, layers: layers, fontSize: fontSize,
                                              mode: mode, showsArticleNote: n == 0)
                        if showZh, let zh = s.zh, !zh.isEmpty {
                            Text(zh)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Mode options

    @ViewBuilder
    private func modePanel(_ seg: ShadowSegment) -> some View {
        switch mode {
        case .repeatAfter:
            PracticeCard {
                rateRow(seg, listenEnabled: true)
                Text("先听原句，再录音模仿。可以放慢原音，不要求跟主播同速。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .shadowing:
            PracticeCard {
                Picker("片段长度", selection: $shadowLength) {
                    Text("1 句").tag(1)
                    Text("加长到 2 句").tag(2)
                    Text("加长到 3 句").tag(3)
                }
                .pickerStyle(.segmented)
                .controlSize(.large)
                .disabled(recorder.isBusy)
                if speakerOut && !recordingHere {
                    speakerWarning
                }
                rateRow(seg, listenEnabled: true)
                Text("“先不录，跟着念”只放原音。“录音跟读”边放原音边录，原音放完约 1 秒后自动停。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .readAloud:
            PracticeCard {
                Picker("朗读范围", selection: $readWhole) {
                    Text("这一句").tag(false)
                    Text("这一段").tag(true)
                }
                .pickerStyle(.segmented)
                .controlSize(.large)
                .disabled(recorder.isBusy)
                Text("先不放原音，看着文字自己读。读完可以听原音对照，或者做 A/B。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                rateRow(seg, listenEnabled: hasVoicedTake(seg))
            }
        case .retell:
            retellPanel(seg)
        }
    }

    /// Speed of the original (SHD-P01), a 1.0× button, and the A/B gap (SHD-P05).
    private func rateRow(_ seg: ShadowSegment, listenEnabled: Bool) -> some View {
        FlowLayout(spacing: 10, lineSpacing: 10) {
            Menu {
                ForEach(ReaderSettings.shadowRates, id: \.self) { r in
                    Button {
                        user.updateSettings { $0.shadowRate = r }
                    } label: {
                        if abs(r - user.settings.shadowRate) < 0.001 {
                            Label(rateText(r), systemImage: "checkmark")
                        } else {
                            Text(rateText(r))
                        }
                    }
                }
            } label: {
                Label("原音速度 \(rateText(user.settings.shadowRate))", systemImage: "speedometer")
            }
            Button {
                playOriginal(seg, rate: 1.0, toggles: false)
            } label: {
                Label("1.0× 原速", systemImage: "play")
            }
            .disabled(!listenEnabled || seg.start == nil)
            if mode != .retell {
                Menu {
                    ForEach(ReaderSettings.abGaps, id: \.self) { g in
                        Button {
                            user.updateSettings { $0.abGap = g }
                        } label: {
                            if abs(g - user.settings.abGap) < 0.001 {
                                Label(gapText(g), systemImage: "checkmark")
                            } else {
                                Text(gapText(g))
                            }
                        }
                    }
                } label: {
                    Label("A/B 间隔 \(gapText(user.settings.abGap))", systemImage: "timer")
                }
            }
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private var speakerWarning: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.title2)
                .foregroundStyle(Theme.warn)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("外放提醒")
                    .font(.headline)
                Text("声音从 iPad 扬声器放出来，原音可能串进录音。建议戴耳机；这样录的会标“可能串音”，不进入任何诊断。")
                    .font(.callout)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: 脱稿复述 (SHD-F04, SHD-P06)

    @ViewBuilder
    private func retellPanel(_ seg: ShadowSegment) -> some View {
        let words = retellKeywords(seg.sents)
        let question = retellFollowUp(key: followKey(seg))
        PracticeCard {
            Picker("复述范围", selection: $retellSpan) {
                Text("这一段").tag(0)
                Text("1 句").tag(1)
                Text("2 句").tag(2)
                Text("3 句").tag(3)
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .disabled(retellStep != .prepare || recorder.isBusy)
            retellSteps
            switch retellStep {
            case .prepare:
                Text("① 先听原文、看原文，抓住主旨和两三个要点。准备好了点“开始复述”：原文会收起，同时开始录音。")
                    .font(.callout)
                rateRow(seg, listenEnabled: true)
                retellTimeRow
            case .speaking:
                Text("② 用自己的话讲主旨和要点。目标 \(Int(user.settings.retellSeconds)) 秒，到了也可以接着讲。讲完点“讲完了”。")
                    .font(.callout)
                hintsRow(words)
            case .answering:
                Text("③ 回答一个追问，也可以跳过：")
                    .font(.callout)
                VStack(alignment: .leading, spacing: 4) {
                    Text(question.en)
                        .font(Font.system(.title3, design: .serif).weight(.semibold))
                        .textSelection(.enabled)
                    Text(question.zh)
                        .foregroundStyle(.secondary)
                }
                if !hintsShown.isEmpty {
                    Text("刚才看过的提示：\(hintsShown.joined(separator: " · "))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !recordingHere {
                    Button {
                        skipFollowUp(question.en)
                    } label: {
                        Label("跳过追问", systemImage: "forward")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(recorder.isBusy)
                }
            case .compare:
                compareSection
            }
        }
    }

    private var retellSteps: some View {
        let steps: [(step: ShadowRetellStep, title: String)] = [
            (.prepare, "① 先听/读"), (.speaking, "② 复述"), (.answering, "③ 追问"), (.compare, "④ 对照原文"),
        ]
        return FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(steps.indices, id: \.self) { n in
                let current = steps[n].step == retellStep
                Text(current ? "\(steps[n].title)（当前）" : steps[n].title)
                    .font(.caption.weight(current ? .semibold : .regular))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(current ? Theme.accent.opacity(0.15) : Theme.chip, in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var retellTimeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Menu {
                ForEach(ReaderSettings.retellTimes, id: \.self) { t in
                    Button {
                        user.updateSettings { $0.retellSeconds = t }
                    } label: {
                        if abs(t - user.settings.retellSeconds) < 0.5 {
                            Label("\(Int(t)) 秒", systemImage: "checkmark")
                        } else {
                            Text("\(Int(t)) 秒")
                        }
                    }
                }
            } label: {
                Label("目标时长 \(Int(user.settings.retellSeconds)) 秒", systemImage: "timer")
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .controlSize(.large)
            Text("基础 30–60 秒，发展 60–120 秒。时间只是练习支架，到了可以接着讲。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func hintsRow(_ words: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !hintsShown.isEmpty {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(hintsShown, id: \.self) { w in
                        Badge(text: w, outlined: true)
                    }
                }
            }
            if words.isEmpty {
                Text("这段找不到合适的关键词提示。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    revealHint(words)
                } label: {
                    Label(hintsShown.count >= words.count ? "提示已经全部打开"
                          : "关键词提示（已看 \(hintsShown.count)/\(words.count)）",
                          systemImage: "lightbulb")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(hintsShown.count >= words.count)
                Text("每看一个提示，都会记在这次录音里。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var compareSection: some View {
        Text("④ 对照原文：原文已经放回上面。看看主旨和要点讲到了没有。")
            .font(.callout)
        Label("复述允许改写和压缩，这里不算逐词一致率。", systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(.secondary)
        if let take = retellTake {
            FlowLayout(spacing: 10, lineSpacing: 10) {
                Button {
                    togglePlayTake(take)
                } label: {
                    Label(isPlaying(take) ? "停止" : "回放复述", systemImage: isPlaying(take) ? "stop.fill" : "play.fill")
                }
                .disabled(practice.recordingURL(take.file) == nil)
                if practice.recordingURL(take.followFile) != nil {
                    Button {
                        togglePlayFollow(take)
                    } label: {
                        Label(isPlayingFollow(take) ? "停止" : "回放追问回答",
                              systemImage: isPlayingFollow(take) ? "stop.fill" : "play.fill")
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            TextField("我注意到……（漏了哪个要点、哪里卡住、想换的说法）", text: $noteDraft, axis: .vertical)
                .lineLimit(2...6)
                .textFieldStyle(.roundedBorder)
                .onChange(of: noteDraft) { _, _ in noteSaved = false }
            HStack(spacing: 12) {
                Button {
                    saveSelfNote(take.id)
                } label: {
                    Label("保存笔记", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                if noteSaved {
                    Label("已保存", systemImage: "checkmark.circle")
                        .font(.callout)
                }
            }
        }
    }

    // MARK: Controls (fixed at the bottom)

    private func controlsBar(_ seg: ShadowSegment) -> some View {
        VStack(spacing: 0) {
            Divider()
            ViewThatFits(in: .horizontal) {
                controlsRow(seg)
                    .labelStyle(.titleAndIcon)
                controlsRow(seg)
                    .labelStyle(.iconOnly)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    private func controlsRow(_ seg: ShadowSegment) -> some View {
        HStack(spacing: 10) {
            Button {
                move(-1)
            } label: {
                Label(seg.isLong ? "上一段" : "上一句", systemImage: "backward.end.fill")
            }
            .disabled(seg.first <= 0 || recorder.isBusy)
            Spacer(minLength: 8)
            modeButtons(seg)
            Spacer(minLength: 8)
            Button {
                move(1)
            } label: {
                Label(seg.isLong ? "下一段" : "下一句", systemImage: "forward.end.fill")
            }
            .disabled(seg.last >= sentences.count - 1 || recorder.isBusy)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    @ViewBuilder
    private func modeButtons(_ seg: ShadowSegment) -> some View {
        switch mode {
        case .repeatAfter:
            listenButton(seg, title: "听原句")
            recordButton(title: "录音") { toggleRecord(seg) }
            abButton(seg)
        case .shadowing:
            listenButton(seg, title: "先不录，跟着念")
            recordButton(title: "录音跟读") {
                if recordingHere { stopTake() } else { startShadowTake(seg) }
            }
            abButton(seg)
        case .readAloud:
            recordButton(title: "录音") { toggleRecord(seg) }
            listenButton(seg, title: seg.isLong ? "听原段对照" : "听原句对照")
                .disabled(!hasVoicedTake(seg))
            abButton(seg)
        case .retell:
            listenButton(seg, title: "听原文")
                .disabled(retellStep == .speaking || retellStep == .answering)
            retellMainButton(seg)
        }
    }

    private func listenButton(_ seg: ShadowSegment, title: String) -> some View {
        let active = player.playing == .original && !recordingHere
        return Button {
            playOriginal(seg, rate: user.settings.shadowRate)
        } label: {
            Label(active ? "停止" : title, systemImage: active ? "stop.fill" : "play.fill")
        }
        .disabled(seg.start == nil || seg.end == nil)
    }

    private func recordButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(recordingHere ? "停止录音" : title,
                  systemImage: recordingHere ? "stop.circle.fill" : "record.circle")
        }
        .buttonStyle(.borderedProminent)
        .tint(recordingHere ? .red : Theme.accent)
        .disabled(!recordingHere && recorder.isBusy)
    }

    private func abButton(_ seg: ShadowSegment) -> some View {
        Button {
            playAB(seg)
        } label: {
            Label("A/B 对照", systemImage: "arrow.left.arrow.right")
        }
        .disabled(abTake(seg) == nil || seg.start == nil || seg.end == nil)
        .accessibilityHint("先放原音，停一下，再放你最近的一次录音")
    }

    @ViewBuilder
    private func retellMainButton(_ seg: ShadowSegment) -> some View {
        switch retellStep {
        case .prepare:
            Button {
                startRetell(seg)
            } label: {
                Label("开始复述", systemImage: "mic.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(recorder.isBusy)
        case .speaking:
            Button {
                stopTake()
            } label: {
                Label("讲完了", systemImage: "stop.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        case .answering:
            if recordingHere {
                Button {
                    stopTake()
                } label: {
                    Label("答完了", systemImage: "stop.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button {
                    startFollowUp(seg)
                } label: {
                    Label("录音回答追问", systemImage: "mic.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(recorder.isBusy)
            }
        case .compare:
            Button {
                resetRetell()
            } label: {
                Label("再练一次", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: 本次录音状态 (right column first)

    @ViewBuilder
    private func statusCard(_ seg: ShadowSegment) -> some View {
        let status = playerStatus
        VStack(alignment: .leading, spacing: 10) {
            Text("本次录音状态")
                .font(.headline)
            if recorder.denied {
                MicrophoneDeniedCard { openSettings() }
            }
            if recordingHere {
                RecordingMeter(elapsed: recorder.elapsed, level: recorder.level, limit: recLimit, target: recTarget)
                if !recWhat.isEmpty {
                    Text("正在录：\(recWhat)")
                        .font(.callout)
                }
                if mode == .shadowing {
                    Text(speakerOut ? "声音输出：\(outputName)。外放会串音，这次会标“可能串音”。" : "声音输出：\(outputName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let take = lastTake {
                lastTakeSummary(take)
            } else if !recorder.denied {
                Text("这一段还没有新录音。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Label(status.text, systemImage: status.icon)
                .font(.callout)
                .foregroundStyle(.secondary)
            if let message {
                Label(message, systemImage: "info.circle")
                    .font(.callout)
            }
            nextStepSuggestion(seg)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func lastTakeSummary(_ take: ShadowAttempt) -> some View {
        let badges = takeBadges(take, showMode: false)
        let seconds = String(format: "%.1f", take.seconds)
        VStack(alignment: .leading, spacing: 6) {
            Text("刚录的一次：\(seconds) 秒 · \(ShadowMode(rawValue: take.mode)?.title ?? take.mode)")
                .font(.callout.weight(.semibold))
            if !badges.isEmpty {
                badgeFlow(badges)
            }
            if take.silent {
                Text("没录到声音。看看麦克风有没有被挡住，再录一次。这里不打分。")
            } else if take.interrupted {
                Text("录音被打断，保留了 \(seconds) 秒。可以回放这段，也可以重录。")
            } else {
                Text(savedTip(take))
            }
            if take.crosstalk == true {
                Text("外放时录的，原音可能串进录音。这条不进入任何诊断。")
            }
            if take.mode == ShadowMode.shadowing.rawValue, let echo = take.echoCancel {
                Text(echo ? "已请求回声消除，效果看设备。" : "这台设备没有打开回声消除。")
                    .foregroundStyle(.secondary)
            }
            Button {
                togglePlayTake(take)
            } label: {
                Label(isPlaying(take) ? "停止" : "回放这次", systemImage: isPlaying(take) ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(practice.recordingURL(take.file) == nil)
        }
        .font(.callout)
    }

    private func savedTip(_ take: ShadowAttempt) -> String {
        guard let m = ShadowMode(rawValue: take.mode) else { return "已保存。" }
        switch m {
        case .repeatAfter: return "已保存。点“A/B 对照”，先听原句，再听你的。"
        case .shadowing: return "已保存。点“A/B 对照”，听原音和你的跟读。"
        case .readAloud: return "已保存。现在可以听原音对照，或者做 A/B。"
        case .retell: return "已保存。接着回答追问，再对照原文。"
        }
    }

    /// SHD-P04: after two voiced takes, suggest the next step. Nothing is blocked.
    @ViewBuilder
    private func nextStepSuggestion(_ seg: ShadowSegment) -> some View {
        let voiced = segmentTakes(seg).filter { $0.mode == mode.rawValue && !$0.silent && $0.file != nil }.count
        if voiced >= 2, !recordingHere, mode != .retell {
            VStack(alignment: .leading, spacing: 8) {
                Label(suggestionText(voiced), systemImage: "lightbulb")
                    .font(.callout)
                if seg.last < sentences.count - 1 {
                    Button {
                        move(1)
                    } label: {
                        Label(seg.isLong ? "下一段" : "下一句", systemImage: "forward.end.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(recorder.isBusy)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.paper.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func suggestionText(_ n: Int) -> String {
        switch mode {
        case .repeatAfter:
            return "这句已经录了 \(n) 次。可以去下一句，或者换“影子跟读”“独立朗读”练同一句。想接着练也可以。"
        case .shadowing:
            return "这段已经跟了 \(n) 次。可以加长片段，或者去下一段。想接着练也可以。"
        case .readAloud:
            return "已经读了 \(n) 次。可以试试“脱稿复述”：收起原文，讲要点。想接着练也可以。"
        case .retell:
            return "已经复述了 \(n) 次。可以换一段。"
        }
    }

    // MARK: Takes

    @ViewBuilder
    private func takesList(_ seg: ShadowSegment) -> some View {
        let all = practice.attempts(article: articleKey, sid: seg.startSid)
        let mine = all.filter { $0.mode == mode.rawValue }
        let others = all.filter { $0.mode != mode.rawValue }
        let shown = allModes ? mine + others : mine
        VStack(alignment: .leading, spacing: 8) {
            Text(allModes ? "从这句开始的录音（\(shown.count)）" : "\(mode.title)录音（\(shown.count)）")
                .font(.headline)
            Toggle(isOn: $allModes) {
                Label("全部模式", systemImage: allModes ? "checkmark.circle.fill" : "circle")
            }
            .toggleStyle(.button)
            .controlSize(.large)
            .accessibilityHint("打开后也列出别的练习模式的录音")
            if shown.isEmpty {
                Text(allModes || others.isEmpty ? "从这句开始还没有录音。" : "这个模式还没有录音。打开“全部模式”，可以看别的模式录的 \(others.count) 次。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(shown.enumerated()), id: \.element.id) { n, take in
                takeRow(take, number: n < mine.count ? mine.count - n : nil, showMode: allModes)
                Divider()
            }
        }
    }

    private func takeRow(_ take: ShadowAttempt, number: Int?, showMode: Bool) -> some View {
        let playing = isPlaying(take)
        let badges = takeBadges(take, showMode: showMode)
        let which: String = number.map { "第 \($0) 次" } ?? "这次"
        let playLabel: String = playing ? "停止回放" : "回放\(which)录音"
        let title: String = (number.map { "第 \($0) 次 · " } ?? "") + take.created.formatted(date: .abbreviated, time: .shortened)
        return HStack(alignment: .top, spacing: 10) {
            Button {
                togglePlayTake(take)
            } label: {
                Image(systemName: playing ? "stop.circle" : "play.circle")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(practice.recordingURL(take.file) == nil)
            .accessibilityLabel(playLabel)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout)
                Text(takeDetail(take))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !badges.isEmpty {
                    badgeFlow(badges)
                }
                if let question = take.followUp {
                    Text(take.followFile == nil ? "追问（跳过了）：\(question)" : "追问：\(question)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if practice.recordingURL(take.followFile) != nil {
                        Button {
                            togglePlayFollow(take)
                        } label: {
                            Label(isPlayingFollow(take) ? "停止" : "回放追问回答",
                                  systemImage: isPlayingFollow(take) ? "stop.fill" : "play.fill")
                                .font(.callout)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
                if let note = take.selfNote, !note.isEmpty {
                    Text("笔记：\(note)")
                        .font(.caption)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func badgeFlow(_ badges: [ShadowTakeBadge]) -> some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(badges, id: \.self) { b in
                Badge(text: b.text, color: b.warn ? Theme.warn : nil, outlined: true)
            }
        }
    }

    private func takeBadges(_ take: ShadowAttempt, showMode: Bool) -> [ShadowTakeBadge] {
        var out: [ShadowTakeBadge] = []
        if showMode {
            out.append(ShadowTakeBadge(text: ShadowMode(rawValue: take.mode)?.title ?? take.mode, warn: false))
        }
        if take.silent {
            out.append(ShadowTakeBadge(text: "只录到静音", warn: true))
        }
        if take.interrupted {
            out.append(ShadowTakeBadge(text: "被打断 · 保留 \(String(format: "%.1f", take.seconds)) 秒", warn: true))
        }
        if take.crosstalk == true {
            out.append(ShadowTakeBadge(text: "可能串音", warn: true))
        }
        if let hints = take.hints, !hints.isEmpty {
            out.append(ShadowTakeBadge(text: "看了 \(hints.count) 个提示", warn: false))
        }
        if take.followFile != nil {
            out.append(ShadowTakeBadge(text: "答了追问", warn: false))
        }
        return out
    }

    private func takeDetail(_ take: ShadowAttempt) -> String {
        let m = ShadowMode(rawValue: take.mode)
        var parts = ["\(String(format: "%.1f", take.seconds)) 秒", m?.title ?? take.mode, spanText(take)]
        if m == .repeatAfter || m == .shadowing {
            parts.append("原音 \(rateText(take.rate))")
        }
        if let out = take.output, !out.isEmpty {
            parts.append("输出：\(out)")
        }
        return parts.joined(separator: " · ")
    }

    private func spanText(_ take: ShadowAttempt) -> String {
        let startIndex = sentences.firstIndex { $0.id == take.sid }
        let endIndex = take.endSid.flatMap { end in sentences.firstIndex { $0.id == end } }
        if let a = startIndex, let b = endIndex, b > a {
            return "第 \(a + 1)–\(b + 1) 句"
        }
        if let a = startIndex {
            return "第 \(a + 1) 句"
        }
        return "句号 \(take.sid)"
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("说明")
                .font(.headline)
                .foregroundStyle(.primary)
            if mode == .repeatAfter {
                Text("听后模仿练的是模仿。更像原声，不等于能即兴表达。")
            }
            if mode == .readAloud {
                Text("独立朗读只反映朗读，不代表即兴组织和互动。")
            }
            if mode == .shadowing {
                Text("原音串进录音的不进入诊断。回声消除只在部分设备上有效，不能预先保证。")
            }
            if mode == .retell {
                Text("复述允许改写和压缩，这里不算逐词一致率。")
            }
            Text("自动发音诊断还没有启用，这里只保存录音，方便你回放、对照。")
            Text("录音只存在这台 iPad 上，不会自动删除。")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Segment

    private var mode: ShadowMode {
        ShadowMode(rawValue: user.settings.shadowMode) ?? .repeatAfter
    }

    private var modeBinding: Binding<ShadowMode> {
        Binding(get: { mode }, set: { newMode in
            guard newMode != mode, !recorder.isBusy else { return }
            stopPlayback()
            user.updateSettings { $0.shadowMode = newMode.rawValue }
            message = nil
            lastTakeId = nil
            resetRetell()
            refreshRoute()
        })
    }

    private var recordingHere: Bool {
        recorder.isRecording && recorder.owner == "shadow"
    }

    private var articleKey: String { ref?.key ?? "" }

    /// Reading size: the user's text size step, following Dynamic Type.
    private var fontSize: CGFloat {
        let scale: [CGFloat] = [0.85, 1.0, 1.17, 1.33]
        let step = min(max(user.settings.fontStep, 0), scale.count - 1)
        return (baseFontSize * scale[step]).rounded()
    }

    /// The stretch of text this mode practises now.
    private func segment() -> ShadowSegment {
        guard !sentences.isEmpty else { return ShadowSegment(first: 0, last: 0, sents: [], paragraph: nil) }
        let i = min(max(index, 0), sentences.count - 1)
        var first = i
        var last = i
        var paragraph: Int?
        switch mode {
        case .repeatAfter:
            break
        case .shadowing:
            last = i + min(max(shadowLength, 1), 3) - 1
        case .readAloud:
            if readWhole {
                let r = paraRange(i)
                first = r.first
                last = r.last
                paragraph = paraNumber(i)
            }
        case .retell:
            if retellSpan <= 0 {
                let r = paraRange(i)
                first = r.first
                last = r.last
                paragraph = paraNumber(i)
            } else {
                last = i + min(retellSpan, 3) - 1
            }
        }
        let lo = min(max(first, 0), sentences.count - 1)
        let hi = min(max(last, lo), sentences.count - 1)
        return ShadowSegment(first: lo, last: hi, sents: Array(sentences[lo...hi]), paragraph: paragraph)
    }

    private func paraRange(_ i: Int) -> (first: Int, last: Int) {
        guard paraOf.indices.contains(i) else { return (i, i) }
        let p = paraOf[i]
        var a = i
        var b = i
        while a > 0, paraOf[a - 1] == p { a -= 1 }
        while b + 1 < paraOf.count, paraOf[b + 1] == p { b += 1 }
        return (a, b)
    }

    private func paraNumber(_ i: Int) -> Int? {
        paraOf.indices.contains(i) ? paraOf[i] + 1 : nil
    }

    private func rangeText(_ seg: ShadowSegment) -> String {
        let total = sentences.count
        let a = seg.first + 1
        let b = seg.last + 1
        let sents = a == b ? "第 \(a) / \(total) 句" : "第 \(a)–\(b) / \(total) 句"
        if let p = seg.paragraph {
            return "第 \(p) 段 · \(sents)"
        }
        return sents
    }

    /// Takes of exactly this segment (same first and last sentence), newest first.
    private func segmentTakes(_ seg: ShadowSegment) -> [ShadowAttempt] {
        practice.attempts(article: articleKey, sid: seg.startSid).filter { ($0.endSid ?? $0.sid) == seg.lastSid }
    }

    private func abTake(_ seg: ShadowSegment) -> ShadowAttempt? {
        segmentTakes(seg).first { $0.mode == mode.rawValue && !$0.silent && practice.recordingURL($0.file) != nil }
    }

    private func hasVoicedTake(_ seg: ShadowSegment) -> Bool {
        segmentTakes(seg).contains { $0.mode == mode.rawValue && !$0.silent && $0.file != nil }
    }

    private var lastTake: ShadowAttempt? {
        guard let id = lastTakeId else { return nil }
        return practice.state.shadow.first { $0.id == id }
    }

    private var retellTake: ShadowAttempt? {
        guard let id = retellTakeId else { return nil }
        return practice.state.shadow.first { $0.id == id }
    }

    private func followKey(_ seg: ShadowSegment) -> String {
        "\(articleKey)#\(seg.startSid)-\(seg.lastSid)"
    }

    private func takeContext(_ seg: ShadowSegment) -> ShadowTakeContext? {
        guard let ref, let first = seg.sents.first else { return nil }
        return ShadowTakeContext(article: ref.key, sid: first.id, endSid: seg.endSid, text: seg.text,
                                 rate: user.settings.shadowRate, mode: mode)
    }

    // MARK: Playback

    private func stopPlayback() {
        player.stop()
        playingKey = nil
    }

    /// An unfinished take is stopped (and saved as it is) before any playback starts.
    private func finishRecordingBeforePlayback() {
        guard recordingHere else { return }
        shadowRun?.cancel()
        shadowRun = nil
        recorder.stop()
    }

    private func playOriginal(_ seg: ShadowSegment, rate: Double, toggles: Bool = true) {
        if toggles, player.playing == .original, !recordingHere {
            stopPlayback()
            return
        }
        finishRecordingBeforePlayback()
        guard let ref, let url = packs.audioURL(ref), let start = seg.start, let end = seg.end else {
            message = "这一段没有原音时间，放不了原音。"
            return
        }
        engine.pause()
        playingKey = nil
        Task { await player.play(url, from: start, to: end, rate: rate, as: .original) }
    }

    private func isPlaying(_ take: ShadowAttempt) -> Bool {
        playingKey == take.id && player.playing == .mine
    }

    private func isPlayingFollow(_ take: ShadowAttempt) -> Bool {
        playingKey == "follow:" + take.id && player.playing == .mine
    }

    private func togglePlayTake(_ take: ShadowAttempt) {
        playRecording(file: take.file, key: take.id)
    }

    private func togglePlayFollow(_ take: ShadowAttempt) {
        playRecording(file: take.followFile, key: "follow:" + take.id)
    }

    private func playRecording(file: String?, key: String) {
        if playingKey == key, player.playing == .mine {
            stopPlayback()
            return
        }
        finishRecordingBeforePlayback()
        guard let url = practice.recordingURL(file) else { return }
        engine.pause()
        playingKey = key
        Task {
            await player.play(url, as: .mine)
            if playingKey == key { playingKey = nil }
        }
    }

    private func playAB(_ seg: ShadowSegment) {
        finishRecordingBeforePlayback()
        guard let ref, let original = packs.audioURL(ref), let start = seg.start, let end = seg.end,
              let take = abTake(seg), let mine = practice.recordingURL(take.file) else { return }
        engine.pause()
        playingKey = nil
        player.playAB(original: original, from: start, to: end, rate: user.settings.shadowRate, mine: mine,
                      gap: user.settings.abGap)
    }

    // MARK: Recording

    private func startRecording(limit: Double, target: Double?, what: String,
                                onFinish: @escaping (RecordingResult) -> Void) async -> Bool {
        recLimit = limit
        recTarget = target
        recWhat = what
        let ok = await recorder.start(into: practice.newRecordingURL(), owner: "shadow", maxDuration: limit,
                                      onFinish: onFinish)
        if !ok && !recorder.isBusy {
            message = recorder.denied ? "没有麦克风权限，录不了音。" : "录音没有启动，请再试一次。"
        }
        return ok
    }

    /// Stops the take in progress; in 影子跟读 the original stops with it.
    private func stopTake() {
        shadowRun?.cancel()
        shadowRun = nil
        if recordingHere { recorder.stop() }
        if player.playing != SegmentPlayer.Source.none { stopPlayback() }
    }

    /// 听后模仿 and 独立朗读: manual stop.
    private func toggleRecord(_ seg: ShadowSegment) {
        if recordingHere {
            stopTake()
            return
        }
        guard !recorder.isBusy, let ctx = takeContext(seg) else { return }
        stopPlayback()
        engine.pause()
        message = nil
        let limit: Double = seg.isLong ? 180 : 60
        let what = "\(mode.title) · \(rangeText(seg))"
        Task {
            _ = await startRecording(limit: limit, target: nil, what: what) { result in
                saveTake(result, ctx, extras: nil)
            }
        }
    }

    /// 影子跟读 (SHD-F02): the recorder starts first, then echo-cancelled input is requested, then the
    /// original plays; about a second after it ends the take stops by itself.
    private func startShadowTake(_ seg: ShadowSegment) {
        guard !recorder.isBusy else { return }
        guard let ref, let audio = packs.audioURL(ref), let start = seg.start, let end = seg.end,
              let ctx = takeContext(seg) else {
            message = "这一段没有原音时间，不能边放边录。"
            return
        }
        stopPlayback()
        engine.pause()
        message = nil
        let rate = user.settings.shadowRate
        let limit = min(120, max(15, (end - start) / max(rate, 0.5) + 8))
        let extras = ShadowTakeExtras()
        shadowRun?.cancel()
        shadowRun = Task {
            let ok = await startRecording(limit: limit, target: nil, what: "影子跟读 · 原音同时在放") { result in
                extras.finished = true
                AudioSessionControl.endShadowing()
                saveTake(result, ctx, extras: extras)
            }
            guard ok else { return }
            extras.echoCancel = (try? AudioSessionControl.useShadowing()) ?? false
            extras.crosstalk = AudioSessionControl.outputIsSpeaker
            extras.output = AudioSessionControl.outputText
            refreshRoute()
            guard !Task.isCancelled, !extras.finished else { return }
            let reached = await player.play(audio, from: start, to: end, rate: rate, as: .original)
            guard !Task.isCancelled, !extras.finished else { return }
            if reached {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, !extras.finished else { return }
            }
            if recordingHere {
                recorder.stop()
            }
            if !reached {
                message = "原音没有放完，录音先停了。"
            }
        }
    }

    private func saveTake(_ result: RecordingResult, _ ctx: ShadowTakeContext, extras: ShadowTakeExtras?) {
        var take = ShadowAttempt(id: UUID().uuidString, article: ctx.article, sid: ctx.sid, text: ctx.text,
                                 created: Date(), file: result.file, seconds: result.seconds, peakDb: result.peakDb,
                                 silent: result.silent, interrupted: result.interrupted, rate: ctx.rate,
                                 mode: ctx.mode.rawValue)
        take.endSid = ctx.endSid
        if let extras {
            take.crosstalk = extras.crosstalk
            take.echoCancel = extras.echoCancel
            take.output = extras.output
        }
        if ctx.mode == .retell {
            take.hints = hintsShown
        }
        practice.addShadow(take)
        lastTakeId = take.id
        message = nil
        refreshRoute()
        if ctx.mode == .retell {
            retellTakeId = take.id
            retellStep = result.silent ? .prepare : .answering
        }
    }

    // MARK: 脱稿复述 actions

    private func startRetell(_ seg: ShadowSegment) {
        guard !recorder.isBusy, let ctx = takeContext(seg) else { return }
        stopPlayback()
        engine.pause()
        message = nil
        hintsShown = []
        noteDraft = ""
        noteSaved = false
        retellTakeId = nil
        let target = user.settings.retellSeconds
        let limit = max(90, (target * 1.5).rounded())
        retellStep = .speaking
        Task {
            let ok = await startRecording(limit: limit, target: target, what: "脱稿复述") { result in
                saveTake(result, ctx, extras: nil)
            }
            if !ok, retellStep == .speaking {
                retellStep = .prepare
            }
        }
    }

    private func revealHint(_ words: [String]) {
        guard hintsShown.count < words.count else { return }
        hintsShown.append(words[hintsShown.count])
    }

    private func startFollowUp(_ seg: ShadowSegment) {
        guard !recorder.isBusy, let id = retellTakeId else { return }
        stopPlayback()
        engine.pause()
        message = nil
        let question = retellFollowUp(key: followKey(seg)).en
        Task {
            _ = await startRecording(limit: 60, target: nil, what: "回答追问") { result in
                practice.updateShadow(id) { t in
                    t.followUp = question
                    t.followFile = result.file
                    t.followSeconds = result.seconds
                }
                if result.silent {
                    message = "回答只录到静音。可以再答一次，或者跳过。"
                } else {
                    if result.interrupted {
                        message = "回答被打断，保留了 \(String(format: "%.1f", result.seconds)) 秒。"
                    }
                    retellStep = .compare
                }
            }
        }
    }

    private func skipFollowUp(_ question: String) {
        if let id = retellTakeId {
            practice.updateShadow(id) { $0.followUp = question }
        }
        message = nil
        retellStep = .compare
    }

    private func saveSelfNote(_ id: String) {
        let clean = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        practice.updateShadow(id) { $0.selfNote = clean.isEmpty ? nil : clean }
        noteSaved = true
    }

    private func resetRetell() {
        retellStep = .prepare
        retellTakeId = nil
        hintsShown = []
        noteDraft = ""
        noteSaved = false
    }

    // MARK: Moving

    private func move(_ step: Int) {
        guard !sentences.isEmpty else { return }
        let seg = segment()
        if step > 0 {
            index = min(sentences.count - 1, seg.last + 1)
        } else if seg.paragraph != nil {
            index = paraRange(max(0, seg.first - 1)).first
        } else {
            index = max(0, seg.first - max(1, seg.sents.count))
        }
        segmentChanged()
    }

    private func segmentChanged() {
        if !recordingHere { stopPlayback() }
        message = nil
        lastTakeId = nil
        resetRetell()
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    // MARK: Audio route (ACC-17)

    private func refreshRoute() {
        speakerOut = AudioSessionControl.outputIsSpeaker
        outputName = AudioSessionControl.outputText
    }

    /// Headphones in or out: the speaker warning follows.
    private func watchRoute() async {
        for await _ in NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification) {
            refreshRoute()
        }
    }

    // MARK: Loading

    private func consumeTarget() {
        guard let target = router.shadowTarget else { return }
        router.shadowTarget = nil
        load(target.ref, sid: target.sid)
    }

    private func loadDefault() {
        if let key = user.state.lastArticle, let last = ArticleRef(key: key), packs.item(last) != nil {
            load(last, sid: nil)
        }
    }

    private func load(_ newRef: ArticleRef, sid: Int?) {
        shadowRun?.cancel()
        shadowRun = nil
        if recordingHere { recorder.stop() }
        stopPlayback()
        AudioSessionControl.endShadowing()
        message = nil
        lastTakeId = nil
        resetRetell()
        do {
            let art = try packs.loadArticle(newRef)
            var list: [Sent] = []
            var paras: [Int] = []
            var number = -1
            for para in art.paras {
                let timed = para.sents.filter { $0.isTimed && $0.unread != true }
                guard !timed.isEmpty else { continue }
                number += 1
                list += timed
                paras += Array(repeating: number, count: timed.count)
            }
            ref = newRef
            article = art
            sentences = list
            paraOf = paras
            if let sid, let i = list.firstIndex(where: { $0.id == sid }) {
                index = i
            } else {
                index = 0
            }
            loadError = nil
        } catch {
            ref = newRef
            article = nil
            sentences = []
            paraOf = []
            loadError = error.localizedDescription
        }
    }

    // MARK: Text

    private var playerStatus: (text: String, icon: String) {
        if recordingHere { return ("录音中", "record.circle") }
        switch player.playing {
        case .original: return ("正在播放原音", "speaker.wave.2")
        case .mine: return ("正在播放你的录音", "person.wave.2")
        case .none: return recorder.denied ? ("麦克风权限已关闭", "mic.slash") : ("准备好了", "checkmark.circle")
        }
    }

    private func rateText(_ r: Double) -> String {
        abs(r - 1) < 0.001 ? "1.0×" : String(format: "%g×", r)
    }

    private func gapText(_ g: Double) -> String {
        String(format: "%g 秒", g)
    }
}

// MARK: - Helpers

/// The sentences one practice step works on.
private struct ShadowSegment {
    var first: Int              // index into the timed sentences
    var last: Int
    var sents: [Sent]
    var paragraph: Int?         // 1-based, when the segment is a whole paragraph

    var startSid: Int { sents.first?.id ?? -1 }
    var lastSid: Int { sents.last?.id ?? -1 }
    var endSid: Int? { sents.count > 1 ? sents.last?.id : nil }
    var start: Double? { sents.first?.s }
    var end: Double? { sents.last?.e }
    var duration: Double? {
        guard let start, let end, end > start else { return nil }
        return end - start
    }
    var isLong: Bool { sents.count > 1 || paragraph != nil }
    var text: String { sents.map { SentenceText.plain($0) }.joined(separator: " ") }
}

/// What a take is about, captured when it starts.
private struct ShadowTakeContext {
    var article: String
    var sid: Int
    var endSid: Int?
    var text: String
    var rate: Double
    var mode: ShadowMode
}

/// 影子跟读 facts known only after the recorder has started.
@MainActor
private final class ShadowTakeExtras {
    var crosstalk = false
    var echoCancel = false
    var output = ""
    var finished = false
}

private enum ShadowRetellStep: Equatable {
    case prepare, speaking, answering, compare
}

private struct ShadowTakeBadge: Hashable {
    var text: String
    var warn: Bool
}

private struct RetellFollowUp {
    let en: String
    let zh: String
}

private enum RetellText {
    /// Original follow-up questions (English, with a Chinese gloss).
    static let followUps: [RetellFollowUp] = [
        RetellFollowUp(en: "What is the main point of this part?", zh: "这部分的主要观点是什么？"),
        RetellFollowUp(en: "Why does it matter?", zh: "这件事为什么重要？"),
        RetellFollowUp(en: "What example does the writer give?", zh: "作者举了什么例子？"),
        RetellFollowUp(en: "Do you agree? Why or why not?", zh: "你同意吗？为什么？"),
        RetellFollowUp(en: "What might happen next?", zh: "接下来可能会发生什么？"),
        RetellFollowUp(en: "Who is affected, and how?", zh: "谁会受影响？怎样受影响？"),
    ]

    static let stopwords: Set<String> = [
        "about", "above", "across", "after", "again", "against", "almost", "along", "already", "also",
        "although", "always", "among", "another", "anyone", "anything", "around", "back", "because", "been",
        "before", "behind", "being", "below", "best", "better", "between", "both", "came", "cannot", "come",
        "comes", "could", "does", "doing", "done", "down", "during", "each", "either", "else", "enough",
        "even", "ever", "every", "first", "from", "further", "gets", "getting", "goes", "going", "have",
        "having", "here", "hers", "herself", "himself", "however", "indeed", "instead", "into", "itself",
        "just", "last", "least", "less", "like", "made", "make", "makes", "many", "might", "more", "most",
        "much", "must", "neither", "never", "next", "none", "nothing", "only", "onto", "other", "others",
        "ought", "ours", "ourselves", "over", "perhaps", "quite", "rather", "really", "said", "same", "says",
        "second", "seem", "seemed", "seems", "shall", "should", "since", "some", "something", "still", "such",
        "take", "takes", "than", "that", "their", "theirs", "them", "themselves", "then", "there", "therefore",
        "these", "they", "thing", "things", "this", "those", "though", "through", "thus", "time", "times",
        "together", "took", "toward", "towards", "under", "unless", "until", "upon", "very", "want", "wants",
        "well", "went", "were", "what", "whatever", "when", "where", "whether", "which", "while", "whom",
        "whose", "will", "with", "within", "without", "would", "year", "years", "your", "yours", "yourself",
        "it's", "that's", "there's", "they're", "don't", "doesn't", "didn't", "isn't", "aren't", "wasn't",
        "weren't", "won't", "can't", "couldn't", "wouldn't", "shouldn't",
    ]
}

/// Up to `limit` keywords for 脱稿复述: the longest content words of the segment (no stopwords),
/// shown in the order they appear in the text.
private func retellKeywords(_ sents: [Sent], limit: Int = 5) -> [String] {
    var seen = Set<String>()
    var found: [(word: String, order: Int)] = []
    for s in sents {
        for t in s.toks {
            let word = t.w.trimmingCharacters(in: CharacterSet.letters.inverted)
            let lower = word.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
            guard word.count >= 4, word.contains(where: { $0.isLetter }),
                  !RetellText.stopwords.contains(lower), !seen.contains(lower) else { continue }
            seen.insert(lower)
            found.append((word: word, order: found.count))
        }
    }
    let longest = found.sorted { a, b in
        a.word.count != b.word.count ? a.word.count > b.word.count : a.order < b.order
    }
    return longest.prefix(limit).sorted { $0.order < $1.order }.map { $0.word }
}

/// One follow-up question, always the same for the same segment.
private func retellFollowUp(key: String) -> RetellFollowUp {
    let list = RetellText.followUps
    guard !list.isEmpty else {
        return RetellFollowUp(en: "What is the main point of this part?", zh: "这部分的主要观点是什么？")
    }
    var h: UInt32 = 2_166_136_261
    for b in key.utf8 {
        h = (h ^ UInt32(b)) &* 16_777_619
    }
    return list[Int(h % UInt32(list.count))]
}

/// The seven layers and four states, for the "标注说明" popover.
private struct ShadowLayerGuide: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("七层发音标注")
                    .font(.headline)
                ForEach(AnnLayer.allCases) { layer in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(layer.title)
                                .font(.subheadline.weight(.semibold))
                            Text(layer.code)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            if layer.defaultOn {
                                Badge(text: "默认开", outlined: true)
                            }
                        }
                        Text(layer.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                Text("四种状态")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 4) {
                    Text("待核对：机器按规则生成，还没人对着原声核对。画得浅一些，重音是空心点，同化是虚线框。")
                    Text("教学建议：一般的读法建议，不代表主播一定这样读。")
                    Text("原声已核对：对着原声听过，确认是这样。")
                    Text("有争议：可能有别的合理读法，记号后面带 ?。")
                }
                .font(.callout)
                Text("点带记号的词可以改状态、隐藏、写备注或报错。你的改动只套用在当时的句子文字上；内容包更新改了句子，旧改动就不再套用。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
        }
        .frame(minWidth: 320, idealWidth: 420, maxWidth: 480, minHeight: 300, idealHeight: 520, maxHeight: 700)
        .presentationDetents([.medium, .large])
    }
}

/// Articles from the library, newest issue first. Used to choose what to practise.
struct ArticlePickerList: View {
    @Environment(PackStore.self) private var packs
    @Environment(PracticeStore.self) private var practice
    var onPick: (ArticleRef) -> Void

    var body: some View {
        List {
            if packs.groups.isEmpty {
                Text("还没有内容包。先在书架导入内容包。")
                    .foregroundStyle(.secondary)
            }
            ForEach(packs.groups) { group in
                Section("\(group.issue) 期") {
                    ForEach(group.items) { item in
                        Button {
                            onPick(item.ref)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.meta.title)
                                        .font(Font.system(.body, design: .serif).weight(.semibold))
                                    Text([item.meta.section, item.meta.fly ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                let n = practice.state.shadow.filter { $0.article == item.ref.key }.count
                                if n > 0 {
                                    Text("跟读 \(n) 次")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
