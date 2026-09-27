import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Counts taps as practice time (MET-01, ACC-30) without taking part in touch handling.
///
/// Up to 1.0.0 the root TabView carried `.simultaneousGesture(TapGesture())` for this. A tap gesture that
/// recognizes makes UIKit cancel the touch for the UIKit views under it, so everything UIKit selects when the
/// finger lifts stopped responding: the iPad sidebar (docked in landscape) and every List / Form row with a
/// NavigationLink (书架 articles, 雅思 prompts, 词汇 entries, 设置 pages). Buttons and segmented controls kept
/// working, which hid the cause (test report 2026-09-27: F02, F07, F12, F14, F16).
///
/// The recognizer below sits on the window and only watches. It never recognizes, so it never cancels, delays
/// or blocks a touch; it fails as soon as a touch sequence is not a plain one-finger tap. Taps in sheets,
/// popovers and menus are not counted, as before (the old gesture did not reach them either).
struct TouchActivityObserver: UIViewRepresentable {
    var onTap: () -> Void

    func makeUIView(context: Context) -> InstallerView {
        let view = InstallerView(frame: .zero)
        view.onTap = onTap
        return view
    }

    func updateUIView(_ view: InstallerView, context: Context) {
        view.onTap = onTap
    }

    /// An empty, non-interactive view whose only job is to put the recognizer on its window.
    final class InstallerView: UIView {
        var onTap: (() -> Void)?
        private let recognizer = PassiveTapRecognizer(target: nil, action: nil)
        private weak var host: UIWindow?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.onTap = { [weak self] in self?.onTap?() }
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard host !== window else { return }
            host?.removeGestureRecognizer(recognizer)
            host = window
            window?.addGestureRecognizer(recognizer)
        }
    }
}

/// Watches every touch sequence that starts in its window and reports a one-finger tap: lifted within 10 pt
/// of where it went down, on the window's own content. It only ever leaves `.possible` to fail.
final class PassiveTapRecognizer: UIGestureRecognizer {
    var onTap: (() -> Void)?
    private var start: CGPoint?
    private static let slop: CGFloat = 10

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard start == nil, touches.count == 1, let touch = touches.first, isOnMainContent(touch) else {
            state = .failed
            return
        }
        start = touch.location(in: view)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let start, let touch = touches.first else { return }
        let point = touch.location(in: view)
        if hypot(point.x - start.x, point.y - start.y) > Self.slop {
            state = .failed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        if start != nil {
            onTap?()
        }
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        state = .failed
    }

    override func reset() {
        super.reset()
        start = nil
    }

    /// The window's root view (the tabs and their pages), not a sheet or popover presented over it.
    private func isOnMainContent(_ touch: UITouch) -> Bool {
        guard let root = (view as? UIWindow)?.rootViewController?.view, let hit = touch.view else { return false }
        return hit.isDescendant(of: root)
    }
}
