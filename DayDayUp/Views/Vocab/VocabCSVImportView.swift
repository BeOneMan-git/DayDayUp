import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// 从 CSV 导入旧生词 (IMP-F08): pick a file → preview → choose columns → check every row → import.
/// The old "认识" mark is kept as history only: it never counts as mastered and gets no review card.
struct VocabCSVImportView: View {
    @Environment(VocabStore.self) private var vocab

    @State private var showImporter = false
    @State private var fileName: String? = nil
    @State private var encodingName = ""
    @State private var table: CSVTable? = nil
    @State private var readError: String? = nil
    @State private var wordColumn: Int? = nil
    @State private var meaningColumn: Int? = nil
    @State private var sentenceColumn: Int? = nil
    @State private var knownColumn: Int? = nil
    @State private var createCards = true
    @State private var trialOnly = false
    @State private var resultMessage: String? = nil

    var body: some View {
        Form {
            Section {
                Text("旧的“认识”只作历史记录，不会当成已掌握，也不建复习卡。")
                Button {
                    showImporter = true
                } label: {
                    Label(table == nil ? "选择 CSV 文件" : "换一个文件", systemImage: "doc.badge.plus")
                }
                if let fileName, let table {
                    Text(fileInfo(fileName, table))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let readError {
                    Label(readError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.warn)
                }
            } header: {
                Text("文件")
            } footer: {
                Text("可以是逗号、分号或 Tab 分隔；编码 UTF-8 或 GB18030（中文版 Excel 常用）。第一行像表头时，当表头用。")
            }

            if let table {
                previewSection(table)
                columnSection(table)
                optionsSection
                let candidates = CSVImportPlan.candidates(table, mapping: mapping, existing: vocab.existingTexts)
                checkSection(VocabCSVCounts(candidates))
                importSection(candidates)
                rowsSection(candidates)
            }

            if let resultMessage {
                Section {
                    Label(resultMessage, systemImage: "checkmark.circle")
                }
            }
        }
        .navigationTitle("从 CSV 导入")
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .utf8PlainText],
                      allowsMultipleSelection: false) { result in
            handlePick(result)
        }
    }

    // MARK: Sections

    private func previewSection(_ table: CSVTable) -> some View {
        let sample = Array(table.rows.prefix(10))
        let columns = columnCount(table)
        return Section {
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        ForEach(0..<columns, id: \.self) { c in
                            Text(columnName(table, c))
                                .font(.caption.weight(.semibold))
                        }
                    }
                    Divider()
                    ForEach(Array(sample.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(0..<columns, id: \.self) { c in
                                Text(c < row.count ? row[c] : "")
                                    .font(.caption)
                                    .lineLimit(2)
                                    .frame(maxWidth: 220, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("预览（前 \(sample.count) 行）")
        }
    }

    private func columnSection(_ table: CSVTable) -> some View {
        let count = columnCount(table)
        return Section {
            columnPicker("词", selection: $wordColumn, table: table, count: count)
            columnPicker("释义", selection: $meaningColumn, table: table, count: count)
            columnPicker("来源句", selection: $sentenceColumn, table: table, count: count)
            columnPicker("认识", selection: $knownColumn, table: table, count: count)
        } header: {
            Text("每一列是什么")
        } footer: {
            Text("来源句会存进备注：它没有原文音频，也不能“回到原文”。“认识”列写 1、yes、是、认识、√ 等，算旧标记。")
        }
    }

    private func columnPicker(_ title: String, selection: Binding<Int?>, table: CSVTable, count: Int) -> some View {
        Picker(title, selection: selection) {
            Text("不用").tag(Int?.none)
            ForEach(0..<count, id: \.self) { c in
                Text(columnName(table, c)).tag(Optional(c))
            }
        }
    }

    private var optionsSection: some View {
        Section {
            Toggle("为新词建认义复习卡", isOn: $createCards)
            Toggle("先只导入前 5 条试试", isOn: $trialOnly)
        } header: {
            Text("导入方式")
        } footer: {
            Text("不建卡时，词只进词汇列表，以后可以在词条里打开题型。带“认识”旧标记的词，怎样都不建卡。")
        }
    }

    private func checkSection(_ counts: VocabCSVCounts) -> some View {
        Section {
            LabeledContent("可导入", value: "\(counts.ok) 条")
            LabeledContent("空词", value: "\(counts.empty) 条")
            LabeledContent("文件内重复", value: "\(counts.duplicate) 条")
            LabeledContent("已收藏", value: "\(counts.saved) 条")
            LabeledContent("太长", value: "\(counts.tooLong) 条")
        } header: {
            Text("检查结果")
        } footer: {
            Text("只导入“可导入”的行。“已收藏”是词汇里已经有的词或词群，不会重复添加。超过 60 个字符算太长。")
        }
    }

    private func importSection(_ candidates: [CSVCandidate]) -> some View {
        let importable = candidates.filter { $0.importable }
        let rows = trialOnly ? Array(importable.prefix(5)) : importable
        let knownCount = rows.filter { $0.known }.count
        let title: String = rows.isEmpty ? "没有可导入的行" : "确认导入 \(rows.count) 条"
        return Section {
            Button {
                runImport(rows, knownCount: knownCount)
            } label: {
                Label(title, systemImage: "square.and.arrow.down")
            }
            .disabled(rows.isEmpty)
            if wordColumn == nil {
                Text("先选“词”在哪一列。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            if knownCount > 0 {
                Text("其中 \(knownCount) 条带“认识”旧标记：只记历史，不建复习卡。")
            }
        }
    }

    private func rowsSection(_ candidates: [CSVCandidate]) -> some View {
        Section {
            ForEach(candidates) { c in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("第 \(c.row) 行")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 56, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.word.isEmpty ? "（空）" : c.word)
                            .font(.body.weight(.semibold))
                        if !c.meaning.isEmpty {
                            Text(c.meaning)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if c.known {
                            Text("旧标记：认识（只作历史）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    statusBadge(c.status)
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("逐行（共 \(candidates.count) 行）")
        }
    }

    private func statusBadge(_ status: CSVCandidate.Status) -> Badge {
        switch status {
        case .ok: return Badge(text: "可导入", color: Theme.level5)
        case .emptyWord: return Badge(text: "空词", outlined: true)
        case .duplicateInFile(let first): return Badge(text: "文件内重复（同第 \(first) 行）", outlined: true)
        case .alreadySaved: return Badge(text: "已收藏", outlined: true)
        case .tooLong: return Badge(text: "太长", outlined: true)
        }
    }

    // MARK: Helpers

    private var mapping: CSVImportPlan.Mapping {
        CSVImportPlan.Mapping(word: wordColumn, meaning: meaningColumn, sentence: sentenceColumn, known: knownColumn)
    }

    /// Header columns, or more when some rows are longer than the header.
    private func columnCount(_ table: CSVTable) -> Int {
        max(table.header.count, table.rows.map { $0.count }.max() ?? 0)
    }

    private func columnName(_ table: CSVTable, _ c: Int) -> String {
        if c < table.header.count, !table.header[c].isEmpty { return table.header[c] }
        return "第 \(c + 1) 列"
    }

    private func fileInfo(_ name: String, _ table: CSVTable) -> String {
        "\(name) · \(table.rows.count) 行 · \(delimiterName(table.delimiter)) · \(encodingName)"
    }

    private func delimiterName(_ d: Character) -> String {
        switch d {
        case ",": return "逗号分隔"
        case ";": return "分号分隔"
        case "\t": return "Tab 分隔"
        default: return "分隔符 \(d)"
        }
    }

    private func runImport(_ rows: [CSVCandidate], knownCount: Int) {
        let n = vocab.importCSV(rows, createCards: createCards)
        var parts = ["已导入 \(n) 条。"]
        if createCards && n > knownCount {
            parts.append("新词建了“认义”复习卡，会按每天的新任务上限慢慢排进来。")
        }
        if knownCount > 0 {
            parts.append("其中 \(knownCount) 条带“认识”旧标记，只记历史，没有建复习卡。")
        }
        resultMessage = parts.joined()
    }

    private func handlePick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            load(url)
        case .failure(let error):
            readError = "没有打开文件：\(error.localizedDescription)"
        }
    }

    private func load(_ url: URL) {
        resultMessage = nil
        readError = nil
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            table = nil
            readError = "读不了这个文件：\(error.localizedDescription)"
            return
        }
        guard let decoded = VocabCSVImportView.decode(data) else {
            table = nil
            readError = "读不出这个文件的文字。请在 Excel 里另存为“CSV UTF-8”再试。"
            return
        }
        let parsed = CSVTable.parse(decoded.text)
        guard !parsed.rows.isEmpty else {
            table = nil
            readError = "文件里没有数据行。"
            return
        }
        fileName = url.lastPathComponent
        encodingName = decoded.encoding
        table = parsed
        let guessedWord = parsed.guessColumn(["word", "单词", "词"])
        wordColumn = guessedWord ?? 0
        meaningColumn = parsed.guessColumn(["meaning", "释义", "中文"])
            ?? (guessedWord == nil && columnCount(parsed) > 1 ? 1 : nil)
        sentenceColumn = parsed.guessColumn(["sentence", "例句", "来源"])
        knownColumn = parsed.guessColumn(["known", "认识", "状态"])
        DiagLog.shared.log("vocab", "CSV preview: \(parsed.rows.count) rows, \(decoded.encoding)")
    }

    /// UTF-16 when the file starts with its byte-order mark, then UTF-8, then GB18030.
    private static func decode(_ data: Data) -> (text: String, encoding: String)? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) {
            return (text, "UTF-16")
        }
        if let text = String(data: data, encoding: .utf8) {
            return (text, "UTF-8")
        }
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        if let text = String(data: data, encoding: gb18030) {
            return (text, "GB18030")
        }
        return nil
    }
}

/// Rows per check result.
private struct VocabCSVCounts {
    var ok = 0
    var empty = 0
    var duplicate = 0
    var saved = 0
    var tooLong = 0

    init(_ list: [CSVCandidate]) {
        for c in list {
            switch c.status {
            case .ok: ok += 1
            case .emptyWord: empty += 1
            case .duplicateInFile: duplicate += 1
            case .alreadySaved: saved += 1
            case .tooLong: tooLong += 1
            }
        }
    }
}
