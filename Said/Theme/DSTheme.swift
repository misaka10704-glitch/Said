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
    /// Connects-compatible neutral palette with Said's own semantic accents.
    static let brandCyan = UIColor(red: 16 / 255, green: 163 / 255, blue: 127 / 255, alpha: 1)
    static let voiceBlue = UIColor(red: 57 / 255, green: 145 / 255, blue: 245 / 255, alpha: 1)
    static let pronounceCoral = UIColor(red: 242 / 255, green: 126 / 255, blue: 98 / 255, alpha: 1)
    static let speakingViolet = UIColor(red: 139 / 255, green: 112 / 255, blue: 232 / 255, alpha: 1)
    static let learningAmber = UIColor(red: 226 / 255, green: 164 / 255, blue: 63 / 255, alpha: 1)
    static let destructiveRed = UIColor(red: 224 / 255, green: 72 / 255, blue: 72 / 255, alpha: 1)

    // Anki answer-button semantics. Keep these stable across appearance modes.
    static let easeAgain = UIColor(red: 218 / 255, green: 72 / 255, blue: 72 / 255, alpha: 1)
    static let easeHard = UIColor(red: 216 / 255, green: 142 / 255, blue: 49 / 255, alpha: 1)
    static let easeGood = UIColor(red: 52 / 255, green: 168 / 255, blue: 102 / 255, alpha: 1)
    static let easeEasy = UIColor(red: 65 / 255, green: 135 / 255, blue: 224 / 255, alpha: 1)

    static let dark = ThemeColors(
        background: UIColor(red: 33 / 255, green: 33 / 255, blue: 33 / 255, alpha: 1),
        sidebarBackground: UIColor(red: 23 / 255, green: 23 / 255, blue: 23 / 255, alpha: 1),
        surface: UIColor(red: 44 / 255, green: 44 / 255, blue: 44 / 255, alpha: 1),
        surfaceHover: UIColor(red: 52 / 255, green: 52 / 255, blue: 52 / 255, alpha: 1),
        border: UIColor(red: 64 / 255, green: 64 / 255, blue: 64 / 255, alpha: 1),
        divider: UIColor(red: 40 / 255, green: 40 / 255, blue: 40 / 255, alpha: 1),
        textPrimary: UIColor(red: 236 / 255, green: 236 / 255, blue: 241 / 255, alpha: 1),
        textSecondary: UIColor(red: 172 / 255, green: 172 / 255, blue: 182 / 255, alpha: 1),
        textTertiary: UIColor(red: 120 / 255, green: 120 / 255, blue: 130 / 255, alpha: 1),
        accent: brandCyan,
        success: easeGood,
        warning: easeHard,
        destructive: destructiveRed,
        inputBackground: UIColor(red: 48 / 255, green: 48 / 255, blue: 52 / 255, alpha: 1),
        inputBorder: UIColor(red: 70 / 255, green: 70 / 255, blue: 76 / 255, alpha: 1),
        navBarStyle: .black,
        statusBarStyle: .lightContent
    )

    static let light = ThemeColors(
        background: .white,
        sidebarBackground: UIColor(red: 247 / 255, green: 247 / 255, blue: 248 / 255, alpha: 1),
        surface: .white,
        surfaceHover: UIColor(red: 236 / 255, green: 236 / 255, blue: 241 / 255, alpha: 1),
        border: UIColor(red: 226 / 255, green: 226 / 255, blue: 232 / 255, alpha: 1),
        divider: UIColor(red: 235 / 255, green: 235 / 255, blue: 240 / 255, alpha: 1),
        textPrimary: UIColor(red: 13 / 255, green: 13 / 255, blue: 13 / 255, alpha: 1),
        textSecondary: UIColor(red: 90 / 255, green: 90 / 255, blue: 98 / 255, alpha: 1),
        textTertiary: UIColor(red: 142 / 255, green: 142 / 255, blue: 150 / 255, alpha: 1),
        accent: brandCyan,
        success: easeGood,
        warning: easeHard,
        destructive: destructiveRed,
        inputBackground: .white,
        inputBorder: UIColor(red: 210 / 255, green: 210 / 255, blue: 218 / 255, alpha: 1),
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
        static let columnWidth: CGFloat = 30
        static let columnSpacing: CGFloat = 2
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
