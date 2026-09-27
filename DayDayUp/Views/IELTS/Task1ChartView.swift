import SwiftUI
import Charts

/// Writing Task 1 figure (IEL-P05): a line graph, bar chart, pie charts, a table or a process
/// diagram, drawn from the original practice data in `IELTSExamBank`.
/// Series never depend on colour alone: lines also differ in symbol and dash, bars and pie
/// sectors carry a letter or number that matches the legend, and the numbers are available as text.
/// "放大看图" opens a larger sheet that zooms with a pinch or with the + / − buttons.
struct Task1ChartView: View {
    let prompt: Task1Prompt

    @State private var showLarge = false
    @State private var showData = false

    init(prompt: Task1Prompt) {
        self.prompt = prompt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Task1Figure(prompt: prompt)
                .padding(12)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
            HStack(alignment: .center, spacing: 12) {
                Label(prompt.source, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button {
                    showLarge = true
                } label: {
                    Label("放大看图", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            if prompt.kind.isChart {
                DisclosureGroup(isExpanded: $showData) {
                    Task1DataGrid(prompt: prompt)
                        .padding(.top, 6)
                } label: {
                    Label("数据文字版", systemImage: "tablecells")
                        .frame(minHeight: 44)
                }
                .font(.callout)
            }
        }
        .sheet(isPresented: $showLarge) {
            Task1ZoomView(prompt: prompt)
                .presentationSizing(.page)
        }
    }
}

// MARK: - Data for Swift Charts

/// One plotted value.
struct Task1Mark: Identifiable {
    let id: String
    let series: String
    let seriesIndex: Int
    let label: String
    let pointIndex: Int
    let value: Double
    let isLast: Bool           // last point of its series (where a line gets its direct label)
}

extension Task1Prompt {
    /// Every value as a flat list, series by series.
    var marks: [Task1Mark] {
        var out: [Task1Mark] = []
        for (si, s) in series.enumerated() {
            for (pi, p) in s.points.enumerated() {
                out.append(Task1Mark(id: "\(si)-\(pi)", series: s.name, seriesIndex: si,
                                     label: p.label, pointIndex: pi, value: p.value,
                                     isLast: pi == s.points.count - 1))
            }
        }
        return out
    }

    func seriesMarks(_ index: Int) -> [Task1Mark] {
        marks.filter { $0.seriesIndex == index }
    }
}

/// Series colours plus a second cue for each series (symbol, dash, letter or number).
/// The colours are a validated categorical order (light / dark steps checked against Theme.paper:
/// adjacent pairs, and the pie wrap-around, clear colour-blind ΔE 8 and normal-vision ΔE 15 in
/// both modes). Fixed order, never cycled; no figure in the bank has more than 6 categories.
/// Text never sits on a coloured fill: labels use ink colours on the surface.
enum Task1Style {
    static let palette: [Color] = [
        Color.adaptive(0x2A78D6, 0x3987E5),   // blue
        Color.adaptive(0xEB6834, 0xD95926),   // orange
        Color.adaptive(0x1BAF7A, 0x199E70),   // aqua
        Color.adaptive(0xEDA100, 0xC98500),   // yellow
        Color.adaptive(0xE87BA4, 0xD55181),   // magenta
        Color.adaptive(0x008300, 0x008300),   // green
        Color.adaptive(0x4A3AA7, 0x9085E9),   // violet
        Color.adaptive(0xE34948, 0xE66767),   // red
    ]

    static func color(_ i: Int) -> Color {
        palette[min(max(i, 0), palette.count - 1)]
    }

    static func stroke(_ i: Int) -> StrokeStyle {
        switch abs(i) % 4 {
        case 0: return StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        case 1: return StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [9, 5])
        case 2: return StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [2, 5])
        default: return StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [12, 4, 2, 4])
        }
    }

    static func symbol(_ i: Int) -> BasicChartSymbolShape {
        switch abs(i) % 4 {
        case 0: return .circle
        case 1: return .square
        case 2: return .triangle
        default: return .diamond
        }
    }

    /// The same shapes as SF Symbols, for the legend.
    static func symbolName(_ i: Int) -> String {
        let names = ["circle.fill", "square.fill", "triangle.fill", "diamond.fill"]
        return names[abs(i) % names.count]
    }

    /// Letter shown above each bar and in the legend.
    static func key(_ i: Int) -> String {
        let letters = ["A", "B", "C", "D", "E", "F", "G", "H"]
        return letters[abs(i) % letters.count]
    }
}

// MARK: - The figure

/// The figure alone at a given chart height. The zoom sheet draws it larger.
struct Task1Figure: View {
    let prompt: Task1Prompt
    var chartHeight: CGFloat = 280

    /// Up to four lines also get their name at the end of the line.
    private var directLabels: Bool { prompt.series.count <= 4 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(prompt.heading)
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            switch prompt.kind {
            case .line:
                lineChart
            case .bar:
                barChart
            case .pie:
                pieCharts
            case .table:
                table
            case .process:
                process
            }
        }
    }

    // MARK: Line

    private var lineChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            axisCaption(prompt.unit)
            Chart(prompt.marks) { m in
                LineMark(
                    x: .value("时间", m.label),
                    y: .value("数值", m.value),
                    series: .value("系列", m.series)
                )
                .foregroundStyle(Task1Style.color(m.seriesIndex))
                .lineStyle(Task1Style.stroke(m.seriesIndex))
                .symbol(Task1Style.symbol(m.seriesIndex))
                .symbolSize(70)
                if m.isLast && directLabels {
                    // Direct label at the end of each line (names in ink, not in the series colour).
                    PointMark(
                        x: .value("时间", m.label),
                        y: .value("数值", m.value)
                    )
                    .symbolSize(0)
                    .annotation(position: .top, spacing: 6,
                                overflowResolution: AnnotationOverflowResolution(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        Text(m.series)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .chartYScale(domain: 0...prompt.axisMax)
            .frame(height: chartHeight)
            axisCaption(prompt.xAxis)
                .frame(maxWidth: .infinity)
            Task1Legend(prompt: prompt)
        }
    }

    // MARK: Bar

    private var barChart: some View {
        let multi = prompt.series.count > 1
        return VStack(alignment: .leading, spacing: 6) {
            axisCaption(prompt.unit)
            Chart(prompt.marks) { m in
                BarMark(
                    x: .value("类别", m.label),
                    y: .value("数值", m.value)
                )
                .foregroundStyle(Task1Style.color(m.seriesIndex))
                .position(by: .value("系列", m.series))
                .annotation(position: .top, spacing: 2) {
                    Text(multi ? Task1Style.key(m.seriesIndex) : "")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .chartYScale(domain: 0...prompt.axisMax)
            .frame(height: chartHeight)
            axisCaption(prompt.xAxis)
                .frame(maxWidth: .infinity)
            Task1Legend(prompt: prompt)
        }
    }

    // MARK: Pie

    private var pieCharts: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Side by side when there is room, otherwise one under the other.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    pies
                }
                VStack(alignment: .center, spacing: 16) {
                    pies
                }
                .frame(maxWidth: .infinity)
            }
            Task1PieLegend(prompt: prompt)
        }
    }

    private var pies: some View {
        ForEach(Array(prompt.series.enumerated()), id: \.offset) { si, s in
            VStack(spacing: 6) {
                Text(s.name)
                    .font(.subheadline.weight(.semibold))
                Chart(prompt.seriesMarks(si)) { m in
                    SectorMark(
                        angle: .value("占比", m.value),
                        innerRadius: .ratio(0.42),
                        angularInset: 1.5
                    )
                    .foregroundStyle(Task1Style.color(m.pointIndex))
                    .annotation(position: .overlay) {
                        // Ink on a small surface chip, readable on every sector colour.
                        Text(pieLabel(m))
                            .font(.caption2.weight(.bold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Theme.paper.opacity(0.9), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .frame(width: chartHeight, height: chartHeight)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Sector number (matches the legend), plus the value when the sector is big enough.
    private func pieLabel(_ m: Task1Mark) -> String {
        let key = "\(m.pointIndex + 1)"
        guard m.value >= 7 else { return key }
        let unit = prompt.unit == "%" ? "%" : ""
        return "\(key)\n\(Task1Prompt.format(m.value))\(unit)"
    }

    // MARK: Table

    private var table: some View {
        let columns = prompt.labels
        return VStack(alignment: .leading, spacing: 6) {
            axisCaption(prompt.unit)
            ScrollView(.horizontal) {
                Grid(alignment: .trailing, horizontalSpacing: 20, verticalSpacing: 10) {
                    GridRow {
                        Text(prompt.xAxis)
                            .fontWeight(.semibold)
                            .gridColumnAlignment(.leading)
                        ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                            Text(column)
                                .fontWeight(.semibold)
                        }
                    }
                    Divider()
                    ForEach(Array(prompt.series.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            Text(row.name)
                                .gridColumnAlignment(.leading)
                            ForEach(Array(row.points.enumerated()), id: \.offset) { _, point in
                                Text(Task1Prompt.format(point.value))
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: Process

    private var process: some View {
        VStack(spacing: 6) {
            ForEach(Array(prompt.steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .center, spacing: 12) {
                    Text("\(i + 1)")
                        .font(.headline.monospacedDigit())
                        .frame(width: 32, height: 32)
                        .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 2))
                    Text(step)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Theme.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.35)))
                .accessibilityElement(children: .combine)
                if i < prompt.steps.count - 1 {
                    Image(systemName: "arrow.down")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func axisCaption(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Legends and data as text

/// Line and bar legend: the line sample with its symbol and dash, or the bar letter.
struct Task1Legend: View {
    let prompt: Task1Prompt

    var body: some View {
        FlowLayout(spacing: 16, lineSpacing: 8) {
            ForEach(Array(prompt.series.enumerated()), id: \.offset) { i, s in
                HStack(spacing: 6) {
                    swatch(i)
                    Text(s.name)
                        .font(.callout)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private func swatch(_ i: Int) -> some View {
        if prompt.kind == .line {
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 7))
                    p.addLine(to: CGPoint(x: 32, y: 7))
                }
                .stroke(Task1Style.color(i), style: Task1Style.stroke(i))
                Image(systemName: Task1Style.symbolName(i))
                    .font(.system(size: 9))
                    .foregroundStyle(Task1Style.color(i))
            }
            .frame(width: 32, height: 14)
            .accessibilityHidden(true)
        } else {
            // Colour square, then the letter shown above this series' bars.
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Task1Style.color(i))
                    .frame(width: 14, height: 14)
                Text(Task1Style.key(i))
                    .font(.callout.weight(.bold))
            }
            .accessibilityHidden(true)
        }
    }
}

/// Pie legend: one row per category, numbered like the sectors, with each pie's value.
struct Task1PieLegend: View {
    let prompt: Task1Prompt

    var body: some View {
        let categories = prompt.labels
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(categories.enumerated()), id: \.offset) { ci, name in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Task1Style.color(ci))
                        .frame(width: 14, height: 14)
                        .accessibilityHidden(true)
                    Text("\(ci + 1)")
                        .font(.callout.weight(.bold).monospacedDigit())
                        .frame(minWidth: 16, alignment: .leading)
                    Text(name)
                        .font(.callout)
                    Spacer(minLength: 8)
                    Text(values(ci))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func values(_ ci: Int) -> String {
        let unit = prompt.unit == "%" ? "%" : ""
        return prompt.series.map { s in
            let v = s.points.indices.contains(ci) ? Task1Prompt.format(s.points[ci].value) + unit : "–"
            return "\(s.name): \(v)"
        }
        .joined(separator: " · ")
    }
}

/// The numbers behind a chart, one row per label (for VoiceOver and for checking values).
struct Task1DataGrid: View {
    let prompt: Task1Prompt

    var body: some View {
        let labels = prompt.labels
        VStack(alignment: .leading, spacing: 6) {
            Text("单位：\(prompt.unit)")
                .foregroundStyle(.secondary)
            Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text(prompt.xAxis.isEmpty ? "类别" : prompt.xAxis)
                        .fontWeight(.semibold)
                        .gridColumnAlignment(.leading)
                    ForEach(Array(prompt.series.enumerated()), id: \.offset) { _, s in
                        Text(s.name)
                            .fontWeight(.semibold)
                    }
                }
                Divider()
                ForEach(Array(labels.enumerated()), id: \.offset) { li, label in
                    GridRow {
                        Text(label)
                            .gridColumnAlignment(.leading)
                        ForEach(Array(prompt.series.enumerated()), id: \.offset) { _, s in
                            Text(s.points.indices.contains(li) ? Task1Prompt.format(s.points[li].value) : "–")
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .font(.callout)
    }
}

// MARK: - Zoom

/// The figure in a large sheet. Pinch or use + / − to zoom; text grows with the figure.
struct Task1ZoomView: View {
    let prompt: Task1Prompt

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var baseTypeSize
    @State private var level = 0

    private static let scales: [CGFloat] = [1, 1.4, 1.8, 2.4]
    private static let typeSteps = [0, 1, 2, 4]

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let scale = Task1ZoomView.scales[min(level, Task1ZoomView.scales.count - 1)]
                let baseWidth = max(300, geo.size.width - 40)
                let baseHeight = max(260, min(geo.size.height - 200, baseWidth * 0.62))
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 12) {
                        Task1Figure(prompt: prompt, chartHeight: baseHeight * scale)
                        Text(prompt.source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .dynamicTypeSize(typeSize)
                    .frame(width: baseWidth * scale, alignment: .topLeading)
                    .padding(20)
                }
                .simultaneousGesture(
                    MagnifyGesture()
                        .onEnded { value in
                            if value.magnification > 1.15 {
                                zoom(1)
                            } else if value.magnification < 0.87 {
                                zoom(-1)
                            }
                        }
                )
            }
            .navigationTitle("Task 1 · \(prompt.kind.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        zoom(-1)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .accessibilityLabel("缩小")
                    .disabled(level == 0)
                    Button {
                        zoom(1)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .accessibilityLabel("放大")
                    .disabled(level >= Task1ZoomView.scales.count - 1)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("双指张开放大、捏合缩小；也可以点右上角的放大镜。现在是第 \(level + 1)/\(Task1ZoomView.scales.count) 级。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(.bar)
            }
        }
    }

    /// Text size follows the zoom, starting from the learner's own text size.
    private var typeSize: DynamicTypeSize {
        let all = DynamicTypeSize.allCases
        let base = all.firstIndex(of: baseTypeSize) ?? 3
        let step = Task1ZoomView.typeSteps[min(level, Task1ZoomView.typeSteps.count - 1)]
        return all[min(all.count - 1, base + step)]
    }

    private func zoom(_ delta: Int) {
        level = max(0, min(Task1ZoomView.scales.count - 1, level + delta))
    }
}
