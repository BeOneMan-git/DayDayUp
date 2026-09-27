import SwiftUI
import UIKit

/// Live recording time and input level (PLAT-08: 录音状态需可读可感知).
/// The state is a symbol plus words ("正在录音 0:12"), never the red colour alone; VoiceOver reads it as one element
/// with the time as its value. RootView announces the start and the end of every recording.
struct RecordingMeter: View {
    let elapsed: Double
    let level: Double
    let limit: Double
    /// Time the task asks for (口语 45 s). After it, the bar turns orange but recording goes on.
    let target: Double?

    var body: some View {
        let over = target.map { elapsed >= $0 } ?? false
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 12, lineSpacing: 4) {
                Label {
                    Text("正在录音 \(formatTime(elapsed))")
                        .font(.headline.monospacedDigit())
                } icon: {
                    Image(systemName: "record.circle.fill")
                        .foregroundStyle(.red)
                }
                if let target {
                    Label(over ? "已到 \(formatTime(target))，可以继续说，也可以停" : "目标 \(formatTime(target))",
                          systemImage: over ? "checkmark.circle" : "timer")
                        .font(.callout)
                        .foregroundStyle(over ? Theme.warn : Color.secondary)
                }
                Text("最长 \(formatTime(limit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule()
                        .fill(over ? Theme.warn : Theme.accent)
                        .frame(width: max(4, geo.size.width * level))
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
        }
        .padding(14)
        .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(Color.red.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在录音")
        .accessibilityValue(spokenValue(over: over))
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func spokenValue(over: Bool) -> String {
        var parts = ["已录 \(spokenTime(elapsed))"]
        if let target {
            parts.append(over ? "已到目标 \(spokenTime(target))，可以继续，也可以停" : "目标 \(spokenTime(target))")
        }
        parts.append("最长 \(spokenTime(limit))")
        return parts.joined(separator: "，")
    }
}

/// Shown when the microphone permission is off (ACC-14): say why, keep the rest usable.
struct MicrophoneDeniedCard: View {
    var openSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "mic.slash")
                .font(.title2)
                .foregroundStyle(Theme.warn)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("麦克风权限已关闭").font(.headline)
                Text("跟读和口语要录下你的声音，录音只存在这台 iPad 上。听读、词汇和写作照常能用。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(action: openSettings) {
                    Text("去“设置”打开麦克风")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warn.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Four-criteria self-assessment: ticks plus evidence, no score (IEL-C4).
struct SelfCheckForm: View {
    let dims: [CheckDimension]
    @Binding var check: SelfCheck

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(dims.enumerated()), id: \.element.id) { di, dim in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(dim.title).font(.headline)
                        Text(dim.en).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(Array(dim.questions.enumerated()), id: \.offset) { qi, question in
                        Toggle(question, isOn: answer(di, qi))
                    }
                    TextField("证据：写下具体的词、句子或停顿的地方", text: note(di), axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                }
            }
        }
    }

    private func answer(_ di: Int, _ qi: Int) -> Binding<Bool> {
        Binding(
            get: {
                guard check.dims.indices.contains(di), check.dims[di].answers.indices.contains(qi) else { return false }
                return check.dims[di].answers[qi]
            },
            set: { value in
                guard check.dims.indices.contains(di), check.dims[di].answers.indices.contains(qi) else { return }
                check.dims[di].answers[qi] = value
            }
        )
    }

    private func note(_ di: Int) -> Binding<String> {
        Binding(
            get: { check.dims.indices.contains(di) ? check.dims[di].note : "" },
            set: { value in
                guard check.dims.indices.contains(di) else { return }
                check.dims[di].note = value
            }
        )
    }
}

/// A submitted self-assessment, read-only.
struct SelfCheckSummary: View {
    let dims: [CheckDimension]
    let check: SelfCheck

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(dims) { dim in
                let entry = check.dims.first { $0.id == dim.id }
                let ticks = entry?.answers.filter { $0 }.count ?? 0
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(dim.title).font(.subheadline.weight(.semibold))
                        Text("做到 \(ticks)/\(dim.questions.count) 项")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let note = entry?.note, !note.isEmpty {
                        Text(note).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// Types in feedback from a teacher, Claude or someone else (IEL-F05).
/// The app sends nothing anywhere; the learner copies the work out and pastes the answer back.
struct FeedbackSheet: View {
    var onSave: (Feedback) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var source = "Claude"
    @State private var text = ""

    static let sources = ["老师", "Claude", "其他"]

    var body: some View {
        NavigationStack {
            Form {
                Section("来源") {
                    Picker("来源", selection: $source) {
                        ForEach(FeedbackSheet.sources, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("反馈内容") {
                    TextEditor(text: $text)
                        .frame(minHeight: 200)
                }
                Section {
                    Text("App 不会把你的作品发出去。先用“复制给 Claude”把作品复制出来，拿到意见后贴在这里。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("录入反馈")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(Feedback(id: UUID().uuidString, created: Date(), source: source, text: clean))
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct FeedbackList: View {
    let items: [Feedback]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("反馈（\(items.count)）").font(.headline)
                ForEach(items) { f in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Badge(text: f.source)
                            Text(f.created.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(f.text)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.chip.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
}

/// Plain rounded card used by the practice pages.
struct PracticeCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }
}

enum Clipboard {
    @MainActor
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}

/// REC-KEEP: a record whose recording file was removed in 设置 › 录音占用与清理 stays, marked like this.
/// Shows nothing when the record never had a file or the file is still there.
struct RecordingGoneBadge: View {
    @Environment(PracticeStore.self) private var practice
    let file: String?

    var body: some View {
        if let file, !file.isEmpty, practice.recordingURL(file) == nil {
            Label("录音已清理", systemImage: "trash")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("录音文件已清理，这条记录还在")
        }
    }
}
