import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Color {
    /// A colour with separate light and dark values (follows the system appearance).
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        adaptive(light, dark, highLight: light, highDark: dark)
    }

    /// Light and dark values, plus stronger ones for 增强对比度 (Increase Contrast, colorSchemeContrast == .increased).
    static func adaptive(_ light: UInt32, _ dark: UInt32, highLight: UInt32, highDark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let high = traits.accessibilityContrast == .high
            if traits.userInterfaceStyle == .dark {
                return UIColor(hex: high ? highDark : dark)
            }
            return UIColor(hex: high ? highLight : light)
        })
    }
}

/// Colours carried over from the web reader, with dark-mode pairs and Increase Contrast values (PLAT-08).
/// Contrast (WCAG) checked on white, paper and chip in light mode and on black, paper and grey in dark mode:
/// - text colours (level5…8, warn, accent) ≥ 4.6:1 on chip and ≥ 5.4:1 on white; ≥ 7:1 with Increase Contrast;
///   white text on them (light) and black text on them (dark, see `onFill`) ≥ 5.4:1;
/// - highlight backgrounds keep primary text ≥ 6.3:1 and get more distinct from the page with Increase Contrast.
enum Theme {
    static let level5 = Color.adaptive(0x0C756B, 0x3CC7B6, highLight: 0x09574F, highDark: 0x4ACBBB)
    static let level6 = Color.adaptive(0x2163D6, 0x6A9CFF, highLight: 0x194AA1, highDark: 0x95B9FF)
    static let level7 = Color.adaptive(0x8A3FD6, 0xB98CFF, highLight: 0x6B26B2, highDark: 0xCAA8FF)
    static let level8 = Color.adaptive(0xB54516, 0xFF8A57, highLight: 0x873410, highDark: 0xFFA178)
    static let warn = Color.adaptive(0x9A5B00, 0xE7B04A, highLight: 0x6E4400, highDark: 0xF5CB78)
    static let sentence = Color.adaptive(0xFFF0C2, 0x3A321C, highLight: 0xFFE08A, highDark: 0x524522)
    static let currentWord = Color.adaptive(0xFFD978, 0x7A5A14, highLight: 0xFFC23D, highDark: 0x6E500E)
    static let selectedWord = Color.adaptive(0xD9EBFF, 0x1F3A57, highLight: 0xB5D6FF, highDark: 0x284B72)
    static let starred = Color.adaptive(0xFFE3C4, 0x4A3320, highLight: 0xFFCF9C, highDark: 0x5E4127)
    static let chunkSelection = Color.adaptive(0xCFF3EC, 0x1D423C, highLight: 0xA3E6D9, highDark: 0x25574F)
    static let accent = Color.adaptive(0x1F5F8B, 0x6FB0E0, highLight: 0x1B5278, highDark: 0x8ABFE6)
    static let chip = Color.adaptive(0xF0ECE4, 0x23272D, highLight: 0xE3DDD0, highDark: 0x30353D)
    static let paper = Color.adaptive(0xFFFDF8, 0x191C20, highLight: 0xFFFFFF, highDark: 0x000000)
    /// Text on a filled Theme colour: white on the darker light-mode fills, black on the lighter dark-mode fills.
    static let onFill = Color.adaptive(0xFFFFFF, 0x000000)

    static func level(_ band: Int) -> Color {
        switch band {
        case 5: return level5
        case 6: return level6
        case 7: return level7
        default: return level8
        }
    }

    // MARK: Reading text (UI-P01, SYS-P03)

    /// The English reading size the learner chose (18…34 pt, default 24), scaled the way body text scales with the
    /// system text size (Dynamic Type). Views pass their `@Environment(\.dynamicTypeSize)`, so they redraw when the
    /// system size changes.
    static func readingPointSize(_ base: Double, typeSize: DynamicTypeSize) -> CGFloat {
        let points = CGFloat(ReaderSettings.clampedFontSize(base))
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))
        return UIFontMetrics(forTextStyle: .body).scaledValue(for: points, compatibleWith: traits).rounded()
    }

    /// Serif reading font at a point size from `readingPointSize`.
    static func readingFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight, design: .serif)
    }

    /// Line spacing that grows with the reading size.
    static func readingLineSpacing(_ size: CGFloat) -> CGFloat {
        max(4, (size * 0.3).rounded())
    }
}

/// A row at normal text sizes that becomes a column at accessibility text sizes, so long labels wrap
/// instead of being cut off (ACC-24: 最大字号无截断).
struct AdaptiveStack<Content: View>: View {
    var spacing: CGFloat?
    var rowAlignment: VerticalAlignment
    var columnAlignment: HorizontalAlignment
    var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    init(spacing: CGFloat? = nil, rowAlignment: VerticalAlignment = .center,
         columnAlignment: HorizontalAlignment = .leading, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.rowAlignment = rowAlignment
        self.columnAlignment = columnAlignment
        self.content = content()
    }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: columnAlignment, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: rowAlignment, spacing: spacing))
        layout {
            content
        }
    }
}

/// Keeps a long excerpt to a few lines at normal text sizes; at accessibility text sizes the whole text shows,
/// so nothing is cut off (ACC-24). Key labels should have no line limit at all.
struct ExcerptLineLimit: ViewModifier {
    let lines: Int?
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content.lineLimit(typeSize.isAccessibilitySize ? nil : lines)
    }
}

extension View {
    func excerptLineLimit(_ lines: Int?) -> some View {
        modifier(ExcerptLineLimit(lines: lines))
    }
}

/// A segmented picker that becomes a menu picker at accessibility text sizes, where segments would cut their
/// labels short.
struct ChoicePicker<SelectionValue: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: SelectionValue
    var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ title: String, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
        self.title = title
        self._selection = selection
        self.content = content()
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            Picker(title, selection: $selection) {
                content
            }
            .pickerStyle(.menu)
        } else {
            Picker(title, selection: $selection) {
                content
            }
            .pickerStyle(.segmented)
        }
    }
}

/// Wraps its children onto new lines, like inline text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: maxWidth.isFinite ? maxWidth : nil, height: nil))
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: maxWidth.isFinite ? min(widest, maxWidth) : widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Small rounded label. Filled badges use `Theme.onFill` for their text, so it stays readable in both themes.
struct Badge: View {
    let text: String
    var color: Color? = nil
    var outlined = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color == nil || outlined ? AnyShapeStyle(color ?? Color.secondary) : AnyShapeStyle(Theme.onFill))
            .background {
                if outlined {
                    Capsule().strokeBorder(color ?? .secondary, lineWidth: 1)
                } else {
                    Capsule().fill(color ?? Theme.chip)
                }
            }
    }
}

/// Progress ring used for 听 / 读 / 跟. Its size follows the text size, so the letter always fits.
struct ProgressRing: View {
    let label: String
    let value: Double          // 0...1
    var tint: Color = Theme.accent
    var disabled = false
    @ScaledMetric(relativeTo: .caption2) private var size: CGFloat = 30

    init(label: String, value: Double, tint: Color = Theme.accent, disabled: Bool = false) {
        self.label = label
        self.value = value
        self.tint = tint
        self.disabled = disabled
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 3)
            Circle()
                .trim(from: 0, to: disabled ? 0 : max(0, min(1, value)))
                .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(disabled ? .tertiary : .secondary)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(disabled ? "\(label)：还没开放" : "\(label)：\(Int((value * 100).rounded()))%")
    }
}

func formatTime(_ t: Double) -> String {
    let s = max(0, Int(t.isFinite ? t : 0))
    return String(format: "%d:%02d", s / 60, s % 60)
}

/// Spoken time for VoiceOver: "1 分 05 秒" / "12 秒".
func spokenTime(_ t: Double) -> String {
    let s = max(0, Int(t.isFinite ? t : 0))
    if s < 60 { return "\(s) 秒" }
    return "\(s / 60) 分 \(s % 60) 秒"
}
