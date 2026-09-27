import SwiftUI

/// 雅思训练 (V0.2): basic speaking and basic writing, grouped by the 12 topics.
/// Full exam formats (Part 2, Task 1/2, mock tests) arrive in V0.4.
struct IELTSView: View {
    @Environment(PracticeStore.self) private var practice

    enum Mode: String, CaseIterable, Identifiable {
        case speaking, writing
        var id: String { rawValue }
        var title: String { self == .speaking ? "口语" : "写作" }
    }

    @State private var mode: Mode = .speaking

    var body: some View {
        List {
            Section {
                Picker("类型", selection: $mode) {
                    ForEach(Mode.allCases) { m in
                        Text(m.title).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                Text(mode == .speaking
                     ? "基础口语：准备 30 秒，说 45 秒。说完先自评，再看参考。"
                     : "基础写作：5–10 分钟，写 3–5 句。完成后原稿只读，可以改写成新版本。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("考试完整题型（Part 2、Task 1/2、口语模拟）在 V0.4 加入。")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }

            ForEach(IELTSBank.topics, id: \.self) { topic in
                if mode == .speaking {
                    let items = IELTSBank.speaking.filter { $0.topic == topic }
                    if !items.isEmpty {
                        Section(topic) {
                            ForEach(items) { p in
                                NavigationLink {
                                    SpeakingSessionView(prompt: p)
                                } label: {
                                    row(p.question, p.zh, done: practice.speakingWorks(prompt: p.id).count)
                                }
                            }
                        }
                    }
                } else {
                    let items = IELTSBank.writing.filter { $0.topic == topic }
                    if !items.isEmpty {
                        Section(topic) {
                            ForEach(items) { p in
                                NavigationLink {
                                    WritingSessionView(prompt: p)
                                } label: {
                                    row(p.task, p.zh, done: practice.writingWorks(prompt: p.id).count)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("雅思")
    }

    private func row(_ english: String, _ chinese: String, done: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(english)
                    .font(Font.system(.body, design: .serif))
                Text(chinese)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if done > 0 {
                Text("练过 \(done) 次")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
