import SwiftUI

/// MET-06 问题复发: points the learner did not tick in their own self-checks (at least twice), always with
/// the denominator. A point can be withdrawn ("撤回") and restored ("恢复").
struct ProgressIssuesCard: View {
    let window: Int
    @Environment(StudyStore.self) private var study
    @Environment(PracticeStore.self) private var practice

    var body: some View {
        let since = ProgressFormat.windowStart(days: window)
        let withdrawn = study.state.retractedIssues
        let active = Metrics.issues(practice: practice.state, since: since, retracted: Set(withdrawn))
        let everything = Metrics.issues(practice: practice.state, since: since, retracted: [])
        ProgressCard("问题复发（最近 \(window) 天）", symbol: "exclamationmark.bubble",
                     footnote: "只列出至少两次没勾的点；分母是做过这一项自评的次数。次数多不等于退步，要和分母一起看。") {
            if active.isEmpty {
                Text("这段时间没有至少两次没勾的点。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(active) { stat in
                    ProgressIssueRow(stat: stat)
                    if stat.id != active.last?.id {
                        Divider()
                    }
                }
            }
            if !withdrawn.isEmpty {
                Divider()
                ProgressDisclosure("已撤回（\(withdrawn.count)）") {
                    ForEach(withdrawn, id: \.self) { id in
                        ProgressRetractedRow(id: id, stat: everything.first(where: { $0.id == id }))
                    }
                }
            }
        }
    }
}

private struct ProgressIssueRow: View {
    let stat: Metrics.IssueStat
    @Environment(StudyStore.self) private var study
    @Environment(PracticeStore.self) private var practice

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(IssueText.title(kind: stat.kind, dim: stat.dim, question: stat.question) + "：")
                    .font(.body.weight(.semibold))
                Spacer(minLength: 8)
                Button {
                    study.retractIssue(stat.id, true)
                } label: {
                    Label("撤回", systemImage: "arrow.uturn.backward")
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
            Text(countText)
                .font(.callout)
                .monospacedDigit()
            if stat.checks < Metrics.smallSample {
                SmallSampleTag("样本少（分母 \(stat.checks) 次）")
            }
            ForEach(otherWordings, id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let note = evidence {
                Text("你记下的证据（最近一次）：" + note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var countText: String {
        var s = "\(stat.checks) 次自评里 \(stat.misses) 次没勾"
        if let latest = sampleDates.max() {
            s += "（最近：" + ProgressFormat.short(latest) + "）"
        }
        return s
    }

    /// When the self-checks that missed this point were made.
    private var sampleDates: [Date] {
        var out: [Date] = []
        for id in Set(stat.samples) {
            if stat.kind == "writing" {
                if let w = practice.writing(id) {
                    out += w.versions.filter { $0.check != nil }.map { $0.finished ?? $0.started }
                }
            } else if let w = practice.speaking(id) {
                out.append(w.created)
            }
        }
        return out
    }

    /// The learner's own evidence note for this dimension, from the newest sample.
    private var evidence: String? {
        guard let id = stat.samples.first else { return nil }
        var check: SelfCheck?
        if stat.kind == "writing" {
            check = practice.writing(id)?.versions.last(where: { $0.check != nil })?.check
        } else {
            check = practice.speaking(id)?.check
        }
        let note = check?.dims.first(where: { $0.id == stat.dim })?.note ?? ""
        let clean = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    /// Basic and exam templates share ids but not always the words: name the other wordings that were used.
    private var otherWordings: [String] {
        let primary = IssueText.text(kind: stat.kind, dim: stat.dim, question: stat.question)
        var templates: [String] = []
        for id in stat.samples {
            var t: String?
            if stat.kind == "writing" {
                t = practice.writing(id).map { IssueText.template(writing: $0) }
            } else {
                t = practice.speaking(id).map { IssueText.template(speaking: $0) }
            }
            if let t, !templates.contains(t) {
                templates.append(t)
            }
        }
        var out: [String] = []
        for t in templates {
            if let words = IssueText.wording(template: t, dim: stat.dim, question: stat.question), words != primary {
                out.append("同一项在" + IssueText.templateName(t) + "里是：" + words)
            }
        }
        return out
    }
}

private struct ProgressRetractedRow: View {
    let id: String
    let stat: Metrics.IssueStat?
    @Environment(StudyStore.self) private var study

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                study.retractIssue(id, false)
            } label: {
                Label("恢复", systemImage: "arrow.uturn.forward")
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
    }

    private var title: String {
        guard let p = IssueText.parse(id) else { return id }
        return IssueText.title(kind: p.kind, dim: p.dim, question: p.question)
    }

    private var detail: String {
        guard let stat else { return "这段时间没勾的次数少于 2 次" }
        return "\(stat.checks) 次自评里 \(stat.misses) 次没勾"
    }
}
