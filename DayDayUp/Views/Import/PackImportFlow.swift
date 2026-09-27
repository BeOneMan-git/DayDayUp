import SwiftUI
import UniformTypeIdentifiers

/// The files of one preview sheet.
struct PackImportRequest: Identifiable {
    let id = UUID()
    let urls: [URL]
}

extension View {
    /// 导入内容包 (IMP-F04): the system file picker for content packs, then the preview sheet
    /// (新增 / 已导入 / 冲突 / 新版本, sizes and free space), then the commit of what the learner confirmed.
    func packImportFlow(isPresented: Binding<Bool>) -> some View {
        modifier(PackImportFlowModifier(isPresented: isPresented))
    }

    /// Files opened with the app ("Open in", AirDrop, a tap on a pack in the Files app) lead to the same preview.
    /// Used at the top of the app, outside the views that get the stores from the environment,
    /// so the store is passed in and handed to the sheet.
    func packOpenURLImport(packs: PackStore, onImported: @escaping () -> Void) -> some View {
        modifier(PackOpenURLModifier(packs: packs, onImported: onImported))
    }
}

struct PackImportFlowModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(PackStore.self) private var packs
    @State private var request: PackImportRequest?

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: [.ecopack, .data],
                          allowsMultipleSelection: true) { result in
                picked(result)
            }
            .sheet(item: $request, onDismiss: { rescan() }) { r in
                PackImportSheet(urls: r.urls)
            }
    }

    private func picked(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        // Let the file picker finish closing before the preview sheet is presented.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            request = PackImportRequest(urls: urls)
        }
    }

    private func rescan() {
        Task { await packs.scanInbox() }
    }
}

struct PackOpenURLModifier: ViewModifier {
    let packs: PackStore
    let onImported: () -> Void
    @State private var request: PackImportRequest?

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                opened(url)
            }
            .sheet(item: $request, onDismiss: { rescan() }) { r in
                PackImportSheet(urls: r.urls) { installed in
                    closed(r.urls, installed: installed)
                }
                .environment(packs)
                .tint(Theme.accent)
            }
    }

    private func opened(_ url: URL) {
        guard url.isFileURL else { return }
        // The file also waits in the banner, in case the sheet cannot be shown right now.
        packs.noteOpened(url)
        if request == nil {
            request = PackImportRequest(urls: [url])
        }
    }

    private func closed(_ urls: [URL], installed: Bool) {
        packs.forgetOpened(urls)
        if installed { onImported() }
    }

    private func rescan() {
        Task { await packs.scanInbox() }
    }
}
