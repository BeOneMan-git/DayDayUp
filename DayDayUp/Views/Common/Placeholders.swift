import SwiftUI

/// Pages that arrive in later versions. Each says what it will do and when.
struct ComingSoonView: View {
    enum Feature {
        case shadowing, progress

        var title: String {
            switch self {
            case .shadowing: return "跟读"
            case .progress: return "进度"
            }
        }

        var symbol: String {
            switch self {
            case .shadowing: return "waveform"
            case .progress: return "chart.line.uptrend.xyaxis"
            }
        }

        var version: String {
            switch self {
            case .shadowing: return "V0.3 上线"
            case .progress: return "V0.4 上线"
            }
        }

        var points: [String] {
            switch self {
            case .shadowing:
                return ["逐句、逐段跟读，每句标出意群、连读、弱读、重音和语调",
                        "本机评分：完整度、词准确度、流利度、意群与连读、节奏与重音、语调",
                        "指出 Top 3 问题，给针对性小练习；原声和你的录音 A/B 对比"]
            case .progress:
                return ["今日计划：听读 → 跟读 → 背词 → 复盘，默认 45 分钟",
                        "连续天数、进度看板和周报",
                        "导出学习记录，给 Claude 做复盘"]
            }
        }
    }

    let feature: Feature

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label(feature.version, systemImage: feature.symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text("这一页还在开发。现在的 V0.1 先把听读做扎实。")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(feature.points, id: \.self) { p in
                        Label(p, systemImage: "checkmark.circle")
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(feature.title)
    }
}
