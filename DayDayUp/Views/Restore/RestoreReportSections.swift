import SwiftUI

/// What the drill found (ACC-26, ACC-27): the backup, record counts per file, the check against the counts
/// written at backup time, missing content packs and recordings, what an older backup does not have,
/// and a clear refusal for a damaged file.
struct RestoreReportSections: View {
    let report: RestoreReport

    var body: some View {
        if let refusal = report.refusal {
            refusalSection(refusal)
        }
        sourceSection
        if report.refusal == nil {
            filesSection
            if !report.checks.isEmpty {
                checksSection
            }
            missingSection
            if !report.migration.isEmpty || !report.keptAsIs.isEmpty {
                migrationSection
            }
            if !report.warnings.isEmpty {
                warningsSection
            }
        }
    }

    private func refusalSection(_ text: String) -> some View {
        Section {
            Label {
                Text("这个备份不能用")
                    .font(.headline)
            } icon: {
                Image(systemName: "xmark.octagon.fill")
            }
            .foregroundStyle(Color.red)
            Text(text)
            Text("现在的记录没有改动。")
                .foregroundStyle(.secondary)
        }
    }

    private var sourceSection: some View {
        Section("备份") {
            LabeledContent("文件", value: report.sourceName)
            if !report.kindText.isEmpty {
                LabeledContent("类型", value: report.kindText)
            }
            if let app = report.appVersion {
                LabeledContent("App 版本", value: app)
            }
            if let created = report.created {
                LabeledContent("时间", value: created.formatted(date: .abbreviated, time: .shortened))
            }
            if report.backupBytes > 0 {
                LabeledContent("大小", value: PackImporter.sizeText(Int64(report.backupBytes)))
            }
        }
    }

    private var filesSection: some View {
        Section {
            ForEach(report.files) { line in
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.title)
                        .font(.headline)
                    Text(line.detail)
                    Text(line.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("在临时库里解开后的记录")
        } footer: {
            Text("每个文件都用 App 自己读数据的方式解码过一遍。")
        }
    }

    private var checksSection: some View {
        Section {
            ForEach(report.checks) { check in
                RestoreCheckRow(check: check)
            }
        } header: {
            Text("清单核对")
        } footer: {
            Text("左边是备份时记下的数量，右边是现在解开后数出来的数量。")
        }
    }

    @ViewBuilder
    private var missingSection: some View {
        Section {
            if report.missingIssues.isEmpty && report.missingRecordingCount == 0 {
                Label("记录用到的内容包和录音都在。", systemImage: "checkmark.circle")
            }
            ForEach(report.missingIssues) { issue in
                Label(issue.text, systemImage: "shippingbox")
            }
            if report.missingRecordingCount > 0 {
                missingRecordingLines
            }
            if report.recordingsOnlyOnDevice > 0 {
                Label("\(report.recordingsOnlyOnDevice) 个录音不在备份里，但这台 iPad 上有，恢复后照常能播放。",
                      systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("缺少的内容")
        } footer: {
            Text("缺的东西只列清单，不用空内容代替。")
        }
    }

    private var missingRecordingLines: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("缺 \(report.missingRecordingCount) 个录音（备份里没有，这台 iPad 上也没有）：这些条目恢复后只有文字记录。",
                  systemImage: "waveform.slash")
                .foregroundStyle(Theme.warn)
            ForEach(Array(report.missingRecordings.enumerated()), id: \.offset) { item in
                Text("· " + item.element)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if report.missingRecordingCount > report.missingRecordings.count {
                Text("……还有 \(report.missingRecordingCount - report.missingRecordings.count) 个")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var migrationSection: some View {
        Section {
            ForEach(Array(report.migration.enumerated()), id: \.offset) { item in
                Text(item.element)
            }
            if !report.keptAsIs.isEmpty {
                Text("备份里没有、恢复时保持现在样子的记录：" + report.keptAsIs.joined(separator: "、"))
            }
        } header: {
            Text(migrationHeader)
        }
    }

    private var migrationHeader: String {
        report.isSnapshot ? "说明" : "旧版备份怎么处理"
    }

    private var warningsSection: some View {
        Section("注意") {
            ForEach(Array(report.warnings.enumerated()), id: \.offset) { item in
                Label(item.element, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.warn)
            }
        }
    }
}

/// One count check: symbol + words, never colour alone.
struct RestoreCheckRow: View {
    let check: RestoreCountCheck

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: check.matches ? "checkmark.circle" : "exclamationmark.triangle.fill")
                .foregroundStyle(check.matches ? Theme.accent : Theme.warn)
                .accessibilityHidden(true)
            Text(check.label)
            Spacer(minLength: 8)
            Text(valueText)
                .foregroundStyle(check.matches ? Color.secondary : Theme.warn)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private var valueText: String {
        check.matches
            ? "\(check.found)，一致"
            : "清单 \(check.listed) · 解开 \(check.found)，不一致"
    }
}
