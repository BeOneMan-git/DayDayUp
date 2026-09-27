import SwiftUI
import Observation

// Small pieces shared by the 进度 page and the weekly report.

/// Dates and numbers in the same short style everywhere ("9/21", "9/21 20:05").
enum ProgressFormat {
    /// "2026-09-21" → "9/21".
    static func short(_ day: String) -> String {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return day }
        return "\(parts[1])/\(parts[2])"
    }

    /// "9/21", or "2025/9/21" when it is not this year.
    static func short(_ date: Date) -> String {
        let key = DayKey.of(date)
        if key.prefix(4) == DayKey.today.prefix(4) { return short(key) }
        return String(key.prefix(4)) + "/" + short(key)
    }

    static func time(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func dayTime(_ date: Date) -> String {
        short(date) + " " + time(date)
    }

    /// "9/21–9/27" for the week that starts on `monday`.
    static func weekRange(_ monday: String) -> String {
        short(monday) + "–" + short(DayKey.adding(6, to: monday))
    }

    static func whole(_ value: Double) -> Int {
        value.isFinite ? Int(value.rounded()) : 0
    }

    static func percent(_ part: Int, _ whole: Int) -> Int {
        guard whole > 0 else { return 0 }
        return Int((Double(part) / Double(whole) * 100).rounded())
    }

    /// Start of the first day of a window of `days` days that ends today.
    static func windowStart(days: Int, now: Date = Date()) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        return cal.date(byAdding: .day, value: -(max(1, days) - 1), to: today) ?? today
    }
}

/// One card with a title, its content and a one-line "怎么算的" footnote.
struct ProgressCard<Content: View>: View {
    let title: String
    let symbol: String
    let footnote: String?
    let content: Content

    init(_ title: String, symbol: String, footnote: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.footnote = footnote
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content
            if let footnote {
                Label(footnote, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Group title: "投入（花了多少时间）" / "证据（练得怎么样）".
struct ProgressGroupHeader: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Small sub-heading inside a card.
struct ProgressSubhead: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }
}

/// "样本少" / "证据不足": symbol + text, never colour alone (MET-P02, VOC-P05).
struct SmallSampleTag: View {
    let text: String

    init(_ text: String = "样本少") {
        self.text = text
    }

    var body: some View {
        Label(text, systemImage: "exclamationmark.circle")
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.warn)
    }
}

/// A collapsed group with a 44 pt tap target (其他、已撤回、原始记录…).
struct ProgressDisclosure<Content: View>: View {
    let title: String
    let content: Content
    @State private var expanded = false

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .frame(width: 20)
                    Text(title)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Text(expanded ? "收起" : "展开")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                content
            }
        }
    }
}

// MARK: Listening back (MET-04)

/// One player for the whole page, so only one recording plays at a time.
@MainActor
@Observable
final class ProgressPlayback {
    let player: SegmentPlayer
    private(set) var currentID: String?

    init() {
        player = SegmentPlayer()
    }

    func isPlaying(_ id: String) -> Bool {
        currentID == id && player.playing == .mine
    }

    func play(_ id: String, url: URL) {
        currentID = id
        Task { [player] in
            await player.play(url, as: .mine)
        }
    }

    func stop() {
        player.stop()
        currentID = nil
    }
}

/// 回听 / 停止 for one recording; "录音已清理" when the file is gone.
struct RecordingPlayButton: View {
    let id: String
    let file: String?
    let playback: ProgressPlayback
    @Environment(PracticeStore.self) private var practice
    @Environment(PlaybackEngine.self) private var engine

    var body: some View {
        if let url = practice.recordingURL(file) {
            let on = playback.isPlaying(id)
            Button {
                if on {
                    playback.stop()
                } else {
                    engine.pause()
                    playback.play(id, url: url)
                }
            } label: {
                Label(on ? "停止" : "回听", systemImage: on ? "stop.fill" : "play.fill")
                    .frame(minWidth: 72, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        } else {
            Label("录音已清理", systemImage: "speaker.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
        }
    }
}
