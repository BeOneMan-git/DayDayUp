import SwiftUI

/// Bottom transport bar. Keyboard: space play/pause, ← → previous/next sentence, L loop.
struct PlayerBar: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(ReadingSession.self) private var session
    @Environment(UserStore.self) private var user
    @State private var scrubValue: Double?

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                Text(formatTime(scrubValue ?? engine.time))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
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
                Text(formatTime(engine.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .leading)
            }
            HStack(spacing: 2) {
                rateMenu
                Spacer(minLength: 8)
                iconButton("gobackward.5", "后退 5 秒") { engine.skip(-5) }
                iconButton("backward.end.fill", "上一句") { session.moveSentence(-1) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                playButton
                    .keyboardShortcut(.space, modifiers: [])
                iconButton("forward.end.fill", "下一句") { session.moveSentence(1) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                iconButton("goforward.5", "前进 5 秒") { engine.skip(5) }
                Spacer(minLength: 8)
                toggleButton("repeat.1", "单句循环", isOn: session.loopSid != nil) { session.toggleLoop() }
                    .keyboardShortcut("l", modifiers: [])
                toggleButton("pause.rectangle", "逐句暂停", isOn: session.stepMode) { session.toggleStepMode() }
                toggleButton("scroll", "自动跟随", isOn: user.settings.follow) {
                    user.updateSettings { $0.follow.toggle() }
                }
                Text(counterText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 92, alignment: .trailing)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.bar)
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
                .frame(width: 60, height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(engine.isPlaying ? "暂停" : "播放")
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
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    private func toggleButton(_ symbol: String, _ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(isOn ? Theme.accent : Color.secondary)
                .frame(width: 44, height: 44)
                .background(isOn ? Theme.accent.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "开" : "关")
        .help(label)
    }
}
