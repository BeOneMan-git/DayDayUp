import SwiftUI

/// 录音占用与清理 (REC-KEEP): how much room the recordings take, and a cleanup that runs only after a preview
/// and two taps (the button, then the confirmation). Nothing is ever deleted automatically. Only files are deleted:
/// every practice record stays, and the pages that play recordings show them as gone.
struct RecordingStorageView: View {
    @Environment(PracticeStore.self) private var practice
    @Environment(VocabStore.self) private var vocab
    @Environment(StudyStore.self) private var study
    @Environment(PackStore.self) private var packs
    @Environment(UserStore.self) private var user
    @Environment(RecorderService.self) private var recorder

    @State private var usage = RecordingUsage()
    @State private var plan: CleanupPlan?
    @State private var includeUnlinked = false
    @State private var confirming = false
    @State private var result: String?

    /// How many example groups the preview shows per kind.
    private static let exampleLimit = 5

    var body: some View {
        Form {
            usageSection
            rulesSection
            previewSection
            if let plan {
                summarySection(plan)
                reasonsSection(plan)
                examplesSection(plan, kind: .shadow)
                examplesSection(plan, kind: .speaking)
                unlinkedSection(plan)
                deleteSection(plan)
            }
        }
        .navigationTitle("录音占用与清理")
        .onAppear { refreshUsage() }
    }

    // MARK: 占用

    private var usageSection: some View {
        Section {
            LabeledContent("录音文件", value: "\(usage.count) 个")
            LabeledContent("占用空间", value: SettingsFormat.megabytes(usage.bytes))
            LabeledContent("iPad 可用空间", value: usage.free.map { SettingsFormat.gigabytes($0) } ?? "读不到")
            if let result {
                Label(result, systemImage: "checkmark.circle")
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("占用")
        } footer: {
            Text("录音只存在这台 iPad 上，App 从不自动删除。完整备份会把录音一起带走。")
        }
    }

    // MARK: 规则

    private var rulesSection: some View {
        Section {
            ForEach(RecordingKeepReason.allCases) { reason in
                SettingsNoteRow(symbol: reason.symbol, title: reason.title, detail: reason.detail)
            }
            SettingsNoteRow(symbol: "speaker.slash", title: "只录到静音的",
                            detail: "不算在“首次”和“最近 3 次”里；一组里全是静音时，才按全部录音算。")
        } header: {
            Text("清理时一定保留")
        } footer: {
            Text("跟读按“同一句、同一种跟读方式”分组，口语按题目分组。删的只是录音文件，练习记录都还在；放不出来的录音，回放按钮是灰的，进度页写“录音已清理”。")
        }
    }

    // MARK: 预览

    private var previewSection: some View {
        Section {
            Button {
                makePlan()
            } label: {
                Label(plan == nil ? "预览清理" : "重新预览", systemImage: "eye")
            }
            .disabled(usage.count == 0)
        } footer: {
            Text(usage.count == 0 ? "现在没有录音文件。" : "预览只列出来，不删任何东西。")
        }
    }

    private func summarySection(_ plan: CleanupPlan) -> some View {
        Section {
            SettingsNoteRow(symbol: "trash",
                            title: "可以删除：\(plan.candidates.count) 个，约 \(SettingsFormat.megabytes(plan.candidateBytes))",
                            detail: "有练习记录，但不属于上面任何一种要保留的录音。")
            SettingsNoteRow(symbol: "lock",
                            title: "保留：\(plan.kept.count) 个，约 \(SettingsFormat.megabytes(plan.keptBytes))",
                            detail: "原因见下面。")
            if plan.missingFiles > 0 {
                SettingsNoteRow(symbol: "speaker.slash", title: "记录还在、文件已经不在：\(plan.missingFiles) 个",
                                detail: "以前清理过，或者恢复备份时没有带上。")
            }
        } header: {
            Text("预览结果")
        }
    }

    private func reasonsSection(_ plan: CleanupPlan) -> some View {
        Section {
            ForEach(RecordingKeepReason.allCases) { reason in
                reasonRow(reason, count: plan.keptCount(reason))
            }
        } header: {
            Text("保留的原因")
        } footer: {
            Text("一个录音可能同时有几个原因，所以加起来会比保留的总数多。")
        }
    }

    @ViewBuilder
    private func reasonRow(_ reason: RecordingKeepReason, count: Int) -> some View {
        if count > 0 {
            LabeledContent {
                Text("\(count) 个")
            } label: {
                Label(reason.title, systemImage: reason.symbol)
            }
        }
    }

    @ViewBuilder
    private func examplesSection(_ plan: CleanupPlan, kind: RecordingCleanupGroup.Kind) -> some View {
        let groups = plan.groups.filter { $0.kind == kind }
        if !groups.isEmpty {
            Section {
                ForEach(Array(groups.prefix(RecordingStorageView.exampleLimit))) { group in
                    exampleRow(group)
                }
                if groups.count > RecordingStorageView.exampleLimit {
                    Text("另外还有 \(groups.count - RecordingStorageView.exampleLimit) 组也会删掉一些录音。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(kind == .shadow ? "例子：跟读（删得最多的几组）" : "例子：口语（删得最多的几组）")
            }
        }
    }

    private func exampleRow(_ group: RecordingCleanupGroup) -> some View {
        let total = group.kept.count + group.candidates.count
        let size = SettingsFormat.megabytes(group.candidateBytes)
        return VStack(alignment: .leading, spacing: 4) {
            Text(exampleTitle(group))
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(exampleDetail(group))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("共 \(total) 个录音：保留 \(group.kept.count) 个，删除 \(group.candidates.count) 个（约 \(size)）")
                .font(.caption)
        }
        .accessibilityElement(children: .combine)
    }

    private func exampleTitle(_ group: RecordingCleanupGroup) -> String {
        switch group.kind {
        case .shadow:
            guard let key = group.articleKey else { return "跟读" }
            if let ref = ArticleRef(key: key), let item = packs.item(ref) {
                return item.meta.title
            }
            return key
        case .speaking:
            return RecordingStorageView.snippet(group.text)
        }
    }

    private func exampleDetail(_ group: RecordingCleanupGroup) -> String {
        switch group.kind {
        case .shadow:
            return group.label + " · " + RecordingStorageView.snippet(group.text)
        case .speaking:
            return group.label
        }
    }

    @ViewBuilder
    private func unlinkedSection(_ plan: CleanupPlan) -> some View {
        if !plan.unlinked.isEmpty || plan.recentUnlinked > 0 {
            Section {
                if !plan.unlinked.isEmpty {
                    Toggle(isOn: $includeUnlinked) {
                        SettingsItemTitle(title: "也删除没有记录的文件（\(plan.unlinked.count) 个，约 \(SettingsFormat.megabytes(plan.unlinkedBytes))）",
                                          detail: "这些文件没有对应的练习记录，App 里放不出来。常见来源：词汇朗读重录前的旧录音、只录到静音或没作答就离开的词汇朗读、复述追问重答前的旧录音、恢复备份以前留下的录音。")
                    }
                }
                if plan.recentUnlinked > 0 {
                    Text("另有 \(plan.recentUnlinked) 个是最近 10 分钟里录的，可能还在保存，这次不动。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("没有记录的文件")
            } footer: {
                Text("默认不删。打开开关，才会和上面的录音一起删。")
            }
        }
    }

    // MARK: 删除

    private func deleteSection(_ plan: CleanupPlan) -> some View {
        let count = deleteCount(plan)
        let size = SettingsFormat.megabytes(deleteBytes(plan))
        return Section {
            Button(role: .destructive) {
                confirming = true
            } label: {
                Label("删除这些录音文件（\(count) 个，约 \(size)）", systemImage: "trash")
            }
            .disabled(count == 0 || recorder.isBusy)
            .confirmationDialog("确定删除 \(count) 个录音文件？", isPresented: $confirming, titleVisibility: .visible) {
                Button("删除 \(count) 个录音文件", role: .destructive) {
                    performCleanup(plan)
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删掉的录音找不回来。练习记录会保留，回放的地方会显示录音已清理。\(backupHint)")
            }
            if recorder.isBusy {
                Label("正在录音。录完再清理。", systemImage: "mic")
                    .font(.footnote)
            }
        } footer: {
            Text(count == 0 ? "按上面的规则，现在没有可以删的录音。" : "要按两次才会删：先按这里，再在确认框里按“删除”。")
        }
    }

    private func deleteCount(_ plan: CleanupPlan) -> Int {
        plan.candidates.count + (includeUnlinked ? plan.unlinked.count : 0)
    }

    private func deleteBytes(_ plan: CleanupPlan) -> Int {
        plan.candidateBytes + (includeUnlinked ? plan.unlinkedBytes : 0)
    }

    private var backupHint: String {
        guard let last = user.state.lastBackup else {
            return "你还没有做过完整备份，建议先备份。"
        }
        let when = last.formatted(date: .abbreviated, time: .shortened)
        return "上次完整备份：\(when)。"
    }

    // MARK: Actions

    private func refreshUsage() {
        let disk = practice.recordingsOnDisk()
        usage = RecordingUsage(count: disk.count, bytes: disk.bytes, free: SettingsFormat.freeSpace())
    }

    private func makePlan() {
        result = nil
        includeUnlinked = false
        plan = RecordingCleanup.plan(practice: practice, vocab: vocab, study: study)
        refreshUsage()
    }

    private func performCleanup(_ confirmed: CleanupPlan) {
        let outcome = RecordingCleanup.apply(confirmed, practice: practice, vocab: vocab, study: study,
                                             includeUnlinked: includeUnlinked)
        result = "已删除 \(outcome.deleted) 个录音文件，腾出约 \(SettingsFormat.megabytes(outcome.bytes))。练习记录都还在。"
        plan = nil
        includeUnlinked = false
        refreshUsage()
    }

    /// The first 40 characters of a sentence or question.
    static func snippet(_ text: String, limit: Int = 40) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > limit else { return clean }
        return String(clean.prefix(limit)) + "…"
    }
}

/// Recording files on disk and free space, read when the page appears and after a cleanup.
private struct RecordingUsage {
    var count = 0
    var bytes = 0
    var free: Int64? = nil
}
