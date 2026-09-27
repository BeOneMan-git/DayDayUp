import UIKit
import XCTest

/// Helpers for the tap tests. The app runs on an iPad simulator with the original demo pack: the CI copies
/// ci/demo_pack.py's demo.ecopack into the Debug app, and DebugHooks imports it on the first launch.
/// XCUIApplication is main-actor bound (Xcode 16+), so the helpers are too.
@MainActor
enum TapUI {
    /// An article of the demo pack (ci/demo_pack.py).
    static let demoArticle = "Why cities plant trees"

    /// Launches the app turned to `orientation`. `arguments` are DebugHooks launch arguments.
    static func launch(_ arguments: [String] = [], orientation: UIDeviceOrientation = .landscapeLeft) -> XCUIApplication {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments += arguments
        app.launch()
        return app
    }

    static func window(_ app: XCUIApplication) -> CGRect {
        app.windows.firstMatch.frame
    }

    /// The page area right of the docked sidebar (the sidebar is narrower than a quarter of a landscape iPad).
    nonisolated static func contentArea(_ frame: CGRect, _ window: CGRect) -> Bool {
        frame.minX >= window.minX + window.width * 0.2
    }

    /// The docked sidebar on the left (landscape).
    nonisolated static func sidebarArea(_ frame: CGRect, _ window: CGRect) -> Bool {
        frame.maxX <= window.minX + window.width * 0.4 && frame.minY > window.minY + 30
    }

    /// The floating tab bar at the top (portrait, or the sidebar collapsed).
    nonisolated static func tabBarArea(_ frame: CGRect, _ window: CGRect) -> Bool {
        frame.minY < window.minY + 140 && frame.midX > window.minX + window.width * 0.15
    }

    /// First hittable element whose label is `text` (or starts with it, when `prefix`) inside `area`,
    /// preferring list cells, then buttons, then texts. SwiftUI joins a row's texts into one label with ", ".
    static func find(_ app: XCUIApplication, _ text: String, prefix: Bool = false, timeout: TimeInterval = 10,
                     in area: (CGRect, CGRect) -> Bool) -> XCUIElement? {
        let predicate = prefix
            ? NSPredicate(format: "label BEGINSWITH %@", text)
            : NSPredicate(format: "label == %@ OR label BEGINSWITH %@", text, text + ",")
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let frame = window(app)
            for query in [app.cells, app.buttons, app.staticTexts, app.otherElements] {
                for element in query.matching(predicate).allElementsBoundByIndex
                where element.exists && element.isHittable && area(element.frame, frame) {
                    return element
                }
            }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        return nil
    }

    static func sidebarRow(_ app: XCUIApplication, _ title: String) -> XCUIElement? {
        find(app, title, in: sidebarArea)
    }

    static func tabBarItem(_ app: XCUIApplication, _ title: String) -> XCUIElement? {
        find(app, title, in: tabBarArea)
    }

    /// Elements that show a tab's page is open: its navigation bar, plus a piece of content only it has.
    static func page(_ app: XCUIApplication, _ title: String) -> [XCUIElement] {
        var marks = [app.navigationBars[title]]
        switch title {
        case "今日": marks.append(app.staticTexts["今日计划"])
        case "书架": marks.append(app.buttons["按刊期"])
        case "词汇": marks.append(app.buttons["听词"])
        default: break
        }
        return marks
    }

    /// The reader of the demo article.
    static func reader(_ app: XCUIApplication) -> [XCUIElement] {
        [app.navigationBars[demoArticle], app.buttons["单词卡"], app.buttons["收起单词卡"]]
    }

    /// Waits until any of the elements exists.
    static func waitForAny(_ elements: [XCUIElement], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if elements.contains(where: { $0.exists }) { return true }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return false
    }

    /// Keeps a screenshot in the test results (the CI exports them into ui-tests.zip).
    static func keepScreenshot(_ app: XCUIApplication, _ name: String, in test: XCTestCase) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        test.add(shot)
    }

    /// One line on what is on screen, for failure messages (the CI turns them into annotations).
    static func summary(_ app: XCUIApplication, limit: Int = 30) -> String {
        var parts = ["window \(Int(window(app).width))x\(Int(window(app).height))"]
        parts += app.navigationBars.allElementsBoundByIndex.map { "nav[\($0.identifier)]" }
        for (kind, query) in [("cell", app.cells), ("button", app.buttons)] {
            for element in query.allElementsBoundByIndex.prefix(limit) where element.exists {
                let f = element.frame
                let seen = element.isHittable ? "" : " hidden"
                parts.append("\(kind)[\(element.label)] \(Int(f.minX)),\(Int(f.minY))\(seen)")
            }
        }
        return parts.joined(separator: " | ")
    }
}
