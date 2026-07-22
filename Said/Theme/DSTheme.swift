import UIKit

enum AppearanceMode: String, CaseIterable {
    case light
    case dark

    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

struct ThemeColors {
    let background: UIColor
    let sidebarBackground: UIColor
    let surface: UIColor
    let surfaceHover: UIColor
    let border: UIColor
    let divider: UIColor
    let textPrimary: UIColor
    let textSecondary: UIColor
    let textTertiary: UIColor
    let accent: UIColor
    let success: UIColor
    let warning: UIColor
    let destructive: UIColor
    let inputBackground: UIColor
    let inputBorder: UIColor
    let navBarStyle: UIBarStyle
    let statusBarStyle: UIStatusBarStyle
}

extension Notification.Name {
    static let saidThemeDidChange = Notification.Name("SaidThemeDidChange")
}

final class ThemeManager {
    static let shared = ThemeManager()
    private let storageKey = "said_appearance_mode"
    private let interfaceScaleKey = "said_interface_scale"

    private init() {}

    var mode: AppearanceMode {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: storageKey),
                  let mode = AppearanceMode(rawValue: rawValue) else {
                return .dark
            }
            return mode
        }
        set {
            guard mode != newValue else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
            NotificationCenter.default.post(name: .saidThemeDidChange, object: nil)
        }
    }

    var colors: ThemeColors {
        mode == .light ? DSTheme.light : DSTheme.dark
    }

    var interfaceScale: CGFloat {
        get {
            let value = UserDefaults.standard.object(forKey: interfaceScaleKey) as? Double ?? 1
            return CGFloat(min(1.3, max(0.85, value)))
        }
        set {
            let value = Double(min(1.3, max(0.85, newValue)))
            UserDefaults.standard.set(value, forKey: interfaceScaleKey)
            NotificationCenter.default.post(name: .saidThemeDidChange, object: nil)
        }
    }
}

enum DSTheme {
    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
    }

    /// Connects-compatible neutral palette with Said's own semantic accents.
    static let brandCyan = rgb(16, 163, 127)
    static let voiceBlue = rgb(57, 145, 245)
    static let pronounceCoral = rgb(242, 126, 98)
    static let speakingViolet = rgb(139, 112, 232)
    static let learningAmber = rgb(226, 164, 63)
    static let destructiveRed = rgb(224, 72, 72)

    // Anki answer-button semantics. Keep these stable across appearance modes.
    static let easeAgain = rgb(218, 72, 72)
    static let easeHard = rgb(216, 142, 49)
    static let easeGood = rgb(52, 168, 102)
    static let easeEasy = rgb(65, 135, 224)

    static let dark = ThemeColors(
        background: rgb(33, 33, 33),
        sidebarBackground: rgb(23, 23, 23),
        surface: rgb(44, 44, 44),
        surfaceHover: rgb(52, 52, 52),
        border: rgb(64, 64, 64),
        divider: rgb(40, 40, 40),
        textPrimary: rgb(236, 236, 241),
        textSecondary: rgb(172, 172, 182),
        textTertiary: rgb(120, 120, 130),
        accent: brandCyan,
        success: easeGood,
        warning: easeHard,
        destructive: destructiveRed,
        inputBackground: rgb(48, 48, 52),
        inputBorder: rgb(70, 70, 76),
        navBarStyle: .black,
        statusBarStyle: .lightContent
    )

    static let light = ThemeColors(
        background: .white,
        sidebarBackground: rgb(247, 247, 248),
        surface: .white,
        surfaceHover: rgb(236, 236, 241),
        border: rgb(226, 226, 232),
        divider: rgb(235, 235, 240),
        textPrimary: rgb(13, 13, 13),
        textSecondary: rgb(90, 90, 98),
        textTertiary: rgb(142, 142, 150),
        accent: brandCyan,
        success: easeGood,
        warning: easeHard,
        destructive: destructiveRed,
        inputBackground: .white,
        inputBorder: rgb(210, 210, 218),
        navBarStyle: .default,
        statusBarStyle: .default
    )

    static var c: ThemeColors { ThemeManager.shared.colors }

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum List {
        static let rowHeight: CGFloat = 44
        static let compactRowHeight: CGFloat = 36
        static let horizontalInset: CGFloat = 16
        static let sectionSpacing: CGFloat = 12
        static var separatorHeight: CGFloat { 1 / UIScreen.main.scale }
    }

    enum DeckCounts {
        static let columnWidth: CGFloat = 38
        static let columnSpacing: CGFloat = 8
        /// Space reserved for the row "more" control so header counts line up.
        /// Matches: more trailing(12) + more width(36) + gap(2).
        static let trailingReserved: CGFloat = 50
        static let leadingInset: CGFloat = 16
    }

    enum Form {
        static let controlHeight: CGFloat = 44
        static let compactControlHeight: CGFloat = 36
        static let cornerRadius: CGFloat = 10
        static let fieldHorizontalInset: CGFloat = 12
        static let cardInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        static let rowSpacing: CGFloat = 12
    }

    static let sidebarWidth: CGFloat = 268
    static let compactBreakpoint: CGFloat = 520
    static let contentMaxWidth: CGFloat = 720
    static let contentPadding = Spacing.lg
    static let cornerRadius: CGFloat = 14
    static let rowHeight = List.rowHeight

    static func bodyFont(size: CGFloat = 16) -> UIFont {
        UIFont.systemFont(ofSize: size * ThemeManager.shared.interfaceScale)
    }

    static func titleFont(size: CGFloat = 16) -> UIFont {
        UIFont.systemFont(ofSize: size * ThemeManager.shared.interfaceScale, weight: .medium)
    }

    static func monoFont(size: CGFloat = 14) -> UIFont {
        UIFont(name: "Menlo-Regular", size: size * ThemeManager.shared.interfaceScale)
            ?? UIFont.monospacedDigitSystemFont(ofSize: size * ThemeManager.shared.interfaceScale, weight: .regular)
    }

    static func practiceAccent(deckName: String) -> UIColor {
        let value = deckName.lowercased()
        if value.contains("pronounce") || value.contains("phon") || value.contains("发音") {
            return pronounceCoral
        }
        if value.contains("ielts") || value.contains("speaking") || value.contains("口语") {
            return speakingViolet
        }
        return voiceBlue
    }

    static func tintedSurface(_ color: UIColor, alpha: CGFloat = 0.14) -> UIColor {
        color.withAlphaComponent(alpha)
    }

    static func makeActivityIndicator() -> UIActivityIndicatorView {
        if #available(iOS 13.0, *) {
            return UIActivityIndicatorView(style: .medium)
        }
        return UIActivityIndicatorView(style: .gray)
    }
}

protocol ThemeRefreshable: AnyObject {
    func applyTheme()
}
