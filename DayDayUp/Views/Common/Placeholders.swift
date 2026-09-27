import SwiftUI

/// Pages that arrive in later versions. Each says what it will do and when.
struct ComingSoonView: View {
    enum Feature {
        case progress

        var title: String {
            switch self {
            case .progress: return "进度"
            }
        }

        var symbol: String {
            switch self {
            case .progress: return "chart.line.uptrend.xyaxis"
            }
        }

        var version: String {
            switch self {
            case .progress: return "V0.5 上线"
            }
        }

        var points: [String] {
            switch self {
            case .progress:
                return ["投入和证据分开看：练习时间是一类，回忆成功率、录音变化、说写作品是另一类",
                        "每周一生成上周周报，可以导出 CSV 或 JSON",
                        "样本少的时候明确提示，不把练熟的材料算成进步"]
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
                Text("这一页还在开发。现在可以先用听读、跟读和雅思说写，记录都会保留，上线后直接用得上。")
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
