import SwiftUI

/// 词汇 (PAGE-05): five sub-pages — 复习 / 浏览 / 听词 / 拼写 / 词群.
/// Each sub-page scrolls on its own; this view only switches between them.
struct VocabView: View {
    enum Page: String, CaseIterable, Identifiable {
        case review, browse, listen, spell, chunks

        var id: String { rawValue }

        var title: String {
            switch self {
            case .review: return "复习"
            case .browse: return "浏览"
            case .listen: return "听词"
            case .spell: return "拼写"
            case .chunks: return "词群"
            }
        }
    }

    @Environment(VocabStore.self) private var vocab
    @Environment(PackStore.self) private var packs
    @Environment(Router.self) private var router
    @SceneStorage("vocab.page") private var pageRaw = Page.review.rawValue

    private var page: Binding<Page> {
        Binding(get: { Page(rawValue: pageRaw) ?? .review }, set: { pageRaw = $0.rawValue })
    }

    var body: some View {
        VStack(spacing: 0) {
            ChoicePicker("词汇子页", selection: page) {
                ForEach(Page.allCases) { p in
                    Text(p.title).tag(p)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: 720)
            if let error = vocab.saveError {
                Label("词汇记录保存失败：\(error)", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(Theme.warn)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
            Divider()
            Group {
                switch page.wrappedValue {
                case .review: VocabReviewView()
                case .browse: VocabBrowseView()
                case .listen: VocabListenView()
                case .spell: VocabSpellingView()
                case .chunks: VocabChunkLibraryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("词汇")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if !packs.lexiconReady && vocab.state.items.isEmpty {
                ProgressView("正在载入词库…")
            }
        }
        .onAppear { takeReviewRequest() }
        .onChange(of: router.vocabReviewRequestID) { _, _ in takeReviewRequest() }
    }

    /// 今日's 词汇 task opens this tab on 复习.
    private func takeReviewRequest() {
        if router.takeVocabReviewRequest() {
            pageRaw = Page.review.rawValue
        }
    }
}
