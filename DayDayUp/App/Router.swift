import Foundation
import Observation
import UIKit

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
    var tab: AppTab = .today
    var libraryPath: [ArticleRef] = []
    var shadowTarget: ShadowTarget?
    private(set) var shadowRequestID = 0
    /// 今日 asked the 词汇 tab to show its 复习 page (V0.5).
    private(set) var vocabReviewPending = false
    private(set) var vocabReviewRequestID = 0

    /// 专注模式 in the reader (SYS-P01): only the text and the player stay. Kept for this run of the app only.
    var readerFocus = false
    /// The learner closed the reader's side panel in a wide window. It then stays closed by default until they
    /// open it again (this run of the app only).
    var inspectorClosedByLearner = false
    /// A text field or text view is being edited somewhere in the app (PLAT-09, ACC-24). While it is,
    /// single-key shortcuts (space, arrows, L) are off, so typing never starts playback or recording.
    private(set) var isEditingText = false

    @ObservationIgnored private var editingObjects: Set<ObjectIdentifier> = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        let names: [(Notification.Name, Bool)] = [
            (UITextField.textDidBeginEditingNotification, true),
            (UITextField.textDidEndEditingNotification, false),
            (UITextView.textDidBeginEditingNotification, true),
            (UITextView.textDidEndEditingNotification, false),
        ]
        for (name, begins) in names {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil,
                                                               queue: .main) { [weak self] note in
                let id: ObjectIdentifier? = note.object.map { ObjectIdentifier($0 as AnyObject) }
                MainActor.assumeIsolated {
                    self?.textEditing(id, begins: begins)
                }
            }
            observers.append(token)
        }
    }

    private func textEditing(_ id: ObjectIdentifier?, begins: Bool) {
        guard let id else { return }
        if begins {
            editingObjects.insert(id)
        } else {
            editingObjects.remove(id)
        }
        let editing = !editingObjects.isEmpty
        if editing != isEditingText { isEditingText = editing }
    }

    func openArticle(_ ref: ArticleRef) {
        tab = .library
        libraryPath = [ref]
    }

    func openShadow(_ ref: ArticleRef, sid: Int?) {
        shadowTarget = ShadowTarget(ref: ref, sid: sid)
        shadowRequestID += 1
        tab = .shadow
    }

    /// Opens 词汇 on its 复习 page.
    func openVocabReview() {
        vocabReviewPending = true
        vocabReviewRequestID += 1
        tab = .vocab
    }

    /// True once after `openVocabReview()`; the 词汇 page then switches to 复习.
    func takeVocabReviewRequest() -> Bool {
        guard vocabReviewPending else { return false }
        vocabReviewPending = false
        return true
    }
}
