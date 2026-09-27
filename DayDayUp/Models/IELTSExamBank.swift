import Foundation

// V0.4 exam-format tasks (IEL-P03…P06): Part 1 topics, Part 2 cue cards with their Part 3
// discussion questions, Academic Writing Task 1 figures and Task 2 essay questions.
// Everything here is original, written for DayDayUp; all numbers are invented and only for
// practice. The repository is public, so no material from published tests belongs here.

// MARK: Speaking

/// One Part 1 topic: four short questions about everyday life.
struct Part1Set: Identifiable {
    let id: String
    let topic: String          // Chinese label
    let questions: [String]    // 4 questions

    /// SpeakingWork.promptId of one question when it is answered in a mock ("p1-home#2").
    func questionId(_ index: Int) -> String { "\(id)#\(index + 1)" }
}

/// One Part 2 cue card.
struct CueCard: Identifiable {
    let id: String
    let topic: String          // Chinese label
    let title: String          // "Describe a …"
    let bullets: [String]      // the "You should say:" points; the last one starts with "and explain"
    let rounding: String       // one short rounding-off question after the talk
}

/// Part 3: discussion questions on the theme of one cue card.
struct Part3Set: Identifiable {
    let id: String
    let cueCardId: String
    let questions: [String]    // 5 questions

    func questionId(_ index: Int) -> String { "\(id)#\(index + 1)" }
}

// MARK: Writing Task 1

enum Task1Kind: String, CaseIterable {
    case line, bar, pie, table, process

    var title: String {
        switch self {
        case .line: return "线图"
        case .bar: return "柱状图"
        case .pie: return "饼图"
        case .table: return "表格"
        case .process: return "流程图"
        }
    }

    /// Drawn with Swift Charts (the others are a table or numbered steps).
    var isChart: Bool { self == .line || self == .bar || self == .pie }

    /// What the task asks for, in plain words.
    var note: String {
        switch self {
        case .process:
            return "流程图：按顺序写清每一步，多用被动语态。概述写出一共几步、从哪里开始、到哪里结束。"
        case .table:
            return "表格：先找最大、最小和变化最明显的数字，写概述，再挑重点比较。不用把每个数字都写进去。"
        case .line, .bar, .pie:
            return "写一段概述，点出最主要的趋势或对比，再用数据支持。不写原因，不写个人观点。"
        }
    }
}

/// One line, one group of bars, one pie, or one table row.
struct Task1Series: Identifiable {
    let name: String
    let points: [(label: String, value: Double)]

    var id: String { name }

    init(name: String, points: [(label: String, value: Double)]) {
        self.name = name
        self.points = points
    }

    /// Labels and values given separately (same length, same order).
    init(_ name: String, labels: [String], values: [Double]) {
        self.name = name
        self.points = zip(labels, values).map { (label: $0.0, value: $0.1) }
    }
}

struct Task1Prompt: Identifiable {
    let id: String
    let kind: Task1Kind
    let zh: String             // short Chinese label for lists
    let heading: String        // the figure's own title, printed above it
    let lead: String           // "The graph below shows …"
    let title: String          // the whole task text: lead + the standard instruction
    let unit: String           // unit of the values ("bikes per day", "%")
    let xAxis: String          // category axis title (line, bar) or first-column title (table)
    let series: [Task1Series]
    let steps: [String]        // process diagrams only
    let source: String

    init(id: String, kind: Task1Kind, zh: String, heading: String, lead: String, unit: String = "",
         xAxis: String = "", series: [Task1Series] = [], steps: [String] = [],
         source: String = IELTSExamBank.dataSource) {
        self.id = id
        self.kind = kind
        self.zh = zh
        self.heading = heading
        self.lead = lead
        self.title = lead + "\n\n" + IELTSExamBank.task1Instruction
        self.unit = unit
        self.xAxis = xAxis
        self.series = series
        self.steps = steps
        self.source = source
    }

    /// Category or time labels in order (from the first series; all series share them).
    var labels: [String] { series.first?.points.map { $0.label } ?? [] }

    /// A round number a little above the largest value, for the value axis.
    var axisMax: Double {
        let top = series.flatMap { $0.points.map { $0.value } }.max() ?? 0
        guard top > 0 else { return 1 }
        let raw = top * 1.08
        let magnitude = pow(10, floor(log10(raw)))
        for step in [1.0, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10] where step * magnitude >= raw {
            return step * magnitude
        }
        return 10 * magnitude
    }

    /// The data as plain text, for "复制给 Claude" (Claude cannot see the chart).
    var dataText: String {
        switch kind {
        case .process:
            return steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        case .table:
            let header = ([xAxis] + labels).joined(separator: " | ")
            let rows = series.map { s in
                ([s.name] + s.points.map { Task1Prompt.format($0.value) }).joined(separator: " | ")
            }
            return (["Unit: \(unit)", header] + rows).joined(separator: "\n")
        case .line, .bar, .pie:
            var lines = ["Unit: \(unit)"]
            for s in series {
                let values = s.points.map { "\($0.label) \(Task1Prompt.format($0.value))" }.joined(separator: "; ")
                lines.append("\(s.name): \(values)")
            }
            return lines.joined(separator: "\n")
        }
    }

    /// English number style, the same on every iPad: 1,200 · 2.4.
    static func format(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.0001 {
            let n = Int(value.rounded())
            let digits = String(abs(n))
            var out = ""
            for (i, ch) in digits.enumerated() {
                if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
                out.append(ch)
            }
            return n < 0 ? "-" + out : out
        }
        return String(format: "%.1f", value)
    }
}

// MARK: Writing Task 2

enum Task2Type: String, CaseIterable {
    case opinion = "观点"
    case discussion = "讨论"
    case advantages = "利弊"
    case problemSolution = "问题与解决"
    case twoPart = "双问题"

    var title: String { rawValue }

    /// What a complete answer has to cover.
    var note: String {
        switch self {
        case .opinion: return "观点题：说清你同意或不同意到什么程度，全文立场一致。"
        case .discussion: return "讨论题：两种观点都要讨论，并给出你自己的看法。"
        case .advantages: return "利弊题：好处和坏处都要写；问“是否利大于弊”时，要给出明确判断。"
        case .problemSolution: return "问题与解决：先写原因或问题，再给具体、可行的办法。"
        case .twoPart: return "双问题：两个问题都要回答，各用一段展开。"
        }
    }
}

struct Task2Prompt: Identifiable {
    let id: String
    let type: Task2Type
    let topic: String          // one of IELTSBank.topics
    let zh: String             // short Chinese label for lists
    let question: String       // the statement and the task, without the closing instruction
    let text: String           // the whole question, ending with the standard instruction

    init(id: String, type: Task2Type, topic: String, zh: String, question: String) {
        self.id = id
        self.type = type
        self.topic = topic
        self.zh = zh
        self.question = question
        self.text = question + "\n\n" + IELTSExamBank.task2Instruction
    }
}

// MARK: Timings

/// Official test conditions (IELTS Academic) and the app's own practice limits, kept apart.
struct IELTSExamTimings {
    // Official format (IEL-P03…P06).
    let part1Minutes: ClosedRange<Double> = 4...5
    let part2Minutes: ClosedRange<Double> = 3...4
    let part3Minutes: ClosedRange<Double> = 4...5
    let mockMinutes: ClosedRange<Double> = 11...14
    let part2Prep: Double = 60            // seconds
    let part2TalkMin: Double = 60         // seconds
    let part2TalkMax: Double = 120        // seconds
    let task1MinWords = 150
    let task1Minutes: Double = 20
    let task2MinWords = 250
    let task2Minutes: Double = 40
    let writingTotalMinutes: Double = 60

    // App practice limits (design choices, not official).
    let part2Limit: Double = 180          // the take stops at 3 minutes
    let part1AnswerTarget: Double = 30
    let part1AnswerLimit: Double = 90
    let part3AnswerTarget: Double = 60
    let part3AnswerLimit: Double = 120
}

// MARK: Self-check templates for the exam formats

// Same dimension ids as SelfCheckTemplate.speaking / .writing ("fc", "lr", "gra", "pr" and
// "tr", "cc", "lr", "gra"), so records from basic and exam tasks can be compared later.
// For Task 1 the "tr" slot holds Task Achievement.
extension SelfCheckTemplate {
    /// Part 2 long turn (1–2 minutes).
    static let part2: [CheckDimension] = [
        CheckDimension(id: "fc", title: "流利与连贯", en: "Fluency & Coherence",
                       questions: ["说到 1 分钟以上，接近 2 分钟", "按题卡要点往下讲，没有长时间停顿"]),
        CheckDimension(id: "lr", title: "词汇", en: "Lexical Resource",
                       questions: ["用自己的词讲细节，不只重复题卡上的词", "没有因为找词卡住"]),
        CheckDimension(id: "gra", title: "语法", en: "Grammatical Range & Accuracy",
                       questions: ["讲经历时，过去时用对了", "用了至少 2 个复合句（because / when / which）"]),
        CheckDimension(id: "pr", title: "发音", en: "Pronunciation",
                       questions: ["回听时每个词都听得清", "重音和语调自然，不像念稿"]),
    ]

    /// A whole speaking mock (Part 1–3).
    static let mock: [CheckDimension] = [
        CheckDimension(id: "fc", title: "流利与连贯", en: "Fluency & Coherence",
                       questions: ["Part 1 每题都多说了一两句，不只一句话", "Part 3 的回答给了理由或例子"]),
        CheckDimension(id: "lr", title: "词汇", en: "Lexical Resource",
                       questions: ["谈抽象话题时找得到词（原因、影响、比较）", "同一个词没有反复用"]),
        CheckDimension(id: "gra", title: "语法", en: "Grammatical Range & Accuracy",
                       questions: ["用了比较、条件或假设等不同句式", "时态和单复数基本没错"]),
        CheckDimension(id: "pr", title: "发音", en: "Pronunciation",
                       questions: ["整场回听都听得清", "语速稳定，重音和语调自然"]),
    ]

    /// Academic Writing Task 1.
    static let task1: [CheckDimension] = [
        CheckDimension(id: "tr", title: "任务完成", en: "Task Achievement",
                       questions: ["开头用自己的话改写了图表说明", "有概述，写出了最主要的趋势或对比",
                                   "用数据支持要点，数字和单位没抄错", "没有写图里没有的原因或个人观点"]),
        CheckDimension(id: "cc", title: "连贯与衔接", en: "Coherence & Cohesion",
                       questions: ["分段清楚：开头、概述、细节段", "比较和变化的衔接自然（while, whereas, by contrast）"]),
        CheckDimension(id: "lr", title: "词汇", en: "Lexical Resource",
                       questions: ["描述变化的词有变化（rise / increase / climb）", "数量和比例表达准确（per cent, a third, twice as many）"]),
        CheckDimension(id: "gra", title: "语法", en: "Grammatical Range & Accuracy",
                       questions: ["用了比较结构（higher than, the largest）", "时态和图表的时间一致", "检查过拼写和冠词"]),
    ]

    /// Academic Writing Task 2.
    static let task2: [CheckDimension] = [
        CheckDimension(id: "tr", title: "任务回应", en: "Task Response",
                       questions: ["回答了题目的每一部分", "立场清楚，从开头到结尾一致", "每个主体段都有理由和例子"]),
        CheckDimension(id: "cc", title: "连贯与衔接", en: "Coherence & Cohesion",
                       questions: ["每段一个中心意思，段首句说清楚", "衔接自然，没有堆连接词"]),
        CheckDimension(id: "lr", title: "词汇", en: "Lexical Resource",
                       questions: ["用词准确，没有为了“高级”硬换词", "检查过拼写和搭配"]),
        CheckDimension(id: "gra", title: "语法", en: "Grammatical Range & Accuracy",
                       questions: ["长句短句都有，复合句用得对", "检查过主谓一致、时态和冠词"]),
    ]
}

// MARK: Bank

enum IELTSExamBank {
    static let dataSource = "DayDayUp 原创数据，仅供练习"
    static let task1Instruction = "Summarise the information by selecting and reporting the main features, and make comparisons where relevant."
    static let task2Instruction = "Give reasons for your answer and include any relevant examples from your own knowledge or experience."
    static let timings = IELTSExamTimings()

    static func part1(_ id: String) -> Part1Set? { part1Sets.first { $0.id == id } }
    static func cueCard(_ id: String) -> CueCard? { cueCards.first { $0.id == id } }
    static func part3(for cueCardId: String) -> Part3Set? { part3Sets.first { $0.cueCardId == cueCardId } }
    static func task1(_ id: String) -> Task1Prompt? { task1Prompts.first { $0.id == id } }
    static func task2(_ id: String) -> Task2Prompt? { task2Prompts.first { $0.id == id } }

    /// "约 4–5 分钟"
    static func minutesText(_ range: ClosedRange<Double>) -> String {
        "约 \(Int(range.lowerBound))–\(Int(range.upperBound)) 分钟"
    }

    /// "p1" → "Part 1"; SpeakingWork.part values.
    static func partTitle(_ part: String) -> String {
        switch part {
        case "p1": return "Part 1"
        case "p2": return "Part 2"
        case "p3": return "Part 3"
        default: return "基础"
        }
    }

    /// Official length of one part of the speaking test.
    static func partGuide(_ part: String) -> String {
        switch part {
        case "p1": return minutesText(timings.part1Minutes)
        case "p2": return minutesText(timings.part2Minutes)
        case "p3": return minutesText(timings.part3Minutes)
        default: return ""
        }
    }

    // MARK: Part 1

    static let part1Sets: [Part1Set] = [
        Part1Set(id: "p1-home", topic: "住处", questions: [
            "Can you tell me a little about the place where you live now?",
            "What do you like most about living there?",
            "Is there anything about your home that you would like to change?",
            "Do you think you will still live there in five years' time? Why or why not?",
        ]),
        Part1Set(id: "p1-morning", topic: "早晨", questions: [
            "What time do you usually get up on a working day?",
            "What is the first thing you do after you wake up?",
            "Do you have breakfast every day? What do you usually eat?",
            "Are your mornings at the weekend different from your weekday mornings?",
        ]),
        Part1Set(id: "p1-walking", topic: "散步", questions: [
            "How often do you go for a walk?",
            "Where do you like to walk near your home?",
            "Do you prefer to walk alone or with other people?",
            "Did you walk more or less when you were a child?",
        ]),
        Part1Set(id: "p1-rain", topic: "下雨天", questions: [
            "Does it rain a lot in the place where you live?",
            "What do you usually do on a rainy day?",
            "Do you usually carry an umbrella with you?",
            "Is there anything you enjoy about rainy weather?",
        ]),
        Part1Set(id: "p1-cooking", topic: "做饭", questions: [
            "Do you cook for yourself, or does someone else usually cook for you?",
            "What is one dish that you can make well?",
            "Who taught you to cook?",
            "Would you like to take a cooking class? Why?",
        ]),
        Part1Set(id: "p1-apps", topic: "手机应用", questions: [
            "Which app on your phone do you use the most?",
            "Is there an app you deleted recently? Why did you delete it?",
            "Do you pay for any apps or online services?",
            "Do you think older people find new apps easy to use?",
        ]),
        Part1Set(id: "p1-gifts", topic: "礼物", questions: [
            "When did you last give someone a present?",
            "Do you find it easy to choose presents for other people?",
            "Do you prefer giving presents or receiving them?",
            "Is it common to give money as a present where you live?",
        ]),
        Part1Set(id: "p1-photos", topic: "拍照", questions: [
            "Do you take a lot of photos with your phone?",
            "What do you usually take photos of?",
            "Do you ever print any of your photos?",
            "Do you like being in photos yourself? Why or why not?",
        ]),
        Part1Set(id: "p1-parks", topic: "公园", questions: [
            "Is there a park near your home?",
            "What do people usually do in the parks in your city?",
            "How often did you go to a park when you were a child?",
            "What would make the parks in your area better?",
        ]),
        Part1Set(id: "p1-reading", topic: "阅读", questions: [
            "Do you read more on paper or on a screen?",
            "What was the last thing you read just for fun?",
            "Did you read a lot when you were younger?",
            "Where is your favourite place to read?",
        ]),
        Part1Set(id: "p1-plans", topic: "做计划", questions: [
            "Do you usually plan your day, or do you take things as they come?",
            "Do you write your plans down or keep them in your head?",
            "What do you do when a plan does not work out?",
            "Are you usually on time for things?",
        ]),
        Part1Set(id: "p1-colours", topic: "颜色", questions: [
            "What is your favourite colour? Has it always been the same?",
            "Are there any colours you would never wear?",
            "What colours would you choose for the walls of your bedroom?",
            "Do you think colours can change how people feel?",
        ]),
        Part1Set(id: "p1-sport", topic: "运动", questions: [
            "What kind of exercise do you do these days?",
            "Did you play any team sports at school?",
            "Do you prefer watching sport or doing it?",
            "Is there a sport you would like to try in the future?",
        ]),
        Part1Set(id: "p1-noise", topic: "噪音", questions: [
            "Is the area where you live noisy or quiet?",
            "What kinds of noise bother you the most?",
            "Can you work or study when there is noise around you?",
            "Do you think cities are getting noisier?",
        ]),
    ]

    // MARK: Part 2

    static let cueCards: [CueCard] = [
        CueCard(id: "p2-skill", topic: "技能",
                title: "Describe a practical skill you learned as an adult.",
                bullets: ["what the skill is",
                          "how you learned it",
                          "how long it took before you felt confident",
                          "and explain how this skill has been useful to you."],
                rounding: "Would you like to teach this skill to someone else?"),
        CueCard(id: "p2-helper", topic: "帮助",
                title: "Describe a time when someone you did not know helped you solve a problem.",
                bullets: ["where you were",
                          "what the problem was",
                          "what the person did",
                          "and explain how you felt about it afterwards."],
                rounding: "Have you ever helped someone you did not know in a similar way?"),
        CueCard(id: "p2-object", topic: "旧物",
                title: "Describe something old that you still keep at home.",
                bullets: ["what it is",
                          "when and how you got it",
                          "where you keep it now",
                          "and explain why you have not thrown it away."],
                rounding: "Do you usually keep old things, or do you prefer to throw them away?"),
        CueCard(id: "p2-journey", topic: "出行",
                title: "Describe a journey that did not go as planned.",
                bullets: ["where you were going",
                          "who you were with",
                          "what went wrong",
                          "and explain what you learned from the experience."],
                rounding: "Do you usually plan your trips carefully?"),
        CueCard(id: "p2-building", topic: "建筑",
                title: "Describe a building in your city that you find interesting.",
                bullets: ["where the building is",
                          "what it looks like",
                          "what it is used for",
                          "and explain why you find it interesting."],
                rounding: "Would you like to live or work in a building like this?"),
        CueCard(id: "p2-habit", topic: "习惯",
                title: "Describe a habit you changed in the last few years.",
                bullets: ["what the old habit was",
                          "why you decided to change it",
                          "how you changed it",
                          "and explain how the change has affected your life."],
                rounding: "Is there another habit you would like to change?"),
        CueCard(id: "p2-conversation", topic: "谈话",
                title: "Describe an interesting conversation you had with an older person.",
                bullets: ["who the person was",
                          "where you had the conversation",
                          "what you talked about",
                          "and explain why you found it interesting."],
                rounding: "Do you often talk with people who are much older than you?"),
        CueCard(id: "p2-app", topic: "学习工具",
                title: "Describe a website or app that helps you learn something.",
                bullets: ["what it is and what it does",
                          "how you found it",
                          "how often you use it",
                          "and explain how it has helped you."],
                rounding: "Would you recommend it to your friends?"),
        CueCard(id: "p2-outdoor", topic: "户外活动",
                title: "Describe an outdoor activity you enjoyed recently.",
                bullets: ["what the activity was",
                          "where you did it",
                          "who you did it with",
                          "and explain why you enjoyed it."],
                rounding: "Do you spend more time outdoors now than you did in the past?"),
        CueCard(id: "p2-decision", topic: "决定",
                title: "Describe a decision that took you a long time to make.",
                bullets: ["what the decision was about",
                          "what choices you had",
                          "who you asked for advice",
                          "and explain why it took you so long to decide."],
                rounding: "Do you think you made the right choice?"),
        CueCard(id: "p2-event", topic: "社区活动",
                title: "Describe a local event that brought people together.",
                bullets: ["what the event was",
                          "when and where it took place",
                          "what people did there",
                          "and explain why it brought people together."],
                rounding: "Would you like to help organise an event like this?"),
        CueCard(id: "p2-waiting", topic: "等待",
                title: "Describe something you waited a long time for.",
                bullets: ["what you were waiting for",
                          "why you had to wait",
                          "how you felt while you were waiting",
                          "and explain what happened in the end."],
                rounding: "Are you usually a patient person?"),
        CueCard(id: "p2-meal", topic: "一顿饭",
                title: "Describe a meal you enjoyed sharing with other people.",
                bullets: ["what the meal was",
                          "who you shared it with",
                          "where you had it",
                          "and explain why this meal was special to you."],
                rounding: "Do you often eat together with your family?"),
    ]

    // MARK: Part 3

    static let part3Sets: [Part3Set] = [
        Part3Set(id: "p3-skill", cueCardId: "p2-skill", questions: [
            "What practical skills should every young person learn before leaving home?",
            "Is it better to learn a skill from a teacher or by yourself from online videos?",
            "Why do some adults find it hard to learn new things?",
            "How have the skills that employers look for changed in recent years?",
            "Should schools spend more time on practical skills and less on academic subjects?",
        ]),
        Part3Set(id: "p3-helper", cueCardId: "p2-helper", questions: [
            "Why are some people more willing to help strangers than others?",
            "Do people help each other more in small towns or in big cities?",
            "How can parents teach children to be helpful?",
            "Should people be rewarded for helping others?",
            "Has technology made it easier or harder for people to help each other?",
        ]),
        Part3Set(id: "p3-object", cueCardId: "p2-object", questions: [
            "Why do people like to keep things from the past?",
            "Do you think people today buy too many things?",
            "What are the advantages of repairing things instead of replacing them?",
            "How are the things young people value different from what older people value?",
            "Should companies be required to make products that last longer?",
        ]),
        Part3Set(id: "p3-journey", cueCardId: "p2-journey", questions: [
            "What problems do people commonly face when they travel?",
            "Is it better to travel with a detailed plan or to stay flexible?",
            "How has the internet changed the way people plan their trips?",
            "Why do some people prefer to go on holiday in their own country?",
            "What can a city do to make travel easier for visitors?",
        ]),
        Part3Set(id: "p3-building", cueCardId: "p2-building", questions: [
            "Should old buildings be protected, or replaced with modern ones?",
            "What makes a building pleasant to live or work in?",
            "Why do many cities build very tall buildings?",
            "How can the buildings around us affect our mood?",
            "Who should decide what new buildings look like: architects, the government or local people?",
        ]),
        Part3Set(id: "p3-habit", cueCardId: "p2-habit", questions: [
            "Why is it difficult for people to change their habits?",
            "Which habits do children usually learn from their parents?",
            "Can technology help people build good habits?",
            "Should governments try to change unhealthy habits, for example with taxes?",
            "Are good habits more important than talent for success?",
        ]),
        Part3Set(id: "p3-conversation", cueCardId: "p2-conversation", questions: [
            "What can young people learn from older people?",
            "Why do some young and old people find it hard to understand each other?",
            "Should older people keep working after the usual retirement age?",
            "How has family life changed for older people in your country?",
            "Is face-to-face conversation becoming less common? Why?",
        ]),
        Part3Set(id: "p3-app", cueCardId: "p2-app", questions: [
            "Can online courses replace traditional classrooms?",
            "What are the disadvantages of learning mainly through a screen?",
            "How can people tell whether information online is reliable?",
            "Why do many people start online courses but never finish them?",
            "Should schools teach children how to use the internet safely?",
        ]),
        Part3Set(id: "p3-outdoor", cueCardId: "p2-outdoor", questions: [
            "Why do many children spend less time playing outside than in the past?",
            "What can cities do to encourage people to exercise outdoors?",
            "Are outdoor activities better for mental health than indoor ones?",
            "Should schools take students out of the classroom more often?",
            "How does the weather affect the activities people choose?",
        ]),
        Part3Set(id: "p3-decision", cueCardId: "p2-decision", questions: [
            "What kinds of decisions do young people find hardest to make?",
            "Is it a good idea to ask many people for advice before deciding?",
            "Why do some people avoid making decisions?",
            "Should parents make important decisions for their teenage children?",
            "Do people make better decisions when they have more choices?",
        ]),
        Part3Set(id: "p3-event", cueCardId: "p2-event", questions: [
            "Why are local events important for a community?",
            "Who should pay for public events: the local government or the people who attend?",
            "How are celebrations in cities different from those in the countryside?",
            "Do large events such as music festivals bring more benefits or more problems to a city?",
            "Has social media changed the way people take part in local events?",
        ]),
        Part3Set(id: "p3-waiting", cueCardId: "p2-waiting", questions: [
            "In what situations do people have to wait in daily life?",
            "Are people today less patient than people in the past? Why?",
            "How can businesses make waiting less unpleasant for customers?",
            "Is patience something people are born with, or can it be learned?",
            "Why do some people enjoy things more when they have waited for them?",
        ]),
        Part3Set(id: "p3-meal", cueCardId: "p2-meal", questions: [
            "Why do families eat together less often than they used to?",
            "How has the way people eat changed in your country?",
            "Should schools teach children how to cook?",
            "How have food delivery apps changed people's eating habits?",
            "Will traditional dishes still be popular in the future?",
        ]),
    ]

    // MARK: Task 1

    static let task1Prompts: [Task1Prompt] = [
        Task1Prompt(
            id: "t1-bikes", kind: .line, zh: "三个城区的共享单车日均租用量",
            heading: "Average daily bike rentals by district, 2016–2024",
            lead: "The graph below shows the average number of bicycles rented per day from a public bike-sharing scheme in three districts of a city between 2016 and 2024.",
            unit: "bikes per day", xAxis: "Year",
            series: [
                Task1Series("Riverside", labels: ["2016", "2018", "2020", "2022", "2024"],
                            values: [1200, 1650, 1400, 2300, 2900]),
                Task1Series("Old Town", labels: ["2016", "2018", "2020", "2022", "2024"],
                            values: [2100, 2250, 1500, 1900, 2000]),
                Task1Series("Hillside", labels: ["2016", "2018", "2020", "2022", "2024"],
                            values: [300, 450, 500, 800, 1350]),
            ]),
        Task1Prompt(
            id: "t1-electricity", kind: .line, zh: "两座城市家庭每月用电量",
            heading: "Average monthly electricity use per household, 2025",
            lead: "The graph below shows the average amount of electricity used each month by one household in two cities, Northport and Southbay, in 2025.",
            unit: "kWh", xAxis: "Month",
            series: [
                Task1Series("Northport", labels: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"],
                            values: [520, 480, 410, 330, 280, 260, 270, 275, 300, 360, 440, 510]),
                Task1Series("Southbay", labels: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"],
                            values: [250, 245, 265, 300, 380, 470, 540, 530, 450, 340, 280, 260]),
            ]),
        Task1Prompt(
            id: "t1-reading", kind: .bar, zh: "四个年龄组每周的阅读时间",
            heading: "Average weekly reading time by age group, 2025",
            lead: "The chart below shows the average number of hours per week that people in four age groups in one country spent reading printed books, e-books and online articles in 2025.",
            unit: "hours per week", xAxis: "Age group",
            series: [
                Task1Series("Printed books", labels: ["16–24", "25–39", "40–59", "60+"], values: [1.2, 1.5, 2.4, 3.8]),
                Task1Series("E-books", labels: ["16–24", "25–39", "40–59", "60+"], values: [1.8, 2.2, 1.4, 0.6]),
                Task1Series("Online articles", labels: ["16–24", "25–39", "40–59", "60+"], values: [4.5, 3.9, 2.8, 1.5]),
            ]),
        Task1Prompt(
            id: "t1-commute", kind: .bar, zh: "一家公司员工上班的方式",
            heading: "Main way employees got to work, 2015 and 2025",
            lead: "The chart below shows the main way that the employees of one company got to work in 2015 and 2025, including those who worked from home.",
            unit: "% of employees", xAxis: "Way of getting to work",
            series: [
                Task1Series("2015", labels: ["Car", "Bus", "Metro", "Bicycle", "On foot", "Home working"],
                            values: [42, 21, 18, 6, 9, 4]),
                Task1Series("2025", labels: ["Car", "Bus", "Metro", "Bicycle", "On foot", "Home working"],
                            values: [28, 14, 25, 11, 8, 14]),
            ]),
        Task1Prompt(
            id: "t1-water", kind: .pie, zh: "家庭用水的去向",
            heading: "How water was used in an average home, 2005 and 2025",
            lead: "The pie charts below show how water was used in an average home in one city in 2005 and 2025.",
            unit: "%",
            series: [
                Task1Series("2005", labels: ["Showers and baths", "Toilets", "Washing machine", "Kitchen and drinking", "Garden", "Other"],
                            values: [30, 28, 16, 10, 12, 4]),
                Task1Series("2025", labels: ["Showers and baths", "Toilets", "Washing machine", "Kitchen and drinking", "Garden", "Other"],
                            values: [37, 21, 13, 14, 9, 6]),
            ]),
        Task1Prompt(
            id: "t1-timeuse", kind: .table, zh: "成年人每天花在五项活动上的时间",
            heading: "Average time adults spent on five activities (minutes per day)",
            lead: "The table below shows the average number of minutes per day that adults in one country spent on five activities in 2005, 2015 and 2025.",
            unit: "minutes per day", xAxis: "Activity",
            series: [
                Task1Series("Cooking", labels: ["2005", "2015", "2025"], values: [52, 44, 38]),
                Task1Series("Commuting", labels: ["2005", "2015", "2025"], values: [41, 48, 36]),
                Task1Series("Exercise", labels: ["2005", "2015", "2025"], values: [18, 22, 29]),
                Task1Series("Watching TV", labels: ["2005", "2015", "2025"], values: [146, 128, 94]),
                Task1Series("Using social media", labels: ["2005", "2015", "2025"], values: [5, 58, 102]),
            ]),
        Task1Prompt(
            id: "t1-bakery", kind: .process, zh: "面包房每天早上做面包和送货",
            heading: "Making and delivering bread at a city bakery",
            lead: "The diagram below shows how a small bakery in a city makes fresh bread and delivers it to shops every morning.",
            steps: [
                "Delivery of flour, water, yeast and salt (the day before)",
                "Weighing, then mixing into dough by machine (15 minutes)",
                "Rising in a warm room (about 2 hours)",
                "Cutting and shaping into loaves by hand",
                "Baking in a large oven (230°C, 35 minutes)",
                "Cooling on racks (1 hour)",
                "Packing in paper bags",
                "Delivery to local shops by electric van (before 7 am)",
            ]),
        Task1Prompt(
            id: "t1-rainwater", kind: .process, zh: "一所学校收集和使用雨水",
            heading: "Rainwater collection at a school",
            lead: "The diagram below shows how a school collects rainwater and uses it.",
            steps: [
                "Rain falls on the school roof",
                "Gutters carry the water to a downpipe",
                "A filter removes leaves and dirt",
                "Storage in an underground tank (20,000 litres); extra water goes to the street drain when the tank is full",
                "A pump lifts the water to a small tank on the roof",
                "Use: flushing toilets and watering the school garden",
            ]),
    ]

    // MARK: Task 2

    static let task2Prompts: [Task2Prompt] = [
        Task2Prompt(id: "t2-cashless", type: .advantages, topic: "科技", zh: "无现金支付",
                    question: "In many places, people can now pay for almost everything with a phone or a card, and some shops no longer accept cash.\n\nDo the advantages of this development outweigh the disadvantages?"),
        Task2Prompt(id: "t2-foodwaste", type: .problemSolution, topic: "环境", zh: "食物浪费",
                    question: "In many cities, shops, restaurants and households throw away large amounts of food that could still be eaten.\n\nWhat are the causes of this problem, and what could be done to reduce it?"),
        Task2Prompt(id: "t2-subjects", type: .discussion, topic: "教育", zh: "按收入还是按兴趣选专业",
                    question: "Some people think university students should choose subjects that lead to well-paid jobs. Others believe students should study the subjects they enjoy most.\n\nDiscuss both these views and give your own opinion."),
        Task2Prompt(id: "t2-healthyfood", type: .opinion, topic: "健康", zh: "让健康食品比不健康食品便宜",
                    question: "Some people say that the most effective way to improve public health is to make healthy food cheaper than unhealthy food.\n\nTo what extent do you agree or disagree?"),
        Task2Prompt(id: "t2-employers", type: .twoPart, topic: "工作", zh: "一生为多家雇主工作",
                    question: "These days, many people work for several different employers during their career instead of staying with one company for a long time.\n\nWhy is this happening? Is it a positive or a negative development?"),
        Task2Prompt(id: "t2-firstaid", type: .opinion, topic: "政府", zh: "成年人必须上急救课",
                    question: "Some people believe that every adult should be required by law to complete a basic first-aid course.\n\nTo what extent do you agree or disagree?"),
        Task2Prompt(id: "t2-secondhand", type: .twoPart, topic: "经济", zh: "网上二手交易流行",
                    question: "Buying and selling second-hand clothes, furniture and electronics online is becoming more and more popular.\n\nWhy is this happening? Do you think it is a positive trend?"),
        Task2Prompt(id: "t2-parents", type: .advantages, topic: "社会", zh: "年轻人成年后仍与父母同住",
                    question: "In some countries, more young adults are living with their parents until their late twenties or early thirties.\n\nWhat are the advantages and disadvantages of this situation?"),
        Task2Prompt(id: "t2-museums", type: .discussion, topic: "文化", zh: "博物馆展本国的还是全世界的",
                    question: "Some people believe that museums should mainly show the history and art of their own country. Others think museums should show works from all over the world.\n\nDiscuss both these views and give your own opinion."),
        Task2Prompt(id: "t2-onlineinfo", type: .problemSolution, topic: "媒体", zh: "网上信息真假难辨",
                    question: "Many people find it hard to judge whether the news and information they see online is accurate.\n\nWhat problems does this cause, and what can be done to help people judge information more carefully?"),
        Task2Prompt(id: "t2-translation", type: .opinion, topic: "国际", zh: "有了翻译软件还要学外语吗",
                    question: "Some people think that learning a foreign language is no longer necessary because translation apps are now so good.\n\nTo what extent do you agree or disagree?"),
        Task2Prompt(id: "t2-carfree", type: .discussion, topic: "交通", zh: "市中心禁止私家车",
                    question: "Some people argue that city centres should be closed to private cars. Others believe this would harm local businesses and people who need to drive.\n\nDiscuss both these views and give your own opinion."),
        Task2Prompt(id: "t2-sitting", type: .problemSolution, topic: "健康", zh: "办公室久坐",
                    question: "Many office workers now spend most of the day sitting at a desk.\n\nWhat health problems can this cause, and what can employers and workers do about them?"),
    ]
}
