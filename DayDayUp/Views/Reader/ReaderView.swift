import SwiftUI

/// 听读页: native text with word-level highlight that follows the narration.
struct ReaderView: View {
    let ref: ArticleRef

    @Environment(ReadingSession.self) private var session
    @Environment(UserStore.self) private var user
    @Environment(PackStore.self) private var packs
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastUserScroll = Date.distantPast
    @State private var showSettings = false

    var body: some View {
        Group {
            if session.ref == ref, let art = session.article {
                reader(art)
            } else if session.ref == ref, let error = session.loadError {
                ContentUnavailableView("打不开这篇文章", systemImage: "exclamationmark.triangle",
                                       description: Text(error))
            } else {
                ProgressView("正在打开…")
            }
        }
        .navigationTitle(packs.item(ref)?.meta.title ?? "听读")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    session.blind.toggle()
                } label: {
                    Label(session.blind ? "显示原文" : "盲听", systemImage: session.blind ? "eye" : "eye.slash")
                }
                .help("盲听：隐藏原文，只听")
                Button {
                    user.updateSettings { $0.showZh.toggle() }
                } label: {
                    Label("中文", systemImage: user.settings.showZh ? "character.bubble.fill" : "character.bubble")
                }
                .help("显示或隐藏中文翻译")
                Button {
                    showSettings = true
                } label: {
                    Label("阅读设置", systemImage: "textformat.size")
                }
                .popover(isPresented: $showSettings) {
                    ReaderSettingsView()
                        .frame(minWidth: 340, minHeight: 420)
                }
                Button {
                    session.showInspector.toggle()
                } label: {
                    Label("单词卡", systemImage: "sidebar.right")
                }
                .keyboardShortcut("i", modifiers: .command)
            }
        }
        .inspector(isPresented: Bindable(session).showInspector) {
            InspectorPanel()
                .inspectorColumnWidth(min: 320, ideal: 380, max: 460)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if session.ref == ref && session.article != nil {
                PlayerBar()
            }
        }
        .overlay(alignment: .top) {
            if let toast = session.toast {
                Text(toast)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .task(id: session.toastID) {
            guard session.toast != nil else { return }
            do {
                try await Task.sleep(for: .seconds(1.6))
                session.toast = nil
            } catch {
                // a newer toast replaced this one
            }
        }
        .onAppear { session.open(ref) }
        .onChange(of: ref) { _, newRef in session.open(newRef) }
        .onDisappear { session.flushProgress() }
        .onChange(of: packs.lexiconReady) { _, ready in
            if ready { session.refreshMarks() }
        }
    }

    @ViewBuilder
    private func reader(_ art: Article) -> some View {
        let settings = user.settings
        let style = ParagraphStyle(fontStep: settings.fontStep, threshold: settings.threshold,
                                   showTrap: settings.showTrap, showPhrase: settings.showPhrase,
                                   showZh: settings.showZh, marksVersion: session.marksVersion)
        let curTok = session.curTok
        let curSent = session.curSent
        let selTok = session.selectedTok
        let loopSid = session.loopSid
        let curTokPara = curTok.flatMap { session.paragraphIndex(ofToken: $0) }
        let curSentPara = curSent.flatMap { session.paragraphIndex(ofSentence: $0) }
        let selPara = selTok.flatMap { session.paragraphIndex(ofToken: $0) }
        let loopPara = loopSid.flatMap { session.paragraphIndex(ofSentence: $0) }

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ArticleHeader(article: art, meta: packs.item(ref)?.meta, titleOn: session.titleOn)
                        .id(-1)
                    if session.blind {
                        BlindListeningView(position: blindPosition)
                    } else {
                        ForEach(Array(art.paras.enumerated()), id: \.offset) { pi, para in
                            ParagraphView(
                                para: para,
                                index: pi,
                                highlight: ParagraphHighlight(
                                    curTok: curTokPara == pi ? curTok : nil,
                                    curSent: curSentPara == pi ? curSent : nil,
                                    selTok: selPara == pi ? selTok : nil,
                                    loopSid: loopPara == pi ? loopSid : nil),
                                style: style,
                                session: session
                            )
                            .equatable()
                            .id(pi)
                        }
                    }
                    Color.clear.frame(height: 80)
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .frame(maxWidth: .infinity)
            }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { lastUserScroll = Date() }
            }
            .onChange(of: curSentPara) { _, pi in
                guard let pi, settings.follow, !session.blind,
                      Date().timeIntervalSince(lastUserScroll) > 2.5 else { return }
                withAnimation(reduceMotion ? nil : Animation.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(pi, anchor: UnitPoint(x: 0.5, y: 0.2))
                }
            }
            .onChange(of: session.scrollRequestID) { _, _ in
                guard let pi = session.scrollTarget else { return }
                lastUserScroll = Date()
                withAnimation(reduceMotion ? nil : Animation.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(pi, anchor: .center)
                }
            }
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "ddu", url.host == "t", let i = Int(url.lastPathComponent) else {
                    return .systemAction
                }
                session.tapToken(i)
                return .handled
            })
        }
    }

    private var blindPosition: String {
        if let sid = session.curSent {
            return "第 \(session.position(of: sid)) / \(session.sentenceCount) 句"
        }
        return "共 \(session.sentenceCount) 句"
    }
}

/// Reading options (popover from the Aa button).
struct ReaderSettingsView: View {
    @Environment(UserStore.self) private var user

    var body: some View {
        Form {
            Section("文字") {
                Picker("字号", selection: binding(\.fontStep)) {
                    ForEach(0..<Theme.fontStepNames.count, id: \.self) { i in
                        Text(Theme.fontStepNames[i]).tag(i)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("显示中文翻译", isOn: binding(\.showZh))
            }
            Section {
                Picker("下划线标注", selection: binding(\.threshold)) {
                    Text("5+").tag(5)
                    Text("6+").tag(6)
                    Text("7+").tag(7)
                    Text("8").tag(8)
                    Text("关").tag(0)
                }
                .pickerStyle(.segmented)
                Toggle("熟词僻义（点状下划线）", isOn: binding(\.showTrap))
                Toggle("短语（虚线）", isOn: binding(\.showPhrase))
            } header: {
                Text("标注")
            } footer: {
                Text("颜色：5 级青、6 级蓝、7 级紫、8 级橙。标成“认识”的词不再标注。")
            }
            Section("听读") {
                Toggle("点词时暂停播放", isOn: binding(\.pauseOnTap))
                Toggle("自动跟随朗读滚动", isOn: binding(\.follow))
                Picker("循环间隔", selection: binding(\.loopGap)) {
                    ForEach(ReaderSettings.loopGaps, id: \.self) { g in
                        Text(g == 0 ? "不停" : String(format: "%g 秒", g)).tag(g)
                    }
                }
                Picker("系统朗读口音", selection: binding(\.accent)) {
                    Text("英音").tag("en-GB")
                    Text("美音").tag("en-US")
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private func binding<T>(_ path: WritableKeyPath<ReaderSettings, T>) -> Binding<T> {
        Binding(
            get: { user.settings[keyPath: path] },
            set: { value in user.updateSettings { $0[keyPath: path] = value } }
        )
    }
}
