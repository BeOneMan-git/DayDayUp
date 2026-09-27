import SwiftUI

/// 能力清单 (OFF-01): what works on this iPad without a network, with live checks where the device matters
/// (content packs, microphone, system voices), and what V1.0 does not switch on, each with a plain reason.
struct CapabilityListView: View {
    @Environment(PackStore.self) private var packs
    @Environment(\.scenePhase) private var scenePhase

    @State private var mic = MicrophoneStatus.notAsked
    @State private var hasBritishVoice = true
    @State private var hasAmericanVoice = true

    var body: some View {
        List {
            Section {
                ForEach(offlineItems) { item in
                    CapabilityRow(item: item, enabled: true)
                }
            } header: {
                Text("断网也能做")
            } footer: {
                Text("这些都在 iPad 上完成，不用联网，也不会上传。")
            }
            Section {
                ForEach(disabledItems) { item in
                    CapabilityRow(item: item, enabled: false)
                }
            } header: {
                Text("没有启用")
            } footer: {
                Text("这些功能以后要先单独核对效果，才会考虑打开。现在可以用录音回放、A/B 对照、自评和人工反馈代替。")
            }
        }
        .navigationTitle("能力清单")
        .onAppear { refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
    }

    private func refresh() {
        mic = MicrophoneStatus.current()
        hasBritishVoice = SpeechQueue.hasVoice("en-GB")
        hasAmericanVoice = SpeechQueue.hasVoice("en-US")
    }

    // MARK: Lists

    private var listenStatus: String {
        let items = packs.allItems
        guard !items.isEmpty else { return "现在：还没有内容包。" }
        let ready = items.filter { PackLabels.canListenOffline(packs.resources($0.ref)) }.count
        return "现在：\(ready)/\(items.count) 篇文章可以断网听读。"
    }

    private var voiceStatus: String {
        let gb = hasBritishVoice ? "英音有" : "英音没有"
        let us = hasAmericanVoice ? "美音有" : "美音没有"
        var text = "现在：\(gb)，\(us)。"
        if !hasBritishVoice || !hasAmericanVoice {
            text += "缺的声音可以在 iPad 的“设置 › 辅助功能 › 朗读内容 › 声音”里下载。"
        }
        return text
    }

    private var offlineItems: [CapabilityItem] {
        [
            CapabilityItem(symbol: "headphones", title: "听读与跟读播放",
                           detail: "原声在内容包里，已经存在 iPad 上。", status: listenStatus),
            CapabilityItem(symbol: "mic", title: "录音与回放",
                           detail: "录音只存在这台 iPad 上。", status: "现在：麦克风\(mic.text)。"),
            CapabilityItem(symbol: "arrow.left.arrow.right", title: "A/B 对比",
                           detail: "原句和你的录音前后接着放。", status: nil),
            CapabilityItem(symbol: "character.book.closed", title: "词汇排期与复习",
                           detail: "FSRS 排期在 iPad 上计算。", status: nil),
            CapabilityItem(symbol: "sun.max", title: "今日计划",
                           detail: "按你的设置和记录，在 iPad 上排。", status: nil),
            CapabilityItem(symbol: "chart.bar", title: "进度统计",
                           detail: "只用这台 iPad 上的记录计算。", status: nil),
            CapabilityItem(symbol: "doc.text", title: "周报导出",
                           detail: "JSON、CSV、PDF 文件在 iPad 上生成，存到哪里由你决定。", status: nil),
            CapabilityItem(symbol: "externaldrive", title: "完整备份与恢复",
                           detail: "备份文件在 iPad 上打包；恢复也在 iPad 上完成。", status: nil),
            CapabilityItem(symbol: "speaker.wave.2", title: "单词合成音",
                           detail: "没有原声时，用 iPad 自带的声音读单词和例句。", status: voiceStatus),
        ]
    }

    private var disabledItems: [CapabilityItem] {
        [
            CapabilityItem(symbol: "waveform.and.mic", title: "语音识别",
                           detail: "V1.0 不做；识别要单独核对准确度。", status: nil),
            CapabilityItem(symbol: "mouth", title: "发音自动诊断",
                           detail: "V1.0 不做；自动判断容易出错。先用 A/B 对照自己听，再看发音标注。", status: nil),
            CapabilityItem(symbol: "text.badge.checkmark", title: "写作自动反馈",
                           detail: "V1.0 不做；可以用“复制给 Claude”或拿给老师看，再把意见录进来。", status: nil),
            CapabilityItem(symbol: "icloud.slash", title: "云同步与上传",
                           detail: "V1.0 不做；App 不联网。换 iPad 时用完整备份带走数据。", status: nil),
        ]
    }
}

/// One capability with how it works and, where it depends on this iPad, what the check found.
struct CapabilityItem: Identifiable {
    let symbol: String
    let title: String
    let detail: String
    let status: String?
    var id: String { title }
}

private struct CapabilityRow: View {
    let item: CapabilityItem
    let enabled: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.symbol)
                .font(.title3)
                .foregroundStyle(enabled ? Theme.accent : Color.secondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                Label(enabled ? "断网可用" : "没有启用",
                      systemImage: enabled ? "checkmark.circle.fill" : "minus.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(enabled ? Theme.level5 : Color.secondary)
                Text(item.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let status = item.status {
                    Text(status)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
