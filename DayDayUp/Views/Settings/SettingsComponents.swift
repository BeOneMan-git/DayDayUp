import SwiftUI
import AVFoundation

// Small pieces shared by the 设置 pages.

/// A settings row: symbol and title on the left, the current value on the right.
struct SettingsLinkLabel: View {
    let title: String
    let symbol: String
    var value: String? = nil

    var body: some View {
        if let value {
            LabeledContent {
                Text(value)
            } label: {
                Label(title, systemImage: symbol)
            }
        } else {
            Label(title, systemImage: symbol)
        }
    }
}

/// Title plus a one-line explanation, used as the label of a picker or toggle.
struct SettingsItemTitle: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A read-only line: symbol, short title, plain explanation.
struct SettingsNoteRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Theme.accent)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Sizes and free space, in the same style on every page.
enum SettingsFormat {
    /// "12.3 MB" (1 MB = 1 000 000 bytes, like the rest of the app).
    static func megabytes(_ bytes: Int) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_000_000)
    }

    static func gigabytes(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }

    /// Free space on the iPad for things the learner wants to keep; nil when it cannot be read.
    static func freeSpace() -> Int64? {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        if let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let free = values.volumeAvailableCapacityForImportantUsage {
            return free
        }
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let free = attrs[.systemFreeSize] as? NSNumber {
            return free.int64Value
        }
        return nil
    }
}

/// Microphone permission as the system reports it (ACC-14). Read again when the app comes back to the front.
enum MicrophoneStatus: Equatable {
    case granted, denied, notAsked

    static func current() -> MicrophoneStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        default: return .notAsked
        }
    }

    var text: String {
        switch self {
        case .granted: return "已允许"
        case .denied: return "没有允许"
        case .notAsked: return "还没问过"
        }
    }

    var detail: String {
        switch self {
        case .granted: return "跟读、口语和词汇朗读可以录音。录音只存在这台 iPad 上。"
        case .denied: return "现在录不了音。听读、词汇和写作照常能用。要录音，在 iPad 的“设置”里打开麦克风。"
        case .notAsked: return "第一次点录音时，iPad 会问你是否允许。"
        }
    }

    var symbol: String {
        switch self {
        case .granted: return "mic"
        case .denied: return "mic.slash"
        case .notAsked: return "questionmark.circle"
        }
    }
}
