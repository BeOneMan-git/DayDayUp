import XCTest

/// Opens the real DayDayUp app on the iPad simulator and walks screens that do not
/// need a content pack. Screenshots go to SIM_SHOT_DIR (or /tmp/ddu-ui-shots) and
/// to the xcresult. Lines starting with DDU_SHOT are the Chinese notes for the report.
/// Microphone recording is never started.
final class WalkUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_Hans_CN"]
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

    func test01TodayAndBaseline() {
        launchApp()
        shot("01-today", area: "今日", title: "今日",
             did: "启动 DayDayUp（不是逻辑测试宿主），停在默认的“今日”。",
             issue: issueIfMissing(["今日", "还没有文章", "建立基线"]))

        if tapButton("开始", nearest: "建立基线"), currentTitle() == "建立基线" {
            shot("03-baseline", area: "基线", title: "建立基线",
                 did: "在今日计划里点了“建立基线”那一项的“开始”。",
                 issue: "")
            walkBaselineParts()
        } else {
            shot("03-baseline", area: "基线", title: "建立基线没有打开",
                 did: "在今日找“建立基线”旁边的“开始”，没有进入标题为“建立基线”的页面。",
                 issue: "没有进入基线页。当时停在：\(currentTitle())。")
        }

        if currentTitle() != "今日" {
            if !goBack() { relaunch() }
        }
        if currentTitle() != "今日" { relaunch(); _ = openTab("今日") }
        if tapText("计划设置") && currentTitle() == "学习计划与提醒" {
            shot("02-today-plan-settings", area: "今日", title: "计划设置",
                 did: "回到今日后点了“计划设置”。",
                 issue: "")
        } else {
            shot("02-today-plan-settings", area: "今日", title: "计划设置没有打开",
                 did: "在今日找“计划设置”，没有进入“学习计划与提醒”。",
                 issue: "当时停在：\(currentTitle())。")
        }
    }

    private func walkBaselineParts() {
        _ = reveal("短听读")
        shot("04-baseline-listening", area: "基线", title: "短听读（缺内容包）",
             did: "滚到“短听读”。没有点“先跳过这一项”。",
             issue: issueIfMissing(["理解题", "先跳过", "内容包"]))
        if tapButton("开始", nearest: "无准备录音"), currentTitle() == "无准备录音" {
            shot("05-baseline-speaking", area: "基线", title: "无准备录音",
                 did: "点了“无准备录音”的“开始”。没有点“看题并开始”，所以没有倒数，也没有录音。",
                 issue: "")
            goBack()
        } else {
            shot("05-baseline-speaking", area: "基线", title: "无准备录音没有打开",
                 did: "在基线页找“无准备录音”的“开始”，没有点到。",
                 issue: "准备页没有出现。")
        }

        if tapButton("开始", nearest: "独立短文"), currentTitle() == "独立短文" {
            shot("06-baseline-writing-ready", area: "基线", title: "独立短文（还没开始写）",
                 did: "点了“独立短文”的“开始”。",
                 issue: "")
            if tapButtonExact("开始写") {
                shot("07-baseline-writing-editor", area: "基线", title: "独立短文编辑",
                     did: "点了“开始写”，看到计时和输入区。没有输入文字，也没有点“写完了”。",
                     issue: "")
                if tapButtonExact("离开") {
                    _ = tapButtonExact("离开，不保存")
                }
            } else {
                shot("07-baseline-writing-editor", area: "基线", title: "独立短文编辑没有打开",
                     did: "准备页上没有点到“开始写”。",
                     issue: "编辑区没有出现。")
                goBack()
            }
        } else {
            shot("06-baseline-writing-ready", area: "基线", title: "独立短文没有打开",
                 did: "在基线页找“独立短文”的“开始”，没有点到。",
                 issue: "准备页没有出现。")
        }

        if tapButton("开始", nearest: "词汇自测"), currentTitle() == "词汇自测" {
            shot("08-baseline-vocab", area: "基线", title: "词汇自测",
                 did: "点了“词汇自测”的“开始”。没有点“先跳过这一项”。",
                 issue: issueIfMissing(["词库", "内容包", "先跳过"]))
            goBack()
        } else {
            shot("08-baseline-vocab", area: "基线", title: "词汇自测没有打开",
                 did: "在基线页找“词汇自测”的“开始”，没有点到。",
                 issue: "自测页没有出现。")
        }
    }

    func test02LibraryAndShadow() {
        launchApp()
        guard openTab("书架") else {
            shot("09-library", area: "书架", title: "书架没有打开",
                 did: "点侧栏或标签“书架”，页面没有切过去。",
                 issue: "标签点不到。当时的界面见这张图。")
            return
        }
        shot("09-library", area: "书架", title: "书架",
             did: "打开“书架”。",
             issue: issueIfMissing(["还没有内容包", "导入内容包"]))
        if tapButtonExact("导入内容包") {
            pause(1.2)
            shot("10-library-import", area: "书架", title: "导入内容包",
                 did: "点了“导入内容包”，看文件选择器是否出现。没有选择任何文件。",
                 issue: "")
            dismissPickerThenEnsure(tab: "书架")
        } else {
            shot("10-library-import", area: "书架", title: "导入没有打开",
                 did: "书架上没有点到“导入内容包”。",
                 issue: "文件选择器没有出现。")
        }

        guard openTab("跟读") else {
            shot("11-shadow", area: "跟读", title: "跟读没有打开",
                 did: "点“跟读”，页面没有切过去。",
                 issue: "标签点不到。")
            return
        }
        shot("11-shadow", area: "跟读", title: "跟读",
             did: "打开“跟读”。仓库里没有内容包，这里应是选文章的空列表。",
             issue: issueIfMissing(["内容包", "还没有"]))
        if tapButtonExact("换一篇") {
            pause(0.8)
            shot("12-shadow-picker", area: "跟读", title: "选一篇文章",
                 did: "点了“换一篇”。",
                 issue: issueIfMissing(["选一篇", "内容包", "取消"]))
            if !tapButtonExact("取消") {
                dismissPickerThenEnsure(tab: "跟读")
            }
        } else {
            shot("12-shadow-picker", area: "跟读", title: "选文章没有打开",
                 did: "没有点到“换一篇”。",
                 issue: "选文章的页面没有出现。")
        }
    }

    func test03IELTS() {
        launchApp()
        guard openTab("雅思") else {
            shot("13-ielts", area: "雅思", title: "雅思没有打开",
                 did: "点“雅思”，页面没有切过去。",
                 issue: "标签点不到。")
            return
        }
        shot("13-ielts-speaking-basic", area: "雅思", title: "雅思 · 口语 · 基础训练",
             did: "打开“雅思”。默认应是口语、基础训练。",
             issue: "")
        if openRow("How often do you use your phone", expectTitle: "基础口语")
            || openRow("你一天用多", expectTitle: "基础口语") {
            shot("14-ielts-speaking-session", area: "雅思", title: "基础口语",
                 did: "点开第一道基础口语。没有点“开始准备”或“直接开始说”。",
                 issue: "")
            if !goBack() { relaunch(); _ = openTab("雅思") }
        } else {
            shot("14-ielts-speaking-session", area: "雅思", title: "基础口语没有打开",
                 did: "口语基础列表里没有点到题目。",
                 issue: "题目页没有出现。")
        }

        _ = tapButtonExact("考试题型")
        pause(0.6)
        shot("15-ielts-speaking-exam", area: "雅思", title: "雅思 · 口语 · 考试题型",
             did: "点了“考试题型”。",
             issue: "")
        if openRow("口语完整模拟", expectTitle: "口语完整模拟") {
            shot("16-ielts-mock", area: "雅思", title: "口语完整模拟",
                 did: "点开“口语完整模拟”。没有点“开始模拟”。",
                 issue: "")
            if !goBack() { relaunch(); _ = openTab("雅思"); _ = tapButtonExact("考试题型") }
        } else {
            shot("16-ielts-mock", area: "雅思", title: "口语完整模拟没有打开",
                 did: "没有点到“口语完整模拟”。",
                 issue: "模拟首页没有出现。")
        }
        if openRow("Describe a practical skill", expectTitle: "口语 Part 2")
            || openRow("You should say", expectTitle: "口语 Part 2")
            || openRow("准备 1 分钟", expectTitle: "口语 Part 2") {
            shot("17-ielts-part2", area: "雅思", title: "口语 Part 2",
                 did: "点开一张 Part 2 题卡。没有点“开始准备”。",
                 issue: "")
            if !goBack() { relaunch(); _ = openTab("雅思") }
        } else {
            shot("17-ielts-part2", area: "雅思", title: "口语 Part 2 没有打开",
                 did: "考试题型列表里没有点到 Part 2 题卡。",
                 issue: "题卡页没有出现。")
        }

        _ = tapButtonExact("写作")
        _ = tapButtonExact("基础训练")
        pause(0.6)
        shot("18-ielts-writing-basic", area: "雅思", title: "雅思 · 写作 · 基础训练",
             did: "切到写作、基础训练。",
             issue: "")
        if openRow("smartphones make us less social", expectTitle: "基础写作")
            || openRow("有人说智能手机", expectTitle: "基础写作") {
            shot("19-ielts-writing-session", area: "雅思", title: "基础写作",
                 did: "点开第一道基础写作。没有点“开始写”，避免计时。",
                 issue: "")
            if !goBack() { relaunch(); _ = openTab("雅思"); _ = tapButtonExact("写作"); _ = tapButtonExact("基础训练") }
        } else {
            shot("19-ielts-writing-session", area: "雅思", title: "基础写作没有打开",
                 did: "写作基础列表里没有点到题目。",
                 issue: "题目页没有出现。")
        }

        _ = tapButtonExact("考试题型")
        pause(0.6)
        shot("20-ielts-writing-exam", area: "雅思", title: "雅思 · 写作 · 考试题型",
             did: "切到写作的考试题型。",
             issue: "")
        if openRow("Average daily", expectTitle: "Task 1")
            || openRow("150", expectTitle: "Task 1") {
            shot("21-ielts-task1", area: "雅思", title: "写作 Task 1",
                 did: "点开第一道 Task 1。没有点“开始写”。",
                 issue: "")
            if !goBack() { relaunch(); _ = openTab("雅思"); _ = tapButtonExact("写作"); _ = tapButtonExact("考试题型") }
        } else {
            shot("21-ielts-task1", area: "雅思", title: "写作 Task 1 没有打开",
                 did: "没有点到 Task 1。",
                 issue: "题目页没有出现。")
        }
        _ = reveal("Task 2")
        if openRow("250", expectTitle: "Task 2") {
            shot("22-ielts-task2", area: "雅思", title: "写作 Task 2",
                 did: "点开第一道 Task 2。没有点“开始写”。",
                 issue: "")
            _ = goBack()
        } else {
            shot("22-ielts-task2", area: "雅思", title: "写作 Task 2 没有打开",
                 did: "没有点到 Task 2。",
                 issue: "题目页没有出现。")
        }
    }

    func test04VocabAndProgress() {
        launchApp()
        guard openTab("词汇") else {
            shot("23-vocab-review", area: "词汇", title: "词汇没有打开",
                 did: "点“词汇”，页面没有切过去。",
                 issue: "标签点不到。")
            return
        }
        let pages = [
            ("23-vocab-review", "复习"),
            ("24-vocab-browse", "浏览"),
            ("25-vocab-listen", "听词"),
            ("26-vocab-spell", "拼写"),
            ("27-vocab-chunks", "词群"),
        ]
        for (id, name) in pages {
            if name != "复习" {
                _ = tapButtonExact(name)
                pause(0.5)
            }
            shot(id, area: "词汇", title: "词汇 · \(name)",
                 did: "打开词汇的“\(name)”。没有收藏词，也没有导入 CSV。",
                 issue: "")
        }

        guard openTab("进度") else {
            shot("28-progress-7", area: "进度", title: "进度没有打开",
                 did: "点“进度”，页面没有切过去。",
                 issue: "标签点不到。")
            return
        }
        shot("28-progress-7", area: "进度", title: "进度 · 最近 7 天",
             did: "打开“进度”。默认窗口是最近 7 天。",
             issue: "")
        if tapButtonExact("最近 30 天") {
            shot("29-progress-30", area: "进度", title: "进度 · 最近 30 天",
                 did: "点了“最近 30 天”。",
                 issue: "")
        } else {
            shot("29-progress-30", area: "进度", title: "最近 30 天没有点到",
                 did: "进度页上没有点到“最近 30 天”。",
                 issue: "窗口可能仍是 7 天。")
        }
    }

    func test05SettingsLearning() {
        launchApp()
        guard openTab("设置") else {
            shot("30-settings", area: "设置", title: "设置没有打开",
                 did: "点“设置”，页面没有切过去。",
                 issue: "标签点不到。")
            return
        }
        shot("30-settings", area: "设置", title: "设置",
             did: "打开“设置”的上半部分。",
             issue: "")
        openSettings("学习计划与提醒", id: "31-settings-study", title: "学习计划与提醒")
        if tapText("词汇复习") {
            shot("32-settings-vocab", area: "设置", title: "词汇复习",
                 did: "在设置里点了“词汇复习”。",
                 issue: "")
            if tapText("从 CSV 导入旧生词") {
                shot("33-settings-csv", area: "设置", title: "从 CSV 导入旧生词",
                     did: "从词汇设置点进 CSV 导入。没有选择文件。",
                     issue: "")
                goBack()
            } else {
                shot("33-settings-csv", area: "设置", title: "CSV 导入没有打开",
                     did: "词汇设置里没有点到“从 CSV 导入旧生词”。",
                     issue: "导入页没有出现。")
            }
            goBack()
        } else {
            shot("32-settings-vocab", area: "设置", title: "词汇复习没有打开",
                 did: "在设置里找“词汇复习”，没有点到。",
                 issue: "这一页没有出现。")
        }
        openSettings("阅读字号与标注", id: "34-settings-reader", title: "阅读字号与标注")
        openSettings("声音与速度", id: "35-settings-audio", title: "声音与速度")
    }

    func test06SettingsRest() {
        launchApp()
        guard openTab("设置") else {
            shot("36-settings-resources", area: "设置", title: "设置没有打开",
                 did: "再次打开设置失败。",
                 issue: "标签点不到。")
            return
        }
        openSettings("资源清单", id: "36-settings-resources", title: "资源清单")
        openSettings("能力清单：断网能做什么", id: "37-settings-capability", title: "能力清单", expect: "能力清单")
        openSettings("导出的文件里有什么", id: "38-settings-privacy", title: "隐私", expect: "隐私")

        if tapText("立即完整备份") {
            pause(0.8)
            shot("39-settings-backup", area: "设置", title: "完整备份",
                 did: "点了“立即完整备份”。没有点“继续：打包并选择保存位置”。",
                 issue: "")
            if !tapButtonExact("取消") { goBack() }
        } else {
            shot("39-settings-backup", area: "设置", title: "完整备份没有打开",
                 did: "设置里没有点到“立即完整备份”。",
                 issue: "备份说明页没有出现。")
        }

        if tapText("从备份恢复") {
            pause(0.8)
            shot("40-settings-restore", area: "设置", title: "从备份恢复",
                 did: "点了“从备份恢复”。没有选择备份文件。",
                 issue: "")
            if !tapButtonExact("关闭") { goBack() }
        } else {
            shot("40-settings-restore", area: "设置", title: "从备份恢复没有打开",
                 did: "设置里没有点到“从备份恢复”。",
                 issue: "恢复页没有出现。")
        }

        openSettings("录音占用与清理", id: "41-settings-recordings", title: "录音占用与清理")
        if tapText("使用说明") {
            shot("42-settings-guide", area: "设置", title: "使用说明",
                 did: "在设置里点了“使用说明”。",
                 issue: "")
            if tapText("听读") {
                shot("43-settings-guide-listening", area: "设置", title: "使用说明 · 听读",
                     did: "在使用说明里点了“听读”。这是说明文字，不是听读器。",
                     issue: "听读器和“显示中文翻译”要先有文章才能打开。仓库里没有内容包。")
                goBack()
            } else {
                shot("43-settings-guide-listening", area: "设置", title: "使用说明里的听读没有打开",
                     did: "使用说明列表里没有点到“听读”。",
                     issue: "说明页没有出现。听读器本身也打不开：没有文章。")
            }
            goBack()
        } else {
            shot("42-settings-guide", area: "设置", title: "使用说明没有打开",
                 did: "在设置里找“使用说明”，没有点到。",
                 issue: "使用说明没有出现。")
        }
    }

    // MARK: Launch and tabs

    private func launchApp() {
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        _ = app.navigationBars.firstMatch.waitForExistence(timeout: 30)
        pause(1.0)
    }

    @discardableResult
    private func openTab(_ name: String) -> Bool {
        if app.navigationBars[name].exists { return true }
        let exact = NSPredicate(format: "label == %@", name)
        let queries = [
            app.tabBars.buttons.matching(exact),
            app.buttons.matching(exact),
            app.collectionViews.buttons.matching(exact),
        ]
        for query in queries {
            let el = query.firstMatch
            if el.waitForExistence(timeout: 2), el.isHittable {
                el.tap()
                pause(0.7)
                if app.navigationBars[name].waitForExistence(timeout: 4) { return true }
            }
        }
        for label in ["显示边栏", "Show Sidebar", "侧边栏"] {
            let toggle = app.buttons[label]
            if toggle.exists, toggle.isHittable {
                toggle.tap()
                pause(0.4)
                break
            }
        }
        let again = app.buttons.matching(exact).firstMatch
        if again.exists, again.isHittable {
            again.tap()
            pause(0.7)
        }
        let opened = app.navigationBars[name].waitForExistence(timeout: 4)
        if !opened {
            print("DDU_HIER \(name) \(app.debugDescription.prefix(2500))")
        }
        return opened
    }

    // MARK: Taps

    /// Detail titles, longest first. Tab names stay last so a pushed page wins over the sidebar.
    private static let screenTitles = [
        "学习计划与提醒", "无准备录音", "独立短文", "词汇自测", "建立基线",
        "口语完整模拟", "口语 Part 2", "基础口语", "基础写作", "写作 Task 1", "写作 Task 2",
        "词汇设置", "阅读字号与标注", "声音与速度", "资源清单", "能力清单", "完整备份",
        "从备份恢复", "录音占用与清理", "使用说明", "选一篇文章", "隐私", "听读",
        "今日", "书架", "跟读", "雅思", "词汇", "进度", "设置",
    ]

    private func currentTitle() -> String {
        let tabs: Set<String> = ["今日", "书架", "跟读", "雅思", "词汇", "进度", "设置"]
        var found: [String] = []
        for bar in app.navigationBars.allElementsBoundByIndex {
            if let name = Self.screenTitles.first(where: { bar.staticTexts[$0].exists }) {
                found.append(name)
                continue
            }
            let title = bar.identifier.isEmpty ? bar.label : bar.identifier
            if !title.isEmpty { found.append(title) }
        }
        if let detail = found.last(where: { !tabs.contains($0) }) { return detail }
        if let any = found.last { return any }
        return Self.screenTitles.first { app.staticTexts[$0].exists && !tabs.contains($0) } ?? ""
    }

    private func relaunch() {
        app.terminate()
        launchApp()
    }

    /// Taps a row. Returns true when the navigation title changes to something containing `expectTitle`,
    /// or when `expectTitle` is nil and the title changes at all.
    @discardableResult
    private func openRow(_ text: String, expectTitle: String? = nil) -> Bool {
        guard reveal(text) else { return false }
        let before = currentTitle()
        let pred = NSPredicate(format: "label CONTAINS %@", text)
        var pool: [XCUIElement] = []
        for query in [app.cells, app.buttons, app.links, app.staticTexts] {
            pool.append(contentsOf: query.matching(pred).allElementsBoundByIndex)
        }
        let usable = pool.filter { el in
            let frame = el.frame
            return frame.width > 80 && frame.height > 18 && frame.minY > 20
        }
        let ordered = usable.sorted { lhs, rhs in
            let rank: (XCUIElement) -> Int = { el in
                switch el.elementType {
                case .cell: return 0
                case .button, .link: return 1
                default: return 2
                }
            }
            if rank(lhs) != rank(rhs) { return rank(lhs) < rank(rhs) }
            return lhs.frame.width > rhs.frame.width
        }
        for target in ordered.prefix(4) {
            for x in [0.5, 0.25, 0.75] as [CGFloat] {
                target.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.5)).tap()
                pause(1.0)
                let title = currentTitle()
                if title == before { continue }
                if let expectTitle {
                    if title.contains(expectTitle) { return true }
                } else {
                    return true
                }
                if !goBack() { relaunch() }
                _ = reveal(text)
            }
        }
        print("DDU_HIER row \(text) title=\(currentTitle()) cells=\(app.cells.count)")
        return false
    }

    @discardableResult
    private func tapText(_ text: String) -> Bool {
        if openRow(text) { return true }
        if !reveal(text) { return false }
        let pred = NSPredicate(format: "label == %@ OR label BEGINSWITH %@", text, text)
        for query in [app.buttons, app.cells, app.staticTexts] {
            let el = query.matching(pred).firstMatch
            if el.exists {
                el.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                pause(0.8)
                return true
            }
        }
        return false
    }

    @discardableResult
    private func tapButtonExact(_ name: String, timeout: TimeInterval = 3) -> Bool {
        let pred = NSPredicate(format: "label == %@", name)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for query in [app.buttons, app.sheets.buttons, app.alerts.buttons, app.scrollViews.buttons] {
                let button = query.matching(pred).firstMatch
                if button.exists {
                    if button.isHittable {
                        button.tap()
                    } else {
                        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                    }
                    pause(0.7)
                    return true
                }
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    @discardableResult
    private func tapButton(_ name: String, nearest anchorText: String) -> Bool {
        guard reveal(anchorText) else { return false }
        let anchor = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", anchorText)).firstMatch
        guard anchor.exists else { return false }
        let pred = NSPredicate(format: "label == %@", name)
        let buttons = app.buttons.matching(pred).allElementsBoundByIndex.filter(\.exists)
        let y = anchor.frame.midY
        guard let chosen = buttons.min(by: { abs($0.frame.midY - y) < abs($1.frame.midY - y) }) else {
            return false
        }
        if chosen.isHittable {
            chosen.tap()
        } else {
            chosen.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        pause(0.9)
        return true
    }

    @discardableResult
    private func tapCell(containing text: String) -> Bool {
        let pred = NSPredicate(format: "label CONTAINS %@", text)
        if !reveal(text) {
            let cell = app.cells.matching(pred).firstMatch
            if !cell.exists { return false }
        }
        let cell = app.cells.matching(pred).firstMatch
        if cell.exists, cell.isHittable {
            cell.tap()
            pause(0.8)
            return true
        }
        let textEl = app.staticTexts.matching(pred).firstMatch
        if textEl.exists {
            textEl.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            pause(0.8)
            return true
        }
        return false
    }

    private func tapFirstCell(skipping: [String], skipContaining: [String] = []) -> Bool {
        for cell in app.cells.allElementsBoundByIndex where cell.isHittable {
            let label = cell.label
            if label.count < 8 { continue }
            if skipContaining.contains(where: { label.contains($0) }) { continue }
            if skipping.contains(where: { label == $0 || label.hasPrefix($0) && label.count < $0.count + 4 }) {
                continue
            }
            cell.tap()
            pause(0.8)
            return true
        }
        return false
    }

    private func tapFirstCell(containingAny needles: [String]) -> Bool {
        for cell in app.cells.allElementsBoundByIndex where cell.isHittable {
            let label = cell.label
            if needles.contains(where: { label.contains($0) }) {
                cell.tap()
                pause(0.8)
                return true
            }
        }
        for needle in needles where reveal(needle) {
            return tapCell(containing: needle)
        }
        return false
    }

    private func openSettings(_ label: String, id: String, title: String, expect: String? = nil) {
        let wanted = expect ?? title
        if openRow(label, expectTitle: wanted) || (tapText(label) && currentTitle().contains(wanted)) {
            shot(id, area: "设置", title: title, did: "在设置里点了“\(label)”。", issue: "")
            if !goBack() { relaunch(); _ = openTab("设置") }
        } else {
            shot(id, area: "设置", title: "\(title)没有打开",
                 did: "在设置里找“\(label)”，点了以后标题仍是“\(currentTitle())”。",
                 issue: "这一页没有出现。上面这张图是当时停住的界面。")
        }
    }

    @discardableResult
    private func reveal(_ text: String, attempts: Int = 7) -> Bool {
        if elementExists(text) { return true }
        for _ in 0..<attempts {
            scrollContent(up: false)
            if elementExists(text) { return true }
        }
        for _ in 0..<attempts {
            scrollContent(up: true)
            if elementExists(text) { return true }
        }
        return elementExists(text)
    }

    private func elementExists(_ text: String) -> Bool {
        let pred = NSPredicate(format: "label == %@ OR label BEGINSWITH %@ OR label CONTAINS %@", text, text, text)
        return app.staticTexts.matching(pred).firstMatch.exists
            || app.buttons.matching(pred).firstMatch.exists
            || app.cells.matching(pred).firstMatch.exists
    }

    @discardableResult
    private func goBack() -> Bool {
        let before = currentTitle()
        let nav = app.navigationBars.firstMatch
        let labels = ["返回", "Back", "今日", "书架", "跟读", "雅思", "词汇", "进度", "设置", "使用说明", "词汇复习"]
        if nav.exists {
            let buttons = nav.buttons.allElementsBoundByIndex.sorted { $0.frame.minX < $1.frame.minX }
            for button in buttons where labels.contains(button.label) || button.label.hasPrefix("返回") {
                button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                pause(0.8)
                if currentTitle() != before { return true }
            }
            if let left = buttons.first {
                left.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                pause(0.8)
                if currentTitle() != before { return true }
            }
        }
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.45))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.45))
        start.press(forDuration: 0.08, thenDragTo: end)
        pause(0.8)
        return currentTitle() != before
    }

    private func dismissPickerThenEnsure(tab: String) {
        if tapButtonExact("取消", timeout: 2) || tapButtonExact("关闭", timeout: 1) || tapButtonExact("Cancel", timeout: 1) {
            pause(0.4)
            return
        }
        app.terminate()
        launchApp()
        _ = openTab(tab)
    }

    private func scrollContent(up: Bool) {
        let startY: CGFloat = up ? 0.35 : 0.72
        let endY: CGFloat = up ? 0.72 : 0.35
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: startY))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: endY))
        start.press(forDuration: 0.02, thenDragTo: end)
        pause(0.4)
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    // MARK: Screenshots

    private func issueIfMissing(_ needles: [String]) -> String {
        let blob = (app.staticTexts.allElementsBoundByIndex.prefix(40).map(\.label)).joined(separator: "\n")
        if needles.contains(where: { blob.contains($0) }) { return "" }
        return "页面上没有看到这些字：" + needles.joined(separator: "、") + "。以这张图为准。"
    }

    private func shot(_ id: String, area: String, title: String, did: String, issue: String) {
        pause(0.5)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = id
        attachment.lifetime = .keepAlways
        add(attachment)

        let saw = visibleText()
        let record: [String: String] = [
            "id": id,
            "file": "\(id).png",
            "area": area,
            "title": title,
            "did": did,
            "saw": saw,
            "issue": issue,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: record),
              let line = String(data: data, encoding: .utf8) else { return }
        print("DDU_SHOT \(line)")
        appendManifest(data)
        let url = Self.shotDirectory().appendingPathComponent("\(id).png")
        try? screenshot.pngRepresentation.write(to: url)
    }

    private func visibleText() -> String {
        var parts: [String] = []
        let title = currentTitle()
        if !title.isEmpty { parts.append("导航标题：" + title) }
        let probes = [
            "还没有文章", "还没有内容包", "建立基线", "短听读", "需要新版内容包",
            "先跳过这一项", "看题并开始", "开始写", "词库里还没有可用的词",
            "还没有词条", "听词列表是空的", "还没有词群", "今日暂无到期",
            "有效练习时间", "最近 30 天", "最近 7 天", "学习计划与提醒",
            "还没有导入内容包", "从未备份", "每个题目几分钟就能看完",
            "基础口语：准备", "考试题型", "导入内容包",
        ]
        for probe in probes where app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", probe)).firstMatch.exists {
            if !parts.contains(where: { $0.contains(probe) }) {
                parts.append(probe)
            }
        }
        return parts.joined(separator: "｜")
    }

    private func appendManifest(_ data: Data) {
        let url = Self.shotDirectory().appendingPathComponent("manifest.jsonl")
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.write(contentsOf: Data("\n".utf8))
        } else {
            var body = data
            body.append(Data("\n".utf8))
            try? body.write(to: url)
        }
    }

    private static func shotDirectory() -> URL {
        let env = ProcessInfo.processInfo.environment
        let raw = env["SIM_SHOT_DIR"]
            ?? env["TEST_RUNNER_SIM_SHOT_DIR"]
            ?? "/tmp/ddu-ui-shots"
        let url = URL(fileURLWithPath: raw, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
