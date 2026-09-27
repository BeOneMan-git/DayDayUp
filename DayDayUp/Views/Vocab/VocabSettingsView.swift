import SwiftUI

/// 词汇设置 (VOC-P01…P03, VOC-P06/P07): the scheduling target, daily amounts, the 听词 list,
/// the audio source, and the CSV import of the old word list.
struct VocabSettingsView: View {
    @Environment(VocabStore.self) private var vocab

    var body: some View {
        let s = vocab.settings
        let retentionPercent = Int((s.retention * 100).rounded())
        let retentionText = "\(retentionPercent)%"
        let rateText = String(format: "%.2f×", s.listenRate)
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("目标保留率", value: retentionText)
                    Slider(value: rounded(\.retention), in: 0.80...0.95, step: 0.01)
                        .accessibilityLabel("目标保留率")
                        .accessibilityValue(retentionText)
                }
                if retentionPercent > 90 {
                    Label("调高后，每天的复习量可能明显变大。", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.warn)
                }
            } header: {
                Text("排期")
            } footer: {
                Text(verbatim: "目标保留率是排期用的目标，不是你已经达到的成绩。默认 90%，可以在 80% 到 95% 之间调。")
            }

            Section {
                Stepper(value: binding(\.budgetMinutes), in: 5...20, step: 1) {
                    Text("每日词汇预算：\(Int(s.budgetMinutes)) 分钟")
                }
                Stepper(value: binding(\.newPerDay), in: 0...15) {
                    Text("每日新任务：\(s.newPerDay) 个")
                }
            } header: {
                Text("每天")
            } footer: {
                Text("预算把复习和新任务算在一起。到期的先做；预算还有剩余，才放新任务。一个义项或词群的一种题型，算 1 个新任务。")
            }

            Section {
                Stepper(value: binding(\.listenGap), in: 0...10, step: 1) {
                    Text("等待：\(VocabSettingsView.number(s.listenGap)) 秒")
                }
                Stepper(value: rounded(\.listenRate), in: 0.75...1.25, step: 0.05) {
                    Text("速度：" + rateText)
                }
                Toggle("一轮不限时，手动结束", isOn: manualRound)
                if s.listenMinutes > 0 {
                    Stepper(value: binding(\.listenMinutes), in: 5...30, step: 5) {
                        Text("一轮时长：\(Int(s.listenMinutes)) 分钟")
                    }
                }
                Toggle("只听英文", isOn: binding(\.listenEnglishOnly))
                Toggle("随机顺序", isOn: binding(\.listenRandom))
            } header: {
                Text("听词")
            } footer: {
                Text("顺序是：单词 → 等待 → 中文义 → 原句。“只听英文”不读中文义。听词只记“听过”，不算复习。")
            }

            Section {
                Toggle("优先用原声", isOn: binding(\.preferOriginalAudio))
            } header: {
                Text("声音")
            } footer: {
                Text("有文章原声时用原声；没有时用系统合成音，并标明“合成音”。")
            }

            Section {
                NavigationLink {
                    VocabCSVImportView()
                } label: {
                    Label("从 CSV 导入旧生词", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("导入")
            } footer: {
                Text("旧的“认识”只作历史记录，不会当成已掌握，也不建复习卡。")
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("排期算法")
                    Text(FSRSScheduler.name)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
            } header: {
                Text("算法")
            } footer: {
                Text("不加随机抖动，所以每个日期都能解释。")
            }
        }
        .navigationTitle("词汇设置")
    }

    private func binding<T>(_ path: WritableKeyPath<VocabSettings, T>) -> Binding<T> {
        Binding(
            get: { vocab.settings[keyPath: path] },
            set: { value in vocab.updateSettings { $0[keyPath: path] = value } }
        )
    }

    /// Keeps two decimals, so steps of 0.01 or 0.05 never drift to values like 0.9000000001.
    private func rounded(_ path: WritableKeyPath<VocabSettings, Double>) -> Binding<Double> {
        Binding(
            get: { vocab.settings[keyPath: path] },
            set: { value in vocab.updateSettings { $0[keyPath: path] = (value * 100).rounded() / 100 } }
        )
    }

    /// 0 minutes means the 听词 round runs until it is stopped (VOC-P07).
    private var manualRound: Binding<Bool> {
        Binding(
            get: { vocab.settings.listenMinutes == 0 },
            set: { manual in vocab.updateSettings { $0.listenMinutes = manual ? 0 : 10 } }
        )
    }

    private static func number(_ value: Double) -> String {
        String(format: "%g", value)
    }
}
