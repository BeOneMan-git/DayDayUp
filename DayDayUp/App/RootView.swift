import SwiftUI

/// Six learning entries plus 设置. The tab bar turns into a sidebar with one tap
/// (sidebarAdaptable), as Apple's HIG suggests for iPad.
struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(PackStore.self) private var packs
    @Environment(UserStore.self) private var user
    @Environment(VocabStore.self) private var vocab
    @Environment(ReadingSession.self) private var session

    var body: some View {
        TabView(selection: Bindable(router).tab) {
            Tab("今日", systemImage: "sun.max", value: AppTab.today) {
                NavigationStack { TodayView() }
            }
            Tab("书架", systemImage: "books.vertical", value: AppTab.library) {
                NavigationStack(path: Bindable(router).libraryPath) {
                    LibraryView()
                        .navigationDestination(for: ArticleRef.self) { ref in
                            ReaderView(ref: ref)
                        }
                }
            }
            Tab("跟读", systemImage: "waveform", value: AppTab.shadow) {
                NavigationStack { ShadowView() }
            }
            Tab("雅思", systemImage: "text.bubble", value: AppTab.ielts) {
                NavigationStack { IELTSView() }
            }
            Tab("词汇", systemImage: "character.book.closed", value: AppTab.vocab) {
                NavigationStack { VocabView() }
            }
            Tab("进度", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.progress) {
                NavigationStack { ComingSoonView(feature: .progress) }
            }
            Tab("设置", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack { SettingsView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .simultaneousGesture(TapGesture().onEnded { ActivityClock.shared.touch() })
        .onChange(of: router.tab, initial: true) { _, tab in
            ActivityClock.shared.currentCategory = RootView.category(for: tab)
        }
        .task(id: packs.lexiconReady) {
            // V0.2 生词本 → V0.3 vocabulary items, once, after the lexicon is loaded.
            guard packs.lexiconReady else { return }
            vocab.migrateFromV02IfNeeded(user: user, packs: packs)
            session.refreshUserMarks()
        }
    }

    /// Practice pages count taps as practice time; 今日, 进度 and 设置 do not.
    static func category(for tab: AppTab) -> StudyCategory? {
        switch tab {
        case .library: return .read
        case .shadow: return .shadow
        case .vocab: return .vocab
        case .ielts: return .output
        case .today, .progress, .settings: return nil
        }
    }
}
