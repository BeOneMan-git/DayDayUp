import SwiftUI

/// 进度 (PAGE-07): what was spent (投入) and what it shows (证据) in two separate groups, so time is never
/// read as ability. The 7 / 30 天 window applies to time, comprehension checks and issues; every other
/// card names its own window. Samples that are too small say so; there are no score curves.
struct StudyProgressPage: View {
    @Environment(StudyStore.self) private var study
    @State private var playback = ProgressPlayback()

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                windowPicker
                ProgressGroupHeader(title: "投入（花了多少时间）",
                                    detail: "时间只说明你练了多久，不说明练得怎么样。")
                ProgressTimeCard(window: window)
                ProgressGroupHeader(title: "证据（练得怎么样）",
                                    detail: "只看有记录的表现：回忆、理解题、录音和作品。样本少的时候会直接说。")
                ProgressRecallCard()
                ProgressComprehensionCard(window: window)
                ProgressVocabStateCard()
                ProgressRecordingsCard(playback: playback)
                ProgressWorksCard(playback: playback)
                ProgressIssuesCard(window: window)
                ProgressGroupHeader(title: "周报", detail: "每周一准备上一周的汇总，可以导出。")
                ProgressWeekListCard()
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("进度")
        .onDisappear { playback.stop() }
    }

    private var window: Int {
        study.settings.windowDays == 30 ? 30 : 7
    }

    /// MET-P01: 7 days, or 30. Two large buttons; the chosen one shows a filled check (symbol + text).
    private var windowPicker: some View {
        HStack(spacing: 10) {
            windowButton(7)
            windowButton(30)
        }
    }

    private func windowButton(_ days: Int) -> some View {
        let selected = window == days
        return Button {
            study.updateSettings { $0.windowDays = days }
        } label: {
            Label("最近 \(days) 天", systemImage: selected ? "checkmark.circle.fill" : "circle")
                .font(.body.weight(selected ? .semibold : .regular))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Theme.accent : Color.primary)
        .background(selected ? Theme.accent.opacity(0.14) : Theme.chip.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 10))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// RPT-01: the last 8 finished weeks that have any record, plus the week in progress (not openable).
struct ProgressWeekListCard: View {
    @Environment(StudyStore.self) private var study
    @Environment(VocabStore.self) private var vocab
    @Environment(PracticeStore.self) private var practice

    var body: some View {
        let thisMonday = DayKey.weekStart(DayKey.today)
        let weeks = pastWeeks(before: thisMonday)
        ProgressCard("每周汇总", symbol: "calendar",
                     footnote: "周报只写事实和最多 3 个下周重点。导出前会先告诉你文件里有什么；App 不会自动发送。") {
            currentWeekRow(thisMonday)
            if weeks.isEmpty {
                Text("还没有已经结束、而且有记录的一周。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(weeks, id: \.self) { week in
                    Divider()
                    NavigationLink {
                        WeeklyReportView(week: week)
                    } label: {
                        weekLabel(week)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func currentWeekRow(_ monday: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "hourglass")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("本周进行中 · " + ProgressFormat.weekRange(monday))
                Text("这周还没结束，下周一可以看完整周报。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private func weekLabel(_ week: String) -> some View {
        let seen = study.state.weeklyReports[week] != nil
        return HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(Theme.accent)
            Text("周报 " + ProgressFormat.weekRange(week))
            Spacer(minLength: 8)
            Label(seen ? "看过" : "还没看", systemImage: seen ? "checkmark.circle" : "circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    /// Mondays before `thisMonday` whose week has practice time, reviews, quizzes or works; newest first.
    private func pastWeeks(before thisMonday: String) -> [String] {
        var days = Set<String>()
        for r in study.activity {
            days.insert(r.day)
        }
        for e in vocab.events where e.kind == .review {
            days.insert(e.day)
        }
        for q in study.state.quizResults {
            days.insert(q.day)
        }
        for w in practice.state.speaking where !w.silent {
            days.insert(DayKey.of(w.created))
        }
        for w in practice.state.writing {
            for v in w.versions {
                if let done = v.finished { days.insert(DayKey.of(done)) }
            }
        }
        for s in practice.state.shadow where !s.silent {
            days.insert(DayKey.of(s.created))
        }
        let mondays = Set(days.map { DayKey.weekStart($0) })
        return Array(mondays.filter { $0 < thisMonday }.sorted(by: >).prefix(8))
    }
}
