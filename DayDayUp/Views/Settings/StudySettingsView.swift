import SwiftUI

/// 学习计划与提醒 (PLAN-P01, BASE-03, BASE-06, PLAN-P06, PAGE-08): daily time, stage, exam and the daily
/// reminder. Every section says what its setting changes. A time or stage change makes today's plan again
/// and keeps what is already done.
struct StudySettingsView: View {
    @Environment(StudyStore.self) private var study
    @Environment(PackStore.self) private var packs
    @Environment(UserStore.self) private var user
    @Environment(PracticeStore.self) private var practice
    @Environment(VocabStore.self) private var vocab

    /// Opened from 今日's "自定义": show the minutes stepper right away.
    private let customBudgetFirst: Bool

    @State private var budgetMode: StudyBudgetMode = .sixty
    @State private var loaded = false
    @State private var rebuildPending = false
    @State private var rebuildTask: Task<Void, Never>?
    @State private var reminderTask: Task<Void, Never>?
    @State private var planNote: String?

    init(customBudgetFirst: Bool = false) {
        self.customBudgetFirst = customBudgetFirst
    }

    var body: some View {
        Form {
            budgetSection
            stageSection
            examSection
            reminderSection
        }
        .navigationTitle("学习计划与提醒")
        .onAppear {
            if !loaded {
                loaded = true
                budgetMode = customBudgetFirst ? .custom : StudySettingsView.mode(for: study.settings.budgetMinutes)
            }
        }
        .onDisappear {
            rebuildNow()
        }
    }

    // MARK: 每天学习时间

    private var budgetSection: some View {
        Section {
            Picker("每天学习时间", selection: budgetModeBinding) {
                Text("60 分钟").tag(StudyBudgetMode.sixty)
                Text("90 分钟").tag(StudyBudgetMode.ninety)
                Text("自定义").tag(StudyBudgetMode.custom)
            }
            .pickerStyle(.segmented)
            if budgetMode == .custom {
                Stepper(value: budgetBinding, in: 30...120, step: 5) {
                    Text("每天 \(study.settings.budgetMinutes) 分钟")
                }
            }
            Text(splitText)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let planNote {
                Label(planNote, systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("每天学习时间")
        } footer: {
            Text("改了以后，今天的计划会重新排；已完成的任务保留。")
        }
    }

    /// PLAN-P01: how the minutes are split (60 = 10/20/15/15, 90 = 10/30/15/35).
    private var splitText: String {
        let split = PlanEngine.split(budget: study.settings.budgetMinutes, vocabMinutes: vocab.settings.budgetMinutes)
        let parts = [StudyCategory.vocab, .read, .shadow, .output].map { cat in
            "\(cat.title) \(split[cat] ?? 0)"
        }
        return "大致分配（分钟）：" + parts.joined(separator: " · ") + "。时间不够时先保留说写，缩短材料。"
    }

    private static func mode(for minutes: Int) -> StudyBudgetMode {
        switch minutes {
        case 60: return .sixty
        case 90: return .ninety
        default: return .custom
        }
    }

    private var budgetModeBinding: Binding<StudyBudgetMode> {
        Binding<StudyBudgetMode>(
            get: { budgetMode },
            set: { mode in
                budgetMode = mode
                switch mode {
                case .sixty: setBudget(60)
                case .ninety: setBudget(90)
                case .custom: break     // the stepper below sets the minutes
                }
            }
        )
    }

    private var budgetBinding: Binding<Int> {
        Binding<Int>(
            get: { study.settings.budgetMinutes },
            set: { setBudget(min(120, max(30, $0))) }
        )
    }

    private func setBudget(_ minutes: Int) {
        guard study.settings.budgetMinutes != minutes else { return }
        study.updateSettings { $0.budgetMinutes = minutes }
        scheduleRebuild()
    }

    // MARK: 学习阶段

    private var stageSection: some View {
        Section {
            ForEach(StudyStage.allCases) { stage in
                Button {
                    setStage(stage)
                } label: {
                    stageRow(stage)
                }
            }
            NavigationLink {
                BaselineView()
            } label: {
                Label("首次基线（完成 \(study.state.baseline.doneCount)/4 项）", systemImage: "list.bullet.clipboard")
            }
        } header: {
            Text("学习阶段")
        } footer: {
            Text("先补基础，再冲 7 分。阶段只改变题目和材料的难度。")
        }
    }

    private func stageRow(_ stage: StudyStage) -> some View {
        let selected = study.settings.stage == stage
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? Theme.accent : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(stage.title)
                    .font(selected ? Font.body.weight(.semibold) : Font.body)
                    .foregroundStyle(Color.primary)
                Text(stage.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if selected {
                Text("当前")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    private func setStage(_ stage: StudyStage) {
        guard study.settings.stage != stage else { return }
        study.updateSettings { $0.stage = stage }
        scheduleRebuild()
    }

    // MARK: 考试

    private var examSection: some View {
        Section {
            Picker("考试类型", selection: examTypeBinding) {
                Text("学术类 Academic").tag("Academic")
                Text("培训类 General Training").tag("General Training")
            }
            Toggle("已经定了考试日期", isOn: examDateOnBinding)
            if study.settings.examDate != nil {
                DatePicker("考试日期", selection: examDateBinding, displayedComponents: .date)
            }
        } header: {
            Text("考试")
        } footer: {
            Text("不显示倒计时。日期只用来提醒你按阶段安排。")
        }
    }

    private var examTypeBinding: Binding<String> {
        Binding<String>(
            get: { study.settings.examType == "General Training" ? "General Training" : "Academic" },
            set: { value in study.updateSettings { $0.examType = value } }
        )
    }

    private var examDateOnBinding: Binding<Bool> {
        Binding<Bool>(
            get: { study.settings.examDate != nil },
            set: { on in
                let fallback = Calendar.current.date(byAdding: .day, value: 90, to: Date()) ?? Date()
                study.updateSettings { $0.examDate = on ? ($0.examDate ?? fallback) : nil }
            }
        )
    }

    private var examDateBinding: Binding<Date> {
        Binding<Date>(
            get: { study.settings.examDate ?? Date() },
            set: { value in study.updateSettings { $0.examDate = value } }
        )
    }

    // MARK: 提醒

    private var reminderSection: some View {
        Section {
            Toggle("每天提醒一次", isOn: reminderOnBinding)
            if study.settings.reminderOn {
                DatePicker("提醒时间", selection: reminderTimeBinding, displayedComponents: .hourAndMinute)
            }
            Toggle("静默时段", isOn: quietOnBinding)
            if study.settings.quietStartHour != nil && study.settings.quietEndHour != nil {
                Picker("从", selection: quietStartBinding) {
                    hourOptions
                }
                Picker("到", selection: quietEndBinding) {
                    hourOptions
                }
            }
            if let status = study.reminderStatus {
                Label(status, systemImage: "bell")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("提醒")
        } footer: {
            Text("默认关闭。选好时间才提醒，每天最多一次；静默时段里不提醒。提醒只在这台 iPad 上，不联网。")
        }
    }

    private var hourOptions: some View {
        ForEach(0..<24, id: \.self) { h in
            Text(String(format: "%02d:00", h)).tag(h)
        }
    }

    private var reminderOnBinding: Binding<Bool> {
        Binding<Bool>(
            get: { study.settings.reminderOn },
            set: { on in
                study.updateSettings { $0.reminderOn = on }
                applyReminderSoon()
            }
        )
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding<Date>(
            get: {
                let s = study.settings
                return Calendar.current.date(bySettingHour: s.reminderHour, minute: s.reminderMinute, second: 0,
                                             of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                study.updateSettings { s in
                    s.reminderHour = min(23, max(0, c.hour ?? s.reminderHour))
                    s.reminderMinute = min(59, max(0, c.minute ?? s.reminderMinute))
                }
                applyReminderSoon()
            }
        )
    }

    private var quietOnBinding: Binding<Bool> {
        Binding<Bool>(
            get: { study.settings.quietStartHour != nil && study.settings.quietEndHour != nil },
            set: { on in
                study.updateSettings { s in
                    if on {
                        s.quietStartHour = s.quietStartHour ?? 22
                        s.quietEndHour = s.quietEndHour ?? 7
                    } else {
                        s.quietStartHour = nil
                        s.quietEndHour = nil
                    }
                }
                applyReminderSoon()
            }
        )
    }

    private var quietStartBinding: Binding<Int> {
        Binding<Int>(
            get: { study.settings.quietStartHour ?? 22 },
            set: { h in
                study.updateSettings { $0.quietStartHour = h }
                applyReminderSoon()
            }
        )
    }

    private var quietEndBinding: Binding<Int> {
        Binding<Int>(
            get: { study.settings.quietEndHour ?? 7 },
            set: { h in
                study.updateSettings { $0.quietEndHour = h }
                applyReminderSoon()
            }
        )
    }

    /// Applies the reminder after the last of a quick run of changes (a time wheel sends many).
    private func applyReminderSoon() {
        reminderTask?.cancel()
        reminderTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            await study.applyReminder()
        }
    }

    // MARK: Plan rebuild

    /// Several quick changes (stepper taps) make the plan once.
    private func scheduleRebuild() {
        rebuildPending = true
        rebuildTask?.cancel()
        rebuildTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            if Task.isCancelled { return }
            rebuildNow()
        }
    }

    private func rebuildNow() {
        rebuildTask?.cancel()
        rebuildTask = nil
        guard rebuildPending else { return }
        rebuildPending = false
        TodayPlanner.rebuild(packs: packs, user: user, practice: practice, vocab: vocab, study: study)
        planNote = "今天的计划已经按新设置重新排了，已完成的任务保留。"
    }
}

private enum StudyBudgetMode: Hashable {
    case sixty, ninety, custom
}
