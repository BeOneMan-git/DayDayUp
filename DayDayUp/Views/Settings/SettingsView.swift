import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 设置: reading options, content packs, recordings, backup and restore, diagnostics, about.
/// Each sheet or alert hangs on its own row, so two presentations never share one view.
struct SettingsView: View {
    @Environment(PackStore.self) private var packs
    @Environment(UserStore.self) private var user
    @Environment(PracticeStore.self) private var practice
    @Environment(VocabStore.self) private var vocab
    @Environment(AnnotationStore.self) private var annotations
    @Environment(StudyStore.self) private var study
    @Environment(ReadingSession.self) private var session

    private enum ImportMode { case packs, backup }

    @State private var importMode: ImportMode = .packs
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var backupDoc: BackupDocument?
    @State private var pendingRestore: BackupContents?
    @State private var packToDelete: InstalledPack?
    @State private var alertText: String?
    @State private var recordingInfo = "……"
    @State private var diagURL: URL?

    var body: some View {
        Form {
            Section("阅读") {
                NavigationLink {
                    ReaderSettingsView()
                        .navigationTitle("阅读与标注")
                } label: {
                    Label("阅读与标注", systemImage: "textformat.size")
                }
            }

            Section {
                if packs.packs.isEmpty {
                    Text("还没有导入内容包。").foregroundStyle(.secondary)
                }
                ForEach(packs.packs) { pack in
                    packRow(pack)
                        .swipeActions {
                            Button(role: .destructive) {
                                packToDelete = pack
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                }
                importPacksButton
                if let message = packs.lastMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("内容包")
            } footer: {
                Text("共 \(packs.articleCount) 篇。删除内容包不会删除你的学习记录；重新导入后，进度和生词都还在。")
            }

            Section {
                LabeledContent("上次备份", value: lastBackupText)
                LabeledContent("录音", value: recordingInfo)
                backupButton
                restoreButton
                if let err = user.saveError {
                    Text("保存出错：\(err)").font(.footnote).foregroundStyle(.red)
                }
                if let err = practice.saveError {
                    Text("练习记录保存出错：\(err)").font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("数据与备份")
            } footer: {
                Text("学习记录、跟读和口语录音、写作作品只存在这台 iPad 上。完整备份（.ddubackup）把它们一起打包，每周备份一次，存到“文件”App 或 iCloud 云盘。录音不会自动删除。")
            }

            Section {
                Button {
                    exportDiagnostics()
                } label: {
                    Label("导出诊断日志", systemImage: "stethoscope")
                }
                if let diagURL {
                    ShareLink(item: diagURL) {
                        Label("分享诊断日志", systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text("诊断")
            } footer: {
                Text("出问题时导出一次。文件存在“文件”App：我的 iPad › DayDayUp › 诊断；电脑上用 iTunes 文件共享也能取到。日志里没有录音，也没有文章正文。")
            }

            Section("关于") {
                LabeledContent("版本", value: BackupArchive.appVersionText())
                LabeledContent("内容格式", value: "ecopack v1")
                Text("DayDayUp 只供个人学习使用。App 用免费 Apple ID 签名，每 7 天要在电脑上用 AltServer 重新安装一次。重新安装是覆盖安装，学习记录、录音和内容包都在；过期了也不要删除 App。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
        .onAppear { refreshRecordingInfo() }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: importMode == .packs ? [.ecopack, .data] : [.ddubackup, .json],
                      allowsMultipleSelection: importMode == .packs) { result in
            handleImport(result)
        }
        .alert(alertText ?? "", isPresented: Binding(
            get: { alertText != nil }, set: { if !$0 { alertText = nil } }
        )) {
            Button("好") { alertText = nil }
        }
    }

    // MARK: Rows

    private var importPacksButton: some View {
        Button {
            importMode = .packs
            showImporter = true
        } label: {
            Label("导入内容包", systemImage: "square.and.arrow.down")
        }
        .confirmationDialog("删除这个内容包？", isPresented: Binding(
            get: { packToDelete != nil }, set: { if !$0 { packToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let pack = packToDelete { packs.delete(pack) }
                packToDelete = nil
            }
        } message: {
            Text("文章和音频会从 iPad 上移除。学习记录会保留。")
        }
    }

    private var backupButton: some View {
        Button {
            makeBackup()
        } label: {
            Label("立即完整备份", systemImage: "externaldrive.badge.plus")
        }
        .fileExporter(isPresented: $showExporter, document: backupDoc, contentType: .ddubackup,
                      defaultFilename: user.backupFileName) { result in
            switch result {
            case .success:
                user.markBackedUp()
                alertText = "备份好了。"
                DiagLog.shared.log("backup", "exported")
            case .failure(let error):
                alertText = "备份没有完成：\(error.localizedDescription)"
                DiagLog.shared.log("backup", "export failed: \(error.localizedDescription)")
            }
        }
    }

    private var restoreButton: some View {
        Button {
            importMode = .backup
            showImporter = true
        } label: {
            Label("从备份恢复", systemImage: "clock.arrow.circlepath")
        }
        .alert("用备份替换现在的学习记录？", isPresented: Binding(
            get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }
        )) {
            Button("替换", role: .destructive) {
                if let contents = pendingRestore { applyRestore(contents) }
                pendingRestore = nil
            }
            Button("取消", role: .cancel) { pendingRestore = nil }
        } message: {
            Text(pendingRestore.map { "备份里有：\n" + $0.summary } ?? "")
        }
    }

    private func packRow(_ pack: InstalledPack) -> some View {
        let m = pack.manifest
        let mb = String(format: "%.1f", Double(pack.sizeOnDisk) / 1_000_000)
        return VStack(alignment: .leading, spacing: 2) {
            Text(m.parts > 1 ? "\(m.issue) 期 · 第 \(m.part)/\(m.parts) 部分" : "\(m.issue) 期")
                .font(.body.weight(.semibold))
            Text("\(m.articles.count) 篇 · \(mb) MB · \(m.version)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Helpers

    private var lastBackupText: String {
        guard let date = user.state.lastBackup else { return "从未备份" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func refreshRecordingInfo() {
        let r = practice.recordingsOnDisk()
        recordingInfo = "\(r.count) 个 · \(String(format: "%.1f", Double(r.bytes) / 1_000_000)) MB"
    }

    private func makeBackup() {
        practice.saveNow()
        user.saveNow()
        vocab.saveNow()
        do {
            annotations.saveNow()
            study.saveNow()
            let extra = try vocab.backupFiles() + [try annotations.backupFile()] + (try study.backupFiles())
            let data = try BackupArchive.make(user: user, practice: practice, extraFiles: extra)
            backupDoc = BackupDocument(data: data)
            showExporter = true
            DiagLog.shared.log("backup", "built \(data.count) bytes")
        } catch {
            alertText = "备份没有生成：\(error.localizedDescription)"
            DiagLog.shared.log("backup", "build failed: \(error.localizedDescription)")
        }
    }

    private func applyRestore(_ contents: BackupContents) {
        do {
            if let restoredPractice = contents.practice {
                try practice.restore(restoredPractice, recordings: contents.recordings)
            }
            if let restoredVocab = contents.vocab {
                try vocab.restore(restoredVocab, events: contents.vocabEvents)
            }
            if let data = contents.files["annotations-user.json"] {
                try annotations.restore(data)
            }
            if contents.files["study.json"] != nil || contents.files["activity.jsonl"] != nil {
                try study.restore(study: contents.files["study.json"], activity: contents.files["activity.jsonl"])
            }
            user.restore(contents.user)
            session.refreshMarks()
            refreshRecordingInfo()
            alertText = "已恢复。"
            DiagLog.shared.log("backup", "restored practice=\(contents.practice != nil) recordings=\(contents.recordings.count)")
        } catch {
            alertText = "恢复没有完成，现有记录没有改动：\(error.localizedDescription)"
            DiagLog.shared.log("backup", "restore failed: \(error.localizedDescription)")
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let first = urls.first else { return }
        switch importMode {
        case .packs:
            Task {
                var messages: [String] = []
                for url in urls {
                    messages.append(await packs.importPack(from: url))
                }
                packs.lastMessage = messages.joined(separator: "\n")
            }
        case .backup:
            do {
                pendingRestore = try user.readBackup(at: first)
            } catch {
                alertText = "这个文件不是 DayDayUp 备份：\(error.localizedDescription)"
            }
        }
    }

    /// Writes a text report (versions, counts, content reports, the log) into Documents/诊断.
    private func exportDiagnostics() {
        practice.saveNow()
        let p = practice.state
        let rec = practice.recordingsOnDisk()
        var lines: [String] = []
        lines.append("DayDayUp 诊断日志")
        lines.append("时间：\(Date().formatted(date: .numeric, time: .standard))")
        lines.append("版本：\(BackupArchive.appVersionText())")
        lines.append("设备：\(UIDevice.current.model) · iPadOS \(UIDevice.current.systemVersion)")
        lines.append("内容包：\(packs.packs.count) 个，\(packs.articleCount) 篇")
        lines.append("生词 \(user.state.star.count)，认识 \(user.state.known.count)，听读 \(user.state.daily.count) 天")
        lines.append("跟读 \(p.shadow.count) 次，口语 \(p.speaking.count) 次，写作 \(p.writing.count) 篇，录音 \(rec.count) 个")
        lines.append("音频线路：\(RecorderService.routeText())")
        lines.append("")
        lines.append("== 报错（\(p.reports.count)）==")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(p.reports) {
            lines.append(String(decoding: data, as: UTF8.self))
        }
        lines.append("")
        lines.append("== 日志 ==")
        lines.append(DiagLog.shared.contents())
        let text = lines.joined(separator: "\n")

        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("诊断", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let stamp = DayKey.today + "-" + String(Int(Date().timeIntervalSince1970) % 100_000)
            let url = dir.appendingPathComponent("DayDayUp-诊断-\(stamp).txt")
            try Data(text.utf8).write(to: url, options: .atomic)
            diagURL = url
            alertText = "诊断日志已导出到“文件”App：我的 iPad › DayDayUp › 诊断。"
        } catch {
            alertText = "诊断日志没有导出：\(error.localizedDescription)"
        }
    }
}
