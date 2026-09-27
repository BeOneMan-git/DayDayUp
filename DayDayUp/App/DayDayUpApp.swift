import SwiftUI

@main
struct DayDayUpApp: App {
    @State private var packs: PackStore
    @State private var user: UserStore
    @State private var practice: PracticeStore
    @State private var vocab: VocabStore
    @State private var annotations: AnnotationStore
    @State private var study: StudyStore
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
        let study = StudyStore()
        let practice = PracticeStore()
        _packs = State(initialValue: packs)
        _user = State(initialValue: user)
        _practice = State(initialValue: practice)
        _vocab = State(initialValue: vocab)
        _annotations = State(initialValue: AnnotationStore())
        session.onOpened = { [weak study] ref in study?.noteOpened(ref) }
        session.onFinished = { [weak study] ref in study?.noteFinished(ref) }
        // IEL-F04: feedback or a rewrite schedules a new-prompt retest 3–7 days later.
        practice.onImproved = { [weak study] kind, id in study?.scheduleRetest(kind: kind, sourceId: id) }
        // A retest started from 今日 is completed by the next new work of the same kind.
        practice.onNewWork = { [weak study, weak practice] kind, id in
            guard let study, let practice, let rid = study.activeRetest, let r = study.retest(rid), r.kind == kind else { return }
            study.activeRetest = nil
            study.completeRetest(rid, resultId: id)
            if kind == "speaking" {
                practice.updateSpeaking(id) { $0.retestOf = r.sourceId }
            } else {
                practice.updateWriting(id) { $0.retestOf = r.sourceId }
            }
        }
        _study = State(initialValue: study)
        _engine = State(initialValue: engine)
        _session = State(initialValue: session)
        _recorder = State(initialValue: recorder)
        _router = State(initialValue: Router())
        DiagLog.shared.log("app", "launch \(BackupArchive.appVersionText()) \(AppFlavor.bundleId) packs=\(packs.packs.count)")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(packs)
                .environment(user)
                .environment(practice)
                .environment(vocab)
                .environment(annotations)
                .environment(study)
                .environment(engine)
                .environment(session)
                .environment(recorder)
                .environment(router)
                .tint(Theme.accent)
                .appAppearance(user.settings.appearance)
                // A pack opened with the app leads to the import preview; nothing is installed without it.
                .packOpenURLImport(packs: packs) {
                    router.tab = .library
                }
                .task {
                    // Only finds waiting packs (the banner on 书架 and 设置 offers the preview).
                    await packs.scanInbox()
                    #if DEBUG
                    // CI simulator smoke test only (tools/sim_screens.sh); not in release or test builds.
                    await DebugHooks.run(packs: packs, router: router)
                    #endif
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background, .inactive:
                if phase == .background {
                    recorder.interrupt(reason: "app in background")
                    ActivityClock.shared.flush()
                    ActivityClock.shared.appActive = false
                }
                session.flushProgress()
                user.saveNow()
                practice.saveNow()
                vocab.saveNow()
                annotations.saveNow()
                study.saveNow()
            case .active:
                ActivityClock.shared.appActive = true
                ActivityClock.shared.flushBackground()
                recorder.refreshPermission()
                vocab.noteDayStart()
                Task { await packs.scanInbox() }
            @unknown default:
                break
            }
        }
    }
}
