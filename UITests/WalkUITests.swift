import XCTest

/// Walks the real DayDayUp app on the iPad simulator after one .ecopack is dropped into Documents.
/// Portrait first, then landscape. Microphone recording is never started.
/// Screenshots and one JSON line per screen go to SIM_SHOT_DIR (DDU_SHOT in the log).
final class WalkUITests: XCTestCase {
    private var app = XCUIApplication()
    private var imported = false
    private var packNote = ""
    private let article = "A new age of the orator"

    private let neverTap: Set<String> = [
        "录音", "录音跟读", "开始复述", "直接开始说", "看题并开始",
        "删除", "删除这个内容包", "继续",
    ]

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

    func testPackWalk() {
        packNote = ""
        launchFresh(.portrait)
        imported = importInbox()
        var info: [String: Any] = [
            "packFile": "DayDayUp-2026-09-12-2.ecopack",
            "imported": imported,
            "packNote": packNote,
            "sawOrator": sees(article),
            "sawWater": sees("High and dry"),
            "sawInvent": sees("All the things we do not see"),
        ]
        if let data = try? JSONSerialization.data(withJSONObject: info),
           let line = String(data: data, encoding: .utf8) {
            print("DDU_PACK \(line)")
            try? data.write(to: Self.shotDirectory().appendingPathComponent("pack.json"))
        }
        walk(prefix: "port", orientation: "竖屏")
        setOrientation(.landscapeLeft)
        walk(prefix: "land", orientation: "横屏")
        info["finished"] = true
        if let data = try? JSONSerialization.data(withJSONObject: info) {
            try? data.write(to: Self.shotDirectory().appendingPathComponent("pack.json"))
        }
    }

    // MARK: Pack

    private func importInbox() -> Bool {
        guard openTab("书架") else {
            shot("port-import-banner", area: "导入", title: "书架没有打开", orientation: "竖屏",
                 did: "准备导入前点“书架”，页面没有切过去。",
                 issue: packNote.isEmpty ? "标签点不到。" : packNote)
            return false
        }
        let banner = waitToSee("查看并导入", timeout: 20)
        shot("port-import-banner", area: "导入", title: banner ? "发现待导入的内容包" : "没有出现导入提示",
             orientation: "竖屏",
             did: banner
                ? "内容包已放进 App 的文稿文件夹。书架顶部出现导入提示。"
                : "打开书架后等了约 20 秒，没有看到“查看并导入”。",
             issue: banner ? "" : (packNote.isEmpty ? "文稿里的 .ecopack 没有被认成待导入文件。" : packNote))
        guard banner, tapContaining("查看并导入") else { return false }
        let ready = waitToSee("导入所选", timeout: 90)
        shot("port-import-review", area: "导入", title: ready ? "导入预览" : "导入预览没有出来",
             orientation: "竖屏",
             did: "点了“查看并导入”，等文件核对结束。",
             issue: ready ? "" : "90 秒内没有出现“导入所选”。")
        guard ready, waitEnabled("导入所选", timeout: 20), tapContaining("导入所选") else { return false }
        let done = waitToSeeButton("完成", timeout: 120)
        let titles = sees(article) || sees("High and dry")
        shot("port-import-done", area: "导入", title: done ? "导入结果" : "导入没有完成",
             orientation: "竖屏",
             did: "点了“导入所选”，等待写入书架。",
             issue: done ? "" : "120 秒内没有出现“完成”。")
        if done { _ = tapButtonExact("完成", timeout: 5) }
        pause(1.0)
        let onShelf = sees(article) || sees("High and dry") || sees("All the things we do not see")
        shot("port-import-shelf", area: "导入", title: onShelf ? "书架已有文章" : "导入后书架仍是空的",
             orientation: "竖屏",
             did: "关掉导入结果后看书架。",
             issue: onShelf ? "" : "没有看到三篇文章的标题。")
        return onShelf || titles
    }

    // MARK: One orientation

    private func walk(prefix: String, orientation: String) {
        if !openTab("今日") { relaunch(prefix == "port" ? .portrait : .landscapeLeft); _ = openTab("今日") }
        shot("\(prefix)-today", area: "今日", title: "今日", orientation: orientation,
             did: "打开“今日”。", issue: "")

        if tapButton("开始", nearest: "建立基线"), waitForTitle("建立基线", timeout: 6) {
            shot("\(prefix)-baseline", area: "基线", title: "建立基线", orientation: orientation,
                 did: "点了今日里“建立基线”的“开始”。", issue: "")
            walkBaseline(prefix: prefix, orientation: orientation)
            leaveToTab("今日")
        } else {
            shot("\(prefix)-baseline", area: "基线", title: "建立基线没有打开", orientation: orientation,
                 did: "没有进入标题为“建立基线”的页面。当时停在：\(currentTitle())。",
                 issue: "基线页没有出现。")
        }

        if tapText("计划设置"), waitForTitle("学习计划与提醒", timeout: 5) {
            shot("\(prefix)-today-plan", area: "今日", title: "计划设置", orientation: orientation,
                 did: "在今日点了“计划设置”。", issue: "")
            leaveToTab("今日")
        }

        walkLibraryAndReader(prefix: prefix, orientation: orientation)
        walkShadow(prefix: prefix, orientation: orientation)
        walkIELTS(prefix: prefix, orientation: orientation)
        walkVocab(prefix: prefix, orientation: orientation)
        walkProgress(prefix: prefix, orientation: orientation)
        walkSettings(prefix: prefix, orientation: orientation)
    }

    private func walkBaseline(prefix: String, orientation: String) {
        _ = reveal("短听读")
        if sees("听一小段") || sees("这次用") || sees("理解题") {
            shot("\(prefix)-baseline-listening-note", area: "基线", title: "短听读说明", orientation: orientation,
                 did: "滚到“短听读”，看内容包有没有理解题。", issue: "")
        }
        if tapButton("开始", nearest: "短听读") {
            let opened = waitToSee("基线：短听读", timeout: 8) || waitToSee("听一小段", timeout: 3) || waitToSee("理解题", timeout: 2)
            shot("\(prefix)-baseline-quiz", area: "基线", title: opened ? "短听读理解题" : "短听读没有打开",
                 orientation: orientation,
                 did: "点了“短听读”的“开始”。没有点“播放”，所以没有听完这一段。",
                 issue: opened ? "" : "理解题页面没有出现。")
            if opened { _ = tapButtonExact("关闭", timeout: 3) }
            pause(0.4)
        } else {
            shot("\(prefix)-baseline-quiz", area: "基线", title: "短听读不能开始", orientation: orientation,
                 did: "“短听读”旁边没有可点的“开始”。",
                 issue: sees("先跳过") ? "页面写的是可以先跳过，没有进入理解题。" : "没有点到短听读。")
        }

        if tapButton("开始", nearest: "无准备录音"), waitForTitle("无准备录音", timeout: 6) {
            shot("\(prefix)-baseline-speaking", area: "基线", title: "无准备录音", orientation: orientation,
                 did: "打开“无准备录音”。没有点“看题并开始”，没有录音。", issue: "")
            leaveToTab("今日")
            _ = openBaselineAgain()
        } else {
            shot("\(prefix)-baseline-speaking", area: "基线", title: "无准备录音没有打开", orientation: orientation,
                 did: "没有进入“无准备录音”。", issue: "准备页没有出现。")
        }

        if tapButton("开始", nearest: "独立短文"), waitForTitle("独立短文", timeout: 6) {
            shot("\(prefix)-baseline-writing", area: "基线", title: "独立短文", orientation: orientation,
                 did: "打开“独立短文”准备页。", issue: "")
            if tapButtonExact("开始写") {
                pause(0.6)
                shot("\(prefix)-baseline-writing-editor", area: "基线", title: "独立短文编辑", orientation: orientation,
                     did: "点了“开始写”。没有输入，也没有点“写完了”。", issue: "")
                if tapButtonExact("离开", timeout: 2) { _ = tapButtonExact("离开，不保存", timeout: 2) }
            }
            leaveToTab("今日")
            _ = openBaselineAgain()
        } else {
            shot("\(prefix)-baseline-writing", area: "基线", title: "独立短文没有打开", orientation: orientation,
                 did: "没有进入“独立短文”。", issue: "准备页没有出现。")
        }

        if tapButton("开始", nearest: "词汇自测"), waitForTitle("词汇自测", timeout: 6) {
            shot("\(prefix)-baseline-vocab", area: "基线", title: "词汇自测", orientation: orientation,
                 did: "打开“词汇自测”。没有答题。", issue: "")
            leaveToTab("今日")
        } else {
            shot("\(prefix)-baseline-vocab", area: "基线", title: "词汇自测没有打开", orientation: orientation,
                 did: "没有进入“词汇自测”。", issue: "自测页没有出现。")
        }
    }

    @discardableResult
    private func openBaselineAgain() -> Bool {
        if currentTitle() == "建立基线" { return true }
        if !openTab("今日") { return false }
        return tapButton("开始", nearest: "建立基线") && waitForTitle("建立基线", timeout: 6)
    }

    private func walkLibraryAndReader(prefix: String, orientation: String) {
        guard openTab("书架") else {
            shot("\(prefix)-library", area: "书架", title: "书架没有打开", orientation: orientation,
                 did: "点“书架”，页面没有切过去。", issue: "标签点不到。")
            return
        }
        _ = reveal(article) || reveal("High and dry")
        let filled = sees(article) || sees("High and dry") || sees("All the things we do not see")
        shot("\(prefix)-library", area: "书架", title: filled ? "书架" : "书架（没看到文章）", orientation: orientation,
             did: "打开“书架”。",
             issue: filled ? "" : "这一屏没有三篇文章的标题。")

        guard filled, openRow(article, expectTitle: article) || waitForTitle(article, timeout: 4) else {
            shot("\(prefix)-reader", area: "听读", title: "正文没有打开", orientation: orientation,
                 did: "点文章标题“\(article)”，没有进入听读。当时停在：\(currentTitle())。",
                 issue: "听读页没有出现。")
            return
        }
        shot("\(prefix)-reader", area: "听读", title: "听读正文", orientation: orientation,
             did: "从书架打开“\(article)”。", issue: "")

        if tapControl("播放") {
            pause(1.2)
            let playing = buttonExists("暂停")
            shot("\(prefix)-reader-play", area: "听读", title: playing ? "正在朗读" : "点了播放", orientation: orientation,
                 did: "点了播放器的“播放”。", issue: playing ? "" : "按钮没有变成“暂停”。")
            _ = tapControl("暂停")
        } else {
            shot("\(prefix)-reader-play", area: "听读", title: "没有点到播放", orientation: orientation,
                 did: "正文页上没有点到“播放”。", issue: "朗读控制没有出现。")
        }

        if tapControl("显示中文翻译") {
            pause(0.6)
            let hidden = buttonExists("隐藏中文翻译")
            shot("\(prefix)-reader-zh", area: "听读", title: hidden ? "已显示中文翻译" : "点了显示中文翻译",
                 orientation: orientation,
                 did: "点了“显示中文翻译”。", issue: hidden ? "" : "按钮没有变成“隐藏中文翻译”。")
        } else if buttonExists("隐藏中文翻译") {
            shot("\(prefix)-reader-zh", area: "听读", title: "中文翻译已经开着", orientation: orientation,
                 did: "正文页上的按钮已经是“隐藏中文翻译”，说明译文正显示着。", issue: "")
        } else {
            shot("\(prefix)-reader-zh", area: "听读", title: "没有点到中文翻译", orientation: orientation,
                 did: "没有找到“显示中文翻译”或“更多”里的这一项。", issue: "翻译开关没有点到。")
        }

        if tapControl("理解题") {
            let quiz = waitToSee("理解题", timeout: 8)
            shot("\(prefix)-reader-quiz", area: "听读", title: quiz ? "文章理解题" : "理解题没有打开",
                 orientation: orientation,
                 did: "在听读页点了“理解题”。没有提交答案。",
                 issue: quiz ? "" : "理解题页面没有出现。")
            if quiz { _ = tapButtonExact("关闭", timeout: 3) }
        } else {
            shot("\(prefix)-reader-quiz", area: "听读", title: "没有点到理解题", orientation: orientation,
                 did: "听读工具栏里没有点到“理解题”。", issue: "理解题没有打开。")
        }

        if tapControl("专注模式") {
            pause(0.5)
            shot("\(prefix)-reader-focus", area: "听读", title: "专注模式", orientation: orientation,
                 did: "点了“专注模式”。", issue: buttonExists("退出专注") ? "" : "没有看到“退出专注”。")
            _ = tapControl("退出专注")
        }
        leaveToTab("书架")
    }

    private func walkShadow(prefix: String, orientation: String) {
        guard openTab("跟读") else {
            shot("\(prefix)-shadow", area: "跟读", title: "跟读没有打开", orientation: orientation,
                 did: "点“跟读”，页面没有切过去。", issue: "标签点不到。")
            return
        }
        if !sees("练习模式") {
            _ = reveal(article)
            _ = tapContaining(article)
            pause(1.0)
        }
        let opened = sees("练习模式") || sees("听后模仿")
        shot("\(prefix)-shadow", area: "跟读", title: opened ? "跟读工作台" : "跟读文章没有打开",
             orientation: orientation,
             did: opened ? "在跟读里打开“\(article)”。" : "跟读列表里没有点开文章。",
             issue: opened ? "" : "四种练习的切换没有出现。")
        guard opened else { return }

        let modes = ["听后模仿", "影子跟读", "独立朗读", "脱稿复述"]
        for mode in modes {
            if mode != "听后模仿" { _ = tapSegment(mode) }
            pause(0.5)
            shot("\(prefix)-shadow-\(modeSlug(mode))", area: "跟读", title: mode, orientation: orientation,
                 did: "切到“\(mode)”。没有点录音。",
                 issue: sees(mode) ? "" : "这一屏没有看到“\(mode)”。")
        }
        if buttonExists("听原句") {
            _ = tapSegment("听后模仿")
            _ = tapButtonExact("听原句", timeout: 2)
            pause(0.8)
            shot("\(prefix)-shadow-listen", area: "跟读", title: "听原句", orientation: orientation,
                 did: "在“听后模仿”点了“听原句”。没有点“录音”。", issue: "")
        }
    }

    private func walkIELTS(prefix: String, orientation: String) {
        guard openTab("雅思") else {
            shot("\(prefix)-ielts", area: "雅思", title: "雅思没有打开", orientation: orientation,
                 did: "点“雅思”，页面没有切过去。", issue: "标签点不到。")
            return
        }
        _ = tapSegment("口语")
        _ = tapSegment("基础训练")
        shot("\(prefix)-ielts-speaking-basic", area: "雅思", title: "口语基础", orientation: orientation,
             did: "雅思页选了“口语”和“基础训练”。", issue: "")
        openSession(prefix: prefix, orientation: orientation, id: "ielts-speaking-session",
                    row: "How often do you use your phone", title: "基础口语", area: "雅思")

        _ = tapSegment("考试题型")
        pause(0.4)
        shot("\(prefix)-ielts-speaking-exam", area: "雅思", title: "口语考试题型", orientation: orientation,
             did: "口语下切到“考试题型”。", issue: "")
        openSession(prefix: prefix, orientation: orientation, id: "ielts-mock",
                    row: "口语完整模拟", title: "口语完整模拟", area: "雅思")
        openSession(prefix: prefix, orientation: orientation, id: "ielts-part2",
                    row: "Describe a practical skill", title: "口语 Part 2", area: "雅思")

        _ = tapSegment("写作")
        _ = tapSegment("基础训练")
        pause(0.4)
        shot("\(prefix)-ielts-writing-basic", area: "雅思", title: "写作基础", orientation: orientation,
             did: "切到“写作”和“基础训练”。", issue: "")
        openSession(prefix: prefix, orientation: orientation, id: "ielts-writing-session",
                    row: "Some people say smartphones", title: "基础写作", area: "雅思")

        _ = tapSegment("考试题型")
        pause(0.4)
        _ = reveal("Average daily bike rentals")
        shot("\(prefix)-ielts-writing-exam", area: "雅思", title: "写作考试题型", orientation: orientation,
             did: "写作下切到“考试题型”。", issue: "")
        openSession(prefix: prefix, orientation: orientation, id: "ielts-task1",
                    row: "Average daily bike rentals", title: "写作 Task 1", area: "雅思")
        openSession(prefix: prefix, orientation: orientation, id: "ielts-task2",
                    row: "In many places, people can now pay", title: "写作 Task 2", area: "雅思")
    }

    private func openSession(prefix: String, orientation: String, id: String, row: String, title: String, area: String) {
        if openRow(row, expectTitle: title) || waitForTitle(title, timeout: 4) {
            shot("\(prefix)-\(id)", area: area, title: title, orientation: orientation,
                 did: "打开“\(title)”。没有开始录音，也没有输入文字。", issue: "")
            leaveToTab("雅思")
        } else {
            shot("\(prefix)-\(id)", area: area, title: "\(title)没有打开", orientation: orientation,
                 did: "点“\(row)”后标题仍是“\(currentTitle())”。",
                 issue: "这一页没有出现。")
        }
    }

    private func walkVocab(prefix: String, orientation: String) {
        guard openTab("词汇") else {
            shot("\(prefix)-vocab-review", area: "词汇", title: "词汇没有打开", orientation: orientation,
                 did: "点“词汇”，页面没有切过去。", issue: "标签点不到。")
            return
        }
        let pages = [("复习", "review"), ("浏览", "browse"), ("听词", "listen"), ("拼写", "spell"), ("词群", "chunks")]
        for (title, slug) in pages {
            _ = tapSegment(title)
            pause(0.5)
            shot("\(prefix)-vocab-\(slug)", area: "词汇", title: "词汇 · \(title)", orientation: orientation,
                 did: "词汇子页切到“\(title)”。", issue: "")
        }
    }

    private func walkProgress(prefix: String, orientation: String) {
        guard openTab("进度") else {
            shot("\(prefix)-progress-7", area: "进度", title: "进度没有打开", orientation: orientation,
                 did: "点“进度”，页面没有切过去。", issue: "标签点不到。")
            return
        }
        shot("\(prefix)-progress-7", area: "进度", title: "进度 · 最近 7 天", orientation: orientation,
             did: "打开“进度”。默认是最近 7 天。", issue: "")
        if tapButtonExact("最近 30 天") || tapContaining("最近 30 天") {
            pause(0.5)
            shot("\(prefix)-progress-30", area: "进度", title: "进度 · 最近 30 天", orientation: orientation,
                 did: "点了“最近 30 天”。", issue: "")
        } else {
            shot("\(prefix)-progress-30", area: "进度", title: "最近 30 天没有点到", orientation: orientation,
                 did: "进度页上没有点到“最近 30 天”。", issue: "窗口没有切换。")
        }
    }

    private func walkSettings(prefix: String, orientation: String) {
        guard openTab("设置") else {
            shot("\(prefix)-settings", area: "设置", title: "设置没有打开", orientation: orientation,
                 did: "点“设置”，页面没有切过去。", issue: "标签点不到。")
            return
        }
        _ = reveal("资源与能力")
        shot("\(prefix)-settings", area: "设置", title: "设置", orientation: orientation,
             did: "打开“设置”。", issue: "")

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
            openSettings(prefix: prefix, orientation: orientation, label: label, id: id, title: title)
        }
        if currentTitle() == "使用说明" || openSettingsLink("使用说明", expect: "使用说明") {
            if openRow("每天怎么用", expectTitle: "每天怎么用") || waitForTitle("每天怎么用", timeout: 4) {
                shot("\(prefix)-settings-guide-topic", area: "设置", title: "使用说明 · 每天怎么用", orientation: orientation,
                     did: "在使用说明里打开“每天怎么用”。", issue: "")
                leaveToTab("设置")
            }
        }

        if tapButtonExact("立即完整备份", timeout: 3), waitForTitle("完整备份", timeout: 6) || waitToSee("备份里有", timeout: 3) {
            shot("\(prefix)-settings-backup", area: "设置", title: "完整备份", orientation: orientation,
                 did: "点了“立即完整备份”。没有点“继续”，没有生成文件。", issue: "")
            _ = tapButtonExact("取消", timeout: 3)
            pause(0.4)
        } else {
            shot("\(prefix)-settings-backup", area: "设置", title: "完整备份没有打开", orientation: orientation,
                 did: "没有打开“完整备份”。", issue: "备份说明页没有出现。")
            leaveToTab("设置")
        }

        if tapButtonExact("从备份恢复", timeout: 3), waitForTitle("从备份恢复", timeout: 6) || waitToSee("选择备份", timeout: 3) || waitToSee("备份文件", timeout: 2) {
            shot("\(prefix)-settings-restore", area: "设置", title: "从备份恢复", orientation: orientation,
                 did: "点了“从备份恢复”。没有选择文件。", issue: "")
            _ = tapButtonExact("关闭", timeout: 3)
        } else {
            shot("\(prefix)-settings-restore", area: "设置", title: "从备份恢复没有打开", orientation: orientation,
                 did: "没有打开“从备份恢复”。", issue: "恢复页没有出现。")
        }
    }

    private func openSettings(prefix: String, orientation: String, label: String, id: String, title: String) {
        if openSettingsLink(label, expect: title) {
            shot("\(prefix)-\(id)", area: "设置", title: title, orientation: orientation,
                 did: "在设置里点了“\(label)”。", issue: "")
            if title == "资源清单" {
                if openRow(article, expectTitle: "文章资源") || waitForTitle("文章资源", timeout: 4) {
                    shot("\(prefix)-settings-article-resource", area: "设置", title: "文章资源", orientation: orientation,
                         did: "在资源清单里打开“\(article)”。", issue: "")
                    _ = goBack()
                }
            }
            leaveToTab("设置")
        } else {
            shot("\(prefix)-\(id)", area: "设置", title: "\(title)没有打开", orientation: orientation,
                 did: "点“\(label)”后标题仍是“\(currentTitle())”。",
                 issue: "这一页没有出现。")
            leaveToTab("设置")
        }
    }

    @discardableResult
    private func openSettingsLink(_ label: String, expect: String) -> Bool {
        if currentTitle() == expect { return true }
        if currentTitle() != "设置" { leaveToTab("设置") }
        return openRow(label, expectTitle: expect) || waitForTitle(expect, timeout: 3)
    }

    // MARK: Launch and tabs

    private func launchFresh(_ orientation: UIDeviceOrientation) {
        app.launch()
        _ = app.navigationBars.firstMatch.waitForExistence(timeout: 30)
        setOrientation(orientation)
    }

    private func relaunch(_ orientation: UIDeviceOrientation) {
        app.terminate()
        launchFresh(orientation)
    }

    private func setOrientation(_ orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
        pause(1.0)
    }

    @discardableResult
    private func openTab(_ name: String) -> Bool {
        if app.navigationBars[name].exists, currentTitle() == name { return true }
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
                pause(0.6)
                if app.navigationBars[name].waitForExistence(timeout: 4) { return true }
            }
        }
        for label in ["显示边栏", "Show Sidebar", "侧边栏"] {
            let toggle = app.buttons[label]
            if toggle.exists, toggle.isHittable {
                toggle.tap()
                pause(0.3)
                break
            }
        }
        let again = app.buttons.matching(exact).firstMatch
        if again.exists, again.isHittable {
            again.tap()
            pause(0.6)
        }
        return app.navigationBars[name].waitForExistence(timeout: 4)
    }

    private func leaveToTab(_ name: String) {
        if app.sheets.firstMatch.exists || buttonExists("关闭") && currentTitle() != name {
            _ = tapButtonExact("关闭", timeout: 1)
        }
        for _ in 0..<3 {
            if currentTitle() == name { return }
            if !goBack() { break }
        }
        if currentTitle() != name { _ = openTab(name) }
    }

    // MARK: Taps

    private static let screenTitles = [
        "学习计划与提醒", "无准备录音", "独立短文", "词汇自测", "建立基线",
        "口语完整模拟", "口语 Part 2", "基础口语", "基础写作", "写作 Task 1", "写作 Task 2",
        "词汇设置", "阅读字号与标注", "声音与速度", "资源清单", "文章资源", "能力清单",
        "完整备份", "从备份恢复", "录音占用与清理", "使用说明", "每天怎么用", "隐私",
        "导入内容包", "A new age of the orator", "High and dry", "All the things we do not see",
        "今日", "书架", "跟读", "雅思", "词汇", "进度", "设置",
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
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if currentTitle() == name || app.navigationBars[name].exists { return true }
            pause(0.25)
        }
        return currentTitle() == name
    }

    @discardableResult
    private func openRow(_ text: String, expectTitle: String) -> Bool {
        guard reveal(text) else { return false }
        let before = currentTitle()
        let pred = NSPredicate(format: "label CONTAINS %@", text)
        let queries: [XCUIElementQuery] = [app.buttons, app.cells, app.links, app.staticTexts]
        for query in queries {
            let el = query.matching(pred).firstMatch
            guard el.exists else { continue }
            let frame = el.frame
            guard frame.width > 40, frame.height > 16 else { continue }
            el.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            pause(0.9)
            if currentTitle() != before, currentTitle() == expectTitle || app.navigationBars[expectTitle].exists {
                return true
            }
            if currentTitle() != before, currentTitle() != expectTitle {
                _ = goBack()
                _ = reveal(text)
            }
        }
        return app.navigationBars[expectTitle].exists
    }

    @discardableResult
    private func tapText(_ text: String) -> Bool {
        guard reveal(text) else { return false }
        let pred = NSPredicate(format: "label == %@ OR label BEGINSWITH %@", text, text)
        for query in [app.buttons, app.staticTexts, app.cells] {
            let el = query.matching(pred).firstMatch
            if el.exists {
                el.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                pause(0.7)
                return true
            }
        }
        return false
    }

    @discardableResult
    private func tapContaining(_ text: String) -> Bool {
        if neverTap.contains(text) { return false }
        let pred = NSPredicate(format: "label CONTAINS %@", text)
        for query in [app.buttons, app.sheets.buttons, app.cells, app.staticTexts] {
            let el = query.matching(pred).firstMatch
            if el.exists, el.isHittable {
                el.tap()
                pause(0.7)
                return true
            }
            if el.exists {
                el.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                pause(0.7)
                return true
            }
        }
        return false
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
                    if button.isHittable {
                        button.tap()
                    } else {
                        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                    }
                    pause(0.6)
                    return true
                }
            }
            pause(0.25)
        }
        return false
    }

    /// Toolbar item, or the same item inside the “更多” menu on a narrower column.
    @discardableResult
    private func tapControl(_ name: String) -> Bool {
        if tapButtonExact(name, timeout: 2) { return true }
        if tapButtonExact("更多", timeout: 2) || tapButtonExact("更多操作", timeout: 1) {
            pause(0.3)
            if tapButtonExact(name, timeout: 2) { return true }
        }
        return false
    }

    @discardableResult
    private func tapSegment(_ name: String) -> Bool {
        if neverTap.contains(name) { return false }
        let pred = NSPredicate(format: "label == %@", name)
        for query in [app.buttons, app.segmentedControls.buttons, app.switches] {
            let el = query.matching(pred).firstMatch
            if el.exists {
                if el.isHittable { el.tap() } else { el.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
                pause(0.45)
                return true
            }
        }
        return tapContaining(name)
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
            guard button.exists, button.isEnabled else { continue }
            let dy = abs(button.frame.midY - y)
            if dy < bestDy {
                bestDy = dy
                best = button
            }
        }
        guard let chosen = best else { return false }
        if chosen.isHittable {
            chosen.tap()
        } else {
            chosen.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        pause(0.7)
        return true
    }

    private func buttonExists(_ name: String) -> Bool {
        app.buttons.matching(NSPredicate(format: "label == %@ OR label CONTAINS %@", name, name)).firstMatch.exists
    }

    @discardableResult
    private func reveal(_ text: String, attempts: Int = 6) -> Bool {
        if elementExists(text) { return true }
        for _ in 0..<attempts {
            scrollContent(up: false)
            if elementExists(text) { return true }
        }
        for _ in 0..<3 {
            scrollContent(up: true)
            if elementExists(text) { return true }
        }
        return elementExists(text)
    }

    private func sees(_ text: String) -> Bool {
        elementExists(text)
    }

    private func elementExists(_ text: String) -> Bool {
        let pred = NSPredicate(format: "label == %@ OR label BEGINSWITH %@ OR label CONTAINS %@", text, text, text)
        return app.staticTexts.matching(pred).firstMatch.exists
            || app.buttons.matching(pred).firstMatch.exists
            || app.cells.matching(pred).firstMatch.exists
    }

    private func waitToSee(_ text: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if elementExists(text) { return true }
            pause(0.35)
        }
        return elementExists(text)
    }

    private func waitEnabled(_ snippet: String, timeout: TimeInterval) -> Bool {
        let pred = NSPredicate(format: "label CONTAINS %@", snippet)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let button = app.buttons.matching(pred).firstMatch
            if button.exists, button.isEnabled { return true }
            pause(0.35)
        }
        let button = app.buttons.matching(pred).firstMatch
        return button.exists && button.isEnabled
    }

    private func waitToSeeButton(_ name: String, timeout: TimeInterval) -> Bool {
        let pred = NSPredicate(format: "label == %@", name)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.buttons.matching(pred).firstMatch.exists { return true }
            pause(0.4)
        }
        return app.buttons.matching(pred).firstMatch.exists
    }

    @discardableResult
    private func goBack() -> Bool {
        let before = currentTitle()
        let labels = ["返回", "Back", "今日", "书架", "跟读", "雅思", "词汇", "进度", "设置", "使用说明", "建立基线"]
        let nav = app.navigationBars.firstMatch
        if nav.exists {
            let buttons = nav.buttons
            let count = min(buttons.count, 6)
            var ordered: [XCUIElement] = []
            for index in 0..<count {
                let button = buttons.element(boundBy: index)
                if button.exists { ordered.append(button) }
            }
            ordered.sort { $0.frame.minX < $1.frame.minX }
            for button in ordered where labels.contains(button.label) || button.label.hasPrefix("返回") {
                button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                pause(0.6)
                if currentTitle() != before { return true }
            }
        }
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        pause(0.6)
        return currentTitle() != before
    }

    private func scrollContent(up: Bool) {
        let startY: CGFloat = up ? 0.38 : 0.72
        let endY: CGFloat = up ? 0.72 : 0.38
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: startY))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: endY))
        start.press(forDuration: 0.02, thenDragTo: end)
        pause(0.3)
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
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

    // MARK: Screenshots

    private func shot(_ id: String, area: String, title: String, orientation: String, did: String, issue: String) {
        pause(0.35)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = id
        attachment.lifetime = .keepAlways
        add(attachment)
        let record: [String: String] = [
            "id": id,
            "file": "\(id).png",
            "area": area,
            "title": title,
            "orientation": orientation,
            "did": did,
            "saw": visibleText(),
            "issue": issue,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: record),
              let line = String(data: data, encoding: .utf8) else { return }
        print("DDU_SHOT \(line)")
        appendManifest(data)
        try? screenshot.pngRepresentation.write(to: Self.shotDirectory().appendingPathComponent("\(id).png"))
    }

    private func visibleText() -> String {
        var parts: [String] = []
        let title = currentTitle()
        if !title.isEmpty { parts.append("导航标题：" + title) }
        let probes = [
            article, "High and dry", "All the things we do not see",
            "查看并导入", "导入所选", "3 篇", "The Economist",
            "建立基线", "短听读", "听一小段", "理解题", "先跳过",
            "显示中文翻译", "隐藏中文翻译", "暂停", "练习模式",
            "听后模仿", "影子跟读", "独立朗读", "脱稿复述",
            "基础训练", "考试题型", "最近 30 天", "最近 7 天",
            "还没有内容包", "还没有导入内容包",
        ]
        for probe in probes where app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", probe)).firstMatch.exists
            || app.buttons.matching(NSPredicate(format: "label CONTAINS %@", probe)).firstMatch.exists {
            parts.append(probe)
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
        let raw = env["SIM_SHOT_DIR"] ?? env["TEST_RUNNER_SIM_SHOT_DIR"] ?? "/tmp/ddu-ui-shots"
        let url = URL(fileURLWithPath: raw, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

}
