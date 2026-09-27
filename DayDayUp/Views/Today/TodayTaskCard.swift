import SwiftUI

/// One task of today's plan (PAGE-01, UI-02): category and minutes, what to do, why it was chosen (always
/// shown), its state as symbol + text, and what can be done with it. Done tasks stay on the page, dimmed,
/// so the day stays readable.
struct TodayTaskCard: View {
    let task: PlanTask
    /// Title of the main button ("开始" / "继续" / "再打开"); nil = no main button.
    let startTitle: String?
    /// Why the main button cannot work now (the article's content pack is gone).
    let blocked: String?
    let canSwap: Bool
    let onStart: () -> Void
    let onSwap: () -> Void
    let onDefer: () -> Void
    let onMarkDone: () -> Void
    let onReopen: () -> Void

    private var isOpen: Bool { task.state == .todo }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Text(task.title)
                .font(.headline)
                .foregroundStyle(isOpen ? Color.primary : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            reasonBlock
            statusLabel
            if let blocked {
                Label(blocked, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chip.opacity(isOpen ? 0.6 : 0.3), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(isOpen ? 0 : 0.25)))
    }

    // MARK: Parts

    private var isBaseline: Bool { task.target == .baseline }

    private var categoryTitle: String {
        isBaseline ? "基线" : task.cat.title
    }

    private var categorySymbol: String {
        isBaseline ? "list.bullet.clipboard" : task.cat.symbol
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(categoryTitle, systemImage: categorySymbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isOpen ? Theme.accent : Color.secondary)
            Text("\(task.minutes) 分钟")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var reasonBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("为什么推荐", systemImage: "lightbulb")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(task.reason)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private var statusLabel: some View {
        Label(statusText, systemImage: statusSymbol)
            .font(.callout.weight(.medium))
            .foregroundStyle(statusColor)
    }

    private var statusText: String {
        switch task.state {
        case .todo:
            return "待开始"
        case .done:
            guard let at = task.doneAt else { return "已完成" }
            return "已完成（\(TodayTaskCard.clock(at))）"
        case .deferred:
            return "已暂缓到明天"
        }
    }

    private var statusSymbol: String {
        switch task.state {
        case .todo: return "circle"
        case .done: return "checkmark.circle.fill"
        case .deferred: return "arrow.turn.up.right"
        }
    }

    private var statusColor: Color {
        switch task.state {
        case .todo: return Color.secondary
        case .done: return Theme.level5
        case .deferred: return Theme.warn
        }
    }

    /// "HH:mm" in the current time zone.
    static func clock(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    // MARK: Actions

    private var actions: some View {
        FlowLayout(spacing: 10, lineSpacing: 10) {
            if let startTitle {
                startButton(startTitle)
            }
            if isOpen && canSwap {
                Button(action: onSwap) {
                    Label("换一篇", systemImage: "arrow.triangle.2.circlepath")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            if isOpen {
                Button(action: onDefer) {
                    Label("暂缓", systemImage: "moon.zzz")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            moreMenu
        }
    }

    @ViewBuilder
    private func startButton(_ title: String) -> some View {
        if isOpen {
            Button(action: onStart) {
                Label(title, systemImage: "play.fill")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(blocked != nil)
        } else {
            Button(action: onStart) {
                Label(title, systemImage: "arrow.right.circle")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(blocked != nil)
        }
    }

    private var moreMenu: some View {
        Menu {
            if task.state != .done {
                Button(action: onMarkDone) {
                    Label("标记完成", systemImage: "checkmark.circle")
                }
            }
            if task.state != .todo {
                Button(action: onReopen) {
                    Label("重新打开", systemImage: "arrow.uturn.backward.circle")
                }
            }
        } label: {
            Label("更多", systemImage: "ellipsis.circle")
                .frame(minHeight: 44)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .accessibilityLabel("更多操作")
    }
}
