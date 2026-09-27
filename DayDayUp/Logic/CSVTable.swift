import Foundation

/// A small CSV reader for the old web word list (IMP-F08): quotes, commas or semicolons or tabs,
/// CRLF, a UTF-8 byte-order mark. The first row is taken as a header when it looks like one.
struct CSVTable: Equatable {
    var header: [String]
    var rows: [[String]]
    var delimiter: Character

    static func parse(_ raw: String) -> CSVTable {
        var text = raw
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let delimiter = guessDelimiter(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text)
        chars.append("\n")
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else if c == "\"" && field.isEmpty {
                inQuotes = true
            } else if c == delimiter {
                row.append(field)
                field = ""
            } else if c == "\n" || c == "\r" || c == "\r\n" {
                if c == "\r", i + 1 < chars.count, chars[i + 1] == "\n" { i += 1 }
                row.append(field)
                field = ""
                if !(row.count == 1 && row[0].trimmingCharacters(in: .whitespaces).isEmpty) {
                    rows.append(row.map { $0.trimmingCharacters(in: .whitespaces) })
                }
                row = []
            } else {
                field.append(c)
            }
            i += 1
        }
        guard let first = rows.first else { return CSVTable(header: [], rows: [], delimiter: delimiter) }
        if looksLikeHeader(first) {
            return CSVTable(header: first, rows: Array(rows.dropFirst()), delimiter: delimiter)
        }
        let names = (1...max(1, first.count)).map { "第 \($0) 列" }
        return CSVTable(header: names, rows: rows, delimiter: delimiter)
    }

    static func guessDelimiter(_ text: String) -> Character {
        let firstLine = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).first.map(String.init) ?? ""
        let counts: [(Character, Int)] = [(",", firstLine.filter { $0 == "," }.count),
                                          (";", firstLine.filter { $0 == ";" }.count),
                                          ("\t", firstLine.filter { $0 == "\t" }.count)]
        return counts.max { $0.1 < $1.1 }.flatMap { $0.1 > 0 ? $0.0 : nil } ?? ","
    }

    static func looksLikeHeader(_ row: [String]) -> Bool {
        let known = ["word", "单词", "词", "meaning", "释义", "中文", "source", "来源", "sentence", "例句",
                     "date", "日期", "known", "认识", "状态", "key", "lemma", "note", "备注"]
        return row.contains { cell in
            let c = cell.lowercased()
            return known.contains { c.contains($0) }
        }
    }

    /// Best guess of which column holds what, from header names.
    func guessColumn(_ names: [String]) -> Int? {
        for (i, h) in header.enumerated() {
            let lower = h.lowercased()
            if names.contains(where: { lower.contains($0) }) { return i }
        }
        return nil
    }

    func cell(_ row: [String], _ column: Int?) -> String {
        guard let column, column >= 0, column < row.count else { return "" }
        return row[column]
    }
}

/// One CSV row after mapping and checking.
struct CSVCandidate: Identifiable, Equatable {
    enum Status: Equatable {
        case ok
        case emptyWord
        case duplicateInFile(firstRow: Int)
        case alreadySaved
        case tooLong
    }

    var id: Int { row }
    var row: Int                // 1-based data row
    var word: String
    var meaning: String
    var sentence: String
    var known: Bool
    var status: Status

    var importable: Bool { status == .ok }
}

enum CSVImportPlan {
    struct Mapping: Equatable {
        var word: Int?
        var meaning: Int?
        var sentence: Int?
        var known: Int?
    }

    /// Checks every row: empty word, repeated in the file, already in the word list, too long.
    static func candidates(_ table: CSVTable, mapping: Mapping, existing: Set<String>) -> [CSVCandidate] {
        var out: [CSVCandidate] = []
        var seen: [String: Int] = [:]
        for (n, row) in table.rows.enumerated() {
            let word = table.cell(row, mapping.word).trimmingCharacters(in: .whitespacesAndNewlines)
            let meaning = table.cell(row, mapping.meaning)
            let sentence = table.cell(row, mapping.sentence)
            let knownCell = table.cell(row, mapping.known).lowercased()
            let known = ["1", "true", "yes", "y", "认识", "known", "是", "√", "✓"].contains(knownCell)
            let norm = SentenceText.normalize(word)
            var status = CSVCandidate.Status.ok
            if norm.isEmpty {
                status = .emptyWord
            } else if norm.count > 60 {
                status = .tooLong
            } else if let first = seen[norm] {
                status = .duplicateInFile(firstRow: first)
            } else if existing.contains(norm) {
                status = .alreadySaved
            }
            if !norm.isEmpty && seen[norm] == nil { seen[norm] = n + 1 }
            out.append(CSVCandidate(row: n + 1, word: word, meaning: meaning, sentence: sentence,
                                    known: known, status: status))
        }
        return out
    }
}
