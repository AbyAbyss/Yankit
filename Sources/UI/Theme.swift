import AppKit
import SwiftUI

/// Yankit's fixed colors. The user-chosen accent is `AppAccent`; everything
/// else uses the system's semantic colors.
enum Theme {
    /// Labels and sensitive-item highlights.
    static let amber = Color(light: NSColor(hex: "#9A5B00"), dark: NSColor(hex: "#FFC062"))

    /// The colors a category can take, in picker order.
    static let categoryColors: [(name: String, hex: String)] = [
        ("Lime", "#D4FF4F"), ("Blue", "#7AB0FF"), ("Pink", "#FF8AD0"),
        ("Amber", "#FFC062"), ("Teal", "#6FE3C6"), ("Coral", "#FF8A80"),
    ]
}

extension AppAccent {
    /// Fills selected chips and primary buttons. `onFill` text sits on it.
    var fill: Color {
        switch self {
        case .lime: Color(hex: "#D4FF4F")
        case .blue: Color(hex: "#8AB8FF")
        case .purple: Color(hex: "#C9A2FF")
        case .orange: Color(hex: "#FFB066")
        case .pink: Color(hex: "#FF9AD5")
        case .system: Color.accentColor
        }
    }

    /// Text drawn on `fill`.
    var onFill: Color {
        switch self {
        case .lime: Color(hex: "#111111")
        case .blue: Color(hex: "#0B1A33")
        case .purple: Color(hex: "#1E0B33")
        case .orange: Color(hex: "#2B1500")
        case .pink: Color(hex: "#33081F")
        case .system: Color.white
        }
    }

    /// Strokes, rings, and icons on the panel background. Darker in light
    /// mode so it keeps enough contrast on a light background.
    var tint: Color {
        switch self {
        case .lime: Color(light: NSColor(hex: "#5E7D00"), dark: NSColor(hex: "#D4FF4F"))
        case .blue: Color(light: NSColor(hex: "#1F5FD1"), dark: NSColor(hex: "#8AB8FF"))
        case .purple: Color(light: NSColor(hex: "#7A3FD6"), dark: NSColor(hex: "#C9A2FF"))
        case .orange: Color(light: NSColor(hex: "#B85A00"), dark: NSColor(hex: "#FFB066"))
        case .pink: Color(light: NSColor(hex: "#C0307D"), dark: NSColor(hex: "#FF9AD5"))
        case .system: Color.accentColor
        }
    }
}

private struct AccentKey: EnvironmentKey {
    static let defaultValue: AppAccent = .lime
}

extension EnvironmentValues {
    /// The user's accent, set by the panel and the Settings window.
    var accent: AppAccent {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
}

extension Color {
    /// A color that resolves to `light` or `dark` with the view's appearance.
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    /// A color from a `#RRGGBB` string.
    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex))
    }
}

extension NSColor {
    /// A color from a `#RRGGBB` or `#RGB` string; black if it doesn't parse.
    convenience init(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        let value = UInt32(digits, radix: 16) ?? 0
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
