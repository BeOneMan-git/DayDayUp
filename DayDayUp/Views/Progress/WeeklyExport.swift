import SwiftUI
import UIKit

// RPT-01 / MET-P03 / PLAT-12: one week's facts, shown on screen and exported as JSON, CSV or a PDF print
// view. All three are built from the same Metrics.WeeklyReport, so the numbers always agree (ACC-30).
// Exports contain counts and app texts only: no recordings, no article text, nothing the learner wrote.

/// One section of the weekly report, as lines of plain text.
struct WeeklySection: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let lines: [String]
    let flag: String?      // "样本少（3 次）" …
    let note: String?      // how it is counted
}

/// Everything one weekly report shows or exports, computed once from the stores.
@MainActor
struct WeeklyData {
    let week: String                            // Monday
    let weekEnd: String                         // Sunday
    let report: Metrics.WeeklyReport
    let plannedByCat: [StudyCategory: Int]      // task minutes of the week's plans (deferred ones not counted)
    let recordsStartLater: Bool                 // no activity record existed yet by the end of this week
    let inProgress: Bool                        // the week has not ended

    static func make(week: String, study: StudyStore, vocab: VocabStore, practice: PracticeStore,
                     packs: PackStore, now: Date = Date()) -> WeeklyData {
        let inputs = Metrics.WeeklyInputs(
            monday: week, now: now, plans: study.state.plans, activity: study.activity,
            vocabDays: vocab.state.days, vocabEvents: vocab.events, quizzes: study.state.quizResults,
            titles: ProgressTitles.map(packs), practice: practice.state,
            retracted: Set(study.state.retractedIssues),
            questionText: { kind, dim, question in IssueText.line(kind: kind, dim: dim, question: question) })
        let report = Metrics.weekly(inputs)
        var planned: [StudyCategory: Int] = [:]
        for day in Metrics.weekDays(week) {
            for task in study.state.plans[day]?.tasks ?? [] where task.state != .deferred {
                planned[task.cat, default: 0] += task.minutes
            }
        }
        let weekEnd = DayKey.adding(6, to: week)
        let firstRecord = study.activity.map { $0.day }.min()
        return WeeklyData(week: week, weekEnd: weekEnd, report: report, plannedByCat: planned,
                          recordsStartLater: firstRecord.map { $0 > weekEnd } ?? true,
                          inProgress: weekEnd >= DayKey.today)
    }

    // MARK: Sections (screen and PDF)

    var sections: [WeeklySection] {
        [timeSection, vocabSection, quizSection, outputSection, issueSection, focusSection, notesSection]
    }

    private var timeSection: WeeklySection {
        let r = report
        let hasPlan = r.plannedMinutes > 0
        var lines: [String] = []
        for cat in StudyCategory.allCases {
            let actual = ProgressFormat.whole(r.actualMinutes[cat.rawValue] ?? 0)
            if hasPlan {
                lines.append("\(cat.title)：计划 \(plannedByCat[cat] ?? 0) 分钟 · 实际 \(actual) 分钟")
            } else {
                lines.append("\(cat.title)：实际 \(actual) 分钟")
            }
        }
        let planText = hasPlan ? "计划 \(r.plannedMinutes) 分钟" : "这周没有计划"
        lines.append("合计：" + planText + " · 有效练习 \(ProgressFormat.whole(r.totalMinutes)) 分钟")
        lines.append("后台播放 \(ProgressFormat.whole(r.backgroundMinutes)) 分钟，不计入")
        lines.append("学习天数：\(r.studyDays) / 7 天（有效练习满 1 分钟）")
        if r.totalMinutes == 0 && recordsStartLater {
            lines.append("App 从 V0.5 开始记录练习时间，这周在那之前，所以没有时间记录。")
        }
        return WeeklySection(id: "time", title: "时间", symbol: "clock", lines: lines, flag: nil,
                             note: "计划合计是每天的预算相加；分类计划是当天任务的分钟数相加（暂缓的任务算在第二天）。同一时间段只算一次，所以分类相加可能比合计多。")
    }

    private var vocabSection: WeeklySection {
        let r = report
        var lines = ["每天开始时的到期卡（7 天相加）：\(r.vocabDueAtStart) 张",
                     "复习次数：\(r.vocabReviews) 次（撤回的不算）"]
        let recall = recallRows
        if recall.isEmpty {
            lines.append("隔日回忆：这周没有符合条件的复习。")
        }
        for row in recall {
            var text = "隔日回忆·\(row.task.title)：成功 \(row.successes) / 尝试 \(row.attempts)"
            if row.attempts >= Metrics.recallMinimum {
                text += " · 成功率 " + String(ProgressFormat.percent(row.successes, row.attempts)) + "%"
            } else {
                text += " · 证据不足"
            }
            lines.append(text)
        }
        return WeeklySection(id: "vocab", title: "词汇", symbol: "character.book.closed", lines: lines, flag: nil,
                             note: "隔日回忆只算距离上次复习至少 24 小时的当天第一次作答；少于 30 次不算百分比。")
    }

    private var quizSection: WeeklySection {
        let quizzes = report.quizzes
        let lines = quizzes.isEmpty ? ["这周没有做理解题。"] : quizzes
        let flag: String? = quizzes.isEmpty || quizzes.count >= Metrics.smallSample ? nil : "样本少（\(quizzes.count) 次）"
        return WeeklySection(id: "quiz", title: "文章理解", symbol: "doc.text.magnifyingglass", lines: lines,
                             flag: flag, note: "只数答对的题数，不换算成分数。")
    }

    private var outputSection: WeeklySection {
        let r = report
        let lines = ["口语作品：\(r.speakingWorks) 个", "写作作品：\(r.writingWorks) 篇",
                     "独立完成：\(r.independentWorks) 个"]
        return WeeklySection(id: "output", title: "说写", symbol: "text.bubble", lines: lines, flag: nil,
                             note: "口语只算有声音的录音；写作算这周完成过一版的作品。“独立”指没看参考、没看反馈就完成。")
    }

    private var issueSection: WeeklySection {
        let lines = report.issues.isEmpty ? ["没有至少两次没勾的点。"] : report.issues
        return WeeklySection(id: "issues", title: "问题", symbol: "exclamationmark.bubble", lines: lines, flag: nil,
                             note: "来自你自己的自评：从这周一往前 3 周起，到生成周报时为止；只列前 3 个，撤回的不列。")
    }

    private var focusSection: WeeklySection {
        let lines = report.focuses.isEmpty ? ["没有需要特别调整的地方。"] : report.focuses
        return WeeklySection(id: "focus", title: "下周重点", symbol: "scope", lines: lines, flag: nil,
                             note: "最多 3 条，只根据上面的记录；没有依据就不写。")
    }

    private var notesSection: WeeklySection {
        let lines = report.notes.isEmpty ? ["没有。"] : report.notes
        return WeeklySection(id: "notes", title: "说明", symbol: "note.text", lines: lines, flag: nil, note: nil)
    }

    private struct RecallRow {
        let task: VocabTask
        let successes: Int
        let attempts: Int
    }

    private var recallRows: [RecallRow] {
        VocabTask.allCases.compactMap { task in
            guard let pair = report.delayedRecall[task.rawValue], pair.count == 2 else { return nil }
            return RecallRow(task: task, successes: pair[0], attempts: pair[1])
        }
    }

    var headerLines: [String] {
        var lines = [week + " 至 " + weekEnd + " · 生成于 " + ProgressFormat.dayTime(report.generated),
                     "这里只描述练习记录，不是成绩，也不预测考试分数。"]
        if inProgress {
            lines.append("这周还没结束，数字只到生成的时候。")
        }
        return lines
    }

    // MARK: CSV

    /// UTF-8 with a byte-order mark, header "项目,数值", one row per number or line.
    var csvText: String {
        let r = report
        var rows: [(String, String)] = [("项目", "数值")]
        rows.append(("周", week + " 至 " + weekEnd))
        rows.append(("生成时间", ISO8601DateFormatter().string(from: r.generated)))
        rows.append(("计划合计（分钟，每天预算相加）", "\(r.plannedMinutes)"))
        rows.append(("有效练习合计（分钟，同一时间段只算一次）", "\(ProgressFormat.whole(r.totalMinutes))"))
        for cat in StudyCategory.allCases {
            rows.append(("\(cat.title)·实际（分钟）", "\(ProgressFormat.whole(r.actualMinutes[cat.rawValue] ?? 0))"))
            rows.append(("\(cat.title)·计划（分钟）", "\(plannedByCat[cat] ?? 0)"))
        }
        rows.append(("后台播放（分钟，不计入）", "\(ProgressFormat.whole(r.backgroundMinutes))"))
        rows.append(("学习天数", "\(r.studyDays)"))
        rows.append(("词汇·每天开始时到期（7 天相加）", "\(r.vocabDueAtStart)"))
        rows.append(("词汇·复习次数", "\(r.vocabReviews)"))
        for row in recallRows {
            rows.append(("隔日回忆·\(row.task.title)（成功 / 尝试）", "\(row.successes) / \(row.attempts)"))
        }
        for (i, line) in r.quizzes.enumerated() {
            rows.append(("理解题 \(i + 1)", line))
        }
        rows.append(("口语作品", "\(r.speakingWorks)"))
        rows.append(("写作作品", "\(r.writingWorks)"))
        rows.append(("独立完成的作品", "\(r.independentWorks)"))
        for (i, line) in r.issues.enumerated() {
            rows.append(("问题 \(i + 1)", line))
        }
        for (i, line) in r.focuses.enumerated() {
            rows.append(("下周重点 \(i + 1)", line))
        }
        for (i, line) in r.notes.enumerated() {
            rows.append(("说明 \(i + 1)", line))
        }
        let body = rows.map { WeeklyData.csvField($0.0) + "," + WeeklyData.csvField($0.1) }
        return "\u{FEFF}" + body.joined(separator: "\r\n") + "\r\n"
    }

    /// Quotes a field that holds a comma, a quote or a line break.
    nonisolated static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: JSON

    func jsonData() throws -> Data {
        var planned: [String: Int] = [:]
        for (cat, minutes) in plannedByCat {
            planned[cat.rawValue] = minutes
        }
        let file = WeeklyExportFile(app: "DayDayUp", kind: "weekly-report", week: week, weekEnd: weekEnd,
                                    report: report, plannedMinutesByCategory: planned,
                                    notIncluded: WeeklyExport.excluded)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }

    // MARK: PDF

    var printBlocks: [WeeklyPrintBlock] {
        var blocks = [WeeklyPrintBlock(title: "DayDayUp 周报 " + ProgressFormat.weekRange(week), lines: headerLines,
                                       note: nil, large: true)]
        for section in sections {
            var lines = section.lines
            if let flag = section.flag {
                lines.append("※ " + flag)
            }
            blocks.append(WeeklyPrintBlock(title: section.title, lines: lines, note: section.note, large: false))
        }
        blocks.append(WeeklyPrintBlock(title: nil,
                                       lines: ["不包含：" + WeeklyExport.excluded.joined(separator: "、") + "。",
                                               "这个文件由 DayDayUp 在这台 iPad 上生成，App 不会自动发送。"],
                                       note: nil, large: false))
        return blocks
    }
}

/// The JSON file: the report as computed, plus the planned minutes per category and what is left out.
private struct WeeklyExportFile: Codable {
    var app: String
    var kind: String
    var week: String
    var weekEnd: String
    var report: Metrics.WeeklyReport
    var plannedMinutesByCategory: [String: Int]
    var notIncluded: [String]
}

enum WeeklyExportFormat: String, CaseIterable, Identifiable {
    case json, csv, pdf

    var id: String { rawValue }

    var fileExtension: String { rawValue }

    var buttonTitle: String {
        switch self {
        case .json: return "导出 JSON"
        case .csv: return "导出 CSV"
        case .pdf: return "打印视图（PDF）"
        }
    }

    var symbol: String {
        switch self {
        case .json: return "curlybraces"
        case .csv: return "tablecells"
        case .pdf: return "printer"
        }
    }

    var detail: String {
        switch self {
        case .json: return "JSON（一种数据文件）：给程序或 Claude 读，数字最完整。"
        case .csv: return "CSV（表格文件）：可以用 Numbers 或 Excel 打开，一行一个数字或一句话。"
        case .pdf: return "PDF（打印文件）：A4 纸大小，黑字白底，可以打印或存档。"
        }
    }
}

enum WeeklyExportError: LocalizedError {
    case pdf

    var errorDescription: String? {
        switch self {
        case .pdf: return "PDF 文件没有生成。"
        }
    }
}

/// Writes the chosen file into the temporary folder. Nothing is sent anywhere: the learner shares it.
@MainActor
enum WeeklyExport {
    /// PLAT-12: said before every export.
    static let included = ["日期", "分钟数", "复习次数", "回忆成功数 / 尝试数", "理解题得分和文章标题", "说写作品数量",
                           "自评问题的文字（App 的题目，不是你写的内容）"]
    static let excluded = ["录音", "文章原文", "你写的文字（作文、笔记、反馈内容）"]

    static func fileName(week: String, format: WeeklyExportFormat) -> String {
        "DayDayUp-周报-\(week).\(format.fileExtension)"
    }

    static func write(_ data: WeeklyData, as format: WeeklyExportFormat) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName(week: data.week, format: format))
        try? FileManager.default.removeItem(at: url)
        switch format {
        case .json:
            try data.jsonData().write(to: url, options: .atomic)
        case .csv:
            try Data(data.csvText.utf8).write(to: url, options: .atomic)
        case .pdf:
            try WeeklyPDF.write(data.printBlocks, to: url)
        }
        return url
    }
}

// MARK: Print view

/// One block of the A4 print view: black on white, fixed print sizes.
struct WeeklyPrintBlock: View {
    let title: String?
    let lines: [String]
    let note: String?
    let large: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title)
                    .font(.system(size: large ? 20 : 13, weight: .semibold))
                    .padding(.bottom, 2)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { item in
                Text(item.element)
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note {
                Text(note)
                    .font(.system(size: 9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(Color.black)
        .frame(width: WeeklyPDF.contentWidth, alignment: .leading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

/// Renders the blocks with ImageRenderer into an A4 PDF (vector text). A block that does not fit on the
/// current page starts a new one; a block taller than a page is cut across pages.
@MainActor
enum WeeklyPDF {
    static let pageSize = CGSize(width: 595.28, height: 841.89)   // A4 portrait in points
    static let margin: CGFloat = 48
    static let gap: CGFloat = 14
    static let contentWidth: CGFloat = 595.28 - 48 * 2

    static func write(_ blocks: [WeeklyPrintBlock], to url: URL) throws {
        var box = CGRect(origin: .zero, size: pageSize)
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { throw WeeklyExportError.pdf }
        let usable = pageSize.height - margin * 2
        let top = pageSize.height - margin
        var used: CGFloat = 0
        var pageOpen = false
        for block in blocks {
            let renderer = ImageRenderer(content: block)
            renderer.proposedSize = ProposedViewSize(width: contentWidth, height: nil)
            renderer.render { size, draw in
                if size.height > usable {
                    // Taller than one page: cut it into page-sized slices.
                    if pageOpen {
                        pdf.endPDFPage()
                        pageOpen = false
                    }
                    var offset: CGFloat = 0
                    while offset < size.height {
                        pdf.beginPDFPage(nil)
                        pdf.saveGState()
                        pdf.clip(to: CGRect(x: margin, y: margin, width: contentWidth, height: usable))
                        pdf.translateBy(x: margin, y: top - size.height + offset)
                        draw(pdf)
                        pdf.restoreGState()
                        pdf.endPDFPage()
                        offset += usable
                    }
                    used = 0
                    return
                }
                if pageOpen && used + size.height > usable {
                    pdf.endPDFPage()
                    pageOpen = false
                }
                if !pageOpen {
                    pdf.beginPDFPage(nil)
                    pageOpen = true
                    used = 0
                }
                pdf.saveGState()
                pdf.translateBy(x: margin, y: top - used - size.height)
                draw(pdf)
                pdf.restoreGState()
                used += size.height + gap
            }
        }
        if pageOpen {
            pdf.endPDFPage()
        }
        pdf.closePDF()
    }
}
