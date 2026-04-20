import SwiftUI
import AppKit
import ClaudeTokenManagerCore

/// Typography helper. Uses Inter when installed on the system,
/// falls back to the default system font (SF Pro) otherwise.
///
/// Users who want the exact Inter look can install it from:
/// https://rsms.me/inter/
enum AppFont {
    private static let interFamily = "Inter"

    static var isInterAvailable: Bool {
        NSFontManager.shared.availableFontFamilies.contains(interFamily)
    }

    static func inter(size: CGFloat, weight: NSFont.Weight = .regular) -> Font {
        if isInterAvailable {
            let nsFont = NSFont(name: fontName(for: weight), size: size)
                ?? NSFont.systemFont(ofSize: size, weight: weight)
            return Font(nsFont)
        }
        return Font.system(size: size, weight: swiftUIWeight(weight), design: .default)
    }

    private static func fontName(for weight: NSFont.Weight) -> String {
        switch weight {
        case .medium:   return "Inter-Medium"
        case .semibold: return "Inter-SemiBold"
        case .bold:     return "Inter-Bold"
        case .light:    return "Inter-Light"
        default:        return "Inter-Regular"
        }
    }

    private static func swiftUIWeight(_ w: NSFont.Weight) -> Font.Weight {
        switch w {
        case .medium:   return .medium
        case .semibold: return .semibold
        case .bold:     return .bold
        case .light:    return .light
        default:        return .regular
        }
    }
}
