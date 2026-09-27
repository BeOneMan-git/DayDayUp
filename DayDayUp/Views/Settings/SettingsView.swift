import SwiftUI
import UniformTypeIdentifiers

/// 设置: reading options, content packs, backup and restore, about.
/// Each sheet or alert hangs on its own row, so two presentations never share one view.
struct SettingsView: View {
    @Environment(PackStore.self) private var packs
    @Environment(UserStore.self) private var user
    @Environment(ReadingSession.self) private var session

    private enum ImportMode { case packs, backup }

    @State private var importMode: ImportMode = .packs
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var backupDoc: BackupDocument?
    @State private var pendingRestore: UserState?
    @State private var packToDelete: InstalledPack?
    @State private var alertText: String?

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
                backupButton
                restoreButton
                if let err = user.saveError {
                    Text("保存出错：\(err)").font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("数据与备份")
            } footer: {
                Text("学习记录（进度、生词本、认识的词、听读时长）只存在这台 iPad 上。每周备份一次，存到“文件”App 或 iCloud 云盘。")
            }

            Section("关于") {
                LabeledContent("版本", value: appVersion)
                LabeledContent("内容格式", value: "ecopack v1")
                Text("DayDayUp 只供个人学习使用。App 用免费 Apple ID 签名，每 7 天需要在 AltStore 里续签一次；电脑开着 AltServer、在同一 Wi-Fi 下时会自动续。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: importMode == .packs ? [.ecopack, .data] : [.json],
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
            backupDoc = user.backupDocument()
            showExporter = true
        } label: {
            Label("立即备份", systemImage: "externaldrive.badge.plus")
        }
        .fileExporter(isPresented: $showExporter, document: backupDoc, contentType: .json,
                      defaultFilename: user.backupFileName) { result in
            switch result {
            case .success:
                user.markBackedUp()
                alertText = "备份好了。"
            case .failure(let error):
                alertText = "备份没有完成：\(error.localizedDescription)"
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
                if let restored = pendingRestore {
                    user.restore(restored)
                    session.refreshMarks()
                    alertText = "已恢复。"
                }
                pendingRestore = nil
            }
            Button("取消", role: .cancel) { pendingRestore = nil }
        } message: {
            Text(restoreSummary)
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

    private var restoreSummary: String {
        guard let r = pendingRestore else { return "" }
        return "备份里有：生词 \(r.star.count) 个，认识的词 \(r.known.count) 个，听读记录 \(r.daily.count) 天。"
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

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info?["CFBundleVersion"] as? String) ?? "?"
        return "\(version)（build \(build)）"
    }
}
