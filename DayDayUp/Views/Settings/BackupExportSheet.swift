import SwiftUI
import UniformTypeIdentifiers

/// 完整备份 with a disclosure first (PLAT-12): what the file will contain, with real counts, and what it leaves out
/// (content packs). Only "继续" builds the archive; the learner then chooses where it is saved.
struct BackupExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UserStore.self) private var user
    @Environment(PracticeStore.self) private var practice
    @Environment(VocabStore.self) private var vocab
    @Environment(AnnotationStore.self) private var annotations
    @Environment(StudyStore.self) private var study

    @State private var summary = BackupSummary()
    @State private var building = false
    @State private var document: BackupDocument?
    @State private var showExporter = false
    @State private var savedAt: Date?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                introSection
                includedSection
                excludedSection
                actionSection
            }
            .navigationTitle("完整备份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(savedAt == nil ? "取消" : "完成") {
                        dismiss()
                    }
                    .disabled(building)
                }
            }
            .onAppear {
                summary = BackupSummary.make(user: user, practice: practice, vocab: vocab, study: study)
            }
            .fileExporter(isPresented: $showExporter, document: document, contentType: .ddubackup,
                          defaultFilename: user.backupFileName) { result in
                finishExport(result)
            }
        }
    }

    // MARK: Sections

    private var introSection: some View {
        Section {
            Text("学习记录、录音和作文只存在这台 iPad 上。备份文件把它们打包成一个 .ddubackup 文件，你自己选择存到“文件”App 或 iCloud 云盘。")
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent("上次备份", value: lastBackupText)
        }
    }

    private var includedSection: some View {
        let s = summary
        return Section {
            SettingsNoteRow(symbol: "waveform",
                            title: "录音 \(s.recordings) 个，约 \(SettingsFormat.megabytes(s.recordingBytes))",
                            detail: "跟读、口语和词汇朗读的全部录音。备份文件的大小主要是它们。")
            SettingsNoteRow(symbol: "pencil.line",
                            title: "写作 \(s.writing) 篇（共 \(s.writingVersions) 版）",
                            detail: "作文原文和每一版改写，还有你录入的反馈 \(s.feedback) 条。")
            SettingsNoteRow(symbol: "mic",
                            title: "口语 \(s.speaking) 次、跟读 \(s.shadow) 次、完整模拟 \(s.mocks) 次",
                            detail: "时间、自评和笔记。")
            SettingsNoteRow(symbol: "list.bullet.rectangle", title: "学习记录",
                            detail: "听读 \(s.listenDays) 天、词项 \(s.vocabItems) 个、复习记录 \(s.reviews) 条、计划 \(s.planDays) 天、练习时段 \(s.stretches) 段、理解题 \(s.quizzes) 次。")
            SettingsNoteRow(symbol: "text.quote", title: "练过和收藏的句子",
                            detail: "跟读练过的句子、词条出处的原句，一句一句存着；没有整篇文章。")
            SettingsNoteRow(symbol: "gearshape", title: "设置",
                            detail: "阅读、声音、学习计划和词汇的设置，发音标注里你的改动。")
        } header: {
            Text("备份里有")
        }
    }

    private var excludedSection: some View {
        Section {
            SettingsNoteRow(symbol: "xmark.circle", title: "内容包",
                            detail: "文章、音频和词库不在备份里。在新 iPad 上恢复以后，要再导入内容包。")
            SettingsNoteRow(symbol: "xmark.circle", title: "诊断日志",
                            detail: "需要时在“关于与使用说明”里单独导出。")
        } header: {
            Text("备份里没有")
        } footer: {
            Text("App 不会自动上传备份。")
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        Section {
            if building {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("正在打包……录音多的时候要等一会儿。")
                }
            } else if let savedAt {
                Label("备份好了（\(savedAt.formatted(date: .abbreviated, time: .shortened))）。",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.level5)
            } else {
                Button {
                    startBackup()
                } label: {
                    Label("继续：打包并选择保存位置", systemImage: "externaldrive.badge.plus")
                }
            }
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.warn)
            }
        } footer: {
            Text("每周备份一次最稳妥。换 iPad、重装 App 或恢复以前，都要用到它。")
        }
    }

    private var lastBackupText: String {
        guard let date = user.state.lastBackup else { return "从未备份" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: Actions

    /// Shows the progress row first, then builds (building reads every recording into memory on this thread).
    private func startBackup() {
        building = true
        errorText = nil
        Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            buildBackup()
        }
    }

    private func buildBackup() {
        practice.saveNow()
        user.saveNow()
        vocab.saveNow()
        annotations.saveNow()
        study.saveNow()
        do {
            let extra = try vocab.backupFiles() + [try annotations.backupFile()] + (try study.backupFiles())
            let data = try BackupArchive.make(user: user, practice: practice, extraFiles: extra)
            document = BackupDocument(data: data)
            building = false
            showExporter = true
            DiagLog.shared.log("backup", "built \(data.count) bytes")
        } catch {
            building = false
            errorText = "备份没有生成：\(error.localizedDescription)"
            DiagLog.shared.log("backup", "build failed: \(error.localizedDescription)")
        }
    }

    private func finishExport(_ result: Result<URL, Error>) {
        document = nil
        switch result {
        case .success:
            user.markBackedUp()
            savedAt = Date()
            errorText = nil
            DiagLog.shared.log("backup", "exported")
        case .failure(let error):
            if (error as? CocoaError)?.code == .userCancelled {
                errorText = "没有保存：你取消了。备份文件没有存到任何地方。"
            } else {
                errorText = "备份没有完成：\(error.localizedDescription)"
            }
            DiagLog.shared.log("backup", "export failed: \(error.localizedDescription)")
        }
    }
}

/// Counts shown before a backup is made.
struct BackupSummary {
    var recordings = 0
    var recordingBytes = 0
    var writing = 0
    var writingVersions = 0
    var feedback = 0
    var speaking = 0
    var shadow = 0
    var mocks = 0
    var listenDays = 0
    var vocabItems = 0
    var reviews = 0
    var planDays = 0
    var stretches = 0
    var quizzes = 0

    @MainActor
    static func make(user: UserStore, practice: PracticeStore, vocab: VocabStore, study: StudyStore) -> BackupSummary {
        let p = practice.state
        let disk = practice.recordingsOnDisk()
        let speakingFeedback = p.speaking.reduce(0) { $0 + $1.feedback.count }
        let writingFeedback = p.writing.reduce(0) { $0 + $1.feedback.count }
        let mockFeedback = p.mocks.reduce(0) { $0 + $1.feedback.count }
        var s = BackupSummary()
        s.recordings = disk.count
        s.recordingBytes = disk.bytes
        s.writing = p.writing.count
        s.writingVersions = p.writing.reduce(0) { $0 + $1.versions.count }
        s.feedback = speakingFeedback + writingFeedback + mockFeedback
        s.speaking = p.speaking.count
        s.shadow = p.shadow.count
        s.mocks = p.mocks.count
        s.listenDays = user.state.daily.count
        s.vocabItems = vocab.state.items.count
        s.reviews = vocab.events.count
        s.planDays = study.state.plans.count
        s.stretches = study.activity.count
        s.quizzes = study.state.quizResults.count
        return s
    }
}
