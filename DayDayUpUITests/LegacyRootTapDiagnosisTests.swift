import XCTest

/// A/B control for NavigationTapTests: the same taps with 1.0.0's root tap gesture put back
/// (`-DDULegacyRootTap 1`, Debug builds only). These tests pass when the taps lead NOWHERE, i.e. when that
/// one gesture reproduces the dead sidebar and rows of the 2026-09-27 test report. The CI runs them apart from
/// the gate and never fails a build on them.
final class LegacyRootTapDiagnosisTests: XCTestCase {
    private let legacy = ["-DDULegacyRootTap", "1"]

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testSidebarTapIsSwallowed() {
        let app = TapUI.launch(legacy)
        XCTAssertTrue(TapUI.waitForAny(TapUI.page(app, "今日"), timeout: 30), "今日 did not appear. \(TapUI.summary(app))")
        guard let row = TapUI.sidebarRow(app, "书架") else {
            return XCTFail("no sidebar row 书架. \(TapUI.summary(app))")
        }
        row.tap()
        XCTAssertFalse(TapUI.waitForAny(TapUI.page(app, "书架"), timeout: 5),
                       "with the old gesture the sidebar still opened 书架. \(TapUI.summary(app))")
        TapUI.keepScreenshot(app, "legacy-sidebar-tap", in: self)
    }

    @MainActor
    func testLibraryRowTapIsSwallowed() {
        let app = TapUI.launch(legacy + ["-DDUTab", "library"])
        guard let row = TapUI.find(app, TapUI.demoArticle, prefix: true, timeout: 30, in: TapUI.contentArea) else {
            return XCTFail("no article row in 书架. \(TapUI.summary(app))")
        }
        row.tap()
        XCTAssertFalse(TapUI.waitForAny(TapUI.reader(app), timeout: 5),
                       "with the old gesture the article still opened. \(TapUI.summary(app))")
        TapUI.keepScreenshot(app, "legacy-library-row-tap", in: self)
    }

    @MainActor
    func testSettingsRowTapIsSwallowed() {
        let app = TapUI.launch(legacy + ["-DDUTab", "settings"])
        guard let row = TapUI.find(app, "学习计划与提醒", prefix: true, timeout: 20, in: TapUI.contentArea) else {
            return XCTFail("no 学习计划与提醒 row in 设置. \(TapUI.summary(app))")
        }
        row.tap()
        XCTAssertFalse(TapUI.waitForAny([app.navigationBars["学习计划与提醒"]], timeout: 5),
                       "with the old gesture the settings page still opened. \(TapUI.summary(app))")
        TapUI.keepScreenshot(app, "legacy-settings-row-tap", in: self)
    }
}
