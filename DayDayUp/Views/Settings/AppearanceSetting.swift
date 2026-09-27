import SwiftUI
import UIKit

/// UI-P04 主题: 跟随系统 / 浅色 / 深色, stored as ReaderSettings.appearance ("system" / "light" / "dark").
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    /// Unknown or empty stored values mean 跟随系统.
    init(stored value: String) {
        self = AppAppearance(rawValue: value) ?? .system
    }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// The same choice on the app's windows, so sheets, popovers and alerts follow it at once, and
    /// 跟随系统 really hands the choice back to the iPad.
    @MainActor
    static func applyToWindows(_ appearance: AppAppearance) {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = appearance.interfaceStyle
            }
        }
    }
}

/// Applies the stored theme: `.preferredColorScheme` plus the window style (see `applyToWindows`).
struct AppAppearanceModifier: ViewModifier {
    let value: String

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(AppAppearance(stored: value).colorScheme)
            .onAppear {
                AppAppearance.applyToWindows(AppAppearance(stored: value))
            }
            .onChange(of: value) { _, newValue in
                AppAppearance.applyToWindows(AppAppearance(stored: newValue))
            }
    }
}

extension View {
    /// UI-P04: the learner's theme for the whole app ("system" / "light" / "dark"; anything else = system).
    /// Use once, on the root view: `.appAppearance(user.settings.appearance)`.
    func appAppearance(_ value: String) -> some View {
        modifier(AppAppearanceModifier(value: value))
    }
}
