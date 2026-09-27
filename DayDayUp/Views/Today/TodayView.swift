import SwiftUI
import Charts

/// 今日: continue where you stopped, today's practice, this week's listening, backup reminder.
/// The full daily plan arrives in V0.5.
struct TodayView: View {
    @Environment(PackStore.self) private var packs
    @Environment(UserStore.self) private var user
    @Environment(PracticeStore.self) private var practice
    @Environment(VocabStore.self) private var vocab
    @Environment(Router.self) private var router
    @Environment(ReadingSession.self) private var session
    @Environment(PlaybackEngine.self) private var engine

    private struct DayStat: Identifiable {
        let id: String
        let label: String
        let minutes: Double
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(Date().formatted(date: .complete, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if user.backupOverdue {
                    backupBanner
                }
                if engine.hasAudio, let art = session.article {
                    nowPlaying(art)
                }
                continueCard
                practiceCard
                weekCard
                planCard
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("今日")
    }

    // MARK: Cards

    private var backupBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.title2)
                .foregroundStyle(Theme.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.daysSinceBackup.map { "已经 \($0) 天没有备份" } ?? "还没有备份过学习记录")
                    .font(.headline)
                Text("学习记录只存在这台 iPad 上。每周备份一次，最稳妥。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("去备份") { router.tab = .settings }
                .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(Theme.warn.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }

    private func nowPlaying(_ art: Article) -> some View {
        HStack(spacing: 14) {
            Button {
                session.togglePlay()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(engine.isPlaying ? "暂停" : "播放")
            VStack(alignment: .leading, spacing: 2) {
                Text(engine.isPlaying ? "正在播放" : "已暂停")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(art.title)
                    .font(Font.system(.headline, design: .serif))
                Text("\(formatTime(engine.time)) / \(formatTime(engine.duration))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let ref = session.ref {
                Button("回到原文") { router.openArticle(ref) }
                    .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var continueCard: some View {
        if let key = user.state.lastArticle, let ref = ArticleRef(key: key), let item = packs.item(ref) {
            VStack(alignment: .leading, spacing: 12) {
                Text("继续听读")
                    .font(.headline)
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(item.ref.issue) · \(item.meta.section)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.meta.title)
                            .font(Font.system(.title2, design: .serif).weight(.semibold))
                        if let pos = user.state.positions[key], pos > 1 {
                            Text("上次停在 \(formatTime(pos)) / \(formatTime(item.meta.dur))")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    ProgressRing(label: "听", value: user.state.listenProgress(key, duration: item.meta.dur))
                    ProgressRing(label: "读", value: user.state.readProgress(key, duration: item.meta.dur), tint: Theme.level5)
                }
                Button {
                    router.openArticle(ref)
                } label: {
                    Label("继续", systemImage: "play.fill")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("从书架选一篇开始").font(.headline)
                Text("建议顺序：先盲听一遍，再看着原文听一遍，边听边点生词。")
                    .foregroundStyle(.secondary)
                Button("打开书架") { router.tab = .library }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var weekCard: some View {
        let days = DayKey.lastDays(7).map { key in
            DayStat(id: key, label: String(key.suffix(5)).replacingOccurrences(of: "-", with: "/"),
                    minutes: user.state.minutes(on: key))
        }
        let total = days.reduce(0) { $0 + $1.minutes }
        let finished = packs.allItems.filter { user.state.listenProgress($0.ref.key, duration: $0.meta.dur) >= 1 }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("最近 7 天").font(.headline)
                Spacer()
                Text("听读 \(Int(total.rounded())) 分钟 · 听完 \(finished)/\(packs.articleCount) 篇 · 词汇 \(vocab.activeItems.count) 条")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Chart(days) { d in
                BarMark(x: .value("日期", d.label), y: .value("分钟", d.minutes))
                    .foregroundStyle(Theme.accent)
                    .cornerRadius(4)
            }
            .chartYAxisLabel("分钟")
            .frame(height: 160)
        }
        .padding(16)
        .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }

    private var practiceCard: some View {
        let today = practice.summary(for: DayKey.today)
        let q = vocab.queue()
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("今日练习").font(.headline)
                Spacer()
                Text("跟读 \(today.shadowSentences) 句（\(today.shadowTakes) 次）· 口语 \(today.speaking) 次 · 写作 \(today.writing) 篇")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text(q.dueCount + q.newAllowed > 0
                 ? "词汇：到期 \(q.dueCount) 张，新任务 \(q.newAllowed) 个，预算 \(Int(q.budgetSeconds / 60)) 分钟。"
                 : "词汇：今日暂无到期。")
                .font(.callout)
            Text("每天一个小闭环：听读一段 → 跟读 1–2 句 → 口语 1 题 → 写作 1 题 → 每周备份一次。")
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button {
                    router.tab = .shadow
                } label: {
                    Label("去跟读", systemImage: "waveform")
                }
                Button {
                    router.tab = .ielts
                } label: {
                    Label("去练说写", systemImage: "text.bubble")
                }
                Button {
                    router.tab = .vocab
                } label: {
                    Label("去复习词汇", systemImage: "character.book.closed")
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("今日计划（V0.5 上线）").font(.headline)
            Text("以后这里会按你每天 60 或 90 分钟，排好听读、跟读、词汇和说写四类任务，并说明为什么这样排。")
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chip.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }
}
