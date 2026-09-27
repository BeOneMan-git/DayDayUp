import XCTest

/// Taps that must lead somewhere, on an iPad in landscape (how the app is used). They cover the entries that
/// stopped responding in 1.0.0 (test report 2026-09-27): the sidebar (F02), a 书架 article (F07), a 雅思 prompt
/// (F12) and a 设置 page (F16); the top tab bar in portrait (F03) must keep working too.
/// Each test starts on its own tab through DebugHooks (-DDUTab), so a dead sidebar cannot hide a dead row.
final class NavigationTapTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testSidebarOpensEveryTab() {
        let app = TapUI.launch()
        XCTAssertTrue(TapUI.waitForAny(TapUI.page(app, "今日"), timeout: 30), "今日 did not appear. \(TapUI.summary(app))")
        let window = TapUI.window(app)
        XCTAssertGreaterThan(window.width, window.height, "not landscape. \(TapUI.summary(app))")
        TapUI.keepScreenshot(app, "landscape-today-sidebar", in: self)
        for title in ["书架", "跟读", "雅思", "词汇", "进度", "设置", "今日"] {
            guard let row = TapUI.sidebarRow(app, title) else {
                return XCTFail("no sidebar row \(title). \(TapUI.summary(app))")
            }
            row.tap()
            XCTAssertTrue(TapUI.waitForAny(TapUI.page(app, title), timeout: 6),
                          "sidebar \(title): the page did not open. \(TapUI.summary(app))")
        }
        TapUI.keepScreenshot(app, "landscape-sidebar-after-7-taps", in: self)
    }

    @MainActor
    func testLibraryArticleOpensReader() {
        let app = TapUI.launch(["-DDUTab", "library"])
        guard let row = TapUI.find(app, TapUI.demoArticle, prefix: true, timeout: 30, in: TapUI.contentArea) else {
            return XCTFail("no article row in 书架. \(TapUI.summary(app))")
        }
        row.tap()
        XCTAssertTrue(TapUI.waitForAny(TapUI.reader(app), timeout: 8),
                      "书架 article: the reader did not open. \(TapUI.summary(app))")
        TapUI.keepScreenshot(app, "landscape-reader-from-library", in: self)
    }

    @MainActor
    func testIELTSPromptOpensPractice() {
        let app = TapUI.launch(["-DDUTab", "ielts"])
        guard let row = TapUI.find(app, "How often do you use your phone", prefix: true, timeout: 20,
                                   in: TapUI.contentArea) else {
            return XCTFail("no speaking prompt in 雅思. \(TapUI.summary(app))")
        }
        row.tap()
        XCTAssertTrue(TapUI.waitForAny([app.navigationBars["基础口语"]], timeout: 8),
                      "雅思 prompt: the practice page did not open. \(TapUI.summary(app))")
        TapUI.keepScreenshot(app, "landscape-ielts-prompt", in: self)
    }

    @MainActor
    func testSettingsRowOpensPage() {
        let app = TapUI.launch(["-DDUTab", "settings"])
        guard let row = TapUI.find(app, "学习计划与提醒", prefix: true, timeout: 20, in: TapUI.contentArea) else {
            return XCTFail("no 学习计划与提醒 row in 设置. \(TapUI.summary(app))")
        }
        row.tap()
        XCTAssertTrue(TapUI.waitForAny([app.navigationBars["学习计划与提醒"]], timeout: 8),
                      "设置 row: the page did not open. \(TapUI.summary(app))")
        TapUI.keepScreenshot(app, "landscape-settings-row", in: self)
    }

    @MainActor
    func testTopTabBarInPortrait() {
        let app = TapUI.launch(orientation: .portrait)
        XCTAssertTrue(TapUI.waitForAny(TapUI.page(app, "今日"), timeout: 30), "今日 did not appear. \(TapUI.summary(app))")
        let window = TapUI.window(app)
        XCTAssertLessThan(window.width, window.height, "not portrait. \(TapUI.summary(app))")
        for title in ["书架", "设置", "今日"] {
            guard let item = TapUI.tabBarItem(app, title) else {
                return XCTFail("no tab bar item \(title). \(TapUI.summary(app))")
            }
            item.tap()
            XCTAssertTrue(TapUI.waitForAny(TapUI.page(app, title), timeout: 6),
                          "tab bar \(title): the page did not open. \(TapUI.summary(app))")
        }
        TapUI.keepScreenshot(app, "portrait-tab-bar", in: self)
    }
}
