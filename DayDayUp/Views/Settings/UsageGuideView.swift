import SwiftUI

/// 使用说明: how to use DayDayUp, in short plain Chinese. docs/GUIDE.md has the same content.
/// Only the app's own words: no magazine text.
struct UsageGuideView: View {
    var body: some View {
        List {
            Section {
                Text("每个题目几分钟就能看完。想看哪个，点哪个。")
                    .foregroundStyle(.secondary)
            }
            Section("题目") {
                ForEach(UsageGuide.topics) { topic in
                    NavigationLink {
                        UsageGuideTopicView(topic: topic)
                    } label: {
                        topicLabel(topic)
                    }
                }
            }
        }
        .navigationTitle("使用说明")
    }

    private func topicLabel(_ topic: GuideTopic) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.title)
                Text(topic.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: topic.symbol)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One topic of the guide, as a readable page (at most about 720 pt wide).
struct UsageGuideTopicView: View {
    let topic: GuideTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label(topic.title, systemImage: topic.symbol)
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(topic.blocks.enumerated()), id: \.offset) { item in
                    GuideBlockView(block: item.element)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct GuideTopic: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let summary: String
    let blocks: [GuideBlock]
}

enum GuideBlock {
    case heading(String)
    case text(String)
    case bullets([String])
    case steps([String])
    case note(String)
}

private struct GuideBlockView: View {
    let block: GuideBlock

    var body: some View {
        switch block {
        case .heading(let text):
            Text(text)
                .font(.title3.weight(.semibold))
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
        case .text(let text):
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        case .bullets(let items):
            GuideList(items: items, numbered: false)
        case .steps(let items):
            GuideList(items: items, numbered: true)
        case .note(let text):
            Label(text, systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct GuideList: View {
    let items: [String]
    let numbered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { item in
                let marker: String = numbered ? "\(item.offset + 1)." : "•"
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(marker)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(item.element)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Content (keep in step with docs/GUIDE.md)

@MainActor
enum UsageGuide {
    static var topics: [GuideTopic] {
        [daily, baseline, listening, shadowing, vocabulary, ielts, progress, packs, backup, recordings, privacy, faq]
    }

    private static var daily: GuideTopic {
        GuideTopic(id: "daily", title: "每天怎么用", symbol: "sun.max", summary: "今日计划、60/90 分钟、换一篇、暂缓", blocks: [
            .text("打开 App 先看“今日”。今天的计划已经排好，每一项都写着“为什么推荐”。"),
            .heading("每天学多久"),
            .bullets([
                "在“今日”顶上选 60 分钟、90 分钟或自定义（30–120 分钟）。",
                "60 分钟大致是：词汇 10、听读 20、跟读 15、说写 15。90 分钟大致是：词汇 10、听读 30、跟读 15、说写 35。",
                "时间不够时，先保留说写，把材料缩短，不会让你多学。",
                "改了时间或学习阶段，今天的计划会重新排；已经完成的任务保留。",
            ]),
            .heading("做任务"),
            .bullets([
                "点“开始”或“继续”，打开对应的页面。",
                "做完以后，App 按记录自动打勾，同一件事不会算两次。也可以在“更多”里“标记完成”或“重新打开”。",
                "听读任务觉得太难，点“换一篇”。",
                "今天做不了，点“暂缓”：任务挪到明天，只挪一次，明天不会翻倍。",
            ]),
            .heading("有效练习时间"),
            .text("只算真实的学习操作：播放、答题、录音、打字等。只开着页面不算；锁屏以后继续放的声音记成“后台播放”，也不算。"),
            .heading("提醒"),
            .bullets([
                "每周一，“今日”会提示上周的周报已经准备好。",
                "超过 7 天没有完整备份，“今日”和“设置”顶上会提醒你。",
                "每天一次的学习提醒默认关闭，可以在“设置 › 学习 › 学习计划与提醒”里打开，也可以设静默时段。",
            ]),
        ])
    }

    private static var baseline: GuideTopic {
        GuideTopic(id: "baseline", title: "首次基线", symbol: "list.bullet.clipboard", summary: "4 个小任务，看清起点", blocks: [
            .text("第一次用时，“今日”会安排“建立基线”。它有 4 个小任务，用来看清你现在的起点。"),
            .bullets([
                "短听读：一篇没学过的文章，只听约 1 分钟，不看原文，然后答理解题。",
                "无准备录音：看到题目，倒数 3 秒就开始说，最多 60 秒；说完回答 3 个是 / 否问题。",
                "独立短文：日常话题，10 分钟，没有提示，也没有参考。",
                "词汇自测：5、6、7、8 级词各 6 个，一共 24 个。",
            ]),
            .heading("怎么做"),
            .bullets([
                "可以分 2–3 次做完，每次 15–20 分钟，随时可以停。",
                "顺序随意。每一项做完才保存，中途离开不保存。",
                "想重做某一项，在基线页点“重做”，新结果替换旧结果。",
            ]),
            .text("结果只写成描述，不给雅思分。4 项都做完，App 会建议一个学习阶段：基础表达、表达发展或雅思备考。用不用由你决定；以后也可以在“设置 › 学习 › 学习计划与提醒”里改。"),
        ])
    }

    private static var listening: GuideTopic {
        GuideTopic(id: "listening", title: "听读", symbol: "headphones", summary: "盲听、看原文、点词、单词卡、中文、循环", blocks: [
            .text("在“书架”点一篇文章，就进入听读页。下面是播放条，右边的面板有“单词”“句子”“词表”三页。"),
            .heading("听和看"),
            .bullets([
                "播放时，正在读的词会高亮，页面跟着滚动。不想跟着滚，关掉播放条上的“自动跟随”。",
                "盲听：点右上角的“盲听”，原文藏起来，只听。再点“显示原文”回来。",
                "中文：点右上角的“中文”，显示或隐藏每段的中文翻译。",
                "速度：点播放条左边的速度，0.5×–1.5×，变速不变调。",
                "外接键盘：空格键播放或暂停，← → 上一句、下一句，L 单句循环。",
            ]),
            .heading("点词和单词卡"),
            .bullets([
                "点任意一个词，面板里显示这个词在这一句的意思、词典义项和例句。",
                "带下划线的是雅思 5 级以上的词，颜色表示级别。下划线从几级开始，在“设置 › 显示 › 阅读字号与标注”里改。",
                "想学这个词，点“收藏这个义项”。同一个词的不同意思分开学。",
                "“认识”只作记号，不排复习。",
            ]),
            .heading("循环"),
            .bullets([
                "单句循环：一直放当前这一句。",
                "A–B 循环：点一次设 A，再点一次设 B，第三次关闭。",
                "逐句暂停：每句放完停一下，方便跟着说。",
                "每遍之间停多久，在“设置 › 音频 › 声音与速度”里改。",
            ]),
            .heading("句子"),
            .text("面板的“句子”页有这一句的译文和句子解析，还可以从本句播放、循环本句、去跟读，或者“报错”。"),
            .note("听读完成 = 音频去重覆盖 ≥90%，不等于听懂。"),
        ])
    }

    private static var shadowing: GuideTopic {
        GuideTopic(id: "shadowing", title: "跟读", symbol: "waveform", summary: "四种模式与 A/B 对照", blocks: [
            .text("在听读页的“句子”面板点“跟读”，或者打开“跟读”页选一篇文章。一次练一句或一小段。"),
            .heading("四种模式"),
            .bullets([
                "听后模仿：先听原句，停下，再录音模仿，最后 A/B 对照。更像原声，不等于能即兴表达。",
                "影子跟读：跟着原音同时念，练节奏。可以先不录，只跟着念；“录音跟读”边放原音边录。建议戴耳机，外放时录的会标“可能串音”。",
                "独立朗读：不放原音，看着文字读一句或一段；读完可以听原音对照。",
                "脱稿复述：先听、先看，抓住主旨和两三个要点；点“开始复述”后原文收起并开始录音；可以看关键词提示，看过的会记下来；讲完回答一个追问（可以跳过）；最后对照原文。",
            ]),
            .heading("A/B 对照"),
            .text("先放原句，停一小会儿，再放你的录音，前后比较。原音速度和中间停多久，在跟读页或“设置 › 音频 › 声音与速度”里改。"),
            .heading("记住这些"),
            .bullets([
                "每次录音都保存，App 不打分。",
                "录音时来电话、切到后台或锁屏，已经录的部分会保存，标着“被打断”。",
                "发音标注有七层：意群、重音、连读、弱读、省音、同化、语调。机器按规则生成的标注写着“待核对”。",
            ]),
        ])
    }

    private static var vocabulary: GuideTopic {
        let tasks: [String] = VocabTask.allCases.map { $0.title + "：" + $0.detail }
        return GuideTopic(id: "vocabulary", title: "词汇", symbol: "character.book.closed",
                          summary: "收藏义项和词群、六种题型、FSRS 排期、积压时的规则", blocks: [
            .text("“词汇”页有五个子页：复习、浏览、听词、拼写、词群。"),
            .heading("收藏"),
            .bullets([
                "义项：在听读页点词，点“收藏这个义项”，选这一句里的意思。同一个词的不同意思，分开学。",
                "词群：在单词卡点“从这个词开始选词群”，再点最后一个词，预览以后保存。句子里的意群不进词群库，只在跟读标注里。",
                "新收藏只开“认义”。其他题型在“浏览”里点开词项，按需要打开。",
            ]),
            .heading("六种题型"),
            .bullets(tasks),
            .heading("排期（FSRS）"),
            .bullets([
                "每次作答先自己想，再揭晓，然后选：忘记、困难、记得、轻松。",
                "App 用 FSRS 算法按你的回答排下次复习。目标保留率默认 90%，可以在 80%–95% 之间调；调高了，每天的复习会变多。",
                "点错了，可以“撤销上一次”。",
                "复习间隔到了 21 天以上，只叫“较长复习间隔”，不叫“掌握”。",
            ]),
            .heading("每天的量和积压"),
            .bullets([
                "词汇预算默认每天 10 分钟（5–20 分钟），复习和新任务算在一起。到期的先做，预算还有剩余才放新任务；新任务默认每天 5 个（0–15 个）。",
                "最近两个学习日，开始时的到期量都超过预算，App 建议今天不加新任务。你可以选“今天仍然加新任务”。",
                "没做完的卡保持到期，不会偷偷挪到以后。",
                "听词只记“听过”，不算复习。",
            ]),
        ])
    }

    private static var ielts: GuideTopic {
        GuideTopic(id: "ielts", title: "雅思说写", symbol: "text.bubble", summary: "基础训练、考试题型、自评、反馈、新题复测", blocks: [
            .text("“雅思”页分口语和写作，每种都有“基础训练”和“考试题型”。题目和参考都是 DayDayUp 原创的。"),
            .heading("基础训练"),
            .bullets([
                "口语：准备 30 秒（可以跳过），说 45 秒左右；说长一点也可以，时间照实记。",
                "写作：5–10 分钟，写 3–5 句。草稿自动保存。",
            ]),
            .heading("考试题型"),
            .bullets([
                "口语 Part 2：准备 1 分钟，可以记笔记；陈述 1–2 分钟。不给范文。",
                "口语完整模拟：Part 1（8 题）→ Part 2（1 张题卡）→ Part 3（5 题），每题单独录音。这是离线固定题库，不等于真人考官。中途被打断或离开，就不算完整模拟，已录的回答都保留。",
                "写作 Task 1：图表题，至少 150 词，约 20 分钟，图可以放大看。",
                "写作 Task 2：至少 250 词，约 40 分钟。",
            ]),
            .heading("自评、参考、反馈"),
            .bullets([
                "做完先按四个方面自评：打勾，再写下证据（具体的词、句子、停顿的地方）。只打勾，不打分。",
                "基础训练要先自评，才能看参考。看过参考再做同一题，会记为“看过参考后”。",
                "反馈：点“复制给 Claude”，把题目（写作还有你的作文）复制出去，或者拿给老师看；拿到意见后点“录入反馈”存下来。",
                "写作完成后原稿只读，改写会存成新的一版。",
            ]),
            .heading("新题复测"),
            .text("作品有了反馈或改写，过 3–7 天（默认 4 天），“今日”会安排一道同类型的新题。看的是改进能不能用到新题上；它和同题重写分开记录。"),
        ])
    }

    private static var progress: GuideTopic {
        GuideTopic(id: "progress", title: "进度与周报", symbol: "chart.bar", summary: "投入和证据分开、样本少的提示", blocks: [
            .text("“进度”页把“投入”和“证据”分开：花了多少时间，和练得怎么样，是两回事。"),
            .heading("投入（花了多少时间）"),
            .bullets([
                "有效练习时间按周画成柱状图；同一段时间只算一次。后台播放单独列出，不算进去。",
                "可以看最近 7 天或 30 天。",
            ]),
            .heading("证据（练得怎么样）"),
            .bullets([
                "词汇回忆：近 28 天、隔天以上的第一次作答，成功几次 / 试了几次。少于 30 次只写“证据不足”，不算百分比。",
                "文章理解：理解题答对几题 / 共几题，不换算成分数。",
                "词项状态：几种能力分开记，不合成一个“掌握”。",
                "录音轨迹：第一次、最近几次和新题复测的录音，可以回听。",
                "说写作品链：原稿 → 反馈 → 重写 → 新题；同题重写和新题分开放。",
                "问题复发：你自评里多次没勾的点，带分母；觉得不对可以撤回。",
            ]),
            .heading("样本少"),
            .text("数量少于 20 时，旁边会标“样本少”，并写出分子和分母。这些数字只描述练习记录，不是成绩，也不预测考试分数。"),
            .heading("周报"),
            .bullets([
                "每周一准备上一周的汇总：时间、词汇、文章理解、说写、问题，还有下周最多 3 个重点。",
                "可以导出 JSON、CSV 或 PDF。导出前会先列出文件里有什么、没有什么。App 不会自动发送。",
            ]),
        ])
    }

    private static var packs: GuideTopic {
        GuideTopic(id: "packs", title: "内容包", symbol: "shippingbox", summary: "导入、预览、冲突、更新", blocks: [
            .text("内容包是 .ecopack 文件，一个文件装一期（或半期）的文章、音频和词卡。它只放在你自己的电脑和 iPad 上。"),
            .heading("导入"),
            .bullets([
                "在书架或“设置 › 资源与能力”里点“导入内容包”，选文件，可以一次选几个。",
                "也可以用 iTunes 文件共享或“文件”App，把内容包放进 DayDayUp 的文件夹。打开 App 后会提示发现了几个内容包，点它查看并导入。",
            ]),
            .heading("先预览，再导入"),
            .bullets([
                "每个文件先检查：文件完不完整、版本支不支持、缺不缺资源。有问题会一条一条列出来，这个文件不会写进书架。",
                "每个文件标一种情况：新增、已经导入过（不会重复导入）、冲突、新版本。",
                "还会显示要占多少空间、iPad 还剩多少。空间不够就不导入，原来的书架照常可用。",
                "你确认以后才写进书架。中途失败，书架保持导入以前的样子。",
            ]),
            .heading("冲突和更新"),
            .bullets([
                "冲突：版本号一样，内容却不同。默认保留现在的；你也可以选“替换”，或者“另存副本”（不导入，放进“文件”App 的 DayDayUp › 冲突副本），或者取消。",
                "新版本：列出增加、删除、改动的文章和句子。改动后对不上的句子，旧记录保留，标着“原句已更新”。更新不会重置复习。",
            ]),
            .note("删除内容包不会删除学习记录；重新导入以后，进度和生词都还在。每篇文章有什么、缺什么，在“设置 › 资源与能力 › 资源清单”里看。"),
        ])
    }

    private static var backup: GuideTopic {
        GuideTopic(id: "backup", title: "备份与恢复", symbol: "externaldrive", summary: "每周一次、恢复演练、撤销", blocks: [
            .text("学习记录、录音和作文只存在这台 iPad 上。删掉 App，它们就没了。所以要备份。"),
            .heading("每周备份一次"),
            .steps([
                "打开“设置 › 备份与恢复”，点“立即完整备份”。",
                "先看清单：录音几个、多大，写作几篇，学习记录有哪些；内容包不在备份里。",
                "点“继续”，选保存位置：“文件”App 里的“我的 iPad”或 iCloud 云盘。",
            ]),
            .text("超过 7 天没有备份，“今日”和“设置”顶上会提醒。"),
            .heading("恢复：先演练，再替换"),
            .steps([
                "点“设置 › 备份与恢复 › 从备份恢复”，选一个备份文件。",
                "App 先把它解到一个临时的地方，一个文件一个文件地检查。坏的备份会被拒绝，现在的记录不动。",
                "你会看到备份里有多少记录，还缺哪些内容包、哪些录音。旧版本的备份，会说明要转换什么。",
                "你确认以后才替换。替换以前，现在的全部数据会先整份留一份。",
                "恢复以后发现不对，可以“撤销这次恢复”，回到恢复以前。",
            ]),
            .note("恢复不会带回内容包。恢复以后缺哪一期，就再导入哪一期。"),
        ])
    }

    private static var recordings: GuideTopic {
        let reasons: [String] = RecordingKeepReason.allCases.map { $0.title + "：" + $0.detail }
        return GuideTopic(id: "recordings", title: "录音清理", symbol: "trash",
                          summary: "看占用、先预览、确认后才删", blocks: [
            .text("录音不会自动删除。录得多了，可以在“设置 › 备份与恢复 › 录音占用与清理”里清理。"),
            .steps([
                "先看占用：录音有几个、多大，iPad 还剩多少空间。",
                "点“预览清理”：App 列出能删的、要保留的，还有几组例子。预览不删任何东西。",
                "点“删除这些录音文件”，再在确认框里点“删除”。按两次才会删。",
            ]),
            .heading("一定保留"),
            .bullets(reasons),
            .bullets([
                "只录到静音的录音，不算在“首次”和“最近 3 次”里。",
                "没有记录的文件（App 里放不出来）默认不删；打开开关才一起删。最近 10 分钟里录的不动。",
            ]),
            .note("删掉的只是录音文件，练习记录都还在。放不出来的录音，回放按钮是灰的，进度页写“录音已清理”。删之前最好先做一次完整备份。"),
        ])
    }

    private static var privacy: GuideTopic {
        let has = WeeklyExport.included.joined(separator: "、")
        let hasNot = WeeklyExport.excluded.joined(separator: "、")
        let weekly = "周报：有\(has)；没有\(hasNot)。"
        return GuideTopic(id: "privacy", title: "隐私", symbol: "hand.raised", summary: "不联网、导出时带走什么", blocks: [
            .bullets([
                "App 里没有联网的代码：不上传、不统计、不同步。",
                "学习记录、录音和作文只存在这台 iPad 上。只有你自己导出、分享或复制时，文件才离开 iPad。",
            ]),
            .heading("每种导出里有什么"),
            .bullets([
                "完整备份：学习记录、全部录音、写作原文和改写、反馈和笔记、设置、练过的句子；没有内容包和诊断日志。",
                weekly,
                "诊断日志：版本、设备、数量、操作记录、你提交的报错（含那一句原文）；没有录音、作文和整篇文章。",
                "复制给 Claude：题目、用时和你写的文字，只放进剪贴板。",
            ]),
            .text("麦克风权限在“设置 › 隐私”里能看到，那里也有按钮直达 iPad 设置里的 DayDayUp 页。"),
        ])
    }

    private static var faq: GuideTopic {
        GuideTopic(id: "faq", title: "常见问题", symbol: "questionmark.circle", summary: "没有声音、导入失败、换新 iPad", blocks: [
            .heading("没有声音"),
            .bullets([
                "回到 App，点播放。",
                "看看 iPad 的静音和音量，蓝牙耳机有没有连到别的设备上。",
                "正在录音时不会播放；录完再放。",
                "单词没有声音：这篇可能没有单词原声，要用 iPad 自带的合成音。在“设置 › 资源与能力 › 能力清单”里看英音、美音有没有；没有的话，在 iPad 的“设置 › 辅助功能 › 朗读内容 › 声音”里下载。",
                "还不行，把 App 从后台关掉，再打开。",
            ]),
            .heading("导入失败"),
            .bullets([
                "提示“文件校验失败”或缺文件：文件没拷完整，重新拷一次这个内容包。",
                "提示格式太新：先更新 App。",
                "提示空间不够：清理一些录音或别的文件，再导入。",
                "导入失败时，原来的书架不变。",
            ]),
            .heading("录不了音"),
            .bullets([
                "看“设置 › 隐私”里的麦克风状态。没有允许，点按钮去 iPad 的设置里打开。",
                "录音被来电或切到后台打断，已经录的部分会保存，标着“被打断”；需要的话再录一次。",
            ]),
            .heading("换新 iPad"),
            .steps([
                "在旧 iPad 上做一次完整备份，存到 iCloud 云盘或电脑上。",
                "在新 iPad 上装好 DayDayUp，导入内容包。",
                "点“设置 › 备份与恢复 › 从备份恢复”，选这个备份，看清单，确认。",
                "打开几篇文章、听几个录音，确认都在。",
            ]),
            .heading("App 打不开了"),
            .text("免费签名每 7 天要在电脑上重装一次。过期以后图标还在，但打不开：不要删除 App，删除会清掉内容包、学习记录和录音。按安装说明重装一次就好。"),
        ])
    }
}
