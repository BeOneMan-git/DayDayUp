import SwiftUI
import UIKit

/// 设置 (PAGE-08): 学习 / 显示 / 音频 / 资源与能力 / 隐私 / 备份与恢复 / 关于与使用说明.
/// Every section's footer says what its settings change; details live on their own pages.
/// This page keeps the content pack list (swipe or long-press to delete, with a confirmation), backup and
/// restore, recordings, diagnostics and the about text.
/// The backup and restore sheets hang on the form, because more than one row opens them; each dialog or alert
/// hangs on the row that opens it, so two presentations never share one view.
struct SettingsView: View {
    @Environment(PackStore.self) private var packs
    @Environment(UserStore.self) private var user
    @Environment(PracticeStore.self) private var practice
    @Environment(VocabStore.self) private var vocab
    @Environment(StudyStore.self) private var study
    @Environment(\.scenePhase) private var scenePhase

    @State private var sheet: SettingsSheet?
    @State private var showPackImport = false
    @State private var packToDelete: InstalledPack?
    @State private var recordingInfo = "……"
    @State private var micStatus = MicrophoneStatus.notAsked
    @State private var diagURL: URL?
    @State private var diagMessage: String?

    var body: some View {
        Form {
            backupReminder
            studySection
            displaySection
            audioSection
            resourceSection
            privacySection
            backupSection
            aboutSection
        }
        .navigationTitle("设置")
        .onAppear { refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
        .sheet(item: $sheet, onDismiss: { refresh() }) { which in
            sheetContent(which)
        }
    }

    @ViewBuilder
    private func sheetContent(_ which: SettingsSheet) -> some View {
        switch which {
        case .backup:
            BackupExportSheet()
        case .restore:
            RestoreFlowView()
        }
    }

    // MARK: 备份提醒

    /// Shown when the last full backup is more than 7 days old (or there is none yet); 今日's "去备份" lands here.
    @ViewBuilder
    private var backupReminder: some View {
        if user.backupOverdue {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(backupOverdueTitle)
                            .font(.headline)
                        Text("学习记录只存在这台 iPad 上。每周备份一次，最稳妥。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .foregroundStyle(Theme.warn)
                }
                .accessibilityElement(children: .combine)
                Button {
                    sheet = .backup
                } label: {
                    Label("现在完整备份", systemImage: "externaldrive.badge.plus")
                }
            }
        }
    }

    private var backupOverdueTitle: String {
        guard let days = user.daysSinceBackup else { return "还没有做过完整备份" }
        return "已经 \(days) 天没有完整备份"
    }

    // MARK: 学习

    private var studySection: some View {
        Section {
            NavigationLink {
                StudySettingsView()
            } label: {
                SettingsLinkLabel(title: "学习计划与提醒", symbol: "calendar", value: studySummary)
            }
            NavigationLink {
                VocabSettingsView()
            } label: {
                SettingsLinkLabel(title: "词汇复习", symbol: "character.book.closed", value: vocabSummary)
            }
        } header: {
            Text("学习")
        } footer: {
            Text("每天的时间、学习阶段和考试决定今日计划；改了以后今天的计划重新排，已完成的保留。词汇设置改变复习排期和每天的量。")
        }
    }

    private var studySummary: String {
        let s = study.settings
        return "每天 \(s.budgetMinutes) 分钟 · \(s.stage.title)"
    }

    private var vocabSummary: String {
        let s = vocab.settings
        return "每天 \(Int(s.budgetMinutes)) 分钟 · 新任务 \(s.newPerDay) 个"
    }

    // MARK: 显示

    private var displaySection: some View {
        Section {
            Picker(selection: appearanceBinding) {
                ForEach(AppAppearance.allCases) { look in
                    Text(look.title).tag(look.rawValue)
                }
            } label: {
                Label("主题", systemImage: "circle.lefthalf.filled")
            }
            NavigationLink {
                ReaderSettingsView()
            } label: {
                SettingsLinkLabel(title: "阅读字号与标注", symbol: "textformat.size", value: fontSizeText)
            }
            .accessibilityIdentifier("settings-type-size")
        } header: {
            Text("显示")
        } footer: {
            Text("主题改变整个 App 的颜色；跟随系统时，iPad 换成深色，App 也跟着换。英文正文默认 24 pt，可以在 18–34 pt 之间调；界面文字跟随系统字号。")
        }
    }

    private var appearanceBinding: Binding<String> {
        Binding<String>(
            get: { AppAppearance(stored: user.settings.appearance).rawValue },
            set: { value in user.updateSettings { $0.appearance = value } }
        )
    }

    private var fontSizeText: String {
        "\(Int(user.settings.fontSize.rounded())) pt"
    }

    // MARK: 音频

    private var audioSection: some View {
        Section {
            NavigationLink {
                AudioSettingsView()
            } label: {
                SettingsLinkLabel(title: "声音与速度", symbol: "speaker.wave.2", value: audioSummary)
            }
        } header: {
            Text("音频")
        } footer: {
            Text("听读速度、循环间隔、跟读的原音速度和 A/B 间隔、复述时长、合成音的口音，下一次播放就用新的设置。里面也写了锁屏、拔耳机和来电话时会怎样。")
        }
    }

    private var audioSummary: String {
        let s = user.settings
        let listen = AudioSettingsView.rateText(s.rate)
        let shadow = AudioSettingsView.rateText(s.shadowRate)
        return "听读 \(listen) · 跟读 \(shadow)"
    }

    // MARK: 资源与能力

    private var resourceSection: some View {
        Section {
            InboxImportBanner()
            importPacksButton
            if packs.packs.isEmpty {
                Text("还没有导入内容包。")
                    .foregroundStyle(.secondary)
            }
            ForEach(packs.packs) { pack in
                packRow(pack)
            }
            if let message = packs.lastMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            NavigationLink {
                ResourceListView()
            } label: {
                SettingsLinkLabel(title: "资源清单", symbol: "checklist", value: "\(packs.articleCount) 篇")
            }
            NavigationLink {
                CapabilityListView()
            } label: {
                SettingsLinkLabel(title: "能力清单：断网能做什么", symbol: "wifi.slash")
            }
        } header: {
            Text("资源与能力")
        } footer: {
            Text("资源清单列出每篇文章在 iPad 上有什么、缺什么；能力清单说明断网能做什么。删除内容包不会删除你的学习记录；重新导入后，进度和生词都还在。")
        }
    }

    private var importPacksButton: some View {
        Button {
            showPackImport = true
        } label: {
            Label("导入内容包", systemImage: "square.and.arrow.down")
        }
        .packImportFlow(isPresented: $showPackImport)
    }

    private func packRow(_ pack: InstalledPack) -> some View {
        let m = pack.manifest
        let size = SettingsFormat.megabytes(PackLabels.bytes(m))
        let title = PackLabels.title(m)
        return VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body.weight(.semibold))
            Text("\(m.articles.count) 篇 · \(size) · \(PackLabels.version(m))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                packToDelete = pack
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                packToDelete = pack
            } label: {
                Label("删除这个内容包", systemImage: "trash")
            }
        }
        .confirmationDialog("删除这个内容包？", isPresented: deleteBinding(pack), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                packs.delete(pack)
                packToDelete = nil
            }
            Button("取消", role: .cancel) {
                packToDelete = nil
            }
        } message: {
            Text("\(title)：文章和音频会从 iPad 上移除。学习记录会保留，重新导入后都还在。")
        }
    }

    private func deleteBinding(_ pack: InstalledPack) -> Binding<Bool> {
        Binding<Bool>(
            get: { packToDelete?.id == pack.id },
            set: { shown in
                if !shown { packToDelete = nil }
            }
        )
    }

    // MARK: 隐私

    private var privacySection: some View {
        Section {
            SettingsNoteRow(symbol: "wifi.slash", title: "App 不联网，不上传",
                            detail: "文件只在你自己导出、分享或复制时离开 iPad。")
            SettingsLinkLabel(title: "麦克风", symbol: micStatus.symbol, value: micStatus.text)
            NavigationLink {
                PrivacySettingsView()
            } label: {
                SettingsLinkLabel(title: "导出的文件里有什么", symbol: "doc.text.magnifyingglass")
            }
        } header: {
            Text("隐私")
        } footer: {
            Text("这里不改设置，只说明数据在哪里、导出时带走什么。麦克风权限在 iPad 的“设置”里改，里面的页面有按钮直达。")
        }
    }

    // MARK: 备份与恢复

    private var backupSection: some View {
        Section {
            LabeledContent("上次备份", value: lastBackupText)
            Button {
                sheet = .backup
            } label: {
                Label("立即完整备份", systemImage: "externaldrive.badge.plus")
            }
            Button {
                sheet = .restore
            } label: {
                Label("从备份恢复", systemImage: "clock.arrow.circlepath")
            }
            NavigationLink {
                RecordingStorageView()
            } label: {
                SettingsLinkLabel(title: "录音占用与清理", symbol: "waveform", value: recordingInfo)
            }
            saveErrorRows
        } header: {
            Text("备份与恢复")
        } footer: {
            Text("学习记录、跟读和口语录音、写作作品只存在这台 iPad 上。完整备份（.ddubackup）把它们一起打包，每周备份一次，存到“文件”App 或 iCloud 云盘。恢复前会先试着解开，列出有什么、缺什么，你确认后才替换。录音不会自动删除。")
        }
    }

    private var lastBackupText: String {
        guard let date = user.state.lastBackup else { return "从未备份" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    @ViewBuilder
    private var saveErrorRows: some View {
        if let err = user.saveError {
            errorRow("学习记录保存出错：\(err)")
        }
        if let err = practice.saveError {
            errorRow("练习记录保存出错：\(err)")
        }
        if let err = vocab.saveError {
            errorRow("词汇记录保存出错：\(err)")
        }
        if let err = study.saveError {
            errorRow("计划记录保存出错：\(err)")
        }
    }

    private func errorRow(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(.red)
    }

    // MARK: 关于与使用说明

    private var aboutSection: some View {
        Section {
            LabeledContent("版本", value: BackupArchive.appVersionText())
            LabeledContent("内容包格式", value: "ecopack 格式 1 和 2")
            NavigationLink {
                UsageGuideView()
            } label: {
                SettingsLinkLabel(title: "使用说明", symbol: "book")
            }
            diagnosticsButton
            if let diagURL {
                ShareLink(item: diagURL) {
                    Label("分享诊断日志", systemImage: "square.and.arrow.up")
                }
            }
            Text("DayDayUp 只供个人学习使用。内容包只放在你自己的电脑和 iPad 上，不对外分发。App 用免费 Apple ID 签名，每 7 天要在电脑上用 AltServer 重新安装一次。重新安装是覆盖安装，学习记录、录音和内容包都在；过期了也不要删除 App。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("关于与使用说明")
        } footer: {
            Text("出问题时导出一次诊断日志。文件在“文件”App：我的 iPad › DayDayUp › 诊断；电脑上用 iTunes 文件共享也能取到。里面有什么，见“隐私”。")
        }
    }

    private var diagnosticsButton: some View {
        Button {
            exportDiagnostics()
        } label: {
            Label("导出诊断日志", systemImage: "stethoscope")
        }
        .alert(diagMessage ?? "", isPresented: diagAlertBinding) {
            Button("好") { diagMessage = nil }
        }
    }

    private var diagAlertBinding: Binding<Bool> {
        Binding<Bool>(
            get: { diagMessage != nil },
            set: { shown in
                if !shown { diagMessage = nil }
            }
        )
    }

    // MARK: Actions

    private func refresh() {
        let disk = practice.recordingsOnDisk()
        recordingInfo = "\(disk.count) 个 · " + SettingsFormat.megabytes(disk.bytes)
        micStatus = MicrophoneStatus.current()
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
        lines.append("词项 \(vocab.state.items.count)，复习记录 \(vocab.events.count) 条，计划 \(study.state.plans.count) 天")
        lines.append("音频线路：\(RecorderService.routeText())")
        lines.append("麦克风：\(MicrophoneStatus.current().text)")
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
            diagMessage = "诊断日志已导出到“文件”App：我的 iPad › DayDayUp › 诊断。"
        } catch {
            diagMessage = "诊断日志没有导出：\(error.localizedDescription)"
        }
    }
}

/// The two sheets of 设置.
private enum SettingsSheet: String, Identifiable {
    case backup, restore

    var id: String { rawValue }
}
