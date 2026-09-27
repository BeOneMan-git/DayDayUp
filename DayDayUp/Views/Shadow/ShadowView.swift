import SwiftUI
import UIKit

/// 跟读工作台. V0.2 has one mode, 听后模仿: one sentence at a time,
/// 听原句 → 录音 → A/B 对照. Every take is kept as a practice record.
struct ShadowView: View {
    @Environment(PackStore.self) private var packs
    @Environment(UserStore.self) private var user
    @Environment(PracticeStore.self) private var practice
    @Environment(RecorderService.self) private var recorder
    @Environment(PlaybackEngine.self) private var engine
    @Environment(Router.self) private var router
    @Environment(\.openURL) private var openURL

    @State private var ref: ArticleRef?
    @State private var article: Article?
    @State private var sentences: [Sent] = []
    @State private var index = 0
    @State private var player = SegmentPlayer()
    @State private var showZh = false
    @State private var message: String?
    @State private var showPicker = false
    @State private var loadError: String?

    var body: some View {
        Group {
            if let article, !sentences.isEmpty {
                workbench(article)
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
            if router.shadowTarget != nil {
                consumeTarget()
            } else if ref == nil {
                loadDefault()
            }
        }
        .onChange(of: router.shadowRequestID) { _, _ in consumeTarget() }
        .onDisappear {
            player.stop()
            if recorder.owner == "shadow" { recorder.stop() }
            AudioSessionControl.usePlayback()
        }
    }

    // MARK: Workbench

    @ViewBuilder
    private func workbench(_ art: Article) -> some View {
        let s = sentences[min(index, sentences.count - 1)]
        let key = ref?.key ?? ""
        let takes = practice.attempts(article: key, sid: s.id)
        let voiced = takes.filter { !$0.silent }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(art.issue) · \(art.section)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(art.title)
                            .font(Font.system(.title3, design: .serif).weight(.semibold))
                    }
                    Spacer()
                    Badge(text: "听后模仿")
                }

                sentenceCard(s)
                controls(s, takes: takes)

                if recorder.isRecording && recorder.owner == "shadow" {
                    RecordingMeter(elapsed: recorder.elapsed, level: recorder.level, limit: 60, target: nil)
                }
                if recorder.denied {
                    MicrophoneDeniedCard { openSettings() }
                }
                if let message {
                    Label(message, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if voiced.count >= 3 && index < sentences.count - 1 {
                    HStack(spacing: 12) {
                        Label("这句已经练了 \(voiced.count) 次。可以去下一句，明天再回来听一遍。", systemImage: "lightbulb")
                            .font(.callout)
                        Spacer()
                        Button("下一句") { move(1) }
                            .buttonStyle(.bordered)
                    }
                    .padding(12)
                    .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                }

                takesList(takes)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    private func sentenceCard(_ s: Sent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("第 \(index + 1) / \(sentences.count) 句")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let start = s.s, let end = s.e {
                    Text("· \(String(format: "%.1f", end - start)) 秒")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(showZh ? "收起译文" : "译文") { showZh.toggle() }
                    .buttonStyle(.borderless)
                    .font(.callout)
            }
            Text(ReadingSession.plainText(s))
                .font(Theme.readingFont(user.settings.fontStep + 1 > 3 ? 3 : user.settings.fontStep + 1))
                .lineSpacing(6)
                .textSelection(.enabled)
            if showZh, let zh = s.zh, !zh.isEmpty {
                Text(zh)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }

    private func controls(_ s: Sent, takes: [ShadowAttempt]) -> some View {
        let recording = recorder.isRecording && recorder.owner == "shadow"
        let latestFile = takes.first(where: { $0.file != nil && !$0.silent })
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    move(-1)
                } label: {
                    Label("上一句", systemImage: "backward.end.fill")
                }
                .disabled(index == 0 || recording)

                Button {
                    playOriginal(s)
                } label: {
                    Label(player.playing == .original ? "停止" : "听原句",
                          systemImage: player.playing == .original ? "stop.fill" : "play.fill")
                }
                .disabled(recording)

                Button {
                    toggleRecord(s)
                } label: {
                    Label(recording ? "停止录音" : "录音",
                          systemImage: recording ? "stop.circle.fill" : "record.circle")
                }
                .tint(recording ? .red : Theme.accent)
                .buttonStyle(.borderedProminent)

                Button {
                    playAB(s, take: latestFile)
                } label: {
                    Label("A/B 对照", systemImage: "arrow.left.arrow.right")
                }
                .disabled(latestFile == nil || recording)

                Button {
                    move(1)
                } label: {
                    Label("下一句", systemImage: "forward.end.fill")
                }
                .disabled(index >= sentences.count - 1 || recording)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            HStack(spacing: 16) {
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
                    Label("原音 \(rateText(user.settings.shadowRate))", systemImage: "speedometer")
                        .font(.callout)
                }
                Text(statusText(recording: recording))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if let ref {
                    Button("回到原文") { router.openArticle(ref) }
                        .font(.callout)
                }
            }
        }
    }

    @ViewBuilder
    private func takesList(_ takes: [ShadowAttempt]) -> some View {
        if !takes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("我的录音（\(takes.count) 次）")
                    .font(.headline)
                ForEach(Array(takes.enumerated()), id: \.element.id) { n, take in
                    HStack(spacing: 12) {
                        Button {
                            playTake(take)
                        } label: {
                            Image(systemName: "play.circle")
                                .font(.title2)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .disabled(practice.recordingURL(take.file) == nil)
                        .accessibilityLabel("回放第 \(takes.count - n) 次")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("第 \(takes.count - n) 次 · \(take.created.formatted(date: .abbreviated, time: .shortened))")
                                .font(.callout)
                            Text("\(String(format: "%.1f", take.seconds)) 秒 · 原音 \(rateText(take.rate))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if take.silent { Badge(text: "只录到静音", color: Theme.warn, outlined: true) }
                        if take.interrupted { Badge(text: "被打断", color: Theme.warn, outlined: true) }
                    }
                    Divider()
                }
            }
        }
    }

    // MARK: Actions

    private func playOriginal(_ s: Sent) {
        if player.playing == .original {
            player.stop()
            return
        }
        guard let ref, let url = packs.audioURL(ref), let start = s.s, let end = s.e else { return }
        engine.pause()
        let rate = user.settings.shadowRate
        Task { await player.play(url, from: start, to: end, rate: rate, as: .original) }
    }

    private func toggleRecord(_ s: Sent) {
        if recorder.isRecording {
            recorder.stop()
            return
        }
        guard !recorder.isBusy else { return }
        player.stop()
        engine.pause()
        message = nil
        let url = practice.newRecordingURL()
        let key = ref?.key ?? ""
        let text = ReadingSession.plainText(s)
        let rate = user.settings.shadowRate
        Task {
            let ok = await recorder.start(into: url, owner: "shadow", maxDuration: 60) { result in
                saveTake(result, article: key, sid: s.id, text: text, rate: rate)
            }
            if !ok && !recorder.isBusy {
                message = recorder.denied ? "没有麦克风权限，录不了音。" : "录音没有启动，请再试一次。"
            }
        }
    }

    private func saveTake(_ result: RecordingResult, article: String, sid: Int, text: String, rate: Double) {
        let take = ShadowAttempt(id: UUID().uuidString, article: article, sid: sid, text: text, created: Date(),
                                 file: result.file, seconds: result.seconds, peakDb: result.peakDb,
                                 silent: result.silent, interrupted: result.interrupted, rate: rate, mode: "repeat")
        practice.addShadow(take)
        if result.silent {
            message = "只录到静音。看看麦克风有没有被挡住，再录一次。"
        } else if result.interrupted {
            message = "录音被打断，已保存 \(String(format: "%.1f", result.seconds)) 秒。"
        } else {
            message = "已保存。点“A/B 对照”，先听原句，再听你的。"
        }
    }

    private func playAB(_ s: Sent, take: ShadowAttempt?) {
        guard let ref, let original = packs.audioURL(ref), let start = s.s, let end = s.e,
              let take, let mine = practice.recordingURL(take.file) else { return }
        engine.pause()
        player.playAB(original: original, from: start, to: end, rate: user.settings.shadowRate, mine: mine)
    }

    private func playTake(_ take: ShadowAttempt) {
        guard let url = practice.recordingURL(take.file) else { return }
        engine.pause()
        Task { await player.play(url, as: .mine) }
    }

    private func move(_ step: Int) {
        player.stop()
        message = nil
        index = max(0, min(sentences.count - 1, index + step))
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
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
        player.stop()
        message = nil
        do {
            let art = try packs.loadArticle(newRef)
            let list = art.paras.flatMap { $0.sents }.filter { $0.isTimed && $0.unread != true }
            ref = newRef
            article = art
            sentences = list
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
            loadError = error.localizedDescription
        }
    }

    // MARK: Text

    private func statusText(recording: Bool) -> String {
        if recording { return "录音中……说完点“停止录音”" }
        switch player.playing {
        case .original: return "正在播放原句"
        case .mine: return "正在播放你的录音"
        case .none: return recorder.denied ? "麦克风权限已关闭" : "准备好了"
        }
    }

    private func rateText(_ r: Double) -> String {
        abs(r - 1) < 0.001 ? "1.0×" : String(format: "%g×", r)
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
