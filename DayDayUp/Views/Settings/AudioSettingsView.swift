import SwiftUI

/// 音频 (PAGE-08, ACC-25): the sound settings of 听读, 跟读 and word audio, each with its unit and what it changes,
/// and what playback does when the screen locks, headphones come out or a call comes in.
/// The notes only describe what the code does (PlaybackEngine, RecorderService, DayDayUpApp's scene handling).
struct AudioSettingsView: View {
    @Environment(UserStore.self) private var user
    @Environment(ReadingSession.self) private var session

    var body: some View {
        Form {
            listeningSection
            shadowSection
            voiceSection
            playbackSection
            troubleSection
        }
        .navigationTitle("声音与速度")
    }

    // MARK: 听读

    private var listeningSection: some View {
        Section {
            Picker(selection: rateBinding) {
                ForEach(ReaderSettings.rates, id: \.self) { r in
                    Text(AudioSettingsView.rateText(r)).tag(r)
                }
            } label: {
                SettingsItemTitle(title: "听读速度",
                                  detail: "文章原声放多快。变速不变调；听读页底部的速度按钮改的也是它。")
            }
            Picker(selection: choice(\.loopGap, options: ReaderSettings.loopGaps)) {
                ForEach(ReaderSettings.loopGaps, id: \.self) { g in
                    Text(AudioSettingsView.secondsText(g, zero: "不停")).tag(g)
                }
            } label: {
                SettingsItemTitle(title: "循环间隔",
                                  detail: "单句循环和 A–B 循环时，放完一遍，停多久再放。")
            }
        } header: {
            Text("听读")
        } footer: {
            Text("改了马上生效，下一次播放就用新的设置。")
        }
    }

    // MARK: 跟读

    private var shadowSection: some View {
        Section {
            Picker(selection: choice(\.shadowRate, options: ReaderSettings.shadowRates)) {
                ForEach(ReaderSettings.shadowRates, id: \.self) { r in
                    Text(AudioSettingsView.rateText(r)).tag(r)
                }
            } label: {
                SettingsItemTitle(title: "原音速度",
                                  detail: "跟读时原句放多快。慢一点更好模仿；默认 0.85×。")
            }
            Picker(selection: choice(\.abGap, options: ReaderSettings.abGaps)) {
                ForEach(ReaderSettings.abGaps, id: \.self) { g in
                    Text(AudioSettingsView.secondsText(g, zero: "不停顿")).tag(g)
                }
            } label: {
                SettingsItemTitle(title: "A/B 间隔",
                                  detail: "A/B 对照时，原句放完，隔多久再放你的录音。")
            }
            Picker(selection: choice(\.retellSeconds, options: ReaderSettings.retellTimes)) {
                ForEach(ReaderSettings.retellTimes, id: \.self) { t in
                    Text("\(Int(t)) 秒").tag(t)
                }
            } label: {
                SettingsItemTitle(title: "复述时长",
                                  detail: "脱稿复述的目标时间。到了可以接着讲；最长是目标的 1.5 倍，至少 90 秒。")
            }
        } header: {
            Text("跟读")
        } footer: {
            Text("跟读页里也能改这三项，两边是同一个设置。基础阶段复述 30–60 秒，发展阶段 60–120 秒。")
        }
    }

    // MARK: 单词发音

    private var voiceSection: some View {
        Section {
            Picker(selection: accentBinding) {
                Text("英音（en-GB）").tag("en-GB")
                Text("美音（en-US）").tag("en-US")
            } label: {
                SettingsItemTitle(title: "合成音的口音",
                                  detail: "没有文章原声时，单词卡的“朗读”、例句和词汇复习用 iPad 的合成音读。")
            }
        } header: {
            Text("单词发音")
        } footer: {
            Text("单词卡上的“英”“美”按钮固定读英音、美音；“听词”列表现在总是英音。合成音都标着“合成音”，它不是文章的主播。")
        }
    }

    // MARK: 播放说明 (ACC-25)

    private var playbackSection: some View {
        Section {
            SettingsNoteRow(symbol: "lock", title: "锁屏后继续放",
                            detail: "听读的原声在锁屏或切到别的 App 以后会继续放。这段时间记成“后台播放”，不算有效练习。")
            SettingsNoteRow(symbol: "headphones", title: "拔下耳机会暂停",
                            detail: "听读时拔下耳机，或者蓝牙耳机断开，播放自动暂停，不会突然从扬声器放出来。")
            SettingsNoteRow(symbol: "switch.2", title: "控制中心和锁屏上可以操作",
                            detail: "可以暂停、继续、上一句、下一句，也可以拖动进度。耳机上的播放键也能用。")
            SettingsNoteRow(symbol: "phone", title: "来电话、闹钟、Siri",
                            detail: "播放会停下。结束以后，如果系统允许，会接着放；没有接着放，就点播放。")
            SettingsNoteRow(symbol: "mic", title: "录音的时候不放",
                            detail: "正在录音时，播放键（包括锁屏和耳机上的）不起作用，免得原声盖住你的声音。切到后台或锁屏，录音会停下，已经录的部分保存，标着“被打断”。")
            SettingsNoteRow(symbol: "exclamationmark.circle", title: "不保证的情况",
                            detail: "跟读的原句、听词和单词发音只在 App 打开时使用，锁屏以后可能停下。")
        } header: {
            Text("播放说明")
        } footer: {
            Text("这里只写 App 确实做到的事。")
        }
    }

    private var troubleSection: some View {
        Section {
            SettingsNoteRow(symbol: "arrow.clockwise", title: "回到 App，点播放",
                            detail: "大多数时候这样就好了。")
            SettingsNoteRow(symbol: "speaker.wave.2", title: "还是没有声音",
                            detail: "看看 iPad 的静音开关和音量，蓝牙耳机有没有连着别的设备。")
            SettingsNoteRow(symbol: "xmark.app", title: "再不行",
                            detail: "从屏幕底部上滑并停一下，打开多任务界面，把 DayDayUp 向上滑走，再重新打开。学习记录不会丢。")
        } header: {
            Text("声音停了怎么办")
        }
    }

    // MARK: Bindings

    /// The listening rate goes through the reading session, so the player changes speed at once.
    private var rateBinding: Binding<Double> {
        Binding<Double>(
            get: { AudioSettingsView.nearest(user.settings.rate, in: ReaderSettings.rates) },
            set: { value in session.setRate(value) }
        )
    }

    /// A stored value that is not in the list (an older version) shows as the nearest option.
    private func choice(_ path: WritableKeyPath<ReaderSettings, Double>, options: [Double]) -> Binding<Double> {
        Binding<Double>(
            get: { AudioSettingsView.nearest(user.settings[keyPath: path], in: options) },
            set: { value in user.updateSettings { $0[keyPath: path] = value } }
        )
    }

    private var accentBinding: Binding<String> {
        Binding<String>(
            get: { user.settings.accent == "en-US" ? "en-US" : "en-GB" },
            set: { value in user.updateSettings { $0.accent = value } }
        )
    }

    // MARK: Text

    static func nearest(_ value: Double, in options: [Double]) -> Double {
        options.min { abs($0 - value) < abs($1 - value) } ?? value
    }

    /// "1.0×", "0.85×".
    static func rateText(_ r: Double) -> String {
        abs(r - 1) < 0.001 ? "1.0×" : String(format: "%g×", r)
    }

    /// "0.5 秒", or `zero` for no pause.
    static func secondsText(_ s: Double, zero: String) -> String {
        s < 0.001 ? zero : String(format: "%g 秒", s)
    }
}
