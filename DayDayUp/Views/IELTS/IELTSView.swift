import SwiftUI

/// 雅思训练: 口语 / 写作, each split into 基础训练 (V0.2, grouped by the 12 topics) and
/// 考试题型 (V0.4, IEL-P03…P06): 口语 Part 2 单题、口语完整模拟、写作 Task 1、写作 Task 2.
/// Every exam task shows its official conditions (time, words).
struct IELTSView: View {
    @Environment(PracticeStore.self) private var practice

    enum Mode: String, CaseIterable, Identifiable {
        case speaking, writing
        var id: String { rawValue }
        var title: String { self == .speaking ? "口语" : "写作" }
    }

    enum Track: String, CaseIterable, Identifiable {
        case basic, exam
        var id: String { rawValue }
        var title: String { self == .basic ? "基础训练" : "考试题型" }
    }

    @State private var mode: Mode = .speaking
    @State private var track: Track = .basic

    var body: some View {
        List {
            Section {
                Picker("类型", selection: $mode) {
                    ForEach(Mode.allCases) { m in
                        Text(m.title).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                Picker("训练", selection: $track) {
                    ForEach(Track.allCases) { t in
                        Text(t.title).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                Text(introText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(track == .basic
                     ? "基础训练：短题，有提示，完成后有原创参考。"
                     : "考试题型：按官方时间和字数练习。题目和图表数据都是 DayDayUp 原创，仅供练习，不打分。")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }

            if track == .basic {
                basicSections
            } else if mode == .speaking {
                speakingExamSections
            } else {
                writingExamSections
            }
        }
        .navigationTitle("雅思")
    }

    private var introText: String {
        switch (mode, track) {
        case (.speaking, .basic):
            return "基础口语：准备 30 秒，说 45 秒。说完先自评，再看参考。"
        case (.writing, .basic):
            return "基础写作：5–10 分钟，写 3–5 句。完成后原稿只读，可以改写成新版本。"
        case (.speaking, .exam):
            return "口语考试题型：Part 2 准备 1 分钟、陈述 1–2 分钟；完整模拟约 11–14 分钟，每题单独录音。不给范文，先自评，再找老师或 Claude 反馈。"
        case (.writing, .exam):
            return "写作考试题型（Academic）：Task 1 至少 150 词、约 20 分钟；Task 2 至少 250 词、约 40 分钟。不给范文，先自评，再找老师或 Claude 反馈。"
        }
    }

    // MARK: 基础训练

    @ViewBuilder
    private var basicSections: some View {
        ForEach(IELTSBank.topics, id: \.self) { topic in
            if mode == .speaking {
                let items = IELTSBank.speaking.filter { $0.topic == topic }
                if !items.isEmpty {
                    Section("基础训练 · \(topic)") {
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
                    Section("基础训练 · \(topic)") {
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

    // MARK: 考试题型 · 口语

    @ViewBuilder
    private var speakingExamSections: some View {
        let t = IELTSExamBank.timings
        let complete = practice.state.mocks.filter { $0.isComplete }.count
        Section {
            NavigationLink {
                MockTestView()
            } label: {
                examRow(title: "口语完整模拟",
                        subtitle: "Part 1（8 题）→ Part 2（1 张题卡）→ Part 3（5 题），每题单独录音",
                        conditions: "全程\(IELTSExamBank.minutesText(t.mockMinutes)) · Part 1 \(IELTSExamBank.minutesText(t.part1Minutes)) · Part 2 \(IELTSExamBank.minutesText(t.part2Minutes)) · Part 3 \(IELTSExamBank.minutesText(t.part3Minutes))",
                        done: complete > 0 ? "完整模拟 \(complete) 次" : nil,
                        serif: false)
            }
        } header: {
            Text("考试题型 · 口语完整模拟")
        } footer: {
            Text("离线固定题库，不能等同真人考官互动。")
        }

        Section {
            ForEach(IELTSExamBank.cueCards) { card in
                NavigationLink {
                    Part2SessionView(card: card)
                } label: {
                    examRow(title: card.title,
                            subtitle: card.topic,
                            conditions: "准备 1 分钟 · 陈述 1–2 分钟",
                            done: doneText(practice.speakingWorks(prompt: card.id).count),
                            serif: true)
                }
            }
        } header: {
            Text("考试题型 · 口语 Part 2 单题")
        } footer: {
            Text("准备时可以记笔记，可以提前开始说。不给范文。")
        }
    }

    // MARK: 考试题型 · 写作

    @ViewBuilder
    private var writingExamSections: some View {
        let t = IELTSExamBank.timings
        Section {
            ForEach(IELTSExamBank.task1Prompts) { p in
                NavigationLink {
                    WritingSessionView(task1: p)
                } label: {
                    examRow(title: p.heading,
                            subtitle: "\(p.kind.title) · \(p.zh)",
                            conditions: "至少 \(t.task1MinWords) 词 · 建议约 \(Int(t.task1Minutes)) 分钟",
                            done: doneText(practice.writingWorks(prompt: p.id).count),
                            serif: true)
                }
            }
        } header: {
            Text("考试题型 · 写作 Task 1")
        } footer: {
            Text("Academic 图表题：线图、柱状图、饼图、表格、流程图。图可以放大看。")
        }

        Section {
            ForEach(IELTSExamBank.task2Prompts) { p in
                NavigationLink {
                    WritingSessionView(task2: p)
                } label: {
                    examRow(title: p.question,
                            subtitle: "\(p.type.title) · \(p.topic) · \(p.zh)",
                            conditions: "至少 \(t.task2MinWords) 词 · 建议约 \(Int(t.task2Minutes)) 分钟",
                            done: doneText(practice.writingWorks(prompt: p.id).count),
                            serif: true)
                }
            }
        } header: {
            Text("考试题型 · 写作 Task 2")
        } footer: {
            Text("考试时两篇共 \(Int(t.writingTotalMinutes)) 分钟；Task 2 分量更重，时间要多留给它。")
        }
    }

    // MARK: Rows

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

    private func examRow(title: String, subtitle: String, conditions: String, done: String?, serif: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(serif ? Font.system(.body, design: .serif) : .body.weight(.semibold))
                    .lineLimit(4)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(conditions, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let done {
                Text(done)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func doneText(_ count: Int) -> String? {
        count > 0 ? "练过 \(count) 次" : nil
    }
}
