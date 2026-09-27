import SwiftUI

/// "报错" for one sentence: the translation, analysis, word card or audio looks wrong.
/// Reports stay on the iPad and go out with the diagnostic log, so the content packs can be fixed.
struct ReportSheet: View {
    let articleKey: String
    let sid: Int
    let sentence: String
    var onSaved: () -> Void

    @Environment(PracticeStore.self) private var practice
    @Environment(\.dismiss) private var dismiss
    @State private var kind = "翻译"
    @State private var note = ""

    static let kinds = ["翻译", "句子解析", "单词卡", "音频对不上", "其他"]

    var body: some View {
        NavigationStack {
            Form {
                Section("这一句") {
                    Text(sentence)
                        .font(Font.system(.body, design: .serif))
                }
                Section("哪里不对") {
                    Picker("类型", selection: $kind) {
                        ForEach(ReportSheet.kinds, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField("说明（可以不写）", text: $note, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section {
                    Text("报错只存在这台 iPad 上。导出诊断日志时会一起带上，用来修正内容包。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("报错")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("提交") {
                        let report = ContentReport(id: UUID().uuidString, created: Date(), article: articleKey,
                                                   sid: sid, kind: kind,
                                                   note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                                                   text: sentence)
                        practice.addReport(report)
                        DiagLog.shared.log("report", "\(articleKey)#\(sid) \(kind)")
                        onSaved()
                        dismiss()
                    }
                }
            }
        }
    }
}
