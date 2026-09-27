import Foundation
import Observation

enum AppTab: Hashable {
    case today, library, shadow, ielts, vocab, progress, settings
}

/// A sentence to open in 跟读 (from the reader's sentence panel).
struct ShadowTarget: Equatable {
    var ref: ArticleRef
    var sid: Int?
}

/// Tab selection and the library's navigation path, shared so any page can open an article.
@MainActor
@Observable
final class Router {
    var tab: AppTab = .library
    var libraryPath: [ArticleRef] = []
    var shadowTarget: ShadowTarget?
    private(set) var shadowRequestID = 0

    func openArticle(_ ref: ArticleRef) {
        tab = .library
        libraryPath = [ref]
    }

    func openShadow(_ ref: ArticleRef, sid: Int?) {
        shadowTarget = ShadowTarget(ref: ref, sid: sid)
        shadowRequestID += 1
        tab = .shadow
    }
}
