import SwiftUI

/// "在 App 文件夹里发现 n 个内容包 → 查看并导入" (IMP-F04). Packs copied in with Finder, iTunes file sharing or
/// the Files app, and packs opened with the app, wait here; nothing is installed silently any more.
/// Tapping opens the same preview as 导入内容包. Renders nothing when no file waits.
struct InboxImportBanner: View {
    @Environment(PackStore.self) private var packs
    @State private var request: PackImportRequest?
    @State private var shownCount = 0
    @Environment(\.dynamicTypeSize) private var typeSize

    init() {}

    var body: some View {
        let files = packs.waitingFiles
        if files.isEmpty && request == nil {
            EmptyView()
        } else {
            // The row stays while its sheet is open, even when the files have been handled meanwhile.
            Button {
                open(files)
            } label: {
                bannerLabel(count: files.isEmpty ? shownCount : files.count)
            }
            .accessibilityIdentifier("inbox-import-banner")
            .accessibilityHint("打开导入预览，先看再决定")
            .sheet(item: $request, onDismiss: { rescan() }) { r in
                PackImportSheet(urls: r.urls) { _ in
                    packs.forgetOpened(r.urls)
                }
            }
        }
    }

    private func open(_ files: [URL]) {
        guard !files.isEmpty else { return }
        shownCount = files.count
        request = PackImportRequest(urls: files)
    }

    private func rescan() {
        Task { await packs.scanInbox() }
    }

    private func title(count n: Int) -> String {
        if packs.openedFiles.isEmpty {
            return "在 App 文件夹里发现 \(n) 个内容包"
        }
        if packs.pendingInbox.isEmpty {
            return "收到 \(n) 个内容包"
        }
        return "发现 \(n) 个内容包"
    }

    @ViewBuilder
    private func bannerLabel(count: Int) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                icon
                texts(count: count)
                action
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        } else {
            HStack(alignment: .center, spacing: 12) {
                icon
                texts(count: count)
                Spacer(minLength: 8)
                action
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
    }

    private var icon: some View {
        Image(systemName: "tray.and.arrow.down.fill")
            .font(.title2)
            .foregroundStyle(Theme.accent)
            .accessibilityHidden(true)
    }

    private func texts(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title(count: count))
                .font(.headline)
                .foregroundStyle(Color.primary)
            Text("先看是新增、已导入、冲突还是新版本，确认后才写入书架。")
                .font(.callout)
                .foregroundStyle(Color.secondary)
        }
    }

    private var action: some View {
        HStack(spacing: 4) {
            Text("查看并导入")
            Image(systemName: "chevron.right")
                .accessibilityHidden(true)
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(Theme.accent)
    }
}
