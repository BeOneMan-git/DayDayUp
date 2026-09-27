import SwiftUI

/// RPT-01 / MET-P03 周报 for the week that starts on `week` (Monday day key, e.g. "2026-09-21").
/// Works pushed or inside a sheet: it only sets .navigationTitle and repeats the title in its content.
/// Opening it marks the report as prepared.
struct WeeklyReportView: View {
    let week: String
    @Environment(StudyStore.self) private var study
    @Environment(VocabStore.self) private var vocab
    @Environment(PracticeStore.self) private var practice
    @Environment(PackStore.self) private var packs
    @State private var exportFormat: WeeklyExportFormat?

    init(week: String) {
        self.week = week
    }

    var body: some View {
        let data = WeeklyData.make(week: week, study: study, vocab: vocab, practice: practice, packs: packs)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(data)
                ForEach(data.sections) { section in
                    WeeklySectionCard(section: section)
                }
                WeeklyRecordsCard(week: week)
                exportCard
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("周报 " + ProgressFormat.weekRange(week))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if study.state.weeklyReports[week] == nil {
                study.markReportPrepared(week)
            }
        }
        .sheet(item: $exportFormat) { format in
            WeeklyExportSheet(week: week, format: format)
        }
    }

    private func header(_ data: WeeklyData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("周报 " + ProgressFormat.weekRange(week))
                .font(.largeTitle.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(data.headerLines.enumerated()), id: \.offset) { item in
                Text(item.element)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var exportCard: some View {
        ProgressCard("导出", symbol: "square.and.arrow.up",
                     footnote: "导出前会先告诉你文件里有什么、没有什么。App 不会自动发送。") {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    exportButtons
                }
                VStack(alignment: .leading, spacing: 10) {
                    exportButtons
                }
            }
        }
    }

    private var exportButtons: some View {
        ForEach(WeeklyExportFormat.allCases) { format in
            Button {
                exportFormat = format
            } label: {
                Label(format.buttonTitle, systemImage: format.symbol)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}

/// One section of the report as a card: lines, a "样本少" marker when needed, and how it is counted.
struct WeeklySectionCard: View {
    let section: WeeklySection

    var body: some View {
        ProgressCard(section.title, symbol: section.symbol, footnote: section.note) {
            if let flag = section.flag {
                SmallSampleTag(flag)
            }
            ForEach(Array(section.lines.enumerated()), id: \.offset) { item in
                Text(item.element)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// ACC-30: the stretches of practice behind the minutes, so every number can be traced to its records.
struct WeeklyRecordsCard: View {
    let week: String
    @Environment(StudyStore.self) private var study

    var body: some View {
        let days = Set(Metrics.weekDays(week))
        let records = study.activity.filter { days.contains($0.day) }.sorted { $0.start < $1.start }
        ProgressCard("原始记录", symbol: "list.bullet.rectangle",
                     footnote: "每一段是一次连续的练习操作。上面的分钟数就是把这些记录里重叠的部分合并后算的；重复点“完成”不会多算。") {
            if records.isEmpty {
                Text("这周没有练习时间记录。")
                    .foregroundStyle(.secondary)
            } else {
                ProgressDisclosure("查看 \(records.count) 段记录") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(records) { record in
                            Text(line(record))
                                .font(.caption)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    private func line(_ r: ActivityRecord) -> String {
        var parts = [ProgressFormat.short(r.day) + " " + ProgressFormat.time(r.start) + "–" + ProgressFormat.time(r.end),
                     r.cat.title,
                     String(format: "%.1f 分钟", r.seconds / 60)]
        if let source = r.source, !source.isEmpty {
            parts.append("来源 " + source)
        }
        if r.background {
            parts.append("后台播放，不计入")
        }
        return parts.joined(separator: " · ")
    }
}

/// PLAT-12: says what the file contains and what it does not, before anything is written.
/// 继续导出 writes the file into the temporary folder; the learner then chooses where it goes.
struct WeeklyExportSheet: View {
    let week: String
    let format: WeeklyExportFormat
    @Environment(\.dismiss) private var dismiss
    @Environment(StudyStore.self) private var study
    @Environment(VocabStore.self) private var vocab
    @Environment(PracticeStore.self) private var practice
    @Environment(PackStore.self) private var packs
    @State private var fileURL: URL?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("周报 " + ProgressFormat.weekRange(week))
                    Text(format.detail)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("要导出")
                }
                Section {
                    ForEach(WeeklyExport.included, id: \.self) { item in
                        Label(item, systemImage: "checkmark.circle")
                    }
                } header: {
                    Text("文件里有")
                }
                Section {
                    ForEach(WeeklyExport.excluded, id: \.self) { item in
                        Label(item, systemImage: "xmark.circle")
                    }
                } header: {
                    Text("文件里没有")
                }
                Section {
                    Label("App 不会自动发送。你自己选择保存或分享到哪里。", systemImage: "hand.raised")
                }
                actionSection
            }
            .navigationTitle(format.buttonTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(fileURL == nil ? "取消" : "完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        if let url = fileURL {
            Section {
                Label(url.lastPathComponent, systemImage: "doc")
                ShareLink(item: url) {
                    Label("保存或分享…", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("文件已准备好")
            } footer: {
                Text("在分享面板里选“存储到文件”，文件只存在你的 iPad 或你自己的 iCloud 云盘里。")
            }
        } else {
            Section {
                Button {
                    export()
                } label: {
                    Label("继续导出", systemImage: "arrow.down.doc")
                }
                Button("取消", role: .cancel) {
                    dismiss()
                }
            } footer: {
                if let errorText {
                    Text(errorText)
                }
            }
        }
    }

    private func export() {
        let data = WeeklyData.make(week: week, study: study, vocab: vocab, practice: practice, packs: packs)
        do {
            fileURL = try WeeklyExport.write(data, as: format)
            errorText = nil
        } catch {
            errorText = "文件没有生成：\(error.localizedDescription)"
        }
    }
}
