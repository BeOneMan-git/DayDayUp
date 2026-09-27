import SwiftUI

/// Bottom transport bar. Keyboard: space play/pause, ← → previous/next sentence, L loop.
/// One row when it fits; in a narrow window or at large text sizes the transport buttons get their own row and
/// the options wrap below, so no control is cut off (ACC-24).
struct PlayerBar: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(ReadingSession.self) private var session
    @Environment(UserStore.self) private var user
    @Environment(Router.self) private var router
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var scrubValue: Double?
    @State private var barWidth: CGFloat = 0

    /// Single-key shortcuts only while the library tab is showing and no text is being edited anywhere,
    /// so typing in a text field (a sheet's note, 写作, a search field) never starts playback (PLAT-09, ACC-24).
    private func key(_ k: KeyEquivalent) -> KeyboardShortcut? {
        guard router.tab == .library, !router.isEditingText else { return nil }
        return KeyboardShortcut(k, modifiers: [])
    }

    /// The single row needs about 700 pt at the default text size, more at larger sizes.
    private var twoRows: Bool {
        if typeSize.isAccessibilitySize { return true }
        let needed: CGFloat = typeSize >= .xLarge ? 780 : 700
        return barWidth > 0 && barWidth < needed
    }

    var body: some View {
        VStack(spacing: 4) {
            scrubber
            if twoRows {
                VStack(spacing: 6) {
                    transport
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        rateMenu
                        options
                        counter
                    }
                }
            } else {
                HStack(spacing: 2) {
                    rateMenu
                    Spacer(minLength: 8)
                    transport
                    Spacer(minLength: 8)
                    options
                    counter
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.bar)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            barWidth = newWidth
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("播放器")
    }

    private var scrubber: some View {
        HStack(spacing: 12) {
            Text(formatTime(scrubValue ?? engine.time))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 48, alignment: .trailing)
                .fixedSize()
                .accessibilityHidden(true)
            Slider(
                value: Binding(get: { scrubValue ?? engine.time }, set: { scrubValue = $0 }),
                in: 0...max(1, engine.duration),
                onEditingChanged: { editing in
                    if !editing, let v = scrubValue {
                        engine.seek(to: v)
                        scrubValue = nil
                    }
                }
            )
            .accessibilityLabel("播放进度")
            .accessibilityValue("\(spokenTime(scrubValue ?? engine.time))，共 \(spokenTime(engine.duration))")
            Text(formatTime(engine.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 48, alignment: .leading)
                .fixedSize()
                .accessibilityHidden(true)
        }
    }

    /// −5 s, previous sentence, play / pause, next sentence, +5 s.
    private var transport: some View {
        HStack(spacing: 2) {
            iconButton("gobackward.5", "后退 5 秒") { engine.skip(-5) }
            iconButton("backward.end.fill", "上一句") { session.moveSentence(-1) }
                .keyboardShortcut(key(.leftArrow))
            playButton
                .keyboardShortcut(key(.space))
            iconButton("forward.end.fill", "下一句") { session.moveSentence(1) }
                .keyboardShortcut(key(.rightArrow))
            iconButton("goforward.5", "前进 5 秒") { engine.skip(5) }
        }
    }

    /// Loop, A–B, step-by-step and follow switches.
    private var options: some View {
        HStack(spacing: 2) {
            toggleButton("repeat.1", "单句循环", isOn: session.loopSid != nil) { session.toggleLoop() }
                .keyboardShortcut(key("l"))
            abButton
            toggleButton("pause.rectangle", "逐句暂停", isOn: session.stepMode) { session.toggleStepMode() }
            toggleButton("scroll", "自动跟随", isOn: user.settings.follow) {
                user.updateSettings { $0.follow.toggle() }
            }
        }
    }

    private var counter: some View {
        Text(counterText)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(minWidth: 92, minHeight: 44, alignment: .trailing)
            .fixedSize()
    }

    /// A–B loop: first tap sets A, second sets B, third turns it off.
    private var abButton: some View {
        let state = session.abState
        return Button {
            session.tapAB()
        } label: {
            Text(state == 0 ? "A–B" : (state == 1 ? "A–?" : "A–B"))
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(state == 0 ? Color.secondary : Theme.accent)
                .padding(.horizontal, 6)
                .frame(minWidth: 52, minHeight: 44)
                .background(state == 0 ? Color.clear : Theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("A–B 循环")
        .accessibilityValue(state == 0 ? "关" : (state == 1 ? "已设 A 点" : "开"))
        .help("A–B 循环：点一次设 A，再点一次设 B，第三次关闭")
    }

    private var counterText: String {
        if let sid = session.curSent {
            return "第 \(session.position(of: sid)) / \(session.sentenceCount) 句"
        }
        return "共 \(session.sentenceCount) 句"
    }

    private var playButton: some View {
        Button {
            session.togglePlay()
        } label: {
            Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 44))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.accent)
                .frame(minWidth: 60, minHeight: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(engine.isPlaying ? "暂停" : "播放")
        .help(engine.isPlaying ? "暂停（空格）" : "播放（空格）")
    }

    private var rateMenu: some View {
        Menu {
            ForEach(ReaderSettings.rates, id: \.self) { r in
                Button {
                    session.setRate(r)
                } label: {
                    if abs(r - engine.rate) < 0.001 {
                        Label(rateText(r), systemImage: "checkmark")
                    } else {
                        Text(rateText(r))
                    }
                }
            }
        } label: {
            Text(rateText(engine.rate))
                .font(.callout.monospacedDigit().weight(.semibold))
                .frame(minWidth: 56, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("语速 \(rateText(engine.rate))")
    }

    private func rateText(_ r: Double) -> String {
        abs(r - 1) < 0.001 ? "1.0×" : String(format: "%g×", r)
    }

    private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    /// On = accent symbol on a filled rounded square (a shape, not only a colour) and "开" for VoiceOver.
    private func toggleButton(_ symbol: String, _ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(isOn ? Theme.accent : Color.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .background(isOn ? Theme.accent.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    if isOn {
                        RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent, lineWidth: 1.5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "开" : "关")
        .help(isOn ? "\(label)：开" : "\(label)：关")
    }
}
