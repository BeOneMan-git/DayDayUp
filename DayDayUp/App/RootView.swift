import SwiftUI
import UIKit

/// Six learning entries plus 设置. The tab bar turns into a sidebar with one tap
/// (sidebarAdaptable), as Apple's HIG suggests for iPad. The reader's 专注模式 hides the tab bar from inside
/// the reader (ReaderView), so every other page keeps its navigation.
struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(PackStore.self) private var packs
    @Environment(UserStore.self) private var user
    @Environment(VocabStore.self) private var vocab
    @Environment(ReadingSession.self) private var session
    @Environment(RecorderService.self) private var recorder

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
                NavigationStack { StudyProgressPage() }
            }
            Tab("设置", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack { SettingsView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .background {
            ActivityTouchRecorder()
                .allowsHitTesting(false)
        }
        .onChange(of: router.tab, initial: true) { _, tab in
            ActivityClock.shared.currentCategory = RootView.category(for: tab)
        }
        .onChange(of: recorder.isRecording) { _, recording in
            // PLAT-08: the recording state is perceivable without looking (VoiceOver speaks it).
            RootView.announce(recording ? "开始录音" : "录音已停止")
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

    /// Spoken by VoiceOver when it is on; nothing happens otherwise.
    static func announce(_ text: String) {
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}

/// Counts a tap toward practice time without taking the click away from lists or buttons.
/// A SwiftUI tap gesture on the tab view swallowed those clicks. This recognizer sits on the window,
/// does not cancel or delay the touch, and is the same in Debug and Release.
private struct ActivityTouchRecorder: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        context.coordinator.attach(from: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.attach(from: uiView)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private static let gestureName = "daydayup.activity"

        func attach(from view: UIView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                self.install(on: view)
            }
        }

        private func install(on view: UIView) {
            guard let window = view.window else { return }
            if window.gestureRecognizers?.contains(where: { $0.name == Self.gestureName }) == true { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            tap.name = Self.gestureName
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc func tapped() {
            Task { @MainActor in
                ActivityClock.shared.touch()
            }
        }
    }
}
