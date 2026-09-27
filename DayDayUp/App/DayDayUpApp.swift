import SwiftUI

@main
struct DayDayUpApp: App {
    @State private var packs: PackStore
    @State private var user: UserStore
    @State private var engine: PlaybackEngine
    @State private var session: ReadingSession
    @State private var router: Router
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let packs = PackStore()
        let user = UserStore()
        let engine = PlaybackEngine()
        _packs = State(initialValue: packs)
        _user = State(initialValue: user)
        _engine = State(initialValue: engine)
        _session = State(initialValue: ReadingSession(engine: engine, packs: packs, user: user))
        _router = State(initialValue: Router())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(packs)
                .environment(user)
                .environment(engine)
                .environment(session)
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
                session.flushProgress()
                user.saveNow()
            case .active:
                Task { await packs.scanInbox() }
            @unknown default:
                break
            }
        }
    }
}
