import SwiftUI
import UIKit

// Colours from ui/Theme.kt. Each one switches with light / dark mode.

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) { self.init(uiColor: UIColor(hex: hex, alpha: alpha)) }

    /// A colour with a light and a dark value.
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

enum Palette {
    static let primary = Color.dynamic(0x5B57F2, 0x8D8AFF)
    static let onPrimary = Color.dynamic(0xFFFFFF, 0x16134A)
    static let primaryContainer = Color.dynamic(0xECEBFF, 0x2B2967)
    static let onPrimaryContainer = Color.dynamic(0x2A2690, 0xE2E1FF)
    static let secondaryContainer = Color.dynamic(0xEEEFF5, 0x25262E)
    static let onSecondaryContainer = Color.dynamic(0x2A2C38, 0xE6E7EE)
    static let background = Color.dynamic(0xF5F6FA, 0x0C0D11)
    static let onBackground = Color.dynamic(0x15161C, 0xEDEEF3)
    static let card = Color.dynamic(0xFFFFFF, 0x16171C)
    static let cardHigh = Color.dynamic(0xFFFFFF, 0x1C1D23)
    static let surfaceVariant = Color.dynamic(0xEEEFF5, 0x1F2027)
    static let onSurfaceVariant = Color.dynamic(0x6B6E80, 0x9A9DAD)
    static let outline = Color.dynamic(0xD9DBE5, 0x34353F)
    static let outlineVariant = Color.dynamic(0xE9EAF1, 0x24252D)
    static let error = Color.dynamic(0xE5484D, 0xFF6B70)
    static let errorContainer = Color.dynamic(0xFFE5E6, 0x4A1518)
    static let onErrorContainer = Color.dynamic(0x8A1C20, 0xFFD9DA)

    static let success = Color.dynamic(0x1DB37A, 0x34D399)
    static let warning = Color.dynamic(0xF2A10C, 0xFBBF24)
    static let danger = Color.dynamic(0xE5484D, 0xFF6B70)
    static let field = Color.dynamic(0xF3F4F8, 0x1F2027)
    static let hairline = Color.dynamic(0xECEDF3, 0x23242B)
    static let textMuted = Color.dynamic(0x8E91A2, 0x6E7182)

}

/// Corner radii (AppShapes).
enum Radius {
    static let extraSmall: CGFloat = 8
    static let small: CGFloat = 12
    static let medium: CGFloat = 16
    static let large: CGFloat = 22
    static let extraLarge: CGFloat = 28
}

/// The app's own text size setting (設定 → 字體大小): 1, 1.12 or 1.25.
private struct TextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var textScale: CGFloat {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

/// Text at [size] points, multiplied by the system text size and then by the app's setting
/// (Android: sp × system font scale × FontSize.scale).
private struct AppFont: ViewModifier {
    @Environment(\.textScale) private var scale
    @Environment(\.dynamicTypeSize) private var typeSize
    let size: CGFloat
    let weight: Font.Weight

    func body(content: Content) -> some View {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))
        content.font(.system(size: UIFontMetrics.default.scaledValue(for: size, compatibleWith: traits) * scale, weight: weight))
    }
}

extension View {
    /// The font for text: follows the system text size and the app's 字體大小 setting. Icons keep `.font(.system(size:))`.
    func appFont(size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(AppFont(size: size, weight: weight))
    }

    /// Numbers line up in lists (Android's "tnum").
    func tnum() -> some View { monospacedDigit() }

    /// On an iPad, content stays a comfortable column in the middle instead of stretching edge to edge.
    func readableWidth() -> some View { frame(maxWidth: 700).frame(maxWidth: .infinity) }

    /// A white rounded card on the grey background.
    func cardStyle(radius: CGFloat = Radius.medium, padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Palette.card))
    }
}
