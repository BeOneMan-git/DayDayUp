import Foundation
import Observation

enum AppTab: Hashable {
    case today, library, shadow, vocab, progress, settings
}

/// Tab selection and the library's navigation path, shared so any page can open an article.
@MainActor
@Observable
final class Router {
    var tab: AppTab = .library
    var libraryPath: [ArticleRef] = []

    func openArticle(_ ref: ArticleRef) {
        tab = .library
        libraryPath = [ref]
    }
}
