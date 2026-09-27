import SwiftUI

/// 复习 (PAGE-05): today's queue under the time budget (VOC-P02/P03/P04), then one card at a time.
/// Due cards come first and stay due until they are answered; nothing is postponed silently.
struct VocabReviewView: View {
    @Environment(VocabStore.self) private var vocab
    @State private var queue = VocabQueue()
    @State private var running = false
    @State private var note: String? = nil

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if running {
                    SessionPane(only: nil) { endNote in
                        running = false
                        note = endNote
                        refresh()
                    }
                } else {
                    overview
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .onAppear { refresh() }
    }

    /// `vocab.queue()` may record the day's starting load, so it runs in actions, never in `body`.
    private func refresh() {
        queue = vocab.queue()
    }

    // MARK: Overview

    @ViewBuilder
    private var overview: some View {
        if let note {
            Label(note, systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        PracticeCard {
            BudgetMeter(spent: queue.spentSeconds, budget: queue.budgetSeconds)
            HStack(spacing: 10) {
                Stat(value: "\(queue.dueCount) 张", title: "现在到期")
                Stat(value: "\(queue.laterToday) 张", title: "学习步（稍后出现）")
                Stat(value: "\(queue.newAllowed) 个", title: "今天还放新任务")
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(queue.explanation.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        if queue.backlogSuggestsZero {
            backlogCard
        }
        if queue.entries.isEmpty {
            ContentUnavailableView("今日暂无到期", systemImage: "checkmark.circle", description: Text(emptyDetail))
        } else {
            startButton
        }
        UndoRow(showWord: true) { _ in refresh() }
        NavigationLink {
            VocabSettingsView()
        } label: {
            Label("复习设置：保留率、每日预算、新任务上限", systemImage: "slider.horizontal.3")
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.bordered)
    }

    private var startButton: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                note = nil
                running = true
            } label: {
                Label("开始复习（\(queue.entries.count) 张）", systemImage: "play.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            if queue.overBudget {
                Text("今天的预算已经用完。开始后会先问你：继续（超出计划），还是先停在这里。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// VOC-P04: the suggestion to add no new tasks, with the learner's choice and a way back.
    private var backlogCard: some View {
        PracticeCard {
            Label("积压提醒", systemImage: "tray.full")
                .font(.headline)
            if queue.backlogOverridden {
                Text("最近两个学习日，开始时的到期量都超过预算。你选了今天仍然加新任务。")
                    .font(.callout)
                Button {
                    vocab.keepNewTasksToday(false)
                    refresh()
                } label: {
                    Label("撤销：今天不加新任务", systemImage: "arrow.uturn.backward")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            } else {
                Text("最近两个学习日，开始时的到期量都超过预算，建议今天不加新任务，先做到期的。")
                    .font(.callout)
                Button {
                    vocab.keepNewTasksToday(true)
                    refresh()
                } label: {
                    Label("今天仍然加新任务", systemImage: "plus.circle")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var emptyDetail: String {
        if queue.laterToday > 0 {
            return "还有 \(queue.laterToday) 张在学习步里，1 或 10 分钟后再出现。"
        }
        if queue.newCount > 0 {
            return "今天不再加新任务，原因见上面的说明。"
        }
        return "在听读页收藏义项或词群后，会按每日上限排进来。"
    }
}

/// 拼写 (PAGE-05): due 拼写 cards (VOC-T03), and switching the 拼写 task on for saved words.
struct VocabSpellingView: View {
    @Environment(VocabStore.self) private var vocab
    @State private var queue = VocabQueue()
    @State private var running = false
    @State private var note: String? = nil
    @State private var enabledNote: String? = nil
    @State private var search = ""

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if running {
                    VocabReviewView.SessionPane(only: .spell) { endNote in
                        running = false
                        note = endNote
                        refresh()
                    }
                } else {
                    overview
                    enableList
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        queue = vocab.queue()
    }

    // MARK: Due 拼写 cards

    @ViewBuilder
    private var overview: some View {
        let spell = queue.entries.filter { $0.card.task == .spell }
        let due = spell.filter { !$0.card.isNew }.count
        let fresh = spell.count - due
        let inQueue = Set(queue.entries.map { $0.id })
        let waiting = vocab.state.cards.filter {
            $0.task == .spell && !$0.suspended && $0.isNew && !inQueue.contains($0.id)
        }.count
        if let note {
            Label(note, systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        PracticeCard {
            VocabReviewView.BudgetMeter(spent: queue.spentSeconds, budget: queue.budgetSeconds)
            HStack(spacing: 10) {
                VocabReviewView.Stat(value: "\(due) 张", title: "到期的拼写卡")
                VocabReviewView.Stat(value: "\(fresh) 个", title: "今天的新拼写任务")
            }
            if waiting > 0 {
                Text("还有 \(waiting) 个新拼写任务排在后面。新任务和复习页共用每日上限和时间预算。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        if spell.isEmpty {
            ContentUnavailableView("今日暂无到期的拼写卡", systemImage: "character.cursor.ibeam",
                                   description: Text("可以在下面为词打开拼写任务。"))
        } else {
            Button {
                note = nil
                running = true
            } label: {
                Label("开始拼写（\(spell.count) 张）", systemImage: "play.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        VocabReviewView.UndoRow(showWord: true) { _ in refresh() }
    }

    // MARK: Switching 拼写 on

    @ViewBuilder
    private var enableList: some View {
        let on = Set(vocab.state.cards.filter { $0.task == .spell && !$0.suspended }.map { $0.itemId })
        let candidates = vocab.activeItems.filter { !on.contains($0.id) }
        let shown = candidates.filter { matches($0) }.sorted { $0.created > $1.created }
        VStack(alignment: .leading, spacing: 10) {
            Text("为词打开拼写任务")
                .font(.headline)
            Text("打开后先作为新任务，按每日上限排进来。以后关掉只是暂停，记录还在。")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let enabledNote {
                Label(enabledNote, systemImage: "checkmark.circle")
                    .font(.callout)
            }
            if candidates.isEmpty {
                Text(vocab.activeItems.isEmpty ? "还没有收藏的词。在听读页点词，收藏义项后再来。" : "所有词都已经打开了拼写任务。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                TextField("搜索词或中文义", text: $search)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(10)
                    .background(Theme.paper, in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.3))
                    }
                if shown.isEmpty {
                    Text("没有找到。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(shown) { item in
                            row(item)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func row(_ item: VocabItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                    .font(.body.weight(.semibold))
                if !item.gloss.isEmpty {
                    Text(item.gloss)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                enable(item)
            } label: {
                Label("打开拼写", systemImage: "plus.circle")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("为 \(item.text) 打开拼写任务")
        }
        .padding(.vertical, 6)
    }

    private func enable(_ item: VocabItem) {
        vocab.setTask(.spell, enabled: true, for: item.id)
        enabledNote = "已为「\(item.text)」打开拼写任务。"
        refresh()
    }

    private func matches(_ item: VocabItem) -> Bool {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        return SentenceText.normalize(item.text).contains(SentenceText.normalize(q)) || item.gloss.contains(q)
    }
}

extension VocabReviewView {
    /// A running session: one card at a time from today's queue, rebuilt after every answer
    /// so that learning steps (1 or 10 minutes) come back. `only` limits it to one task type.
    fileprivate struct SessionPane: View {
        let only: VocabTask?
        let onEnd: (String?) -> Void

        @Environment(VocabStore.self) private var vocab
        @State private var queue = VocabQueue()
        @State private var current: VocabCard? = nil
        @State private var lastCardId: String? = nil
        @State private var lastItemId: String? = nil
        @State private var skipped: Set<String> = []
        @State private var continueOver = false
        @State private var turn = 0
        @State private var started = false
        @State private var startedAt = Date()
        @State private var waitUntil: Date? = nil

        init(only: VocabTask?, onEnd: @escaping (String?) -> Void) {
            self.only = only
            self.onEnd = onEnd
        }

        var body: some View {
            // The pane sits in the page's ScrollView; each new card starts at the top.
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 16) {
                    header
                        .id("session-top")
                    if let error = vocab.saveError {
                        Label("保存出错：" + error, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(Theme.warn)
                    }
                    content
                    UndoRow(showWord: false) { event in undone(event) }
                }
                .onChange(of: turn) { _, _ in
                    proxy.scrollTo("session-top", anchor: .top)
                }
            }
            .onAppear {
                guard !started else { return }
                started = true
                startedAt = Date()
                advance(prefer: nil)
            }
            .task(id: waitUntil) {
                // Nothing due right now: look again when the next card falls due.
                guard let until = waitUntil else { return }
                let delay = max(1, until.timeIntervalSinceNow + 1)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                advance(prefer: nil)
            }
        }

        private var header: some View {
            let remaining = pool(queue).count
            let title = spellOnly ? "拼写练习" : "复习"
            return VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Text("本次已做 \(doneCount) 张 · 还剩 \(remaining) 张")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if continueOver && queue.overBudget {
                        Badge(text: "超出计划", color: Theme.warn, outlined: true)
                    }
                    Spacer()
                    Button {
                        onEnd(endNote())
                    } label: {
                        Label("结束", systemImage: "xmark.circle")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
                BudgetMeter(spent: queue.spentSeconds, budget: queue.budgetSeconds)
            }
        }

        @ViewBuilder
        private var content: some View {
            if !started {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let card = current {
                if queue.overBudget && !continueOver {
                    budgetReached
                } else {
                    VocabTaskCard(card: card) { answered(card) }
                        .id("\(card.id)#\(turn)")
                }
            } else if let until = waitUntil {
                waiting(until)
            } else {
                finished
            }
        }

        /// Time is up: continue beyond the plan, or stop. Unfinished cards stay due either way.
        private var budgetReached: some View {
            let left = pool(queue).count
            return PracticeCard {
                Label("今天的词汇预算用完了", systemImage: "hourglass")
                    .font(.headline)
                Text("还有 \(left) 张到期没做。它们保持到期，不会偷偷顺延：可以继续（超出计划），也可以先停在这里，下次再做。")
                    .font(.callout)
                FlowLayout(spacing: 12, lineSpacing: 12) {
                    Button {
                        continueOver = true
                    } label: {
                        Label("继续（超出计划）", systemImage: "play.fill")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        onEnd(endNote())
                    } label: {
                        Label("先停在这里", systemImage: "pause.fill")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }

        private func waiting(_ until: Date) -> some View {
            PracticeCard {
                Label("现在没有到期的卡片", systemImage: "clock")
                    .font(.headline)
                Text("还有卡片今天稍后到期（学习步是 1 或 10 分钟）。下一张大约 \(until.formatted(date: .omitted, time: .shortened)) 到期，到时自动刷新。")
                    .font(.callout)
                FlowLayout(spacing: 12, lineSpacing: 12) {
                    Button {
                        advance(prefer: nil)
                    } label: {
                        Label("现在刷新", systemImage: "arrow.clockwise")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        onEnd(endNote())
                    } label: {
                        Label("先停在这里", systemImage: "pause.fill")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }

        private var finished: some View {
            PracticeCard {
                Label(spellOnly ? "今天到期的拼写卡做完了" : "今天到期的卡片做完了", systemImage: "checkmark.circle")
                    .font(.headline)
                Text("本次做了 \(doneCount) 张。")
                    .font(.callout)
                if !skipped.isEmpty {
                    Text("跳过 \(skipped.count) 张：没有记录作答，它们仍然到期。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Button {
                    onEnd(endNote())
                } label: {
                    Label("回到概览", systemImage: "list.bullet")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }

        // MARK: Queue

        private var spellOnly: Bool {
            only == VocabTask.spell
        }

        private func matchesTask(_ task: VocabTask?) -> Bool {
            guard let only else { return true }
            return task == only
        }

        /// Entries this session may show: the task filter, minus cards skipped in this session.
        private func pool(_ q: VocabQueue) -> [VocabQueue.Entry] {
            q.entries.filter { entry in
                matchesTask(entry.card.task) && !skipped.contains(entry.card.id)
            }
        }

        /// Rebuilds the queue and picks the next card: `prefer` first (after an undo), then a card of
        /// another item, then any card other than the last one, and only then the same card again.
        private func advance(prefer: String?) {
            queue = vocab.queue()
            let list = pool(queue)
            var next = list.first(where: { $0.card.id == prefer })
            if next == nil {
                next = list.first(where: { $0.card.itemId != lastItemId && $0.card.id != lastCardId })
            }
            if next == nil {
                next = list.first(where: { $0.card.id != lastCardId })
            }
            if next == nil {
                next = list.first
            }
            current = next?.card
            waitUntil = next == nil ? nextLearningDue() : nil
            turn += 1
        }

        /// The next card that falls due later today (usually a learning step), for the waiting screen.
        private func nextLearningDue() -> Date? {
            let now = Date()
            let end = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
            return vocab.state.cards
                .filter { !$0.suspended && !$0.isNew && !skipped.contains($0.id) && matchesTask($0.task) }
                .map { $0.fsrs.due }
                .filter { $0 > now && $0 < end }
                .min()
        }

        /// Called by the card. If the schedule did not move, nothing was recorded (跳过):
        /// the card stays due and is left out for the rest of this session.
        private func answered(_ shown: VocabCard) {
            let moved = vocab.card(shown.id).map { $0.fsrs != shown.fsrs } ?? false
            if !moved {
                skipped.insert(shown.id)
            }
            lastCardId = shown.id
            lastItemId = shown.itemId
            advance(prefer: nil)
        }

        /// After an undo the card is due again; show it next so it can be answered again.
        private func undone(_ event: ReviewEvent) {
            if let id = event.cardId {
                skipped.remove(id)
            }
            lastCardId = nil
            lastItemId = nil
            advance(prefer: event.cardId)
        }

        /// Answers since the session started, taken-back ones excluded.
        private var doneCount: Int {
            let recent = vocab.events.filter { $0.at >= startedAt && matchesTask($0.task) }
            return VocabQueueBuilder.activeReviews(recent).count
        }

        private func endNote() -> String {
            let left = queue.entries.filter { matchesTask($0.card.task) && !$0.card.isNew }.count
            var text = "本次做了 \(doneCount) 张。"
            if left > 0 {
                text += "还有 \(left) 张到期没做：它们保持到期，下次打开还在，不会偷偷顺延。"
            }
            return text
        }
    }

    /// Today's vocabulary time against the budget. The text says when it is used up (not colour alone).
    fileprivate struct BudgetMeter: View {
        let spent: Double
        let budget: Double

        var body: some View {
            let over = spent >= budget
            let total = max(budget, 1)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("今日词汇用时")
                        .font(.subheadline.weight(.semibold))
                    if over {
                        Badge(text: "预算已用完", color: Theme.warn, outlined: true)
                    }
                    Spacer()
                    Text("\(BudgetMeter.text(spent)) / 预算 \(Int((budget / 60).rounded())) 分钟")
                        .font(.callout.monospacedDigit())
                }
                ProgressView(value: min(spent, total), total: total)
                    .tint(over ? Theme.warn : Theme.accent)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
        }

        static func text(_ seconds: Double) -> String {
            let s = max(0, Int(seconds.rounded()))
            if s < 60 { return "\(s) 秒" }
            let m = s / 60
            let r = s % 60
            return r == 0 ? "\(m) 分钟" : "\(m) 分 \(r) 秒"
        }
    }

    /// "撤销上一次": takes back the latest answer of today that nothing has moved since.
    /// Inside a session the word is not named, so the next card's answer is not given away.
    fileprivate struct UndoRow: View {
        let showWord: Bool
        let onUndone: (ReviewEvent) -> Void

        @Environment(VocabStore.self) private var vocab

        init(showWord: Bool, onUndone: @escaping (ReviewEvent) -> Void) {
            self.showWord = showWord
            self.onUndone = onUndone
        }

        var body: some View {
            if let event = vocab.lastUndoable {
                Button {
                    if vocab.undo(event.id) {
                        onUndone(event)
                    }
                } label: {
                    Label("撤销上一次（\(summary(event))）", systemImage: "arrow.uturn.backward")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("这次作答作废，卡片回到作答前的状态")
            }
        }

        private func summary(_ event: ReviewEvent) -> String {
            var parts: [String] = []
            if showWord, let text = vocab.item(event.itemId)?.text {
                parts.append(text)
            }
            if let task = event.task {
                parts.append(task.title)
            }
            if let raw = event.rating, let rating = FSRSRating(rawValue: raw) {
                parts.append(rating.title)
            }
            return parts.joined(separator: " · ")
        }
    }

    fileprivate struct Stat: View {
        let value: String
        let title: String

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Theme.paper.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
        }
    }
}
