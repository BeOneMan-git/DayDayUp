#if DEBUG
import SwiftUI
import UIKit

/// Launch arguments for the iPad simulator smoke test in CI (ci/sim_screens.sh) and browser demo.
/// Debug builds only:
/// the release and test builds that go onto the iPad never contain this file's code.
///   -DDUImportInbox 1          import every .ecopack waiting in Documents, without the preview
///   -DDUTab <name>             today / library / shadow / ielts / vocab / progress / settings
///   -DDUOpenArticle <issue/id> open that article in 书架
///   -DDUOrientation <o>        landscape / portrait
///   -DDULegacyRootTap 1        put back 1.0.0's root tap gesture (UI test LegacyRootTapDiagnosis only)
@MainActor
enum DebugHooks {
    static func value(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-" + name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func run(packs: PackStore, router: Router) async {
        if let o = value("DDUOrientation") {
            rotate(o)
        }
        // The browser simulator starts with fresh app data. Seed its bundled, original demo
        // content on first launch so the reader and library can be tested without file sharing.
        if value("DDUImportInbox") != "1", packs.packs.isEmpty,
           let demo = Bundle.main.url(forResource: "demo", withExtension: "ecopack") {
            let message = await packs.importPack(from: demo)
            DiagLog.shared.log("debug", "bundled demo: \(message)")
        }
        if value("DDUImportInbox") == "1" {
            let fm = FileManager.default
            let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let files = (try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? []
            for url in files where url.pathExtension.lowercased() == "ecopack" {
                let message = await packs.importPack(from: url, moveAfterImport: true)
                DiagLog.shared.log("debug", "import \(url.lastPathComponent): \(message)")
            }
        }
        if let name = value("DDUTab"), let tab = tab(name) {
            router.tab = tab
        }
        if let key = value("DDUOpenArticle"), let ref = ArticleRef(key: key) {
            router.openArticle(ref)
        }
    }

    static func tab(_ name: String) -> AppTab? {
        switch name {
        case "today": return .today
        case "library": return .library
        case "shadow": return .shadow
        case "ielts": return .ielts
        case "vocab": return .vocab
        case "progress": return .progress
        case "settings": return .settings
        default: return nil
        }
    }

    static func rotate(_ orientation: String) {
        let mask: UIInterfaceOrientationMask = orientation == "landscape" ? .landscapeRight : .portrait
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                DiagLog.shared.log("debug", "rotate \(orientation) failed: \(error.localizedDescription)")
            }
        }
    }
}

/// With `-DDULegacyRootTap 1`, the root view gets back the tap gesture that 1.0.0 used for practice time.
/// The UI test LegacyRootTapDiagnosis runs with it to show what that gesture broke (the sidebar and the
/// List/Form rows stop responding), next to NavigationTapTests that run without it. Debug builds only.
struct LegacyRootTapDiagnosis: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if DebugHooks.value("DDULegacyRootTap") == "1" {
            content.simultaneousGesture(TapGesture().onEnded { ActivityClock.shared.touch() })
        } else {
            content
        }
    }
}
#endif
