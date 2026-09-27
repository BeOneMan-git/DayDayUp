import SwiftUI

@main
struct DayDayUpApp: App {
    @State private var packs: PackStore
    @State private var user: UserStore
    @State private var practice: PracticeStore
    @State private var vocab: VocabStore
    @State private var annotations: AnnotationStore
    @State private var engine: PlaybackEngine
    @State private var session: ReadingSession
    @State private var recorder: RecorderService
    @State private var router: Router
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let packs = PackStore()
        let user = UserStore()
        let engine = PlaybackEngine()
        let recorder = RecorderService()
        let vocab = VocabStore()
        engine.blocksPlayback = { [weak recorder] in recorder?.isRecording ?? false }
        packs.onArticlesChanged = { [weak vocab] diffs in vocab?.applyDiffs(diffs) }
        let session = ReadingSession(engine: engine, packs: packs, user: user)
        session.vocabKeys = { [weak vocab] in vocab?.savedKeys ?? [] }
        _packs = State(initialValue: packs)
        _user = State(initialValue: user)
        _practice = State(initialValue: PracticeStore())
        _vocab = State(initialValue: vocab)
        _annotations = State(initialValue: AnnotationStore())
        _engine = State(initialValue: engine)
        _session = State(initialValue: session)
        _recorder = State(initialValue: recorder)
        _router = State(initialValue: Router())
        DiagLog.shared.log("app", "launch \(BackupArchive.appVersionText()) packs=\(packs.packs.count)")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(packs)
                .environment(user)
                .environment(practice)
                .environment(vocab)
                .environment(annotations)
                .environment(engine)
                .environment(session)
                .environment(recorder)
                .environment(router)
                .tint(Theme.accent)
                .onOpenURL { url in
                    guard url.isFileURL else { return }
                    Task {
                        _ = await packs.importPack(from: url)
                        router.tab = .library
                    }
                }
                .task {
                    await packs.scanInbox()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background, .inactive:
                if phase == .background {
                    recorder.interrupt(reason: "app in background")
                }
                session.flushProgress()
                user.saveNow()
                practice.saveNow()
                vocab.saveNow()
                annotations.saveNow()
            case .active:
                recorder.refreshPermission()
                vocab.noteDayStart()
                Task { await packs.scanInbox() }
            @unknown default:
                break
            }
        }
    }
}
