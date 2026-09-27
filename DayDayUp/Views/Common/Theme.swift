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
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

/// Colours carried over from the web reader, with dark-mode pairs.
enum Theme {
    static let level5 = Color.adaptive(0x10988A, 0x3CC7B6)
    static let level6 = Color.adaptive(0x2F6FDF, 0x6A9CFF)
    static let level7 = Color.adaptive(0x8A3FD6, 0xB98CFF)
    static let level8 = Color.adaptive(0xE0561B, 0xFF8A57)
    static let warn = Color.adaptive(0xC7851A, 0xE7B04A)
    static let sentence = Color.adaptive(0xFFF0C2, 0x3A321C)
    static let currentWord = Color.adaptive(0xFFD978, 0x7A5A14)
    static let selectedWord = Color.adaptive(0xD9EBFF, 0x1F3A57)
    static let starred = Color.adaptive(0xFFE3C4, 0x4A3320)
    static let chunkSelection = Color.adaptive(0xCFF3EC, 0x1D423C)
    static let accent = Color.adaptive(0x1F5F8B, 0x6FB0E0)
    static let chip = Color.adaptive(0xF0ECE4, 0x23272D)
    static let paper = Color.adaptive(0xFFFDF8, 0x191C20)

    static func level(_ band: Int) -> Color {
        switch band {
        case 5: return level5
        case 6: return level6
        case 7: return level7
        default: return level8
        }
    }

    /// Reading text size steps; each follows Dynamic Type.
    static func bodyStyle(_ step: Int) -> Font.TextStyle {
        switch step {
        case 0: return .body
        case 2: return .title2
        case 3: return .title
        default: return .title3
        }
    }

    static let fontStepNames = ["小", "中", "大", "特大"]

    static func readingFont(_ step: Int) -> Font {
        .system(bodyStyle(step), design: .serif)
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

/// Small rounded label.
struct Badge: View {
    let text: String
    var color: Color? = nil
    var outlined = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color == nil || outlined ? AnyShapeStyle(color ?? Color.secondary) : AnyShapeStyle(Color.white))
            .background {
                if outlined {
                    Capsule().strokeBorder(color ?? .secondary, lineWidth: 1)
                } else {
                    Capsule().fill(color ?? Theme.chip)
                }
            }
    }
}

/// Progress ring used for 听 / 读 / 跟.
struct ProgressRing: View {
    let label: String
    let value: Double          // 0...1
    var tint: Color = Theme.accent
    var disabled = false

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
        .frame(width: 30, height: 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(disabled ? "\(label)：还没开放" : "\(label)：\(Int((value * 100).rounded()))%")
    }
}

func formatTime(_ t: Double) -> String {
    let s = max(0, Int(t.isFinite ? t : 0))
    return String(format: "%d:%02d", s / 60, s % 60)
}
