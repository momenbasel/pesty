import SwiftUI

enum Theme {
    static let cardWidth: CGFloat = 215
    static let cardSpacing: CGFloat = 12
    static let cornerRadius: CGFloat = 16
    static let cardCorner: CGFloat = 13
    static let headerHeight: CGFloat = 54

    static let panelTint = Color.black.opacity(0.34)
    static let cardBody = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let cardBorder = Color.white.opacity(0.07)
    static let selection = Color(red: 0.20, green: 0.55, blue: 1.0)

    static let textPrimary = Color.white.opacity(0.95)
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.34)

    static let headerText = Color.white
    static let headerSubText = Color.white.opacity(0.78)

    static let fieldBG = Color.white.opacity(0.09)
    static let pillBG = Color.white.opacity(0.10)
    static let pillSelected = Color.white.opacity(0.18)
}

extension Date {
    var clipRelative: String {
        let secs = -timeIntervalSinceNow
        switch secs {
        case ..<5:        return "Now"
        case ..<60:       return "\(Int(secs))s"
        case ..<3600:     return "\(Int(secs / 60))m"
        case ..<86_400:   return "\(Int(secs / 3600))h"
        case ..<604_800:  return "\(Int(secs / 86_400))d"
        default:
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return f.string(from: self)
        }
    }

    var clipRelativeLong: String {
        let secs = -timeIntervalSinceNow
        if secs < 8 { return "Just now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: self, relativeTo: Date())
    }
}
