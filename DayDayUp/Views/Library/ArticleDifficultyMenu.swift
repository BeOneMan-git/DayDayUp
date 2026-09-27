import SwiftUI

/// 我的难度 (IMP-F07): the learner's own 1–5 rating, used when picking material. The current rating has a
/// checkmark; tapping it again, or 清除, goes back to "未评". Place it inside a Menu or a context menu.
struct ArticleDifficultyMenu: View {
    @Environment(StudyStore.self) private var study
    let ref: ArticleRef

    var body: some View {
        ForEach(ArticleDifficultyText.levels, id: \.self) { n in
            Toggle(ArticleDifficultyText.option(n), isOn: level(n))
        }
        Divider()
        Button {
            study.setDifficulty(ref, nil)
        } label: {
            Label("清除（改回未评）", systemImage: "xmark.circle")
        }
        .disabled(study.difficulty(ref) == nil)
    }

    private func level(_ n: Int) -> Binding<Bool> {
        Binding(
            get: { study.difficulty(ref) == n },
            set: { on in study.setDifficulty(ref, on ? n : nil) }
        )
    }
}
