import SwiftUI

/// Where the reader puts its side panel (word card, sentence notes, word list), from the width of the app's window
/// (SYS-P01 / PLAT-05: 宽屏 = 导航 + 正文 + 检查器). iPad portrait, Split View and Stage Manager windows all count; the
/// device model never does. An open sidebar does not count against it: on a landscape iPad the text keeps about
/// 700 pt next to the side panel.
enum ReaderLayout: Equatable {
    /// ≥ 1180 pt: text plus a side-panel column; the column is open unless the learner closed it.
    case wide
    /// 800–1179 pt: text first; the side panel is a drawer over the text, opened on demand.
    case medium
    /// < 800 pt: one column; the side panel comes up as a sheet when asked for.
    case narrow

    static let wideMinWidth: CGFloat = 1180
    static let mediumMinWidth: CGFloat = 800

    init(width: CGFloat) {
        if width >= ReaderLayout.wideMinWidth {
            self = .wide
        } else if width >= ReaderLayout.mediumMinWidth {
            self = .medium
        } else {
            self = .narrow
        }
    }
}

/// 听读页: native text with word-level highlight that follows the narration.
/// 专注模式 (⌃⌘F) hides the navigation bar, the tab bar, the status bar and the side panel; the text and the
/// player stay, with a visible 退出专注 button. A tapped word still opens its card, as a drawer or a sheet.
struct ReaderView: View {
    let ref: ArticleRef

    @Environment(ReadingSession.self) private var session
    @Environment(UserStore.self) private var user
    @Environment(PackStore.self) private var packs
    @Environment(StudyStore.self) private var study
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var lastUserScroll = Date.distantPast
    @State private var showSettings = false
    @State private var showQuiz = false
    @State private var width: CGFloat = 0
    @State private var measured = false
    @State private var lastLayout: ReaderLayout?

    /// The text column with its ▷ margin: about 720 pt of English per line in wide windows (UI-P01).
    static let textColumnWidth: CGFloat = 770

    private var layout: ReaderLayout { ReaderLayout(width: layoutWidth) }
    /// The window's width once RootView has measured it; the reader's own width before that.
    private var layoutWidth: CGFloat { router.windowWidth > 0 ? router.windowWidth : width }
    private var focus: Bool { router.readerFocus }

    var body: some View {
        presented
            .onAppear { session.open(ref) }
            .onChange(of: ref) { _, newRef in session.open(newRef) }
            .onDisappear {
                session.flushProgress()
                session.cancelChunkSelection()
                // Leaving the reader (not just switching tabs) ends 专注模式.
                if !router.libraryPath.contains(ref) {
                    router.readerFocus = false
                }
            }
            .onChange(of: packs.lexiconReady) { _, ready in
                if ready { session.refreshMarks() }
            }
            .onChange(of: router.readerFocus) { _, on in focusChanged(on) }
            .onChange(of: session.showInspector) { _, open in
                if open && layout == .wide && !focus {
                    router.inspectorClosedByLearner = false
                }
            }
            .onChange(of: session.chunkMode) { _, on in
                // Picking a chunk needs the text: the drawer and the sheet get out of the way.
                if on && (layout != .wide || focus) {
                    session.showInspector = false
                }
            }
    }

    // MARK: Layers

    private var presented: some View {
        framed
            .sheet(isPresented: Bindable(session).chunkReady, onDismiss: { session.cancelChunkSelection() }) {
                chunkSheet
            }
            .sheet(isPresented: $showQuiz) {
                ArticleQuizView(ref: ref, purpose: "practice")
            }
            .task(id: session.toastID) {
                guard let text = session.toast else { return }
                RootView.announce(text)
                do {
                    try await Task.sleep(for: .seconds(1.6))
                    session.toast = nil
                } catch {
                    // a newer toast replaced this one
                }
            }
    }

    private var framed: some View {
        columns
            .toolbarVisibility(focus ? .hidden : .automatic, for: .navigationBar, .tabBar)
            .statusBarHidden(focus)
            .safeAreaInset(edge: .top, spacing: 0) {
                focusBar
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBars
            }
            .overlay(alignment: .top) {
                toastView
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                widthChanged(newWidth)
            }
            .onChange(of: router.windowWidth) { _, _ in
                if measured { applyLayout() }
            }
    }

    private var columns: some View {
        readerContent
            .overlay(alignment: .trailing) {
                drawerHost
            }
            .navigationTitle(packs.item(ref)?.meta.title ?? "听读")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if measured && layout == .narrow {
                        compactToolbarItems
                    } else {
                        fullToolbarItems
                    }
                }
            }
            .inspector(isPresented: columnBinding) {
                InspectorPanel()
                    .inspectorColumnWidth(min: 300, ideal: 340, max: 380)
            }
    }

    private var readerContent: some View {
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
        .sheet(isPresented: sheetBinding) {
            InspectorPanel()
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
    }

    // MARK: Side panel: column (wide), drawer (medium, 专注模式), sheet (narrow)

    private var columnBinding: Binding<Bool> {
        Binding(
            get: { measured && layout == .wide && !focus && session.showInspector },
            set: { shown in
                guard layout == .wide, !focus else { return }
                session.showInspector = shown
                router.inspectorClosedByLearner = !shown
            }
        )
    }

    private var sheetBinding: Binding<Bool> {
        Binding(
            get: { measured && layout == .narrow && session.showInspector },
            set: { shown in
                if !shown && layout == .narrow {
                    session.showInspector = false
                }
            }
        )
    }

    private var drawerOpen: Bool {
        guard measured, session.showInspector else { return false }
        return layout == .medium || (layout == .wide && focus)
    }

    private var drawerWidth: CGFloat {
        min(380, max(300, (width * 0.4).rounded()))
    }

    private var drawerHost: some View {
        ZStack(alignment: .trailing) {
            if drawerOpen {
                ReaderDrawer(width: drawerWidth) {
                    session.showInspector = false
                }
                .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .trailing))
            }
        }
        .animation(reduceMotion ? nil : Animation.easeInOut(duration: 0.25), value: drawerOpen)
    }

    /// Measured width → layout. The first measurement and every layout change reset the side panel to that
    /// layout's default: open in a wide window (unless the learner closed it), closed below 1180 pt until asked.
    private func widthChanged(_ newWidth: CGFloat) {
        width = newWidth
        measured = true
        applyLayout()
    }

    private func applyLayout() {
        let new = layout
        guard new != lastLayout, !focus else { return }
        lastLayout = new
        switch new {
        case .wide:
            session.showInspector = !router.inspectorClosedByLearner
        case .medium, .narrow:
            session.showInspector = false
        }
    }

    private func toggleInspector() {
        let open = !session.showInspector
        session.showInspector = open
        if layout == .wide && !focus {
            router.inspectorClosedByLearner = !open
        }
    }

    // MARK: 专注模式

    private func setFocus(_ on: Bool) {
        if reduceMotion {
            router.readerFocus = on
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                router.readerFocus = on
            }
        }
    }

    /// Entering hides the side panel; leaving brings back the layout's default.
    private func focusChanged(_ on: Bool) {
        if on {
            session.showInspector = false
        } else if layout == .wide {
            session.showInspector = !router.inspectorClosedByLearner
        } else {
            session.showInspector = false
        }
    }

    @ViewBuilder
    private var focusBar: some View {
        if focus {
            HStack {
                Spacer(minLength: 0)
                Button {
                    setFocus(!router.readerFocus)
                } label: {
                    Label("退出专注", systemImage: "arrow.down.right.and.arrow.up.left")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(.regularMaterial, in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("f", modifiers: [.command, .control])
                .help("退出专注模式（⌃⌘F）")
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
    }

    // MARK: Bars and toast

    @ViewBuilder
    private var bottomBars: some View {
        if session.ref == ref && session.article != nil {
            VStack(spacing: 0) {
                if session.chunkMode {
                    ChunkSelectionBar()
                }
                PlayerBar()
            }
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast = session.toast {
            Text(toast)
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 8)
                .padding(.horizontal, 16)
                .transition(.opacity)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    @ViewBuilder
    private var chunkSheet: some View {
        if let r = session.chunkRange, let sid = session.chunkSentence {
            NavigationStack {
                SaveChunkSheet(target: ChunkTarget(ref: ref, sid: sid, first: r.lowerBound, last: r.upperBound,
                                                   gloss: nil, note: nil, origin: .reader))
            }
        }
    }

    // MARK: Toolbar

    /// Wide and medium windows: every control in the bar.
    @ViewBuilder
    private var fullToolbarItems: some View {
        blindButton
        chineseButton
        Button {
            showSettings = true
        } label: {
            Label("阅读设置", systemImage: "textformat.size")
        }
        .help("阅读设置：字号、标注、译文")
        .popover(isPresented: $showSettings) {
            settingsPopover
        }
        inspectorButton
        focusButton
        Button {
            showQuiz = true
        } label: {
            Label("理解题", systemImage: "checklist")
        }
        .disabled(!quizAvailable)
        .help(quizAvailable ? "做这篇的理解题" : "这篇还没有理解题")
        .accessibilityHint(quizAvailable ? "打开这篇文章的理解题" : "这篇还没有理解题：导入新版内容包（格式 2）以后才有")
        Menu {
            ArticleDifficultyMenu(ref: ref)
        } label: {
            Label(ArticleDifficultyText.label(study.difficulty(ref)), systemImage: "chart.bar")
                .labelStyle(.titleAndIcon)
        }
        .help("我的难度：你自己觉得这篇有多难，用来排材料")
        .accessibilityLabel("我的难度：" + ArticleDifficultyText.short(study.difficulty(ref)))
    }

    /// Narrow windows (< 800 pt): the card and 专注 stay in the bar, the rest goes into 更多, so nothing is cut off.
    @ViewBuilder
    private var compactToolbarItems: some View {
        inspectorButton
        focusButton
        Menu {
            Button {
                session.blind.toggle()
            } label: {
                Label(session.blind ? "显示原文" : "盲听", systemImage: session.blind ? "eye" : "eye.slash")
            }
            Button {
                user.updateSettings { $0.showZh.toggle() }
            } label: {
                Label(user.settings.showZh ? "隐藏中文翻译" : "显示中文翻译", systemImage: "character.bubble")
            }
            Button {
                showSettings = true
            } label: {
                Label("阅读设置", systemImage: "textformat.size")
            }
            Button {
                showQuiz = true
            } label: {
                Label(quizAvailable ? "理解题" : "理解题（这篇还没有）", systemImage: "checklist")
            }
            .disabled(!quizAvailable)
            Menu {
                ArticleDifficultyMenu(ref: ref)
            } label: {
                Label("我的难度：" + ArticleDifficultyText.short(study.difficulty(ref)), systemImage: "chart.bar")
            }
        } label: {
            Label("更多", systemImage: "ellipsis.circle")
        }
        .accessibilityLabel("更多操作")
        .popover(isPresented: $showSettings) {
            settingsPopover
        }
    }

    private var settingsPopover: some View {
        ReaderSettingsView()
            .frame(minWidth: 360, idealWidth: 420, minHeight: 480, idealHeight: 680)
    }

    private var blindButton: some View {
        Button {
            session.blind.toggle()
        } label: {
            Label(session.blind ? "显示原文" : "盲听", systemImage: session.blind ? "eye" : "eye.slash")
        }
        .help("盲听：隐藏原文，只听")
    }

    private var chineseButton: some View {
        Button {
            user.updateSettings { $0.showZh.toggle() }
        } label: {
            Label(user.settings.showZh ? "隐藏中文翻译" : "显示中文翻译",
                  systemImage: user.settings.showZh ? "character.bubble.fill" : "character.bubble")
        }
        .help("显示或隐藏中文翻译")
        .accessibilityValue(user.settings.showZh ? "中文翻译已显示" : "中文翻译已隐藏")
    }

    private var inspectorButton: some View {
        Button {
            toggleInspector()
        } label: {
            Label(session.showInspector ? "收起单词卡" : "单词卡", systemImage: "sidebar.right")
        }
        .keyboardShortcut("i", modifiers: .command)
        .help("打开或收起单词卡（⌘I）")
    }

    private var focusButton: some View {
        Button {
            setFocus(!router.readerFocus)
        } label: {
            Label("专注模式", systemImage: "arrow.up.left.and.arrow.down.right")
        }
        .keyboardShortcut("f", modifiers: [.command, .control])
        .help("专注模式：只留正文和播放器（⌃⌘F）")
    }

    // MARK: Text

    @ViewBuilder
    private func reader(_ art: Article) -> some View {
        let settings = user.settings
        let style = ParagraphStyle(fontSize: Theme.readingPointSize(settings.fontSize, typeSize: typeSize),
                                   threshold: settings.threshold,
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
        let chunkPara = session.chunkSentence.flatMap { session.paragraphIndex(ofSentence: $0) }
        let chunkRange = session.chunkRange

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ArticleHeader(article: art, meta: packs.item(ref)?.meta, titleOn: session.titleOn,
                                  publication: packs.publication(ref))
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
                                    loopSid: loopPara == pi ? loopSid : nil,
                                    chunk: chunkPara == pi ? chunkRange : nil),
                                style: style,
                                session: session
                            )
                            .equatable()
                            .id(pi)
                        }
                    }
                    Color.clear.frame(height: 80)
                }
                .frame(maxWidth: ReaderView.textColumnWidth, alignment: .leading)
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
                // Reduce Motion: jump without the scrolling animation.
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

    /// 理解题 come only with new-format content packs (format 2).
    private var quizAvailable: Bool {
        packs.resources(ref).quiz == .available
    }

    private var blindPosition: String {
        if let sid = session.curSent {
            return "第 \(session.position(of: sid)) / \(session.sentenceCount) 句"
        }
        return "共 \(session.sentenceCount) 句"
    }
}

/// The side panel as a drawer over the text: 800–1179 pt, and in 专注模式 after a word is tapped.
/// The text underneath keeps its width and stays tappable.
private struct ReaderDrawer: View {
    let width: CGFloat
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("单词卡")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭单词卡")
                .help("关闭单词卡")
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            Divider()
            InspectorPanel()
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(.background, ignoresSafeAreaEdges: [])
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 1)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 14, x: -3, y: 0)
        .accessibilityElement(children: .contain)
    }
}

/// Reading options: the Aa button in the reader, and 设置 → 显示 → 阅读字号与标注.
struct ReaderSettingsView: View {
    @Environment(UserStore.self) private var user
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Original sample sentence for the preview (no magazine text in the app).
    static let previewSentence = "Reading a little every day makes a big difference."

    var body: some View {
        Form {
            textSection
            marksSection
            listeningSection
            keysSection
        }
        .navigationTitle("阅读设置")
    }

    // MARK: Sections

    private var textSection: some View {
        Section {
            preview
            Stepper(value: sizeBinding, in: ReaderSettings.fontSizeRange, step: 1) {
                Text(sizeTitle)
            }
            HStack(spacing: 12) {
                Text("A")
                    .font(Font.system(size: 15, design: .serif))
                    .accessibilityHidden(true)
                Slider(value: sizeBinding, in: ReaderSettings.fontSizeRange, step: 1)
                    .accessibilityLabel("英文正文字号")
                    .accessibilityValue("\(Int(fontSize)) pt")
                Text("A")
                    .font(Font.system(size: 27, design: .serif))
                    .accessibilityHidden(true)
            }
            if fontSize != ReaderSettings.defaultFontSize {
                Button("恢复默认 24 pt") {
                    user.updateSettings { $0.fontSize = ReaderSettings.defaultFontSize }
                }
            }
            Toggle("显示中文翻译", isOn: binding(\.showZh))
        } header: {
            Text("文字")
        } footer: {
            Text("英文正文可以在 18–34 pt 之间调，默认 24 pt。iPad 的系统文字大小调大时，正文和界面文字会一起放大，最大字号下也不会被截断。")
        }
    }

    private var marksSection: some View {
        Section {
            ChoicePicker("下划线标注", selection: binding(\.threshold)) {
                Text("5+").tag(5)
                Text("6+").tag(6)
                Text("7+").tag(7)
                Text("8").tag(8)
                Text("关").tag(0)
            }
            Toggle("熟词僻义（点状下划线）", isOn: binding(\.showTrap))
            Toggle("短语（虚线）", isOn: binding(\.showPhrase))
        } header: {
            Text("标注")
        } footer: {
            Text("颜色：5 级青、6 级蓝、7 级紫、8 级橙。点一个词，单词卡上会写出它的等级。标成“认识”的词不再标注。")
        }
    }

    private var listeningSection: some View {
        Section("听读") {
            Toggle("点词时暂停播放", isOn: binding(\.pauseOnTap))
            Toggle("自动跟随朗读滚动", isOn: binding(\.follow))
            Picker("循环间隔", selection: binding(\.loopGap)) {
                ForEach(ReaderSettings.loopGaps, id: \.self) { g in
                    Text(g == 0 ? "不停" : String(format: "%g 秒", g)).tag(g)
                }
            }
            ChoicePicker("系统朗读口音", selection: binding(\.accent)) {
                Text("英音").tag("en-GB")
                Text("美音").tag("en-US")
            }
        }
    }

    /// PLAT-09: the shortcuts, and when they are off.
    private var keysSection: some View {
        Section {
            LabeledContent("播放 / 暂停", value: "空格")
            LabeledContent("上一句 / 下一句", value: "← / →")
            LabeledContent("单句循环", value: "L")
            LabeledContent("打开或收起单词卡", value: "⌘I")
            LabeledContent("专注模式", value: "⌃⌘F")
        } header: {
            Text("键盘快捷键（外接键盘）")
        } footer: {
            Text("在输入框里打字时，单键快捷键自动停用，不会误触播放或录音。")
        }
    }

    // MARK: Pieces

    private var fontSize: Double { user.settings.fontSize }

    private var sizeTitle: String {
        let n = Int(fontSize)
        return fontSize == ReaderSettings.defaultFontSize ? "英文正文 \(n) pt（默认）" : "英文正文 \(n) pt"
    }

    private var preview: some View {
        let points = Theme.readingPointSize(fontSize, typeSize: typeSize)
        let scaled = Int(points)
        let base = Int(fontSize)
        return VStack(alignment: .leading, spacing: 6) {
            Text(ReaderSettingsView.previewSentence)
                .font(Theme.readingFont(size: points))
                .lineSpacing(Theme.readingLineSpacing(points))
                .fixedSize(horizontal: false, vertical: true)
            Text(scaled == base ? "预览：\(base) pt" : "预览：\(base) pt，随系统文字大小放大到约 \(scaled) pt")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var sizeBinding: Binding<Double> {
        Binding(
            get: { user.settings.fontSize },
            set: { value in
                let clean = ReaderSettings.clampedFontSize(value)
                user.updateSettings { $0.fontSize = clean }
            }
        )
    }

    private func binding<T>(_ path: WritableKeyPath<ReaderSettings, T>) -> Binding<T> {
        Binding(
            get: { user.settings[keyPath: path] },
            set: { value in user.updateSettings { $0[keyPath: path] = value } }
        )
    }
}
