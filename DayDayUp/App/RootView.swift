import SwiftUI

/// Six entries. The tab bar turns into a sidebar with one tap (sidebarAdaptable), as Apple's HIG suggests for iPad.
struct RootView: View {
    @Environment(Router.self) private var router

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
                NavigationStack { ComingSoonView(feature: .shadowing) }
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
    }
}
