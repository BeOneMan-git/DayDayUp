import XCTest

/// Walks DayDayUp on the iPad simulator. Article titles come from the pack manifest at runtime.
/// Screens that show magazine body text are checked, then not written as screenshots.
/// A required screen that does not open fails the test (`continueAfterFailure` still runs the rest).
final class WalkUITests: XCTestCase {
    private var app = XCUIApplication()
    private var titles: [String] = []

    private let neverTap: Set<String> = [
        "录音", "录音跟读", "开始复述", "直接开始说", "看题并开始",
        "删除", "删除这个内容包", "继续",
    ]

    private var wantLandscape: Bool {
        let env = ProcessInfo.processInfo.environment
        let raw = env["WALK_ORIENTATION"] ?? env["TEST_RUNNER_WALK_ORIENTATION"] ?? "portrait"
        return raw == "landscape"
    }

    private var prefix: String { wantLandscape ? "land" : "port" }
    private var orientationName: String { wantLandscape ? "横屏" : "竖屏" }

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_Hans_CN"]
        titles = Self.articleTitles()
        addUIInterruptionMonitor(withDescription: "系统弹窗") { alert in
            for label in ["允许", "Allow", "好", "OK", "关闭", "以后再说", "Not Now"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: Tests

    func test01DocumentsImport() {
        launch()
        let banner = app.descendants(matching: .any)["inbox-import-banner"]
        let sawBanner = banner.waitForExistence(timeout: 20)
        require(sawBanner, "import-banner", sawBanner ? "" : "书架上没有“查看并导入”。文稿里的内容包没有被认出来。",
                area: "导入", title: "待导入提示", did: "打开书架，找文稿里的导入提示。")
        guard sawBanner else { writePack(documentsImport: false); return }

        press(banner)
        let sheet = waitForImportSheet(timeout: 8)
        require(sheet, "import-review", sheet ? "" : "点了“查看并导入”，没有出现导入预览。工具栏上的“导入内容包”不算预览。",
                area: "导入", title: "导入预览", did: "点导入提示，等预览的导航标题。")
        guard sheet else { writePack(documentsImport: false); return }

        let commit = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "导入所选")).firstMatch
        let appeared = commit.waitForExistence(timeout: 45)
        var enabled = false
        if appeared {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: commit)
            enabled = XCTWaiter().wait(for: [ready], timeout: 20) == .completed
        }
        let canCommit = appeared && enabled
        require(canCommit, "import-commit", canCommit ? "" : "预览里没有可点的“导入所选”。",
                area: "导入", title: "导入所选", did: "等文件核对结束，再点确认。")
        guard canCommit else { writePack(documentsImport: false); return }
        commit.tap()

        let done = app.buttons["完成"].waitForExistence(timeout: 60)
        require(done, "import-done", done ? "" : "点了“导入所选”之后没有出现“完成”。",
                area: "导入", title: "导入结果", did: "确认导入，等写入结束。")
        if done { app.buttons["完成"].tap() }

        let onShelf = titles.contains { waitToSee($0, timeout: 8) }
        require(onShelf, "import-shelf", onShelf ? "" : "导入结束后书架上没有清单里的文章。",
                area: "导入", title: "书架", did: "关掉结果后看书架上有没有文章。")
        writePack(documentsImport: onShelf)
        XCTAssertTrue(onShelf)
    }

    func test02TodayAndBaseline() {
        launch()
        guard openTab("今日") else {
            require(false, "today", "没有打开“今日”。", area: "今日", title: "今日", did: "点“今日”。")
            return
        }
        require(app.navigationBars["今日"].exists, "today", "", area: "今日", title: "今日", did: "打开“今日”。")

        let baseline = tapButton("开始", nearest: "建立基线") && waitForTitle("建立基线", timeout: 6)
        require(baseline, "baseline", baseline ? "" : "没有进入“建立基线”。", area: "基线", title: "建立基线",
                did: "点今日里“建立基线”的“开始”。")
        if baseline {
            walkBaseline()
            leaveToTab("今日")
        }

        let plan = (tapText("计划设置") || openRow("计划设置", expect: "学习计划与提醒"))
            && waitForTitle("学习计划与提醒", timeout: 5)
        require(plan, "today-plan", plan ? "" : "没有进入“学习计划与提醒”。", area: "今日", title: "学习计划与提醒",
                did: "点“计划设置”。")
    }

    func test03ReaderNoBodyShot() {
        launch()
        guard let title = titles.first else {
            require(false, "reader", "内容包清单里没有文章，不能核听读。", area: "听读", title: "听读正文",
                    did: "读清单。", body: true)
            return
        }
        guard openTab("书架") else {
            require(false, "reader", "没有打开书架。", area: "听读", title: "听读正文", did: "点“书架”。", body: true)
            return
        }
        let opened = openRow(title, expect: title) || waitForTitle(title, timeout: 4)
        require(opened, "reader", opened ? "" : "没有进入听读正文。", area: "听读", title: "听读正文",
                did: "从书架打开清单里的第一篇。不保存正文截图。", body: true)
        guard opened else { return }

        let played = tapControl("播放") && waitToSeeButton("暂停", timeout: 4)
        if played { _ = tapControl("暂停") }
        require(played, "reader-play", played ? "" : "点了播放，按钮没有变成“暂停”。", area: "听读", title: "朗读",
                did: "点播放，再暂停。不保存这一屏。", body: true)

        let showed = tapControl("显示中文翻译") && waitToSeeButton("隐藏中文翻译", timeout: 4)
        require(showed, "reader-zh", showed ? "" : "没有点到“显示中文翻译”，或按钮没有变成“隐藏中文翻译”。",
                area: "听读", title: "中文翻译", did: "点显示中文翻译。不保存译文截图。", body: true)

        let quiz = tapControl("理解题") && app.navigationBars["理解题"].waitForExistence(timeout: 8)
        if quiz { _ = tapButtonExact("关闭", timeout: 3) }
        require(quiz, "reader-quiz", quiz ? "" : "没有打开“理解题”。", area: "听读", title: "理解题",
                did: "点理解题后关闭。不保存题目截图。", body: true)
    }

    func test04Shadow() {
        launch()
        guard let title = titles.first else {
            require(false, "shadow", "内容包清单里没有文章，不能核跟读。", area: "跟读", title: "跟读",
                    did: "读清单。", body: true)
            return
        }
        guard openTab("跟读") else {
            require(false, "shadow", "没有打开“跟读”。", area: "跟读", title: "跟读", did: "点“跟读”。", body: true)
            return
        }
        if !sees("练习模式") {
            _ = reveal(title)
            tapRow(title)
            _ = waitToSee("练习模式", timeout: 6)
        }
        let opened = sees("练习模式")
        require(opened, "shadow", opened ? "" : "跟读里没有出现“练习模式”。", area: "跟读", title: "跟读工作台",
                did: "打开一篇文章的跟读。不保存句子截图。", body: true)
        guard opened else { return }

        for mode in ["听后模仿", "影子跟读", "独立朗读", "脱稿复述"] {
            if mode != "听后模仿" { _ = tapSegment(mode) }
            let shown = waitToSee(mode, timeout: 3)
            require(shown, "shadow-\(modeSlug(mode))", shown ? "" : "没有切到“\(mode)”。",
                    area: "跟读", title: mode, did: "切换练习模式。没有点录音。不保存句子截图。", body: true)
        }
    }

    func test05IELTS() {
        launch()
        guard openTab("雅思") else {
            require(false, "ielts", "没有打开“雅思”。", area: "雅思", title: "雅思", did: "点“雅思”。")
            return
        }
        _ = tapSegment("口语")
        _ = tapSegment("基础训练")
        require(sees("基础训练"), "ielts-speaking-basic", sees("How often do you use your phone") ? "" : "口语基础列表里没有预期的题目。",
                area: "雅思", title: "口语基础", did: "打开口语基础列表。")
        openSession(row: "How often do you use your phone", title: "基础口语", id: "ielts-speaking-session")

        _ = tapSegment("考试题型")
        require(sees("口语完整模拟"), "ielts-speaking-exam", sees("口语完整模拟") ? "" : "没有看到口语考试题型。",
                area: "雅思", title: "口语考试题型", did: "切到考试题型。")
        openSession(row: "口语完整模拟", title: "口语完整模拟", id: "ielts-mock")
        openSession(row: "Describe a practical skill", title: "口语 Part 2", id: "ielts-part2")

        _ = tapSegment("写作")
        _ = tapSegment("基础训练")
        require(sees("Some people say smartphones"), "ielts-writing-basic",
                sees("Some people say smartphones") ? "" : "写作基础列表里没有预期的题目。",
                area: "雅思", title: "写作基础", did: "打开写作基础列表。")
        openSession(row: "Some people say smartphones", title: "基础写作", id: "ielts-writing-session")

        _ = tapSegment("考试题型")
        _ = reveal("Average daily bike rentals")
        require(sees("Average daily bike rentals"), "ielts-writing-exam",
                sees("Average daily bike rentals") ? "" : "没有看到写作考试题型。",
                area: "雅思", title: "写作考试题型", did: "切到写作考试题型。")
        openSession(row: "Average daily bike rentals", title: "写作 Task 1", id: "ielts-task1")
        openSession(row: "In many places, people can now pay", title: "写作 Task 2", id: "ielts-task2")
    }

    func test06VocabAndProgress() {
        launch()
        guard openTab("词汇") else {
            require(false, "vocab-review", "没有打开“词汇”。", area: "词汇", title: "词汇", did: "点“词汇”。")
            return
        }
        let pages = [("复习", "review"), ("浏览", "browse"), ("听词", "listen"), ("拼写", "spell"), ("词群", "chunks")]
        for (title, slug) in pages {
            _ = tapSegment(title)
            let marker = app.descendants(matching: .any)["vocab-page-\(slug)"]
            let shown = marker.waitForExistence(timeout: 4)
            require(shown, "vocab-\(slug)", shown ? "" : "切到“\(title)”后没有出现对应页面。",
                    area: "词汇", title: "词汇 · \(title)", did: "点词汇子页“\(title)”，核对页面标识。")
        }

        guard openTab("进度") else {
            require(false, "progress-7", "没有打开“进度”。", area: "进度", title: "进度", did: "点“进度”。")
            return
        }
        let sevenButton = app.buttons["最近 7 天"]
        let seven = app.descendants(matching: .any)["progress-window-7"].waitForExistence(timeout: 4)
            || (sevenButton.exists && sevenButton.isSelected)
        require(seven, "progress-7", seven ? "" : "进度页没有停在最近 7 天。",
                area: "进度", title: "最近 7 天", did: "打开进度，核对默认窗口。")
        let tapped = tapButtonExact("最近 30 天", timeout: 3)
        let thirty = tapped && app.descendants(matching: .any)["progress-window-30"].waitForExistence(timeout: 4)
        require(thirty, "progress-30", thirty ? "" : "点了“最近 30 天”，窗口没有切过去。",
                area: "进度", title: "最近 30 天", did: "点“最近 30 天”，核对页面标识。")
    }

    func test07Settings() {
        launch()
        guard openTab("设置") else {
            require(false, "settings", "没有打开“设置”。", area: "设置", title: "设置", did: "点“设置”。")
            return
        }
        require(app.navigationBars["设置"].exists, "settings", "", area: "设置", title: "设置", did: "打开“设置”。")

        let links: [(String, String, String)] = [
            ("学习计划与提醒", "settings-plan", "学习计划与提醒"),
            ("词汇复习", "settings-vocab", "词汇设置"),
            ("阅读字号与标注", "settings-type", "阅读字号与标注"),
            ("声音与速度", "settings-audio", "声音与速度"),
            ("资源清单", "settings-resources", "资源清单"),
            ("能力清单", "settings-capability", "能力清单"),
            ("导出的文件里有什么", "settings-privacy", "隐私"),
            ("录音占用与清理", "settings-recordings", "录音占用与清理"),
            ("使用说明", "settings-guide", "使用说明"),
        ]
        for (label, id, title) in links {
            openSettings(label: label, id: id, title: title)
        }
        if currentTitle() == "使用说明" || openSettingsLink("使用说明", expect: "使用说明") {
            let topic = openRow("每天怎么用", expect: "每天怎么用")
            require(topic, "settings-guide-topic", topic ? "" : "没有打开“每天怎么用”。",
                    area: "设置", title: "每天怎么用", did: "在使用说明里点“每天怎么用”。")
            leaveToTab("设置")
        }

        _ = reveal("立即完整备份")
        let backup = tapButtonExact("立即完整备份", timeout: 3) && waitForTitle("完整备份", timeout: 6)
        require(backup, "settings-backup", backup ? "" : "没有打开“完整备份”。",
                area: "设置", title: "完整备份", did: "点“立即完整备份”。没有点“继续”。")
        if backup { _ = tapButtonExact("取消", timeout: 3) }
        leaveToTab("设置")

        _ = reveal("从备份恢复")
        let restore = tapButtonExact("从备份恢复", timeout: 3) && waitForTitle("从备份恢复", timeout: 6)
        require(restore, "settings-restore", restore ? "" : "没有打开“从备份恢复”。",
                area: "设置", title: "从备份恢复", did: "点“从备份恢复”。没有选择文件。")
        if restore { _ = tapButtonExact("关闭", timeout: 3) }
    }

    // MARK: Baseline

    private func walkBaseline() {
        _ = reveal("短听读")
        let note = sees("短听读")
        require(note, "baseline-listening-note", note ? "" : "基线页上没有“短听读”。",
                area: "基线", title: "短听读说明", did: "滚到短听读。", body: true)
        if tapButton("开始", nearest: "短听读") {
            let quiz = app.navigationBars["基线：短听读"].waitForExistence(timeout: 8)
            require(quiz, "baseline-quiz", quiz ? "" : "短听读没有打开理解题。",
                    area: "基线", title: "短听读理解题", did: "点短听读的“开始”。不保存题目截图。", body: true)
            if quiz { _ = tapButtonExact("关闭", timeout: 3) }
        } else if sees("先跳过") {
            require(false, "baseline-quiz", "短听读写着可以跳过，没有进入理解题。",
                    area: "基线", title: "短听读理解题", did: "找短听读的“开始”。", body: true)
        } else {
            require(false, "baseline-quiz", "没有点到短听读的“开始”。",
                    area: "基线", title: "短听读理解题", did: "找短听读的“开始”。", body: true)
        }

        require(openPart("无准备录音"), "baseline-speaking", currentTitle() == "无准备录音" ? "" : "没有进入“无准备录音”。",
                area: "基线", title: "无准备录音", did: "打开无准备录音。没有点“看题并开始”。")
        if currentTitle() == "无准备录音" { leaveToTab("今日"); _ = reopenBaseline() }

        let writing = openPart("独立短文")
        require(writing, "baseline-writing", writing ? "" : "没有进入“独立短文”。",
                area: "基线", title: "独立短文", did: "打开独立短文。")
        if writing, tapButtonExact("开始写") {
            let editor = waitToSee("离开", timeout: 4) || waitToSee("写完了", timeout: 2)
            require(editor, "baseline-writing-editor", editor ? "" : "点了“开始写”，没有进入编辑。",
                    area: "基线", title: "独立短文编辑", did: "点“开始写”。没有输入。")
            if tapButtonExact("离开", timeout: 2) { _ = tapButtonExact("离开，不保存", timeout: 2) }
            leaveToTab("今日")
            _ = reopenBaseline()
        }

        require(openPart("词汇自测"), "baseline-vocab", currentTitle() == "词汇自测" ? "" : "没有进入“词汇自测”。",
                area: "基线", title: "词汇自测", did: "打开词汇自测。没有答题。")
    }

    private func openPart(_ title: String) -> Bool {
        if tapButton("开始", nearest: title), waitForTitle(title, timeout: 4) { return true }
        return false
    }

    private func reopenBaseline() -> Bool {
        if currentTitle() == "建立基线" { return true }
        guard openTab("今日") else { return false }
        return tapButton("开始", nearest: "建立基线") && waitForTitle("建立基线", timeout: 6)
    }

    // MARK: Navigation

    private func launch() {
        app.launch()
        _ = app.navigationBars.firstMatch.waitForExistence(timeout: 25)
        setOrientation(wantLandscape ? .landscapeLeft : .portrait)
    }

    private func setOrientation(_ orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
        _ = app.navigationBars.firstMatch.waitForExistence(timeout: 3)
    }

    /// Landscape sidebar taps miss. Switch tabs in portrait, then turn back for the check.
    private func withPortraitTaps<T>(_ work: () -> T) -> T {
        guard wantLandscape else { return work() }
        setOrientation(.portrait)
        let value = work()
        setOrientation(.landscapeLeft)
        return value
    }

    @discardableResult
    private func openTab(_ name: String) -> Bool {
        if openTabHere(name) { return true }
        return withPortraitTaps { openTabHere(name) }
    }

    private func openTabHere(_ name: String) -> Bool {
        if currentTitle() == name { return true }
        let exact = NSPredicate(format: "label == %@", name)
        for query in [app.tabBars.buttons.matching(exact), app.buttons.matching(exact)] {
            if query.firstMatch.waitForExistence(timeout: 2) == false { continue }
            let count = min(query.count, 4)
            for index in 0..<count {
                let el = query.element(boundBy: index)
                guard el.exists, onScreen(el) else { continue }
                press(el)
                if currentTitle() == name { return true }
            }
        }
        return app.navigationBars[name].waitForExistence(timeout: 3)
    }

    private func leaveToTab(_ name: String) {
        if app.sheets.firstMatch.exists { _ = tapButtonExact("关闭", timeout: 1) }
        for _ in 0..<3 {
            if currentTitle() == name { return }
            if !goBack() { break }
        }
        if currentTitle() != name { _ = openTab(name) }
    }

    @discardableResult
    private func goBack() -> Bool {
        let before = currentTitle()
        let nav = app.navigationBars.firstMatch
        guard nav.exists else { return false }
        let buttons = nav.buttons
        let count = min(buttons.count, 6)
        var ordered: [XCUIElement] = []
        for index in 0..<count {
            let button = buttons.element(boundBy: index)
            if button.exists { ordered.append(button) }
        }
        ordered.sort { $0.frame.minX < $1.frame.minX }
        let labels = ["返回", "Back", "今日", "书架", "跟读", "雅思", "词汇", "进度", "设置", "使用说明", "建立基线"]
        for button in ordered where labels.contains(button.label) || button.label.hasPrefix("返回") {
            if button.isHittable { button.tap() } else { button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
            if waitUntil({ self.currentTitle() != before }, timeout: 3) { return true }
        }
        return false
    }

    @discardableResult
    private func openRow(_ text: String, expect: String) -> Bool {
        if openRowHere(text, expect: expect) { return true }
        return withPortraitTaps { openRowHere(text, expect: expect) }
    }

    private func openRowHere(_ text: String, expect: String) -> Bool {
        guard reveal(text) else { return false }
        let before = currentTitle()
        let pred = NSPredicate(format: "label CONTAINS %@", text)
        for query in [app.buttons.matching(pred), app.cells.matching(pred), app.links.matching(pred)] {
            let count = min(query.count, 3)
            for index in 0..<count {
                let el = query.element(boundBy: index)
                guard el.exists, onScreen(el) else { continue }
                if activate(el), waitForTitle(expect, timeout: 2) { return true }
                press(el)
                if waitForTitle(expect, timeout: 3) { return true }
                if currentTitle() != before, currentTitle() != expect {
                    _ = goBack()
                    _ = reveal(text)
                }
            }
        }
        return app.navigationBars[expect].exists
    }

    private func tapRow(_ text: String) {
        guard reveal(text) else { return }
        let pred = NSPredicate(format: "label CONTAINS %@", text)
        for query in [app.buttons.matching(pred), app.cells.matching(pred)] {
            let count = min(query.count, 2)
            for index in 0..<count {
                let el = query.element(boundBy: index)
                guard el.exists, onScreen(el) else { continue }
                if activate(el) { if waitUntil({ self.sees("练习模式") || self.currentTitle() != "跟读" && self.currentTitle() != "书架" }, timeout: 2) { return } }
                press(el)
                return
            }
        }
    }

    private func openSession(row: String, title: String, id: String) {
        let opened = openRow(row, expect: title) || waitForTitle(title, timeout: 4)
        require(opened, id, opened ? "" : "没有打开“\(title)”。", area: "雅思", title: title,
                did: "打开“\(title)”。没有开始录音，也没有输入。")
        if opened { leaveToTab("雅思") }
    }

    private func openSettings(label: String, id: String, title: String) {
        if label == "阅读字号与标注" {
            openTypeSize()
            return
        }
        let opened = openSettingsLink(label, expect: title)
        require(opened, id, opened ? "" : "没有打开“\(title)”。", area: "设置", title: title,
                did: "在设置里点“\(label)”。")
        if opened { leaveToTab("设置") }
    }

    /// The failed walk’s settings-type screenshot stayed on 设置. The destination used to title itself
    /// “阅读设置” while the row says “阅读字号与标注”, so a real push would also have been missed.
    private func openTypeSize() {
        leaveToTab("设置")
        _ = reveal("阅读字号与标注")
        let link = app.descendants(matching: .any)["settings-type-size"]
        var opened = false
        if link.waitForExistence(timeout: 3), onScreen(link) {
            if activate(link) { opened = typeSizeVisible(timeout: 2) }
            if !opened {
                press(link)
                opened = typeSizeVisible(timeout: 3)
            }
        }
        if !opened {
            opened = openRow("阅读字号与标注", expect: "阅读字号与标注") && typeSizeVisible(timeout: 2)
        }
        let wrong = app.navigationBars["阅读设置"].exists && !app.navigationBars["阅读字号与标注"].exists
        let issue: String
        if wrong {
            issue = "页面标题是“阅读设置”，设置入口写的是“阅读字号与标注”。"
            opened = false
        } else if opened {
            issue = ""
        } else {
            issue = "没有进入“阅读字号与标注”。当时停在：\(currentTitle())。"
        }
        require(opened && !wrong, "settings-type", issue, area: "设置", title: "阅读字号与标注",
                did: "点设置里的“阅读字号与标注”，核对导航标题和页面标识。")
        if opened { leaveToTab("设置") }
    }

    private func typeSizeVisible(timeout: TimeInterval) -> Bool {
        let marker = app.descendants(matching: .any)["reader-settings-screen"]
        if marker.waitForExistence(timeout: timeout) { return true }
        return waitForTitle("阅读字号与标注", timeout: timeout)
    }

    @discardableResult
    private func openSettingsLink(_ label: String, expect: String) -> Bool {
        if currentTitle() == expect { return true }
        if currentTitle() != "设置" { leaveToTab("设置") }
        return openRow(label, expect: expect)
    }

    // MARK: Taps

    private func press(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    @discardableResult
    private func activate(_ element: XCUIElement) -> Bool {
        let sel = NSSelectorFromString("activate")
        guard element.exists, element.responds(to: sel) else { return false }
        element.perform(sel)
        return true
    }

    @discardableResult
    private func tapButtonExact(_ name: String, timeout: TimeInterval = 3) -> Bool {
        if neverTap.contains(name) { return false }
        let pred = NSPredicate(format: "label == %@", name)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for query in [app.buttons, app.sheets.buttons, app.alerts.buttons] {
                let button = query.matching(pred).firstMatch
                if button.exists, button.isEnabled {
                    press(button)
                    return true
                }
            }
            if waitUntil({ false }, timeout: 0.2) { break }
        }
        return false
    }

    @discardableResult
    private func tapControl(_ name: String) -> Bool {
        if tapButtonExact(name, timeout: 2) { return true }
        if tapButtonExact("更多", timeout: 2) || tapButtonExact("更多操作", timeout: 1) {
            if tapButtonExact(name, timeout: 2) { return true }
        }
        return false
    }

    @discardableResult
    private func tapSegment(_ name: String) -> Bool {
        if neverTap.contains(name) { return false }
        let pred = NSPredicate(format: "label == %@", name)
        for query in [app.segmentedControls.buttons.matching(pred), app.buttons.matching(pred)] {
            let el = query.firstMatch
            if el.exists {
                press(el)
                return true
            }
        }
        return false
    }

    @discardableResult
    private func tapText(_ text: String) -> Bool {
        guard reveal(text) else { return false }
        let pred = NSPredicate(format: "label == %@", text)
        for query in [app.buttons.matching(pred), app.staticTexts.matching(pred)] {
            let el = query.firstMatch
            if el.exists, onScreen(el) {
                press(el)
                return true
            }
        }
        return false
    }

    @discardableResult
    private func tapButton(_ name: String, nearest anchorText: String) -> Bool {
        if neverTap.contains(name) { return false }
        guard reveal(anchorText) else { return false }
        let anchor = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", anchorText)).firstMatch
        guard anchor.exists else { return false }
        let pred = NSPredicate(format: "label == %@", name)
        var best: XCUIElement?
        var bestDy = CGFloat.greatestFiniteMagnitude
        let y = anchor.frame.midY
        let matches = app.buttons.matching(pred)
        let count = min(matches.count, 8)
        for index in 0..<count {
            let button = matches.element(boundBy: index)
            guard button.exists, button.isEnabled, onScreen(button) else { continue }
            let dy = button.frame.midY - y
            guard dy > -30, dy < 280 else { continue }
            if dy < bestDy {
                bestDy = dy
                best = button
            }
        }
        guard let chosen = best else { return false }
        press(chosen)
        return true
    }

    private func onScreen(_ element: XCUIElement) -> Bool {
        let frame = element.frame
        return frame.width > 24 && frame.height > 16 && frame.minY > 20 && frame.minY < 1500
            && frame.minX > -20 && frame.maxX > 40
    }

    @discardableResult
    private func reveal(_ text: String) -> Bool {
        if elementExists(text) { return true }
        for _ in 0..<6 {
            app.swipeUp()
            if elementExists(text) { return true }
        }
        for _ in 0..<3 {
            app.swipeDown()
            if elementExists(text) { return true }
        }
        return elementExists(text)
    }

    private func sees(_ text: String) -> Bool { elementExists(text) }

    private func elementExists(_ text: String) -> Bool {
        let pred = NSPredicate(format: "label == %@ OR label BEGINSWITH %@ OR label CONTAINS %@", text, text, text)
        return app.staticTexts.matching(pred).firstMatch.exists
            || app.buttons.matching(pred).firstMatch.exists
            || app.cells.matching(pred).firstMatch.exists
    }

    private func waitToSee(_ text: String, timeout: TimeInterval) -> Bool {
        let pred = NSPredicate(format: "label CONTAINS %@", text)
        return app.staticTexts.matching(pred).firstMatch.waitForExistence(timeout: timeout)
            || app.buttons.matching(pred).firstMatch.exists
            || app.cells.matching(pred).firstMatch.exists
    }

    private func waitToSeeButton(_ name: String, timeout: TimeInterval) -> Bool {
        app.buttons[name].waitForExistence(timeout: timeout)
    }

    private static let screenTitles = [
        "学习计划与提醒", "无准备录音", "独立短文", "词汇自测", "建立基线",
        "口语完整模拟", "口语 Part 2", "基础口语", "基础写作", "写作 Task 1", "写作 Task 2",
        "词汇设置", "阅读字号与标注", "阅读设置", "声音与速度", "资源清单", "文章资源", "能力清单",
        "完整备份", "从备份恢复", "录音占用与清理", "使用说明", "每天怎么用", "隐私",
        "导入内容包", "今日", "书架", "跟读", "雅思", "词汇", "进度", "设置",
    ]

    private func currentTitle() -> String {
        let tabs: Set<String> = ["今日", "书架", "跟读", "雅思", "词汇", "进度", "设置"]
        for name in Self.screenTitles where !tabs.contains(name) && app.navigationBars[name].exists {
            return name
        }
        for name in Self.screenTitles where tabs.contains(name) && app.navigationBars[name].exists {
            return name
        }
        return ""
    }

    @discardableResult
    private func waitForTitle(_ name: String, timeout: TimeInterval) -> Bool {
        waitUntil({ self.currentTitle() == name || self.app.navigationBars[name].exists }, timeout: timeout)
    }

    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return condition()
    }

    private func waitForImportSheet(timeout: TimeInterval) -> Bool {
        waitUntil({ self.importSheetVisible() }, timeout: timeout)
    }

    /// The library toolbar always has a button named “导入内容包”. That is not the preview.
    private func importSheetVisible() -> Bool {
        if app.descendants(matching: .any)["pack-import-sheet"].exists { return true }
        return app.navigationBars["导入内容包"].exists
    }

    // MARK: Records

    private func require(_ ok: Bool, _ id: String, _ issue: String, area: String, title: String, did: String, body: Bool = false) {
        let passed = ok && issue.isEmpty
        let problem = passed ? "" : (issue.isEmpty ? "这一屏没有核到。" : issue)
        record(id: id, area: area, title: title, did: did, issue: problem, checked: passed, body: body)
        if !passed { XCTFail(problem) }
    }

    private func record(id: String, area: String, title: String, did: String, issue: String, checked: Bool, body: Bool) {
        let shotId = "\(prefix)-\(id)"
        var payload: [String: Any] = [
            "id": shotId,
            "area": area,
            "title": title,
            "orientation": orientationName,
            "did": did,
            "issue": issue,
            "checked": checked,
            "body": body,
        ]
        if !body {
            payload["file"] = "\(shotId).png"
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = shotId
            attachment.lifetime = .keepAlways
            add(attachment)
            try? screenshot.pngRepresentation.write(to: Self.shotDirectory().appendingPathComponent("\(shotId).png"))
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let line = String(data: data, encoding: .utf8) else { return }
        print("DDU_SHOT \(line)")
        let url = Self.shotDirectory().appendingPathComponent("manifest.jsonl")
        if FileManager.default.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.write(contentsOf: Data("\n".utf8))
        } else {
            var bodyData = data
            bodyData.append(Data("\n".utf8))
            try? bodyData.write(to: url)
        }
    }

    private func writePack(documentsImport: Bool) {
        let info: [String: Any] = [
            "preseeded": false,
            "documentsImport": documentsImport,
            "articleCount": titles.count,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: info),
              let line = String(data: data, encoding: .utf8) else { return }
        print("DDU_PACK \(line)")
        try? data.write(to: Self.shotDirectory().appendingPathComponent("pack.json"))
    }

    private static func articleTitles() -> [String] {
        let env = ProcessInfo.processInfo.environment
        let path = env["PACK_MANIFEST"] ?? env["TEST_RUNNER_PACK_MANIFEST"] ?? ""
        guard !path.isEmpty,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let articles = obj["articles"] as? [[String: Any]] else { return [] }
        return articles.compactMap { $0["title"] as? String }.filter { !$0.isEmpty }
    }

    private static func shotDirectory() -> URL {
        let env = ProcessInfo.processInfo.environment
        let raw = env["SIM_SHOT_DIR"] ?? env["TEST_RUNNER_SIM_SHOT_DIR"] ?? "/tmp/ddu-ui-shots"
        let url = URL(fileURLWithPath: raw, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func modeSlug(_ mode: String) -> String {
        switch mode {
        case "听后模仿": return "repeat"
        case "影子跟读": return "shadowing"
        case "独立朗读": return "read"
        case "脱稿复述": return "retell"
        default: return "mode"
        }
    }
}
