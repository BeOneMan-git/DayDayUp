import SwiftUI
import Charts

/// MET-01 有效练习时间: minutes per day, stacked by category. Only real learning actions count
/// (ActivityClock), overlaps count once, and audio played in the background is a separate number,
/// never stacked in. Days from before V0.5 (no activity records) show the old listening minutes as
/// their own grey series.
struct ProgressTimeCard: View {
    let window: Int
    @Environment(StudyStore.self) private var study
    @Environment(UserStore.self) private var user
    @State private var only = "all"

    static let oldSeries = "旧记录·听读"

    private struct Bar: Identifiable {
        let id: String
        let day: String
        let series: String
        let minutes: Double
    }

    private struct Series {
        let name: String
        let color: Color
    }

    private struct Model {
        var days: [String] = []
        var mins: [Metrics.DayMinutes] = []
        var old: [String: Double] = [:]      // day -> minutes, only days without activity records
        var byCat: [StudyCategory: Double] = [:]
        var total: Double = 0
        var background: Double = 0
        var planned = 0
        var planDays = 0
        var studyDays = 0
        var oldTotal: Double = 0
        var oldDays = 0

        var hasAny: Bool { total > 0 || background > 0 || oldTotal > 0 }
    }

    var body: some View {
        let m = model()
        ProgressCard("有效练习时间", symbol: "clock",
                     footnote: "只有真的操作（播放、录音、作答、点按、输入）才计时，每次最多延长 1 分钟；屏幕开着不操作不算。同一时间段只算一次。") {
            if m.hasAny {
                filterRow
                chart(m)
                totals(m)
            } else {
                Text("这段时间还没有练习记录。练习时间只在书架、跟读、雅思、词汇页里有操作时才记。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Data

    private func model() -> Model {
        var m = Model()
        m.days = DayKey.lastDays(window)
        m.mins = study.minutes(days: m.days)
        let recordDays = Set(study.activity.map(\.day))
        for d in m.mins {
            for (cat, value) in d.byCat {
                m.byCat[cat, default: 0] += value
            }
            m.total += d.total
            m.background += d.background
            if d.total >= 1 { m.studyDays += 1 }
        }
        for day in m.days {
            if let plan = study.state.plans[day] {
                m.planned += plan.budget
                m.planDays += 1
            }
            if !recordDays.contains(day), let seconds = user.state.daily[day], seconds > 0 {
                m.old[day] = seconds / 60
                m.oldTotal += seconds / 60
                m.oldDays += 1
            }
        }
        return m
    }

    private var shownCategories: [StudyCategory] {
        StudyCategory.allCases.filter { only == "all" || $0.rawValue == only }
    }

    private var showsOld: Bool {
        only == "all" || only == StudyCategory.read.rawValue
    }

    private func bars(_ m: Model) -> [Bar] {
        var out: [Bar] = []
        let cats = shownCategories
        for d in m.mins {
            let label = ProgressFormat.short(d.day)
            for cat in cats {
                out.append(Bar(id: d.day + "|" + cat.rawValue, day: label, series: cat.title,
                               minutes: d.byCat[cat] ?? 0))
            }
            if showsOld, let old = m.old[d.day] {
                out.append(Bar(id: d.day + "|old", day: label, series: ProgressTimeCard.oldSeries, minutes: old))
            }
        }
        return out
    }

    private func scale(_ m: Model) -> [Series] {
        var out = shownCategories.map { Series(name: $0.title, color: ProgressTimeCard.color($0)) }
        if showsOld && m.oldTotal > 0 {
            out.append(Series(name: ProgressTimeCard.oldSeries, color: Color.gray.opacity(0.5)))
        }
        return out
    }

    static func color(_ cat: StudyCategory) -> Color {
        switch cat {
        case .read: return Theme.level6
        case .vocab: return Theme.level5
        case .shadow: return Theme.level7
        case .output: return Theme.level8
        }
    }

    /// Every label for 7 days; every fifth (ending today) for 30 days.
    private func ticks(_ days: [String]) -> [String] {
        let labels = days.map { ProgressFormat.short($0) }
        guard labels.count > 10 else { return labels }
        let last = labels.count - 1
        return labels.enumerated().filter { (last - $0.offset) % 5 == 0 }.map { $0.element }
    }

    // MARK: Views

    /// 筛选任务 (PAGE-07): which categories the chart shows. The totals below always list all four.
    private var filterRow: some View {
        Menu {
            Picker("只看", selection: $only) {
                Text("全部类别").tag("all")
                ForEach(StudyCategory.allCases) { cat in
                    Label(cat.title, systemImage: cat.symbol).tag(cat.rawValue)
                }
            }
        } label: {
            Label("图里显示：" + filterTitle, systemImage: "line.3.horizontal.decrease.circle")
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
    }

    private var filterTitle: String {
        StudyCategory.allCases.first { $0.rawValue == only }?.title ?? "全部类别"
    }

    private func chart(_ m: Model) -> some View {
        let data = bars(m)
        let series = scale(m)
        let names: [String] = series.map { $0.name }
        let colors: [Color] = series.map { $0.color }
        return Chart(data) { b in
            BarMark(x: .value("日期", b.day), y: .value("分钟", b.minutes))
                .foregroundStyle(by: .value("类别", b.series))
        }
        .chartForegroundStyleScale(domain: names, range: colors)
        .chartXAxis {
            AxisMarks(values: ticks(m.days))
        }
        .chartYAxisLabel("分钟")
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 220)
    }

    private func totals(_ m: Model) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(StudyCategory.allCases) { cat in
                totalRow(cat.title, symbol: cat.symbol, value: "\(ProgressFormat.whole(m.byCat[cat] ?? 0)) 分钟")
            }
            Divider()
            totalRow("有效练习合计", symbol: "sum", value: "\(ProgressFormat.whole(m.total)) 分钟")
            totalRow("计划合计", symbol: "list.bullet.clipboard", value: planText(m))
            totalRow("学习天数", symbol: "calendar", value: "\(m.studyDays) / \(window) 天")
            Label("后台播放 \(ProgressFormat.whole(m.background)) 分钟，不计入", systemImage: "speaker.wave.1")
                .font(.callout)
                .foregroundStyle(.secondary)
            if m.oldTotal > 0 {
                Label(oldText(m), systemImage: "clock.arrow.circlepath")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text("分类之间同一时间段只算一次，所以分类相加可能比合计多。学习天数：有效练习满 1 分钟的天数。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func totalRow(_ title: String, symbol: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(title, systemImage: symbol)
            Spacer(minLength: 12)
            Text(value)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }

    private func planText(_ m: Model) -> String {
        guard m.planDays > 0 else { return "这段时间没有计划" }
        return "\(m.planned) 分钟（\(m.planDays) 天有计划）"
    }

    private func oldText(_ m: Model) -> String {
        "旧记录·听读 \(ProgressFormat.whole(m.oldTotal)) 分钟（\(m.oldDays) 天），不计入合计。V0.5 以前只记了听读的播放时长，口径不同，灰色画出只作参考。"
    }
}
